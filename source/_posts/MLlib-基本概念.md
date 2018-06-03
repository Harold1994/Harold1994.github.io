---
title: MLlib----基本概念
date: 2018-05-06 12:34:23
tags: [MLlib,  机器学习,  大数据]
---

**一、MLlib基本数据类型：**

**多种数据类型**

Local vector：本地向量集，主要向Spark提供一组可以进行操作的数据集合

Labeled point： 向量标签， 能够让用户分类不同的数据集合

Local matrix： 本地矩阵， 将数据集合以矩阵形式存储在本地计算机中

Distributed matrix： 分布式矩阵，将数据集合以矩阵形式存储在分布式计算机中
<!-- more-->

**本地向量集**

Local vector 主要分为两类，以数据集（4,5,2,9）为例介绍两种分类：

- 稀疏型数据集：(4,  Array(0,1,2,3), Array(4,5,2,9))
- 密集型数据集：(4,5,2,9)

```scala
object testVector {
  def main(args: Array[String]): Unit = {
    val vd : Vector = Vectors.dense(2,0,6)
    println(vd(2))
      //Vectors.sparse(数据大小, 数据下标（严格递增，不需要公差为1,可大于数据大小）, 数据)
    val vs: Vector = Vectors.sparse(4, Array(0,1,2,3), Array(9,5,2,7))
    println(vs(2))//这里面的参数必须小于总的数据大小
  }
}
output :
6.0
2.0
```

目前MLib只支持整数与浮点数计算，字符类型会转换成整数

**向量标签**

向量标签用于对MLlib中机器学习算法的不同值做标记，LabeledPoint是建立向量标签的静态类，Feature现实打印标记点所代表的数据内容，Label显示标记数

```scala
import org.apache.spark.mllib.linalg.{Vector, Vectors}
import org.apache.spark.mllib.regression.LabeledPoint

object testLablePoint {
  def main(args: Array[String]): Unit = {
    val vd: Vector = Vectors.dense(2,0,6)
    val pos = LabeledPoint(1,vd)
    println(pos.features)//打印标记点内容数据
    println(pos.label)
    val vs: Vector = Vectors.sparse(4, Array(0,1,2,3), Array(9,5,2,7))
    val neg = LabeledPoint(2, vs)
    println(neg.features)
    println(neg.label)
  }
}
output：
[2.0,0.0,6.0]
1.0
(4,[0,1,2,3],[9.0,5.0,2.0,7.0])
2.0
```

可以调用MLUtils.loadLibSVMFile对写到文件中的数据进行读取，数据格式为：

`label index1：value1 index2：value2 ...`

```scala
import org.apache.spark.mllib.util.MLUtils
import org.apache.spark._

object testLabeledPoint2 {
  def main(args: Array[String]): Unit = {
    val conf = new SparkConf()
      .setMaster("local")
      .setAppName("testLabeledPoint2")
    val sc = new SparkContext(conf)
    val mu = MLUtils.loadLibSVMFile(sc, "/media/harold/SpareDisk/SParkMLibDemo/src/labeleddata.txt")
    mu.foreach(println)
  }
}

input:
1 0:2 1:3 2:3
2 0:5 1:8 2:9
1 0:7 1:6 2:7
1 0:3 1:2 2:1
```

loadLibSVMFile方法将数据分解为一个稀疏向量 

**本地矩阵**

```scala
object testMatrix {
  def main(args: Array[String]): Unit = {
    val mx = Matrices.dense(2, 3, Array(1,2,3,4,5,6))//将数组转换为2行三列的矩阵
    println(mx)
  }
}
output：
1.0  3.0  5.0  
2.0  4.0  6.0  
```
​

**分布式矩阵**

分布式矩阵进行数据存储的情况一般数据量都非常大，其处理速度和效率与存储格式相关，MLlib提供四种分布式矩阵存储形式：行矩阵，带有行索引的行矩阵，坐标矩阵、块矩阵。

* 行矩阵

> 以行作为基本方向，列的作用比较小,相当于一个巨大的特征向量的集合。

