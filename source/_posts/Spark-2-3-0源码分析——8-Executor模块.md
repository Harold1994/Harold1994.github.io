---
title: Spark_2.3.0源码分析——8_Executor模块
date: 2018-10-14 10:15:41
tags: [大数据，Spark]
---

Executor是Spark中执行任务的进程，它可以被不同的调度模式所调度。Executor中有一个RPC远程过程调用接口，有两种实现，分别是netty和AKKA，默认是Netty框架。

Executor中有一个CachedThreadPool，任务被分发到Executor并以TaskRunner形式运行于线程池的线程中。

### 一、Executor中创建、分配、启动及异常处理

#### 1.Executor的创建

以standAlone调度模式为例，SparkContext启动之后，StandaloneSchedulerBackend会构建一个作为应用程序客户端的AppClient实例，AppClient中有一个内部类ClientEndpoint，其通过RPC机制和Master通信。在EndPoint的onStart方法中，会通过registerWithMaster向Master发送RegisterApplication请求，Master收到请求后，会先通过registerApplication完成信息登记，之后调用schedule方法，在Worker上启动Executor。

<!-- more-->

```scala
case RegisterApplication(description, driver) =>
      // TODO Prevent repeated registrations from some driver
      if (state == RecoveryState.STANDBY) {
        // ignore, don't send response
      } else {
        logInfo("Registering app " + description.name)
        val app = createApplication(description, driver)
        // 信息登记
        registerApplication(app)
        logInfo("Registered app " + description.name + " with ID " + app.id)
        persistenceEngine.addApplication(app)
        driver.send(RegisteredApplication(app.id, self))
        // schedule两个作用：
        // 一、完成Driver的调度：将waitingDrivers数组中的Driver发送到满足运行条件的Worker上运行
        // 二、在满足条件的Worker上为Application启动Executor
        schedule()
      }
```

* org.apache.spark.deploy.master.Master#schedule

  ```scala
  private def schedule(): Unit = {
    // 若Master的状态不为Alive，直接退出
    if (state != RecoveryState.ALIVE) {
      return
    }
    //  Driver严格优先于executor调度
    // 逻辑上需要先调度驱动程序，然后再为驱动程序的具体任务分配Executors
  
    // 对所有可分配Worker进行洗牌，可以帮助Driver均衡部署
    // 可以看出Driver是在集群中随机的Worker上启动的
    val shuffledAliveWorkers = Random.shuffle(workers.toSeq.filter(_.state == WorkerState.ALIVE))
    val numWorkersAlive = shuffledAliveWorkers.size
    var curPos = 0
    // 对等待队列中的Driver进行调度
    for (driver <- waitingDrivers.toList) {
      // 迭代waitDrivers的副本我们以循环方式将worker分配给每个等待的Driver
      // 对于每个Driver，我们从最后一个被分配了Driver的Worker开始，然后继续向前
      // 直到我们探查了所有Alive Worker。
      // 和Application在多个节点上分布式启动不同， Driver只在一个结点上启动，调度比较简单
      var launched = false
      var numWorkersVisited = 0
      while (numWorkersVisited < numWorkersAlive && !launched) {
        val worker = shuffledAliveWorkers(curPos)
        numWorkersVisited += 1
        if (worker.memoryFree >= driver.desc.mem && worker.coresFree >= driver.desc.cores) {
          // 开始启动Driver，该方法会向Worker发送启动Driver的请求消息
          launchDriver(worker, driver)
          waitingDrivers -= driver
          launched = true
        }
        curPos = (curPos + 1) % numWorkersAlive
      }
    }
    // 开始为应用程序调度资源
    startExecutorsOnWorkers()
  }
  ```

  startExecutorsOnWorkers在上一片文章中分析过，不赘述，需要注意的是启动Executors有两种方式：
  第一种方式是轮流均摊：将应用程序的Executor部署到尽可能多的Executor上，这是默认方式，可以更好的实现数据本地性
  第二种是依次全占：将应用程序的Executor部署到尽可能少的Executor上， 通常用于计算密集型的应用

