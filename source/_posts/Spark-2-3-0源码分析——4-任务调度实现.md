---
title: Spark-2-3-0源码分析——4-任务调度实现
date: 2018-10-04 21:55:55
tags: [大数据, Spark]
---

​	本文是Scheduler模块源码分析的第二篇，第一篇主要分析了DAGScheduler，本篇将结合Spark2.3.0的源码继续分析TaskScheduler和SchedulerBackend。

#### 三、任务调度实现

​	每个TaskScheduler都对应一个SchedulerBackend，其中TaskScheduler负责Application的不同Job之间的调度，在Task失败时重试的机制，并且为执行速度慢的Task启动备份的任务。而SchedulerBackend负责与Cluster Master交互，取得该Application分配得到的资源，并将这些资源传给TaskScheduler，由TaskScheduler为Task最终分配计算资源。

<!-- more-->

##### 1. TaskScheduler的创建

TaskScheduler与DAGScheduler都是在SparkContext创建的时候创建的，其中TaskScheduler是通过

SparkContext.createTaskScheduler创建的。

进入到`SparkContext.createTaskScheduler`方法中，该方法中根据master类型，生成不同的TaskScheduler和SchedulerBackend实例。以Standalone模式为例：

```scala
val SPARK_REGEX = """spark://(.*)""".r
// Create a task scheduler based on a given master URL.
// Return a 2-tuple of the scheduler backend and the task scheduler.
private def createTaskScheduler(
      sc: SparkContext,
      master: String,
      deployMode: String): (SchedulerBackend, TaskScheduler) = {
    import SparkMasterRegex._

    // When running locally, don't try to re-execute tasks on failure.
    val MAX_LOCAL_TASK_FAILURES = 1

    master match {
      ...
    case SPARK_REGEX(sparkUrl) =>
        val scheduler = new TaskSchedulerImpl(sc)
        val masterUrls = sparkUrl.split(",").map("spark://" + _)
        val backend = new StandaloneSchedulerBackend(scheduler, sc, masterUrls)
        scheduler.initialize(backend)
        (backend, scheduler)
    ...
```

从上面代码中可以看到，在生成这两个对象后，接下来将backend传入scheduler的初始化方法中进行初始化，`TaskSchedulerImpl.initialize`方法中主要是根据调度模式初始化调度池,有两种调度方式，分别是**FIFO**和**Fair**调度方式。之后会详细介绍。

##### 2.Task的提交

DAGScheduler完成对Stage的划分后，会提交Stage。从这里开始，继续从上一篇文章最后的二.4 DAGScheduler.submitMissingTasks方法开始进行分析。

###### A. org.apache.spark.scheduler.DAGScheduler#submitMissingTasks

这个方法比较长，这里只列举出源代码中的主要逻辑，搞清楚DAGScheduler提交Stage时如何开始对Task的提交的。

