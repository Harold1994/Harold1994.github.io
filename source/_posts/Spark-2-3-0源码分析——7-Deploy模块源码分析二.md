---
title: Spark_2.3.0源码分析——7_Deploy模块源码分析二
date: 2018-10-11 21:09:22
tags: [大数据, Spark]
---

接着上一篇博客继续看Deploy模块。

#### 一、Standalone部署

​	Standalone时Spark的自带一种集群资源管理器，能够满足绝大部分纯粹的Spark计算环境中对集群资源管理的需求，基本上只有在集群中运行多套计算框架时才考虑YARN和Mesos。

​	Standalone部署采用典型的Master/Slave架构，Master节点负责整个集群资源的管理与调度，Worker节点在Master节点的调度下启动Executor，负责执行具体工作。

##### 1.应用程序的部署

SparkStandalone对应Spark原生的完全分布式集群，因此此种方式下不需要像伪分布集群那样构建虚拟的本地集群

###### a. 以Client部署模式提交应用程序

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

* SparkContext构建出StandaloneSchedulerBackend实例后，调用其start方法

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