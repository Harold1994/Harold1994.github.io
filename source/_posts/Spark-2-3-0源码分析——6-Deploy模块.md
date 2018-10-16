---
title: Spark_2.3.0源码分析——6_Deploy模块源码分析(一)
date: 2018-10-09 16:21:27
tags: [大数据, Spark]
---

Spark的部署方式有以下几种：

* Standalone
* Mesos
* YARN
* Local
* KUBERNETES

<!-- more-->

#### 一、应用程序的部署脚本

Spark提供了各种应用程序提交的统一入口脚本，即spark-submit脚本,这些脚本最终都调用到一个执行Java类的脚本：./bin/spark-class

###### 1.spark-shell

通过这个脚本可以打开使用Scala语言进行开发和调试的交互式界面

用法：`"Usage: ./bin/spark-shell [options]"`

```shell
...
function main() {
  if $cygwin; then
    stty -icanon min 1 -echo > /dev/null 2>&1
    export SPARK_SUBMIT_OPTS="$SPARK_SUBMIT_OPTS -Djline.terminal=unix"
    "${SPARK_HOME}"/bin/spark-submit --class org.apache.spark.repl.Main --name "Spark shell" "$@"
    stty icanon echo > /dev/null 2>&1
  else
    export SPARK_SUBMIT_OPTS
    "${SPARK_HOME}"/bin/spark-submit --class org.apache.spark.repl.Main --name "Spark shell" "$@"
  fi
}
...
```

###### 2.pyspark

通过该脚本可以打开使用python语言开发和调试的交互式界面

用法：`"Usage: ./bin/pyspark [options]"`

脚本的执行语句如下：

```scala
exec "${SPARK_HOME}"/bin/spark-submit pyspark-shell-main --name "PySparkShell" "$@"
```

###### 3.spark-submit

用法：

```scala
val command = sys.env.get("_SPARK_CMD_USAGE").getOrElse(
  """Usage: spark-submit [options] <app jar | python file | R file> [app arguments]
    |Usage: spark-submit --kill [submission ID] --master [spark://...]
    |Usage: spark-submit --status [submission ID] --master [spark://...]
    |Usage: spark-submit run-example [options] example-class [example args]""".stripMargin)
```

spark通过这段脚本执行org.apache.spark.deploy.SparkSubmit的main方法，作为整个Spark程序的主入口

```shell
if [ -z "${SPARK_HOME}" ]; then
  source "$(dirname "$0")"/find-spark-home
fi

# disable randomized hash for string in Python 3.3+
export PYTHONHASHSEED=0
# SparkSubmit是利用Spark-submit提交应用程序的入口类。进入SparkSubmit的main函数。
exec "${SPARK_HOME}"/bin/spark-class org.apache.spark.deploy.SparkSubmit "$@"
```

###### 4.spark-class

这个脚本是所有其他脚本最终都调用到的一个执行Java类的脚本，关键执行语句如下：

```shell
build_command() {
  "$RUNNER" -Xmx128m -cp "$LAUNCH_CLASSPATH" org.apache.spark.launcher.Main "$@"
  printf "%d\0" $?
}

# Turn off posix mode since it does not allow process substitution
set +o posix
CMD=()
#  IFS的默认值为：空白
# Shell中while循环的done 后接一个重定向<
# 读文件的方法：
# 第一步： 将文件的内容通过管道（|）或重定向（<）的方式传给while
# 第二步： while中调用read将文件内容一行一行的读出来，并付值给read后跟随的变量。变量中就保存了当前行中的内容。
while IFS= read -d '' -r ARG; do
  CMD+=("$ARG")
done < <(build_command "$@")
...
exec "${CMD[@]}"
```

负责运行的 RUNNER变量设置如下：

```shell
# Find the java binary
if [ -n "${JAVA_HOME}" ]; then
  RUNNER="${JAVA_HOME}/bin/java"
else
  if [ "$(command -v java)" ]; then
    RUNNER="java"
  else
    echo "JAVA_HOME is not set" >&2
    exit 1
  fi
fi
```

在脚本中，LAUNCH_CLASSPATH变量对应了Java命令运行时所需的classpath信息,最终Java命令启动的类是org.apache.spark.launcher.Main,Main类的入口函数main会根据输入参数构建出最终执行的命令，即这里返回的${CMD[@]}，然后通过exec执行。

还有其他几种脚本，与前面的几个大同小异，不再赘述