```scala
import org.apache.spark.mllib.linalg.Vectors
import org.apache.spark.mllib.linalg.distributed.RowMatrix
import org.apache.spark.{SparkConf, SparkContext}

object testRowMatrix {
  def main(args: Array[String]): Unit = {
    val conf = new SparkConf()
      .setMaster("local")
      .setAppName("testRowMatrix")
    val sc = new SparkContext(conf)
    val rdd = sc.textFile("labeleddata.txt")
      .map(_.split(" ")
      .map(_.toDouble))
      .map(line => Vectors.dense(line))
    val rm = new RowMatrix(rdd)
    println(rm.numRows())
    println(rm.numCols())
  }
}
fileinput：
1 2 3
4 5 6
output：
2
3
```

  * 带有行索引的矩阵

  行矩阵是一个转换变化,不是最运行结果,内容无法直接显示,因此提供了带有行索引的矩阵

  ```scala
  import org.apache.spark.mllib.linalg.Vectors
  import org.apache.spark.mllib.linalg.distributed.{IndexedRow, IndexedRowMatrix}
  import org.apache.spark.{SparkConf, SparkContext}

  object testIndexedRowMatrix {
    def main(args: Array[String]): Unit = {
      val conf = new SparkConf()
        .setMaster("local")
        .setAppName("testIndexedRowMatrix")
      val sc = new SparkContext(conf)
      val rdd = sc.textFile("labeleddata.txt")
        .map(_.split(" ")
          .map(_.toDouble))
        .map(line => Vectors.dense(line))
        .map((vd) => new IndexedRow(vd.size,vd))
      val irm = new IndexedRowMatrix(rdd)
      println(irm.getClass)
      irm.rows.foreach(println)
    }
  }
  input:
  1 2 3
  4 5 6
  output:
  class org.apache.spark.mllib.linalg.distributed.IndexedRowMatrix
  IndexedRow(3,[1.0,2.0,3.0])
  IndexedRow(3,[4.0,5.0,6.0])
  ```

  * 坐标矩阵

    一种带有坐标标记的矩阵,每一个具体数据都有一组坐标进行标示(x: Long,  y:  Long, value: Double).x,y分别是行和列,一般用于数据比较多且较为分散的情形

    ```scala
    import org.apache.spark.mllib.linalg.distributed.{CoordinateMatrix, MatrixEntry}
    import org.apache.spark.{SparkConf, SparkContext}

    object testCoordinateRowMatrix {
      def main(args: Array[String]): Unit = {
        val conf = new SparkConf()
          .setMaster("local")
          .setAppName("testCoordinateRowMatrix")
        val sc = new SparkContext(conf)
        val rdd = sc.textFile("labeleddata.txt")
          .map(_.split(" ")
            .map(_.toDouble))
          .map(vue => (vue(0).toLong, vue(1).toLong, vue(2)))
          .map(vue2 => new MatrixEntry(vue2 _1, vue2 _2, vue2 _3))
        val crm = new CoordinateMatrix(rdd)
        crm.entries.foreach(println)
      }
    }
    output:
    MatrixEntry(1,2,3.0)
    MatrixEntry(4,5,6.0)
    ```

    三个矩阵级别依次增加,高级可向低级转换.



**二 MLlib数理统计基本概念**

在MLlib中,统计量计算主要用Statistic类库,主要包括:

* colStats:  以列为基础计算统计量的基本数据
* chiSqTest: 对数据集内数据计算皮尔逊距离
* corr: 计算两个数据集的相关系数

```scala
import org.apache.spark.mllib.linalg.Vectors
import org.apache.spark.mllib.stat.Statistics
import org.apache.spark.{SparkConf, SparkContext}

object testSummary {
  def main(args: Array[String]): Unit = {
    val conf = new SparkConf()
      .setMaster("local")
      .setAppName("testIndexedRowMatrix")
    val sc = new SparkContext(conf)
    val rdd = sc.textFile("a.txt")
      .map(_.split(" ")
        .map(_.toDouble))
      .map(line => Vectors.dense(line))
    val summary = Statistics.colStats(rdd)
    println(summary.max)
    println(summary.min)
    println(summary.count)//行内数据个数
    println(summary.mean)//均值
    println(summary.numNonzeros)//非零数字个数
    println(summary.variance)//标准差
    println(summary.normL1)//欧式距离,表达数据集内数据长度
    println(summary.normL2)//曼哈顿距离,表达两点在标准坐标系上的绝对轴距总和
  }
}
input:
0
1
2
3
45
6
2
1
3
56
32
65
output:
[65.0]
[0.0]
12
[18.0]
[11.0]
[598.7272727272727]
[216.0]
[102.34256201600583]
```

