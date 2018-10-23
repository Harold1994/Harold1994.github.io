---
title: Spark_2.3.0源码分析——10_Spark的Shuffle机制
date: 2018-10-21 14:27:57
tags: [大数据, Spark]
---

### 一、Hadoop MapReduce框架中的shuffle框架

![屏幕快照 2018-10-21 下午3.19.15.png](https://i.loli.net/2018/10/21/5bcc287ec7a98.png)

Map阶段负责准备数据，Reduce阶段则读取Map阶段所准备的数据，然后做进一步处理。即Map阶段实现Shuffle过程中的数据持久化，而Reduce阶段实现Shuffle过程中的数据读取。

<!-- more-->

### 二、Spark Shuffle框架

用户可以通过自定义ShuffleManager接口，并通过制定的配置属性进行设置，也可以通过该配置属性指定Spark已经支持的ShuffleManager具体实现自类。

SparkEnv源码中可以看到设置的配置属性：

```scala
// 短格式命名指定所使用的ShuffleManager
val shortShuffleMgrNames = Map(
  // 基于sort的Shuffle实现方式，也是默认的Shuffle方式，每个Mapper阶段的Task分别生成数据文件和索引文件
  "sort" -> classOf[org.apache.spark.shuffle.sort.SortShuffleManager].getName,
  "tungsten-sort" -> classOf[org.apache.spark.shuffle.sort.SortShuffleManager].getName)
// 指定shuffleManager的配置属性
// 默认为sort
val shuffleMgrName = conf.get("spark.shuffle.manager", "sort")
val shuffleMgrClass =
  shortShuffleMgrNames.getOrElse(shuffleMgrName.toLowerCase(Locale.ROOT), shuffleMgrName)
val shuffleManager = instantiateClass[ShuffleManager](shuffleMgrClass)
```

ShuffleManager是Spark Shuffle系统提供的一个可插拔式接口，在Driver和每个Executor实例化的过程中，都会创建一个ShuffleManager，用于管理块数据，提供集群块数据的读写，包括本地读写和远程读取。 

#### 1. ShuffleManager代码

```scala
/**
 * Pluggable interface for shuffle systems. A ShuffleManager is created in SparkEnv on the driver
 * and on each executor, based on the spark.shuffle.manager setting. The driver registers shuffles
 * with it, and executors (or tasks running locally in the driver) can ask to read and write data.
 *
 * NOTE: this will be instantiated by SparkEnv so its constructor can take a SparkConf and
 * boolean isDriver as parameters.
 */
private[spark] trait ShuffleManager {

  /**
   * Register a shuffle with the manager and obtain a handle for it to pass to tasks.
    * 在Driver端向ShuffleManager注册一个Shuffle，获取一个Handle
    * 在具体Task中会通过该Handler来读写数据
   */
  def registerShuffle[K, V, C](
      shuffleId: Int,
      numMaps: Int,
      dependency: ShuffleDependency[K, V, C]): ShuffleHandle

  /** Get a writer for a given partition. Called on executors by map tasks.
    * 获取给定分区所使用的shuffleWriter，该方法在Executor上执行各个Map任务时调用。
    * */
  def getWriter[K, V](handle: ShuffleHandle, mapId: Int, context: TaskContext): ShuffleWriter[K, V]

  /**
   * Get a reader for a range of reduce partitions (startPartition to endPartition-1, inclusive).
   * Called on executors by reduce tasks.
    * 获取在Reduce阶段读取分区的ShuffleReader，对应的分区由[startPartition,endPartition-1]决定
   */
  def getReader[K, C](
      handle: ShuffleHandle,
      startPartition: Int,
      endPartition: Int,
      context: TaskContext): ShuffleReader[K, C]

  /**
   * Remove a shuffle's metadata from the ShuffleManager.
   * @return true if the metadata removed successfully, otherwise false.
   */
  def unregisterShuffle(shuffleId: Int): Boolean

  /**
   * Return a resolver capable of retrieving shuffle block data based on block coordinates.
    * 返回一个能够根据块坐标获取Shuffle块数据的ShuffleBlockResolver。
   */
  def shuffleBlockResolver: ShuffleBlockResolver

  /** Shut down this ShuffleManager. */
  def stop(): Unit
}
```

#### 2. ShuffleHandle

ShuffleHandle用于记录Task与Shuffle相关的一些元数据，同时可以作为不同具体Shuffle实现机制的一种标志信息，控制不同具体实现子类的选择等。

```scala
abstract class ShuffleHandle(val shuffleId: Int) extends Serializable {}
```

#### 3. ShuffleWriter

给出任务在输出时的记录具体写的方法

```scala
/**
 * Obtained inside a map task to write out records to the shuffle system.
 */
private[spark] abstract class ShuffleWriter[K, V] {
  /** Write a sequence of records to this task's output */
  @throws[IOException]
  def write(records: Iterator[Product2[K, V]]): Unit

  /** Close this writer, passing along whether the map completed */
  def stop(success: Boolean): Option[MapStatus]
}
```

#### 4. ShuffleReader

```scala
/**
 * Obtained inside a reduce task to read combined records from the mappers.
 */
private[spark] trait ShuffleReader[K, C] {
  /** Read the combined key-values for this reduce task */
  // 从上一阶段的输出中读取记录
  def read(): Iterator[Product2[K, C]]
  }
```

#### 5. ShuffleBlockResolver

```scala
/**
 * Implementers of this trait understand how to retrieve block data for a logical shuffle block
 * identifier (i.e. map, reduce, and shuffle). Implementations may use files or file segments to
 * encapsulate shuffle data. This is used by the BlockStore to abstract over different shuffle
 * implementations when shuffle data is retrieved.
 */
// 该特质的具体实现子类知道如何通过一个逻辑Shuffle块表示信息来
// 获取一个块数据。具体实现可以使用文件或者文件段来封装Shuffle的数据
// 在BlockStore使用
trait ShuffleBlockResolver {
  type ShuffleId = Int

  /**
   * Retrieve the data for the specified block. If the data for that block is not available,
   * throws an unspecified exception.
   */
  def getBlockData(blockId: ShuffleBlockId): ManagedBuffer

  def stop(): Unit
}
```

### 三、Shuffle的注册

当构架一个宽依赖的RDD时，该RDD需要向ShuffleManager注册，这样做是因为DAG调度器中的stage是根据宽依赖进行划分的，而对应的宽依赖类目前只有ShuffleDependency

```scala
class ShuffleDependency[K: ClassTag, V: ClassTag, C: ClassTag](
    @transient private val _rdd: RDD[_ <: Product2[K, V]],
    val partitioner: Partitioner,
    val serializer: Serializer = SparkEnv.get.serializer,
    val keyOrdering: Option[Ordering[K]] = None,
    val aggregator: Option[Aggregator[K, V, C]] = None,
    val mapSideCombine: Boolean = false)
  extends Dependency[Product2[K, V]] {

  override def rdd: RDD[Product2[K, V]] = _rdd.asInstanceOf[RDD[Product2[K, V]]]

  private[spark] val keyClassName: String = reflect.classTag[K].runtimeClass.getName
  private[spark] val valueClassName: String = reflect.classTag[V].runtimeClass.getName
  // Note: It's possible that the combiner class tag is null, if the combineByKey
  // methods in PairRDDFunctions are used instead of combineByKeyWithClassTag.
  private[spark] val combinerClassName: Option[String] =
    Option(reflect.classTag[C]).map(_.runtimeClass.getName)
  // 针对特定rdd，每个shuffleId都是唯一的
  // 获取新的shuffleId
  val shuffleId: Int = _rdd.context.newShuffleId()
  // 向shuffleManager注册Shuffle信息，获取ShuffleHandle
  val shuffleHandle: ShuffleHandle = _rdd.context.env.shuffleManager.registerShuffle(
    shuffleId, _rdd.partitions.length, this)
  // Shuffle数据其清理器的设置
  _rdd.sparkContext.cleaner.foreach(_.registerShuffleForCleanup(this))
}
```

### 四、Shuffle读写数据

##### 1. Shuffle写数据源码

​	Spark中一个作业可以根据宽依赖切分stage，在Stage中，相应的Task也包含两种，ShuffleMapTask和ResultTask。其中，一个ShuffleMapTask会基于ShuffleDependency中指定的分区器将一个RDD的元素拆分到多个bucket中，此时通过ShuffleManager的getWriter接口来获取数据与bucket的映射关系，而ResultTask对应一个将输出返回给应用程序Driver端的Task，在该Task执行过程中，最终都会调用到RDD的compute对内部数据进行计算，而在带有ShuffleDependency的RDD中，在compute计算时，会通过ShuffleManager的getReader接口获取上一个Stage的Shuffle输出结果来作为本次Task的输入数据。

* org.apache.spark.scheduler.ShuffleMapTask#runTask

  ```scala
  override def runTask(context: TaskContext): MapStatus = {
    ...
    var writer: ShuffleWriter[Any, Any] = null
    try {
      // 先从SparkEnv获取shuffleManager
      val manager = SparkEnv.get.shuffleManager
      // 从ShuffleDependency中获取注册到shuffleManager时得到的shuffleHandle
      // 依据shuffleHandle和当前的Task对应的分区ID，获取ShuffleWriter
      writer = manager.getWriter[Any, Any](dep.shuffleHandle, partitionId, context)
      // 写入当前分区的数据
      writer.write(rdd.iterator(partition, context).asInstanceOf[Iterator[_ <: Product2[Any, Any]]])
      // 关闭writer
      writer.stop(success = true).get
    } catch {
    ...
  ```

##### 2. Shuffle读数据源码

* org.apache.spark.rdd.CoGroupedRDD#compute

  ```scala
  override def compute(s: Partition, context: TaskContext): Iterator[(K, Array[Iterable[_]])] = {
    val split = s.asInstanceOf[CoGroupPartition]
    val numRdds = dependencies.length
  
    // A list of (rdd iterator, dependency number) pairs
    val rddIterators = new ArrayBuffer[(Iterator[Product2[K, Any]], Int)]
    for ((dep, depNum) <- dependencies.zipWithIndex) dep match {
      case oneToOneDependency: OneToOneDependency[Product2[K, Any]] @unchecked =>
        val dependencyPartition = split.narrowDeps(depNum).get.split
        // Read them from the parent
        val it = oneToOneDependency.rdd.iterator(dependencyPartition, context)
        rddIterators += ((it, depNum))
  
      case shuffleDependency: ShuffleDependency[_, _, _] =>
        // Read map outputs of shuffle
        // 先从SparkEnv获取shuffleManager，然后根据shuffleHandle和分区Id获取ShuffleReader
        val it = SparkEnv.get.shuffleManager
          .getReader(shuffleDependency.shuffleHandle, split.index, split.index + 1, context)
          .read()
        rddIterators += ((it, depNum))
    }
     ...
  ```

可以看到,宽依赖的RDD的compute操作中，最终是通过SparkEnv中的ShuffleManager实例的getReader方法，获取数据读取器的，然后再次调用读取器的read方法读取指定分区范围的Shuffle数据。

目前实现了ShuffleReader特质的具体子类只有BlockStoreShuffleReader：

BlockStoreShuffleReader通过从其他结点上请求shuffle数据来接收并读取指定范围[起始分区, 结束分区),关键实现父类的read()方法:

```scala
/** Read the combined key-values for this reduce task */
// 为该Reduce任务读取并合并key-values值
override def read(): Iterator[Product2[K, C]] = {
  // 真正的数据Iterator读取是通过ShuffleBlockFetcherIterator来完成的
  val wrappedStreams = new ShuffleBlockFetcherIterator(
    context,
    blockManager.shuffleClient,
    blockManager,
    // 当ShuffleMapTask完成后注册到mapOutputTracker的元数据信息
    // 同样会通过mapOutputTracker来获取，在此之前还指定了获取的分区范围
    // 通过该方法的返回值类型
    mapOutputTracker.getMapSizesByExecutorId(handle.shuffleId, startPartition, endPartition),
    serializerManager.wrapStream,
    // Note: we use getSizeAsMb when no suffix is provided for backwards compatibility
    // 默认读取时的数据大小限制为48M,对应后续并行的读取，可以避免目标机器占用过多带宽，同时也可以启动并行机制，加快读取速度
    SparkEnv.get.conf.getSizeAsMb("spark.reducer.maxSizeInFlight", "48m") * 1024 * 1024,
    SparkEnv.get.conf.getInt("spark.reducer.maxReqsInFlight", Int.MaxValue),
    SparkEnv.get.conf.get(config.REDUCER_MAX_BLOCKS_IN_FLIGHT_PER_ADDRESS),
    SparkEnv.get.conf.get(config.MAX_REMOTE_BLOCK_SIZE_FETCH_TO_MEM),
    SparkEnv.get.conf.getBoolean("spark.shuffle.detectCorrupt", true))

  val serializerInstance = dep.serializer.newInstance()

  // Create a key/value iterator for each stream
  // 在此针对前面获取的各个数据块唯一标识Id信息及其对应的输入流进行处理
  val recordIter = wrappedStreams.flatMap { case (blockId, wrappedStream) =>
    // Note: the asKeyValueIterator below wraps a key/value iterator inside of a
    // NextIterator. The NextIterator makes sure that close() is called on the
    // underlying InputStream when all records have been read.
    serializerInstance.deserializeStream(wrappedStream).asKeyValueIterator
  }

  // Update the context task metrics for each record read.
  val readMetrics = context.taskMetrics.createTempShuffleReadMetrics()
  // 用CompletionIterator包装recordIter，这样可以统计总的record数量
  // 在遍历iterator结束后会调用mergeShuffleReadMetrics
  val metricIter = CompletionIterator[(Any, Any), Iterator[(Any, Any)]](
    recordIter.map { record =>
      readMetrics.incRecordsRead(1)
      record
    },
    context.taskMetrics().mergeShuffleReadMetrics())

  // An interruptible iterator must be used here in order to support task cancellation
  val interruptibleIter = new InterruptibleIterator[(Any, Any)](context, metricIter)
  // 对读取到的数据进行聚合处理
  val aggregatedIter: Iterator[Product2[K, C]] = if (dep.aggregator.isDefined) {
    // 如果设置Map端聚合操作，则对读取到的聚合结果进行聚合
    // 此时的聚合操作与数据类型和Map端未做优化时是不同的
    if (dep.mapSideCombine) {
      // We are reading values that are already combined
      val combinedKeyValuesIterator = interruptibleIter.asInstanceOf[Iterator[(K, C)]]
      // 针对Map端各分区对Key进行合并后的结果再聚合
      // Map的合并可以减少网络传输数据量
      dep.aggregator.get.combineCombinersByKey(combinedKeyValuesIterator, context)
    } else {
      // We don't know the value type, but also don't care -- the dependency *should*
      // have made sure its compatible w/ this aggregator, which will convert the value
      // type to the combined type C
      val keyValuesIterator = interruptibleIter.asInstanceOf[Iterator[(K, Nothing)]]
      // 针对未合并的keyValues的值进行聚合
      dep.aggregator.get.combineValuesByKey(keyValuesIterator, context)
    }
  } else {
    require(!dep.mapSideCombine, "Map-side combine without Aggregator specified!")
    interruptibleIter.asInstanceOf[Iterator[Product2[K, C]]]
  }

  // Sort the output if there is a sort ordering defined.
  // 提供针对分区内的数据进行排序的标识
  dep.keyOrdering match {
    case Some(keyOrd: Ordering[K]) =>
      // Create an ExternalSorter to sort the data.
      // 减少内存开销，引入外部排序
      val sorter =
        new ExternalSorter[K, C, C](context, ordering = Some(keyOrd), serializer = dep.serializer)
      sorter.insertAll(aggregatedIter)
      context.taskMetrics().incMemoryBytesSpilled(sorter.memoryBytesSpilled)
      context.taskMetrics().incDiskBytesSpilled(sorter.diskBytesSpilled)
      context.taskMetrics().incPeakExecutionMemory(sorter.peakMemoryUsedBytes)
      CompletionIterator[Product2[K, C], Iterator[Product2[K, C]]](sorter.iterator, sorter.stop())
    case None =>
      aggregatedIter
  }
```

ShuffleBlockFetcherIterator是用来获取本地或者远程块的，继承自Iterator类，在构造体中调用了initialize()方法，该方法会根据数据块所在位置分别进行读取：

```scala
private[this] def initialize(): Unit = {
  // Add a task completion callback (called in both success case and failure case) to cleanup.
  context.addTaskCompletionListener(_ => cleanup())

  // Split local and remote blocks.
  // 本地数据和远程数据的读取方式不一样，因此先进行拆分
  // 拆封时会考虑一次获取的数据大小和并行数
  // 最后将剩余不足该大小的数据也封装为一个请求
  val remoteRequests = splitLocalRemoteBlocks()
  // Add the remote requests into our queue in a random order
  // 存入需要远程读取的数据块请求信息
  fetchRequests ++= Utils.randomize(remoteRequests)
  assert ((0 == reqsInFlight) == (0 == bytesInFlight),
    "expected reqsInFlight = 0 but found reqsInFlight = " + reqsInFlight +
    ", expected bytesInFlight = 0 but found bytesInFlight = " + bytesInFlight)

  // Send out initial requests for blocks, up to our maxBytesInFlight
  // 发送数据获取请求
  fetchUpToMaxBytes()

  val numFetches = remoteRequests.size - fetchRequests.size
  logInfo("Started " + numFetches + " remote fetches in" + Utils.getUsedTimeMs(startTime))

  // Get Local Blocks
  // 获取本地数据
  fetchLocalBlocks()
  logDebug("Got local blocks in " + Utils.getUsedTimeMs(startTime))
}
```

和Hadoop一样，Spark计算框架也是基于数据本地性，即激动计算而不是移动数据的原则，因此在获取数据时，会尽量从本地读取已有数据块，然后再远程读取。数据块的本地性是通过ShuffleBlockFetcherIterator实例构建时所传入的位置信息来判断的，`blocksByAddress: Seq[(BlockManagerId, Seq[(BlockId, Long)])]`由mapOutputTracker.getMapSizesByExecutorId获得，BlockManagerId是BlockManager的唯一标识信息，BlockId是数据块的唯一信息。

### 五、 基于Sort的Shuffle

基于Sort的Shuffle过程根据分区Id进行排序，然后输出到单个数据文件中，并且同时生成对应的索引文件。在Reduce端获取数据时，会根据该索引文件从数据文件中获取他所需要的数据。

#### 1. 基于Sort的Shuffle内核

​	在基于Sort的Shuffle过程中，sort体现在输出的数据会根据目标的分区Id(即带Shuffle过程的目标RDD中各个分区的Id值)进行排序，然后写入一个单独的Map端输出文件中。相应的，各个分区内部数据并不会再根据Key进行排序。除非调用带排序目的方法，在方法中指定Key值的Ordering实例才会在分区内根据该Ordering实例对数据进行排序。当Map端输出数据超出内训容纳大小时，会将各个排序结果溢出到磁盘上，最后再将这些Spill文件合并到一个最终的文件中。

​	在本博客第二部分Spark Shuffle框架的shuffleManager实例化代码中可以发现,sort与tungsten-sort对应的具体实现子类都是org.apache.spark.shuffle.sort.SortShuffleManager，也就是基于Sort的shuffle实现机制与使用tungsten项目的Shuffle实现机制都是通过SortShuffleManager类来提供接口，两种实现机制的区别在于该类中使用了不同的Shuffle数据写入器。

​	SortShuffleManager根据内部采用的不同实现细节，对应有两种不同的构建 Map端文件输出的写方式，分为序列化排序方式与反序列化排序方式。

* Serialized sorting:适用于以下三种情况：
  * shuffle依赖项不指定聚合或输出顺序。
  * shuffle序列化器支持序列化值的重新定位(目前由KryoSerializer和Spark SQL的自定义序列化器支持)。
  * shuffle产生的输出分区不到16777216个。

* Deserialized sorting：其他情况

基于Sort的Shuffle实现机制，具体的Writer的选择与注册得到的ShuffleHandle类型有关：

```scala
/**
 * Obtains a [[ShuffleHandle]] to pass to tasks.
 */
override def registerShuffle[K, V, C](
    shuffleId: Int,
    numMaps: Int,
    dependency: ShuffleDependency[K, V, C]): ShuffleHandle = {
  //
  if (SortShuffleWriter.shouldBypassMergeSort(conf, dependency)) {
    // If there are fewer than spark.shuffle.sort.bypassMergeThreshold partitions and we don't
    // need map-side aggregation, then write numPartitions files directly and just concatenate
    // them at the end. This avoids doing serialization and deserialization twice to merge
    // together the spilled files, which would happen with the normal code path. The downside is
    // having multiple files open at a time and thus more memory allocated to buffers.
    // 如果当前分区个数少于设置的配置属性：spark.shuffle.sort.bypassMergeThreshold
    // 此时可以直接写文件，最后再将文件合并
    new BypassMergeSortShuffleHandle[K, V](
      shuffleId, numMaps, dependency.asInstanceOf[ShuffleDependency[K, V, V]])
  } else if (SortShuffleManager.canUseSerializedShuffle(dependency)) {
    // Otherwise, try to buffer map outputs in a serialized form, since this is more efficient:
    new SerializedShuffleHandle[K, V](
      shuffleId, numMaps, dependency.asInstanceOf[ShuffleDependency[K, V, V]])
  } else {
    // Otherwise, buffer map outputs in a deserialized form:
    new BaseShuffleHandle(shuffleId, numMaps, dependency)
  }
}
```

#### 2. 基于Sort的Shuffle写数据的源代码分析

基于Sort的Shuffle实现机制中相关的ShuffleManager包含BaseShuffleHandle和BypassMergeSortShuffleHandle，对应的Shuffle数据写入器类型的相关代码参考getWriter方法：

```scala
override def getWriter[K, V](
    handle: ShuffleHandle,
    mapId: Int,
    context: TaskContext): ShuffleWriter[K, V] = {
  // numMapsForShuffle是一个ConcurrentHashMap，存放（shuffleId，numMaps）对
  numMapsForShuffle.putIfAbsent(
    handle.shuffleId, handle.asInstanceOf[BaseShuffleHandle[_, _, _]].numMaps)
  val env = SparkEnv.get
  // 根据ShuffleHandle类型构建具体数据写入器
  handle match {
    case unsafeShuffleHandle: SerializedShuffleHandle[K @unchecked, V @unchecked] =>
      new UnsafeShuffleWriter(
        env.blockManager,
        shuffleBlockResolver.asInstanceOf[IndexShuffleBlockResolver],
        context.taskMemoryManager(),
        unsafeShuffleHandle,
        mapId,
        context,
        env.conf)
      
    case bypassMergeSortHandle: BypassMergeSortShuffleHandle[K @unchecked, V @unchecked] =>
      // 如果是BypassMergeSortShuffleHandle，返回BypassMergeSortShuffleWriter
      new BypassMergeSortShuffleWriter(
        env.blockManager,
        shuffleBlockResolver.asInstanceOf[IndexShuffleBlockResolver],
        bypassMergeSortHandle,
        mapId,
        context,
        env.conf)
    // 如果是其他Handle，返回SortShuffleWriter
    case other: BaseShuffleHandle[K @unchecked, V @unchecked, _] =>
      new SortShuffleWriter(shuffleBlockResolver, other, mapId, context)
  }
}
```

对应构建的三种数据写入器中都是通过shuffleBlockResolver对逻辑数据块和物理数据块的映射进行解析，该变量使用的是IndexShuffleBlockResolver解析类。

##### a. BypassMergeSortShuffleWriter

BypassMergeSortShuffleWriter为每个Reduce端的任务构建一个输出文件，将输入的每条记录分别写入各自对应的文件中，并在最后讲这些基于各个分区的文件合并成一个输出文件。这种方式在Reduce端任务较多时不适用，因为会打开太多的文件流和序列化器，因此只有满足如下条件时才可以使用该写入器：

* 不能指定Ordering
* 不能指定聚合器
* 分区个数小于spark.shuffle.sort.bypassMergeThreshold

```scala
@Override
public void write(Iterator<Product2<K, V>> records) throws IOException {
  // 为每个Reduce端的分区打开的DiskBlockObjectWriter存放于partitionWriters
  // 需要根据具体Reduce端的分区数构建
  assert (partitionWriters == null);
  if (!records.hasNext()) {
    partitionLengths = new long[numPartitions];
    // 初始化索引文件的内容，此时对应各个分区的数据量或偏移量需要在后续获取分区的真实数据量时重写
    shuffleBlockResolver.writeIndexFileAndCommit(shuffleId, mapId, partitionLengths, null);
    mapStatus = MapStatus$.MODULE$.apply(blockManager.shuffleServerId(), partitionLengths);
    return;
  }
  final SerializerInstance serInstance = serializer.newInstance();
  final long openStartTime = System.nanoTime();
  // 对应每个分区各配置一个DiskBlockObjectWriter
  partitionWriters = new DiskBlockObjectWriter[numPartitions];
  partitionWriterSegments = new FileSegment[numPartitions];
  // 这种写入方式下会打开numPartitions个DiskBlockObjectWriter
    // 因此对应的分区数不应该设置的过大，避免过大的内存开销
  for (int i = 0; i < numPartitions; i++) {
    final Tuple2<TempShuffleBlockId, File> tempShuffleBlockIdPlusFile =
      blockManager.diskBlockManager().createTempShuffleBlock();
    final File file = tempShuffleBlockIdPlusFile._2();
    final BlockId blockId = tempShuffleBlockIdPlusFile._1();
    partitionWriters[i] =
      blockManager.getDiskWriter(blockId, file, serInstance, fileBufferSize, writeMetrics);
  }
  // Creating the file to write to and creating a disk writer both involve interacting with
  // the disk, and can take a long time in aggregate when we open many files, so should be
  // included in the shuffle write time.
  writeMetrics.incWriteTime(System.nanoTime() - openStartTime);
  // 读取每条记录，并根据分区器将该记录交给分区对应的DiskOjectWriter
    // 写入各自对应的文件中
  while (records.hasNext()) {
    final Product2<K, V> record = records.next();
    final K key = record._1();
    partitionWriters[partitioner.getPartition(key)].write(key, record._2());
  }

  for (int i = 0; i < numPartitions; i++) {
    final DiskBlockObjectWriter writer = partitionWriters[i];
    partitionWriterSegments[i] = writer.commitAndGet();
    writer.close();
  }
  // 获取最终合并后的文件名
  File output = shuffleBlockResolver.getDataFile(shuffleId, mapId);
  File tmp = Utils.tempFileWith(output);
  try {
      // 在此合并前生成的各个中间临时文件，并获取各个分区对应的数据量
      // 由数据量可以得到对应的偏移量
    partitionLengths = writePartitionedFile(tmp);
    // 重写Index文件中的偏移量信息
    shuffleBlockResolver.writeIndexFileAndCommit(shuffleId, mapId, partitionLengths, tmp);
  } finally {
    if (tmp.exists() && !tmp.delete()) {
      logger.error("Error while deleting temp file {}", tmp.getAbsolutePath());
    }
  }
  // 封装并返回任务结果
  mapStatus = MapStatus$.MODULE$.apply(blockManager.shuffleServerId(), partitionLengths);
}
```

createTempShuffleBlock描述了各个分区所生成的中间临时文件的格式于对应的BlockId，代码如下：

```scala
// 中间临时文件名的格式由前缀temp_shuffle_与UUID.randomUUID组成，可以唯一标识一个BlockId
def createTempShuffleBlock(): (TempShuffleBlockId, File) = {
  var blockId = new TempShuffleBlockId(UUID.randomUUID())
  while (getFile(blockId).exists()) {
    blockId = new TempShuffleBlockId(UUID.randomUUID())
  }
  (blockId, getFile(blockId))
}
```

从上面的分析可以知道，每个Map端任务最重会生成两个文件：Data文件和Index文件。

##### b. SortShuffleWriter

前面BypassMergeSortShuffleWriter是在reduce端分区个数较少的情况下提供的一种优化方式，但是当数据集规模非常大，就需要使用SortShuffleWriter来写数据块。

```scala
override def write(records: Iterator[Product2[K, V]]): Unit = {
  // 当需要在Map端进行聚合操作时，此时会将指定的聚合器Aggregator与Key值的Ordering传入到外部排序器ExternalSorter中
  sorter = if (dep.mapSideCombine) {
    require(dep.aggregator.isDefined, "Map-side combine without Aggregator specified!")
    new ExternalSorter[K, V, C](
      context, dep.aggregator, Some(dep.partitioner), dep.keyOrdering, dep.serializer)
  } else {
    // In this case we pass neither an aggregator nor an ordering to the sorter, because we don't
    // care whether the keys get sorted in each partition; that will be done on the reduce side
    // if the operation being run is sortByKey.
    new ExternalSorter[K, V, V](
      context, aggregator = None, Some(dep.partitioner), ordering = None, dep.serializer)
  }
  // 将写入的记录集全部放入外部排序器
  sorter.insertAll(records)

  // Don't bother including the time to open the merged output file in the shuffle write time,
  // because it just opens a single file, so is typically too fast to measure accurately
  // (see SPARK-3570).
  // 获取输出文件名和BlockId
  val output = shuffleBlockResolver.getDataFile(dep.shuffleId, mapId)
  val tmp = Utils.tempFileWith(output)
  
  try {
    val blockId = ShuffleBlockId(dep.shuffleId, mapId, IndexShuffleBlockResolver.NOOP_REDUCE_ID)
    // 将分区数据写入文件，返回各个分区对应的数据量
    val partitionLengths = sorter.writePartitionedFile(blockId, tmp)
    // 更新索引文件的偏移量信息
    shuffleBlockResolver.writeIndexFileAndCommit(dep.shuffleId, mapId, partitionLengths, tmp)
    mapStatus = MapStatus(blockManager.shuffleServerId, partitionLengths)
  } finally {
    if (tmp.exists() && !tmp.delete()) {
      logError(s"Error while deleting temp file ${tmp.getAbsolutePath}")
    }
  }
}
```

这种基于Sort的Shuffle实现机制引入了外部排序器ExternalSorter，ExternalSorter继承了Spillable，因此内存使用达到一定阈值后，会spill到磁盘，减少内存开销。

### 六、基于Tungsten的Shuffle

Spark提供了配置属性，用于选择具体的Shuffle实现机制，虽然默认情况下Spark使用Sort的shuffle机制，但实际上，基于Sort的的Shuffle实现与基于Tungsten的Shuffle实现机制都是使用后SortShuffleManager，而内部的具体实现机制是通过两个方法判断的：当SortShuffleWriter.shouldBypassMergeSort返回false时，通过SortShuffleManager.canUseSerializedShuffle(dependency)方法判断是否使用基于Tungsten的Shuffle，如果上面两个判断都返回false，则会采用常规意义上的基于Sort的的Shuffle机制。也就是说，当设置了`spark.shuffle.manager = tunsten - sort`时，也不能保证一定采用基于Tungsten的Shuffle机制。

#### 1.基于Tungsten的Shuffle内核

基于Tungsten的Shuffle实现机制使用的shufflehandle与ShuffleWriter分别是SerializedShuffleHandle和UnsafeShuffleWriter。

```scala
else if (SortShuffleManager.canUseSerializedShuffle(dependency)) {
  // Otherwise, try to buffer map outputs in a serialized form, since this is more efficient:
  // 当可以使用序列化模式时，可以直接以序列化的个数输出数据，这刻印减少内存开销和序列化、反序列化等方面的Cpu开销
  new SerializedShuffleHandle[K, V](
    shuffleId, numMaps, dependency.asInstanceOf[ShuffleDependency[K, V, V]])
} else {
```

Serialized sorting:适用于以下三种情况：

- shuffle依赖项不指定聚合或输出顺序。
- shuffle序列化器支持序列化值的重新定位(目前由KryoSerializer和Spark SQL的自定义序列化器支持)。
- shuffle产生的输出分区不到16777216个。

#### 2.基于Tungsten的Shuffle写数据源码分析

```scala
/** Get a writer for a given partition. Called on executors by map tasks. */
override def getWriter[K, V](
    handle: ShuffleHandle,
    mapId: Int,
    context: TaskContext): ShuffleWriter[K, V] = {
  // numMapsForShuffle是一个ConcurrentHashMap，存放（shuffleId，numMaps）对
  numMapsForShuffle.putIfAbsent(
    handle.shuffleId, handle.asInstanceOf[BaseShuffleHandle[_, _, _]].numMaps)
  val env = SparkEnv.get
  // 根据ShuffleHandle类型构建具体数据写入器
  handle match {
    case unsafeShuffleHandle: SerializedShuffleHandle[K @unchecked, V @unchecked] =>
      new UnsafeShuffleWriter(
        env.blockManager,
        shuffleBlockResolver.asInstanceOf[IndexShuffleBlockResolver],
        context.taskMemoryManager(),
        unsafeShuffleHandle,
        mapId,
        context,
        env.conf)
```

在数据写入器类unsafeShuffleHandle中，仍然使用shuffleBlockResolver变量来对逻辑数据块与物理数据块的映射进行解析，解析类是IndexShuffleBlockResolver。

UnsafeShuffleWriter中传入的参数context.taskMemoryManager()是与Task一对一的关系，负责管理分配给Task的内存。

* org.apache.spark.shuffle.sort.UnsafeShuffleWriter#write

  ```scala
  public void write(scala.collection.Iterator<Product2<K, V>> records) throws IOException {
    // Keep track of success so we know if we encountered an exception
    // We do this rather than a standard try/catch/re-throw to handle
    // generic throwables.
    boolean success = false;
    try {
      // step1:对输入records，循环将每条记录插入到外部排序器
      while (records.hasNext()) {
        insertRecordIntoSorter(records.next());
      }
      // step2: 每个Map端的任务对应生成Data文件和Index文件，写的过程中会先合并外部排序器在插入过程中产生的spill文件
      closeAndWriteOutput();
      success = true;
    } finally {
      if (sorter != null) {
        try {
          // step3: 释放排序过程中使用的资源
          sorter.cleanupResources();
        } catch (Exception e) {
          ...
  ```

* step1:对输入records，循环将每条记录插入到外部排序器

  ```scala
  @VisibleForTesting
  void insertRecordIntoSorter(Product2<K, V> record) throws IOException {
    assert(sorter != null);
    // 对于多次访问的Key值，使用局部变量，避免多次函数调用
    final K key = record._1();
    final int partitionId = partitioner.getPartition(key);
    // 先复位存放每条记录的缓冲区
    // 序列化输出流的输出缓存为serBuffer ，大小为spark.shuffle.spill.diskWriteBufferSize，默认1MB
    serBuffer.reset();
    // 进一步使用序列化器从serBuffer缓冲区构建序列化输出流，将记录写入到缓冲区
    serOutputStream.writeKey(key, OBJECT_CLASS_TAG);
    serOutputStream.writeValue(record._2(), OBJECT_CLASS_TAG);
    serOutputStream.flush();
  
    final int serializedRecordSize = serBuffer.size();
    assert (serializedRecordSize > 0);
    // 将记录插入到外部排序器中，serBuffer是一个字节数组
    // 内部数据存放的偏移量为Platform.BYTE_ARRAY_OFFSET
    sorter.insertRecord(
      serBuffer.getBuf(), Platform.BYTE_ARRAY_OFFSET, serializedRecordSize, partitionId);
  }
  ```

* step2: 每个Map端的任务对应生成Data文件和Index文件，写的过程中会先合并外部排序器在插入过程中产生的spill文件

  这里用到`IndexShuffleBlockResolver`，用来创建并维护逻辑块和物理文件位置之间的shuffle块映射,来自同一map任务的shuffle块数据存储在单个合并的数据文件中。数据文件中数据块的偏移量存储在单独的索引文件中，文件名称为`shuffle_" + shuffleId + "_" + mapId + "_" + reduceId`，其中reduceId为0，“.data”作为数据文件的文件名后缀，“.index”作为索引文件的文件名后缀

  ```scala
  void closeAndWriteOutput() throws IOException {
    assert(sorter != null);
    updatePeakMemoryUsed();
    // 设为null,用于GC
    serBuffer = null;
    serOutputStream = null;
    // 关闭sorter，所有的缓冲数据进行排序并写入磁盘，返回所有溢出文件的信息
    final SpillInfo[] spills = sorter.closeAndGetSpills();
    sorter = null;
    final long[] partitionLengths;
    // 通过shuffleId，与map端该分区的partitionId创建一个名称为"shuffle_" + shuffleId + "_" + mapId + "_" + reduceId + ".data"的文件
    final File output = shuffleBlockResolver.getDataFile(shuffleId, mapId);
    // 在合并后序Spill文件时先使用临时文件名，最终在重新命名为真正的输出文件名
    // 即在writeIndexFileAndCommit方法中会重复通过块解析器获取输出文件名
    final File tmp = Utils.tempFileWith(output);
    try {
      try {
        // 把spill文件合并到一起，根据不同情况，选择合适的合并方式
        partitionLengths = mergeSpills(spills, tmp);
      } finally {
        // 清除生成的Spill文件
        for (SpillInfo spill : spills) {
          if (spill.file.exists() && ! spill.file.delete()) {
            logger.error("Error while deleting spill file {}", spill.file.getPath());
          }
        }
      }
      // 将合并Spill后获取的分区及其数据量信息写入索引文件
      // 并将临时数据文件重命名为真正的数据文件名
      shuffleBlockResolver.writeIndexFileAndCommit(shuffleId, mapId, partitionLengths, tmp);
    } finally {
      if (tmp.exists() && !tmp.delete()) {
        logger.error("Error while deleting temp file {}", tmp.getAbsolutePath());
      }
    }
    mapStatus = MapStatus$.MODULE$.apply(blockManager.shuffleServerId(), partitionLengths);
  }
  ```

  closeAndWriteOutput方法主要有以下几步：

  1）触发外部排序器，获取Spill信息

  2）合并中间的Spill文件，生成数据文件，并返回各个分区对应的数据量信息

  3）根据各个分区的数据量信息生成数据文件和对应的索引文件

* org.apache.spark.shuffle.sort.UnsafeShuffleWriter#mergeSpills

  ```scala
  /**
   * Merge zero or more spill files together, choosing the fastest merging strategy based on the
   * number of spills and the IO compression codec.
   * 基于Spill个数以及I/O压缩码选择最快速的合并策略，返回包含合并文件中各个分区的数据长度的数组
   * @return the partition lengths in the merged file.
   */
  private long[] mergeSpills(SpillInfo[] spills, File outputFile) throws IOException {
    // 是否使用压缩，默认为压缩，压缩方式由"spark.io.compression.codec"指定，默认是"lz4"
    final boolean compressionEnabled = sparkConf.getBoolean("spark.shuffle.compress", true);
    final CompressionCodec compressionCodec = CompressionCodec$.MODULE$.createCodec(sparkConf);
    // 是否启动unsafe的快速合并
    final boolean fastMergeEnabled =
      sparkConf.getBoolean("spark.shuffle.unsafe.fastMergeEnabled", true);
    // 不使用压缩或者codec支持对级联序列化流进行解压缩时，支持快速合并
    final boolean fastMergeIsSupported = !compressionEnabled ||
      CompressionCodec$.MODULE$.supportsConcatenationOfSerializedStreams(compressionCodec);
    // 加密 "spark.io.encryption.enabled"，默认为false
    final boolean encryptionEnabled = blockManager.serializerManager().encryptionEnabled();
    try {
      // 如果没有中间spills文件，创建一个空文件，并返回包含分区数据长度的空数组，后续读取时会滤掉空文件
      if (spills.length == 0) {
        new FileOutputStream(outputFile).close(); // Create an empty file
        return new long[partitioner.numPartitions()];
      } else if (spills.length == 1) {
        // 只有一个文件，中间没有进行数据溢出，直接把文件移动到该路径下
        // Here, we don't need to perform any metrics updates because the bytes written to this
        // output file would have already been counted as shuffle bytes written.
        Files.move(spills[0].file, outputFile);
        return spills[0].partitionLengths;
      } else {
        final long[] partitionLengths;
        // 当存在多个Spill中间文件时，根据不同的条件，采用不同的文件合并策略
        // There are multiple spills to merge, so none of these spill files' lengths were counted
        // towards our shuffle write count or shuffle write time. If we use the slow merge path,
        // then the final output file's size won't necessarily be equal to the sum of the spill
        // files' sizes. To guard against this case, we look at the output file's actual size when
        // computing shuffle bytes written.
        //
        // We allow the individual merge methods to report their own IO times since different merge
        // strategies use different IO techniques.  We count IO during merge towards the shuffle
        // shuffle write time, which appears to be consistent with the "not bypassing merge-sort"
        // branch in ExternalSorter.
        if (fastMergeEnabled && fastMergeIsSupported) {
          // Compression is disabled or we are using an IO compression codec that supports
          // decompression of concatenated compressed streams, so we can perform a fast spill merge
          // that doesn't need to interpret the spilled bytes.
          // 不加密
          if (transferToEnabled && !encryptionEnabled) {
            logger.debug("Using transferTo-based fast merge");
            // 通过NIO的方式合并各个spills的分区字节数据
            // 仅在IO压缩码和序列化器支持序列化流的合并式安全
            partitionLengths = mergeSpillsWithTransferTo(spills, outputFile);
          } else {
            logger.debug("Using fileStream-based fast merge");
            partitionLengths = mergeSpillsWithFileStream(spills, outputFile, null);
          }
        } else {
          logger.debug("Using slow merge");
          partitionLengths = mergeSpillsWithFileStream(spills, outputFile, compressionCodec);
        }
        // When closing an UnsafeShuffleExternalSorter that has already spilled once but also has
        // in-memory records, we write out the in-memory records to a file but do not count that
        // final write as bytes spilled (instead, it's accounted as shuffle write). The merge needs
        // to be counted as shuffle write, but this will lead to double-counting of the final
        // SpillInfo's bytes.
        writeMetrics.decBytesWritten(spills[spills.length - 1].file.length());
        writeMetrics.incBytesWritten(outputFile.length());
        return partitionLengths;
      }
    } catch (IOException e) {
        ...
  ```

  快速合并：对应`mergeSpillsWithTransferTo`方法，快速合并时使用Java NIO，`spark.file.transferTo` 默认为true，此时 Java NIO， channel之间直接传输数据

  慢合并：对应`mergeSpillsWithFileStream`，使用Java标准的流式IO，它主要用于IO压缩的编解码器不支持级联压缩数据，加密被启动或用户已显示禁止使用`transferTo`的情况，其中设计对数据流进行加密，压缩等。通常它的速度要比快速合并慢，但是如果spill中单个分区的数据量很小，此时`mergeSpillsWithTransferTo`方法执行许多小的磁盘IO，效率低下，该方法可能更快。因为它使用大缓冲区缓存输入和输出文件.