#### 二、应用程序部署代码

##### 1.org.apache.spark.launcher.Main

通过前面的脚本可以知道，都是通过launcher.Main类来启动应用程序的

Main类主要有两种工作方式：

* spark-submit：启动器要启动的类为org.apache.spark.deploy.SparkSubmit，使用SparkSubmitCommandBuilder来构建启动命令
* spark-class：启动的类是除了SparkSubmit外的其他类，使用SparkClassCommandBuilder.buildCommand方法构建启动命令

以SparkSubmitCommandBuilder为例，它的构造函数如下

```scala
SparkSubmitCommandBuilder(List<String> args) {
  // 是否允许将spark-submit参数和app参数混合在一起
  this.allowsMixedArguments = false;
  this.sparkArgs = new ArrayList<>();
  boolean isExample = false;
  List<String> submitArgs = args;
  // 根据第一个参数设置相应的资源
  if (args.size() > 0) {
    switch (args.get(0)) {
      case PYSPARK_SHELL:
        this.allowsMixedArguments = true;
        appResource = PYSPARK_SHELL;
        submitArgs = args.subList(1, args.size());
        break;

      case SPARKR_SHELL:
        this.allowsMixedArguments = true;
        appResource = SPARKR_SHELL;
        submitArgs = args.subList(1, args.size());
        break;

      case RUN_EXAMPLE:
        isExample = true;
        submitArgs = args.subList(1, args.size());
    ...	
```

##### 2.org.apache.spark.deploy.SparkSubmit#main

提交应用程序的行为类型有三种：

* SUBMIT:提交应用
* KILL：停止应用
* REQUEST_STATUS：查询应用状态

```scala
private[deploy] object SparkSubmitAction extends Enumeration {
  type SparkSubmitAction = Value
  val SUBMIT, KILL, REQUEST_STATUS = Value
}
```

从前面的脚本可以看出，在提交应用程序时，Main所启动的类，也就是用户最终提交执行的类是org.apache.spark.deploy.SparkSubmit，SparkSubmit是启动一个Spark程序的主入口点。一个程序运行的入口点是对应单例对象的main函数：

main方法主要做了两件事情：

- 解析参数：SparkSubmitArguments(args)解析提交脚本时spark-submit传入的参数信息
- 命令提交

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
    case SparkSubmitAction.SUBMIT => submit(appArgs, uninitLog)
    case SparkSubmitAction.KILL => kill(appArgs)
    case SparkSubmitAction.REQUEST_STATUS => requestStatus(appArgs)
  }
}
```

###### a.解析参数

* **org.apache.spark.deploy.SparkSubmitArguments**

```scala
// Set parameters from command line arguments
//  从命令行参数获取解析参数
try {
  parse(args.asJava)
} catch {
  case e: IllegalArgumentException =>
    SparkSubmit.printErrorAndExit(e.getMessage())
}
// Populate `sparkProperties` map from properties file
//  从属性配置文件中填充 sparkProperties 这个map
mergeDefaultSparkProperties()
// Remove keys that don't start with "spark." from `sparkProperties`.
//  移除sparkProperties属性配置中不是以spark.开头的变量。
ignoreNonSparkProperties()
// Use `sparkProperties` map along with env vars to fill in any missing parameters
//  使用sparkProperties和env变量去填充任何缺失的参数。
loadEnvironmentArguments()