```scala
private def submitMissingTasks(stage: Stage, jobId: Int) {
    //取得当前Stage需要计算的partition
    val partitionsToCompute: Seq[Int] = stage.findMissingPartitions() 
    ...
    // 将当前stage存入running状态的stage列表中
    runningStages += stage
    // 判断当前stage是ShuffleMapStage还是ResultStage
    stage match { 
        case s: ShuffleMapStage =>
        outputCommitCoordinator.stageStart(stage = s.id, maxPartitionId = s.numPartitions - 1)
        case s: ResultStage =>
        outputCommitCoordinator.stageStart(
            stage = s.id, maxPartitionId = s.rdd.partitions.length - 1)
    }
    ...
    // 向listenerBus提交StageSubmitted事件
    listenerBus.post(SparkListenerStageSubmitted(stage.latestInfo, properties))
    ...
    // 根据stage的类型获取其中包含的task
    val tasks: Seq[Task[_]] = try {
        stage match {
            // ShuffleMapStage中对应的是ShuffleMapTask
            case stage: ShuffleMapStage =>
            partitionsToCompute.map { id =>
                val locs = taskIdToLocations(id)
                val part = stage.rdd.partitions(id)
                new ShuffleMapTask(stage.id, stage.latestInfo.attemptId,
                                   taskBinary, part, locs, stage.internalAccumulators)
            }
            // ResultStage中对应的是ResultTask
            case stage: ResultStage =>
            val job = stage.activeJob.get
            partitionsToCompute.map { id =>
                val p: Int = stage.partitions(id)
                val part = stage.rdd.partitions(p)
                val locs = taskIdToLocations(id)
                new ResultTask(stage.id, stage.latestInfo.attemptId,
                               taskBinary, part, locs, id, stage.internalAccumulators)
            }
        }
    }
    ...
    if (tasks.size > 0) { // 如果当前Stege中有task
        logInfo("Submitting " + tasks.size + " missing tasks from " + stage + " (" + stage.rdd + ")")
        stage.pendingPartitions ++= tasks.map(_.partitionId)
        logDebug("New pending partitions: " + stage.pendingPartitions)
        // 根据tasks生成TaskSet，然后通过TaskScheduler.submitTasks方法提交TaskSet
        taskScheduler.submitTasks(new TaskSet(
            tasks.toArray, stage.id, stage.latestInfo.attemptId, jobId, properties))
        stage.latestInfo.submissionTime = Some(clock.getTimeMillis())
    } else { // 如果当前Stege中不包含task
        // 由于前面已经向listenerBus中提交了StageSubmitted事件，现在这个Stege中没有task运行
        // 则正常流程时，该stage不会被标记为结束。那么需要手动指定该stege为finish状态。
        markStageAsFinished(stage, None)
        // log中的显示信息
        val debugString = stage match {
            case stage: ShuffleMapStage =>
            s"Stage ${stage} is actually done; " +
            s"(available: ${stage.isAvailable}," +
            s"available outputs: ${stage.numAvailableOutputs}," +
            s"partitions: ${stage.numPartitions})"
            case stage : ResultStage =>
            s"Stage ${stage} is actually done; (partitions: ${stage.numPartitions})"
        }
        logDebug(debugString)
    }
}
```

这个方法的主要过程和逻辑都已经在源码注释中进行了分析，在提交Stage时，对于不同的ShuffleMapStage和ResultStage，有不同的处理逻辑。最终根据Stage对于的rdd partition生成tasks 组，然后通过`TaskScheduler.submitTasks`方法，将tasks生成的TaseSet进行提交。 

这里面有一点需要注意的是，在Stage提交时，会向LiveListenerBus发送一个SparkListenerStageSubmitted事件，正常情况下，随着Stage中的task运行结束，会最终将Stage设置成完成状态。但是，对于空的Stage，不会有task运行，所以该Stage也就不会结束，需要在提交时手动将Stage的运行状态设置成Finished。

###### B.  org.apache.spark.scheduler.TaskScheduler#submitTasks

上一步中生成的TaskSet对象传入该方法中，那么首先看一下TaskSet的结构。在TaskSet中，有一个Task类型的数组包含当前Stage对应的Task，然后就是一些stageId，stageAttemptId，以及priority等信息。从前面代码中可以看到，这里传入的优先级是jobId，越早提交的job越优先运行。

TaskSet保存了Stage包含的一组完全相同的Task，每个Task的处理逻辑完全相同，不同的是处理数据，每个Task负责处理一个Partition，对于一个Task来说，他从数据源获得逻辑，然后按照拓扑顺序，顺序执行。

```scala
private[spark] class TaskSet(
    val tasks: Array[Task[_]],
    val stageId: Int,
    val stageAttemptId: Int,
    val priority: Int,
    val properties: Properties) {
  val id: String = stageId + "." + stageAttemptId

  override def toString: String = "TaskSet " + id
}
```

submitTasks的主要是将保存这组任务的TaskSet加入到一个TaskSetManager中。

