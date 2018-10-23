---
title: Spark_2.3.0源码分析——9_Spark的存储模块
date: 2018-10-17 19:10:10
tags: [大数据, Spark]
---

### 一、Storage模块

#### 1.Storage概述

在Spark中存储模块被抽象成Storage，负责管理和实现数据块(Block)的存放。其中存取数据的最小单元是Block，数据由不同的Block组成，所有操作以Block为单位进行。本质上RDD中的Partition与Storage中的Block等价。Storage抽象模块的实现分为两个层次，如图所示：

<!-- more-->

![屏幕快照 2018-10-17 下午10.28.57.png](https://i.loli.net/2018/10/17/5bc74752b9c18.png)

* 通信层：Master-Slave结构， Master和Slave之间传输控制和状态信息
* 存储层：否则将数据存储到内存、磁盘或者外存中，有时需要为数据在远程节点上生成副本。

其他模块若要和Storage通信，需要通过统一的操作类BlockManager来完成

### 二、Storage模块的架构

#### 1.通信层

在Storage模块中，使用RPC框架进行通信。Storage模块对外提供一个统一的交互类BlockManager。BlockManager在每个结点(Master和Slave端)都有创建。Slave端创建的BlockManager在initialize方法中向Driver端的BlockManagerMasterEndpoint发送注册信息，收到消息后，完成Slave端BlockManager在Driver端的注册。

![屏幕快照 2018-10-17 下午8.53.22.png](https://i.loli.net/2018/10/17/5bc730e246458.png)

​	Driver端的BlockManagerMaster拥有所有结点BlockManagerSlaveEndPoint的Ref。Slave端的BlockManagerMaster拥有本结点上所有所有BlockManagerMasterEndPoint的Ref。在Driver和Slave结点上的Executor中都有BlockManager。BlockManager提供了本地和远程不同存储类型(Disk,Memory,ExternalBlockState)存储读取数据的接口。

> Spark2.0移除了ExternalBlockStore相关的API

##### a. BlockManager在Driver端的创建

在Spark创建时会根据具体的配置创建SparkEnv对象。

```scala
private[spark] def createSparkEnv(
    conf: SparkConf,
    isLocal: Boolean,
    listenerBus: LiveListenerBus): SparkEnv = {
  // 创建Driver端的运行环境
  SparkEnv.createDriverEnv(conf, isLocal, listenerBus, SparkContext.numDriverCores(master))
}
```

在 SparkEnv.createDriverEnv方法会创建SparkEnv并返回，在createDriverEnv方法中会创建BlockManager和BlockManagerMaster等对象，完成Storage在Driver端的部署。关键代码如下：

```scala
// 创建BlockManagerMaster
val blockManagerMaster = new BlockManagerMaster(registerOrLookupEndpoint(
  BlockManagerMaster.DRIVER_ENDPOINT_NAME,
  //  创建BlockManagerMasterEndpoint
  // isDriver表示是在Driver上创建还是在slave上创建
  new BlockManagerMasterEndpoint(rpcEnv, isLocal, conf, listenerBus)),
  conf, isDriver)

// NB: blockManager is not valid until initialize() is called later.
val blockManager = new BlockManager(executorId, rpcEnv, blockManagerMaster,
  serializerManager, conf, memoryManager, mapOutputTracker, shuffleManager,
  blockTransferService, securityManager, numUsableCores)
```

BlockManager和BlockManagerMaster属于聚合关系，BlockManager对外提供统一的访问接口，BlockManagerMaster主要对内提供各结点之间的指令通信服务。

* BlockManager的初始化

  在SparkContext调用_env.blockManager.initialize(_applicationId)时，会调用BlockManager的initialize方法：

  ```scala
  def initialize(appId: String): Unit = {
    // 调用blockTransferService的initialize方法，blockTransferService在不同结点fetch数据，传送数据
    blockTransferService.init(this)
    // shuffleClient读取其他Executor上的shuffle files
    shuffleClient.init(appId)
    // 设置block的复制分片策略，由spark.storage.replication.policy指定
    blockReplicationPolicy = {
      val priorityClass = conf.get(
        "spark.storage.replication.policy", classOf[RandomBlockReplicationPolicy].getName)
      val clazz = Utils.classForName(priorityClass)
      val ret = clazz.newInstance.asInstanceOf[BlockReplicationPolicy]
      logInfo(s"Using $priorityClass for block replication policy")
      ret
    }
    // 得到blockManager Id
    val id =
      BlockManagerId(executorId, blockTransferService.hostName, blockTransferService.port, None)
    // 向BlockManagerMaster注册BlockManager，返回一个更新的BlockManagerId
    val idFromMaster = master.registerBlockManager(
      id,
      maxOnHeapMemory,
      maxOffHeapMemory,
      slaveEndpoint)
  
    blockManagerId = if (idFromMaster != null) idFromMaster else id
  
    shuffleServerId = if (externalShuffleServiceEnabled) {
      logInfo(s"external shuffle service port = $externalShuffleServicePort")
      BlockManagerId(executorId, blockTransferService.hostName, externalShuffleServicePort)
    } else {
      blockManagerId
    }
  
    // Register Executors' configuration with the local shuffle service, if one should exist.
    // 向本地外部shuffle服务注册executor程序
    if (externalShuffleServiceEnabled && !blockManagerId.isDriver) {
      registerWithExternalShuffleServer()
    }
  
    logInfo(s"Initialized BlockManager: $blockManagerId")
  }
  ```

##### b.BlockManager在Slave结点上的创建

​	BlockManager的initilizer方法在SparkContext和Executor两个地方得到调用。在启动Executor时，会调用BlockManager的initilizer方法，代码如下：

```scala
// CoarseGrainedExecutorBackend中实例化Executor，isLocal始终未=为False
if (!isLocal) {
  // 完成Executor中的BlockManager向Driver中的BlockManagerMaster注册
  env.blockManager.initialize(conf.getAppId)
  // 向度量系统注册
  env.metricsSystem.registerSource(executorSource)
  env.metricsSystem.registerSource(env.blockManager.shuffleMetricsSource)
}
```

#### 2.存储层

在Spark 2.3.0中有两种存储方式：

* DiskStore：存储到磁盘
* MemoryStore：以字节数组或Java对象的方式存储在内存中

> 在Spark2.0之前，还有一种存储方式叫ExternalBlockStore，存储数据到JVM外部的存储系统中，Spark2.0移除了ExternalBlockStore相关的API，具体原因ExternalBlockStore很少被使用，而且相比之下file system接口是一种更标准、更好的与外部存储系统交互的工具。
>
> 同时，在Spark2.0中还移除了三种存储方式的公共父类BlockStore，具体原因看下面的网址：
>
> https://github.com/apache/spark/pull/11534#issue-61801724

##### 1. DiskStore

DiskStore会将Block存放到磁盘上，在DiskStore中可以配置多个存放Block的目录，DiskStoreManager会根据这些配置创建不同的文件夹，存放Block。DiskBlockManager会调用createLocalDirs方法为Block创建文件夹，文件夹的格式是：prefix-UUID

```scala
private def createLocalDirs(conf: SparkConf): Array[File] = {
  // 从SparkConf中找出配置的文件保存路径，路径可以配置多个，用逗号分开
  Utils.getConfiguredLocalDirs(conf).flatMap { rootDir =>
    try {
      // 创建目录，并指定前缀，返回一个File对象
      val localDir = Utils.createDirectory(rootDir, "blockmgr")
      logInfo(s"Created local directory at $localDir")
      // 返回创建好的目录
      Some(localDir)
    } catch {
      case e: IOException =>
        logError(s"Failed to create local dir in $rootDir. Ignoring this directory.", e)
        None
    }
  }
}
```

如果要创建的文件已近存在或者没有创建的权限，在尝试多次后会抛出IOException异常：

```scala
 try {
    dir = new File(root, namePrefix + "-" + UUID.randomUUID.toString)
    // 如果dir已经存在或者创建失败，置dir为null
    if (dir.exists() || !dir.mkdirs()) {
      dir = null
    }
  } catch { case e: SecurityException => dir = null; }
}
```

在DiskBlock存储中，每一个Block被存储为一个文件，文件名通过计算BlockId对象中的fileName的哈希值得到，通过映射得到文件名后，将block中的数据写到文件中。

```scala
def getFile(filename: String): File = {
  // Figure out which local directory it hashes to, and which subdirectory in that
  val hash = Utils.nonNegativeHash(filename)
  // 使用非负哈希值对localDirs取余，得到目录id
  val dirId = hash % localDirs.length
  // 得到子目录id
  val subDirId = (hash / localDirs.length) % subDirsPerLocalDir

  // Create the subdirectory if it doesn't already exist
  val subDir = subDirs(dirId).synchronized {
    val old = subDirs(dirId)(subDirId)
    if (old != null) {
      old
    } else {
      val newDir = new File(localDirs(dirId), "%02x".format(subDirId))
      if (!newDir.exists() && !newDir.mkdir()) {
        throw new IOException(s"Failed to create local dir in $newDir.")
      }
      subDirs(dirId)(subDirId) = newDir
      newDir
    }
  }
  // 返回以subDir为根目录，filename作为文件名称的、File对象
  new File(subDir, filename)
}
```

使用hash映射将文件分配到不同的目录是为了避免顶级目录的inodes过于庞大。

DiskStore实现了BlockManager中存取block的方法

* org.apache.spark.storage.DiskStore#putBytes

* ```scala
  def putBytes(blockId: BlockId, bytes: ChunkedByteBuffer): Unit = {
    // 柯里化方式向put传入第二个参数
    put(blockId) { channel =>
      bytes.writeFully(channel)
    }
  }
  ```

* org.apache.spark.storage.DiskStore#put

  ```scala
  /**
   * Invokes the provided callback function to write the specific block.
   *  调用提供的回调函数writeFunc来写这个块
   * @throws IllegalStateException if the block already exists in the disk store.
   */
  def put(blockId: BlockId)(writeFunc: WritableByteChannel => Unit): Unit = {
    if (contains(blockId)) {
      throw new IllegalStateException(s"Block $blockId is already present in the disk store")
    }
    logDebug(s"Attempting to put block $blockId")
    val startTime = System.currentTimeMillis
    // 获得对应blockId的文件名
    val file = diskManager.getFile(blockId)
    // 使用nio没得到文件上的channel通道
    val out = new CountingWritableChannel(openForWrite(file))
    var threwException: Boolean = true
    try {
      // 利用回调函数将bytes写入通道
      writeFunc(out)
      blockSizes.put(blockId, out.getCount)
      threwException = false
    } finally {
      try {
        // 关闭通道
        out.close()
      } catch {
        case ioe: IOException =>
          if (!threwException) {
            threwException = true
            throw ioe
          }
      } finally {
         if (threwException) {
          remove(blockId)
        }
      }
    }
    val finishTime = System.currentTimeMillis
    logDebug("Block %s stored as %s file on disk in %d ms".format(
      file.getName,
      Utils.bytesToString(file.length()),
      finishTime - startTime))
  }
  ```

* org.apache.spark.storage.DiskStore#getBytes

  ```scala
  def getBytes(blockId: BlockId): BlockData = {
    val file = diskManager.getFile(blockId.name)
    // 获取Block的大小
    val blockSize = getSize(blockId)
    // 获取IO加密密钥
    securityManager.getIOEncryptionKey() match {
      case Some(key) =>
        // Encrypted blocks cannot be memory mapped; return a special object that does decryption
        // and provides InputStream / FileRegion implementations for reading the data.
        // 如果加密，加密块不能进行内存映射; 返回一个执行解密的特殊对象，并提供InputStream / FileRegion实现来读取数据。
        new EncryptedBlockData(file, blockSize, conf, key)
      // 若未加密，返回一个DiskBlockData
      case _ =>
        new DiskBlockData(minMemoryMapBytes, maxMemoryMapBytes, file, blockSize)
    }
  }
  ```

  这个方法返回一个BlockData对象，BlockData是描述块数据的接口，有如下方法：

  ```scala
  private[spark] trait BlockData {
  
    def toInputStream(): InputStream
  
    /**
     * Returns a Netty-friendly wrapper for the block's data.
     *
     * Please see `ManagedBuffer.convertToNetty()` for more details.
     */
    def toNetty(): Object
    def toChunkedByteBuffer(allocator: Int => ByteBuffer): ChunkedByteBuffer
    def toByteBuffer(): ByteBuffer
    def size: Long
    def dispose(): Unit
  }
  ```

  DiskBlockData是BlockData的一种对于存储在磁盘上的数据的实现，传入分别是内存映射的最小字节数和最小字节数，分别由spark.storage.memoryMapThreshold和spark.storage.memoryMapLimitForTests指定，还有Block所存的文件和BlockSize

  着重看一下toByteBuffer方法：

  ```scala
  override def toByteBuffer(): ByteBuffer = {
    // 如果目标块的大小超出了设置的内存映射最大值
    require(blockSize < maxMemoryMapBytes,
      s"can't create a byte buffer of size $blockSize" +
      s" since it exceeds ${Utils.bytesToString(maxMemoryMapBytes)}.")
    // tryWithResource会默认在resource使用完后执行close方法
    Utils.tryWithResource(open()) { channel =>
      if (blockSize < minMemoryMapBytes) {
        // minMemoryMapBytes默认是2M
        // 对于小2M文件，直接读取而不是内存映射。
        val buf = ByteBuffer.allocate(blockSize.toInt)
        JavaUtils.readFully(channel, buf)
        buf.flip()
        buf
      } else {
        // 以内存映射的方式读取文件内容
        channel.map(MapMode.READ_ONLY, 0, file.length)
      }
    }
  }
  ```

DIskStore会将数据保存到磁盘，如果频繁的进行磁盘I/O操作，会严重影响系统性能,MemoryStore可以解决这个问题。

##### 2. MemoryStore

MemoryStore中维护着一个LinkedHashMap来管理所有Block，Block被包装成MemoryEntry对象，该对象中保存着Block相关的信息，如大小、是否反序列化等，定义如下：

```scala
// 初始容量32，负荷系数0.75,涉及到自动扩容，访问模型为顺序访问
private val entries = new LinkedHashMap[BlockId, MemoryEntry[_]](32, 0.75f, true)

private sealed trait MemoryEntry[T] {
  def size: Long
  def memoryMode: MemoryMode
  def classTag: ClassTag[T]
}
private case class DeserializedMemoryEntry[T](
    value: Array[T],
    size: Long,
    classTag: ClassTag[T]) extends MemoryEntry[T] {
  val memoryMode: MemoryMode = MemoryMode.ON_HEAP
}
private case class SerializedMemoryEntry[T](
    buffer: ChunkedByteBuffer,
    memoryMode: MemoryMode,
    classTag: ClassTag[T]) extends MemoryEntry[T] {
  def size: Long = buffer.size
}
```

MemoryStore必须有足够的内存来存放Block，如果内存不够，会移除一些已有的块，以putButes方法为例：

```scala
 /**
 * 使用`size`来测试MemoryStore中是否有足够的空间。 如果是这样，
  * 创建ByteBuffer并将其放入MemoryStore。 否则，将不会创建ByteBuffer。 调用者应该保证`size`是正确的。
 * @return true if the put() succeeded, false otherwise.
 */
def putBytes[T: ClassTag](
    blockId: BlockId,
    size: Long,
    memoryMode: MemoryMode,
    _bytes: () => ChunkedByteBuffer): Boolean = {
  // 确保之前没有存过blockId对应的块
  require(!contains(blockId), s"Block $blockId is already present in the MemoryStore")
  // 获取N个字节的内存来缓存给定的块，必要时驱逐现有的块。返回是否成功分配了空间
  if (memoryManager.acquireStorageMemory(blockId, size, memoryMode)) {
    // We acquired enough memory for the block, so go ahead and put it
    val bytes = _bytes()
    assert(bytes.size == size)
    val entry = new SerializedMemoryEntry[T](bytes, memoryMode, implicitly[ClassTag[T]])
    entries.synchronized {
      entries.put(blockId, entry)
    }
    logInfo("Block %s stored as bytes in memory (estimated size %s, free %s)".format(
      blockId, Utils.bytesToString(size), Utils.bytesToString(maxMemory - blocksMemoryUsed)))
    true
  } else {
    false
  }
}
```

```scala
/** 
* 尝试驱逐块以释放给定数量的空间来存储特定的块。如果块大于我们的内存，或者需要从同一个RDD替换另一个块，
  * 则会失败
 *
 * @param blockId the ID of the block we are freeing space for, if any
 * @param space the size of this block
 * @param memoryMode the type of memory to free (on- or off-heap)
 * @return the amount of memory (in bytes) freed by eviction
 */
private[spark] def evictBlocksToFreeSpace(
    blockId: Option[BlockId],
    space: Long,
    memoryMode: MemoryMode): Long = {
  assert(space > 0)
  memoryManager.synchronized {
    var freedMemory = 0L
    val rddToAdd = blockId.flatMap(getRddId)
    val selectedBlocks = new ArrayBuffer[BlockId]
    // 内嵌方法，判断block是否可以移除
    def blockIsEvictable(blockId: BlockId, entry: MemoryEntry[_]): Boolean = {
      // memoryMode 相同时， block所属的rdd为空或者rdd不是当前block所属rdd
      entry.memoryMode == memoryMode && (rddToAdd.isEmpty || rddToAdd != getRddId(blockId))
    }
    // This is synchronized to ensure that the set of entries is not changed
    // (because of getValue or getBytes) while traversing the iterator, as that
    // can lead to exceptions.
    entries.synchronized {
      // 遍历entries
      val iterator = entries.entrySet().iterator()
      while (freedMemory < space && iterator.hasNext) {
        val pair = iterator.next()
        val blockId = pair.getKey
        val entry = pair.getValue
        if (blockIsEvictable(blockId, entry)) {
          // We don't want to evict blocks which are currently being read, so we need to obtain
          // an exclusive write lock on blocks which are candidates for eviction. We perform a
          // non-blocking "tryLock" here in order to ignore blocks which are locked for reading:
          // 移除时，不考虑正在被读取的block，为没有读取的block加写锁
          if (blockInfoManager.lockForWriting(blockId, blocking = false).isDefined) {
            selectedBlocks += blockId
            freedMemory += pair.getValue.size
          }
        }
      }
    }

    def dropBlock[T](blockId: BlockId, entry: MemoryEntry[T]): Unit = {
      val data = entry match {
        case DeserializedMemoryEntry(values, _, _) => Left(values)
        case SerializedMemoryEntry(buffer, _, _) => Right(buffer)
      }
      // 调用BlockManager的方法删除block
      val newEffectiveStorageLevel =
        blockEvictionHandler.dropFromMemory(blockId, () => data)(entry.classTag)
      if (newEffectiveStorageLevel.isValid) {
        // The block is still present in at least one store, so release the lock
        // but don't delete the block info
        blockInfoManager.unlock(blockId)
      } else {
        // The block isn't present in any store, so delete the block info so that the
        // block can be stored again
        blockInfoManager.removeBlock(blockId)
      }
    }
    // 可移除空间大于Block的size
    if (freedMemory >= space) {
      var lastSuccessfulBlock = -1
      try {
        logInfo(s"${selectedBlocks.size} blocks selected for dropping " +
          s"(${Utils.bytesToString(freedMemory)} bytes)")
        (0 until selectedBlocks.size).foreach { idx =>
          val blockId = selectedBlocks(idx)
          val entry = entries.synchronized {
            entries.get(blockId)
          }
          // This should never be null as only one task should be dropping
          // blocks and removing entries. However the check is still here for
          // future safety.
          if (entry != null) {
            // 删除block
            dropBlock(blockId, entry)
            afterDropAction(blockId)
          }
          lastSuccessfulBlock = idx
        }
        logInfo(s"After dropping ${selectedBlocks.size} blocks, " +
          s"free memory is ${Utils.bytesToString(maxMemory - blocksMemoryUsed)}")
        freedMemory
      } finally {
        // like BlockManager.doPut, we use a finally rather than a catch to avoid having to deal
        // with InterruptedException
        // 没有完成所有候选block释放，空间已经达到需求，需要对未处理的block释放锁
        if (lastSuccessfulBlock != selectedBlocks.size - 1) {
          // the blocks we didn't process successfully are still locked, so we have to unlock them
          (lastSuccessfulBlock + 1 until selectedBlocks.size).foreach { idx =>
            val blockId = selectedBlocks(idx)
            blockInfoManager.unlock(blockId)
          }
        }
      }
    } else {
      // 就算移除了其他块也没有足够的空间
      blockId.foreach { id =>
        logInfo(s"Will not store $id")
      }
      selectedBlocks.foreach { id =>
        blockInfoManager.unlock(id)
      }
      0L
    }
  }
}
```

##### 3.通过BlockManager读写数据

BlockManager提供了putBlockData方法，用于存储数据

* org.apache.spark.storage.BlockManager#putBlockData

* ```scala
  override def putBlockData(
      blockId: BlockId,
      data: ManagedBuffer,
      level: StorageLevel,
      classTag: ClassTag[_]): Boolean = {
    putBytes(blockId, new ChunkedByteBuffer(data.nioByteBuffer()), level)(classTag)
  }
  ```

  传入四个参数，第一个是BlockId对象，第二个是ManagedBuffer，表示待存对象，第三个level指定存储的级别，第四个ClassTag描述运行时类型信息。方法中调用putBytes方法，代码如下：

  ```scala
  def putBytes[T: ClassTag](
      blockId: BlockId,
      bytes: ChunkedByteBuffer,
      level: StorageLevel,
      tellMaster: Boolean = true): Boolean = {
    require(bytes != null, "Bytes is null")
    doPutBytes(blockId, bytes, level, implicitly[ClassTag[T]], tellMaster)
  }
  ```

  tellMaster用于设置在存入数据后是否通知Master，默认为true。putBytes方法主要完成将一个序列化的字节数组存入BlockManager。该方法调用了doPutBytes，doPutBytes返回一个Boolean值，如果block已经存在或者写入成功，则返回True，否则返回True，代码如下：

  ```scala
  private def doPutBytes[T](
      blockId: BlockId,
      bytes: ChunkedByteBuffer,
      level: StorageLevel,
      classTag: ClassTag[T],
      tellMaster: Boolean = true,
      keepReadLock: Boolean = false): Boolean = {
    // 调用doPut方法
    doPut(blockId, level, classTag, tellMaster = tellMaster, keepReadLock = keepReadLock) { info =>
      // 开始时间
      val startTimeMs = System.currentTimeMillis
      // 由于我们存储字节，因此在本地存储之前启动复制。
      // 由于数据已经序列化并准备发送，因此速度更快。
      val replicationFuture = if (level.replication > 1) {
        Future {
          // This is a blocking action and should run in futureExecutionContext which is a cached
          // thread pool. The ByteBufferBlockData wrapper is not disposed of to avoid releasing
          // buffers that are owned by the caller.
  
          // 这是一个阻塞操作，应该在futureExecutionContext中运行，后者是一个缓存的线程池。不会丢弃ByteBufferBlockData包装以避免释放调用者拥有的缓冲区。、
          // 备份数据
          replicate(blockId, new ByteBufferBlockData(bytes, false), level, classTag)
        }(futureExecutionContext)
      } else {
        null
      }
  
      val size = bytes.size
  
      if (level.useMemory) {
        // Put it in memory first, even if it also has useDisk set to true;
        // We will drop it to disk later if the memory store can't hold it.
        // 如果内存放不下才会将block放到磁盘上
        val putSucceeded = if (level.deserialized) {
          val values =
            // 将字节流反序列化为value迭代器
            serializerManager.dataDeserializeStream(blockId, bytes.toInputStream())(classTag)
          // 将块以值的方式存储到内存中
          memoryStore.putIteratorAsValues(blockId, values, classTag) match {
            case Right(_) => true
            case Left(iter) =>
              // If putting deserialized values in memory failed, we will put the bytes directly to
              // disk, so we don't need this iterator and can close it to free resources earlier.
              iter.close()
              false
          }
        } else {
          // 以序列化的形式存储到内存
          val memoryMode = level.memoryMode
          memoryStore.putBytes(blockId, size, memoryMode, () => {
            if (memoryMode == MemoryMode.OFF_HEAP &&
                bytes.chunks.exists(buffer => !buffer.isDirect)) {
              bytes.copy(Platform.allocateDirectBuffer)
            } else {
              bytes
            }
          })
        }
        // 如果存到内存失败，就存到磁盘
        if (!putSucceeded && level.useDisk) {
          logWarning(s"Persisting block $blockId to disk instead.")
          diskStore.putBytes(blockId, bytes)
        }
      } else if (level.useDisk) {
        diskStore.putBytes(blockId, bytes)
      }
  
      val putBlockStatus = getCurrentBlockStatus(blockId, info)
      val blockWasSuccessfullyStored = putBlockStatus.storageLevel.isValid
      if (blockWasSuccessfullyStored) {
        // Now that the block is in either the memory or disk store,
        // tell the master about it.
        info.size = size
        // 向Master汇报情况
        if (tellMaster && info.tellMaster) {
          reportBlockStatus(blockId, putBlockStatus)
        }
        // 向度量器汇报Block新状态
        addUpdatedBlockStatusToTaskMetrics(blockId, putBlockStatus)
      }
      logDebug("Put block %s locally took %s".format(blockId, Utils.getUsedTimeMs(startTimeMs)))
      if (level.replication > 1) {
        // Wait for asynchronous replication to finish
        // 等待备份结束
        try {
          ThreadUtils.awaitReady(replicationFuture, Duration.Inf)
        } catch {
          case NonFatal(t) =>
            throw new Exception("Error occurred while waiting for replication to finish", t)
        }
      }
      if (blockWasSuccessfullyStored) {
        None
      } else {
        Some(bytes)
      }
    }.isEmpty
  }
  ```

  上面的方法直接调用了doPut方法，传入了一个函数参数，通过StorageLevel的设定将block存储到对应的BlockStore，如果有必要将会产生并存储副本。

  ```scala
  private def doPut[T](
      blockId: BlockId,
      level: StorageLevel,
      classTag: ClassTag[_],
      tellMaster: Boolean,
      keepReadLock: Boolean)(putBody: BlockInfo => Option[T]): Option[T] = {
    // 检查blockId是否为null
    require(blockId != null, "BlockId is null")
    // level不为null且合法
    require(level != null && level.isValid, "StorageLevel is null or invalid")
    // put操作产生的Block信息
    val putBlockInfo = {
      val newInfo = new BlockInfo(level, classTag, tellMaster)
      // 如果获取BlockId对应的Block的写锁，返回newInfo
      if (blockInfoManager.lockNewBlockForWriting(blockId, newInfo)) {
        newInfo
      } else {
        logWarning(s"Block $blockId already exists on this machine; not re-adding it")
        if (!keepReadLock) {
          // lockNewBlockForWriting returned a read lock on the existing block, so we must free it:
          releaseLock(blockId)
        }
        return None
      }
    }
  
    val startTimeMs = System.currentTimeMillis
    var exceptionWasThrown: Boolean = true
    val result: Option[T] = try {
      // 将block存入blockStore
      val res = putBody(putBlockInfo)
      exceptionWasThrown = false
      if (res.isEmpty) {
        // the block was successfully stored
        // 如果成功存储
        if (keepReadLock) {
          blockInfoManager.downgradeLock(blockId)
        } else {
          blockInfoManager.unlock(blockId)
        }
      } else {
        // 移除Block和BlockInfo
        removeBlockInternal(blockId, tellMaster = false)
        logWarning(s"Putting block $blockId failed")
      }
      res
    } catch {
      // Since removeBlockInternal may throw exception,
      // we should print exception first to show root cause.
      case NonFatal(e) =>
        logWarning(s"Putting block $blockId failed due to exception $e.")
        throw e
    } finally {
      // This cleanup is performed in a finally block rather than a `catch` to avoid having to
      // catch and properly re-throw InterruptedException.
      if (exceptionWasThrown) {
        // If an exception was thrown then it's possible that the code in `putBody` has already
        // notified the master about the availability of this block, so we need to send an update
        // to remove this block location.
        removeBlockInternal(blockId, tellMaster = tellMaster)
        // The `putBody` code may have also added a new block status to TaskMetrics, so we need
        // to cancel that out by overwriting it with an empty block status. We only do this if
        // the finally block was entered via an exception because doing this unconditionally would
        // cause us to send empty block statuses for every block that failed to be cached due to
        // a memory shortage (which is an expected failure, unlike an uncaught exception).
        addUpdatedBlockStatusToTaskMetrics(blockId, BlockStatus.empty)
      }
    }
    if (level.replication > 1) {
      logDebug("Putting block %s with replication took %s"
        .format(blockId, Utils.getUsedTimeMs(startTimeMs)))
    } else {
      logDebug("Putting block %s without replication took %s"
        .format(blockId, Utils.getUsedTimeMs(startTimeMs)))
    }
    result
  }
  ```

* 获取数据

  ```scala
  def get[T: ClassTag](blockId: BlockId): Option[BlockResult] = {
    // 首先调用getLocalValues方法，查找本地是否有对应blockId的数据
    val local = getLocalValues(blockId)
    if (local.isDefined) {
      logInfo(s"Found block $blockId locally")
      return local
    }
    // 如果本地没有定义该blockId，到远程节点查找
    val remote = getRemoteValues[T](blockId)
    if (remote.isDefined) {
      logInfo(s"Found block $blockId remotely")
      return remote
    }
    // 否则返回None
    None
  }
  ```

  get方法中，根据blockId，先从本地blockManager中获得数据，如果获得了就返回，如果没有，调用getRemoteValues方法，尝试在其他远程blockManager中查找数据，如果找到则返回，没有找到的返回None。Spark中，往往是根据block所在位置进行分配的，大部分通过getLocalValues就可以找到，但在资源有限情况下，TaskScheduler可能会将任务调度到Block所在结点不同的结点上执行。

  getLocalValues源码如下：

  ```scala
  def getLocalValues(blockId: BlockId): Option[BlockResult] = {
    logDebug(s"Getting local block $blockId")
    // 获取读锁
    blockInfoManager.lockForReading(blockId) match {
      case None =>
        logDebug(s"Block $blockId was not found")
        None
      case Some(info) =>
        val level = info.level
        logDebug(s"Level for block $blockId is $level")
  
        val taskAttemptId = Option(TaskContext.get()).map(_.taskAttemptId())
        // 如果使用的是MEMORY的存储级别，查找MemoeyStore并返回
        if (level.useMemory && memoryStore.contains(blockId)) {
          // 如果存储非序列化的值，调用getValues
          val iter: Iterator[Any] = if (level.deserialized) {
            memoryStore.getValues(blockId).get
          } else {
            // 否则先获得序列化的字节缓冲数组在进行反序列化，得到value的iterator
            serializerManager.dataDeserializeStream(
              blockId, memoryStore.getBytes(blockId).get.toInputStream())(info.classTag)
          }
          // We need to capture the current taskId in case the iterator completion is triggered
          // from a different thread which does not have TaskContext set; see SPARK-18406 for
          // discussion.
          // 我们需要捕获当前的taskId，以防迭代器完成从没有设置TaskContext的不同线程触发;
          val ci = CompletionIterator[Any, Iterator[Any]](iter, {
            releaseLock(blockId, taskAttemptId)
          })
          // 返回BlockResult
          Some(new BlockResult(ci, DataReadMethod.Memory, info.size))
        }
          // 如果使用的是磁盘存储，通过DiskStore查找并返回数据
        else if (level.useDisk && diskStore.contains(blockId)) {
          val diskData = diskStore.getBytes(blockId)
          val iterToReturn: Iterator[Any] = {
            if (level.deserialized) {
              val diskValues = serializerManager.dataDeserializeStream(
                blockId,
                diskData.toInputStream())(info.classTag)
              // 尝试将从磁盘读取的溢出值缓存到MemoryStore中，以加快后续读取速度。
              // 此方法要求调用者在块上保持读锁定。
              maybeCacheDiskValuesInMemory(info, blockId, level, diskValues)
            } else {
              val stream = maybeCacheDiskBytesInMemory(info, blockId, level, diskData)
                .map { _.toInputStream(dispose = false) }
                .getOrElse { diskData.toInputStream() }
              serializerManager.dataDeserializeStream(blockId, stream)(info.classTag)
            }
          }
          val ci = CompletionIterator[Any, Iterator[Any]](iterToReturn, {
            releaseLockAndDispose(blockId, diskData, taskAttemptId)
          })
          Some(new BlockResult(ci, DataReadMethod.Disk, info.size))
        } else {
          // 从本地读取失败
          handleLocalReadFailure(blockId)
        }
    }
  }
  ```

  如果本地没有查询到blockId对应的Block，会调用getRemote方法查询远程节点上是否有该blockId对应的Block数据。getRemote方法源码如下：

  ```scala
  /**
   * Get block from remote block managers.
   *
   * This does not acquire a lock on this block in this JVM.
   */
  private def getRemoteValues[T: ClassTag](blockId: BlockId): Option[BlockResult] = {
    val ct = implicitly[ClassTag[T]]
    // 调用getRemoteBytes
    getRemoteBytes(blockId).map { data =>
      val values =
        serializerManager.dataDeserializeStream(blockId, data.toInputStream(dispose = true))(ct)
      new BlockResult(values, DataReadMethod.Network, data.size)
    }
  }
  ```

  getRemote方法通过其他节点的BlockManager查询block，最后通过map方法，将得到的序列化字节反序列化为value，最终返回BlockResult。

  ```scala
  /**
   * Get block from remote block managers as serialized bytes.
   */
  def getRemoteBytes(blockId: BlockId): Option[ChunkedByteBuffer] = {
    logDebug(s"Getting remote block $blockId")
    // 检查blockId是否为null
    require(blockId != null, "BlockId is null")
    var runningFailureCount = 0
    var totalFailureCount = 0
  
    // Because all the remote blocks are registered in driver, it is not necessary to ask
    // all the slave executors to get block status.
    // 调用BlockManagerMaster的GetLocationsAndStatus方法获取blockId的位置和状态
    val locationsAndStatus = master.getLocationsAndStatus(blockId)
    val blockSize = locationsAndStatus.map { b =>
      b.status.diskSize.max(b.status.memSize)
    }.getOrElse(0L)
    // 获取blockId的位置
    val blockLocations = locationsAndStatus.map(_.locations).getOrElse(Seq.empty)
  
    // If the block size is above the threshold, we should pass our FileManger to
    // BlockTransferService, which will leverage it to spill the block; if not, then passed-in
    // null value means the block will be persisted in memory.
    // 如果块大小超过阈值，我们应该将FileManger传递给BlockTransferService，
    // 后者将利用它来溢出块; 如果没有，那么传入的空值意味着该块将被持久化在内存中。
    val tempFileManager = if (blockSize > maxRemoteBlockToMem) {
      remoteBlockTempFileManager
    } else {
      null
    }
    // 按照位置选出blockLocations
    val locations = sortLocations(blockLocations)
    val maxFetchFailures = locations.size
    var locationIterator = locations.iterator
    while (locationIterator.hasNext) {
      val loc = locationIterator.next()
      logDebug(s"Getting remote block $blockId from $loc")
      val data = try {
        // 调用blockTransferService的fetchBlockSync方法，异步抓取远程结点上的数据
        blockTransferService.fetchBlockSync(
          loc.host, loc.port, loc.executorId, blockId.toString, tempFileManager).nioByteBuffer()
      } catch {
      ...
          }
  
          // This location failed, so we retry fetch from a different one by returning null here
          null
      }
  
      if (data != null) {
        return Some(new ChunkedByteBuffer(data))
      }
      logDebug(s"The value of block $blockId is null")
    }
    logDebug(s"Block $blockId not found")
    None
  }
  ```

  通过master.getLocationsAndStatus获取blockId的所有位置，然后调用sortLocations(blockLocations)方法获取给定块的位置列表，优先考虑本地计算机，然后是同一机架上的主机，最后调用blockTransferService的fetchBlockSync方法，异步抓取远程结点上的数据，如果成功则返回值，否则从下一个位置继续fetch。

  sortLocations源码如下

  ```scala
  /**
   * Return a list of locations for the given block, prioritizing the local machine since
   * multiple block managers can share the same host, followed by hosts on the same rack.
   */
  // 返回给定块的位置列表，优先考虑本地计算机，因为多个块管理器可以共享同一主机，然后是同一机架上的主机
  private def sortLocations(locations: Seq[BlockManagerId]): Seq[BlockManagerId] = {
    // 将位置打乱，不至于每次都到同一个远程结点取出blockId对应的数据
    val locs = Random.shuffle(locations)
    // 优先考虑本地计算机
    val (preferredLocs, otherLocs) = locs.partition { loc => blockManagerId.host == loc.host }
    blockManagerId.topologyInfo match {
      case None => preferredLocs ++ otherLocs
      case Some(_) =>
        val (sameRackLocs, differentRackLocs) = otherLocs.partition {
          loc => blockManagerId.topologyInfo == loc.topologyInfo
        }
        preferredLocs ++ sameRackLocs ++ differentRackLocs
    }
  }
  ```

##### 4.Partition与Block的对应关系

RDD中重要的计算方法是iterator，代码如下：

```scala
/**
 * Internal method to this RDD; will read from cache if applicable, or otherwise compute it.
 * This should ''not'' be called by users directly, but is available for implementors of custom
 * subclasses of RDD.
 */
final def iterator(split: Partition, context: TaskContext): Iterator[T] = {
  if (storageLevel != StorageLevel.NONE) {
    // 如果存储级别不是None，先检查是否有缓存，没有则计算
    getOrCompute(split, context)
  } else {
    // 如果有检查点，那么直接读取结果，否则计算
    computeOrReadCheckpoint(split, context)
  }
}
```

iterator方法中，首先判断StorageLevel是否设置，如果没有设置，说明在DiskStore和MemoryStore中都没有存储该RDD，反之说明BlockStore中存储了该RDD。为了避免重复计算，可以将多次使用的RDD缓存起来，再次使用时直接从缓存中获取，从而提高性能。cacheManager是一个RDD缓存管理类，在getOrCompute方法中可以看到它的用法：

```scala
private[spark] def getOrCompute(partition: Partition, context: TaskContext): Iterator[T] = {
  // 获取RDD的BlockId
  // RDDBlockId建立RDD与block之间的联系
  val blockId = RDDBlockId(id, partition.index)
  var readCachedBlock = true
    // This method is called on executors, so we need call SparkEnv.get instead of sc.env.
    // SparkEnv包含了一个运行时节点所需的所有环境信息
    // BlockManager运行在每个节点上
    // 检索给定的块（如果存在），否则调用提供的`makeIterator`方法来计算块，持久化并返回其值， 如果块已成功缓存，则返回BlockResult;如果无法缓存块，则返回迭代器。
    SparkEnv.get.blockManager.getOrElseUpdate(blockId, storageLevel, elementClassTag, () => {
    ...
```

代码中使用rdd.id和partition.index构建出一个RDDBlockId对象，在构建对象的过程中，重写name方法，代码如下：

```scala
case class RDDBlockId(rddId: Int, splitIndex: Int) extends BlockId {
  override def name: String = "rdd_" + rddId + "_" + splitIndex
}
```

此时的blockId用传入的rddId和splitIndex拼凑而成，然后调用blockManager的get方法取出blockId对应的数据。

block的计算和存储是阻塞的，其他线程需要等到该block装载结束后才能操作该block。

RDD中的Transcation操作和Action操作，虽然逻辑上是在Partition上进行，但最后还是转换成了Block，实际上对数据的存储都发生在Block上。

### 三、不同Storage Level对比

Spark Storage模块中设置了不同的Storage Level，不同的存储级别在性能和容错性上各有优势。

#### 1.内存存储级别

| 存储级别          | 描述                                     | 优点                                   | 缺点                                                         |
| ----------------- | ---------------------------------------- | -------------------------------------- | ------------------------------------------------------------ |
| MEMORY_ONLY       | 只启用内存存储并保留一份数据             |                                        | 数据以对象形式存储在内存中，数据量大时容易OOM                |
| MEMORY_ONLY_2     | 将数据存储在内存并在远程结点存储一份副本 | 当本地结点数据破坏后，还有远程冗余备份 | 数据仍以对象形式存储在内存中，且在远程结点备份，增加了网络开销 |
| MEMORY_ONLY_SER   | 将数据序列化后以字节数组存放在内存       | 降低了内存消耗                         | 仍然会OOM                                                    |
| MEMORY_ONLY_SER_2 | 序列化数组同时在远程结点冗余备份数据     | 增强了抵抗风险的能力                   | 仍然会OOM，增加了网络开销                                    |

内存存储在速度上很快，但跟磁盘相比，其容量仍然很有限。

#### 2. 磁盘存储级别

| 存储级别    | 描述                                     | 优点     | 缺点       |
| ----------- | ---------------------------------------- | -------- | ---------- |
| DISK_ONLY   | 将数据通过I/O操作存储到磁盘上            |          | 访问速度慢 |
| DISK_ONLY_2 | 实用化磁盘存储，在远程结点上进行冗余备份 | 抵抗风险 |            |

#### 3.组合方式

| 存储级别              | 描述                                           |
| --------------------- | ---------------------------------------------- |
| MEMORY_AND_DISK       | 先将数据存到内存，内存放不下时溢出到磁盘中     |
| MEMORY_AND_DISK_2     | 在本地和远程结点分别保存                       |
| MEMORY_AND_DISK_SER   | 先将数据序列化存到内存，内存不足时溢出到磁盘中 |
| MEMORY_AND_DISK_SER_2 | MEMORY_AND_DISK_SER基础伤害增加了              |

#### 4.OFF_HEAP存储方式

OFF_HEAP表示堆外存储，数据存储在JVM外边，其优点是让第三方服务专门管理数据，而JVM中只负责计算，将存储和计算分离。