* 两组数据相关系数计算

  相关系数用来反映变量之间相关关系密切程度,MLlib中默认相关系数求法是皮尔逊相关系数法.

  两个变量之间的皮尔逊相关系数定义为两个变量之间的[协方差](https://baike.baidu.com/item/%E5%8D%8F%E6%96%B9%E5%B7%AE)和[标准差](https://baike.baidu.com/item/%E6%A0%87%E5%87%86%E5%B7%AE)的商：

  ![img](https://gss3.bdstatic.com/-Po3dSag_xI4khGkpoWK1HF6hhy/baike/s%3D289/sign=90b7ce2ea064034f0bcdc50e96c27980/060828381f30e92463d59cc247086e061c95f7d4.jpg)

​       可以看作是两组数据的向量夹角的余弦,描述两组数据的分开程度.

```scala
import org.apache.spark.mllib.stat.Statistics
import org.apache.spark.{SparkConf, SparkContext}

object testCorrect {
  def main(args: Array[String]): Unit = {
    val conf = new SparkConf()
      .setMaster("local")
      .setAppName("testCorrect")
    val sc = new SparkContext(conf)
    val rddX = sc.textFile("x.txt")
      .flatMap(_.split(" ")
        .map(_.toDouble))
    val rddY = sc.textFile("y.txt")
      .flatMap(_.split(" ")
        .map(_.toDouble))
    val correlation: Double = Statistics.corr(rddX,rddY)
    println(correlation)
  }
}
input://两个文件分别输入
xtxt:1 2 3 4 5
ytxt:2 4 6 8 10
outout:
0.9999999999999998
```

使用val correlation: Double = Statistics.corr(rddX,rddY,'spearman'),可以计算斯皮尔曼相关系数

* 分层抽样

分层抽样:一种数据提取算法,先将总体的单位按照特征分为若干级次总体,然后再从每一曾进行单纯随机抽样,组成一个样本.

eg:数据内容如下:

> aa
>
> bb
>
> aaa
>
> bbb
>
> ccc

将每个字符串中含有三个字符的标记为1,两个字符的标记为2,再根据其数目进行分组.

```scala
import org.apache.spark.{SparkConf, SparkContext}

object testStratifiedSampling2 {
  def main(args: Array[String]): Unit = {
    val conf = new SparkConf()
      .setMaster("local")
      .setAppName("testStratifiedSampling2")
    val sc = new SparkContext(conf)
    val data = sc.textFile("a.txt").map(row => {
      if (row.length == 3)
        (row, 1)
      else
        (row, 2)
    }
    ).map(each => (each _2, each _1))
    val fractions : Map[Int, Double] = (List((1,0.3),(2,0.7))).toMap//设定抽样格式,fractions表示在层1抽0.2，在层2中抽0.8
    //withReplacement false表示不重复抽样
    val approxSample = data.sampleByKey(withReplacement = false, fractions, 0)
    approxSample.foreach(println)
  }
}
```

* 假设检验

  MLlib规定常使用的数据集一般为向量和矩阵.

  ```scala
  import org.apache.spark.mllib.linalg.{Matrices, Vectors}
  import org.apache.spark.mllib.stat.Statistics

  object testChiSq {
    def main(args: Array[String]): Unit = {
      val vd = Vectors.dense(1,2,3,4,5,6)
      val vdResult = Statistics.chiSqTest(vd)
      println(vdResult)
      println("------------------")
      val mtx = Matrices.dense(3,2, Array(1,3,5,2,4,6))
      val mtxResult = Statistics.chiSqTest(mtx)
      println(mtxResult)
    }
  }
  output:
  Chi squared test summary:
  method: pearson//卡方检验使用方法
  degrees of freedom = 5 //自由度
  statistic = 5.000000000000001 //统计量
  pValue = 0.4158801869955079 //p值
  No presumption against null hypothesis: observed follows the same distribution as expected..
  ------------------
  Chi squared test summary:
  method: pearson
  degrees of freedom = 2 
  statistic = 0.14141414141414144 
  pValue = 0.931734784568187 
  No presumption against null hypothesis: the occurrence of the outcomes is statistically independent..
  ```