```scala
override def submitTasks(taskSet: TaskSet) {
    val tasks = taskSet.tasks
    logInfo("Adding task set " + taskSet.id + " with " + tasks.length + " tasks")
    this.synchronized {
      // 生成一个TaskSetManager类型对象，
      // task最大重试次数，由参数spark.task.maxFailures设置，默认为4
      // TaskSetManager会根据数据的就近原则为Task分配计算资源
      val manager = createTaskSetManager(taskSet, maxTaskFailures)
      val stage = taskSet.stageId
      // key为stageId，value为一个HashMap，这个HashMap中的key为stageAttemptId，value为TaskSetManager对象
      val stageTaskSets =
        taskSetsByStageIdAndAttempt.getOrElseUpdate(stage, new HashMap[Int, TaskSetManager])
      stageTaskSets(taskSet.stageAttemptId) = manager
      // 如果当前这个stageId对应的HashMap[Int, TaskSetManager]中存在某个taskSet
      // 使得当前的taskSet和这个taskSet不是同一个，并且当前这个TaskSetManager不是zombie进程
      // 即对于同一个stageId，如果当前这个TaskSetManager不是zombie进程，即其中的tasks需要运行，
      // 并且对当前stageId，有两个不同的taskSet在运行
      // 那么就应该抛出异常，确保同一个Stage在正常运行情况下不能有两个taskSet在运行
      val conflictingTaskSet = stageTaskSets.exists { case (_, ts) =>
        ts.taskSet != taskSet && !ts.isZombie
      }
      if (conflictingTaskSet) {
        throw new IllegalStateException(s"more than one active taskSet for stage $stage:" +
          s" ${stageTaskSets.toSeq.map{_._2.taskSet.id}.mkString(",")}")
      }
      // 根据调度模式生成FIFOSchedulableBuilder或者FairSchedulableBuilder，将当前的TaskSetManager提交到调度池中
      // schedulableBuilder是Application级别的调度器，现在支持FIFO和FAIR两种策略
      schedulableBuilder.addTaskSetManager(manager, manager.taskSet.properties)

      if (!isLocal && !hasReceivedTask) {
        starvationTimer.scheduleAtFixedRate(new TimerTask() {
          override def run() {
            if (!hasLaunchedTask) {
              logWarning("Initial job has not accepted any resources; " +
                "check your cluster UI to ensure that workers are registered " +
                "and have sufficient resources")
            } else {
              this.cancel()
            }
          }
        }, STARVATION_TIMEOUT_MS, STARVATION_TIMEOUT_MS)
      }
      hasReceivedTask = true
    }
    // 向schedulerBackend申请资源
    backend.reviveOffers()
  }

```

isZombie的默认值为false，进入true状态有两种情况：TaskSetManager中的tasks都执行成功了，或者这些tasks不再需要执行(比如当前stage被cancel)。之所以在tasks都执行成功后将该TaskSetManager设置为zombie状态而不是直接清除该对象，是为了从TaseSetManager中获取task的运行状况信息。 那么对于isZombie为false的TaseSetManager，即表示其中的tasks仍然需要执行，如果对于当前stage，有一个taskSet正在执行，并且此次提交的taskSet和正在执行的那个不是同一个，那么就会出现同一个Stage执行两个不同的TaskSet的状况，这是不允许的。

关于schedulableBuilder.addTaskSetManager我会在后面的部分详细写，下面继续分析申请资源的部分。

###### C. org.apache.spark.scheduler.cluster.CoarseGrainedSchedulerBackend#reviveOffers

```scala
override def reviveOffers() {
  // 发送单向异步消息。 即发即忘
  driverEndpoint.send(ReviveOffers)
}
```

###### D. org.apache.spark.rpc.netty.NettyRpcEndpointRef#send

NettyRpcEndpointRef#send最终进入org.apache.spark.rpc.netty.NettyRpcEnv#send

```scala
private[netty] def send(message: RequestMessage): Unit = {
  val remoteAddr = message.receiver.address
  if (remoteAddr == address) {
    // Message to a local RPC endpoint.
    try {
      dispatcher.postOneWayMessage(message)
    } catch {
      case e: RpcEnvStoppedException => logDebug(e.getMessage)
    }
  } else {
    // Message to a remote RPC endpoint.
    postToOutbox(message.receiver, OneWayOutboxMessage(message.serialize(this)))
  }
}
```

###### E. org.apache.spark.scheduler.cluster.CoarseGrainedSchedulerBackend.DriverEndpoint#receive

通过netty发送一个请求资源的消息后，CoarseGrainedSchedulerBackend的receive方法则会接收分配到的资源。 
　　在该方法中，由于接收到的是ReviveOffers，会调用makeOffers方法开始生成资源。

```scala
override def receive: PartialFunction[Any, Unit] = {
  case StatusUpdate(executorId, taskId, state, data) =>
    ...

  case ReviveOffers =>
    makeOffers()

  case KillTask(taskId, executorId, interruptThread, reason) =>
    ...
```

