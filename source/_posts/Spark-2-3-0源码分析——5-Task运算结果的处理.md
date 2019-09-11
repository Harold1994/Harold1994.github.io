---
title: Spark-2-3-0源码分析——5-Task运算结果的处理
date: 2018-10-06 17:12:01
tags: [大数据, Spark]
---

#### 一. Task运算结果的处理

TaskRunner将Task的执行状态汇报给Driver后，Driver会转给org.apache.spark.scheduler.TaskSchedulerImpl#statusUpdate。而在这里不同的状态有不同的处理：

1)       如果类型是TaskState.FINISHED，那么调用org.apache.spark.scheduler.TaskResultGetter#enqueueSuccessfulTask进行处理。

<!-- more-->

2)       如果类型是TaskState.FAILED或者TaskState.KILLED或者TaskState.LOST，调用org.apache.spark.scheduler.TaskResultGetter#enqueueFailedTask进行处理。对于TaskState.LOST，还需要将其所在的Executor标记为failed,并且根据更新后的Executor重新调度。

 enqueueSuccessfulTask的逻辑也比较简单，就是如果是IndirectTaskResult，那么需要通过blockid来获取结果：sparkEnv.blockManager.getRemoteBytes(blockId)；如果是DirectTaskResult，那么结果就无需远程获取了。然后调用

1)       org.apache.spark.scheduler.TaskSchedulerImpl#handleSuccessfulTask

2)       org.apache.spark.scheduler.TaskSetManager#handleSuccessfulTask

3)       org.apache.spark.scheduler.DAGScheduler#taskEnded

4)       org.apache.spark.scheduler.DAGScheduler#eventProcessActor

5)       org.apache.spark.scheduler.DAGScheduler#handleTaskCompletion

进行处理。核心逻辑都在第5个调用栈。

如果task是ShuffleMapTask，那么它需要将结果通过某种机制告诉下游的Stage，以便于其可以作为下游Stage的输入。这个机制是怎么实现的？

实际上，对于ShuffleMapTask来说，其结果实际上是org.apache.spark.scheduler.MapStatus；其序列化后存入了DirectTaskResult或者IndirectTaskResult中。而DAGScheduler#handleTaskCompletion通过下面的方式来获取这个结果：

val status=event.result.asInstanceOf[MapStatus]

###### A.org.apache.spark.scheduler.cluster.CoarseGrainedSchedulerBackend.DriverEndpoint#receive

```scala
override def receive: PartialFunction[Any, Unit] = {
      // 接收StatusUpdate发送过来的消息
      case StatusUpdate(executorId, taskId, state, data) =>
        // 调用TaskSchedulerImpl中的statusUpdate方法
        scheduler.statusUpdate(taskId, state, data.value)
        
        // 如果Task的State是FINISHED, FAILED, KILLED, LOST其中一个
        // 就认为该Task结束
        if (TaskState.isFinished(state)) {
          executorDataMap.get(executorId) match {
            case Some(executorInfo) =>
              // 释放资源并重新分配
              executorInfo.freeCores += scheduler.CPUS_PER_TASK
              makeOffers(executorId)
            case None =>
              // Ignoring the update since we don't know about the executor.
              logWarning(s"Ignored task status update ($taskId state $state) " +
                s"from unknown executor with ID $executorId")
          }
        }
```

###### B. org.apache.spark.scheduler.TaskSchedulerImpl#statusUpdate

```scala
def statusUpdate(tid: Long, state: TaskState, serializedData: ByteBuffer) {
  var failedExecutor: Option[String] = None
  var reason: Option[ExecutorLossReason] = None
  synchronized {
    try {
      taskIdToTaskSetManager.get(tid) match {
        case Some(taskSet) =>
          // 如果Task的状态为Lost
          // 移除掉task的Executor
          if (state == TaskState.LOST) {
            // TaskState.LOST is only used by the deprecated Mesos fine-grained scheduling mode,
            // where each executor corresponds to a single task, so mark the executor as failed.
            val execId = taskIdToExecutorId.getOrElse(tid, throw new IllegalStateException(
              "taskIdToTaskSetManager.contains(tid) <=> taskIdToExecutorId.contains(tid)"))
            if (executorIdToRunningTaskIds.contains(execId)) {
              reason = Some(
                SlaveLost(s"Task $tid was lost, so marking the executor as lost as well."))
              removeExecutor(execId, reason.get)
              failedExecutor = Some(execId)
            }
          }

          if (TaskState.isFinished(state)) {
            // 清理本地的数据结构
            cleanupTaskState(tid)
            // 标志任务已结束，注意不一定成功完成
            taskSet.removeRunningTask(tid)
            // 任务成功完成
            if (state == TaskState.FINISHED) {
              // taskResultGetter为线程池，处理执行成功的情况
              taskResultGetter.enqueueSuccessfulTask(taskSet, tid, serializedData)
            } else if (Set(TaskState.FAILED, TaskState.KILLED, TaskState.LOST).contains(state)) {
              // 处理失败任务
              taskResultGetter.enqueueFailedTask(taskSet, tid, state, serializedData)
            }
          }
        case None =>
          logError(
            ("Ignoring update with state %s for TID %s because its task set is gone (this is " +
              "likely the result of receiving duplicate task finished status updates) or its " +
              "executor has been marked as failed.")
              .format(state, tid))
      }
    } catch {
      case e: Exception => logError("Exception in statusUpdate", e)
    }
  }
```

