---
title: Spark_2.3.0源码分析——7_Deploy模块源码分析二
date: 2018-10-11 21:09:22
tags: [大数据, Spark]
---

接着上一篇博客继续看Deploy模块。

### 一、Standalone部署

​	Standalone时Spark的自带一种集群资源管理器，能够满足绝大部分纯粹的Spark计算环境中对集群资源管理的需求，基本上只有在集群中运行多套计算框架时才考虑YARN和Mesos。

​	Standalone部署采用典型的Master/Slave架构，Master节点负责整个集群资源的管理与调度，Worker节点在Master节点的调度下启动Executor，负责执行具体工作。

#### 1.应用程序的部署

SparkStandalone对应Spark原生的完全分布式集群，因此此种方式下不需要像伪分布集群那样构建虚拟的本地集群

<!-- more-->

##### A. 以Client部署模式提交应用程序

在Client部署模式提交时，直接在提交点运行应用程序，也就是驱动程序在当前节点启动，对应的部署与执行框架图如下：

![](http://p5s7d12ls.bkt.clouddn.com/18-10-11/47339461.jpg)

SparkContext创建StandaloneSchedulerBackend的代码如下

```scala
case SPARK_REGEX(sparkUrl) =>
  val scheduler = new TaskSchedulerImpl(sc)
  val masterUrls = sparkUrl.split(",").map("spark://" + _)
  val backend = new StandaloneSchedulerBackend(scheduler, sc, masterUrls)
  scheduler.initialize(backend)
  (backend, scheduler)
```

以Client部署模式提交应用程序具体部署与交互过程如下：

1）SparkContext构建出StandaloneSchedulerBackend实例后，调用其start方法

```scala
override def start() {
  super.start()

  // SPARK-21159. The scheduler backend should only try to connect to the launcher when in client
  // mode. In cluster mode, the code that submits the application to the Master needs to connect
  // to the launcher instead.
  if (sc.deployMode == "client") {
    launcherBackend.connect()
  }
  ...
  // Start executors with a few necessary configs for registering with the scheduler
  val sparkJavaOpts = Utils.sparkJavaOpts(conf, SparkConf.isExecutorStartupConf)
  val javaOpts = sparkJavaOpts ++ extraJavaOpts
  // 封装的命令，该命令发送到worker节点，并根据获取的资源启动后，相当于打开了一个通信通道
  val command = Command("org.apache.spark.executor.CoarseGrainedExecutorBackend",
    args, sc.executorEnvs, classPathEntries ++ testingClassPath, libraryPathEntries, javaOpts)
  val webUrl = sc.ui.map(_.webUrl).getOrElse("")
  val coresPerExecutor = conf.getOption("spark.executor.cores").map(_.toInt)
  // If we're using dynamic allocation, set our initial executor limit to 0 for now.
  // ExecutorAllocationManager will send the real initial limit to the Master later.
  val initialExecutorLimit =
    if (Utils.isDynamicAllocationEnabled(conf)) {
      Some(0)
    } else {
      None
    }
  // 通过ApplicationDescription将command封装起来
  val appDesc = ApplicationDescription(sc.appName, maxCores, sc.executorMemory, command,
    webUrl, sc.eventLogDir, sc.eventLogCodec, coresPerExecutor, initialExecutorLimit)
  // 构建一个作为应用程序客户端的AppClient实例，并将this作为该实例的监听器，
  // client实例内部会将Executor端的消息转发给this
  client = new StandaloneAppClient(sc.env.rpcEnv, masters, appDesc, this, conf)
  client.start()
  launcherBackend.setState(SparkAppHandle.State.SUBMITTED)
  waitForRegistration()
  launcherBackend.setState(SparkAppHandle.State.RUNNING)
}
```

其中，client实例调用start()方法后，会构建一个PRC终端通信，即ClientEndpoint实例，实例化后再自动调用onStart()，这时就会将封装的ApplicationDescription实例进一步封装到消息RegisterApplication中，然后由该PRC通信终端将信息发送到Master的通信终端。

```scala
    /**
     *  异步向所有主机注册，并返回一个Future数组用来在之后取消。
     */
    private def tryRegisterAllMasters(): Array[JFuture[_]] = {
      for (masterAddress <- masterRpcAddresses) yield {
        registerMasterThreadPool.submit(new Runnable {
          override def run(): Unit = try {
            if (registered.get) {
              return
            }
            logInfo("Connecting to master " + masterAddress.toSparkURL + "...")
            val masterRef = rpcEnv.setupEndpointRef(masterAddress, Master.ENDPOINT_NAME)
              // 封装appDescription到消息RegisterApplication
            masterRef.send(RegisterApplication(appDescription, self))
          } catch {
            case ie: InterruptedException => // Cancelled
            case NonFatal(e) => logWarning(s"Failed to connect to master $masterAddress", e)
          }
        })
      }
    }
```

2）Master的RPC通信终端在收到RegisterApplications消息后，通过资源调度方法，最终会调用launchExecutor方法，在该方法中再向调度所分配到的Worker节点的RPC通信终端发送LaunchExecutor消息。

3）Worker的PRC通信终端收到LaunchExecutor消息后，会实例化ExecutorRunner对象，然后在线程中解析ApplicationDescription中封装的Command实例，也就是前面的CoarseGrainedExecutorBackend类，最后启动CoarseGrainedExecutorBackend类的进程。

```java
/**
* <p>The new process will
* invoke the command and arguments given by {@link #command()},
* in a working directory as given by {@link #directory()},
* with a process environment as given by {@link #environment()}.
**/
public Process start() throws IOException {  
    ...
        // 最终调用java native方法forkAndExec，forkAndExecthe返回子进程pid
        return ProcessImpl.start(cmdarray,
                                     environment,
                                     dir,
                                     redirects,
                                     redirectErrorStream);
    ...
```

4）在CoarseGrainedExecutorBackend伴生对象main函数中，会解析参数，然后调用run函数，在run函数中会构建CoarseGrainedExecutorBackend实例，即构建一个RPC通信终端，核心代码：

```scala
env.rpcEnv.setupEndpoint("Executor", new CoarseGrainedExecutorBackend(
  env.rpcEnv, driverUrl, executorId, hostname, cores, userClassPath, env))
workerUrl.foreach { url =>
  env.rpcEnv.setupEndpoint("WorkerWatcher", new WorkerWatcher(env.rpcEnv, url))
}
```

其中driverURL是封装CoarseGrainedExecutorBackend到Command时设置的

5）对应CoarseGrainedExecutorBackend的RPC通信终端在实例化时自动调用onStart(),在该方法中向driverURL发送RegisterExecutor消息

6）CoarseGrainedSchedulerBackend收到RegisterExecutor方法后，表示当前有可用资源注册上来，此时即可开始作业调度

##### B.以Cluster的部署模式提交应用程序

​	在Cluster的部署模式提交时，Spark会将应用程序封装到指定的类中，由该类负责向集群申请提交应用程序的执行。即在Cluster部署模式提交时，通过向Master申请执行应用程序，然后Master负责调度分配一个Worker结点，并向该结点发送启动应用程序的消息，应用程序启动后的执行流程，与在该Worker结点上直接以Client部署模式提交应用程序的执行流程是一样的，只是在此之前需要先调度得到该Worker结点，并在该结点启动应用程序。

###### a. 提交方式为REST方式

提交方式为REST方式时，Spark会将应用程序的主类等信息封装到RestSubmissionClient类中，由该类向RestSubmissionServer发送提交应用程序的请求，RestSubmissionServer接收到应用程序提交的请求后，会向Master发送requestSubmitDriver消息，然后由Master根据资源调度策略，启动相应的Driver，执行提交的应用程序。

![屏幕快照 2018-10-12 下午10.07.05.png](https://i.loli.net/2018/10/12/5bc0aaa85a54e.png)

* org.apache.spark.deploy.rest.RestSubmissionClientApp#run

  ```scala
  /** Submits a request to run the application and return the response. Visible for testing. */
  def run(
      appResource: String,
      mainClass: String,
      appArgs: Array[String],
      conf: SparkConf,
      env: Map[String, String] = Map()): SubmitRestProtocolResponse = {
    val master = conf.getOption("spark.master").getOrElse {
      throw new IllegalArgumentException("'spark.master' must be set.")
    }
    val sparkProperties = conf.getAll.toMap
    // 创建一个Rest提交客户端
    val client = new RestSubmissionClient(master)
    // 封装应用程序的相关信息，包括主资源、主类等
    val submitRequest = client.constructSubmitRequest(
      appResource, mainClass, appArgs, sparkProperties, env)
    // Rest提交客户端开始创建Submission
    // 创建过程中向RestSubmissionServer发送post请求
    client.createSubmission(submitRequest)
  }
  ```

* org.apache.spark.deploy.rest.StandaloneSubmitRequestServlet#handleSubmit

  收到提交的Post请求后，StandaloneSubmitRequestServlet向Master的RPC终端发送请求

  ```scala
  /**
   * Handle the submit request and construct an appropriate response to return to the client.
   *
   * This assumes that the request message is already successfully validated.
   * If the request message is not of the expected type, return error to the client.
   */
  protected override def handleSubmit(
      requestMessageJson: String,
      requestMessage: SubmitRestProtocolMessage,
      responseServlet: HttpServletResponse): SubmitRestProtocolResponse = {
    requestMessage match {
      case submitRequest: CreateSubmissionRequest =>
        // 在这里开始构建驱动程序的描述信息
        val driverDescription = buildDriverDescription(submitRequest)
        // 向Master的RPC终端masterEndpoint发送请求消息RequestSubmitDriver
        val response = masterEndpoint.askSync[DeployMessages.SubmitDriverResponse](
          DeployMessages.RequestSuorg.apache.spark.deploy.master.Master#receiveAndReplybmitDriver(driverDescription))
        val submitResponse = new CreateSubmissionResponse
        submitResponse.serverSparkVersion = sparkVersion
        ...
  ```

* org.apache.spark.deploy.rest.StandaloneSubmitRequestServlet#buildDriverDescription

  构建驱动程序的描述信息的方法如下：

  ```scala
  private def buildDriverDescription(request: CreateSubmissionRequest): DriverDescription = {
      ...
       val javaOpts = sparkJavaOpts ++ extraJavaOpts
      // 构建Command实例，将主类mainClass封装到DriverWrapper
      val command = new Command(
        "org.apache.spark.deploy.worker.DriverWrapper",
        Seq("{{WORKER_URL}}", "{{USER_JAR}}", mainClass) ++ appArgs, // args to the DriverWrapper
        environmentVariables, extraClassPath, extraLibraryPath, javaOpts)
      val actualDriverMemory = driverMemory.map(Utils.memoryStringToMb).getOrElse(DEFAULT_MEMORY)
      val actualDriverCores = driverCores.map(_.toInt).getOrElse(DEFAULT_CORES)
      val actualSuperviseDriver = superviseDriver.map(_.toBoolean).getOrElse(DEFAULT_SUPERVISE)
      // 构建DriverDescription
      new DriverDescription(
        appResource, actualDriverMemory, actualDriverCores, actualSuperviseDriver, command)
    }
  ```

* org.apache.spark.deploy.master.Master#receiveAndReply

  Master在收到消息后做如下处理

  ```scala
  // 接收并处理消息
  override def receiveAndReply(context: RpcCallContext): PartialFunction[Any, Unit] = {
    case RequestSubmitDriver(description) =>
      if (state != RecoveryState.ALIVE) {
        val msg = s"${Utils.BACKUP_STANDALONE_MASTER_PREFIX}: $state. " +
          "Can only accept driver submissions in ALIVE state."
        context.reply(SubmitDriverResponse(self, false, None, msg))
      } else {
        // 这里的mainClass就是被封装的应用程序的主类
        logInfo("Driver submitted " + description.command.mainClass)
        // 创建Driver信息，，在Master中需要调度Application和Driver
        val driver = createDriver(description)
        persistenceEngine.addDriver(driver)
        waitingDrivers += driver
        drivers.add(driver)
        // 开始根据调度机制进行调度
        schedule()
  ```

* org.apache.spark.deploy.master.Master#schedule

  ```scala
  /**
   * Schedule the currently available resources among waiting apps. This method will be called
   * every time a new app joins or resource availability changes.
   */
  private def schedule(): Unit = {
    if (state != RecoveryState.ALIVE) {
      return
    }
    //  Driver严格优先于executor调度
    // 逻辑上需要先调度驱动程序，然后再为驱动程序的具体任务分配Executors
    // 调度均衡的一种机制
    val shuffledAliveWorkers = Random.shuffle(workers.toSeq.filter(_.state == WorkerState.ALIVE))
    val numWorkersAlive = shuffledAliveWorkers.size
    var curPos = 0
    for (driver <- waitingDrivers.toList) { // iterate over a copy of waitingDrivers
      // We assign workers to each waiting driver in a round-robin fashion. For each driver, we
      // start from the last worker that was assigned a driver, and continue onwards until we have
      // explored all alive workers.
      // 迭代waitDrivers的副本我们以循环方式将worker分配给每个等待的Driver
      // 对于每个Driver，我们从最后一个被分配了Driver的Worker开始，然后继续向前
      // 直到我们探查了所有活着的Worker。
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
    startExecutorsOnWorkers()
  }
  ```

* org.apache.spark.deploy.worker.Worker#receive

  worker上的Driver启动代码如下：

  ```scala
  case LaunchDriver(driverId, driverDesc) =>
    logInfo(s"Asked to launch driver $driverId")
    // 构造DriverRunner实例
    val driver = new DriverRunner(
      conf,
      driverId,
      workDir,
      sparkHome,
      driverDesc.copy(command = Worker.maybeUpdateSSLSettings(driverDesc.command, conf)),
      self,
      workerUri,
      securityMgr)
    drivers(driverId) = driver
    // 启动驱动程序
    driver.start()
  
    coresUsed += driverDesc.cores
    memoryUsed += driverDesc.mem
  ```

###### b. 提交方式为传统方式

传统方式也会将提交的应用程序封装到DriverDescription，然后向Master发送RequestSubmitDriver消息，之后Master的处理方式与REST方式一样，执行框架如下：

![屏幕快照 2018-10-13 上午10.04.23.png](https://i.loli.net/2018/10/13/5bc152c1151f8.png)

图中的2，3方法与REST一致

* org.apache.spark.deploy.ClientApp#start

  Client的入口函数main调用了org.apache.spark.deploy.ClientApp#start方法

  ```scala
  override def start(args: Array[String], conf: SparkConf): Unit = {
    val driverArgs = new ClientArguments(args)
  
    if (!conf.contains("spark.rpc.askTimeout")) {
      conf.set("spark.rpc.askTimeout", "10s")
    }
    Logger.getRootLogger.setLevel(driverArgs.logLevel)
    // 构建RPC环境实例
    val rpcEnv =
      RpcEnv.create("driverClient", Utils.localHostName(), 0, conf, new SecurityManager(conf))
    // 获取与Master进行通信终端
    val masterEndpoints = driverArgs.masters.map(RpcAddress.fromSparkURL).
      map(rpcEnv.setupEndpointRef(_, Master.ENDPOINT_NAME))
    rpcEnv.setupEndpoint("client", new ClientEndpoint(rpcEnv, driverArgs, masterEndpoints, conf))
    // 等待Master反馈并退出
    rpcEnv.awaitTermination()
  }
  ```

  ClientEndpoint创建后会调用该实例的onStart方法，然后向Master的通信终端发送请求消息RequestSubmitDriver

* org.apache.spark.deploy.ClientEndpoint#onStart

  ```scala
  override def onStart(): Unit = {
    driverArgs.cmd match {
        // 这里处理启动应用程序的消息
      case "launch" =>
      	// 将主类封装到DriverWrapper
          val mainClass = "org.apache.spark.deploy.worker.DriverWrapper"
  		...
  		 // 将 command封装到driverDescription
          val driverDescription = new DriverDescription(
            driverArgs.jarUrl,
            driverArgs.memory,
            driverArgs.cores,
            driverArgs.supervise,
            command)
          // 发送提交Driver的请求，这里的Driver可以理解为请求启动驱动程序的驱动
          asyncSendToMasterAndForwardReply[SubmitDriverResponse](
            RequestSubmitDriver(driverDescription))
  
        case "kill" =>
          val driverId = driverArgs.driverId
          // 发送停止Driver的请求
          asyncSendToMasterAndForwardReply[KillDriverResponse](RequestKillDriver(driverId))
      }
    }
  ```

#### 2. Master的部署

Spark中的各个组件都是通过脚本启动的，以脚本味切入点分析Master的部署

##### A.Master部署的启动脚本

* sbin/start-master.sh

  ```shell
  # 在脚本执行的节点启动Master
  
  # 如果没有设置环境变量SPARK_HOME，会根据脚本的位置自动设置
  if [ -z "${SPARK_HOME}" ]; then
    export SPARK_HOME="$(cd "`dirname "$0"`"/..; pwd)"
  fi
  
  # NOTE: This exact class name is matched downstream by SparkSubmit.
  # Any changes need to be reflected there.
  # Master组件对应类
  CLASS="org.apache.spark.deploy.master.Master"
  # 脚本帮助信息
  if [[ "$@" = *--help ]] || [[ "$@" = *-h ]]; then
    echo "Usage: ./sbin/start-master.sh [options]"
    pattern="Usage:"
    pattern+="\|Using Spark's default log4j profile:"
    pattern+="\|Registered signal handlers for"
  
    "${SPARK_HOME}"/bin/spark-class $CLASS --help 2>&1 | grep -v "$pattern" 1>&2
    exit 1
  fi
  
  ORIGINAL_ARGS="$@"
  
  . "${SPARK_HOME}/sbin/spark-config.sh"
  
  . "${SPARK_HOME}/bin/load-spark-env.sh"
  
  # 默认Master的端口是7077
  if [ "$SPARK_MASTER_PORT" = "" ]; then
    SPARK_MASTER_PORT=7077
  fi
  # 用于Master URL， 当没有设置时，默认使用hostname而不是IP地址
  if [ "$SPARK_MASTER_HOST" = "" ]; then
    case `uname` in
        (SunOS)
       SPARK_MASTER_HOST="`/usr/sbin/check-hostname | awk '{print $NF}'`"
       ;;
        (*)
       SPARK_MASTER_HOST="`hostname -f`"
       ;;
    esac
  fi
  
  if [ "$SPARK_MASTER_WEBUI_PORT" = "" ]; then
    SPARK_MASTER_WEBUI_PORT=8080
  fi
  # 通过启动后台进程的脚本spark-daemon.sh来启动Master组件
  "${SPARK_HOME}/sbin"/spark-daemon.sh start $CLASS 1 \
    --host $SPARK_MASTER_HOST --port $SPARK_MASTER_PORT --webui-port $SPARK_MASTER_WEBUI_PORT \
    $ORIGINAL_ARGS
  ```

* sbin/spark-daemon.sh

  分析可知，Master组件是以后台守护进程的方式启动的，在spark-daemon.sh中，通过脚本spark-class来启动一个指定主类的JVM进程

  ```shell
  case "$mode" in
  # 对应启动一个Spark类
    (class)
      execute_command nice -n "$SPARK_NICENESS" "${SPARK_HOME}"/bin/spark-class "$command" "$@"
      ;;
  # 对应提交一个应用程序
    (submit)
      execute_command nice -n "$SPARK_NICENESS" bash "${SPARK_HOME}"/bin/spark-submit --class "$command" "$@"
      ;;
  
    (*)
      echo "unknown mode: $mode"
      exit 1
      ;;
  esac
  ```

  可知最终执行的是Master类，对应伴生对象的main方法。

##### B.Master的源代码分析

###### a. Master的启动过程

* org.apache.spark.deploy.master.Master#main

  ```scala
  def main(argStrings: Array[String]) {
    Thread.setDefaultUncaughtExceptionHandler(new SparkUncaughtExceptionHandler(
      exitOnUncaughtException = false))
    Utils.initDaemon(log)
    val conf = new SparkConf
    // 构建解析参数的实例
    val args = new MasterArguments(argStrings, conf)
    // 启动RPC通信环境和Endpoint
    val (rpcEnv, _, _) = startRpcEnvAndEndpoint(args.host, args.port, args.webUiPort, conf)
    rpcEnv.awaitTermination()
  }
  ```

* org.apache.spark.deploy.master.MasterArguments

  ```scala
  /**
    * Master的命令解析器
   * Command-line parser for the master.
   */
  private[master] class MasterArguments(args: Array[String], conf: SparkConf) extends Logging {
    var host = Utils.localHostName()
    var port = 7077
    var webUiPort = 8080
    var propertiesFile: String = null
  
    // 读取启动脚本中设置的环境变量
    // Check for settings in environment variables
    if (System.getenv("SPARK_MASTER_IP") != null) {
      logWarning("SPARK_MASTER_IP is deprecated, please use SPARK_MASTER_HOST")
      host = System.getenv("SPARK_MASTER_IP")
    }
  
    if (System.getenv("SPARK_MASTER_HOST") != null) {
      host = System.getenv("SPARK_MASTER_HOST")
    }
    if (System.getenv("SPARK_MASTER_PORT") != null) {
      port = System.getenv("SPARK_MASTER_PORT").toInt
    }
    if (System.getenv("SPARK_MASTER_WEBUI_PORT") != null) {
      webUiPort = System.getenv("SPARK_MASTER_WEBUI_PORT").toInt
    }
    // 命令行选项参数的解析
    parse(args.toList)
  
    // 将默认的属性配置设置到SparkConf中
    // This mutates the SparkConf, so all accesses to it must be made after this line
    propertiesFile = Utils.loadDefaultSparkProperties(conf, propertiesFile)
  ```

* org.apache.spark.deploy.master.Master#startRpcEnvAndEndpoint

  解析完Master的参数后，调用startRpcEnvAndEndpoint方法启动RPC通信环境和PRC通信终端

  ```scala
  /**
   * Start the Master and return a three tuple of:
   *   (1) The Master RpcEnv
   *   (2) The web UI bound port
   *   (3) The REST server bound port, if any
   */
  def startRpcEnvAndEndpoint(
      host: String,
      port: Int,
      webUiPort: Int,
      conf: SparkConf): (RpcEnv, Int, Option[Int]) = {
    val securityMgr = new SecurityManager(conf)
    val rpcEnv = RpcEnv.create(SYSTEM_NAME, host, port, conf, securityMgr)
    // 构建RPC通信终端，会实例化Master
    val masterEndpoint = rpcEnv.setupEndpoint(ENDPOINT_NAME,
      new Master(rpcEnv, rpcEnv.address, webUiPort, securityMgr, conf))
    // 向Master的通信终端发送请求，获取绑定的端口号
    // 包含Master的web ui监听端口号和REST监听端口号
    val portsResponse = masterEndpoint.askSync[BoundPortsResponse](BoundPortsRequest)
    (rpcEnv, portsResponse.webUIPort, portsResponse.restPort)
  }
  ```

* org.apache.spark.deploy.master.Master

  ```scala
  private[deploy] class Master(
      override val rpcEnv: RpcEnv,
      address: RpcAddress,
      webUiPort: Int,
      val securityMgr: SecurityManager,
      val conf: SparkConf)
    extends ThreadSafeRpcEndpoint with Logging with LeaderElectable
  ```

  Master继承了ThreadSafeRpcEndpoint和LeaderElectable，其中LeaderElectable设计Master的HA(高可用性)机制，这里先关注ThreadSafeRpcEndpoint，继承该类后，Master作为一个RpcEndpoint，实例化后会首先调用onStart方法。

  ```scala
  override def onStart(): Unit = {
      logInfo("Starting Spark master at " + masterUrl)
      logInfo(s"Running Spark version ${org.apache.spark.SPARK_VERSION}")
      // 构建一个Master 的web ui
      // 可以查看向Master提交的应用程序等
      webUi = new MasterWebUI(this, webUiPort)
      webUi.bind()
      masterWebUiUrl = "http://" + masterPublicAddress + ":" + webUi.boundPort
      if (reverseProxy) {
        masterWebUiUrl = conf.get("spark.ui.reverseProxyUrl", masterWebUiUrl)
        webUi.addProxy()
        logInfo(s"Spark Master is acting as a reverse proxy. Master, Workers and " +
         s"Applications UIs are available at $masterWebUiUrl")
      }
      // 在一个守护线程中启动调度机制，周期性的检查Worker是否超时
      // 当Worker节点超时后，会修改其状态或从Master中移除与之相关的操作
      checkForWorkerTimeOutTask = forwardMessageThread.scheduleAtFixedRate(new Runnable {
        override def run(): Unit = Utils.tryLogNonFatalError {
          self.send(CheckForWorkerTimeOut)
        }
      }, 0, WORKER_TIMEOUT_MS, TimeUnit.MILLISECONDS)
  // 默认情况下会启动Rest服务，可以通过该服务向Master提交各种请求
      if (restServerEnabled) {
        val port = conf.getInt("spark.master.rest.port", 6066)
        restServer = Some(new StandaloneRestServer(address.host, port, conf, self, masterUrl))
      }
      restServerBoundPort = restServer.map(_.start())
    // 度量相关的操作，用于监控
      masterMetricsSystem.registerSource(masterSource)
      masterMetricsSystem.start()
      applicationMetricsSystem.start()
      // Attach the master and app metrics servlet handler to the web ui after the metrics systems are
      // started.
      masterMetricsSystem.getServletHandlers.foreach(webUi.attachHandler)
      applicationMetricsSystem.getServletHandlers.foreach(webUi.attachHandler)
    // 下面是Master的HA相关的操作
    ...
  ```

###### b. Master的资源调度过程

* org.apache.spark.deploy.master.Master#schedule

  ```scala
  /**
    * 为等待的应用分配资源
    * 当有新用用加入或可用资源发生变化时调用该方法
   * Schedule the currently available resources among waiting apps. This method will be called
   * every time a new app joins or resource availability changes.
   */
  private def schedule(): Unit = {
    if (state != RecoveryState.ALIVE) {
      return
    }
    //  Driver严格优先于executor调度
    // 逻辑上需要先调度驱动程序，然后再为驱动程序的具体任务分配Executors
    
    // 对所有可分配Worker进行洗牌，可以帮助Driver均衡部署
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

* org.apache.spark.deploy.master.Master#startExecutorsOnWorkers

  ```scala
  /**
   * Schedule and launch executors on workers
   */
  private def startExecutorsOnWorkers(): Unit = {
    // Right now this is a very simple FIFO scheduler. We keep trying to fit in the first app
    // in the queue, then the second app, etc.
    // 目前仅支持FIFO调度器
    // Spark中的调度有许多层面，包含应用程序层面的、作业（Job）层面的、作业内Satge层面
    // 以及一个Stage中TaskSet层面的调度
    // 在Master组件的调度中，可以认为是面向应用层面的：Driver和Application层面
    for (app <- waitingApps) {
      val coresPerExecutor = app.desc.coresPerExecutor.getOrElse(1)
      // If the cores left is less than the coresPerExecutor,the cores left will not be allocated
      if (app.coresLeft >= coresPerExecutor) {
        // Filter out workers that don't have enough resources to launch an executor
        // 过滤Workers，提出具有足够资源启动一个Executor的Workers
        // 提取之后再根据内核数进行倒序，优先使用资源丰富的Worker结点
        // 提取条件包括内存大小和内核数
        val usableWorkers = workers.toArray.filter(_.state == WorkerState.ALIVE)
          .filter(worker => worker.memoryFree >= app.desc.memoryPerExecutorMB &&
            worker.coresFree >= coresPerExecutor)
          .sortBy(_.coresFree).reverse// 根据内核数倒序
        // 在提取的可用Workers上为Executor指定分配到的内核数
        val assignedCores = scheduleExecutorsOnWorkers(app, usableWorkers, spreadOutApps)
  
        // 在指定了每个Worker分配到的内核数之后，开始分配并启动Executor
        // Now that we've decided how many cores to allocate on each worker, let's allocate them
        for (pos <- 0 until usableWorkers.length if assignedCores(pos) > 0) {
          allocateWorkerResourceToExecutors(
            app, assignedCores(pos), app.desc.coresPerExecutor, usableWorkers(pos))
        }
      }
    }
  }
  ```

  从代码可知，startExecutorsOnWorkers方法包含下列三个步骤：

  (1). 提取满足资源条件的Worker队列

  (2).指定在每个可用Worker上分配的内核数

  (3). 根据分配到的内核数，在各个Worker上调度和启动Executors

* org.apache.spark.deploy.master.Master#scheduleExecutorsOnWorkers

  ```scala
  /**
  * 启动Executors有两种方式：
    * 第一种方式是将应用程序的Executor部署到尽可能多的Executor上，这是默认方式
    * 可以更好的实现数据本地性
    * 第二种是将应用程序的Executor部署到尽可能少的Executor上， 通常用于计算密集型的应用
    *
    * 每个executor上的内核数可以配置。当显示配置时，如果一个Worker上拥有足够的
    * 内存大小和内核数，同一个应用程序就可以在该Worker上部署多个executor
    * 否则，默认情况下每个Executor会使用Worker上的全部内核，此时就不能在这个Worker上
    * 启动另外一个Executor
   */
  private def scheduleExecutorsOnWorkers(
      app: ApplicationInfo,
      usableWorkers: Array[WorkerInfo],
      // spreadOutApps是控制启动Executors两种方式的变量
      spreadOutApps: Boolean): Array[Int] = {
    val coresPerExecutor = app.desc.coresPerExecutor
    val minCoresPerExecutor = coresPerExecutor.getOrElse(1)
    // 如果没有指定每个Executor分配的内核数，则一个Worker只启动一个executor
    val oneExecutorPerWorker = coresPerExecutor.isEmpty
    val memoryPerExecutor = app.desc.memoryPerExecutorMB
    val numUsable = usableWorkers.length
    val assignedCores = new Array[Int](numUsable) // Number of cores to give to each worker
    val assignedExecutors = new Array[Int](numUsable) // Number of new executors on each worker
    var coresToAssign = math.min(app.coresLeft, usableWorkers.map(_.coresFree).sum)
  
    /** Return whether the specified worker can launch an executor for this app. */
    /** 判断指定索引位置的Worker结点是否能为该应用启动一个Executor **/
    def canLaunchExecutor(pos: Int): Boolean = {
      // 判断当前需要分配的内核数是否满足每个Executor所需的内核数
      val keepScheduling = coresToAssign >= minCoresPerExecutor
      // 判断当前Worker可用内核数量减去当前结点已经分配的内核数
      // 是否满足每个executor所需的内核数
      val enoughCores = usableWorkers(pos).coresFree - assignedCores(pos) >= minCoresPerExecutor
  
      // If we allow multiple executors per worker, then we can always launch new executors.
      // Otherwise, if there is already an executor on this worker, just give it more cores.
      val launchingNewExecutor = !oneExecutorPerWorker || assignedExecutors(pos) == 0
      if (launchingNewExecutor) {
        // 启动一个新的Executor时，除了内核数要满足条件
        // 还需要判断内存是否满足条件
        // 以及当前应用程序的总Executors数是否满足条件
        val assignedMemory = assignedExecutors(pos) * memoryPerExecutor
        val enoughMemory = usableWorkers(pos).memoryFree - assignedMemory >= memoryPerExecutor
        val underLimit = assignedExecutors.sum + app.executors.size < app.executorLimit
        keepScheduling && enoughCores && enoughMemory && underLimit
      } else {
        // We're adding cores to an existing executor, so no need
        // to check memory and executor limits
        keepScheduling && enoughCores
      }
    }
  
    // Keep launching executors until no more workers can accommodate any
    // more executors, or if we have reached this application's limits
    var freeWorkers = (0 until numUsable).filter(canLaunchExecutor)
    while (freeWorkers.nonEmpty) {
      freeWorkers.foreach { pos =>
        var keepScheduling = true
        while (keepScheduling && canLaunchExecutor(pos)) {
          coresToAssign -= minCoresPerExecutor
          assignedCores(pos) += minCoresPerExecutor
  
          // If we are launching one executor per worker, then every iteration assigns 1 core
          // to the executor. Otherwise, every iteration assigns cores to a new executor.
          if (oneExecutorPerWorker) {
            assignedExecutors(pos) = 1
          } else {
            assignedExecutors(pos) += 1
          }
  
          // Spreading out an application means spreading out its executors across as
          // many workers as possible. If we are not spreading out, then we should keep
          // scheduling executors on this worker until we use all of its resources.
          // Otherwise, just move on to the next worker.
          // 根据spreadOutApps判断是否在当前Worker上继续分配内核数，如果为true，
          // 不再从当前结点上继续分配， 而是从下一个Worker上继续分配
          if (spreadOutApps) {
            keepScheduling = false
          }
        }
      }
      freeWorkers = freeWorkers.filter(canLaunchExecutor)
    }
    assignedCores
  }
  ```

* org.apache.spark.deploy.master.Master#allocateWorkerResourceToExecutors

  在指定了每个Worker分配到的内核数之后，开始分配并启动Executor

  ```scala
  private def allocateWorkerResourceToExecutors(
      app: ApplicationInfo,
      assignedCores: Int,
      coresPerExecutor: Option[Int],
      worker: WorkerInfo): Unit = {
    // 如果指定了每个Executor上的内核个数，就将该Worker结点上分配到的内核
    // 分给每个Executor， 如果没有指定，就将全部分配到的内核给一个Executor
    val numExecutors = coresPerExecutor.map { assignedCores / _ }.getOrElse(1)
    val coresToAssign = coresPerExecutor.getOrElse(assignedCores)
    for (i <- 1 to numExecutors) {
      // 为应用程序添加Executor，并启动Executor
      val exec = app.addExecutor(worker, coresToAssign)
      launchExecutor(worker, exec)
      app.state = ApplicationState.RUNNING
    }
  }
  ```

下图形象的展示了Master的调度机制：

![屏幕快照 2018-10-13 下午5.05.05.png](https://i.loli.net/2018/10/13/5bc1b55eeb594.png)

#### 3.Worker的部署

##### A.Worker部署脚本解析

部署脚本根据单个结点几多个结点的Worker的部署，对应有两个脚本：start-slave.sh和start-slaves.sh。start-slaves.sh会读取conf/slaves文件，逐个启动集群中各个Slave结点上的Worker

###### a. sbin/start-slaves.sh

```shell
# Starts a slave instance on each machine specified in the conf/slaves file.

if [ -z "${SPARK_HOME}" ]; then
  export SPARK_HOME="$(cd "`dirname "$0"`"/..; pwd)"
fi

. "${SPARK_HOME}/sbin/spark-config.sh"
. "${SPARK_HOME}/bin/load-spark-env.sh"

# Find the port number for the master
if [ "$SPARK_MASTER_PORT" = "" ]; then
  SPARK_MASTER_PORT=7077
fi

# 获取Master的host信息，如果没有配置的话会通过hostname来获取
# 如果不是在Master组件所在节点运行这个脚本，Master hostname就不一样了
# 最好在Master结点运行这个脚本
if [ "$SPARK_MASTER_HOST" = "" ]; then
  case `uname` in
      (SunOS)
     SPARK_MASTER_HOST="`/usr/sbin/check-hostname | awk '{print $NF}'`"
     ;;
      (*)
     SPARK_MASTER_HOST="`hostname -f`"
     ;;
  esac
fi

# Launch the slaves
# 通过slaves.sh 脚本启动Worker实例，这里会调用start-slave.sh
"${SPARK_HOME}/sbin/slaves.sh" cd "${SPARK_HOME}" \; "${SPARK_HOME}/sbin/start-slave.sh" "spark://$SPARK_MASTER_HOST:$SPARK_MASTER_PORT"
```

slaves.sh通过SSH协议在指定的各个Slave结点执行各种命令。

###### b. sbin/start-slave.sh

从前面可以看到，最终是在各个Slave结点上执行start-slave.sh脚本来部署Worker组件

```shell
if [ -z "${SPARK_HOME}" ]; then
  export SPARK_HOME="$(cd "`dirname "$0"`"/..; pwd)"
fi

# NOTE: This exact class name is matched downstream by SparkSubmit.
# Any changes need to be reflected there.
# Worker组件对应的类
CLASS="org.apache.spark.deploy.worker.Worker"

# 脚本的用法，其中master参数是必选的，Worker需要与集群的Master通信
# 这里的master对用Master URL 信息
if [[ $# -lt 1 ]] || [[ "$@" = *--help ]] || [[ "$@" = *-h ]]; then
  echo "Usage: ./sbin/start-slave.sh [options] <master>"
  pattern="Usage:"
  pattern+="\|Using Spark's default log4j profile:"
  pattern+="\|Registered signal handlers for"

  "${SPARK_HOME}"/bin/spark-class $CLASS --help 2>&1 | grep -v "$pattern" 1>&2
  exit 1
fi

. "${SPARK_HOME}/sbin/spark-config.sh"

. "${SPARK_HOME}/bin/load-spark-env.sh"

# First argument should be the master; we need to store it aside because we may
# need to insert arguments between it and the other arguments
MASTER=$1
shift

# Determine desired worker port
if [ "$SPARK_WORKER_WEBUI_PORT" = "" ]; then
  SPARK_WORKER_WEBUI_PORT=8081
fi

# 在结点上启动指定序列号的Worker实例
# Start up the appropriate number of workers on this machine.
# quick local function to start a worker
function start_instance {
  WORKER_NUM=$1
  shift

  if [ "$SPARK_WORKER_PORT" = "" ]; then
    PORT_FLAG=
    PORT_NUM=
  else
    PORT_FLAG="--port"
    PORT_NUM=$(( $SPARK_WORKER_PORT + $WORKER_NUM - 1 ))
  fi
  WEBUI_PORT=$(( $SPARK_WORKER_WEBUI_PORT + $WORKER_NUM - 1 ))
 # 启用守护进程来启动一个Worker实例
  "${SPARK_HOME}/sbin"/spark-daemon.sh start $CLASS $WORKER_NUM \
     --webui-port "$WEBUI_PORT" $PORT_FLAG $PORT_NUM $MASTER "$@"
}
# SPARK_WORKER_INSTANCES设置了一个节点上部署几个Worker组件，默认只部署一个
if [ "$SPARK_WORKER_INSTANCES" = "" ]; then
  start_instance 1 "$@"
else
  for ((i=0; i<$SPARK_WORKER_INSTANCES; i++)); do
    start_instance $(( 1 + $i )) "$@"
  done
fi
```

##### B. Worker源代码分析

* org.apache.spark.deploy.worker.Worker#main

  ```scala
  def main(argStrings: Array[String]) {
    Thread.setDefaultUncaughtExceptionHandler(new SparkUncaughtExceptionHandler(
      exitOnUncaughtException = false))
    Utils.initDaemon(log)
    val conf = new SparkConf
    // 构建解析参数的实例
    val args = new WorkerArguments(argStrings, conf)
    // 启动RPC通信环境
    val rpcEnv = startRpcEnvAndEndpoint(args.host, args.port, args.webUiPort, args.cores,
      args.memory, args.masters, args.workDir, conf = conf)
    // 启用外部shuffle服务后，如果我们请求在一台主机上启动多个
    // worker，我们只能成功启动第一个worker而其余的都失败，因为端口绑定后，
    // 我们可能会在每台主机上启动不超过一个外部shuffle服务。
    // 当发生这种情况时，我们应该明确失败的原因，而不是默默地失败。
    val externalShuffleServiceEnabled = conf.getBoolean("spark.shuffle.service.enabled", false)
    val sparkWorkerInstances = scala.sys.env.getOrElse("SPARK_WORKER_INSTANCES", "1").toInt
    require(externalShuffleServiceEnabled == false || sparkWorkerInstances <= 1,
      "Starting multiple workers on one host is failed because we may launch no more than one " +
        "external shuffle service on each host, please set spark.shuffle.service.enabled to " +
        "false or set SPARK_WORKER_INSTANCES to 1 to resolve the conflict.")
    rpcEnv.awaitTermination()
  }
  ```

  Worker的main方法与Master基本一致，先解析命令行参数，再调用startRpcEnvAndEndpoint方法启动RPC通信环境及Worker的通信终端。

* org.apache.spark.deploy.worker.Worker#onStart

  最终会实例化一个Worker，Worker继承了ThreadSafeRpcEndpoint，因此在实例化时会调用onStart()方法。	

  ```scala
  override def onStart() {
    // 刚启动时Worker状态是未注册的状态
    assert(!registered)
    logInfo("Starting Spark worker %s:%d with %d cores, %s RAM".format(
      host, port, cores, Utils.megabytesToString(memory)))
    logInfo(s"Running Spark version ${org.apache.spark.SPARK_VERSION}")
    logInfo("Spark home: " + sparkHome)
    // 构建工作路径
    createWorkDir()
    // 启动ExternalShuffle
    startExternalShuffleService()
    webUi = new WorkerWebUI(this, workDir, webUiPort)
    webUi.bind()
  
    workerWebUiUrl = s"http://$publicAddress:${webUi.boundPort}"
    // 注册到Master：Spark集群是Master/Slave结构，每个Slave
    // 结点上启动Worker组件时，都需要向Master注册
    registerWithMaster()
  
    metricsSystem.registerSource(workerSource)
    metricsSystem.start()
    // Attach the worker metrics servlet handler to the web ui after the metrics system is started.
    metricsSystem.getServletHandlers.foreach(webUi.attachHandler)
  }
  ```

  其中createWorkDir()方法对应构建了该Worker结点上的工作目录，后续在该结点上执行的Application相关信息会存放在该目录下。若未指定路径，默认使用sparkHome下的work目录

* org.apache.spark.deploy.worker.Worker#registerWithMaster

  ```scala
  private def registerWithMaster() {
    // onDisconnected可能会被多次触发，
    // 因此如果有未完成的注册尝试，请不要尝试注册。
  
    // 设置注册重试定时器
    registrationRetryTimer match {
      case None =>
        registered = false
        // 尝试注册到所有Master
        registerMasterFutures = tryRegisterAllMasters()
        // 控制重试的次数
        connectionAttemptCount = 0
        // 构建注册重试定时器，注意初始注册重试定时器的时间限制
        // 注册重试定时器会周期性的向Worker本身发送RegisterWithMaster消息
        registrationRetryTimer = Some(forwordMessageScheduler.scheduleAtFixedRate(
          new Runnable {
            override def run(): Unit = Utils.tryLogNonFatalError {
              Option(self).foreach(_.send(ReregisterWithMaster))
            }
          },
          INITIAL_REGISTRATION_RETRY_INTERVAL_SECONDS,
          INITIAL_REGISTRATION_RETRY_INTERVAL_SECONDS,
          TimeUnit.SECONDS))
      case Some(_) =>
        logInfo("Not spawning another attempt to register with the master, since there is an" +
          " attempt scheduled already.")
    }
  }
  ```

* org.apache.spark.deploy.worker.Worker#tryRegisterAllMasters

  ```scala
  private def tryRegisterAllMasters(): Array[JFuture[_]] = {
    masterRpcAddresses.map { masterAddress =>
      // 通过注册线程池提交，线程池最大线程数为Master的数量
      registerMasterThreadPool.submit(new Runnable {
        override def run(): Unit = {
          try {
            logInfo("Connecting to master " + masterAddress + "...")
            val masterEndpoint = rpcEnv.setupEndpointRef(masterAddress, Master.ENDPOINT_NAME)
            // 向特定Master的PRC通信终端发送注册信息
            sendRegisterMessageToMaster(masterEndpoint)
          } catch {
            case ie: InterruptedException => // Cancelled
            case NonFatal(e) => logWarning(s"Failed to connect to master $masterAddress", e)
          }
        }
      })
    }
  }
  ```

* org.apache.spark.deploy.worker.Worker#handleRegisterResponse

* ```scala
  private def handleRegisterResponse(msg: RegisterWorkerResponse): Unit = synchronized {
    msg match {
        // 成功注册Worker结点，修改状态
      case RegisteredWorker(masterRef, masterWebUiUrl, masterAddress) =>
        if (preferConfiguredMasterAddress) {
          logInfo("Successfully registered with master " + masterAddress.toSparkURL)
        } else {
          logInfo("Successfully registered with master " + masterRef.address.toSparkURL)
        }
        registered = true
        changeMaster(masterRef, masterWebUiUrl, masterAddress)
        // 启动周期性心跳发送调度器，在Worker生命周期中定期向Worker自动发送
        // SendHeartbeat，在receive方法中向Master发送心跳
        forwordMessageScheduler.scheduleAtFixedRate(new Runnable {
          override def run(): Unit = Utils.tryLogNonFatalError {
            self.send(SendHeartbeat)
          }
        }, 0, HEARTBEAT_MILLIS, TimeUnit.MILLISECONDS)
        // 启动工作目录定期清理调度器，默认为false
        if (CLEANUP_ENABLED) {
          logInfo(
            s"Worker cleanup enabled; old application directories will be deleted in: $workDir")
          forwordMessageScheduler.scheduleAtFixedRate(new Runnable {
            override def run(): Unit = Utils.tryLogNonFatalError {
              self.send(WorkDirCleanup)
            }
          }, CLEANUP_INTERVAL_MILLIS, CLEANUP_INTERVAL_MILLIS, TimeUnit.MILLISECONDS)
        }
  
        val execs = executors.values.map { e =>
          new ExecutorDescription(e.appId, e.execId, e.cores, e.state)
        }
        masterRef.send(WorkerLatestState(workerId, execs.toList, drivers.keys.toSeq))
      // 失败则退出
      case RegisterWorkerFailed(message) =>
        if (!registered) {
          logError("Worker registration failed: " + message)
          System.exit(1)
        }
    
      case MasterInStandby =>
        // Ignore. Master not yet ready.
    }
  }
  ```

#### 4. Master HA的部署

HA(High Available)，高可用性集群，是保证业务连续性的有效解决方案，一般有两个或两个以上的节点，且分为活动节点及备用节点。通常把正在执行业务的称为活动节点，而作为活动节点的一个备份的则称为备用节点。当活动节点出现问题，导致正在运行的业务（任务）不能正常运行时，备用节点此时就会侦测到，并立即接续活动节点来执行业务。从而实现业务的不中断或短暂中断。

Master继承了ThreadSafeRpcEndpoint和LeaderElectable，其中LeaderElectable是一个特征，代码如下：

```scala
@DeveloperApi
trait LeaderElectable {
    // 为领导选中处理接口
  def electedLeader(): Unit
    // 废除领导层的处理接口
  def revokedLeadership(): Unit
}
```

在Master中，与HA有关的变量如下：

```scala
// 初始状态设置为RecoveryState.STANDBY
private var state = RecoveryState.STANDBY
// Master HA 中用于持久化各种信息的持久化引擎
private var persistenceEngine: PersistenceEngine = _
// Master HA 中用于领导选举的代理
private var leaderElectionAgent: LeaderElectionAgent = _
```

它们位于onStart方法中：

```scala
val (persistenceEngine_, leaderElectionAgent_) = RECOVERY_MODE match {
    case "ZOOKEEPER" =>
      logInfo("Persisting recovery state to ZooKeeper")
      // 通过zookeeper恢复模式的工厂实例构建出持久化引擎和领导选举代理
      val zkFactory =
        new ZooKeeperRecoveryModeFactory(conf, serializer)
      (zkFactory.createPersistenceEngine(), zkFactory.createLeaderElectionAgent(this))
    case "FILESYSTEM" =>
      // 构建一个基于文件系统恢复模式的工厂实例
      val fsFactory =
        new FileSystemRecoveryModeFactory(conf, serializer)
      (fsFactory.createPersistenceEngine(), fsFactory.createLeaderElectionAgent(this))
    case "CUSTOM" =>
      val clazz = Utils.classForName(conf.get("spark.deploy.recoveryMode.factory"))
      val factory = clazz.getConstructor(classOf[SparkConf], classOf[Serializer])
        .newInstance(conf, serializer)
        .asInstanceOf[StandaloneRecoveryModeFactory]
      (factory.createPersistenceEngine(), factory.createLeaderElectionAgent(this))
    case _ =>
      (new BlackHolePersistenceEngine(), new MonarchyLeaderAgent(this))
  }
  persistenceEngine = persistenceEngine_
  leaderElectionAgent = leaderElectionAgent_
}
```

从代码看出有四种RECOVERY_MODE，分别对应ZooKeeper，FILESYSTEM和自定义CUSTOM以及None。