###### F. org.apache.spark.scheduler.cluster.CoarseGrainedSchedulerBackend.DriverEndpoint#makeOffers

makeOffers获取可用的Executor，生成一个executor上可用资源WorkerOffer的序列，传入scheduler.resourceOffers方法中。

```scala
// Make fake resource offers on all executors
private def makeOffers() {
  // Make sure no executor is killed while some task is launching on it
  val taskDescs = CoarseGrainedSchedulerBackend.this.synchronized {
    // Filter out executors under killing
    val activeExecutors = executorDataMap.filterKeys(executorIsAlive)
    //
    val workOffers = activeExecutors.map {
      case (id, executorData) =>
        new WorkerOffer(id, executorData.executorHost, executorData.freeCores)
    }.toIndexedSeq
    // 分配资源
    scheduler.resourceOffers(workOffers)
  }
  if (!taskDescs.isEmpty) {
    launchTasks(taskDescs)
  }
}
```

###### G. org.apache.spark.scheduler.TaskSchedulerImpl#resourceOffers

```scala
/**
    * 由cluster manager来调用，为task分配节点上的资源。
    * 根据优先级为task分配资源，
    * 采用round-robin方式使task均匀分布到集群的各个节点上。
    */
  def resourceOffers(offers: IndexedSeq[WorkerOffer]): Seq[Seq[TaskDescription]] = synchronized {
    // Mark each slave as alive and remember its hostname
    // Also track if new executor is added
    var newExecAvail = false
    for (o <- offers) {
      // 添加host到Executer的映射
      if (!hostToExecutors.contains(o.host)) {
        hostToExecutors(o.host) = new HashSet[String]()
      }
      // 将新的executorId添加到executorId到RunningTaskIds的映射
      if (!executorIdToRunningTaskIds.contains(o.executorId)) {
        hostToExecutors(o.host) += o.executorId
        executorAdded(o.executorId, o.host)
        executorIdToHost(o.executorId) = o.host
        executorIdToRunningTaskIds(o.executorId) = HashSet[Long]()
        newExecAvail = true
      }
      // 机架
      for (rack <- getRackForHost(o.host)) {
        hostsByRack.getOrElseUpdate(rack, new HashSet[String]()) += o.host
      }
    }

    // Before making any offers, remove any nodes from the blacklist whose blacklist has expired. Do
    // this here to avoid a separate thread and added synchronization overhead, and also because
    // updating the blacklist is only relevant when task offers are being made.
    blacklistTrackerOpt.foreach(_.applyBlacklistTimeout())

    val filteredOffers = blacklistTrackerOpt.map { blacklistTracker =>
      offers.filter { offer =>
        !blacklistTracker.isNodeBlacklisted(offer.host) &&
          !blacklistTracker.isExecutorBlacklisted(offer.executorId)
      }
    }.getOrElse(offers)

    // 为避免多个Task集中分配到某些机器上，对机器进行随机打散.
    val shuffledOffers = shuffleOffers(filteredOffers)
    // Build a list of tasks to assign to each worker.
    //用来存储分配好资源的task
    val tasks = shuffledOffers.map(o => new ArrayBuffer[TaskDescription](o.cores / CPUS_PER_TASK))
    val availableCpus = shuffledOffers.map(o => o.cores).toArray
    // 从调度池中获取排好序的TaskSetManager，由调度池确定TaskSet的执行顺序
    val sortedTaskSets = rootPool.getSortedTaskSetQueue
    for (taskSet <- sortedTaskSets) {
      logDebug("parentName: %s, name: %s, runningTasks: %s".format(
        taskSet.parent.name, taskSet.name, taskSet.runningTasks))
      if (newExecAvail) {
        taskSet.executorAdded()
      }
    }

    // 为从rootPool中获得的TaskSetManager列表分配资源。就近顺序是：
    // PROCESS_LOCAL, NODE_LOCAL, NO_PREF, RACK_LOCAL, ANY
    // 对每一个taskSet，按照就近顺序分配最近的executor来执行task
    for (taskSet <- sortedTaskSets) {
      var launchedAnyTask = false
      var launchedTaskAtCurrentMaxLocality = false
      for (currentMaxLocality <- taskSet.myLocalityLevels) {
        do {
          // 将前面随机打散的WorkOffers计算资源按照就近原则分配给taskSet，用于执行其中的task
          launchedTaskAtCurrentMaxLocality = resourceOfferSingleTaskSet(
            taskSet, currentMaxLocality, shuffledOffers, availableCpus, tasks)
          launchedAnyTask |= launchedTaskAtCurrentMaxLocality
        } while (launchedTaskAtCurrentMaxLocality)
      }
        // 如果一个task都没有执行
      if (!launchedAnyTask) {
        // 检查给定的任务集是否已被列入黑名单，以至于无法在任何地方运行。
        taskSet.abortIfCompletelyBlacklisted(hostToExecutors)
      }
    }

    if (tasks.size > 0) {
      hasLaunchedTask = true
    }
    return tasks
  }
```

