---
title: Hadoop源码阅读——文件系统目录树
date: 2019-02-12 21:37:06
tags: [Hadoop,HDFS,大数据]
---

HDFS以Master/Slave模式运行，主要有NameNode和DataNode两类节点，NameNode是HDFS中的主节点。

HDFS的文件和目录在内存中以树的形式存储，目录树由NameNode维护，目录树以"/"为根，通过FSDirectory类管理。在目录树中不管是文件还是目录都被看作一个INode节点，分别对应INodeFile和INodeDirectory。HDFS会将命名空间存储在NameNode本地文件系统上的fsimage文件中，由FSImage类管理，另外对HDFS的各种操作，NameNode都会将其记录在editlog文件中，由FSEditLog类管理，NameNode会周期性的合并editlog与fsimage产生新的fsimage。

<!-- more--> 

#### 一、INode相关类

如下图所示，INode是一个抽象类，INodeFile和INodeDirectory是它的子类

[![屏幕快照 2019-02-12 下午10.00.47.png](https://i.loli.net/2019/02/12/5c62d1abccedd.png)](https://i.loli.net/2019/02/12/5c62d1abccedd.png)

##### 1.INode抽象类

INode实现了INodeAttributes接口，接口包括userName、groupName、accessTime等七个字断的get方法，INode由定义了元信息（包括id、name、fullPathName、parent）的get和set接口方法，同时提供了几个基本判断方法：isFile()、isDirectory()、isSynlink()、isRoot()、isReference()

INode类的设计采用了模版模式，将userName等字段的定义留给了子类实现。如setUser()方法：

```java
/** Set user */
// 抽象方法，由子类实现
abstract void setUser(String user);

/** Set user */
// 模版方法，不可继承，供接口调用
final INode setUser(String user, int latestSnapshotId) {
  recordModification(latestSnapshotId);
  setUser(user);
  return this;
}
```

> 在模板模式（Template Pattern）中，一个抽象类公开定义了执行它的方法的方式/模板。它的子类可以按需要重写方法实现，但调用将以抽象类中定义的方式进行。这种类型的设计模式属于行为型模式。

INode中只有一个parent字段，表明当前INode的父目录，父目录只能是INodeDirectory或INodeReference之一。

##### 2.INodeWithAdditionalFields抽象类

INodeWithAdditionalFields定义了INode中没有定义的id、name、permission、modificationTime、accessTime等字段，并覆盖了INode中的抽象方法。

（1） permission字段

​	permission字断包括三个部分信息：用户信息、用户组信息、权限信息

​	PermissionStatusFormat是用来解析及处理permission字段的工具类。SerialNumberManager类中存放了用户名和用户标识、用户组名和用户组标识的对应关系，因此不必在INode中保存字符串形式的名字。

```java
static enum PermissionStatusFormat {
  MODE(null, 16),// 16个比特存放文件模式表示
  GROUP(MODE.BITS, 24), //24个比特存放用户组标识
  USER(GROUP.BITS, 24);// 24个比特存放用户名标识

  final LongBitFormat BITS;

  private PermissionStatusFormat(LongBitFormat previous, int length) {
    BITS = new LongBitFormat(name(), previous, length, 0);
  }
  // 提取最后24个比特的信息，并通过SerialNumberManager获取用户名
  static String getUser(long permission) {
    final int n = (int)USER.BITS.retrieve(permission);
    return SerialNumberManager.INSTANCE.getUser(n);
  }
  // 提取中间24个比特的信息，并通过SerialNumberManager获取用户组名
  static String getGroup(long permission) {
    final int n = (int)GROUP.BITS.retrieve(permission);
    return SerialNumberManager.INSTANCE.getGroup(n);
  }
  
  static short getMode(long permission) {
    return (short)MODE.BITS.retrieve(permission);
  }

  /** Encode the {@link PermissionStatus} to a long. */
  static long toLong(PermissionStatus ps) {
    long permission = 0L;
    final int user = SerialNumberManager.INSTANCE.getUserSerialNumber(
        ps.getUserName());
    permission = USER.BITS.combine(user, permission);
    final int group = SerialNumberManager.INSTANCE.getGroupSerialNumber(
        ps.getGroupName());
    permission = GROUP.BITS.combine(group, permission);
    final int mode = ps.getPermission().toShort();
    permission = MODE.BITS.combine(mode, permission);
    return permission;
  }
}
```

(2) features字段

INodeWithAdditionalFields.features字段保存当前INode拥有哪些特性，它是一个Feature类型的数组

```java
private static final Feature[] EMPTY_FEATURE = new Feature[0];
protected Feature[] features = EMPTY_FEATURE;
```

INodeWithAdditionalFields提供了向INode增删查特性的方法，底层是对features的操作。

##### 3.INodeDirectory类

INodeDirectory中添加了成员变量children来保存目录中所有子目录项的INode对象。

（1）子目录项相关方法

INodeDirectory作为目录容器，主要功能是维护目录中保存的文件及子目录，即维护children字段。HDFS2.6引入了快照特性，当在当前INodeDirectory创建快照之后，所有对于子目录项的操作都需要在快照内进行记录。

（2）特性相关方法

对于INodeDirectory，可以对目录添加磁盘配额特性（DirectoryWithQuotaFeature）和快照特性（SnapshotFeature）

##### 4.INodeFile类

INodeFile类保存了文件头header字段和文件对应的数据块blocks字段，

```java
// 文件头，保存当前文件有多少副本、文件数据块大小 [4-bit storagePolicyID][12-bit replication][48-bit preferredBlockSize]
private long header = 0L;
// 保存当前文件所有数据块信息
private BlockInfo[] blocks;
```

内部类INodeFile.HeaderFormat用户处理header字段，BlockInfo类报讯了数据块与文件、数据块与DataNode的对应关系。

##### 5.INodeReference类

当HDFS文件/目录处于某个快照中，并且这个文件或目录被重命名或者移动到其他路径时，该文件或目录就会存在多条访问路径，INodeReference就是为了解决这个问而生的。

>  例如：
>
> /a是hdfs中的一个普通目录，s0为/a的一个快照，在/a目录下有一个文件test。根据快照的定义，我们可以通过/a/test以及/a/snapshot/s0/test访问test文件。但是当用户将/a/test文件重命名成/x/test1时，通过快照路径/a/snapshot/s0/test将无法访问test文件，这种情况是不符合快照规范的。



[![屏幕快照 2019-02-13 上午11.28.10.png](https://i.loli.net/2019/02/13/5c638eddcccfb.png)](https://i.loli.net/2019/02/13/5c638eddcccfb.png)

上图给出了INodeReference的继承关系图。这里的WithName,WithCount,DstReference都是INodeReference的子类，同时也是INodeReference的内部类。WithName对象用于替代重命名操作前源路径中的INode对象，DstReference对象则用于替代重命名操作后目标路径中的INode对象，WithName和DstReference共同指向了一个WithCount对象，WithCount对象则指向了文件系统目录树中真正的INode对象。

INodeReference是一个抽象类，但是它继承自INode，所以他的子类可以替代文件系统目录中的INodeFile节点，INodeReference定义了referred字段，用以保存当前INodeReference类指向的INode节点。

* org.apache.hadoop.hdfs.server.namenode.INodeReference.WithCount#WithCount

```java
/** An anonymous reference with reference count. */
public static class WithCount extends INodeReference {
// 保存所有指向这个WithCount对象的WithName对象的集合
  private final List<WithName> withNameList = new ArrayList<>();
  ...
   /** Increment and then return the reference count. */
    // 任何指向WithCount的withName对象和DstReference对象都需要调用这个方法来添加指向关系
    public void addReference(INodeReference ref) {
      if (ref instanceof WithName) {// 如果是WithName对象，添加到withNameList
        WithName refWithName = (WithName) ref;
        int i = Collections.binarySearch(withNameList, refWithName,
            WITHNAME_COMPARATOR);
        Preconditions.checkState(i < 0);
        withNameList.add(-i - 1, refWithName);
      } else if (ref instanceof DstReference) {
        setParentReference(ref);// 如果是DstReference指向这个对象，将它设置为自己的父节点
      }
    }
...
```

* org.apache.hadoop.hdfs.server.namenode.INodeReference.WithName

  ```java
  /** A reference with a fixed name. */
  public static class WithName extends INodeReference {
    // 保存重命名前文件的名字
    private final byte[] name;
  
    /**
     * The id of the last snapshot in the src tree when this WithName node was 
     * generated. When calculating the quota usage of the referred node, only 
     * the files/dirs existing when this snapshot was taken will be counted for 
     * this WithName node and propagated along its ancestor path.
     */
    private final int lastSnapshotId;
    
    public WithName(INodeDirectory parent, WithCount referred, byte[] name,
        int lastSnapshotId) {
      super(parent, referred);// 调用父类的构造方法，指向WithCount节点
      this.name = name;
      this.lastSnapshotId = lastSnapshotId;
      referred.addReference(this);// *
    }
      ...
  ```

建立INodeReference的入口是FSDirRenameOp.RenameOperation，只有在进行rename操作时才有可能创建INodeReference

```java
RenameOperation(FSDirectory fsd, INodesInPath srcIIP, INodesInPath dstIIP)
    throws QuotaExceededException {
  this.fsd = fsd;
  this.srcIIP = srcIIP;
  this.dstIIP = dstIIP;
  this.srcParentIIP = srcIIP.getParentINodesInPath();
  this.dstParentIIP = dstIIP.getParentINodesInPath();

  BlockStoragePolicySuite bsps = fsd.getBlockStoragePolicySuite();
  srcChild = this.srcIIP.getLastINode();
  srcChildName = srcChild.getLocalNameBytes();
  final int srcLatestSnapshotId = srcIIP.getLatestSnapshotId();
  isSrcInSnapshot = srcChild.isInLatestSnapshot(srcLatestSnapshotId);
  srcChildIsReference = srcChild.isReference();
  srcParent = this.srcIIP.getINode(-2).asDirectory();

  // Record the snapshot on srcChild. After the rename, before any new
  // snapshot is taken on the dst tree, changes will be recorded in the
  // latest snapshot of the src tree.
  if (isSrcInSnapshot) {
    srcChild.recordModification(srcLatestSnapshotId);
  }

  // check srcChild for reference
  srcRefDstSnapshot = srcChildIsReference ?
      srcChild.asReference().getDstSnapshotId() : Snapshot.CURRENT_STATE_ID;
  oldSrcCounts = new QuotaCounts.Builder().build();
  if (isSrcInSnapshot) {// 如果源节点在快照中，调用replaceChild4ReferenceWithName构造INodeReference.WithName对象
    final INodeReference.WithName withName = srcParent
        .replaceChild4ReferenceWithName(srcChild, srcLatestSnapshotId);
    withCount = (INodeReference.WithCount) withName.getReferredINode();
    srcChild = withName;
    this.srcIIP = INodesInPath.replace(srcIIP, srcIIP.length() - 1,
        srcChild);
    // get the counts before rename
    oldSrcCounts.add(withCount.getReferredINode().computeQuotaUsage(bsps));
  } else if (srcChildIsReference) {
    // srcChild is reference but srcChild is not in latest snapshot
    withCount = (INodeReference.WithCount) srcChild.asReference()
        .getReferredINode();
  } else {
    withCount = null;// 否则将withCount设置为null，作为普通重命名操作
  }
}
```

```java
// 将源节点或者dst节点添加到目标路径
INodesInPath addSourceToDestination() {
  final INode dstParent = dstParentIIP.getLastINode();
  final byte[] dstChildName = dstIIP.getLastLocalName();
  final INode toDst;
  if (withCount == null) {// 普通rename操作，不需要INodeReference机制
    srcChild.setLocalName(dstChildName);
    toDst = srcChild;
  } else {
    withCount.getReferredINode().setLocalName(dstChildName);
    toDst = new INodeReference.DstReference(dstParent.asDirectory(),
        withCount, dstIIP.getLatestSnapshotId());
  }
  // 将toDst添加到目标路径
  return fsd.addLastINodeNoQuotaCheck(dstParentIIP, toDst);
}
```

#### 二、Feature相关类

[![屏幕快照 2019-02-13 下午2.26.02.png](https://i.loli.net/2019/02/13/5c63b88639e08.png)](https://i.loli.net/2019/02/13/5c63b88639e08.png)

##### 1.SnapshotFeature

快照是一个文件系统或者文件系统中某个目录在某一时刻的镜像。目标目录的快照创建之后，不论目标目录发生什么变化，或者目标目录子目录发生任何变化，都可以通过快照找回快照建立时目标目录的所有文件以及目录结构。

同一个目录可以创建多个快照，它们通过名字来区分。

（1）快照相关类

HDFS中定义了DirectorySnapshottableFeature和DirectoryWithSnapshotFeature两个类来描述目录的快照特性。

DirectorySnapshottableFeature描述了目录开启快照功能的特性，DirectoryWithSnapshotFeature描述了目录拥有的快照的特性。DirectoryDiff类记录了两个快照版本之间进行的所有操作，DirectoryDiff使用ChildrenDiff类记录HDFS目录的子目录项集合children的变化情况。ChildrenDiff中有两个List created和deleted分别保存快照创建之后新创建的子目录项和删除的子目录项。

#### 三、FSEditLog类

在NameNode中，命名空间是全部被缓存在内存中的，一旦NameNode重启或者宕机，内存中的数据将会全部丢失。因此，NameNode将命名空间信息记录在fsimage文件中，用于在重启时重构命名空间，但是fsimage文件存储在磁盘上，不能实时和内存中的数据结构保持同步，而且fsimage一般很大，所以namenode隔一段时间才更新一次fsimage，HDFS将操作记录在editlog文件中， 定期与fsimage文件合并，FSEditLog类用来管理editlog文件，editlog随着namenode实时更新，所有FSEditLog的实现依赖于底层的输入输出流。

##### 1.TransactionId机制

TransactionId与客户端每次发起的RPC请求有关，当客户端发起一次RPC请求对NameNode的命名空间进行修改后，NameNode就会在editlog中发起一个新的transaction用于记录这次操作，每个transaction会用一个唯一的transactionId标识。

##### 2.FSEditLog状态机

FSEditLog被设计成一个状态机：

> UNINITIALIZED: editlog的初始状态
> BETWEEN_LOG_SEGMENTS:editlog的前一个segment已经关闭，另一个还没开始
> IN_SEGMENT:editlog处于可写阶段
> OPEN_FOR_READING:可读阶段
> CLOSED:关闭状态

In a non-HA setup:

The log starts in UNINITIALIZED state upon construction. Once it's initialized, it is usually in IN_SEGMENT state, indicating that edits may be written. In the middle of a roll, or while saving the namespace, it briefly enters the BETWEEN_LOG_SEGMENTS state, indicating that the previous segment has been closed, but the new one has not yet been opened.

In an HA setup: 

The log starts in UNINITIALIZED state upon construction. Once it's initialized, it sits in the OPEN_FOR_READING state the entire time that the NN is in standby. Upon the NN transition to active, the log will be CLOSED, and then move to being BETWEEN_LOG_SEGMENTS, much as if the NN had just started up, and then will move to IN_SEGMENT so it can begin writing to the log. The log states will then revert to behaving as they do in a non-HA setup.

* initJournalsForWrite将UNINITIALIZED状态转换为BETWEEN_LOG_SEGMENTS，其间调用了initJournals方法

JournalManager类是负责在特定存储目录上持久化editlog文件的类。他有多个子类，普通文件系统由FileJournalManager管理，NFS、BookKeeper等文件系统有对应的JournalManager子类管理。

```java
private synchronized void initJournals(List<URI> dirs) {
  int minimumRedundantJournals = conf.getInt(
      DFSConfigKeys.DFS_NAMENODE_EDITS_DIR_MINIMUM_KEY,
      DFSConfigKeys.DFS_NAMENODE_EDITS_DIR_MINIMUM_DEFAULT);

  synchronized(journalSetLock) {
    // 初始化journalSet， 存放存储路径对应的所有JournalManager对象
    journalSet = new JournalSet(minimumRedundantJournals);

    for (URI u : dirs) {
      boolean required = FSNamesystem.getRequiredNamespaceEditsDirs(conf)
          .contains(u);
      // 如果是本地URl，则使用FileJournalManager
      if (u.getScheme().equals(NNStorage.LOCAL_URI_SCHEME)) {
        StorageDirectory sd = storage.getStorageDirectory(u);
        if (sd != null) {
          journalSet.add(new FileJournalManager(conf, sd, storage),
              required, sharedEditsDirs.contains(u));
        }
      } else {
          // 否则根据URL创建对应的JournalManager
        journalSet.add(createJournal(u), required,
            sharedEditsDirs.contains(u));
      }
    }
  }

  if (journalSet.isEmpty()) {
    LOG.error("No edits directories configured!");
  } 
}
```

* initSharedJournalsForRead

```java
// 用在HA情况下，将editlog由UNINITIALIZED转到OPEN_FOR_READING
public synchronized void initSharedJournalsForRead() {
  if (state == State.OPEN_FOR_READING) {
    LOG.warn("Initializing shared journals for READ, already open for READ",
        new Exception());
    return;
  }
  Preconditions.checkState(state == State.UNINITIALIZED ||
      state == State.CLOSED);
  // 对于HA的情况，editlog的日志存储目录为共享的目录sharedEditsDirs，由Active Namenode与 StandBy NameNode共享
  initJournals(this.sharedEditsDirs);
  state = State.OPEN_FOR_READING;
}
```

* openForWrite()

* ```java
  /**
   * Initialize the output stream for logging, opening the first
   * log segment.
   */
  synchronized void openForWrite(int layoutVersion) throws IOException {
    Preconditions.checkState(state == State.BETWEEN_LOG_SEGMENTS,
        "Bad state: %s", state);
    // 返回最后一个写入log的TxId+1，作为本次的TxId
    long segmentTxId = getLastWrittenTxId() + 1;
    // Safety check: we should never start a segment if there are
    // newer txids readable.
    List<EditLogInputStream> streams = new ArrayList<EditLogInputStream>();
    // 判断，有没有包含这个新的segmentTxId的editlog的问文件，有则抛出异常
    journalSet.selectInputStreams(streams, segmentTxId, true);
    if (!streams.isEmpty()) {
      String error = String.format("Cannot start writing at txid %s " +
        "when there is a stream available for read: %s",
        segmentTxId, streams.get(0));
      IOUtils.cleanup(LOG, streams.toArray(new EditLogInputStream[0]));
      throw new IllegalStateException(error);
    }
    //开始记录新的段落，创建edits_inprogress_* 文件
    startLogSegment(segmentTxId, true, layoutVersion);
    assert state == State.IN_SEGMENT : "Bad state: " + state;
  }
  ```

* startLogSegment()

* ```java
  /**
   * Start writing to the log segment with the given txid.
   * Transitions from BETWEEN_LOG_SEGMENTS state to IN_LOG_SEGMENT state. 
   */
  synchronized void startLogSegment(final long segmentTxId,
      boolean writeHeaderTxn, int layoutVersion) throws IOException {
    ...
    numTransactions = 0;
    totalTimeTransactions = 0;
    numTransactionsBatchedInSync.set(0L);
  
    // TODO no need to link this back to storage anymore!
    // See HDFS-2174.
      // 检查是否有可以重新服务的storage
    storage.attemptRestoreRemovedStorage();
    // 初始化editLogStream
    try {
     //journalSet.startLogSegment在所有editlog文件的存储路径上构造输出流，并将这些输出流保存在FSEditLog的journalSet。journals中
      editLogStream = journalSet.startLogSegment(segmentTxId, layoutVersion);
    } catch (IOException ex) {
      throw new IOException("Unable to start log segment " +
          segmentTxId + ": too few journals successfully started.", ex);
    }
    // 将当前正在写入TxId设置为segmentTxId
    curSegmentTxId = segmentTxId;
    state = State.IN_SEGMENT;
  
    if (writeHeaderTxn) {
      logEdit(LogSegmentOp.getInstance(cache.get(),
          FSEditLogOpCodes.OP_START_LOG_SEGMENT));
      logSync();
    }
  }
  ```