对于Task执行成功的情况，它会调用TaskResultGetter的enqueueSuccessfulTask方法进行处理，处理每次结果都是由一个Daemon线程池负责，默认由四个线程组成，可以通过spark.resultGetter.threads设置。

###### C. org.apache.spark.scheduler.TaskResultGetter#enqueueSuccessfulTask

Executor在将结果回传到Driver时会根据结果的大小设置不同的策略：

* 如果结果大于1G，会直接丢弃这个结果
* 对于“较大”的结果，将其以tid为key存入blockManager，如果结果不大，则直接回传给Driver，这里的回传是直接通过AKKA的消息传递机制。
* 其他的直接通过AKKA回传到Driver

```scala
def enqueueSuccessfulTask(
      taskSetManager: TaskSetManager,
      tid: Long,
      serializedData: ByteBuffer): Unit = {
    // 通过线程池来执行结果获取
    getTaskResultExecutor.execute(new Runnable {
      override def run(): Unit = Utils.logUncaughtExceptions {
        try {
          val (result, size) = serializer.get().deserialize[TaskResult[_]](serializedData) match {
              // 结果是计算结果
            case directResult: DirectTaskResult[_] =>
              // 确定大小符合要求 < 1G
              if (!taskSetManager.canFetchMoreResults(serializedData.limit())) {
                return
              }
              // deserialize "value" without holding any lock so that it won't block other threads.
              // We should call it here, so that when it's called again in
              // "TaskSetManager.handleSuccessfulTask", it does not need to deserialize the value.
              // 反序列化value object
              directResult.value(taskResultSerializer.get())
              (directResult, serializedData.limit())
            // 结果保存在远程Worker节点的BlockManager当中
            case IndirectTaskResult(blockId, size) =>
              // 确定大小符合要求
              if (!taskSetManager.canFetchMoreResults(size)) {
                // dropped by executor if size is larger than maxResultSize
                sparkEnv.blockManager.master.removeBlock(blockId)
                return
              }
              logDebug("Fetching indirect task result for TID %s".format(tid))
              scheduler.handleTaskGettingResult(taskSetManager, tid)
              // 从远程Worker获取结果
              val serializedTaskResult = sparkEnv.blockManager.getRemoteBytes(blockId)
              if (!serializedTaskResult.isDefined) {
                // 如果在Executor的任务执行完成和Driver端去结果之间完全，Executor所在机器出现故障或者其他错误
                // 会导致获取结果失败
                // handleFailedTask会re-runTask，如果没有超过尝试次数
                scheduler.handleFailedTask(
                  taskSetManager, tid, TaskState.FINISHED, TaskResultLost)
                return
              }
              // 反序列化远程获取的结果
              val deserializedResult = serializer.get().deserialize[DirectTaskResult[_]](
                serializedTaskResult.get.toByteBuffer)
              // force deserialization of referenced value
              deserializedResult.value(taskResultSerializer.get())
              // 删除远程结果sparkEnv.blockManager.master.removeBlock(blockId)
              sparkEnv.blockManager.master.removeBlock(blockId)
              (deserializedResult, size)
          }

          // 在从执行程序收到的累加器更新中设置任务结果大小。我们需要在驱动程序上执行此操作，
          // 因为如果我们在执行程序上执行此操作，那么在更新大小后我们将不得不再次序列化结果。
          result.accumUpdates = result.accumUpdates.map { a =>
            if (a.name == Some(InternalAccumulator.RESULT_SIZE)) {
              val acc = a.asInstanceOf[LongAccumulator]
              assert(acc.sum == 0L, "task result size should not have been set on the executors")
              acc.setValue(size.toLong)
              acc
            } else {
              a
            }
          }
          // TaskSchedulerImpl处理获取到的结果
          scheduler.handleSuccessfulTask(taskSetManager, tid, result)
        } catch {
          case cnf: ClassNotFoundException =>
            val loader = Thread.currentThread.getContextClassLoader
            taskSetManager.abort("ClassNotFound with classloader: " + loader)
          // Matching NonFatal so we don't catch the ControlThrowable from the "return" above.
          case NonFatal(ex) =>
            logError("Exception while getting task result", ex)
            taskSetManager.abort("Exception while getting task result: %s".format(ex))
        }
      }
    })
  }
```