###### H. org.apache.spark.scheduler.TaskSchedulerImpl#resourceOfferSingleTaskSet

这个方法主要是在分配的executor资源上，执行taskSet中包含的所有task。首先遍历分配到的executor，如果当前executor中的cores个数满足配置的单个task需要的core数要求(该core数由参数`spark.task.cpus`确定，默认值为1)，才能在该executor上启动task。

```scala
private def resourceOfferSingleTaskSet(
    taskSet: TaskSetManager,
    maxLocality: TaskLocality,
    shuffledOffers: Seq[WorkerOffer],
    availableCpus: Array[Int],
    tasks: IndexedSeq[ArrayBuffer[TaskDescription]]) : Boolean = {
  var launchedTask = false
  // nodes and executors that are blacklisted for the entire application have already been
  // filtered out by this point
  for (i <- 0 until shuffledOffers.size) {
    val execId = shuffledOffers(i).executorId
    val host = shuffledOffers(i).host
    if (availableCpus(i) >= CPUS_PER_TASK) { // 如果当前executor上的core数满足配置的单个task的core数要求
      try {
        for (task <- taskSet.resourceOffer(execId, host, maxLocality)) { // 为当前stage分配一个executor
          tasks(i) += task
          val tid = task.taskId
          taskIdToTaskSetManager(tid) = taskSet // 存储该task->taskSet的映射关系
          taskIdToExecutorId(tid) = execId // 存储该task分配到的executorId
          executorIdToRunningTaskIds(execId).add(tid) // 存储host->executorId的映射关系
          availableCpus(i) -= CPUS_PER_TASK// 该Executor可用core数减一
          assert(availableCpus(i) >= 0) // 如果启动task后，该executor上的core数大于等于0，才算正常启动。
          launchedTask = true
        }
      } catch {
        case e: TaskNotSerializableException =>
          logError(s"Resource offer failed, task set ${taskSet.name} was not serializable")
          // Do not offer resources for this task, but don't throw an error to allow other
          // task sets to be submitted.
          return launchedTask
      }
    }
  }
  return launchedTask
}
```

###### I. org.apache.spark.scheduler.cluster.CoarseGrainedSchedulerBackend.DriverEndpoint#launchTasks

我们回到CoarseGrainedSchedulerBackend.DriverEndpoint.makeOffers，看最后一步，发送任务的函数launchTasks：

```scala
// Launch tasks returned by a set of resource offers
private def launchTasks(tasks: Seq[Seq[TaskDescription]]) {
  for (task <- tasks.flatten) {
    val serializedTask = TaskDescription.encode(task)
    // 若序列化Task大小达到Rpc限制，则停止
    if (serializedTask.limit() >= maxRpcMessageSize) {
      scheduler.taskIdToTaskSetManager.get(task.taskId).foreach { taskSetMgr =>
        try {
          var msg = "Serialized task %s:%d was %d bytes, which exceeds max allowed: " +
            "spark.rpc.message.maxSize (%d bytes). Consider increasing " +
            "spark.rpc.message.maxSize or using broadcast variables for large values."
          msg = msg.format(task.taskId, task.index, serializedTask.limit(), maxRpcMessageSize)
          taskSetMgr.abort(msg)
        } catch {
          case e: Exception => logError("Exception in error callback", e)
        }
      }
    }
    else {
      // 减少改task所对应的executor信息的core数量
      val executorData = executorDataMap(task.executorId)
      executorData.freeCores -= scheduler.CPUS_PER_TASK

      logDebug(s"Launching task ${task.taskId} on executor id: ${task.executorId} hostname: " +
        s"${executorData.executorHost}.")
      //向executorEndpoint 发送LaunchTask 信号
      executorData.executorEndpoint.send(LaunchTask(new SerializableBuffer(serializedTask)))
    }
  }
}
```

