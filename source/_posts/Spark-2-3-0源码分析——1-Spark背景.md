---
title: Spark_2.3.0源码分析——1_Spark背景
date: 2018-10-02 21:50:35
tags: [大数据, Spark]
---

从今天开始阅读Spark 2.3.0的源码，以加深对Spark的理解，之后会有Hadoop、kafka的源码分析，希望自己能坚持下来✊。

我会参照着官方的技术文档和一本参考书《Saprk技术内幕》完成本次分析，书的版本较老，因此会将其作为一个支撑框架，具体的内容会以实际源码和技术文档为主。下载源码和编译的过程网上有许多教程，这里不赘述。

<!-- more-->

#### 一、技术背景

Apache Spark 是一个快速的, 多用途的集群计算系统。 它提供了 Java, Scala, Python 和 R 的高级 API，以及一个支持通用的执行图计算的优化过的引擎. 它还支持一组丰富的高级工具, 包括使用 SQL 处理结构化数据处理的 [Spark SQL](http://spark.apachecn.org/docs/cn/2.2.0/sql-programming-guide.html), 用于机器学习的 [MLlib](http://spark.apachecn.org/docs/cn/2.2.0/ml-guide.html), 用于图计算的 [GraphX](http://spark.apachecn.org/docs/cn/2.2.0/graphx-programming-guide.html), 以及 [Spark Streaming](http://spark.apachecn.org/docs/cn/2.2.0/streaming-programming-guide.html)。

​	像 MapReduce 和 Dryad 等分布式计算框架已经广泛应用于大数据集的分析. 这些系统可以让用户不用担心分布式工作以及容错, 而是使用一系列的高层次的操作 api 来达到并行计算的目的.

​	虽然当前的框架提供了大量的对访问利用计算资源的抽象, 但是它们缺少了对利用分布式内存的抽象.样使的它们在处理需要在多个计算之间复用中间结果的应用的时候会非常的不高效. 数据的复用在迭代机器学习和图计算领域（比如 PageRank, K-means 以及线性回归等算法）是很常见的. 在交互式数据挖掘中, 一个用户会经常对一个相同的数据子集进行多次不同的特定查询, 所以数据复用在交互式数据挖掘也是很常见的. 然而, 目前的大部分的框架对计算之间的数据复用的处理方式就是将中间数据写到一个靠稳定的系统中（比如分布式文件系统）, 这样会由于数据的复制备份, 磁盘的 I/O 以及数据的序列化而致应用任务执行很费时间.

​	大多数现有的集群计算系统都是基于非循环的数据流模型。即从稳定的物理存储(如分布式文件系统)中加载记录，记录被传入由一组确定性操作构成的DAG，然后写回稳定存储。DAG数据流能在运行时实现任务调度和故障恢复。基于数据流的框架并不明确支持工作集，所以需要将数据输出到磁盘，然后在每次查询时重新加载，这会带来较大的开销。针对以上问题，Spark实现了一种分布式内存抽象，称为弹性分布式数据集（Resilient distributed Dataset,RDD）。它支持基于工作集的应用，同时具有数据流的特点：**自动容错、位置感知性调度和可伸缩性**。RDD允许用户在执行多个查询时显式的将工作集换存在内存中，后续查询能够重用工作集，这提高了查询速度。

​	RDD提供了一种高度受限的共享内存模型，即RDD是只读记录分区的集合，只能通过在其他RDD执行确定的转换操作而创建。RDD通过Lineage来重建丢失的分区：一个RDD中包含了如何从其他RDD衍生所必须的相关信息，从而不需要检查点操作就可以重建丢失的数据分区。

#### 二、Spark架构综述

![屏幕快照 2018-10-11 下午10.34.04.png](https://i.loli.net/2018/10/12/5bbff58e516bd.png)

* Driver是用户编写的的数据处理逻辑，这个逻辑中包含用户创建的SparkContext
* SparkContext是用户逻辑与Spark集群的主要交互接口，它会和Cluster Manager交互，包括向它申请资源等。
* Cluster Manager负责集群的资源管理和调度。
* Worker Node是集群中可以执行计算的节点
* Executor是在一个Worker Node上为某应用启动的一个**进程**，该进程负责运行任务，并负责将数据存在内存或磁盘上。每个应用都有各自独立的Executor，计算最终在计算节点的Executer上执行。
* Task是被送到某个Executer上的计算单元

--------------

用户从最开始的提交到最终的执行计算，需要经历以下几个阶段：

1. 用户创建SparkContext时，新创建的SparkContext实例会连接到Cluster Manager。Cluster Manager根据用户提交时设置的CPU和内存等信息为本次提交分配资源，启动Executor。
2. Driver会将用户程序划分为不同的阶段，每个执行阶段由一组完全相同的Task组成，这些Task分别作用于不同的分区。在阶段划分完成和Task创建后，Driver会向Executor发送Task。
3. Executor接收到Task后，下载Task的运行时依赖，之后执行Task，并将Task的运行状态汇报给Driver
4. Driver根据收到的Task运行状态来处理不同的状态更新。有两种Task，Shuffle Map Task实现数据的重新洗牌，洗牌结果保存在Executor所在节点的文件系统中；Result Task负责生成结果数据
5. Driver不断的调用Task，将Task发送到Executor执行，知道所有Task都正确执行或者超过执行次数限制仍未成功。

