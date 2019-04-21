---
title: fink官网学习笔记——DataStream API
date: 2019-04-20 20:11:17
tags: 大数据
---

The data streams are initially created from various sources (e.g., message queues, socket streams, files). Results are returned via sinks, which may for example write the data to files, or to standard output (for example the command line terminal). 

#### 一、数据源

可以通过StreamExecutionEnvironment.addSource(sourceFunction)来添加数据源，Flink内嵌了很多实现好的数据源，也可以通过实现SourceFunction接口创建非并行输入的源，或者实现ParallelSourceFunction或者继承RichParallelSourceFunction类实现并行的源。

<!-- more--> 

StreamExecutionEnvironment预定义的源包括：

* 基于文件的：

  * `readTextFile(path)` - Reads text files, i.e. 遵循TextInputFormat规范的文件，并将它们逐行作为字符串返回。

  * `readFile(fileInputFormat, path)` - Reads (once) files as dictated by the specified file input format.

  * `readFile(fileInputFormat, path, watchType, interval, pathFilter, typeInfo) `- This is the method called internally by the two previous ones. It reads files in the `path` based on the given `fileInputFormat`. Depending on the provided `watchType`, this source may periodically monitor (every `interval` ms) the path for new data (`FileProcessingMode.PROCESS_CONTINUOUSLY`), or process once the data currently in the path and exit (`FileProcessingMode.PROCESS_ONCE`). Using the `pathFilter`, the user can further exclude files from being processed.

    > 在底层系统中，Flink将文件读取过程分割成两个子任务，分别叫做**目录监控**和**数据读取**，每个任务由独立的实体实现。目录监控是由一个单线程任务执行，而数据读取是由多个任务并发执行。其中，读取任务的并发度与job的并发度相同。单个监视任务的作用是扫描目录（定期或仅一次，具体取决于watchType），找到要处理的文件，将它们分成splits，并将这些splits分配给下游读取器。读取器将读取实际数据的人。 每个split仅由一个读取器读取，读取器可以逐个读取多个splits。

    > 值得注意的是：
    >
    > * 如果watchType设置为FileProcessingMode.PROCESS_CONTINUOUSLY，当一个文件被修改，它的所有内容都会被重新处理。这将破坏"exactly-once"语义。
    > * 如果watchType设置为FileProcessingMode.PROCESS_ONCE，源扫描路径一次并退出，而不等待读者完成读取文件内容。 当然读者将继续阅读，直到读取所有文件内容。 在该点之后关闭源将导致不再有检查点。 这可能会导致节点故障后恢复速度变慢，因为作业将从上一个检查点恢复读取。

* 基于Socket的：
  * socketTextStream

* 基于容器的：

  * fromCollection(Collection) - Creates a data stream from the Java Java.util.Collection. 容器中的所有元素必须具有相同的数据类型
  * fromCollection(Iterator, Class) - Creates a data stream from an iterator. The class specifies the data type of the elements returned by the iterator.
  * fromElement(T …) - Creates a data stream from the given sequence of objects. 所有元素必须具有相同的数据类型

  * fromParallelCollection(SplittableIterator, Class) -  Creates a data stream from an iterator, in parallel. The class specifies the data type of the elements returned by the iterator.
  * generateSequence(from, to) -  Generates the sequence of numbers in the given interval, in parallel.

* 自定义源：
  * `addSource` -Attach a new source function. For example, to read from Apache Kafka you can use `addSource(new FlinkKafkaConsumer08<>(...))`.

#### 二、DataStream Transformations

>  表格：https://ci.apache.org/projects/flink/flink-docs-release-1.8/dev/stream/operators/index.html

#### 三、DataSink

Data sinks consume DataStreams and forward them to files, sockets, external systems, or print them. Flink comes with a variety of built-in output formats that are encapsulated behind operations on the DataStreams：