executorEndpoint接收到LaunchTask信号（包含SerializableBuffer(serializedTask) ）后，会开始执行任务。

##### 3. 任务调度的具体实现

###### A. org.apache.spark.scheduler.Pool#getSortedTaskSetQueue

在2.G中讲到TaskSchedulerImpl.resourceOffers中会调用：

```scala
val sortedTaskSets = rootPool.getSortedTaskSetQueue
```

获取按照调度策略排序好的TaskSetManager。接下来我们深入查看这行代码。

rootPool是一个Pool对象，Pool定义为：一个可调度的实体，代表着Pool的集合或者TaskSet的集合，即Schedulable为一个接口，由Pool类和TaskSetManager类实现。

```scala
override def getSortedTaskSetQueue: ArrayBuffer[TaskSetManager] = {
  // 生成TaskSetManager数组
  val sortedTaskSetQueue = new ArrayBuffer[TaskSetManager]
  // 根据调度算法对调度实体进行排序
  val sortedSchedulableQueue =
    schedulableQueue.asScala.toSeq.sortWith(taskSetSchedulingAlgorithm.comparator)
x  for (schedulable <- sortedSchedulableQueue) {
    // 从调度实体中取得TaskSetManager数组
    sortedTaskSetQueue ++= schedulable.getSortedTaskSetQueue
  }
  sortedTaskSetQueue
}
```

注意这里有一个schedulableQueue，Spark通过调度算法提供的比较器对它排序，schedulableQueue的定义如下：

```scala
val schedulableQueue = new ConcurrentLinkedQueue[Schedulable]
```

schedulableQueue是一个并发线性队列，它的元素来源于TaskScheduler#submitTasks中的关键调用是：

`schedulableBuilder.addTaskSetManager(manager, manager.taskSet.properties)`

如果调度方式是FIFO，schedulerBuilder的实现是org.apache.spark.scheduler.FIFOSchedulableBuilder，调度方式如果是FAIR，schedulerBuilder的实现就是org.apache.spark.scheduler.FairSchedulableBuilder。

调度算法taskSetSchedulingAlgorithm，会在Pool被生成时候根据SchedulingMode被设定为FairSchedulingAlgorithm或者FIFOSchedulingAlgorithm

```scala
private val taskSetSchedulingAlgorithm: SchedulingAlgorithm = {
    schedulingMode match {
      case SchedulingMode.FAIR =>
        new FairSchedulingAlgorithm()
      case SchedulingMode.FIFO =>
        new FIFOSchedulingAlgorithm()
      case _ =>
        val msg = s"Unsupported scheduling mode: $schedulingMode. Use FAIR or FIFO instead."
        throw new IllegalArgumentException(msg)
    }
  }
```

###### B. org.apache.spark.scheduler.TaskSchedulerImpl#initialize

在初始化SparkContext时候就会根据集群部署方式初始化TaskManager，同时调用scheduler.initialize(backend),这个时候就会创建一个Pool实例rootPool。

```scala
// 根据schedulingMode创建一个名字为空的rootPool
 val rootPool: Pool = new Pool("", schedulingMode, 0, 0)
 def initialize(backend: SchedulerBackend) {
    this.backend = backend
    schedulableBuilder = {
      schedulingMode match {
        // TaskSchedulerImpl在初始化时，
        // 根据SchedulingMode来创建不同的schedulableBuilder
        case SchedulingMode.FIFO =>
          new FIFOSchedulableBuilder(rootPool)
        case SchedulingMode.FAIR =>
          new FairSchedulableBuilder(rootPool, conf)
        case _ =>
          throw new IllegalArgumentException(s"Unsupported $SCHEDULER_MODE_PROPERTY: " +
          s"$schedulingMode")
      }
    }
    schedulableBuilder.buildPools()
  }
```

##### 4. FIFO调度

###### A. org.apache.spark.scheduler.FIFOSchedulableBuilder#addTaskSetManager