###### D. org.apache.spark.scheduler.TaskSchedulerImpl#handleSuccessfulTask

TaskSchedulerImpl中的handleSuccessfulTask方法将最终对计算结果进行处理，具有源码如下：

```scala
def handleSuccessfulTask(
    taskSetManager: TaskSetManager,
    tid: Long,
    taskResult: DirectTaskResult[_]): Unit = synchronized {
    //调用TaskSetManager.handleSuccessfulTask方法进行处理
  taskSetManager.handleSuccessfulTask(tid, taskResult)
}
```

###### E. org.apache.spark.scheduler.TaskSetManager#handleSuccessfulTask

```scala
/**
 * Marks a task as successful and notifies the DAGScheduler that the task has ended.
 */
def handleSuccessfulTask(tid: Long, result: DirectTaskResult[_]): Unit = {
  // 获得TaskInfo
  val info = taskInfos(tid)
  val index = info.index
  // 标记taskfinish
  info.markFinished(TaskState.FINISHED, clock.getTimeMillis())
  // 支持推测
  if (speculationEnabled) {
    successfulTaskDurations.insert(info.duration)
  }
  // 从RunningTask中移除该task
  removeRunningTask(tid)

  // 杀死所有其他与之相同的task的尝试
  for (attemptInfo <- taskAttempts(index) if attemptInfo.running) {
    logInfo(s"Killing attempt ${attemptInfo.attemptNumber} for task ${attemptInfo.id} " +
      s"in stage ${taskSet.id} (TID ${attemptInfo.taskId}) on ${attemptInfo.host} " +
      s"as the attempt ${info.attemptNumber} succeeded on ${info.host}")
    killedByOtherAttempt(index) = true
    sched.backend.killTask(
      attemptInfo.taskId,
      attemptInfo.executorId,
      interruptThread = true,
      reason = "another attempt succeeded")
  }
  if (!successful(index)) {
    // 计数
    tasksSuccessful += 1
    logInfo(s"Finished task ${info.id} in stage ${taskSet.id} (TID ${info.taskId}) in" +
      s" ${info.duration} ms on ${info.host} (executor ${info.executorId})" +
      s" ($tasksSuccessful/$numTasks)")
    // Mark successful and stop if all the tasks have succeeded.
    // 若果有所task成功了，
    // 那么标记successful，并且停止
    successful(index) = true
    if (tasksSuccessful == numTasks) {
      isZombie = true
    }
  } else {
    logInfo("Ignoring task-finished event for " + info.id + " in stage " + taskSet.id +
      " because task " + index + " has already completed successfully")
  }
  // This method is called by "TaskSchedulerImpl.handleSuccessfulTask" which holds the
  // "TaskSchedulerImpl" lock until exiting. To avoid the SPARK-7655 issue, we should not
  // "deserialize" the value when holding a lock to avoid blocking other threads. So we call
  // "result.value()" in "TaskResultGetter.enqueueSuccessfulTask" before reaching here.
  // Note: "result.value()" only deserializes the value when it's called at the first time, so
  // here "result.value()" just returns the value and won't block other threads.
  // 通知dagScheduler该task完成
  sched.dagScheduler.taskEnded(tasks(index), Success, result.value(), result.accumUpdates, info)
  maybeFinishTaskSet()
}
```

###### F.  org.apache.spark.scheduler.DAGScheduler#taskEnded

```scala
 def taskEnded(
      task: Task[_],
      reason: TaskEndReason,
      result: Any,
      accumUpdates: Seq[AccumulatorV2[_, _]],
      taskInfo: TaskInfo): Unit = {
    eventProcessLoop.post(
      // 调用DAGSchedulerEventProcessLoop的post方法将CompletionEvent提交到事件队列中，
      // 交由eventThread进行处理，onReceive方法将处理该事件
      CompletionEvent(task, reason, result, accumUpdates, taskInfo))
  }
```

###### G. org.apache.spark.scheduler.DAGSchedulerEventProcessLoop#doOnReceive