* org.apache.spark.deploy.master.Master#allocateWorkerResourceToExecutors

  ```scala
  private def allocateWorkerResourceToExecutors(
      app: ApplicationInfo,
      assignedCores: Int,
      coresPerExecutor: Option[Int],
      worker: WorkerInfo): Unit = {
   // 如果Executor上指定了核的个数，使用分配的核的个数除以指定核的个数，确定要启动的Executor个数
    // 若未指定，则只分配一个Ececutor，并占用分配的全部的核
    val numExecutors = coresPerExecutor.map { assignedCores / _ }.getOrElse(1)
    // 如果coresPerExecutor为0， 则取assignedCores并赋给coresToAssign
    val coresToAssign = coresPerExecutor.getOrElse(assignedCores)
    for (i <- 1 to numExecutors) {
      // 为应用程序添加Executor，并启动Executor
      val exec = app.addExecutor(worker, coresToAssign)
      launchExecutor(worker, exec)
      // 启动后将app状态设置为Running
      app.state = ApplicationState.RUNNING
    }
  }
  ```

  launchExecutor会向Worker发送LaunchExecutor请求，

  ```scala
  private def launchExecutor(worker: WorkerInfo, exec: ExecutorDesc): Unit = {
    logInfo("Launching executor " + exec.fullId + " on worker " + worker.id)
    worker.addExecutor(exec)
    // 向Worker发送LaunchExecutor消息
    worker.endpoint.send(LaunchExecutor(masterUrl,
      exec.application.id, exec.id, exec.application.desc, exec.cores, exec.memory))
    // 向Driver发回ExecutorAdded消息
    exec.application.driver.send(
      ExecutorAdded(exec.id, worker.id, worker.hostPort, exec.cores, exec.memory))
  }
  ```

* Worker收到LaunchExecutor消息后

  首先判断传过来的masterUrl是否与activeMasterUrl相同，如果不相同，说明收到的不是处于ALIVE状态的Master发来的请求，打印警告；如果相同，为Executor创建工作目录，创建好目录后，创建ExecutorRunner，在ExecutorRunner中有一个工作线程，负责下载依赖的文件，并启动CoarseGaindExecutorBackend

  ```scala
  case LaunchExecutor(masterUrl, appId, execId, appDesc, cores_, memory_) =>
    // 如果materUrl和activeMasterUrl不同，说明非法的Master尝试加载Executor
    if (masterUrl != activeMasterUrl) {
      logWarning("Invalid Master (" + masterUrl + ") attempted to launch executor.")
    } else {
      try {
        logInfo("Asked to launch executor %s/%d for %s".format(appId, execId, appDesc.name))
  
        // Create the executor's working directory
        // 在workDir/appId目录下创建一execId为名的Executor工作目录
        val executorDir = new File(workDir, appId + "/" + execId)
        if (!executorDir.mkdirs()) {
          throw new IOException("Failed to create directory " + executorDir)
        }
  
        // Create local dirs for the executor. These are passed to the executor via the
        // SPARK_EXECUTOR_DIRS environment variable, and deleted by the Worker when the
        // application finishes.
        val appLocalDirs = appDirectories.getOrElse(appId, {
          val localRootDirs = Utils.getOrCreateLocalRootDirs(conf)
          val dirs = localRootDirs.flatMap { dir =>
            try {
              val appDir = Utils.createDirectory(dir, namePrefix = "executor")
              Utils.chmod700(appDir)
              Some(appDir.getAbsolutePath())
            } catch {
              case e: IOException =>
                logWarning(s"${e.getMessage}. Ignoring this directory.")
                None
            }
          }.toSeq
          if (dirs.isEmpty) {
            throw new IOException("No subfolder can be created in " +
              s"${localRootDirs.mkString(",")}.")
          }
          dirs
        })
        appDirectories(appId) = appLocalDirs
        // 实例化ExecutorRunner对象
        val manager = new ExecutorRunner(
          appId,
          execId,
          appDesc.copy(command = Worker.maybeUpdateSSLSettings(appDesc.command, conf)),
          cores_,
          memory_,
          self,
          workerId,
          host,
          webUi.boundPort,
          publicAddress,
          sparkHome,
          executorDir,
          workerUri,
          conf,
          appLocalDirs, ExecutorState.RUNNING)
        executors(appId + "/" + execId) = manager
        // 启动一个线程，在线程中解析ApplicationDescription中封装的Command实例
        manager.start()
        coresUsed += cores_
        memoryUsed += memory_
        sendToMaster(ExecutorStateChanged(appId, execId, manager.state, None, None))
      } catch {
        case e: Exception =>
          logError(s"Failed to launch executor $appId/$execId for ${appDesc.name}.", e)
          if (executors.contains(appId + "/" + execId)) {
            executors(appId + "/" + execId).kill()
            executors -= appId + "/" + execId
          }
          sendToMaster(ExecutorStateChanged(appId, execId, ExecutorState.FAILED,
            Some(e.toString), None))
      }
  }  
  ```