接下来，我们回过头看TaskSchedulerImpl.submitTasks中的schedulableBuilder.addTaskSetManager。

schedulableBuilder是一个SchedulableBuilder接口，SchedulableBuilder接口由两个类FIFOSchedulableBuilder和FairSchedulableBuilder实现。

这里先讲解FIFOSchedulableBuilder，FIFOSchedulableBuilder的addTaskSetManager：

```scala
override def addTaskSetManager(manager: Schedulable, properties: Properties) {
  rootPool.addSchedulable(manager)
}
```

```scala
override def addSchedulable(schedulable: Schedulable) {
  require(schedulable != null)
  schedulableQueue.add(schedulable)
  schedulableNameToSchedulable.put(schedulable.name, schedulable)
  schedulable.parent = this
}
```

实际上是将manager加入到schedulableQueue（这里是FIFO的queue），将manger的name加入到一个名为schedulableNameToSchedulable的 ConcurrentHashMap[String, Schedulable]中，并将manager的parent设置为rootPool。

FIFOSchedulableBuilder#buildPools的实现为空，这是因为rootPool里面不包含其他的Pool，而是像上述所讲的直接将manager的parent设置为rootPool。实际上，这是一种2层的树形结构，第0层为rootPool，第二层叶子节点为各个manager。

采用FIFO任务调度的顺序是这样的：首先保证Job ID较小的先被调用，如果是同一个Job，那么Stage ID小的先被调度。

###### B. org.apache.spark.scheduler.FIFOSchedulingAlgorithm

```scala
private[spark] class FIFOSchedulingAlgorithm extends SchedulingAlgorithm {
  override def comparator(s1: Schedulable, s2: Schedulable): Boolean = {
    val priority1 = s1.priority
    val priority2 = s2.priority
    // 判断符号
    var res = math.signum(priority1 - priority2)
    if (res == 0) {
      val stageId1 = s1.stageId
      val stageId2 = s2.stageId
      res = math.signum(stageId1 - stageId2)
    }
    res < 0
  }
}
```

##### 5. FAIR调度

对于FAIR来说，rootPool包含了一组Pool，这些Pool构成了一颗调度树，其中这棵树的叶子结点就是TaskManager。

###### A. org.apache.spark.scheduler.FairSchedulableBuilder#buildPools

FairSchedulableBuilder.buildPools需要根据 $SPARK_HOME/conf/fairscheduler.xml文件来构建调度树。配置文件大致如下：

```xml
<allocations>
  <pool name="production">
    <schedulingMode>FAIR</schedulingMode>
    <weight>1</weight>
    <minShare>2</minShare>
  </pool>
  <pool name="test">
    <schedulingMode>FIFO</schedulingMode>
    <weight>2</weight>
    <minShare>3</minShare>
  </pool>
</allocations>
```

核心实现：

```scala
private def buildFairSchedulerPool(is: InputStream, fileName: String) {
    // 加载xml 文件
    val xml = XML.load(is)
    // 遍历
    for (poolNode <- (xml \\ POOLS_PROPERTY)) {

      val poolName = (poolNode \ POOL_NAME_PROPERTY).text

      val schedulingMode = getSchedulingModeValue(poolNode, poolName,
        DEFAULT_SCHEDULING_MODE, fileName)
      val minShare = getIntValue(poolNode, poolName, MINIMUM_SHARES_PROPERTY,
        DEFAULT_MINIMUM_SHARE, fileName)
      val weight = getIntValue(poolNode, poolName, WEIGHT_PROPERTY,
        DEFAULT_WEIGHT, fileName)

      // 向rootPool添加Pool
      rootPool.addSchedulable(new Pool(poolName, schedulingMode, minShare, weight))

      logInfo("Created pool: %s, schedulingMode: %s, minShare: %d, weight: %d".format(
        poolName, schedulingMode, minShare, weight))
    }
  }
```

可想而知，FAIR 调度并不是简单的公平调度。我们会先根据xml配置文件生成很多pool加入rootPool中，而每个app会根据配置“spark.scheduler.pool”的poolName，将TaskSetManager加入到某个pool中。其实，rootPool还会对Pool也进程一次调度。