* `writeAsText()` / `TextOutputFormat` - Writes elements line-wise as Strings. The Strings are obtained by calling the *toString()*method of each element.
* `writeAsCsv(...)` / `CsvOutputFormat` - Writes tuples as comma-separated value files. Row and field delimiters are configurable. The value for each field comes from the *toString()* method of the objects.
* `print()` / `printToErr()` - Prints the *toString()* value of each element on the standard out / standard error stream. Optionally, a prefix (msg) can be provided which is prepended to the output. This can help to distinguish between different calls to *print*. If the parallelism is greater than 1, the output will also be prepended with the identifier of the task which produced the output.
* `writeUsingOutputFormat()` / `FileOutputFormat` - Method and base class for custom file outputs. Supports custom object-to-bytes conversion.
* `writeToSocket` - Writes elements to a socket according to a `SerializationSchema`
* `addSink` - Invokes a custom sink function. Flink comes bundled with connectors to other systems (such as Apache Kafka) that are implemented as sink functions.

Flink中的write*()方法主要用于调试，它们不参与Flink的检查点机制，这意味着这些函数拥有at-least-once语义，刷向目标系统的数据取决于OutputFormat的实现， This means that not all elements send to the OutputFormat are immediately showing up in the target system. Also, in failure cases, those records might be lost.

为了可靠性，实现exactly-once语义输出流到文件系统，应该使用flink-connector-filesystem。通过addSink(...)方法的自定义实现可以参与Flink的精确一次语义检查点。

#### 四、迭代

迭代流程序实现步进功能并将其嵌入到IterativeStream中。 由于DataStream程序可能永远不会完成，因此没有最大迭代次数。 相反，需要指定流的哪个部分反馈到迭代，哪个部分使用split转换或filter向下游转发。 

首先，我们定义一个IterativeStream

```java
IterativeStream<Integer> iteration = input.iterate();
```

然后，我们使用一系列转换指定将在循环内执行的逻辑（这里是一个简单的映射转换）

```java
DataStream<Integer> iterationBody = iteration.map(/* this is executed many times */);
```

要关闭迭代并定义迭代尾部，调用IterativeStream的closeWith（feedbackStream）方法。 传给closeWith函数的DataStream将从迭代头开始继续迭代。 常见的模式是使用过滤器来分离反馈的流的一部分和向前传播的流的一部分。例如， 这些filter可以定义“终止”逻辑，允许元件向下游传播而不是继续迭代。

```java
iteration.closeWith(iterationBody.filter(/* one part of the stream */));
DataStream<Integer> output = iterationBody.filter(/* some other part of the stream */);
```

#### 五、执行参数

StreamExecutionEnvironment中的ExecutionConfig实例允许为每个job指定运行时配置,

```java
StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
ExecutionConfig executionConfig = env.getConfig();
```

ExecutionConfig有如下配置选项：

* `enableClosureCleaner()` / `disableClosureCleaner()`.默认情况下闭包清理器是启用的。 闭包清理器删除Flink程序中匿名函数的不需要的对外围类引用。 禁用闭包清除器后，可能会发生匿名用户函数引用不可序列化的外围类。 这将导致序列化器出现异常。

* `getParallelism()` / `setParallelism(int parallelism)` Set the default parallelism for the job.
* `getMaxParallelism()` / `setMaxParallelism(int parallelism)` Set the default maximum parallelism for the job.此设置确定最大并行度并指定动态缩放的上限。
* `getExecutionMode()` / `setExecutionMode()`默认执行模式是PIPELINED。执行模式定义数据交换是以批处理还是以流水线方式执行。
* `enableForceKryo()` / **disableForceKryo.** Kryo不是默认的序列化工具，需要手工设置
* `enableForceAvro()` / **disableForceAvro().**
* `enableObjectReuse()` / **disableObjectReuse().**默认情况下。Flink中的对象是不可重用的，允许崇勇对象可能会有更好的性能。不过当操作的用户代码功能不知道此行为时，可能会导致错误。
* **enableSysoutLogging()** / `disableSysoutLogging()`.JobManager默认会将状态更新输出到标准输出，这个设置可以去取消输出日志
* `getGlobalJobParameters()` / `setGlobalJobParameters()`.This method allows users to set custom objects as a global configuration for the job. Since the `ExecutionConfig` is accessible in all user defined functions, this is an easy method for making configuration globally available in a job.