validateArguments()
```

Spark先解析外部传进来的参数，然后mergeDefaultSparkProperties将外部参数和默认参数进行了merge，之后移除了不合要求的参数，然后又从从系统环境变量和spark properties中加载参数。

* **org.apache.spark.launcher.SparkSubmitOptionParser#parse**

该函数主要是负责解析spark-submit命令行参数。主要分成两个部分：

1，spark运行环境参数解析,代表方法是SparkSubmitArguments$handle(opt: String, value: String)，不同的部署模式稍微有些区别。 在这里做一点说明，--conf的配置被写道了sparkProperties这个hashmap里了。

2，用户类参数解析，代表方法是SparkSubmitArguments$handleExtraArgs(args.subList(idx, args.size()));这个会传给用户类。

```scala
protected final void parse(List<String> args) {
  Pattern eqSeparatedOpt = Pattern.compile("(--[^=]+)=(.+)");

  int idx = 0;
  for (idx = 0; idx < args.size(); idx++) {
    String arg = args.get(idx);
    String value = null;

    Matcher m = eqSeparatedOpt.matcher(arg);
    if (m.matches()) {
      arg = m.group(1);
      value = m.group(2);
    }

    // Look for options with a value.
    String name = findCliOption(arg, opts);
    if (name != null) {
      if (value == null) {
        if (idx == args.size() - 1) {
          throw new IllegalArgumentException(
              String.format("Missing argument for option '%s'.", arg));
        }
        idx++;
        value = args.get(idx);
      }
      if (!handle(name, value)) {
         break;
      }
      continue;
    }

    // Look for a switch.
    name = findCliOption(arg, switches);
    if (name != null) {
      if (!handle(name, null)) {
        break;
      }
      continue;
    }

    if (!handleUnknown(arg)) {
      break;
    }
  }

  if (idx < args.size()) {
    idx++;
  }
  //    之外的参数会当成，用户入口类的参数
  handleExtraArgs(args.subList(idx, args.size()));
}
```

* **org.apache.spark.deploy.SparkSubmitArguments#handle**

```scala
override protected def handle(opt: String, value: String): Boolean = {
  opt match {
    case NAME =>
      name = value

    case MASTER =>
      master = value

    case CLASS =>
      mainClass = value 
      ...
    // 在这里处理conf配置，--conf的配置被写道了sparkProperties这个hashmap里了
    // 在这之后调用的mergeDefaultSparkProperties又将默认配置文件不覆盖的写入了sparkProperties
    // 因此--conf优先级更高
    case CONF =>
      val (confName, confValue) = SparkSubmit.parseSparkConfProperty(value)
      sparkProperties(confName) = confValue
  ...
```

* **org.apache.spark.deploy.SparkSubmitArguments#mergeDefaultSparkProperties**

```scala
/**
 * Merge values from the default properties file with those specified through --conf.
 * When this is called, `sparkProperties` is already filled with configs from the latter.
  *  合并配置文件里的默认配置属性和--conf指定的配置属性，在这里可以看出--conf优先级更高.
 */
private def mergeDefaultSparkProperties(): Unit = {
  // Use common defaults file, if not specified by user
  //    如果用户没有指定默认属性配置文件，将使用公用的属性配置文件
  propertiesFile = Option(propertiesFile).getOrElse(Utils.getDefaultPropertiesFile(env))
  // Honor --conf before the defaults file
  defaultSparkProperties.foreach { case (k, v) =>
    if (!sparkProperties.contains(k)) {
      sparkProperties(k) = v
    }
  }
}
```

上面代码中的defaultSparkProperties是一个懒值，它的定义如下：

```scala
//    当前配置文件里的默认属性配置，会在mergeDefaultSparkProperties赋值给sparkProperties
lazy val defaultSparkProperties: HashMap[String, String] = {
  val defaultProperties = new HashMap[String, String]()
  // scalastyle:off println
  if (verbose) SparkSubmit.printStream.println(s"Using properties file: $propertiesFile")
  Option(propertiesFile).foreach { filename =>
    val properties = Utils.getPropertiesFromFile(filename)
    properties.foreach { case (k, v) =>
      defaultProperties(k) = v
    }
    // Property files may contain sensitive information, so redact before printing
    if (verbose) {
      Utils.redact(properties).foreach { case (k, v) =>
        SparkSubmit.printStream.println(s"Adding default property: $k=$v")
      }
    }
  }
  // scalastyle:on println
  defaultProperties
}
```

可以看到这段代码里，是将配置文件的属性读取，然后添加到了defaultProperties。最终是返回作为defaultSparkProperties，该变量会在调用的地方执行初始化，然后在调用的foreach方法中将 属性书写到sparkProperties。这里并没有覆盖掉命令行参数解析里获取的配置。

剩余的几个方法比较简单，不赘述。

###### b.命令提交

参数分析完之后便是各种提交行为的具体处理，以SUBMIT为例进行分析，该过程分两步：

一 通过设置适当的类路径、系统属性和应用程序参数来准备启动环境，以便基于集群管理器和部署模式运行子主类。
二 使用这个启动环境来调用子main类的main方法。

```scala
// 尾递归是指递归调用是函数的最后一个语句，而且其结果被直接返回，这是一类特殊的递归调用。
// 由于递归结果总是直接返回，尾递归比较方便转换为循环，因此编译器容易对它进行优化。
@tailrec
private def submit(args: SparkSubmitArguments, uninitLog: Boolean): Unit = {
  //准备启动环境
  val (childArgs, childClasspath, sparkConf, childMainClass) = prepareSubmitEnvironment(args)

  def doRunMain(): Unit = {
    if (args.proxyUser != null) {
      val proxyUser = UserGroupInformation.createProxyUser(args.proxyUser,
        UserGroupInformation.getCurrentUser())
      try {
        proxyUser.doAs(new PrivilegedExceptionAction[Unit]() {
          override def run(): Unit = {
           // 使用提供的启动环境运行子类的主方法。
            runMain(childArgs, childClasspath, sparkConf, childMainClass, args.verbose)
          }
        })
      } catch {
          ...
          }
      }
    } else {
      runMain(childArgs, childClasspath, sparkConf, childMainClass, args.verbose)
    }
  }
// standalone 集群模式下，有两种提交app的方式
    //   (1) 传统的AKKA网关使用o.a.s.deploy.Client作为封装
    //   (2) Spark 1.3 使用REST-based网关方式，如果master节点不是REST服务节点，spark提交时会
    //       切换到传统的网关模式
    if (args.isStandaloneCluster && args.useRest) {
      try {
        // scalastyle:off println
        printStream.println("Running Spark using the REST application submission protocol.")
        // scalastyle:on println
        doRunMain()
      } catch {
        // 失败的话切换到传统的网关模式
        case e: SubmitRestConnectionException =>
          printWarning(s"Master endpoint ${args.master} was not a REST server. " +
            "Falling back to legacy submission gateway instead.")
          args.useRest = false
          submit(args, false)
      }
    // In all other modes, just run the main class as prepared
    } else {
      doRunMain()
    }
  }
```

最终运行所需的 参数都由prepareSubmitEnvironment负责解析和转换吗，解析的结果包括

* childArgs：子进程运行所需的参数
* childClasspath：子进程的classpath列表
* sparkConf：系统属性映射
* childMainClass：子进程运行时的主类

之后调用runMain方法，该方法除了一些环境设置外，最终会调用解析得到的childMainClass的main方法。

###### c.prepareSubmitEnvironment方法分析

prepareSubmitEnvironment方法体现了SparkSubmit如何帮助底层的集群管理器和部署模式的封装。

* **部署模式为Client时**

  如果传入参数时没有指明deployMode，那么默认的部署模式就是Client模式

  ```scala
  //    设置部署模式，默认情况都是client模式
  var deployMode: Int = args.deployMode match {
    case "client" | null => CLIENT
    case "cluster" => CLUSTER
    case _ => printErrorAndExit("Deploy mode must be either client or cluster"); -1
  }
  ```

  当部署模式为Client时,将childMainClass设置为传入的mainClass，代码如下

  ```scala
  //    客户端模式，会直接运行用户程序的main函数
  //    同时会将用户app jar和任何需要的jar，加入到classpath
  if (deployMode == CLIENT) {
    childMainClass = args.mainClass
    if (localPrimaryResource != null && isUserJar(localPrimaryResource)) {
      childClasspath += localPrimaryResource
    }
    if (localJars != null) { childClasspath ++= localJars.split(",") }
  }
  ```

* **集群管理器为standalone，部署模式为Cluster**

  根据提交方式将childMainClass设置为不同的类，同时将传入的args.mainClass及其参数根据不同的部署模式及新转换并封装到新的主类所需要的参数中

  ```scala
  if (args.isStandaloneCluster) {
    if (args.useRest) {
      childMainClass = REST_CLUSTER_SUBMIT_CLASS
      childArgs += (args.primaryResource, args.mainClass)
    } else {
      // In legacy standalone cluster mode, use Client as a wrapper around the user class
      childMainClass = STANDALONE_CLUSTER_SUBMIT_CLASS
      if (args.supervise) { childArgs += "--supervise" }
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

* 其他模式

  在其他Cluster模式下，都会对执行类进行封装

从上面的分析可以看出，Cilent模式部署时，由于设置的childMainClass为应用程序提交时的主类，因此是直接在提交点执行设置的主类，即mainClass；在Cluster部署模式提交时，会根据具体集群管理器等信息使用相应封装类。

##### 3.SparkContext分析

在Spark源码分析的第一篇博客中的集群部署图中可以看到Driver部分对应了一个SaprkContext实例，因此需要看一下SaprkContext的细节

SaprkContext类是Spark功能的主入口点，一个SparkContext代表了与一个Spark集群的连接，也可用于在该集群上创建RDD，累加器和广播变量。每个JVM只能激活一个SparkContext。您必须在创建新的SparkContext之前停止它。

SparkContext的构建参数的config中的任何设置都会覆盖默认配置以及系统属性。

SparkContext中有一个SparkMasterRegex单例对象，描述集群管理器类型，给出了当前支持的各种集群管理器类型的正则表达式

```scala
/**
 * A collection of regexes for extracting information from the master string.
  *
用于从主字符串中提取信息的正则表达式的集合。
 */
private object SparkMasterRegex {
  // Regular expression used for local[N] and local[*] master formats
  val LOCAL_N_REGEX = """local\[([0-9]+|\*)\]""".r
  // Regular expression for local[N, maxRetries], used in tests with failing tasks
  val LOCAL_N_FAILURES_REGEX = """local\[([0-9]+|\*)\s*,\s*([0-9]+)\]""".r
  // Regular expression for simulating a Spark cluster of [N, cores, memory] locally
  // 模拟Spark集群的本地模式的正则表达式
  val LOCAL_CLUSTER_REGEX = """local-cluster\[\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*]""".r
  // Regular expression for connecting to Spark deploy clusters
  // 连接Spark部署集群的正则表达式
  val SPARK_REGEX = """spark://(.*)""".r
}
```

SparkContext的主要哦流程归纳如下：

1. createSparkEnv：创建Spark执行环境（缓存，映射输出跟踪器等）

   ```scala
   // Create the Spark execution environment (cache, map output tracker, etc)
       _env = createSparkEnv(_conf, isLocal, listenerBus)
       SparkEnv.set(_env)
   ```

2. createTaskScheduler: 创建作业调度器实例

   ```scala
   // Spark在构造SparkContext时就会生成DAGScheduler的实例。
       val (sched, ts) = SparkContext.createTaskScheduler(this, master, deployMode)
       _schedulerBackend = sched
       _taskScheduler = ts
   ```

   TaskScheduler是低层次的任务调度器，负责任务的调度，每个TaskScheduler负责调度一个SparkContext实例中的任务，负责调度上层DAG调度器中每个Stage提交的任务集(TaskSet),并将这些任务集提交到集群运行

3. new DAGScheduler：创建高层stage调度的DAG调度器实例

   ```scala
   _dagScheduler = new DAGScheduler(this)
   ```

#### 二、Local与Local-Cluster部署

在使用Local与Local-Cluster两种Local方式时，不支持以Cluster部署模式提交应用程序：

```scala
//    给出不支持的部署模式，直接退出
(clusterManager, deployMode) match {
...
case (LOCAL, CLUSTER) =>
        printErrorAndExit("Cluster deploy mode is not compatible with master \"local\"")
...       
```

Master URL如果使用以下方式，那么就以本地方式启动Spark：

* local

  最简单的本地模式使用一个线程来运行计算任务，不会重新计算失败的计算任务

  ```scala
  // When running locally, don't try to re-execute tasks on failure.
  val MAX_LOCAL_TASK_FAILURES = 1
  case "local" =>
          val scheduler = new TaskSchedulerImpl(sc, MAX_LOCAL_TASK_FAILURES, isLocal = true)
          // 使用一个线程来运行计算任务
          val backend = new LocalSchedulerBackend(sc.getConf, scheduler, 1)
          scheduler.initialize(backend)
          (backend, scheduler)
  ```

* local[N]或local[*]

  local [*]估计机器上的核心数量; local [N]正好使用N个线程，失败不会重新计算 

  ```scala
  case LOCAL_N_REGEX(threads) =>
          // 获取本机处理器个数
          def localCpuCount: Int = Runtime.getRuntime.availableProcessors()
          // local[*] estimates the number of cores on the machine; local[N] uses exactly N threads.
          val threadCount = if (threads == "*") localCpuCount else threads.toInt
          if (threadCount <= 0) {
            throw new SparkException(s"Asked to run locally with $threadCount threads")
          }
          // 失败不会重新计算 
          val scheduler = new TaskSchedulerImpl(sc, MAX_LOCAL_TASK_FAILURES, isLocal = true)
          val backend = new LocalSchedulerBackend(sc.getConf, scheduler, threadCount)
          scheduler.initialize(backend)
          (backend, scheduler)
  ```

* local[threads, maxFailures]：比上面多出了一个失败重试次数

  ```scala
  case LOCAL_N_FAILURES_REGEX(threads, maxFailures) =>
    // 获取本机处理器个数
    def localCpuCount: Int = Runtime.getRuntime.availableProcessors()
    // local[*, M] means the number of cores on the computer with M failures
    // local[N, M] means exactly N threads with M failures
    val threadCount = if (threads == "*") localCpuCount else threads.toInt
    // 任务最大失败重新计算maxFailures次
    val scheduler = new TaskSchedulerImpl(sc, maxFailures.toInt, isLocal = true)
    val backend = new LocalSchedulerBackend(sc.getConf, scheduler, threadCount)
    scheduler.initialize(backend)
    (backend, scheduler)
  ```

* local-cluster[numSlaves, coresPerSlave, memoryPerSlave]

  本地伪分布模式，因为本地模式下没有集群，因此需要构建一个用于模拟集群的实例new LocalSparkCluster，会运行Master和Worker，numSlaves设置了模拟Worker的数量，coresPerSlave设置了各个Worker所能使用的CPU core数量，memoryPerSlave设置了每个Worker所能使用的内存数，

  ```scala
  case LOCAL_CLUSTER_REGEX(numSlaves, coresPerSlave, memoryPerSlave) =>
    // 检查以确保请求的内存<= memoryPerSlave。否则Spark会挂起。
    val memoryPerSlaveInt = memoryPerSlave.toInt
    if (sc.executorMemory > memoryPerSlaveInt) {
      throw new SparkException(
        "Asked to launch cluster with %d MB RAM / worker but requested %d MB/worker".format(
          memoryPerSlaveInt, sc.executorMemory))
    }
  
    val scheduler = new TaskSchedulerImpl(sc)
    // 在集群中创建一个Spark独立进程，Master和Worker运行在同一个JVM
    val localCluster = new LocalSparkCluster(
      numSlaves.toInt, coresPerSlave.toInt, memoryPerSlaveInt, sc.conf)
    // 启动本地集群
    val masterUrls = localCluster.start()
    // 独立SchedulerBackend
    val backend = new StandaloneSchedulerBackend(scheduler, sc, masterUrls)
    scheduler.initialize(backend)
    // 回调函数
    backend.shutdownCallback = (backend: StandaloneSchedulerBackend) => {
      localCluster.stop()
    }
    (backend, scheduler)
  ```

对于前三种方式，内部实现相同，只有线程和失败重试次数上的区别，第四种local-cluster方式是伪分布模式，实际上是在本地机器模拟分布式环境，除了Master和Worker都运行在本机外，与Standalone模式并无区别。

前三种Local模式SchedulerBackend的实现都是LocalSchedulerBackend：

```scala
// executor, backend, 和 master 运行在同一个 JVM中
private[spark] class LocalSchedulerBackend(
    conf: SparkConf,
    scheduler: TaskSchedulerImpl,
    val totalCores: Int)
```

------------------------------------

具体内部流程如下：

* SparkContext中createTaskScheduler构建TaskScheduler实例，初始化TaskScheduler时同时传入LocalSchedulerBackend

* 调用taskScheduler.start()方法，会调用LocalSchedulerBackend.start()方法

* 在LocalSchedulerBackend.start()方法中会构建一个LocalEndpoint实例，该实例会实例化一个Executor，Executor实例负责具体的任务执行

* 之后TaskScheduler进行作业调度，调用LocalSchedulerBackend.ReviveOffers方法，然后就由该方法执行`localEndpoint.send(ReviveOffers)`，发送ReviveOffers消息

* 最终在LocalEndpoint实例处理ReviveOffers消息时启动Task，最终的Task启动代码如下：

  ```scala
  def reviveOffers() {
      val offers = IndexedSeq(new WorkerOffer(localExecutorId, localExecutorHostname, freeCores))
      for (task <- scheduler.resourceOffers(offers).flatten) {
        // 在Executor中会使用线程池方式调度任务，而对应的作业调度是通过
        // 判断当前可用cores数量是否符合每个任务所需的Cores个数
        // 符合条件时更新当前可用Cores数freeCores， 然后启动Task
        freeCores -= scheduler.CPUS_PER_TASK
        executor.launchTask(executorBackend, task)
      }
    }
  ```

  三种Local部署模式图：

  ![屏幕快照 2018-10-15 下午9.15.22.png](https://i.loli.net/2018/10/15/5bc492fc6820b.png)