所以，在FAIR调度策略中包含了两层调度。第一层的rootPool内的多个Pool，第二层是Pool内的多个TaskSetManager。fairscheduler.xml文件中， weight（任务权重）和minShare（最小任务数）是来设置第一层调度的，该调度使用的是FAIR算法。而第二层调度由schedulingMode设置。

其调度逻辑如图所示：

![屏幕快照 2018-10-11 下午10.32.58](/Users/harold/Desktop/屏幕快照 2018-10-11 下午10.32.58.png)

###### B. org.apache.spark.scheduler.FairSchedulableBuilder#addTaskSetManager

在FAIR调度下，将TaskSetManager加入Pool的代码比FIFO复杂

```scala
override def addTaskSetManager(manager: Schedulable, properties: Properties) {
  // 根据Properties 确定pool
  val poolName = if (properties != null) {
      properties.getProperty(FAIR_SCHEDULER_PROPERTIES, DEFAULT_POOL_NAME)
    } else {
      DEFAULT_POOL_NAME
    }
  var parentPool = rootPool.getSchedulableByName(poolName)
  // 若rootPool中没有这个pool
  if (parentPool == null) {
    // 我们会根据用户在app上的配置生成新的pool，
    // 而不是根据xml 文件
    parentPool = new Pool(poolName, DEFAULT_SCHEDULING_MODE,
      DEFAULT_MINIMUM_SHARE, DEFAULT_WEIGHT)
    rootPool.addSchedulable(parentPool)
    logWarning(s"A job was submitted with scheduler pool $poolName, which has not been " +
      "configured. This can happen when the file that pools are read from isn't set, or " +
      s"when that file doesn't contain $poolName. Created $poolName with default " +
      s"configuration (schedulingMode: $DEFAULT_SCHEDULING_MODE, " +
      s"minShare: $DEFAULT_MINIMUM_SHARE, weight: $DEFAULT_WEIGHT)")
  }
  // 将这个manager加入到这个pool
  parentPool.addSchedulable(manager)
  logInfo("Added task set " + manager.name + " tasks to pool " + poolName)
}
```

###### C.  org.apache.spark.scheduler.FairSchedulingAlgorithm

现在来看FAIR调度算法的具体实现

```scala
private[spark] class FairSchedulingAlgorithm extends SchedulingAlgorithm {
  override def comparator(s1: Schedulable, s2: Schedulable): Boolean = {
    // 最小任务数
    val minShare1 = s1.minShare
    val minShare2 = s2.minShare
    val runningTasks1 = s1.runningTasks
    val runningTasks2 = s2.runningTasks
    // 若s1运行的任务数小于s1的最小任务数
    val s1Needy = runningTasks1 < minShare1
    // 若s2运行的任务数小于s2的最小任务数
    val s2Needy = runningTasks2 < minShare2
    // minShareRatio = 运行的任务数/最小任务数
    // 代表着负载程度，越小，负载越小
    val minShareRatio1 = runningTasks1.toDouble / math.max(minShare1, 1.0)
    val minShareRatio2 = runningTasks2.toDouble / math.max(minShare2, 1.0)
    // taskToWeightRatio = 运行的任务数/权重
    // 权重越大，越优先
    // 即taskToWeightRatio 越小 越优先
    val taskToWeightRatio1 = runningTasks1.toDouble / s1.weight.toDouble
    val taskToWeightRatio2 = runningTasks2.toDouble / s2.weight.toDouble

    var compare = 0
    // 若s1运行的任务小于s1的最小任务数，而s2不然
    // 则s1优先
    if (s1Needy && !s2Needy) {
      return true
    } else if (!s1Needy && s2Needy) {
      return false
    } else if (s1Needy && s2Needy) {
      // 若s1 s2 运行的任务都小于自己的的最小任务数
      // 比较minShareRatio，哪个小，哪个优先
      compare = minShareRatio1.compareTo(minShareRatio2)
    } else {
      // 若s1 s2 运行的任务都不小于自己的的最小任务数
      // 比较taskToWeightRatio，哪个小，哪个优先
      compare = taskToWeightRatio1.compareTo(taskToWeightRatio2)
    }
    if (compare < 0) {
      true
    } else if (compare > 0) {
      false
    } else {
      s1.name < s2.name
    }
  }
```

至此，TaskScheduler在发送任务给executor前的工作就全部完成了。