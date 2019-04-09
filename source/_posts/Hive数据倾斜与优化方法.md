---
title: Hive数据倾斜和优化方法
date: 2019-03-27 21:45:40
tags: [大数据, Hive]
---
最近面试总被问到Hive调优的问题，在这里专门总结一下：

#### 一、一般优化方式

* Map-side JOIN

  如果所有表中只有一张表是小表，可以在最大的表通过mapper的时候将小表放如内存中，Hive可以在map端执行连接过程，这是因为Hive可以和内存中的小表逐一匹配，从而省略掉常规连接操作所需要的reduce过程。

  > 通过设置set hive.auto.convert.join = true,Hive会在必要的时候启动这个优化

<!-- more--> 

* 本地模式

  如果Hive的输入数据量非常小，这种情况下，为触发查询任务的时间消耗可能会比实际job执行的时间还要长，对于大多数这种情况，可以通过本地模式在单台机器上处理所有任务

  > 通过设置hive.exec.mode.local.auto = true，Hive会在必要的时候启动这个优化

* 并行执行

Hive会将一个查询转化为一个或多个阶段，这样的阶段可能是MR阶段、抽样阶段、合并阶段、limit阶段等，默认情况下，Hive一次只会执行一个阶段，不过如果这些阶段并非完全依赖的，就可以并行执行，从而降低执行时间

> 通过设置hive.exec.parallel = true，Hive会在必要的时候启动这个优化

* 严格模式

  hive提供了一个严格模式，阻止用户执行一些会产生意想不到结果的查询。

  * 对于分区表，除非where语句中含有分区字段过滤条件来限制数据范围，否则不允许执行
  * 对于使用了Order By的查询，要求必须使用LIMIT语句，因为Order B为了执行排序过程会将所有结果数据分发到同一个reducer中处理。
  * 限制笛卡尔积的查询

  > 通过设置hive.mapred.mode = strict，Hive会启动这个优化

* 调整mapper和reducer的个数

  Hive通过将查询划分成多个MapReduce任务达到并行的目的，每个任务都可能具有多个mapper和reducer任务，其中至少有一些可以并行执行。

  Hive按照输入数据量大小来确定reducer的个数，Hive默认的reducer个数为3，可以通过设置mapred.reduce.tasks的值为不同的值来确定是使用较多还是较少的reducer来缩短执行时间。因为一个Hadoop集群可以提供的map和reduce资源个数是固定的，某个大job就可能消耗完所有插槽，从而导致其他job无法执行，所以属性hive.exec.reducers.max控制任务最大的reducer的数量。

  > 设置hive.exec.reducers.bytes.per.reducer指明每个reduce任务处理的数据量，默认为1G

* 推测执行

  这个功能的目的是通过加快获取单个task的结果以及进行侦测将执行慢的TaskTracker加入到黑名单的方式来提高整体的执行效率。

  > 通过设置hive.mapred.tasks.speculative.execution = true，Hive会启动这个优化
  >
  > mapreduce.map.speculative=true
  > mapreduce.reduce.speculative=true

* JVM重用

  Hadoop默认配置是使用派生JVM来执行map和reduce任务，此时JVM的启动可能会造成相当大的开销， 尤其是执行的job包含很多task任务的情况，JVM重用可以使得JVM实例在同一个job中重新使用N次。

  > 设置mapreduce.job.jvm.numtasks=$number来设置重用次数

  JVM重用的缺点是如果某个job中有某几个reduce task执行的时间比其他的都唱，那么保留的插槽会一直空闲着却无法被其他job使用，直到所有task都结束了才会释放。

#### 二、解决数据倾斜问题

* 数据倾斜的原因

   当数据量比较大，并且key分布不均匀，大量的key都shuffle到一个reduce上了，就出现了数据的倾斜。Hive倾斜的原因很大部分是由于sql中的join语句与group by语句。

  原因：对于普通的join操作，会在map端根据key的hash值，shuffle到某一个reduce上去，在reduce端做join连接操作，内存中缓存join左边的表，遍历右边的表，依次做join操作。所以在做join操作时候，将数据量多的表放在join的右边。


* 数据倾斜的现象

  map/reduce程序执行时，reduce节点大部分执行完毕，但是有一个或者几个reduce节点运行很慢，导致整个程序的处理时间很长，这是因为某一个key的条数比其他key多很多（有时是百倍或者千倍之多），这条key所在的reduce节点所处理的数据量比其他节点就大很多，从而导致某几个节点迟迟运行不完，此称之为数据倾斜。

   hive在跑数据时经常会出现数据倾斜的情况，使的作业经常reduce完成在99%后一直卡住，最后的１%花了几个小时都没跑完，这种情况就很可能是数据倾斜的原因。


* 数据倾斜的优化

  1. 如果是join 过程中出现倾斜应将hive.optimize.skewjoin.compiletime=true;

     如果大表和大表进行join操作，则可采用skewjoin

     skewjoin原理

     1. 对于skewjoin.key，在执行job时，将它们存入临时的HDFS目录。其它数据正常执行
     2. 对倾斜数据开启map join操作，对非倾斜值采取普通join操作
     3. 将倾斜数据集和非倾斜数据及进行合并操作

     如果建表语句元数据中指定了skew key，则使用set hive.optimize.skewjoin.compiletime=true开启skew join。

     > ```sql
     > set hive.optimize.skewjoin=true;
     > set hive.skewjoin.key=100000;
     > ```
     >
     > 以上参数表示当记录条数超过100000时采用skewjoin操作

  2. 不影响结果可以考虑过滤空值

  3. 在进行两个表join的过程中，由于hive都是从左向右执行，要注意讲小表在前，大表在后（小表会先进行缓存）。

  4. 如果是group by过程出现倾斜应将hive.groupby.skewindata设置true。

     参数会把sql翻译成两个MR，第一个MR的reduce_key是gender+id。因为id是一个随机散列的值，因此这个MR的reduce计算是很均匀的，reduce完成局部聚合的工作

     第二个MR完成最终的聚合，统计男女的distinct id值

  5. hive.map.aggr=true参数控制在group by的时候是否map局部聚合，这个参数默认是打开的