---
title: Hadoop源码阅读——HDFS
date: 2018-11-15 13:58:39
tags: [Hadoop,HDFS,大数据]
---

#### 系统架构

HDFS是一个主/从结构的分布式系统，拥有一个NameNode和一些DateNode，HDFS中NameNode是Master节点，负责管理文件系统的命名空间，以及数据块到DateNode的映射信息。DateNode一般一个节点一个，负责管理它所在节点上的存储。

<!-- more--> 

![hdfsarchitecture.png](https://i.loli.net/2018/11/15/5bed54fc16112.png)

数据块是HDFS文件处理的最小单元，为最小化寻址开销，HDFS数据块也更大，默认128MB，数据块以文件形式存储在数据节点的磁盘上。

NameNode是HDFS中的单一故障点，Hadoop2.X引入了NameNode的HA支持，同一个HDFS集群中会配置两个NameNode节点：二者完全同步。

NameNode中保存了数据块与DateNode的对应关系，因此当集群中文件过多时，NameNode将成为限制系统横向扩展的瓶颈。因此Hadoop2.X引入了联邦HDFS机制，允许添加NameNode以实现命名空间的扩展，每个NameNode都管理文件系统命名空间中的一部分，是一个独立的命名空间卷，命名空间卷之间相互独立。

##### NameNode安全模式

安全模式是NameNode的一种状态，处于安全模式的NameNode不接受客户端对命名空间的修改操作，整个NameSpace处于只读状态。同时NameNode不会对DataNode下发任何数据块的复制、删除指令。

刚刚启动的NameNode会直接进入SafeMode，当NameNode中保存的满足最小副本系数的数据块达到一定比例时，NameNode会自动退出安全模式。而对于用户通过dfsAdmin方式触发的安全模式，则只能由管理员手动退出。

##### HFDS通信协议

HDFS节点间的接口主要有两种类型：

- Hadoop RPC接口：HDFS中基于Hadoop RPC框架实现的接口
- 流式接口：HDFS中基于TCP或者HTTP实现的接口

##### DataNodeProtocal

DataNodeProtocal是Hadoop RPC接口之一，datanode uses DataNodeProtocal to communicate with the NameNode.同时NameNode会通过这个接口中方法的返回值向数据节点下发指令，它是NameNode和DataNode通信的唯一方式。

DataNodeProtocal定义的方法主要分为三种类型：DataNode启动相关、心跳相关和数据读写相关。方法如下：

![屏幕快照 2018-11-15 下午8.41.29.png](https://i.loli.net/2018/11/15/5bed6989940d8.png)

###### DataNode启动相关

一个完整的DataNode启动会与NameNode进行四次交互，首先调用versionRequest()与NameNode 进行握手操作，然后调用registerDatanode()向NameNode注册当前DataNode，接着调用blockReport()汇报本节点存储的所有数据块，最后调用cacheReport()汇报DataNode缓存的所有数据块

* DataNode启动时先调用versionRequest()与NameNode握手，返回一个NamespaceInfo对象，包含了当前HDFS集群NameSpace信息，DataNode获取到该信息后会比较DataNode当前HDFS版本号与NameNode的版本号是否能协同工作，若不能则抛出异常。

* 握手成功后，DataNode调用registerDatanode()向NameNode注册当前DataNode，参数是一个DatanodeRegistration对象，它contains all information the name-node needs to identify and verify a data-node when it contacts the name-node.NameNode会判断DataNode的软件版本号与NameNode的是否兼容，如果兼容则注册并返回一个DatanodeRegistration对象供DataNode后续使用。


* 成功注册之后，DataNode通过blockReport()汇报本节点存储的所有数据块，NameNode接收到blockReport()请求后，根据上报的数据块存储情况建立数据块与DataNode之间的对应关系。

  blockReport()方法只在DataNode启动时以指定间隔执行一次

##### InterDatanodeProtocol

An inter-datanode protocol for updating generation stamp

##### DatanodeLifelineProtocol

Protocol used by a DataNode to send lifeline messages to a NameNode.

##### JournalProtocol

Protocol used to journal edits to a remote node. Currently,this is used to publish edits from the NameNode to a BackupNode.

This class is used by both the Namenode (client) and BackupNode (server) to insulate from the protocol serialization.

##### NamenodeProtocol

Protocol that a secondary NameNode uses to communicate with the NameNode.It's used to get part of the name node state

##### ClientProtocol

ClientProtocol is used by user code via the DistributedFileSystem class to communicate with the NameNode.  User code can manipulate the directory namespace, as well as open/close file streams, etc.

##### ClientDatanodeProtocol

 An client-datanode protocol for block recovery，This class is used by both the DFSClient and the DN server side to insulate from the protocol serialization.

##### HAServiceProtocol