* `addDefaultKryoSerializer(Class<?> type, Serializer<?> serializer)` Register a Kryo serializer instance for the given `type`.
* `addDefaultKryoSerializer(Class<?> type, Class<? extends Serializer<?>> serializerClass)` Register a Kryo serializer class for the given `type`.
* `registerTypeWithKryoSerializer(Class<?> type, Serializer<?> serializer)` Register the given type with Kryo and specify a serializer for it. By registering a type with Kryo, the serialization of the type will be much more efficient.
* `registerKryoType(Class<?> type)` If the type ends up being serialized with Kryo, then it will be registered at Kryo to make sure that only tags (integer IDs) are written. If a type is not registered with Kryo, its entire class-name will be serialized with every instance, leading to much higher I/O costs.
* `registerPojoType(Class<?> type)` Registers the given type with the serialization stack. If the type is eventually serialized as a POJO, then the type is registered with the POJO serializer. If the type ends up being serialized with Kryo, then it will be registered at Kryo to make sure that only tags are written. If a type is not registered with Kryo, its entire class-name will be serialized with every instance, leading to much higher I/O costs.

##### 容错性

关于容错性后面会专开一帖

##### 控制延迟

默认情况下。为了防止网络拥塞，数据元素并不是在网络中一个接一个的被转换，而是被缓存了起来。缓存的大小(在多台机器中传输)可以通过配置文件设置。尽管配置缓存可以优化吞吐量，但是当输入流不够快时，可能导致延迟问题。为了控制延迟和吞吐量的平衡，可以在执行环境或独立操作符中配置`env.setBufferTimeout(timeoutMillis)`来设置缓存等待填满的最大等待时间。超时之后，就算缓存未满也会将数据元素发送出去，默认超市时间设置为100ms。

使用方式：

```java
LocalStreamEnvironment env = StreamExecutionEnvironment.createLocalEnvironment();
env.setBufferTimeout(timeoutMillis);

env.generateSequence(1,10).map(new MyMapper()).setBufferTimeout(timeoutMillis);
```

想要最大化吞吐量，设置setBufferTimeout(-1)，此时只有当缓存被填满之后才会发出数据；要最小化延迟，设置timeout为0.应避免缓冲区超时为0，因为它可能导致严重的性能下降，一般设置为接近0的数。

#### 六、调试

Before running a streaming program in a distributed cluster, it is a good idea to make sure that the implemented algorithm works as desired. Hence, implementing data analysis programs is usually an incremental process of checking results, debugging, and improving.

##### Local Execution Environment（本地执行环境）

LocalStreamEnvironment在其创建的同一JVM进程中启动Flink系统。如果从IDE启动LocalEnvironment，则可以在代码中设置断点并轻松调试程序。

```java
final StreamExecutionEnvironment env = StreamExecutionEnvironment.createLocalEnvironment();
DataStream<String> lines = env.addSource(/* some source */);
// build your program

env.execute();
```

##### Collection Data Sources

为了方便调试，Flink提供了基于collection的特殊数据源。一旦程序经过测试，源和接收器可以很容易地被读取/写入外部系统的源和接收器替换。

```java
final StreamExecutionEnvironment env = StreamExecutionEnvironment.createLocalEnvironment();

// Create a DataStream from a list of elements
DataStream<Integer> myInts = env.fromElements(1, 2, 3, 4, 5);

// Create a DataStream from any Java collection
List<Tuple2<String, Integer>> data = ...
DataStream<Tuple2<String, Integer>> myTuples = env.fromCollection(data);

// Create a DataStream from an Iterator
Iterator<Long> longIt = ...
DataStream<Long> myLongs = env.fromCollection(longIt, Long.class);
```

> 作为Source的Collection<u>中的数据类型需要是可序列化的，而且collection的源是不可并行的

##### Iterator Data Sink

Flink还提供了一个接收器来收集DataStream结果，以便进行测试和调试。 它可以使用如下：

```java
import org.apache.flink.streaming.experimental.DataStreamUtils

DataStream<Tuple2<String, Integer>> myResult = ...
Iterator<Tuple2<String, Integer>> myOutput = DataStreamUtils.collect(myResult)
```

