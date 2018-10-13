---
title: Spark-2-3-0源码分析——3-DAGScheduler模块
date: 2018-10-04 15:36:46
tags: [大数据, Spark]
---

#### 一、模块概述

##### 1. 整体框架

任务调度模块主要包括两大部分：

* DAGScheduler：分析用户提交的应用，建立DAG，划分Stage。
* TaskScheduler：通过Cluster Manager在集群的某个Worker的Executor上启动任务

它们负责将用户提交的计算任务按DAG划分为不同的阶段，并将不同阶段的计算任务提交到集群进行最终的计算。

<!-- more-->

![屏幕快照 2018-10-11 下午10.33.14.png](https://i.loli.net/2018/10/12/5bbff77a3be8c.png)

#### 二、DAGScheduler实现

​	The high-level scheduling layer that implements stage-oriented scheduling. **It computes a DAG of stages for each job, keeps track of which RDDs and stage outputs are materialized, and <u>finds a minimal schedule to run the job</u>.** It then submits stages as TaskSets to an underlying  TaskScheduler implementation that runs them on the cluster. A TaskSet contains fully independent tasks that can run right away based on the data that's already on the cluster (e.g. map output files from previous stages), though it may fail if this data becomes unavailable.

​	**Spark stages are created by breaking the RDD graph at shuffle boundaries. **RDD operations with "narrow" dependencies, like map() and filter(), are pipelined together into one set of tasks in each stage, but operations with shuffle dependencies require multiple stages (one to write a set of map output files, and another to read those files after a barrier). In the end, every stage will have only shuffle dependencies on other stages, and may compute multiple operations inside it. The actual pipelining of these operations happens in the RDD.compute() functions of various RDDs

​	In addition to coming up with a DAG of stages,**the DAGScheduler also determines the preferred locations to run each task on**, based on the current cache status, and passes these to the low-level TaskScheduler. Furthermore, it handles failures due to shuffle output files being lost, in which case old stages may need to be resubmitted. Failures within a stage that are not caused by shuffle file loss are handled by the TaskScheduler, which will retry each task a small number of times before cancelling the whole stage.

Spark Context的runJob方法是大多数Action操作的主要入口点，runJob会调用DAGScheduler的runJob，而DAGScheduler的runJob会开始对用户提交的Job进行处理。

Spark在构造SparkContext时就会生成DAGScheduler的实例。

```Scala
val (sched, ts) = SparkContext.createTaskScheduler(this, master)
_schedulerBackend = sched//生成schedulerBackend
_taskScheduler = ts//生成taskScheduler
_dagScheduler = new DAGScheduler(this)//生成dagScheduler，传入当前sparkContext对象。
```

在生成_dagScheduler之前，已经生成了_schedulerBackend和_taskScheduler对象。之所以taskScheduler对象在dagScheduler对象构造之前先生成，是由于在生成DAGScheduler的构造方法中会从传入的SparkContext中获取到taskScheduler对象`def this(sc: SparkContext) = this(sc, sc.taskScheduler)`。 

看一下DAGScheduler对象的主构造方法:

```scala
class DAGScheduler(
    private[scheduler] val sc: SparkContext,
    private[scheduler] val taskScheduler: TaskScheduler,
    listenerBus: LiveListenerBus,// 异步处理事件的对象，从sc中获取
    mapOutputTracker: MapOutputTrackerMaster,//运行在Driver端管理shuffle map task的输出
    blockManagerMaster: BlockManagerMaster,
    env: SparkEnv,
    clock: Clock = new SystemClock())
```

##### 1. DAGScheduler的数据结构

在DAGScheduler的源代码中，定义了很多变量，在刚构造出来时，仅仅只是初始化这些变量，具体使用是在后面Job提交的过程中了。

```scala
private[spark] val metricsSource: DAGSchedulerSource = new DAGSchedulerSource(this)
  // 生成JobId
  private[scheduler] val nextJobId = new AtomicInteger(0)
  // 总的Job数
  private[scheduler] def numTotalJobs: Int = nextJobId.get()
  // 下一个StageId
  private val nextStageId = new AtomicInteger(0)

  // 记录某个job对应的包含的所有stage
  private[scheduler] val jobIdToStageIds = new HashMap[Int, HashSet[Int]]
  // 记录StageId对应的Stage
  private[scheduler] val stageIdToStage = new HashMap[Int, Stage]
  /**
    * 映射shuffle依赖项ID到将为该依赖项生成数据的ShuffleMapStage。 仅包括那些当前正在运行的作业部分阶段
    * （当需要的洗牌阶段完成的任务（一个或多个），
    * 映射将被删除，并混洗数据的唯一记录将在MapOutputTracker）。
    * key为shuffleId
    */
  private[scheduler] val shuffleIdToMapStage = new HashMap[Int, ShuffleMapStage]
  // 记录处于Active状态的job，key为jobId, value为ActiveJob类型对象
  private[scheduler] val jobIdToActiveJob = new HashMap[Int, ActiveJob]

  // 等待运行的Stage，一般这些是在等待Parent Stage运行完成才能开始
  private[scheduler] val waitingStages = new HashSet[Stage]

  // Stages we are running right now
  private[scheduler] val runningStages = new HashSet[Stage]

  // Stages that must be 重新提交 due to fetch failures
  private[scheduler] val failedStages = new HashSet[Stage]
  // active状态的Job列表
  private[scheduler] val activeJobs = new HashSet[ActiveJob]

 // 包含缓存每个RDD分区的位置。 此映射的键是RDD ID，其值是由分区号索引的数组。 每个数组值都是缓存该RDD分区的位置集
  private val cacheLocs = new HashMap[Int, IndexedSeq[Seq[TaskLocation]]]

  // 为了跟踪失败的节点，我们使用MapOutputTracker的epoch编号，
  // 该编号随每个任务一起发送。 当我们检测到节点失败时，我们会注意到当前的epoch编号和失败的执行器，为新任务增加它，
  // 并使用它来忽略杂散的ShuffleMapTask结果。
  // TODO：当我们知道没有更多的杂散消息需要检测时，垃圾收集有关失败时期的信息。
  private val failedEpoch = new HashMap[String, Long]
  // outputCommitCoordinator决定任务是否可以将输出提交到HDFS的权限。 使用“第一个提交者获胜策略。
  private [scheduler] val outputCommitCoordinator = env.outputCommitCoordinator

  // A closure serializer that we reuse.
  // This is only safe because DAGScheduler runs in a single thread.
  private val closureSerializer = SparkEnv.get.closureSerializer.newInstance()

  /** If enabled, FetchFailed will not cause stage retry, in order to surface the problem. */
  private val disallowStageRetryForTest = sc.getConf.getBoolean("spark.test.noStageRetry", false)

  /**
   * Whether to unregister all the outputs on the host in condition that we receive a FetchFailure,
   * this is set default to false, which means, we only unregister the outputs related to the exact
   * executor(instead of the host) on a FetchFailure.
   */
  private[scheduler] val unRegisterOutputOnHostOnFetchFailure =
    sc.getConf.get(config.UNREGISTER_OUTPUT_ON_HOST_ON_FETCH_FAILURE)

  /**
   * Number of consecutive stage attempts allowed before a stage is aborted.
    * 在中止阶段之前允许的连续阶段尝试次数。
   */
  private[scheduler] val maxConsecutiveStageAttempts =
    sc.getConf.getInt("spark.stage.maxConsecutiveAttempts",
      DAGScheduler.DEFAULT_MAX_CONSECUTIVE_STAGE_ATTEMPTS)

  private val messageScheduler =
    ThreadUtils.newDaemonSingleThreadScheduledExecutor("dag-scheduler-message")
  // 处理Scheduler事件的对象
  private[scheduler] val eventProcessLoop = new DAGSchedulerEventProcessLoop(this)

```

DAGScheduler构造完成，并初始化一个eventProcessLoop实例后，会调用其`eventProcessLoop.start()`方法，启动一个多线程，然后把各种event都提交到eventProcessLoop中。这个eventProcessLoop比较重要，在后面也会提到。

##### 2. Job的提交

一个Job实际上是从RDD调用一个Action操作开始的，该Action操作最终会进入到`org.apache.spark.SparkContext.runJob()`方法中，在SparkContext中有多个重载的runJob方法，最终调用`dagScheduler.runJob()`方法，它又会调用`submitJob`方法，具体事件流如下：

###### A. org.apache.spark.scheduler.DAGScheduler#runJob

```scala
def runJob[T, U](
      rdd: RDD[T],
      func: (TaskContext, Iterator[T]) => U,
      partitions: Seq[Int],
      callSite: CallSite,
      resultHandler: (Int, U) => Unit,
      properties: Properties): Unit = {
    val start = System.nanoTime
    //这里进入submitJob
    val waiter = submitJob(rdd, func, partitions, callSite, resultHandler, properties)
    ThreadUtils.awaitReady(waiter.completionFuture, Duration.Inf)
    waiter.completionFuture.value.get match {
      case scala.util.Success(_) =>
        logInfo("Job %d finished: %s, took %f s".format
          (waiter.jobId, callSite.shortForm, (System.nanoTime - start) / 1e9))
      case scala.util.Failure(exception) =>
        logInfo("Job %d failed: %s, took %f s".format
          (waiter.jobId, callSite.shortForm, (System.nanoTime - start) / 1e9))
        // SPARK-8644: Include user stack trace in exceptions coming from DAGScheduler.
        val callerStackTrace = Thread.currentThread().getStackTrace.tail
        exception.setStackTrace(exception.getStackTrace ++ callerStackTrace)
        throw exception
    }
  }
```

调用DAGScheduler.submitJob方法后会得到一个JobWaiter实例来监听Job的执行情况。针对Job的Succeeded状态和Failed状态，在接下来代码中都有不同的处理方式。 

###### B. org.apache.spark.scheduler.DAGScheduler#submitJob

进入submitJob方法，首先会去检查rdd的分区信息，在确保rdd分区信息正确的情况下，给当前job生成一个jobId，nexJobId在刚构造出来时是从0开始编号的，在同一个SparkContext中，jobId会逐渐顺延。然后构造出一个JobWaiter对象返回给上一级调用函数。通过上面提到的eventProcessLoop提交该任务，最终会调用到`DAGScheduler.handleJobSubmitted`来处理这次提交的Job。handleJobSubmitted在下面的Stage划分部分会有提到。

```scala
 def submitJob[T, U](
      rdd: RDD[T],
      func: (TaskContext, Iterator[T]) => U,
      partitions: Seq[Int],
      callSite: CallSite,
      resultHandler: (Int, U) => Unit,
      properties: Properties): JobWaiter[U] = {
    // Check to make sure we are not launching a task on a partition that does not exist.
    val maxPartitions = rdd.partitions.length
    // 确保rdd分区信息正确的情况下
    partitions.find(p => p >= maxPartitions || p < 0).foreach { p =>
      throw new IllegalArgumentException(
        "Attempting to access a non-existent partition: " + p + ". " +
          "Total number of partitions: " + maxPartitions)
    }
    // 给当前job生成一个jobId
    val jobId = nextJobId.getAndIncrement()
    if (partitions.size == 0) {
      // Return immediately if the job is running 0 tasks
      return new JobWaiter[U](this, jobId, 0, resultHandler)
    }

    assert(partitions.size > 0)
    val func2 = func.asInstanceOf[(TaskContext, Iterator[_]) => _]
    val waiter = new JobWaiter(this, jobId, partitions.size, resultHandler)
    eventProcessLoop.post(JobSubmitted(
      jobId, rdd, func2, partitions.toArray, callSite, waiter,
      SerializationUtils.clone(properties)))
    waiter
  }
```

###### C. org.apache.spark.util.EventLoop#post

在前面的方法中，调用post方法传入的是一个JobSubmitted实例。DAGSchedulerEventProcessLoop类继承自EventLoop类，其中的post方法也是在EventLoop中定义的。在EventLoop中维持了一个LinkedBlockingDeque类型的事件队列，将该Job提交事件存入该队列后，事件线程会从队列中取出事件并进行处理/

```scala
/**
 * Put the event into the event queue. The event thread will process it later.
 */
private val eventQueue: BlockingQueue[E] = new LinkedBlockingDeque[E]()
def post(event: E): Unit = {
    eventQueue.put(event)
}
```

###### D.org.apache.spark.util.EventLoop#eventThread

守护线程的run方法从eventQueue队列中顺序取出event，调用onReceive方法处理事件

```scala
val event = eventQueue.take()
try {
  onReceive(event)
} 
```

###### E. org.apache.spark.scheduler.DAGSchedulerEventProcessLoop#onReceive

```scala
/**
 * The main event loop of the DAG scheduler.
 */
override def onReceive(event: DAGSchedulerEvent): Unit = {
    val timerContext = timer.time()
    try {
        doOnReceive(event)
    } finally {
        timerContext.stop()
    }
}
```

###### F. org.apache.spark.scheduler.DAGSchedulerEventProcessLoop#doOnReceive

在该方法中，根据事件类别分别匹配不同的方法进一步处理。本次传入的是JobSubmitted方法，那么进一步调用的方法是DAGScheduler.handleJobSubmitted。这部分的逻辑，以及还可以处理的其他事件，都在下面的源代码中。 

```scala
private def doOnReceive(event: DAGSchedulerEvent): Unit = event match {
    // 处理Job提交事件
    case JobSubmitted(jobId, rdd, func, partitions, callSite, listener, properties) =>
      dagScheduler.handleJobSubmitted(jobId, rdd, func, partitions, callSite, listener, properties)

    case MapStageSubmitted(jobId, dependency, callSite, listener, properties) =>
      dagScheduler.handleMapStageSubmitted(jobId, dependency, callSite, listener, properties)

    case StageCancelled(stageId, reason) =>
      dagScheduler.handleStageCancellation(stageId, reason)

    case JobCancelled(jobId, reason) =>
      dagScheduler.handleJobCancellation(jobId, reason)

    case JobGroupCancelled(groupId) =>
      dagScheduler.handleJobGroupCancelled(groupId)

    case AllJobsCancelled =>
      dagScheduler.doCancelAllJobs()

    case ExecutorAdded(execId, host) =>
      dagScheduler.handleExecutorAdded(execId, host)

    case ExecutorLost(execId, reason) =>
      val workerLost = reason match {
        case SlaveLost(_, true) => true
        case _ => false
      }
      dagScheduler.handleExecutorLost(execId, workerLost)

    case WorkerRemoved(workerId, host, message) =>
      dagScheduler.handleWorkerRemoved(workerId, host, message)

    case BeginEvent(task, taskInfo) =>
      dagScheduler.handleBeginEvent(task, taskInfo)

    case SpeculativeTaskSubmitted(task) =>
      dagScheduler.handleSpeculativeTaskSubmitted(task)

    case GettingResultEvent(taskInfo) =>
      dagScheduler.handleGetTaskResult(taskInfo)

    case completion: CompletionEvent =>
      dagScheduler.handleTaskCompletion(completion)

    case TaskSetFailed(taskSet, reason, exception) =>
      dagScheduler.handleTaskSetFailed(taskSet, reason, exception)

    case ResubmitFailedStages =>
      dagScheduler.resubmitFailedStages()
  }
```

doOnReceive最终会调用dagScheduler.handleJobSubmitted，开始处理Job，并执行Stage的划分。

##### 3.Stage的划分

![屏幕快照 2018-10-11 下午10.33.21.png](https://i.loli.net/2018/10/12/5bbff7a09e4ff.png)

​	Stage的划分是从最后一个RDD开始的，也就是触发Action的那个RDD，比如上图中，在RDD G处调用了Action操作，在划分Stage时，会从G开始逆向分析，G依赖于B和F，其中对B是窄依赖，对F是宽依赖，所以F和G不能算在同一个Stage中，即在F和G之间会有一个Stage分界线。上图中还有一处宽依赖在A和B之间，所以这里还会分出一个Stage。最终形成了3个Stage，由于Stage1和Stage2是相互独立的，所以可以并发执行，等Stage1和Stage2准备就绪后，Stage3才能开始执行。 

###### A. org.apache.spark.scheduler.DAGScheduler#handleJobSubmitted

```scala
private[scheduler] def handleJobSubmitted(jobId: Int,
    finalRDD: RDD[_],
    func: (TaskContext, Iterator[_]) => _,
    partitions: Array[Int],
    callSite: CallSite,
    listener: JobListener,
    properties: Properties) {
  var finalStage: ResultStage = null
  try {
    // New stage creation may throw an exception if, for example, jobs are run on a
    // HadoopRDD whose underlying HDFS files have been deleted.
    // 先创建finalStage，也就是ResultStage，Stage划分过程是从最后一个Stage开始往前执行的
    finalStage = createResultStage(finalRDD, func, partitions, jobId, callSite)
  } catch {
    case e: Exception =>
      logWarning("Creating new stage failed due to exception - job: " + jobId, e)
      listener.jobFailed(e)
      return
  }
  //为该Job生成一个ActiveJob对象，并准备计算这个finalStage
  val job = new ActiveJob(jobId, finalStage, callSite, listener, properties)
  clearCacheLocs()
  logInfo("Got job %s (%s) with %d output partitions".format(
    job.jobId, callSite.shortForm, partitions.length))
  logInfo("Final stage: " + finalStage + " (" + finalStage.name + ")")
  logInfo("Parents of final stage: " + finalStage.parents)
  logInfo("Missing parents: " + getMissingParentStages(finalStage))

  val jobSubmissionTime = clock.getTimeMillis()
  jobIdToActiveJob(jobId) = job
  activeJobs += job // 该job进入active状态
  finalStage.setActiveJob(job)
  val stageIds = jobIdToStageIds(jobId).toArray
  val stageInfos = stageIds.flatMap(id => stageIdToStage.get(id).map(_.latestInfo))
  listenerBus.post(  // 向LiveListenerBus发送Job提交事件
    SparkListenerJobStart(job.jobId, jobSubmissionTime, stageInfos, properties))
  submitStage(finalStage)
}
```

###### B. org.apache.spark.scheduler.DAGScheduler#createResultStage

在这个方法中，会根据最后调用Action的那个RDD，以及方法调用过程callSite，生成的jobId，partitions等信息生成最后那个Stage。

```scala
/**
   * Create a ResultStage associated with the provided jobId.
   */
  private def createResultStage(
      rdd: RDD[_],
      func: (TaskContext, Iterator[_]) => _,
      partitions: Array[Int],
      jobId: Int,
      callSite: CallSite): ResultStage = {
    // 获取当前Stage的parent Stage，这个方法是划分Stage的核心实现
    val parents = getOrCreateParentStages(rdd, jobId)
    val id = nextStageId.getAndIncrement()
    val stage = new ResultStage(id, rdd, func, partitions, parents, jobId, callSite)
    stageIdToStage(id) = stage
    // 更新该job中包含的stage
    updateJobIdStageIdMaps(jobId, stage)
    stage
  }
```

###### C. org.apache.spark.scheduler.DAGScheduler#getOrCreateParentStages

​	在上面的代码中，调用getOrCreateParentStages，为当前的RDD向前探索，找到宽依赖处划分出parentStage。它的做法是先获取这个rdd的所有ShuffleDependency，然后再获取这些ShuffleDependency所依赖的Stage。

```scala
/**
 * Get or create the list of parent stages for a given RDD.  The new Stages will be created with the provided firstJobId.
 */
private def getOrCreateParentStages(rdd: RDD[_], firstJobId: Int): List[Stage] = {
    // getShuffleDependencies获取所有的shuffle依赖，返回一个类型为ShuffleDependency的Set
    getShuffleDependencies(rdd).map { shuffleDep =>
        // 获取ShuffleDependency所依赖的Stage
        getOrCreateShuffleMapStage(shuffleDep, firstJobId)
    }.toList
}
```

###### E. org.apache.spark.scheduler.DAGScheduler#getShuffleDependencies

上一段代码调用了getShuffleDependencies方法，getShuffleDependencies方法值根据当前RDD寻找其前面的第一个Shuffle依赖(如果有多个的话，只返回前面的第一个)

```scala
private[scheduler] def getShuffleDependencies(
      rdd: RDD[_]): HashSet[ShuffleDependency[_, _, _]] = {
    // 存储parent stage
    val parents = new HashSet[ShuffleDependency[_, _, _]]
    // 存储已经被访问到的RDD
    val visited = new HashSet[RDD[_]]
    // 一个栈，保存未访问过的rdd，先进后出
    val waitingForVisit = new ArrayStack[RDD[_]]
    // 以输入的rdd作为第一个需要被处理的RDD，然后从这个rdd开始，顺序处理其parent rdd
    waitingForVisit.push(rdd)

    while (waitingForVisit.nonEmpty) {
      val toVisit = waitingForVisit.pop()
      if (!visited(toVisit)) {
        visited += toVisit
        toVisit.dependencies.foreach {
          // 如果是ShuffleDependency,就加入parent的集合
          case shuffleDep: ShuffleDependency[_, _, _] =>
            parents += shuffleDep
            // 如果不是如果是ShuffleDependency，那么就属于同一个Stage
          case dependency =>
            waitingForVisit.push(dependency.rdd)
        }
      }
    }
    parents
  }
```

###### F. org.apache.spark.scheduler.DAGScheduler#getOrCreateShuffleMapStage

由于getShuffleDependencies只返回一个前面最近的Shuffle依赖，此时接着执行getOrCreateShuffleMapStage方法，对返回的Shuffle依赖创建Stage：

```scala
private def getOrCreateShuffleMapStage(
    shuffleDep: ShuffleDependency[_, _, _],
    firstJobId: Int): ShuffleMapStage = {
  shuffleIdToMapStage.get(shuffleDep.shuffleId) match {
    case Some(stage) => // 如果已经创建，则直接返回
      stage

    case None =>
      // Create stages for all missing ancestor shuffle dependencies.
      getMissingAncestorShuffleDependencies(shuffleDep.rdd).foreach { dep =>
        // Even though getMissingAncestorShuffleDependencies only returns shuffle dependencies
        // that were not already in shuffleIdToMapStage, it's possible that by the time we
        // get to a particular dependency in the foreach loop, it's been added to
        // shuffleIdToMapStage by the stage creation process for an earlier dependency. See
        // SPARK-13902 for more information.
        if (!shuffleIdToMapStage.contains(dep.shuffleId)) {
          createShuffleMapStage(dep, firstJobId)
        }
      }
      // Finally, create a stage for the given shuffle dependency.
      createShuffleMapStage(shuffleDep, firstJobId)
  }
}
```

 getOrCreateShuffleMapStage方法首先根据当前shuffleDep的shuffle依赖id判断是否创建了Stage，如果创建了返回该Stage，如果没有创建的话调用org.apache.spark.scheduler.DAGScheduler#getMissingAncestorShuffleDependencies方法寻找shuffleDep的父RDD前面所有的Shuffle依赖(依赖划分是后向前进行的)，最后以栈的形式返回，通过foreach对栈(栈顶是最前面的shuffle依赖)中所有的Shuffle依赖创建Stage(stage创建过程是由前向后创建的)。最后返回一个Stage的列表

###### G. org.apache.spark.scheduler.DAGScheduler#getMissingAncestorShuffleDependencies

```scala
/** Find ancestor shuffle dependencies that are not registered in shuffleToMapStage yet */
  private def getMissingAncestorShuffleDependencies(
      rdd: RDD[_]): ArrayStack[ShuffleDependency[_, _, _]] = {
    val ancestors = new ArrayStack[ShuffleDependency[_, _, _]]
    val visited = new HashSet[RDD[_]]
    // We are manually maintaining a stack here to prevent StackOverflowError
    // caused by recursively visiting
    val waitingForVisit = new ArrayStack[RDD[_]]
    waitingForVisit.push(rdd)
    while (waitingForVisit.nonEmpty) {
      val toVisit = waitingForVisit.pop()
      if (!visited(toVisit)) {
        visited += toVisit
        // 这里又一次用到了getShuffleDependencies
        getShuffleDependencies(toVisit).foreach { shuffleDep =>
          if (!shuffleIdToMapStage.contains(shuffleDep.shuffleId)) {
            ancestors.push(shuffleDep)
            waitingForVisit.push(shuffleDep.rdd)
          } // Otherwise, the dependency and its ancestors have already been registered.
        }
      }
    }
    ancestors
  }
```

通过调用org.apache.spark.scheduler.DAGScheduler#getShuffleDependencies方法，每找到一个Shuffle依赖就把该依赖的父RDD放到waitingForVisit栈中，依次遍历。

>  总结：第一次是根据RDD调用getShuffleDependencies找到第一个shuffle，然后根据该shuffle创建Stage，如果stage存在则直接返回，不存在的话，寻找该shuffle父RDD的所有依赖Shuffle依赖，最后以Stack[ShuffleDependency]数据结构返回，然后遍历该栈依次为ShuffleDependency创建Stage，最后返回List[Stage]

##### 4. 任务的生成

让我们再次回到DAGScheduler#handleJobSubmitted方法中，生成了finalStage后，就会为该Job生成一个ActiveJob对象了，并准备计算这个finalStage。 

`val job = new ActiveJob(jobId, finalStage, callSite, listener, properties)`

在`DAGScheduler.handleJobSubmitted`方法的最后，调用了`DAGScheduler.submitStage`方法，在提交finalSate的前面，会通过listenerBus的post方法，把Job开始的事件提交到Listener中。

提交Job的提交，是从最后那个Stage开始的。如果当前stage已经被提交过，处于waiting或者waiting状态，或者当前stage已经处于failed状态则不作任何处理，否则继续提交该stage。 
 　　在提交时，需要当前Stage需要满足依赖关系，其前置的Parent Stage都运行完成后才能轮得到当前Stage运行。如果还有Parent Stage未运行完成，则优先提交Parent Stage。通过调用方法`DAGScheduler.getMissingParentStages`方法获取未执行的Parent Stage。 
 　　如果当前Stage满足上述两个条件后，调用`DAGScheduler.submitMissingTasks`方法，提交当前Stage。

```scala
/** Submits stage, but first recursively submits any missing parents. */
  private def submitStage(stage: Stage) {
    val jobId = activeJobForStage(stage) // 获取当前提交Stage所属的Job
    if (jobId.isDefined) {
      logDebug("submitStage(" + stage + ")")
      // 首先判断当前stage的状态，如果当前Stage不是处于waiting, running以及failed状态
      // 则提交该stage
      if (!waitingStages(stage) && !runningStages(stage) && !failedStages(stage)) {
        val missing = getMissingParentStages(stage).sortBy(_.id)
        logDebug("missing: " + missing)
        if (missing.isEmpty) { // 如果所有的parent stage都以及完成，那么就会提交该stage所包含的task
          logInfo("Submitting " + stage + " (" + stage.rdd + "), which has no missing parents")
          submitMissingTasks(stage, jobId.get)
        } else {
          for (parent <- missing) {
            submitStage(parent)
          }
          waitingStages += stage //当前stage进入等待队列
        }
      }
    } else { //如果jobId没被定义，即无效的stage则直接停止
      abortStage(stage, "No active job for stage " + stage.id, None)
    }
  }
```

**getMissingParentStage**方法用于获取stage未执行的Parent Stage。在上面方法中，获取到Parent Stage后，递归调用上面那个方法按照StageId小的先提交的原则，这个方法的逻辑和[DAGScheduler#getParentStages方法类似，这里不再分析了。总之就是根据当前Stage，递归调用其中的visit方法，依次对每一个Stage追溯其未运行的Parent Stage。 

当Stage的Parent Stage都运行完毕，才能调用submitMissingTasks方法真正的提交当前Stage中包含的Task。这个方法涉及到了Task，会在下一篇文章中进一步分析。