* org.apache.spark.deploy.worker.ExecutorRunner#start

  ```scala
  private[worker] def start() {
    // 创建线程
    workerThread = new Thread("ExecutorRunner for " + fullId) {
      override def run() { fetchAndRunExecutor() }
    }
    workerThread.start()
    // Shutdown hook that kills actors on shutdown.
    // 终止回调函数，用于杀死进程
    shutdownHook = ShutdownHookManager.addShutdownHook { () =>
      // It's possible that we arrive here before calling `fetchAndRunExecutor`, then `state` will
      // be `ExecutorState.RUNNING`. In this case, we should set `state` to `FAILED`.
      if (state == ExecutorState.RUNNING) {
        state = ExecutorState.FAILED
      }
      killProcess(Some("Worker shutting down")) }
  }
  ```

  上 面代码中的fetchAndRunExecutor负责以进程方式启动ApplicationDescription中携带的CoarseGrainedExecutorBackend。

* org.apache.spark.deploy.worker.ExecutorRunner#fetchAndRunExecutor

* ```scala
  /**
   * Download and run the executor described in our ApplicationDescription
   */
  private def fetchAndRunExecutor() {
    try {
      // Launch the process
      // 在线程中解析ApplicationDescription中封装的Command实例
      val builder = CommandUtils.buildProcessBuilder(appDesc.command, new SecurityManager(conf),
        memory, sparkHome.getAbsolutePath, substituteVariables)
      // 得到进程启动命令
      val command = builder.command()
      // 格式化启动命令
      val formattedCommand = command.asScala.mkString("\"", "\" \"", "\"")
      logInfo(s"Launch command: $formattedCommand")
      // 设置进程工作目录
      builder.directory(executorDir)
      builder.environment.put("SPARK_EXECUTOR_DIRS", appLocalDirs.mkString(File.pathSeparator))
      // In case we are running this from within the Spark Shell, avoid creating a "scala"
      // parent process for the executor command
      builder.environment.put("SPARK_LAUNCH_WITH_SCALA", "0")
  
      // Add webUI log urls
      val baseUrl =
        if (conf.getBoolean("spark.ui.reverseProxy", false)) {
          s"/proxy/$workerId/logPage/?appId=$appId&executorId=$execId&logType="
        } else {
          s"http://$publicAddress:$webUiPort/logPage/?appId=$appId&executorId=$execId&logType="
        }
      builder.environment.put("SPARK_LOG_URL_STDERR", s"${baseUrl}stderr")
      builder.environment.put("SPARK_LOG_URL_STDOUT", s"${baseUrl}stdout")
      // 启动CoarseGrainedExecutorBackend进程
      process = builder.start()
      val header = "Spark Executor Command: %s\n%s\n\n".format(
        formattedCommand, "=" * 40)
  
      // Redirect its stdout and stderr to files
      val stdout = new File(executorDir, "stdout")
      stdoutAppender = FileAppender(process.getInputStream, stdout, conf)
  
      val stderr = new File(executorDir, "stderr")
      Files.write(header, stderr, StandardCharsets.UTF_8)
      stderrAppender = FileAppender(process.getErrorStream, stderr, conf)
  
      // Wait for it to exit; executor may exit with code 0 (when driver instructs it to shutdown)
      // or with nonzero exit code
      // 等待进程退出
      val exitCode = process.waitFor()
      state = ExecutorState.EXITED
      val message = "Command exited with code " + exitCode
      // 进程退出后向Worker发送ExecutorStateChanged消息，Worker收到消息后回收资源
      worker.send(ExecutorStateChanged(appId, execId, state, Some(message), Some(exitCode)))
    } catch {
      case interrupted: InterruptedException =>
        logInfo("Runner thread for executor " + fullId + " interrupted")
        state = ExecutorState.KILLED
        killProcess(None)
      case e: Exception =>
        logError("Error running executor", e)
        state = ExecutorState.FAILED
        killProcess(Some(e.toString))
    }
  }
  ```

