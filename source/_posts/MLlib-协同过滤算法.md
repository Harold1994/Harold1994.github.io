---
title: MLlib----协同过滤算法
date: 2018-05-06 23:48:26
tags: [MLlib,机器学习, 协同过滤, ALS算法]
---

协同过滤算法是最常用的推荐算法,主要有两种形式:基于用户和基于物品的推荐算法.

ALS(alternate least square)是交替最小二乘法的简称,也是MLlib的基础推荐算法.

**一. 协同过滤**

协同过滤算法是一种基于群体用户或物品的典型推荐算法,主要有两种:

> - 通过考察具有相同爱好的用户对相同物品的评分标准进行计算
> - 考察具有相同特质的物品从而推荐给选择了某件物品的用户

<!-- more-->

不足:

> * 基于用户: 针对热点物品的处理不够准确,一些常用的物品其推荐结果往往排在首位,但是这样没有实际意义.其次,数据量大,计算费事

> * 基于物品: 存在推荐同类物品的问题

**二. 相似度度量**

1. 基于欧几里德距离的相似度计算

   欧式距离表示空间中两个点的真实距离,![img](https://gss2.bdstatic.com/-fo3dSag_xI4khGkpoWK1HF6hhy/baike/s%3D272/sign=824f524b36292df593c3ab128e305ce2/9e3df8dcd100baa1dbb0d0df4b10b912c8fc2e31.jpg),在相似度计算中,不同的物品或用户可将其定义成不同的坐标点,特定目标定位成坐标原点.因为欧式距离越大,相近度越小,因此一般以`1/(ρ+1)`作为相似度近似值

2. 基于余弦角度的相似度

   余弦相似度通过计算两个向量的夹角余弦值来评估他们的相似度

![img](https://gss0.bdstatic.com/-4o3dSag_xI4khGkpoWK1HF6hhy/baike/c0%3Dbaike80%2C5%2C5%2C80%2C26/sign=ff93f325064f78f0940692a118586130/e850352ac65c1038573da3b3b7119313b07e897b.jpg)

计算公式:   ![img](https://gss3.bdstatic.com/-Po3dSag_xI4khGkpoWK1HF6hhy/baike/s%3D187/sign=50b538a78244ebf869716037eef8d736/0df431adcbef760970e3983b2bdda3cc7dd99ead.jpg)      余弦值大小在[-1,1],值大小与夹角成正比

3. 欧式距离相似度与余弦相似度比较 

   欧式相似度以目标绝对距离作为衡量标准,余弦相似度以目标差异大小作为衡量标准.一般来说,欧氏相似度用来表现不同目标的绝对差异性,分析目标之间的相似度与差异情况.余弦相似度更多的从目标的方向趋势上区分,而随特定坐标数字不敏感.

4. 余弦相似度实战----使用余弦相似度计算不同用户之间的相似性

   步骤:

   a. 输入数据

   b.建立相似度算法公式

   c.计算不同用户之间的相似度

```scala
object CollaborativeFilteringSpark {
  //屏蔽不必要的日志显示在终端上
  Logger.getLogger("org.apache.spark").setLevel(Level.WARN)
  Logger.getLogger("org.apache.eclipse.jetty.server").setLevel(Level.OFF)

  val conf= new SparkConf().setMaster("local[1]").setAppName("CollaborativeFilteringSpark")
  val sc = new SparkContext(conf)
  val users = sc.parallelize(Array("aaa","bbb","ccc","ddd", "eee"))//设置用户名
  val films = sc.parallelize(Array("StarWar","Spider","Ghost","Beauty","Hero"))//设置电影名
  val source = Map[String,Map[String,Int]]()//用来存储user对每个电影的打分
  val filmsource = Map[String,Int]()
  def getSource() : Map[String,Map[String,Int]] = {//设置电影评分
    val user1FilmSource = Map("StarWar" -> 2,"Spider"->3,"Ghost"->1,"Beauty" -> 0,"Hero" -> 1)
    val user2FilmSource = Map("StarWar" -> 1,"Spider"->2,"Ghost"->2,"Beauty" -> 1,"Hero" -> 4)
    val user3FilmSource = Map("StarWar" -> 2,"Spider"->1,"Ghost"->0,"Beauty" -> 1,"Hero" -> 4)
    val user4FilmSource = Map("StarWar" -> 3,"Spider"->2,"Ghost"->0,"Beauty" -> 5,"Hero" -> 3)
    val user5FilmSource = Map("StarWar" -> 5,"Spider"->3,"Ghost"->1,"Beauty" -> 0,"Hero" -> 2)
    source += ("aaa" -> user1FilmSource)
    source += ("bbb" -> user2FilmSource)
    source += ("ccc" -> user3FilmSource)
    source += ("ddd" -> user4FilmSource)
    source += ("eee" -> user5FilmSource)
    source
  }
  //两两计算分值，采用余弦相似性
  def getCollaborateSource(user1: String, user2: String): Double = {
    //获得1，2两个用户的评分
    val user1FilmSource = source.get(user1).get.values.toVector
    val user2FilmSource = source.get(user2).get.values.toVector

    //对公式部分分子进行计算
    val member = user1FilmSource.zip(user2FilmSource).map(d => d._1 * d._2).reduce(_ + _).toDouble
    //求出分母第一个变量值
    val temp1 = math.sqrt(user1FilmSource.map(num => {
      math.pow(num, 2)
    }).reduce(_ + _))
    //求出分母第二个变量值
    val temp2 = math.sqrt(user2FilmSource.map(num => {
      math.pow(num, 2)
    }).reduce(_ + _))
    //求出分母
    val denominator = temp1 * temp2
    //进行计算
    member / denominator
  }

  def main(args: Array[String]): Unit = {
    getSource()
    val name = "aaa"
    users.foreach(user => {
      println(name + " 相对于 " + user + "的相似性分数为:" + getCollaborateSource(name, user))
    })
  }
}
```

#### 三. MLlib中的交替最小二乘法(ALS算法)

交替最小二乘法是统计分析中最常用的逼近计算的一种算法,其交替计算结果使得最终结果尽可能的逼近真实结果.

**1.最小二乘法(LS算法)**

对于一元线性回归模型, 假设从总体中获取了n组观察值$(X1,Y1)(X2,Y2),(Xn,Yn)$.对于平面中的这n个点，可以使用无数条曲线来拟合。要求样本回归函数尽可能好地拟合这组值。综合起来看，这条直线处于样本数据的中心位置最合理。 选择最佳拟合曲线的标准可以确定为：使总的拟合误差（即总残差）达到最小。有以下三个标准可以选择：

​        （1）用“残差和最小”确定直线位置是一个途径。但很快发现计算“残差和”存在相互抵消的问题。
        （2）用“残差绝对值和最小”确定直线位置也是一个途径。但绝对值的计算比较麻烦。
        （3）最小二乘法的原则是以“残差平方和最小”确定直线位置。用最小二乘法除了计算比较方便外，得到的估计量还具有优良特性。这种方法对异常值非常敏感。

用数学公式描述就是： 

​						$Q=min\sum_i^n(y_{ie}-y_i)^2$ 　　　　　　　　　　　　　　　　　　　　

其中，$y_ie$表示根据$y=ax+b$估算出来的值，$y_i$是观察得到的真实值。

**2.MLlib中的交替最小二乘法(ALS)**

2.1　ALS算法

从协同过滤的分类来说，ALS算法属于User-Item CF，也叫做混合CF。它同时考虑了User和Item两个方面。

用户和商品的关系，可以抽象为如下的三元组：`<User,Item,Rating>`。其中，Rating是用户对商品的评分，表征用户对该商品的喜好程度。

ALS算法是基于模型的推荐算法。起基本思想是对稀疏矩阵进行模型分解，评估出缺失项的值，以此来得到一个基本的训练模型。然后依照此模型可以针对新的用户和物品数据进行评估。ALS是采用交替的最小二乘法来算出缺失项的。交替的最小二乘法是在最小二乘法的基础上发展而来的。

假设我们有一批用户数据，其中包含m个User和n个Item，则我们定义Rating矩阵，其中的元素表示第u个User对第i个Item的评分。

在实际使用中，由于n和m的数量都十分巨大，因此R矩阵的规模很容易就会突破1亿项。这时候，传统的矩阵分解方法对于这么大的数据量已经是很难处理了。

另一方面，一个用户也不可能给所有商品评分，因此，Rating矩阵注定是个稀疏矩阵。矩阵中所缺失的评分，又叫做missing item。

![](http://p5s7d12ls.bkt.clouddn.com/18-6-18/62022843.jpg)

针对这样的特点，我们可以假设用户和商品之间存在若干关联维度（比如用户年龄、性别、受教育程度和商品的外观、价格等），我们只需要将R矩阵投射到这些维度上即可。

如下图，对于一个R（观众对电影的一个评价矩阵）可以分解为U（观众的特征矩阵）和V（电影的特征矩阵）

![img](https://img-blog.csdn.net/20160523103701786)

现在假如观众有5个人，电影有5部，那么R就是一个5\*5的矩阵。假设评分如下：**

![img](https://img-blog.csdn.net/20160523110941941)

假设d是三个属性（性格，文化程度，兴趣爱好）那么U的矩阵如下：

![img](https://img-blog.csdn.net/20160523112421700)

V的矩阵如下：

![img](https://img-blog.csdn.net/20160523114759278)

R约等于U*V，为什么是约等于呢？因为对于一个U矩阵来说，我们并不可能说（性格，文化程度，兴趣爱好）这三个属性就代表着一个人对一部电影评价全部的属性，比如还有地域等因素。但是我们可以用“主成分分析的思想”来近似（我没有从纯数学角度来谈，是为了大家更好理解）。这也是ALS和核心：一个评分矩阵可以用两个小矩阵来近似（ALS是NNMF问题下在丢失数据情况下的一个重要手段）。

那么如何评价这两个矩阵的好坏？

理想的情况下：
$$
r_{i,j} = <u_i,v_i>
$$
但在实际中，我们求$r_{i,j}$使用数值方法来求，那么计算得到的$r_{i,j}$就会存在误差，采用均方根误差RMSE来评价$r_{i,j}$的好坏：
$$
RMSE=\sqrt{\frac1n\sum_{u,v}|(p_{u,v} - r_{u,v})^2|}
$$
$p_{u,v}$是u对v评分的预测值，$r_{u,v}$是u对v评分的观察值。
$$
p_{i,j}=<u_i,v_j>
$$
那么就是转化的要求：
$$
(u_i,v_j) = min_{u,v}\sum_{(u,v)\in \kappa}(p_{u,v} - r_{u,v})
$$
现在一共有$(n_u + n_v)*d$个参数需要求解，而且碰到以下问题：

* K矩阵是稀疏矩阵（K就是R在U对V没有全部评价的矩阵）
* K的大小远小于R的密集对应的大小$n_u*n_v$

采用拟合数据的形式来进行解决数据是稀疏的问题，公式如下：
$$
(u_i,v_j) = min_{u,v}\sum_{(i,j)\in \kappa}(p_{i,j} - r_{i,j})^2 + \lambda(||u_i||^2 + ||v_j||^2)
$$
后面的$ \lambda(||u_i||^2 + ||v_j||^2)$是为了解决过拟合问题而增加的。

对于ALS来求解這样這个问题的思想是：先固定$u_i$或者$v_j$,然后就转化为最小二乘法的问题了。他這样做就可以把一个非凸函数的问题转为二次函数的问题了。下面就求解步骤[1]：
步骤1：初始化矩阵V（可以取平均值也可以随机取值）

步骤2：固定V，然后通过最小化误差函数(RMSE)解决求解U

步骤3：固定步骤2中的U，然后通过最小化误差函数(RMSE)解决求解V

步骤4：反复步骤2，3；直到U和V收敛。

梳理：为什么是交替，从处理步骤来看就是确定V，来优化U，再来优化V，再来优化U,直到收敛

因为采用梯度下降和最小二乘都可以解决這个问题，在此不写代码来讲如何决定参数，可以看前面的最小二乘或者梯度下降算法。

2.2 MLlib中的交替最小二乘法

MLlib中的ALS算法有固定的数据格式：

```scala
case class Rating (user: Int, product: Int, rating: Double)
```

其中Rating是固定的ALS输入格式,要求是一个元组类型的数据，其中数值类型分别是[Int,Int,Double],因此在数据集建立时，用户名和物品分别用用数值代替。

ALS.train方法源码如下，参数类型见代码

```scala
/**
   * @param ratings    RDD of [[Rating]] objects with userID, productID, and rating
   * @param rank       number of features to use (also referred to as the number of latent factors)
   * @param iterations number of iterations of ALS
   * @param lambda     regularization parameter
   * @param blocks     level of parallelism to split computation into
   * @param seed       random seed for initial matrix factorization model
   */
@Since("0.9.1")
def train(
    ratings: RDD[Rating],
    rank: Int,
    iterations: Int,
    lambda: Double,
    blocks: Int,
    seed: Long
): MatrixFactorizationModel = {
    new ALS(blocks, blocks, rank, iterations, lambda, false, 1.0, seed).run(ratings)
}
```

```scala
object CollaborativeFilter {
  def main(args: Array[String]): Unit = {
    val conf = new SparkConf().setAppName("CollaborativeFilter").setMaster("local")
    val sc = new SparkContext(conf)
    val data = sc.textFile("u1.txt")
    val rating = data.map(_.split(" ") match {
      case Array(user, item, rate) =>
        Rating(user.toInt, item.toInt, rate.toDouble)
    })
    val rank = 2//设置隐藏因子
    val numIteration = 2 //设置迭代次数
    val model = ALS.train(rating,rank,numIteration,0.01)
    val rs = model.recommendProducts(2,1)//为用户２推荐一个商品
    rs.foreach(println)
  }
}
```

ALS算法的缺点在于：

1.它是一个离线算法。

2.无法准确评估新加入的用户或商品。这个问题也被称为Cold Start问题。
