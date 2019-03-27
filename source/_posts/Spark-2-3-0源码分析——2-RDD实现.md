---
title: Spark_2.3.0源码分析——2_RDD实现
date: 2018-10-02 22:57:00
tags: [大数据, Spark]
---

​	RDD是Spark最基本也是最根本的数据抽象，RDD提供了一种高度受限的共享内存，即**RDD是只读的**，并且只能通过其他RDD上的批量操作来创建，以此来实现容错。

​	一般来说，分布式数据集的容错性有两种方式：数据检查点和记录数据的更新。对于大规模数据分析，数据检查点操作成本很高：需要通过数据中心的网络连接在机器之前复制庞大的数据集，而网络带宽往往比内存带宽低很多，同时还需要消耗更多的存储资源。**所以Spark选择记录更新的方式**，但是如果更新太多，记录更新成本也不低，因此RDD只支持**粗粒度**转换，即在大量记录上执行的单个操作。将创建RDD的一系列转换记录下来，以便恢复丢失的分区。

<!-- more-->

#### 一、RDD的概念

一个 RDD 是一个只读, 被分区的数据集.我们可以通过两种对稳定的存储系统和其他的 RDDs 进行操作而创建一个新的 RDD.为了区别开 RDD 的其他操作, 我们称这些操作为 transformations, 比如 map, filter 以及 join 等都是 transformations 操作.

RDDs 并不要始终被物化, 一个 RDD 有足够的信息知道自己是从哪个数据集计算而来的（就是所谓的依赖血统）, 这是一个非常强大的属性：其实, 一个程序你只能引用一个不能从失败中重新构建的 RDD.同时具有数据流模型的特点：自动容错、位置感知调度、可伸缩性

每个RDD有5个主要的属性：

