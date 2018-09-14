---
title: MLlib-聚类
date: 2018-06-30 14:33:40
tags: [机器学习, Spark, MLlib]
---

**1.k-means**

K-means是一个常用的聚类算法来将数据点按预定的簇数进行聚集。K-means算法的基本思想是：以空间中k个点为中心进行聚类，对最靠近他们的对象归类。通过迭代的方法，逐次更新各聚类中心的值，直至得到最好的聚类结果。

假设要把样本集分为c个类别，算法描述如下：

<!-- more--> 

（1）适当选择c个类的初始中心；

（2）在第k次迭代中，对任意一个样本，求其到c个中心的距离，将该样本归到距离最短的中心所在的类；

（3）利用均值等方法更新该类的中心值；

（4）对于所有的c个聚类中心，如果利用（2）（3）的迭代法更新后，值保持不变，则迭代结束，否则继续迭代。

MLlib工具包含并行的K-means++算法，称为kmeans||。Kmeans是一个Estimator，它在基础模型之上产生一个KMeansModel。

**输入列** 

| 参数名称    | 类型(s) | 默认的     | 描述           |
| ----------- | ------- | ---------- | -------------- |
| featuresCol | Vector  | "features" | Feature vector |

**输出列** 

| 参数名称      | 类型(s) | 默认的       | 描述                     |
| ------------- | ------- | ------------ | ------------------------ |
| predictionCol | Int     | "prediction" | Predicted cluster center |

```scala
object KMeansExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("KMeansExample")
      .master("local")
      .getOrCreate()
    val dataset = spark.read.format("libsvm").load("data/mllib/sample_kmeans_data.txt")
    val kmeans = new KMeans().setK(2).setSeed(1L)
    val model = kmeans.fit(dataset)
    // 评估平方误差的总和。
    val WSSSE = model.computeCost(dataset)
    println(s"Within Set Sum of Squared Errors = ${WSSSE}")

    // 显示结果
    println("Cluster Centers: ")
    model.clusterCenters.foreach(println)
  }
}
```

**2. 文档主题生成模型LDA**

LDA（Latent Dirichlet Allocation）是一种文档主题生成模型，也称为一个三层贝叶斯概率模型，包含词、主题和文档三层结构。所谓生成模型，就是说，我们认为一篇文章的每个词都是通过“以一定概率选择了某个主题，并从这个主题中以一定概率选择某个词语”这样一个过程得到。文档到主题服从多项式分布，主题到词服从多项式分布。

LDA是一种非监督机器学习技术，可以用来识别大规模文档集（document collection）或语料库（corpus）中潜藏的主题信息。它采用了词袋（bag of words）的方法，这种方法将每一篇文档视为一个词频向量，从而将文本信息转化为了易于建模的数字信息。但是词袋方法没有考虑词与词之间的顺序，这简化了问题的复杂性，同时也为模型的改进提供了契机。每一篇文档代表了一些主题所构成的一个概率分布，而每一个主题又代表了很多单词所构成的一个概率分布。

```scala
object LDAExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("LDAExample")
      .master("local")
      .getOrCreate()

    val dataset = spark.read.format("libsvm")
      .load("data/mllib/sample_lda_libsvm_data.txt")
// K: 需推断的主题（簇）的数目
    val lda = new LDA().setK(10).setMaxIter(10)
    val model = lda.fit(dataset)

    val ll = model.logLikelihood(dataset)
    val lp = model.logPerplexity(dataset)
    println(s"The lower bound on the log likelihood of the entire corpus: $ll")
    println(s"The upper bound bound on perplexity: $lp")
    // 描述topics
    val topics = model.describeTopics(3)
    println("The topics described by their top-weighted terms:")
    topics.show(false)
    // 显示结果
    val transformed = model.transform(dataset)
    transformed.show(false)
  }
}
```

**3. 高斯混合模型**

混合高斯模型描述数据点以一定的概率服从k种高斯子分布的一种混合分布。Spark.ml使用EM算法给出一组样本的极大似然模型。

**输出列** 

| 参数名称       | 类型(s) | 默认的        | 描述           |
| -------------- | ------- | ------------- | -------------- |
| predictionCol  | Int     | "prediction"  | 预测集群中心   |
| probabilityCol | Vector  | "probability" | 每个集群的概率 |

```scala
object GaussianMixtureExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("LDAExample")
      .master("local")
      .getOrCreate()

    val dataset = spark.read.format("libsvm")
      .load("data/mllib/sample_kmeans_data.txt")

    val gmm = new GaussianMixture()
      .setK(2)
    val model = gmm.fit(dataset)
    for (i <-0 until model.getK)
      println(s"Gaussian $i:\nweight=${model.weights(i)}\n" +
        s"mu=${model.gaussians(i).mean}\nsigma=\n${model.gaussians(i).cov}\n")
  }
}
```

​																		