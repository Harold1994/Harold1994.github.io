---
layout: posts
title: 数据算法——Spark的二次排序解决方案
date: 2018-06-07 15:41:50
tags: [分布式算法, 大数据, 机器学习, Spark]
---

在Saprk中解决二次排序问题，又以下两种解决方案：

* 方案一：

  将一个给定的键的所有值读取并缓存到一个List数组，对数组中得值完成归约器排序，如果每个归约器键的值集很小，则本方案适用

* 方案二：

  使用Spark框架对归约器值排序，这种方法“会为自然键增加部分或者整个值来创建一个组合键以实现排序目标”，本方法可伸缩，不受内存限制。
<!-- more-->
**时间序列作为输入**：

输入格式：

```
<key><,><time><,><value>
```

示例：

```
p,4,40
p,6,20
x,2,9
y,2,5
x,1,3
y,1,7
y,3,1
x,3,6
z,1,4
z,2,8
z,3,7
z,4,0
p,1,10
p,3,60
```

**期望输出：**

```
(z,{1=4, 2=8, 3=7, 4=0})
(p,{1=10, 3=60, 4=40, 6=20})
(x,{1=3, 2=9, 3=6})
(y,{1=7, 2=5, 3=1})
```

#### 一、方案一：内存中实现二次排序

算法：

>1.导入所需Java/Spark类
>
>2.将输入数据作为参数传入并验证
>
>3.创建sparkcontext对象，连接到Spark master,用来创建新的RDD
>
>4.使用sc对象为输入文件创建一个RDD
>
>5.从一个RDD<String>创建键值对，键是name，值是（time，value）对，得到PairRDD<String,Tuple2<String, String>>
>
>6.验证第五步，打印PairRDD所有值
>
>7.按键分组，使用GroupByKey()方法， 得到PairRDD<String, Iterable<Tuple2<String, String>>>
>
>* 注意：Iterable<Tuple2<String, String>>并不是有序的，一般处于性能考虑，更优先使用reduceByKey(),而不是GroupByKey(),不过此处只能用GroupByKey()，因为reduceByKey()不允许对给定键的值原地排序。
>
>8.验证第七步，打印PairRDD<String, Iterable<Tuple2<String, String>>>中所有值
>
>9.对reducer排序来得到最终输出
>
>10.打印所有值

```scala
object SecondarySort_InMemory {
  def main(args: Array[String]): Unit = {
    if (args.length != 2) {
      println("Usage <input-path> <output-path>")
      sys.exit(1)
    }

    val inpath = args(0)
    val outpath = args(1)
    //    val inpath = "/Users/harold-mac/Documents/data-algorithms/input"
    //    val outpath = "./out"
    val config = new SparkConf()
      .setAppName("SecondarySort_InMemory")
      .setMaster("local")
    val sc = new SparkContext(config)
    val input = sc.textFile(inpath)
    val tmp = input.map(line => {
      val x = line.split(",")
      (x(0), (x(1).toInt, x(2).toInt))
    })
    val output = tmp.groupByKey().mapValues(x => x.toList.sortWith((x, y) => x._1 > y._1))
    //或者
    //    val output = tmp.groupByKey().map {
    //      case (name, iter) => iter.toList.sortWith((x, y) => x._1 > y._1)
    //    }
    output.saveAsTextFile(outpath)
  }
}
```

#### 二、方案二：使用Spark框架实现二次排序

按照(name, time)排序，写一个分区器。

```scala
object SecondarySort {
  def main(args: Array[String]): Unit = {
    if (args.length != 3) {
      println("Usage <number-of-partitions> <input-path> <output-path>")
      sys.exit(1)
    }

    val partitions = args(0).toInt
    val inputPath = args(1)
    val outputPath = args(2)

    val config = new SparkConf()
      .setMaster("local")
      .setAppName("SecondarySort")

    val sc = new SparkContext(config)
    val input = sc.textFile(inputPath)
    val valueToKey = input.map(x => {
      val line = x.split(",")
      ((line(0) + "-" + line(1) , line(2).toInt), line(2).toInt)
    }
    )
    //隐式变换，按照（name，time）方式排序
    implicit def tupleOrderingDesc = new Ordering[Tuple2[String, Int]] {
      override def compare(x: Tuple2[String, Int], y: Tuple2[String, Int]): Int = {
        if (y._1.compareTo(x._1) == 0)
          y._2.compareTo(x._2)
        else y._1.compareTo(x._1)
      }
    }

    val sorted = valueToKey.repartitionAndSortWithinPartitions(new CustomPartitioner(partitions))
    val result = sorted.map {
      case (k,v) => (k._1, v)
    }
    result.saveAsTextFile(outputPath)
    sc.stop()
  }
}
```

```scala
//分区器
class CustomPartitioner(partitons :Int) extends Partitioner{
  require(partitons >0, s"Number of partitons ($partitons) cannot be negative.")
  override def numPartitions: Int = partitons

  override def getPartition(key: Any): Int = key match {
    case (k:String, v:Int) => math.abs(k.hashCode % numPartitions)
    case null => 0
    case _ => math.abs(key.hashCode() % numPartitions)
  }

  override def equals(obj: scala.Any): Boolean = obj match {
    case h:CustomPartitioner => h.numPartitions == numPartitions
    case _ => false
  }

  override def hashCode(): Int = numPartitions
}
```