* 一组分片，即数据集的基本组成单位。对于RDD，每个分片都会被一个计算任务处理，并决定计算的粒度。每个分片会被逻辑映射成BolckManager的一个Block，而这个Block会被一个Task负责计算

  ![屏幕快照 2018-10-11 下午10.33.32.png](https://i.loli.net/2018/10/12/5bbff5af9a77a.png)

* 一个计算每个分片的函数：RDD中的计算以分片为单位，每个RDD都会实现compute函数以达到这个目的

* RDD之间的依赖关系：RDD之间会形成类似流水线的前后依赖关系，可以用与计算丢失的分区数据

* 一个Partitioner，即RDD的分片函数：RDD实现了两种Partitioner，一种基于哈希，一种基于范围。Partitioner决定了RDD本身的分片数量，也决定了parent RDD Shuffle输出数量

* 一个列表：存储每个Partition的优先位置（比如说HDFS的块位置）

##### 1.RDD的创建

1. 由一个以存在Scala集合创建
2. 由外部存储系统数据创建

RDD支持两种操作：

**转换：**从现有数据集创建一个新的数据集

**动作：**在数据集上进行计算后，返回一个值给Driver程序

##### 2.RDD的转换和动作

​	RDD中所有转换都是惰性的，它们只记住应用到基础数据集上的转换动作，只有当发生一个要求返回结果给Driver 的动作时，这些转换才会运行。默认情况下，每一个转换过的RDD都会在它执行一个动作时被重新计算，不过可以使用persist方法，在内存中持久化RDD。

​	我们需要记住 transformations 是用来定义一个新的 RDD 的 lazy 操作, 而**actions 是真正触发一个能返回结果或者将结果写到文件系统中的计算**.

##### 3.RDD的缓存

当持久化一个RDD后，每个节点都把计算的分片保存在内存中，并在对此数据集进行的其他动作中重用，这使得后续的动作变得更快。RDD相关的缓存和持久化，是Spark构建迭代式算法和快速交互式查询的关键。

Spark在持久化RDD时提供了三种存储选项：

| 存储方式                         | 特点                                                         |
| -------------------------------- | ------------------------------------------------------------ |
| 存在内存中的非序列化的 java 对象 | 性能最好, 因为 java VM 可以很快的访问 RDD 的每一个元素.      |
| 存在内存中的序列化的数据         | 在内存有限的情况下, 使的用户可以以很低的性能代价而选择的比 java 对象图更加高效的内存存储的方式 |
| 存储在磁盘中                     | 如果内存完全不够存储的下很大的 RDDs , 而且计算这个 RDD 又很费时的, 那么选择第三种方式 |

通过persist()或者cache()方法可以标记一个要被持久化的RDD，一旦首次被触发，该RDD将会被保留在计算节点的内存中并重用。cache()方法默认用MEMORY_ONLY的存储级别持久化数据。​	

- persist持久化级别：

```scala
val NONE = new StorageLevel(false, false, false, false)
val DISK_ONLY = new StorageLevel(true, false, false, false)
val DISK_ONLY_2 = new StorageLevel(true, false, false, false, 2)
val MEMORY_ONLY = new StorageLevel(false, true, false, true)
val MEMORY_ONLY_2 = new StorageLevel(false, true, false, true, 2)
val MEMORY_ONLY_SER = new StorageLevel(false, true, false, false)
val MEMORY_ONLY_SER_2 = new StorageLevel(false, true, false, false, 2)
// 如果数据在内存中放不下，则溢写到磁盘上
val MEMORY_AND_DISK = new StorageLevel(true, true, false, true)
val MEMORY_AND_DISK_2 = new StorageLevel(true, true, false, true, 2)
// 如果数据在内存中放不下，则溢写到磁盘上，在内存中存放序列化后的数据 
val MEMORY_AND_DISK_SER = new StorageLevel(true, true, false, false)
val MEMORY_AND_DISK_SER_2 = new StorageLevel(true, true, false, false, 2)
val OFF_HEAP = new StorageLevel(true, true, true, false, 1)
```

Scala和Java中，默认情况下persist()会把数据以序列化的形式缓存在JVM的堆空间中.

​	缓存有可能丢失，或者存储在内存中的数据由于内存不足而被删除。为了管理有限的内存资源, 在 RDDs 的层面上采用 LRU （最近最少使用）回收策略. 当一个新的 RDD 分区被计算但是没有足够的内存空间来存储这个分区的数据的时候, 会回收掉最近很少使用的 RDD 的分区数据的占用内存, 如果这个 RDD 和这个新的计算分区的 RDD 时同一个 RDD 的时候, 我们则不对这个分区数据占用的内存做回收. 

##### 4.RDD对 Checkpointing 的支持

​	虽然我们总是可以使用 RDDs 的血缘关系来恢复失败的 RDDs 的计算, 但是如果这个血缘关系链很长的话, 则恢复是需要耗费不少时间的.因此, 将一些 RDDs 的数据持久化到稳定存储系统中是有必要的，因此Spark又引入了检查点机制。

​	一般来说, checkpointing 对具有很长的血缘关系链且包含了宽依赖的 RDDs 是非常有用的, 这些场景下, 集群中的某个节点的失败会导致每一个父亲 RDD 的一些数据的丢失, 进而需要重新所有的计算. 与此相反的, 对于存储在稳定存储系统中且是窄依赖的 RDDs , checkpointing 可能一点用都没有. 如果一个节点失败了, 我们可以在其他的节点中并行的重新计算出丢失了数据的分区, 这个成本只是备份整个 RDD 的成本的一点点而已.

​	Spark 目前提供了一个 checkpointing 的 API（ persist 中的标识为 REPLICATE , 还有 checkpoint()）, 但是需要将哪些数据需要 checkpointing 的决定权留给了用户. 

#### 二、RDD的转换和DAG的生成

Spark会根据用户提交的计算逻辑中的RDD的转换和动作来生成RDD之间的依赖关系，同时这个计算链也就生成了逻辑上的DAG。

##### 1. RDD的依赖关系

RDD和它依赖的parent RDD的关系有两种不同的类型：

* 窄依赖：如果RDD与上游RDD分区是一对一的关系，那么RDD和其上游RDD之间的依赖关系属于窄依赖

* 宽依赖：parent RDDs 的一个分区可以被子 RDDs 的多个子分区所依赖

![屏幕快照 2018-10-11 下午10.33.52.png](https://i.loli.net/2018/10/12/5bbff5cf7abcb.png)

以下两个原因使的这种区别很有用：
​	第一, 窄依赖可以使得在集群中一个机器节点的执行流计算所有父亲的分区数据, 比如, 我们可以将每一个元素应用了 map 操作后紧接着应用 filter 操作, 与此相反, 宽依赖需要父亲 RDDs 的所有分区数据准备好并且利用类似于 MapReduce 的操作将数据在不同的节点之间进行重新洗牌和网络传输. 

​	第二, 窄依赖从一个失败节点中恢复是非常高效的, 因为只需要重新计算相对应的父亲的分区数据就可以, 而且这个重新计算是在不同的节点进行并行重计算的, 与此相反, 在一个含有宽依赖的血缘关系 RDDs 图中, 一个节点的失败可能导致一些分区数据的丢失, 但是我们需要重新计算父 RDD 的所有分区的数据.

所有的依赖都要继承抽象类Dependency[T]

```scala
abstract class Dependency[T] extends Serializable {
  def rdd: RDD[T]
}
```

对于窄依赖：

```scala
abstract class NarrowDependency[T](_rdd: RDD[T]) extends Dependency[T] {
  //返回子RDD的partitionId对应的所有parent RDD的Partition
  def getParents(partitionId: Int): Seq[Int]
  override def rdd: RDD[T] = _rdd
}
```

有三种窄依赖的具体实现：

* 一对一的依赖

  ```scala
  class OneToOneDependency[T](rdd: RDD[T]) extends NarrowDependency[T](rdd) {
    override def getParents(partitionId: Int): List[Int] = List(partitionId)
  }
  ```

  RDD仅仅依赖于Parent RDD相同ID的Partition。

* 范围的依赖

  ```scala
  /**
   * :: DeveloperApi ::
   * Represents a one-to-one dependency between ranges of partitions in the parent and child RDDs.
   * @param rdd the parent RDD
   * @param inStart the start of the range in the parent RDD
   * @param outStart the start of the range in the child RDD
   * @param length the length of the range
   */
  class RangeDependency[T](rdd: RDD[T], inStart: Int, outStart: Int, length: Int)
    extends NarrowDependency[T](rdd) {
  
    override def getParents(partitionId: Int): List[Int] = {
      if (partitionId >= outStart && partitionId < outStart + length) {
        List(partitionId - outStart + inStart)
      } else {
        Nil
      }
    }
  }
  ```

  RangeDependency仅被UnionRDD使用，UnionRDD把多个RDD合并成一个RDD，即每个parent RDD的Partition的相对顺序不会变，只不过每个parent RDD在UnionRDD中的Partition起始位置不同。

* PruneDependency

  ```scala
  private[spark] class PruneDependency[T](rdd: RDD[T], partitionFilterFunc: Int => Boolean)
    extends NarrowDependency[T](rdd) {
  
    @transient
    val partitions: Array[Partition] = rdd.partitions
      .filter(s => partitionFilterFunc(s.index)).zipWithIndex
      .map { case(split, idx) => new PartitionPruningRDDPartition(idx, split) : Partition }
  
    override def getParents(partitionId: Int): List[Int] = {
      List(partitions(partitionId).asInstanceOf[PartitionPruningRDDPartition].parentSplit.index)
    }
  }
  ```

  表示PartitionPruningRDD与其父级之间的依赖关系。 在这种情况下，子RDD包含父项的分区子集。

-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-·-

宽依赖的实现只有一种：ShuffleDependency。子RDD依赖于parent RDD的所有Partition。

```scala
/**
 * :: DeveloperApi ::
 * Represents a dependency on the output of a shuffle stage. Note that in the case of shuffle,
 * the RDD is transient since we don't need it on the executor side.
 *
 * @param _rdd the parent RDD
 * @param partitioner partitioner used to partition the shuffle output
 * @param serializer [[org.apache.spark.serializer.Serializer Serializer]] to use. If not set
 *                   explicitly then the default serializer, as specified by `spark.serializer`
 *                   config option, will be used.
 * @param keyOrdering key ordering for RDD's shuffles
 * @param aggregator map/reduce-side aggregator for RDD's shuffle
 * @param mapSideCombine whether to perform partial aggregation (also known as map-side combine)
 */
@DeveloperApi
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

##### 2. DAG的生成

​	原始的RDD(s)通过一系列转换就形成了DAG。RDD之间的依赖关系是DAG的重要属性。借助这些关系，DAG可以认为这些RDD之间形成了“血缘”，借助“血缘”，能保证一个RDD计算前，它所依赖的parent RDD都已经完成了计算；同时也实现了RDD的容错性。

​	Spark根据DAG划分计算任务：

 * 根据依赖关系将DAG划分为不同的stage，对于窄依赖，由于分区依赖关系的确定性，Partition的转换处理就在**同一个线程里完成**，窄依赖被划分到同一个stage。
 * 对于宽依赖，由于shuffle的存在，只有parent RDD shuffle处理完成后，才能开始接下来的计算，因此**宽依赖是Spark划分Stage的依据**，会根据宽依赖将DAG划分为不同stage。不同stage内部，每个partition都会被分配一个Task，它们可以**并行执行**
 * Stage只有在它没有parent Stage或者parent Stage都执行完毕后才可以执行。

### 三、RDD的计算

##### 1.Task介绍

原始RDD经过一系列转换后，会在最后一个RDD上触发一个动作，这个动作形成一个Job。在Job被划分为一批计算任务Task之后，这批任务会被提交到计算节点计算。

Spark中有两种Task：

* ResultTask：DAG最后一个阶段会为每个结果的Partition生成一个ResultTask
* ShuffleMapTask：其余阶段生成ShuffleMapTask

##### 2.Task的执行起点

org.apache.spark.scheduler.Task#run会调用ShuffleMapTask或ResultTask的runTask；runTask会调用RDD的org.apache.spark.rdd.RDD#iterator，计算由此开始。

```scala
 /**
   * Internal method to this RDD; will read from cache if applicable, or otherwise compute it.
   * This should ''not'' be called by users directly, but is available for implementors of custom
   * subclasses of RDD.
   */
  final def iterator(split: Partition, context: TaskContext): Iterator[T] = {
    if (storageLevel != StorageLevel.NONE) {
      // 如果存储级别不是None，说明分区数据要么已经存储在文件系统中，要么当前的RDD曾经执行过cache、
      // persist等持久化操作，因此需要想办法把数据从存储介质中提取出来。
      // iterator方法会继续调用RDD的getOrCompute方法
      getOrCompute(split, context)
    } else {
      // 存储级别为none，说明未经持久化的RDD，需要重新计算RDD内的数据，
      // 这时候调用RDD类computeOrReadCheckpoint方法，该方法也在持久化RDD的分区获取数据失败时被调用。
      computeOrReadCheckpoint(split, context)
    }
  }
```

##### 3.缓存的处理

以下是getOrCompute的实现：

```scala
private[spark] def getOrCompute(partition: Partition, context: TaskContext): Iterator[T] = {
    // 获取RDD的BlockId
    val blockId = RDDBlockId(id, partition.index)
    var readCachedBlock = true
    // This method is called on executors, so we need call SparkEnv.get instead of sc.env.
    // SparkEnv包含了一个运行时节点所需的所有环境信息
    // BlockManager运行在每个节点上
    // 检索给定的块（如果存在），否则调用提供的`makeIterator`方法来计算块，持久化并返回其值， 如果块已成功缓存，则返回BlockResult;如果无法缓存块，则返回迭代器。
    SparkEnv.get.blockManager.getOrElseUpdate(blockId, storageLevel, elementClassTag, () => {
    readCachedBlock = false
    computeOrReadCheckpoint(partition, context)
    }) match {
      case Left(blockResult) =>
        if (readCachedBlock) {
          val existingMetrics = context.taskMetrics().inputMetrics
          existingMetrics.incBytesRead(blockResult.bytes)
          new InterruptibleIterator[T](context, blockResult.data.asInstanceOf[Iterator[T]]) {
            override def next(): T = {
              existingMetrics.incRecordsRead(1)
              delegate.next()
            }
          }
        } else {
          new InterruptibleIterator(context, blockResult.data.asInstanceOf[Iterator[T]])
        }
      case Right(iter) =>
        new InterruptibleIterator(context, iter.asInstanceOf[Iterator[T]])
    }
  }
```

##### 4.checkpoint的处理

在缓存未命中的情况下，首先会判读是否保存了RDD的checkpoint，如果有则读取checkpoint。

* checkpoint数据写入过程：Job结束后，会判断是否需要checkpoint，需要则调用org.apache.spark.rdd.RDD#doCheckpoint.
* doCheckpoint首先为数据创建一个目录，然后启动一个新的Job来计算，并将计算结果写入新创建的目录
* 然后创建一个CheckPointRDD
* 最后原始RDD的所有依赖被清除，意味着RDD的转换的计算链等信息都被清除

```scala
/**
   * Compute an RDD partition or read it from a checkpoint if the RDD is checkpointing.
   */
  private[spark] def computeOrReadCheckpoint(split: Partition, context: TaskContext): Iterator[T] =
  {
    // Return whether this RDD is checkpointed and materialized, either reliably or locally.
    if (isCheckpointedAndMaterialized) {
      // 拉取父RDD对应分区的数据
      firstParent[T].iterator(split, context)
    } else {
      compute(split, context)
    }
  }
```

RDD抽象类要求其所有子类都必须实现compute方法，该方法介绍的参数之一是一个Partition对象，目的是计算该分区中的数据。以ReliableCheckpointRDD类为例，其compute方法如下:

```scala
 override def compute(split: Partition, context: TaskContext): Iterator[T] = {
    val file = new Path(checkpointPath, ReliableCheckpointRDD.checkpointFileName(split.index))
    ReliableCheckpointRDD.readCheckpointFile(file, broadcastedConf, context)//读取checkpoint的数据
  }
```