DAGSchedulerEventProcessLoop的doOnReceive会对信号进行监听：

```scala
private def doOnReceive(event: DAGSchedulerEvent): Unit = event match {
  // 处理Job提交事件
  case JobSubmitted(jobId, rdd, func, partitions, callSite, listener, properties) =>
    dagScheduler.handleJobSubmitted(jobId, rdd, func, partitions, callSite, listener, properties)
    ...
  case completion: CompletionEvent =>
    dagScheduler.handleTaskCompletion(completion)
```

###### H. org.apache.spark.scheduler.DAGScheduler#handleTaskCompletion

我们来看下DAGScheduler.handleTaskCompletion 处理失败任务部分的核心代码：

```scala
       //重新提交任务
      case Resubmitted =>
        logInfo("Resubmitted " + task + ", so marking it as still running")
        //把任务加入的等待队列
        stage.pendingPartitions += task.partitionId

      //获取结果失败
      case FetchFailed(bmAddress, shuffleId, mapId, reduceId, failureMessage) =>
        val failedStage = stageIdToStage(task.stageId)
        val mapStage = shuffleIdToMapStage(shuffleId)
        //若失败的尝试ID不是stage尝试ID，
        //则忽略这个失败
        if (failedStage.latestInfo.attemptId != task.stageAttemptId) {
          logInfo(s"Ignoring fetch failure from $task as it's from $failedStage attempt" +
            s" ${task.stageAttemptId} and there is a more recent attempt for that stage " +
            s"(attempt ID ${failedStage.latestInfo.attemptId}) running")
        } else {
          //若失败的Stage还在运行队列，
          //标记这个Stage完成
          if (runningStages.contains(failedStage)) {
            logInfo(s"Marking $failedStage (${failedStage.name}) as failed " +
              s"due to a fetch failure from $mapStage (${mapStage.name})")
            markStageAsFinished(failedStage, Some(failureMessage))
          } else {
            logDebug(s"Received fetch failure from $task, but its from $failedStage which is no " +
              s"longer running")
          }
          //若不允许重试，
          //则停止这个Stage
          if (disallowStageRetryForTest) {
            abortStage(failedStage, "Fetch failure will not retry stage due to testing config",
              None)
          } 
         //若达到最大重试次数，
         //则停止这个Stage
          else if (failedStage.failedOnFetchAndShouldAbort(task.stageAttemptId)) {
            abortStage(failedStage, s"$failedStage (${failedStage.name}) " +
              s"has failed the maximum allowable number of " +
              s"times: ${Stage.MAX_CONSECUTIVE_FETCH_FAILURES}. " +
              s"Most recent failure reason: ${failureMessage}", None)
          } else {
            if (failedStages.isEmpty) {
            //若失败的Stage中，没有个task完成了，
            //则重新提交Stage。
            //若果有完成的task的话，我们不能重新提交Stage，
            //因为有些task已经被调度过了。
            //task级别的重新提交是在TaskSetManager.handleFailedTask进行的
              logInfo(s"Resubmitting $mapStage (${mapStage.name}) and " +
                s"$failedStage (${failedStage.name}) due to fetch failure")
              messageScheduler.schedule(new Runnable {
                override def run(): Unit = eventProcessLoop.post(ResubmitFailedStages)
              }, DAGScheduler.RESUBMIT_TIMEOUT, TimeUnit.MILLISECONDS)
            }
            failedStages += failedStage
            failedStages += mapStage
          }
          // 移除OutputLoc中的数据
          // 取消注册mapOutputTracker
          if (mapId != -1) {
            mapStage.removeOutputLoc(mapId, bmAddress)
            mapOutputTracker.unregisterMapOutput(shuffleId, mapId, bmAddress)
          }

          //当有executor上发生多次获取结果失败，
          //则标记这个executor丢失
          if (bmAddress != null) {
            handleExecutorLost(bmAddress.executorId, filesLost = true, Some(task.epoch))
          }
        }

      //拒绝处理
      case commitDenied: TaskCommitDenied =>
        // 不做任何事,
        //让 TaskScheduler 来决定如何处理

      //异常
      case exceptionFailure: ExceptionFailure =>
        // 更新accumulator
        updateAccumulators(event)

      //task结果丢失
      case TaskResultLost =>
      // 不做任何事,
      // 让 TaskScheduler 处理这些错误和重新提交任务

     // executor 丢失
     // 任务被杀死
     // 未知错误
      case _: ExecutorLostFailure | TaskKilled | UnknownReason =>
        // 不做任何事,
        // 若这task不断的错误，
        // TaskScheduler 会停止 job
```