#### 2.Executor的资源分配

Executor作为单独的进程运行于Worker上，CoarseGrainedExecutorBackend进程启动时会先向Driver注册，注册成功后，CoarseGrainedExecutor收到消息并新建Executor。Executor的配置项可以有多种不同的配置方式：

* 在系统环境变量中指定
* 在配置文件spark-env.sh中指定
* 在使用spark-submit提交程序时，通过参数指定配置。
* 不指定，使用默认值

spark-submit脚本直接运行了org.apache.spark.deploy.SparkSubmit对象

```shell
exec "${SPARK_HOME}"/bin/spark-class org.apache.spark.deploy.SparkSubmit "$@"
```

* org.apache.spark.deploy.SparkSubmit#main

  ```scala
  override def main(args: Array[String]): Unit = {
    // Initialize logging if it hasn't been done yet. Keep track of whether logging needs to
    // be reset before the application starts.
    val uninitLog = initializeLogIfNecessary(true, silent = true)
  
    // 解析参数
    val appArgs = new SparkSubmitArguments(args)
    if (appArgs.verbose) {
      // scalastyle:off println
      printStream.println(appArgs)
      // scalastyle:on println
    }
    // 根据三种行为分别处理
    appArgs.action match {
        // 提交，调用submit方法
      case SparkSubmitAction.SUBMIT => submit(appArgs, uninitLog)
      case SparkSubmitAction.KILL => kill(appArgs)
      case SparkSubmitAction.REQUEST_STATUS => requestStatus(appArgs)
    }
  }
  ```

  关于这里设计的代码在之前的博客中有具体分析过，请到[Spark_2.3.0源码分析——6_Deploy模块源码分析(一)](https://harold1994.github.io/2018/10/09/Spark-2-3-0%E6%BA%90%E7%A0%81%E5%88%86%E6%9E%90%E2%80%94%E2%80%946-Deploy%E6%A8%A1%E5%9D%97/)查看。

  在submit()方法中，完成了提交环境的准备工作之后，接下来启动子进程，在Standalone模式下，启动的子进程是o.a.s.deploy.ClientApp，具体执行过程在org.apache.spark.deploy.SparkSubmit#runMain中。

* org.apache.spark.deploy.SparkSubmit#runMain

  ```scala
  private def runMain(
      childArgs: Seq[String],
      childClasspath: Seq[String],
      sparkConf: SparkConf,
      childMainClass: String,
      verbose: Boolean): Unit = {
  ...
  // 获得ClassLoader
      Thread.currentThread.setContextClassLoader(loader)
  
      for (jar <- childClasspath) { // 遍历classpath列表
        addJarToClasspath(jar, loader) // 使用loader类加载器将jar包依赖加入classpath
      }
  
      var mainClass: Class[_] = null
  
      try {
        mainClass = Utils.classForName(childMainClass)
      } catch {
      ...
          }
          System.exit(CLASS_NOT_FOUND_EXIT_STATUS)
      }
      // 如果mainClass是SparkApplication的子类，返回SparkApplication的新实例
      val app: SparkApplication = if (classOf[SparkApplication].isAssignableFrom(mainClass)) {
        mainClass.newInstance().asInstanceOf[SparkApplication]
      } else {
        // SPARK-4170
        if (classOf[scala.App].isAssignableFrom(mainClass)) {
          printWarning("Subclasses of scala.App may not work correctly. Use a main() method instead.")
        }
        // 返回一个包装了main方法的java类
        new JavaMainApplication(mainClass)
      }
  ...
      try {
        // 如果childMainClass不是SparkApplication的子类，则通过反射调用main方法
        // 如果是，直接调用器start方法
        app.start(childArgs.toArray, sparkConf)
      } catch {
        case t: Throwable =>
          findCause(t) match {
            case SparkUserAppException(exitCode) =>
              System.exit(exitCode)
  
            case t: Throwable =>
              throw t
          }
      }
  ```

  对于childMainClass，由prepareSubmitEnvironment()方法返回，在standalone模式下，childMainClass指的是RestSubmissionClientApp或ClientApp类，源代码如下：

  ```scala
  private[deploy] val REST_CLUSTER_SUBMIT_CLASS = classOf[RestSubmissionClientApp].getName()
    private[deploy] val STANDALONE_CLUSTER_SUBMIT_CLASS = classOf[ClientApp].getName()
  ...
  if (args.isStandaloneCluster) {
    // 如果使用Rest，则childMainClass为org.apache.spark.deploy.rest.RestSubmissionClientApp
    if (args.useRest) {
      childMainClass = REST_CLUSTER_SUBMIT_CLASS
      childArgs += (args.primaryResource, args.mainClass)
    } else {
      // 非Rest，则childMainClass为org.apache.spark.deploy.ClientApp
      // In legacy standalone cluster mode, use Client as a wrapper around the user class
      childMainClass = STANDALONE_CLUSTER_SUBMIT_CLASS
      if (args.supervise) { childArgs += "--supervise" }
      // 设置driverMemory
      Option(args.driverMemory).foreach { m => childArgs += ("--memory", m) }
      Option(args.driverCores).foreach { c => childArgs += ("--cores", c) }
      childArgs += "launch"
      childArgs += (args.master, args.primaryResource, args.mainClass)
    }
    if (args.childArgs != null) {
      childArgs ++= args.childArgs
    }
  }
  ```

* org.apache.spark.deploy.ClientApp#start

  ```scala
  override def start(args: Array[String], conf: SparkConf): Unit = {
    val driverArgs = new ClientArguments(args)
    // 设置rpc超时时间为10s
    if (!conf.contains("spark.rpc.askTimeout")) {
      conf.set("spark.rpc.askTimeout", "10s")
    }
    // 日志级别为WARN
    Logger.getRootLogger.setLevel(driverArgs.logLevel)
    // 构建RPC环境实例
    val rpcEnv =
      RpcEnv.create("driverClient", Utils.localHostName(), 0, conf, new SecurityManager(conf))
    // 获取与Master进行通信终端
    val masterEndpoints = driverArgs.masters.map(RpcAddress.fromSparkURL).
      map(rpcEnv.setupEndpointRef(_, Master.ENDPOINT_NAME))
    // 使用RpcEnv的setupEndpoint方法设置名为client的Endpoint，可与master通信
    rpcEnv.setupEndpoint("client", new ClientEndpoint(rpcEnv, driverArgs, masterEndpoints, conf))
    // 等待Master反馈并退出
    rpcEnv.awaitTermination()
  }
  ```

  Master将Driver加载到Worker结点并启动，Worker节点上运行的Driver同样包含配置参数。当Driver端的SparkContext启动并实例化DAGScheduler、TaskScheduler时，TaskSchedulerBackend实例化ClientApp

  。AppClientPoing的onStart()方法向Master发送RegisterApplication消息，Master收到请求并调用schedule()方法，向Worker发送LaunchExecutor请求，Worker结点启动ExecutorRunner，ExecutorRunner启动CoarseGrainedExecutorBackend并向Driver注册。

#### 3.Executor的启动

​	Master收到RegisterApplication消息后，调用schedule方法，在调度过程中会使用allocateWorkerResourceToExecutors方法为Worker节点上的Executor分配资源。分配好资源后，调用launchExecutor(worker, exec),这个方法向Worker发送LaunchExecutor请求，启动Executor。

​	Worker收到LaunchExecutor消息后，先启动ExecutorRunner，然后向Master发送ExecutorStateChanged消息，Master收到消息后视Executor状态调用schedule()方法，重新调整集群资源。

### 二、执行器的通信接口(ExecutorBackend)

ExecutorBackend时Executor向集群发送更新消息(statusUpdate)的一个可插拔接口。ExecutorBackend有不同的实现，Standalone模式下的默认实现是CoarseGrainedExecutorBackend。

#### 1. ExecutorBackend与Executor的关系

在StandaloneSchedulerBackend中会创建一个StandaloneAppClient，StandaloneAppClient包含了command信息，在command中指定了要启动的ExecutorBackend的实现类，在Standalone模式下，该ExecutorBackend实现类是CoarseGrainedExecutorBackend。

```scala
// 封装的命令，该命令发送到worker节点，并根据获取的资源启动后，相当于打开了一个通信通道
    val command = Command("org.apache.spark.executor.CoarseGrainedExecutorBackend",
      args, sc.executorEnvs, classPathEntries ++ testingClassPath, libraryPathEntries, javaOpts)
// 通过ApplicationDescription将command封装起来
    val appDesc = ApplicationDescription(sc.appName, maxCores, sc.executorMemory, command,
      webUrl, sc.eventLogDir, sc.eventLogCodec, coresPerExecutor, initialExecutorLimit)
    // 构建一个作为应用程序客户端的AppClient实例，并将this作为该实例的监听器，
    // client实例内部会将Executor端的消息转发给this
    client = new StandaloneAppClient(sc.env.rpcEnv, masters, appDesc, this, conf)
    client.start()
    launcherBackend.setState(SparkAppHandle.State.SUBMITTED)
    // 等待登记注册
    waitForRegistration()
    launcherBackend.setState(SparkAppHandle.State.RUNNING)
  }
```

StandaloneAppClient实例向Master发送registerApplication注册请求，Master受理后在Worker结点启动一个ExecutorRunner对象，用于管理一个Executor，在ExecutorRunner中通过CommandUtils.buildProcessBuilder

构建一个ProcessBuilder，调用ProcessBuilder的start方法会以进程的方式启动一个org.apache.spark.executor.CoarseGrainedExecutorBackend，在CoarseGrainedExecutorBackend的onStart方法中会向Driver端发送RegisterExecutor消息请求注册，完成注册后立减返回一个RegisteredExecutor消息，CoarseGrainedExecutorBackend收到消息后马上实例化出一个Executor：

```scala
case RegisteredExecutor =>
  logInfo("Successfully registered with driver")
  try {
    // 注册成功后在本地创建对应的Executor
    executor = new Executor(executorId, hostname, env, userClassPath, isLocal = false)
  } catch {
    case NonFatal(e) =>
      exitExecutor(1, "Unable to create executor due to " + e.getMessage, e)
  }
```

从这里可以看出**ExecutorBackend比Executor先实例化**，ExecutorBackend负责和集群通信，而Executor则专注于处理任务，它们是一对一的关系。每一个Worker上可以启动多个ExecutorBackend进程，每一个进程对应一个Executor。

### 三、Executor中任务的执行

#### 1. Executor中任务的加载

​	Executor是基于线程池的任务执行器，通过launchTask()方法加载任务，将任务以TaskRunner形式放入线程池中运行。DAGScheduler划分好Stage并通过submitMissTask方法分配好任务，并把任务交由TaskSchedulerImpl的submit方法，将任务加入调度池，之后调用CoarseGrainedSchedulerBackend的reviveOffers方法为Task分配资源指定Executor。任务资源分配好后，CoarseGrainedSchedulerBackend将向CoarseGrainedExecutorBackend发送分LaunchTask消息，将具体任务发送到Executor上进行计算。

​	CoarseGrainedExecutorBackend匹配到LaunchTask(data)消息后，将会调用Executor的launchTask方法。launchTask方法将会构建TaskRunner对象并放入线程池中执行。

#### 2. Executor中的任务线程池

在Executor上使用线程池可以减少时在创建和销毁线程上所花费的时间和系统资源开销，如果不使用线程池，可能会造成系统创建大量线程而导致消耗完系统内存，以及出现过度切换。

Executor中使用的是newCachedThreadPool

```scala
// 初始化时创建一个线程池
private val threadPool = {
  val threadFactory = new ThreadFactoryBuilder()
    .setDaemon(true)
    .setNameFormat("Executor task launch worker-%d")
    .setThreadFactory(new ThreadFactory {
      override def newThread(r: Runnable): Thread =
        // Use UninterruptibleThread to run tasks so that we can allow running codes without being
        // interrupted by `Thread.interrupt()`. Some issues, such as KAFKA-1894, HADOOP-10622,
        // will hang forever if some methods are interrupted.
        new UninterruptibleThread(r, "unused") // thread name will be set by ThreadFactoryBuilder
    })
    .build()
  Executors.newCachedThreadPool(threadFactory).asInstanceOf[ThreadPoolExecutor]
}
```

当CoarseGrainedExecutorBackend调用LaunchTask方法，该方法中将会新建TaskRunner，然后放入线程池处理。

```scala
val tr = new TaskRunner(context, taskDescription)
runningTasks.put(taskDescription.taskId, tr)
threadPool.execute(tr)
```

#### 3. 任务执行失败处理

TaskRunner计算过程中可能出现各种异常或错误，如抓取Shuffle失败、没有hdfs的写权限等，当TaskRunner的run方法运行时，可以通过try-catch捕获异常，并通过CoarseGrainedExecutorBackend的statusUpdate方法向CoarseGrainedSchedulerBackend汇报。

```scala
override def statusUpdate(taskId: Long, state: TaskState, data: ByteBuffer) {
  // 接收者通过state值来对Task的执行情况做出判断
  val msg = StatusUpdate(executorId, taskId, state, data)
  driver match {
    case Some(driverRef) => driverRef.send(msg)
    case None => logWarning(s"Drop $msg because has not yet connected to driver")
  }
}
```

TaskState是一个枚举变量，包括LAUNCHING, RUNNING, FINISHED, FAILED, KILLED, LOST

* FAILED

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

* org.apache.spark.scheduler.cluster.CoarseGrainedSchedulerBackend.DriverEndpoint#makeOffers

  ```scala
  private def makeOffers(executorId: String) {
    // Make sure no executor is killed while some task is launching on it
    val taskDescs = CoarseGrainedSchedulerBackend.this.synchronized {
      // 过滤存活的Executor
      if (executorIsAlive(executorId)) {
        // 根据executorId取出ExecutorData
        val executorData = executorDataMap(executorId)
        // 使用ExecutorData创建workOffers对象，它代表Executor上可用的资源
        val workOffers = IndexedSeq(
          new WorkerOffer(executorId, executorData.executorHost, executorData.freeCores))
        // 为任务分配资源，返回获得运行资源的任务的集合
        scheduler.resourceOffers(workOffers)
      } else {
        Seq.empty
      }
    }
    if (!taskDescs.isEmpty) {
      // 运行Task
      launchTasks(taskDescs)
    }
  }
  ```

