---
title: 数据算法——Top 10列表
date: 2018-06-08 18:06:39
tags: [分布式算法, 大数据, 机器学习, Hadoop, Spark]
---

top10列表问题是一种过滤模式的问题，即需要过滤数据，找出top N列表,本篇博客将分别利用MR和Spark实现top N设计模式。

#### 一、Top N设计模式的形式化描述

令N是一个整数，而且N>0。令L是一个$List<Tuple2<T,Integer>>$,其中T可以是任意类型；$L.size() = S; S > N$,L的元素为：

​								$\lbrace (K_i,V_i),1\leq i\leq S\rbrace$

其中$K_i$类型为T，$V_i$为Integer类型（为$K_i$的频度）。令sort(L)返回以排序的L值，这里使用频度作为键，如下所示：

  						$\lbrace (A_j,B_j),1\leq j\leq S,B_1\geq B_2\geq …\geq B_S \rbrace$

其中$(A_j,B_j) \in L $,则Top N的定义为：

​				$topN(L) =\lbrace (A_j,B_j),1\leq j\leq N,B_1\geq B_2\geq …\geq B_N \geq …\geq B_s \rbrace$			
<!-- more-->
为实现Top N，需要一个散列表数据结构，从而可以得到键的全序，在Java中可以使用SortedMap<K,V>作为接口和TreeMap<K,V>.

```java
public SortedMap<Integer, T> topN(List<Tuple2<T, Integer>> L, int N) {
    if ((L == null) || (L.isEmpty())) {
        return null;
    }
    SortedMap<Integer, T> topN = new TreeMap<Integer, T>();
    for (Tuple2<T, Integer> element : L) {
        topN.put(element._2, element._1);
        if (topN.size() > N) {
            topN.remove(topN.firstKey());
        }
    }
    return topN;
}
```

#### 二、MapReduce/Hadoop实现：唯一键

首先将输入分区为小块，每个小块发送到一个mapper，每个mapper产生一个top N列表，然后将列表发送到reduce如，发出mapper输出时，使用同一个reducer键，这样所有mapper输出都将由一个reducer处理。

![](http://p5s7d12ls.bkt.clouddn.com/18-6-11/20636935.jpg)

**Mapper:**

```java
/**                                                                                                                   
 * @author lihe                                                                                                       
 * @Title: TopNMapper                                                                                                 
 * @Description: 唯一键Mapper                                                                                            
 * @date 2018/6/11下午2:19                                                                                              
 */                                                                                                                   
public class TopNMapper extends Mapper<Text, IntWritable, NullWritable, Text> {                                       
    private int N = 10;                                                                                               
    private SortedMap<Integer, String> top = new TreeMap<Integer, String>();                                          

    @Override                                                                                                         
    protected void map(Text key, IntWritable value, Context context) throws IOException, InterruptedException {       
        String keyAsString = key.toString();                                                                          
        int frequency = value.get();                                                                                  
        String compositValue = keyAsString + "," + frequency;                                                         
        top.put(frequency, compositValue);                                                                            
        if (top.size() > N) {                                                                                         
            top.remove(top.firstKey());                                                                               
        }                                                                                                             
    }                                                                                                                 
    //每个mapper执行一次,一开始从参数中获取N                                                                                         
    @Override                                                                                                         
    protected void setup(Context context) throws IOException, InterruptedException {                                  
        this.N = context.getConfiguration().getInt("N", 10);                                                          
    }                                                                                                                 

    @Override                                                                                                         
    protected void cleanup(Context context) throws IOException, InterruptedException {                                
        for (String str : top.values())                                                                               
            context.write(NullWritable.get(), new Text(str));                                                         
    }                                                                                                                 
}                                                                                                                                                                                                                                          
```

**Reducer:**

```java
/**
 * @author lihe
 * @Title: TopNReducer
 * @Description: 唯一键做reduc，所有数据都到单个reducer
 * @date 2018/6/11下午2:33
 */
public class TopNReducer extends Reducer<NullWritable, Text, IntWritable, Text> {
    private int N = 10;
    private SortedMap<Integer,String> top = new TreeMap<Integer, String>();

    @Override
    protected void reduce(NullWritable key, Iterable<Text> values, Context context) throws IOException, InterruptedException {
        for (Text value : values) {
            String valueAsString = value.toString().trim();
            String [] tokens = valueAsString.split(",")；
            String url = tokens[0];
            int frequency = Integer.parseInt(tokens[1]);
            top.put(frequency, url);
            if (top.size() > N) {
                top.remove(top.firstKey());
            }
        }
        List<Integer> keys = new ArrayList<>(top.keySet());
        for (int i=keys.size()-1; i>= 0; i--)
            context.write(new IntWritable(keys.get(i)), new Text(top.get(keys.get(i))));
    }

    @Override
    protected void setup(Context context) throws IOException, InterruptedException {
        this.N = context.getConfiguration().getInt("N", 10); // default is top 10
    }
}
```

#### 三、Spark实现：唯一键

在这个实现中，我们假定对于所有<K,V>对，K是唯一的，在本节不会使用Spark的排序函数，如top()或takeOrdered().

**步骤：**

* 导入必要的类
* 处理输入参数：确保有一个输入参数：HDFS输入文件
* 连接Spark master
* 从HDFS读取输入文件并创建RDD
* Top10类：从现有RDD<String>创建出PairRDD<Integer,String>
* 为各个输入分区创建本地top 10列表，mapPartitions
* 使用collect()或者reduce()创建最终top10列表

```scala
object TopN {
  def main(args: Array[String]): Unit = {
    if (args.size < 1) {
      println("Usage : TopN <input>")
      sys.exit(1)
    }

    val sparkConf = new SparkConf().setAppName("TopN")
    val sc = new SparkContext(sparkConf)
    //将N设为全局变量
    val N = sc.broadcast(10)
    val path = args(0)

    val input = sc.textFile(path)
    val pair = input.map(line => {
      var tokens = line.split(",")
      (tokens(2).toInt, tokens)
    })

    import Ordering.Implicits._
    val partitions = pair.mapPartitions(itr => {
      var sortedMap = SortedMap.empty[Int, Array[String]]
      itr.foreach { tuple => {
        sortedMap += tuple
        if (sortedMap.size > N.value) {
          sortedMap = sortedMap.takeRight(N.value)
        }
      }
      }
      sortedMap.takeRight(N.value).toIterator
    })

    val alltop10 = partitions.collect()
    val finaltop10 = SortedMap.empty[Int, Array[String]].++(alltop10)
    val resultUsingMapPartiton = finaltop10.takeRight(N.value)

    //打印输出
    resultUsingMapPartiton.foreach({
      case (k, v) => println(s"$k \t ${v.asInstanceOf[Array[String]].mkString(",")}")
    })

    val moreConciseApproach = pair.groupByKey().sortByKey(false).take(N.value)
    moreConciseApproach.foreach {
      case (k, v) => println(s"$k \t ${v.flatten.mkString(",")}")
    }
    sc.stop()
  }
}
```

#### 四、Spark实现：非唯一键

在实际的应用中可能会出现K不唯一的情况，比如统计一个网站最常被访问的是个URL，假设我们有三个Web服务器，只有7个URL，分别为A，B，C，D，E，F，对应的服务器生成的统计如下表：

| Web服务器1 | Web服务器3 | Web服务器3 |
| ---------- | ---------- | ---------- |
| （A，2）   | （A，1）   | （A，2）   |
| （B，2）   | （B，1）   | （B，4）   |
| （C，4）   | （C，5）   | （C，2）   |
| （F，3)    | （E，1）   | （D，3）   |
|            | （F，2)    | （E，2）   |
|            |            | (F，1)     |

