---
title: Hadoop源码阅读——高可用性
date: 2019-02-15 10:13:14
tags: [Hadoop,HDFS,大数据]
---

​	在HA HDFS集群中会同时运行两个NameNode，一个作为活动的Namenode，一个作为备份的Namenode，备份Namenode的命名空间与活动Namenode的命名空间是实时同步的。所以当活动Namenode发生故障而停止服务时，备份Namenode可以立即切换为活动状态。

[![屏幕快照 2019-02-15 上午10.24.28.png](https://i.loli.net/2019/02/15/5c662304d82ab.png)](https://i.loli.net/2019/02/15/5c662304d82ab.png)<!-- more--> 

如图所示，为了使备份节点与活动节点的状态同步一致，。两个节点都需要与一组堵路运行的节点（JournalNodes，JNS）通信，。当活动Namenode执行了修改命名空间的操作时，他会定期将执行的操作记录在editlog中，并写入JNS的多数节点中。而备份Namenode会一直监听JNS上editlog的变化，如果发现editlog有改动，备份Namenode会读取editlog并与当前命名空间合并，当发生错误切换时，备份节点会先保证从JNS上读取了多有editlog并与命名空间合并，然后才会从Standby状态切换为Active状态。

为了使错误切换能够很快地执行完毕，Datenode会向阿两个Namenode发送心跳以及汇报信息。这样活动Namenode与备份Namenode的元数据就完全同步， 一旦发生故障，就可以马上切换，这就是**热备**。

> 脑裂：两个Namenode同时修改命名空间

为防止**脑裂**， HDFS提供了三个级别的隔离机制：

* 共享存储隔离：同一时间只允许一个Namenode向JournalNodes写入editlog数据
* 客户端隔离：同一时间只允许一个Namenode响应客户端请求
* Datenode隔离：同一时间只允许一个Namenode向Datenode的下发名字节点指令

HDFS提供了两种HA状态切换方式：一种是管理员通过手动命令执行状态切换，另一种是自动状态切换机制触发状态切换。前者是由客户端调用HAAdmin类提供的方法实现，后者由ZKFailoverController控制切换流程，他们两个最终都调用了RPC接口HAServiceProtocol向Namenode发送HA请求，到达Namenode后，会由NameNodeRPCServer类响应。

##### （1）HAServiceProtocol

HDFS的HA管理命令底层搜室友Client调用远程RPC接口HAServiceProtocol实现的

[![屏幕快照 2019-02-15 上午11.23.52.png](https://i.loli.net/2019/02/15/5c6630e955cb9.png)](https://i.loli.net/2019/02/15/5c6630e955cb9.png)

* org.apache.hadoop.hdfs.server.namenode.NameNodeRpcServer#transitionToActive

```java
@Override // HAServiceProtocol
public synchronized void transitionToActive(StateChangeRequestInfo req) 
    throws ServiceFailedException, AccessControlException, IOException {
  checkNNStartup();// 检查Namenode是否开启
  nn.checkHaStateChange(req);// 检查这次状态切换是否合法
  nn.transitionToActive();
}
```

* org.apache.hadoop.hdfs.server.namenode.NameNode#transitionToActive

```java
synchronized void transitionToActive() 
    throws ServiceFailedException, AccessControlException {
  namesystem.checkSuperuserPrivilege();
  if (!haEnabled) {
    throw new ServiceFailedException("HA for namenode is not enabled");
  }
  //修改HAState为active
  state.setState(haContext, ACTIVE_STATE);
}
```

setState()方法会调用setStateInternal(context, s)方法执行内部的状态转移流程。

```java
/**
 * Internal method to move from the existing state to a new state.
 * @param context HA context
 * @param s new state
 * @throws ServiceFailedException on failure to transition to new state.
 */
protected final void setStateInternal(final HAContext context, final HAState s)
    throws ServiceFailedException {
  prepareToExitState(context); // 取消Standby Namenode上进行的检查点操作
  s.prepareToEnterState(context);
  context.writeLock();
  try {
    exitState(context);// 停止当前活动节点或备份节点的服务
    context.setState(s); //将NameNodeHAContext中保存的Namenode状态设置为指定状态
    s.enterState(context);// 启动指定状态的所有服务
    s.updateLastHATransitionTime(); // 更新时间
  } finally {
    context.writeUnlock();
  }
}
```

exitState()会调用context.stopStandbyServices()停止当前Standby Namenode的所有服务。

```java
/** Stop services required in standby state */
void stopStandbyServices() throws IOException {
  LOG.info("Stopping services started for standby state");
  if (standbyCheckpointer != null) {
    //关闭进行检查点操作的standbyCheckpointer线程
    standbyCheckpointer.stop();
  }
  // 关闭监控editlog内容的editLogTailer线程
  if (editLogTailer != null) {
    editLogTailer.stop();
  }
  // 关闭当前editLog
  if (dir != null && getFSImage() != null && getFSImage().editLog != null) {
    getFSImage().editLog.close();
  }
}
```

启动指定状态的所有服务的enterState最终由FSNamesystem#startActiveServices()方法实现。

```java
/**
 * Start services required in active state
 * @throws IOException
 */
void startActiveServices() throws IOException {
  startingActiveService = true;
  LOG.info("Starting services required for active state");
  writeLock();
  try {
      // 开启新的editlog输出流
    FSEditLog editLog = getFSImage().getEditLog();
    
    if (!editLog.isOpenForWrite()) {
      // During startup, we're already open for write during initialization.
        // 对editlog进行恢复操作，与之前的Active节点同步editlog内容
      editLog.initJournalsForWrite();
      // May need to recover
      editLog.recoverUnclosedStreams();
      
      LOG.info("Catching up to latest edits from old active before " +
          "taking over writer role in edits logs");
      editLogTailer.catchupDuringFailover();
      // 不再延迟处理数据块
      blockManager.setPostponeBlocksFromFuture(false);
      // 新启动的Active Namenode需要等待所有Datanode更新心跳后再出发删除与复制操作
      blockManager.getDatanodeManager().markAllDatanodesStale();
      // 清除blockmanager中的所有队列
      blockManager.clearQueues();
      // 处理之前由于Namenode信息不完整而延迟处理的数据块
      blockManager.processAllPendingDNMessages();

      // Only need to re-process the queue, If not in SafeMode.
      if (!isInSafeMode()) {
        LOG.info("Reprocessing replication and invalidation queues");
        blockManager.initializeReplQueues();
      }

      if (LOG.isDebugEnabled()) {
        LOG.debug("NameNode metadata after re-processing " +
            "replication and invalidation queues during failover:\n" +
            metaSaveAsString());
      }
      // 读取最新的txid，重置editlog的txid，之后打开editlog
      long nextTxId = getFSImage().getLastAppliedTxId() + 1;
      LOG.info("Will take over writing edit logs at txnid " + 
          nextTxId);
      editLog.setNextTxId(nextTxId);

      getFSImage().editLog.openForWrite(getEffectiveLayoutVersion());
    }

    // Initialize the quota.
    dir.updateCountForQuota();
    // Enable quota checks.
    dir.enableQuotaChecks();
    if (haEnabled) {
      // Renew all of the leases before becoming active.
      // This is because, while we were in standby mode,
      // the leases weren't getting renewed on this NN.
      // Give them all a fresh start here.
      leaseManager.renewAllLeases();
    }
    leaseManager.startMonitor();
    startSecretManagerIfNecessary();

    //ResourceMonitor required only at ActiveNN. See HDFS-2914
    this.nnrmthread = new Daemon(new NameNodeResourceMonitor());
    nnrmthread.start();

    nnEditLogRoller = new Daemon(new NameNodeEditLogRoller(
        editLogRollerThreshold, editLogRollerInterval));
    nnEditLogRoller.start();

    if (lazyPersistFileScrubIntervalSec > 0) {
      lazyPersistFileScrubber = new Daemon(new LazyPersistFileScrubber(
          lazyPersistFileScrubIntervalSec));
      lazyPersistFileScrubber.start();
    } else {
      LOG.warn("Lazy persist file scrubber is disabled,"
          + " configured scrub interval is zero.");
    }
  //启动cacheManager监控线程
    cacheManager.startMonitorThread();
    blockManager.getDatanodeManager().setShouldSendCachingCommands(true);
    if (provider != null) {
      edekCacheLoader = Executors.newSingleThreadExecutor(
          new ThreadFactoryBuilder().setDaemon(true)
              .setNameFormat("Warm Up EDEK Cache Thread #%d")
              .build());
      FSDirEncryptionZoneOp.warmUpEdekCache(edekCacheLoader, dir,
          edekCacheLoaderDelay, edekCacheLoaderInterval);
    }
  } finally {
    startingActiveService = false;
    checkSafeMode();
    writeUnlock("startActiveServices");
  }
}
```

* getServiceStatus方法用于获取当前Namenode服务的状态

  ```java
  synchronized HAServiceStatus getServiceStatus()
      throws ServiceFailedException, AccessControlException {
    namesystem.checkSuperuserPrivilege();
    if (!haEnabled) {
      throw new ServiceFailedException("HA for namenode is not enabled");
    }
    if (state == null) {
      return new HAServiceStatus(HAServiceState.INITIALIZING);
    }
    HAServiceState retState = state.getServiceState();
    HAServiceStatus ret = new HAServiceStatus(retState);
    if (retState == HAServiceState.STANDBY) {
      String safemodeTip = namesystem.getSafeModeTip();
      // Styandby状态，但是处于safemode，则不可以切换为Active状态
      if (!safemodeTip.isEmpty()) {
        ret.setNotReadyToBecomeActive(
            "The NameNode is in safemode. " +
            safemodeTip);
      } else {
        // 否则可以随时切换为Active状态
        ret.setReadyToBecomeActive();
      }
    } else if (retState == HAServiceState.ACTIVE) {
      ret.setReadyToBecomeActive();
    } else {
      ret.setNotReadyToBecomeActive("State is " + state);
    }
    return ret;
  }
  ```

##### (2) HAAdmin

HA管理命令的执行是由HAAdmin类负责的。HAAdmin的runCmd()方法会对管理命令进行判断，如果是'-failover	',也就是进行故障转移和切换Namenode状态的方法，HAAdmin会调用failover()方法。

```java
private int failover(CommandLine cmd)
    throws IOException, ServiceFailedException {
  // 解析命令行是否开启了forcefence和forceactive
  boolean forceFence = cmd.hasOption(FORCEFENCE);
  boolean forceActive = cmd.hasOption(FORCEACTIVE);

  int numOpts = cmd.getOptions() == null ? 0 : cmd.getOptions().length;
  final String[] args = cmd.getArgs();

  if (numOpts > 3 || args.length != 2) {
    errOut.println("failover: incorrect arguments");
    printUsage(errOut, "-failover");
    return -1;
  }
// 解析源节点和目标节点
  HAServiceTarget fromNode = resolveTarget(args[0]);
  HAServiceTarget toNode = resolveTarget(args[1]);
  
  // Check that auto-failover is consistently configured for both nodes.
  Preconditions.checkState(
      fromNode.isAutoFailoverEnabled() ==
        toNode.isAutoFailoverEnabled(),
        "Inconsistent auto-failover configs between %s and %s!",
        fromNode, toNode);
  // 如果是自动切换模式，则不可以设置forceFence以及forceActive
  if (fromNode.isAutoFailoverEnabled()) {
    if (forceFence || forceActive) {
      // -forceActive doesn't make sense with auto-HA, since, if the node
      // is not healthy, then its ZKFC will immediately quit the election
      // again the next time a health check runs.
      //
      // -forceFence doesn't seem to have any real use cases with auto-HA
      // so it isn't implemented.
      errOut.println(FORCEFENCE + " and " + FORCEACTIVE + " flags not " +
          "supported with auto-failover enabled.");
      return -1;
    }
    try {
      return gracefulFailoverThroughZKFCs(toNode);
    } catch (UnsupportedOperationException e){
      errOut.println("Failover command is not supported with " +
          "auto-failover enabled: " + e.getLocalizedMessage());
      return -1;
    }
  }
  // 构造FailoverController对象，并调用failover()方法执行切换操作
  FailoverController fc = new FailoverController(getConf(),
      requestSource);
  
  try {
    fc.failover(fromNode, toNode, forceFence, forceActive); 
    out.println("Failover from "+args[0]+" to "+args[1]+" successful");
  } catch (FailoverFailedException ffe) {
    errOut.println("Failover failed: " + ffe.getLocalizedMessage());
    return -1;
  }
  return 0;
}
```

FailoverController.failover()方法将执行切换操作，会调用上面提到的HAServiceProtocol的transitionToActive()和transitionToStandby()方法，同时在将目标节点切换至Active状态前执行fencing操作，如果切换失败，则执行会滚操作。

> fencing:在故障转移期间，在启动备份节点前，我们首先要确保活动节点处于等待状态，或者进程被中止，为了达到这个目的，您至少要配置一个强行中止的方法，或者回车分隔的列表，这是为了一个一个的尝试中止，直到其中一个返回成功，表明活动节点已停止。hadoop提供了两个方法：shell和sshfence.

```java
/**
   * Failover from service 1 to service 2. If the failover fails
   * then try to failback.
   *
   * @param fromSvc currently active service
   * @param toSvc service to make active
   * @param forceFence to fence fromSvc even if not strictly necessary
   * @param forceActive try to make toSvc active even if it is not ready
   * @throws FailoverFailedException if the failover fails
   */
  public void failover(HAServiceTarget fromSvc,
                       HAServiceTarget toSvc,
                       boolean forceFence,
                       boolean forceActive)
      throws FailoverFailedException {

    Preconditions.checkArgument(fromSvc.getFencer() != null,
        "failover requires a fencer");
    // 调用preFailoverChecks进行检查，如源节点和目标节点是否是同一个节点，目标节点是否已经是Active状态、目标节点是否有足够磁盘空间切换为Active状态
    preFailoverChecks(fromSvc, toSvc, forceActive);

    // Try to make fromSvc standby
    boolean tryFence = true;
    // tryGracefulFence调用HAServiceProtocol.transitionToStandby()将源节点切换为Standby状态
    if (tryGracefulFence(fromSvc)) {
      tryFence = forceFence;
    }

    // Fence fromSvc if it's required or forced by the user
    if (tryFence) {
      if (!fromSvc.getFencer().fence(fromSvc)) {
        throw new FailoverFailedException("Unable to fence " +
            fromSvc + ". Fencing failed.");
      }
    }

    // Try to make toSvc active
    boolean failed = false;
    Throwable cause = null;
    try {
      // 切换目标节点到Active状态
      HAServiceProtocolHelper.transitionToActive(
          toSvc.getProxy(conf, rpcTimeoutToNewActive),
          createReqInfo());
    } catch (ServiceFailedException sfe) {
      LOG.error("Unable to make " + toSvc + " active (" +
          sfe.getMessage() + "). Failing back.");
      failed = true;
      cause = sfe;
    } catch (IOException ioe) {
      LOG.error("Unable to make " + toSvc +
          " active (unable to connect). Failing back.", ioe);
      failed = true;
      cause = ioe;
    }

    // We failed to make toSvc active 回滚
    if (failed) {
      String msg = "Unable to failover to " + toSvc;
      // Only try to failback if we didn't fence fromSvc
      // 如果没有fencing源节点，则回滚到原来的状态
      // 如果源节点已经fencing，则抛出异常
      if (!tryFence) {
        try {
          // Unconditionally fence toSvc in case it is still trying to
          // become active, eg we timed out waiting for its response.
          // Unconditionally force fromSvc to become active since it
          // was previously active when we initiated failover.
          failover(toSvc, fromSvc, true, true);
        } catch (FailoverFailedException ffe) {
          msg += ". Failback to " + fromSvc +
            " failed (" + ffe.getMessage() + ")";
          LOG.fatal(msg);
        }
      }
     
      throw new FailoverFailedException(msg, cause);
    }
  }
}
```

##### (3) Quorum Journal

在典型的HA集群中，两台独立的机器被配置为NameNode。在任何时候，只有一个NameNodes处于Active状态，另一个处于Standby状态。活动NameNode负责群集中的所有客户端操作，而Standby仅充当从属服务器，并保持足够的状态以在必要时提供快速故障转移。

为了让备用节点保持其与活跃节点的状态同步，两个节点都与一组称为“日志节点”（Journal Node）的独立守护进程进行通信。当活动节点执行任何名称空间修改时，它会将修改记录持久记录到大多数这些JN中。备用节点能够读取来自JN的编辑，并不断监视它们以更改编辑日志。当待机节点看到编辑时，它将它们应用到它自己的名称空间。如果发生故障转移，备用服务器将确保在将自己提升为活动状态之前，已经从JounalNodes中读取所有编辑。这确保了在故障转移发生之前命名空间状态已完全同步。

为了提供快速故障切换，备用节点还需要有关于集群中块的位置的最新信息。为了实现这一点，DataNode配置了两个NameNode的位置，并将块位置信息和心跳发送到两者。

HA群集的正确操作对于一次只有一个NameNode处于活动状态至关重要。否则，命名空间状态将很快在两者之间发生分歧，从而可能导致数据丢失或其他不正确的结果。为了确保这个属性并防止所谓的“裂脑场景”，JournalNodes一次只允许一个NameNode成为活跃节点。在故障转移期间，要成为活动状态的NameNode将简单地接管写入JournalNodes的角色，这将有效地防止其他NameNode继续处于活动状态，从而允许新的活动安全地进行故障转移。

Quorum Journal方案是一种预防脑裂情况的机制，具体结构如下：

[![屏幕快照 2019-02-15 下午8.47.37.png](https://i.loli.net/2019/02/15/5c66b5186824c.png)](https://i.loli.net/2019/02/15/5c66b5186824c.png)

* **JournalNode(JN)**:运行在N台独立的机器上，将editlog保存在JournalNode本地磁盘上，同时提供RPC接口以执行远程读editlog文件的功能
* **QuorumJournalManager(QJM)**:运行在Namenode上，通过PRC接口向JournalNode发送写入、互斥、同步editlog