如果先得到每个服务器的本地top N，在规约得到的数据并不正确，原因是所有服务器上的URL并不惟一。要得到正确的结果，必须为所有输入创建一组唯一的URL，然后再分区计算。

```scala
class TopNNonUnique {
  def main(args: Array[String]): Unit = {
    if (args.size < 1) {
      println("Usage: TopNNonUnique <input>")
      sys.exit(1)
    }

    val sparkConf = new SparkConf().setAppName("TopNNonUnique")
    val sc = new SparkContext(sparkConf)

    val N = sc.broadcast(2)
    val path = args(0)

    val input = sc.textFile(path)
    val kv = input.map(line => {
      val tokens = line.split(",")
      (tokens(0), tokens(1).toInt)
    })

    val uniqueKeys = kv.reduceByKey(_ + _)
    import Ordering.Implicits._
    val partitions = uniqueKeys.mapPartitions(itr => {
      var sortedMap = SortedMap.empty[Int, String]
      itr.foreach { tuple => {
        sortedMap += tuple.swap
        if (sortedMap.size > N.value) {
          sortedMap = sortedMap.takeRight(N.value)
        }
      }
      }
      sortedMap.takeRight(N.value).toIterator
    })

    val alltop10 = partitions.collect()
    val finaltop10 = SortedMap.empty[Int, String].++(alltop10)
    val resultUsingMapPartiton = finaltop10.takeRight(N.value)

    resultUsingMapPartiton.foreach {
      case (k, v) => println(s"$k \t ${v.mkString(",")}")
    }

    //更简 洁的一种方式
    val createCombiner = (v: Int) => v
    val mergeValue = (a: Int, b: Int) => (a + b)
    val moreConciseApproach = kv.combineByKey(createCombiner, mergeValue, mergeValue)
      .map(_.swap)
      .groupByKey()
      .sortByKey(false)
      .take(N.value)

    //Prints result (top 10) on the console
    moreConciseApproach.foreach {
      case (k, v) => println(s"$k \t ${v.mkString(",")}")
    }
    sc.stop()
  }
}
```

注意上面代码中使用combineByKey方法得到了一种更简洁的表达方式。combineByKey是Spark中一个比较核心的高级函数，其他一些高阶键值对函数底层都是用它实现的。诸如 groupByKey,reduceByKey等等。

- createCombiner: V => C ，这个函数把当前的值作为参数，此时我们可以对其做些附加操作(类型转换)并把它返回 (这一步类似于初始化操作)
- mergeValue: (C, V) => C，该函数把元素V合并到之前的元素C(createCombiner)上 (这个操作在每个分区内进行)
- mergeCombiners: (C, C) => C，该函数把2个元素C合并 (这个操作在不同分区间进行)
