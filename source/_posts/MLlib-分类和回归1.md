---
title: MLlib-分类回归
date: 2018-06-28 15:59:27
tags: [机器学习, Spark, MLlib]
---

#### 一、分类

**1.逻辑回归**

逻辑回归是预测分类反应的流行方法。 [广义线性模型](https://en.wikipedia.org/wiki/Generalized_linear_model)的一个特例是预测结果的可能性。 在spark.ml逻辑回归中可以使用二项式逻辑回归来预测二进制结果，也可以通过使用多项Logistic回归来预测多类结果。 使用系列参数在这两种算法之间进行选择，或者将其设置为未设置，Spark将推断出正确的变体。

<!-- more--> 

通过将家族参数设置为“多项式”，可以将多项Logistic回归用于二进制分类。它将产生两组系数和两个截距。

当在具有常量非零列的数据集上对LogisticRegressionModel进行拟合时，Spark MLlib为常数非零列输出零系数。此行为与R glmnet相同，但与LIBSVM不同。

* 二项式逻辑回归

  以下示例显示了如何用弹性网络正则化来训练二项分类的二项式和多项Logistic回归模型。 elasticNetParam对应于α，regParam对应于λ（正则化参数（泛化能力），**加正则化的前提是特征值要进行归一化**）。

  > 弹性网络是一种使用 L1， L2 范数作为先验正则项训练的线性回归模型。 这种组合允许学习到一个只有少量参数是非零稀疏的模型，就像 Lasso 一样，但是它仍然保持一些像 Ridge 的正则性质。我们可利用 l1_ratio 参数控制 L1 和 L2 的凸组合。
  >
  > 弹性网络在很多特征互相联系的情况下是非常有用的。Lasso 很可能只随机考虑这些特征中的一个，而弹性网络更倾向于选择两个。

  ```scala
  object LogisticRegressionWithElasticNetExample {
    def main(args: Array[String]): Unit = {
      val spark = SparkSession.builder()
        .appName("LogisticRegressionWithElasticNetExample")
        .master("local")
        .getOrCreate()
  
      val training = spark.read.format("libsvm").load("data/mllib/sample_libsvm_data.txt")
  
      val lr = new LogisticRegression()
        .setMaxIter(10)//最大迭代次数
        .setRegParam(0.3)//学习速率
        .setElasticNetParam(0.8)//结构化参数
  
      val lrModel = lr.fit(training)
      //打印训练出来的系数矩阵和偏置
      println(s"Coefficients: ${lrModel.coefficients} Intercept: ${lrModel.intercept}")
  
      val mlr = new LogisticRegression()
        .setMaxIter(10)
        .setRegParam(0.3)
        .setElasticNetParam(0.8)
        .setFamily("multinomial")
  
      val mlrModel = mlr.fit(training)
      // Print the coefficients and intercepts for logistic regression with multinomial family
      println(s"Multinomial coefficients: ${mlrModel.coefficientMatrix}")
      println(s"Multinomial intercepts: ${mlrModel.interceptVector}")
  
    }
  }
  ```

  逻辑回归的spark.ml实现也支持在训练集中提取模型的摘要。 请注意，在BinaryLogisticRegressionSummary中存储为DataFrame的预测和度量标注为@transient，因此仅在驱动程序上可用。

  [LogisticRegressionTrainingSummary](http://spark.apache.org/docs/2.1.0/api/scala/index.html#org.apache.spark.ml.classification.LogisticRegressionTrainingSummary)为[LogisticRegressionModel](http://spark.apache.org/docs/2.1.0/api/scala/index.html#org.apache.spark.ml.classification.LogisticRegressionModel)提供了一个摘要。 目前，只支持二进制分类，必须将摘要显式转换为[BinaryLogisticRegressionTrainingSummary](http://spark.apache.org/docs/2.1.0/api/scala/index.html#org.apache.spark.ml.classification.BinaryLogisticRegressionTrainingSummary)。 当支持多类分类时，这可能会发生变化。

  继续前面的例子：

  ```scala
   //从之前返回的模型实例中获取summary
      import spark.implicits._
  
      val trainingSummary = lrModel.binarySummary
      //获取每次迭代的目标
      val objectiveHistory = trainingSummary.objectiveHistory
      println("objectiveHistory:")//打印损失
      objectiveHistory.foreach(loss => println(loss))
      //获取有用的度量标准，以判断测试数据的性能。
      // 我们将该summary投射到BinaryLogisticRegressionSummary，因为该问题是二元分类问题。
  
      val roc = trainingSummary.roc
      roc.show()
      println(s"Area under ROC: ${trainingSummary.areaUnderROC}")
  
      //设置模型阈值来最大化F1
      val fMeasure = trainingSummary.fMeasureByThreshold
      val maxFMeasure = fMeasure.select(("F-Measure")).head().getDouble(0)
      val bestThreshold = fMeasure.where($"F-Measure" === maxFMeasure)
        .select("threshold").head().getDouble(0)
      lrModel.setThreshold(bestThreshold)
      spark.stop()
  ```

**2. 决策树分类器**

决策树是一种流行的分类和回归方法。以下示例以LibSVM格式加载数据集，将其拆分为训练和测试集，在第一个数据集上训练，然后对所保留的测试集进行评估。 我们使用两个transformer来准备数据; 这些帮助索引类别的标签和分类功能，添加元数据到决策树算法可以识别的DataFrame。

```scala
object DecisionTreeClassificationExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("DecisionTreeClassificationExample")
      .getOrCreate()

    val data = spark.read.format("libsvm").load("data/mllib/sample_libsvm_data.txt")
    //对label进行索引
    val labelIndexer = new StringIndexer()
      .setInputCol("label")
      .setOutputCol("indexedLabel")
      .fit(data)
    //自动确定哪些功能是分类的，并将原始值转换为类别索引
    val featureIndexer = new VectorIndexer()
      .setInputCol("features")
      .setOutputCol("indexedFeatures")
      .setMaxCategories(4)
      .fit(data)
    //将数据集分为训练集和测试集
    val Array(trainingData, testData) = data.randomSplit(Array(0.7, 0.3))

    val dt = new DecisionTreeClassifier()
      .setLabelCol("indexedLabel")
      .setFeaturesCol("indexedFeatures")
    //将预测出来的label还原为原来对应的label
    val loabelConvertor = new IndexToString()
      .setInputCol("prediction")
      .setOutputCol("predictedLabel")
      .setLabels(labelIndexer.labels)

    val pipeline = new Pipeline()
      .setStages(Array(labelIndexer, featureIndexer, dt, loabelConvertor))

    val model = pipeline.fit(trainingData)

    val predictions = model.transform(testData)

    predictions.select("predictedLabel", "label", "features").show(5)

    val evaluator = new MulticlassClassificationEvaluator()
      .setLabelCol("indexedLabel")
      .setPredictionCol("prediction")
      .setMetricName("accuracy")
    val accuracy = evaluator.evaluate(predictions)
    println("Test Error = " + (1.0 - accuracy))

    val treeModel = model.stages(2).asInstanceOf[DecisionTreeClassificationModel]
    println("Learned classification tree model:\n" + treeModel.toDebugString)
    spark.stop()
  }
}
```

**3. 随机森林分类**

```scala
object RandomForestClassifierExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("VectorIndexerExample")
      .master("local")
      .getOrCreate()

    val data = spark.read.format("libsvm").load("data/mllib/sample_libsvm_data.txt")

    val labelIndexer = new StringIndexer()
      .setInputCol("label")
      .setOutputCol("indexedLabel")
      .fit(data)

    val featureIndexer = new VectorIndexer()
      .setInputCol("features")
      .setOutputCol("indexedFeatures")
      .setMaxCategories(4)
      .fit(data)

    val Array(trainingData, testData) = data.randomSplit(Array(0.7, 0.3))

    val rf = new RandomForestClassifier()
      .setLabelCol("indexedLabel")
      .setFeaturesCol("indexedFeatures")
      .setNumTrees(10)

    val labelConverter = new IndexToString()
      .setInputCol("prediction")
      .setOutputCol("predictedLabel")
      .setLabels(labelIndexer.labels)

    val pipeline = new Pipeline()
      .setStages(Array(labelIndexer, featureIndexer, rf, labelConverter))

    val model = pipeline.fit(trainingData)

    val predictions = model.transform(testData)

    predictions.select("predictedLabel", "label", "features").show(5)

    val evaluator = new MulticlassClassificationEvaluator()
      .setLabelCol("indexedLabel")
      .setPredictionCol("prediction")
      .setMetricName("accuracy")

    val accuracy = evaluator.evaluate(predictions)
    println("Test Error = " + (1.0 - accuracy))
    val rfModel = model.stages(2).asInstanceOf[RandomForestClassificationModel]
    println("Learned classification forest model:\n" + rfModel.toDebugString)
  }
}
```

**4. 梯度增强树分类器**

梯度增强树（GBT）是使用决策树组合的流行分类和回归方法。以下示例以LibSVM格式加载数据集，将其分解为训练和测试集，在第一个数据集上训练，然后在被测试的集合上进行训练。

```scala
val gbt = new GBTClassifier()
      .setLabelCol("indexedLabel")
      .setFeaturesCol("indexedFeatures")
      .setMaxIter(10)
```

**5. 多层感知器分类器**

多层感知器分类器（Multilayer perceptron classifier）是基于[前馈人工神经网络](https://en.wikipedia.org/wiki/Feedforward_neural_network)的分类器。 MLPC由多层节点组成。 每个层完全连接到网络中的下一层。 输入层中的节点表示输入数据。 所有其他节点通过输入与节点权重ww和偏差bb的线性组合将输入映射到输出，并应用激活功能。 这可以用矩阵形式写入具有K + 1层的MLPC，如下所示：

​                                         $y(x) = f_K(...f_2(w_2^Tf_1(w_1^Tx + b1) + b2) ... +b_K)$

中间层节点使用Sigmoid（logistic）函数：

​                                                             $f(z_i) = \frac1{1 + e^{-z_i}}$

输出层节点使用softmax函数：

​                                                             $f(z_i) = \frac {e^{z_i}}{\sum_{k=1}^{N}e^{z_k}}$

输出层中的节点数N对应于类的数量。MLPC采用反向传播来学习模型。我们使用物流损失函数进行优化和L-BFGS作为优化程序。

```scala
object MultilayerPerceptronClassifierExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("MultilayerPerceptronClassifierExample")
      .master("local")
      .getOrCreate()

    val data = spark.read.format("libsvm").load("data/mllib/sample_multiclass_classification_data.txt")

    val splits = data.randomSplit(Array(0.6, 0.4), seed = 1234L)
    val train = splits(0)
    val test = splits(1)
    //    设置神经网络的层数
    //    输入层有4个神经元、两个隐含层分别有5和4个神经元，输出层有3个
    val layers = Array[Int](4, 5, 4, 3)

    val trainer = new MultilayerPerceptronClassifier()
      .setLayers(layers)
      .setBlockSize(128)
      .setSeed(1234L)
      .setMaxIter(100)

    val model = trainer.fit(train)

    val result = model.transform(test)
    val predictionAndLabel = result.select("prediction", "label")
    val evaluator = new MulticlassClassificationEvaluator()
      .setMetricName("accuracy")
    println("Test set accuracy = " + evaluator.evaluate(predictionAndLabel))
  }
}
```

**6. One-vs-Rest classifier**一对全分类器

[OneVsRest](http://en.wikipedia.org/wiki/Multiclass_classification#One-vs.-rest)将一个给定的二分类算法有效地扩展到多分类问题应用中，也叫做“One-vs-All.”算法。OneVsRest是一个Estimator。它采用一个基础的Classifier然后对于k个类别分别创建二分类问题。类别i的二分类分类器用来预测类别为i还是不为i，即将i类和其他类别区分开来。最后，通过依次对k个二分类分类器进行评估，取置信最高的分类器的标签作为i类别的标签。

```scala
object OneVsRestExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("OneVsRestExample")
      .getOrCreate()

    val inputData = spark.read.format("libsvm")
      .load("data/mllib/sample_multiclass_classification_data.txt")
    val Array(train, test) = inputData.randomSplit(Array(0.8, 0.2))
    val classifier = new LogisticRegression()
      .setMaxIter(10)
      .setTol((1E-6)) //迭代算法的收敛性
      .setFitIntercept(true)

    val ovr = new OneVsRest().setClassifier(classifier)

    val ovrModel = ovr.fit(train)
    val predictions = ovrModel.transform(test)
    val evaluator = new MulticlassClassificationEvaluator()
      .setMetricName("accuracy")

    val accuracy = evaluator.evaluate(predictions)
    println(s"Test Error = ${1 - accuracy}")
  }
}
```

**7. 朴素贝叶斯分类器**

朴素贝叶斯法是基于贝叶斯定理与特征条件独立假设的分类方法。

朴素贝叶斯的思想基础是这样的：对于给出的待分类项，求解在此项出现的条件下各个类别出现的概率，在没有其它可用信息下，我们会选择条件概率最大的类别作为此待分类项应属的类别。

朴素贝叶斯分类的正式定义如下：

1、设![img](http://latex.codecogs.com/gif.latex?x%20=%20%5Cleft%5C%7B%20%7B%7Ba_1%7D,%7Ba_2%7D,%20%5Cldots%20,%7Ba_m%7D%7D%20%5Cright%5C%7D) 为一个待分类项，而每个a为x的一个特征属性。

2、有类别集合![img](http://latex.codecogs.com/gif.latex?C%20=%20%5Cleft%5C%7B%20%7B%7By_1%7D,%7By_2%7D,%20%5Cldots%20,%7By_n%7D%7D%20%5Cright%5C%7D) 。

3、计算![img](http://latex.codecogs.com/gif.latex?P%5Cleft(%20%7B%7By_1%7D%5Cleft%7C%20x%20%5Cright.%7D%20%5Cright),P(%7By_2%7D%5Cleft%7C%20x%20%5Cright.),%20%5Cldots%20,P(%7By_n%7D%5Cleft%7C%20x%20%5Cright.)) 。

4、如果![img](http://latex.codecogs.com/gif.latex?P%5Cleft(%20%7B%7By_k%7D%5Cleft%7C%20x%20%5Cright.%7D%20%5Cright)%20=%20max%5C%7B%20P%5Cleft(%20%7B%7By_1%7D%5Cleft%7C%20x%20%5Cright.%7D%20%5Cright),P%5Cleft(%20%7B%7By_2%7D%5Cleft%7C%20x%20%5Cright.%7D%20%5Cright),%20%5Cldots%20,P%5Cleft(%20%7B%7By_n%7D%5Cleft%7C%20x%20%5Cright.%7D%20%5Cright)%5C%7D) ，则![img](http://latex.codecogs.com/gif.latex?x%20%5Cin%20%7By_k%7D) 。

那么现在的关键就是如何计算第3步中的各个条件概率。我们可以这么做：

1、找到一个已知分类的待分类项集合，这个集合叫做训练样本集。

2、统计得到在各类别下各个特征属性的条件概率估计。即![img](http://latex.codecogs.com/gif.latex?P(%7Ba_1%7D%7B%5Cleft%7C%20y%20%5Cright._1%7D),P(%7Ba_2%7D%7B%5Cleft%7C%20y%20%5Cright._1%7D),%20%5Cldots%20,P(%7Ba_m%7D%5Cleft%7C%20%7B%7By_1%7D%7D%20%5Cright.);P(%7Ba_1%7D%7B%5Cleft%7C%20y%20%5Cright._2%7D),P(%7Ba_2%7D%7B%5Cleft%7C%20y%20%5Cright._2%7D),%20%5Cldots%20,P(%7Ba_m%7D%5Cleft%7C%20%7B%7By_2%7D%7D%20%5Cright.);%20%5Cldots%20;P(%7Ba_1%7D%7B%5Cleft%7C%20y%20%5Cright._n%7D),P(%7Ba_2%7D%7B%5Cleft%7C%20y%20%5Cright._n%7D),%20%5Cldots%20,P(%7Ba_m%7D%7B%5Cleft%7C%20y%20%5Cright._n%7D)) 

3、如果各个特征属性是条件独立的，则根据贝叶斯定理有如下推导：

![img](http://latex.codecogs.com/gif.latex?P%5Cleft(%20%7B%7By_i%7D%5Cleft%7C%20x%20%5Cright.%7D%20%5Cright)%20=%20%5Cfrac%7B%7BP(x%5Cleft%7C%20%7B%7By_i%7D)P(%7By_i%7D)%7D%20%5Cright.%7D%7D%7B%7BP(x)%7D%7D) 

因为分母对于所有类别为常数，因为我们只要将分子最大化皆可。又因为各特征属性是条件独立的，所以有：

![img](http://latex.codecogs.com/gif.latex?P%5Cleft(%20%7Bx%5Cleft%7C%20%7B%7By_i%7D%7D%20%5Cright.%7D%20%5Cright)P%5Cleft(%20%7B%7By_i%7D%7D%20%5Cright)%20=%20P%5Cleft(%20%7B%7Ba_1%7D%5Cleft%7C%20%7B%7By_i%7D%7D%20%5Cright.%7D%20%5Cright)P(%7Ba_2%7D%5Cleft%7C%20%7B%7By_i%7D%7D%20%5Cright.)%20%5Cldots%20P(%7Ba_m%7D%5Cleft%7C%20%7B%7By_i%7D%7D%20%5Cright.)%20=%20P%5Cleft(%20%7B%7By_i%7D%7D%20%5Cright)%5Cprod%20P%5Cleft(%20%7B%7Ba_j%7D%5Cleft%7C%20%7B%7By_i%7D%7D%20%5Cright.%7D%20%5Cright)) 

spark.ml现在支持多项朴素贝叶斯和伯努利朴素贝叶斯。

```scala
object NaiveBayesExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("OneVsRestExample")
      .getOrCreate()

    val data = spark.read.format("libsvm").load("data/mllib/sample_libsvm_data.txt")

    val Array(trainingData, testData) = data.randomSplit(Array(0.7,0.3), seed = 1234L)
    val model = new NaiveBayes()
      .fit(trainingData)
    val predictions = model.transform(testData)
    val evaluator = new MulticlassClassificationEvaluator()
        .setLabelCol("label")
        .setPredictionCol("prediction")
       .setMetricName("accuracy")
    val accuracy = evaluator.evaluate(predictions)
    println("Test set accuracy: " + accuracy)
    spark.stop()
  }
}
```

#### 二、回归

**1.线性回归**

以下示例演示了训练弹性网络正则化线性回归模型并提取模型汇总统计量。

```scala
val lr= new LinearRegression()
  .setMaxIter(10)
  .setRegParam(0.3)
  .setElasticNetParam(0.8)

val lrModel = lr.fit(training)
println(s"Coefficients : ${lrModel.coefficients} Intercept: ${lrModel.intercept}")

val trainingSummary = lrModel.summary
println(s"num iterations : ${trainingSummary.totalIterations}")
println(s"objectiveHistory : ${trainingSummary.objectiveHistory.mkString(", ")}")
trainingSummary.residuals.show()//残差
println(s"RMSE: ${trainingSummary.rootMeanSquaredError}")//均方误差
println(s"r2: ${trainingSummary.r2}")//决定系数
```

**2.广义线性回归GLM**

与线性回归假设输出服从高斯分布不同，广义线性模型（GLMs）指定线性模型的因变量$Y_i$服从指数型分布。Spark的GeneralizedLinearRegression接口允许指定GLMs包括线性回归、泊松回归、逻辑回归等来处理多种预测问题。目前 spark.ml仅支持指数型分布家族中的一部分类型，如下：

| 分布类型 | 应变量类型 | 支持连接函数类型          |
| -------- | ---------- | ------------------------- |
| 高斯分布 | 连续       | Identity*,  Log,  Inverse |
| 二项分布 | 二值       | Logit*, Probit, CLogLog   |
| 泊松分布 | 计数       | Log*, Identity, Sqrt      |
| 伽马分布 | 连续       | Inverse*, Idenity, Log    |

> logit、probit以及cloglog都是统计变换，目的是将二项分布数据转换为一种形式，以便能用线性模型估计直接估计模型的参数。

* 注意目前Spark在 `GeneralizedLinearRegression`仅支持最多4096个特征，如果特征超过4096个将会引发异常。对于线性回归和逻辑回归，如果模型特征数量会不断增长，则可通过 LinearRegression 和LogisticRegression来训练。

park的GeneralizedLinearRegression接口提供汇总统计来诊断GLM模型的拟合程度，包括残差、p值、残差、Akaike信息准则及其它。

```scala
object GeneralizedLinearRegressionExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("GeneralizedLinearRegressionExample")
      .getOrCreate()

    val dataset = spark.read.format("libsvm")
      .load("data/mllib/sample_linear_regression_data.txt")

    val glr = new GeneralizedLinearRegression()
      .setFamily("gaussian")//模型中使用的误差分布类型。
      .setLink("identity")//连接函数名，描述线性预测器和分布函数均值之间关系
      .setMaxIter(10)
      .setRegParam(0.3)

    val  model = glr.fit(dataset)
//  输出权值向量和截距
    println(s"Coefficients: ${model.coefficients}")
    println(s"Intercept: ${model.intercept}")

    val summary = model.summary
    println(s"Coefficient Standart errors: ${summary.coefficientStandardErrors.mkString(", ")}")
    println(s"T Values: ${summary.tValues.mkString(",")}")
    println(s"P Values: ${summary.pValues.mkString(",")}")
    println(s"Dispersion: ${summary.dispersion}")
    println(s"Null Deviance: ${summary.nullDeviance}")
    println(s"Residual Degree Of Freedom Null: ${summary.residualDegreeOfFreedomNull}")
    println(s"Deviance: ${summary.deviance}")
    println(s"Residual Degree Of Freedom: ${summary.residualDegreeOfFreedom}")
    println(s"AIC: ${summary.aic}")
    println("Deviance Residuals: ")
    summary.residuals().show()
  }
}
```

**3.决策树回归**

 决策树以及其集成算法是机器学习分类和回归问题中非常流行的算法。因其易解释性、可处理类别特征、易扩展到多分类问题、不需特征缩放等性质被广泛使用。树集成算法如随机森林以及boosting算法几乎是解决分类和回归问题中表现最优的算法。

​       决策树是一个贪心算法递归地将特征空间划分为两个部分，在同一个叶子节点的数据最后会拥有同样的标签。每次划分通过贪心的以获得最大信息增益为目的，从可选择的分裂方式中选择最佳的分裂节点。节点不纯度有节点所含类别的同质性来衡量。工具提供为分类提供两种不纯度衡量（基尼不纯度和熵），为回归提供一种不纯度衡量（方差）。

​       spark.ml支持二分类、多分类以及回归的决策树算法，适用于连续特征以及类别特征。另外，对于分类问题，工具可以返回属于每种类别的概率（类别条件概率），对于回归问题工具可以返回预测在偏置样本上的方差。

```scala
object DecisionTreeRegressionExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("DecisionTreeClassificationExample")
      .getOrCreate()

    val data = spark.read.format("libsvm").load("data/mllib/sample_libsvm_data.txt")
    val featureIndexer = new VectorIndexer()
      .setInputCol("features")
      .setOutputCol("indexedFeatures")
      .setMaxCategories(4)
      .fit(data)
    val Array(trainingData, testData) = data.randomSplit(Array(0.7, 0.3))

    val dt = new DecisionTreeRegressor()
      .setLabelCol("label")
      .setFeaturesCol("indexedFeatures")

    val pipeline = new Pipeline()
      .setStages(Array(featureIndexer,dt))

    val model = pipeline.fit(trainingData)
    val predictions = model.transform(testData)
    predictions.select("prediction","label","features").show(5)

    val evaluator = new RegressionEvaluator()
      .setLabelCol("label")
      .setPredictionCol("prediction")
      .setMetricName("rmse")
    val rmse = evaluator.evaluate(predictions)
    println("Root Mean Squared Error (RMSE) on test data = " + rmse)

    val treeModel = model.stages(1).asInstanceOf[DecisionTreeRegressionModel]
    println("Learned regression tree model:\n" + treeModel.toDebugString)
  }
}
```

**4.随机森林回归**

​       随机森林是决策树的集成算法。随机森林包含多个决策树来降低过拟合的风险。随机森林同样具有易解释性、可处理类别特征、易扩展到多分类问题、不需特征缩放等性质。

​       随机森林分别训练一系列的决策树，所以训练过程是并行的。因算法中加入随机过程，所以每个决策树又有少量区别。通过合并每个树的预测结果来减少预测的方差，提高在测试集上的性能表现。

随机性体现：

1. 每次迭代时，对原始数据进行二次抽样来获得不同的训练数据。
2. 对于每个树节点，考虑不同的随机特征子集来进行分裂。

除此之外，决策时的训练过程和单独决策树训练过程相同。对新实例进行预测时，随机森林需要整合其各个决策树的预测结果。回归和分类问题的整合的方式略有不同。分类问题采取投票制，每个决策树投票给一个类别，获得最多投票的类别为最终结果。回归问题每个树得到的预测结果为实数，最终的预测结果为各个树预测结果的平均值。

spark.ml支持二分类、多分类以及回归的随机森林算法，适用于连续特征以及类别特征。

```scala
object RandomForestRegressorExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("DecisionTreeClassificationExample")
      .getOrCreate()

    val data = spark.read.format("libsvm").load("data/mllib/sample_libsvm_data.txt")
    val featureIndexer = new VectorIndexer()
      .setInputCol("features")
      .setOutputCol("indexedFeatures")
      .setMaxCategories(4)
      .fit(data)

    val Array(trainingData, testData) = data.randomSplit(Array(0.7, 0.3))

    val rf = new RandomForestRegressor()
      .setFeaturesCol("indexedFeatures")
      .setLabelCol("label")

    val pipeline = new Pipeline()
      .setStages(Array(featureIndexer, rf))

    val model = pipeline.fit(trainingData)
    val predictions = model.transform(testData)
    predictions.select("prediction", "label", "features").show(5)

    val evaluator = new RegressionEvaluator()
      .setLabelCol("label")
      .setPredictionCol("prediction")
      .setMetricName("rmse")

    val rmse = evaluator.evaluate(predictions)
    println(s"Root Mean Squared Errpes:\n ${rmse}")

    val rfModel = model.stages(1).asInstanceOf[RandomForestRegressionModel]
    println("Learned regression forest model:\n" + rfModel.toDebugString)
  }
}
```

**5.梯度增强树回归**

  梯度提升树是一种决策树的集成算法。它通过反复迭代训练决策树来最小化损失函数。决策树类似，梯度提升树具有可处理类别特征、易扩展到多分类问题、不需特征缩放等性质。Spark.ml通过使用现有[decision tree](http://spark.apache.org/docs/latest/mllib-decision-tree.html)工具来实现。

​       梯度提升树依次迭代训练一系列的决策树。在一次迭代中，算法使用现有的集成来对每个训练实例的类别进行预测，然后将预测结果与真实的标签值进行比较。通过重新标记，来赋予预测结果不好的实例更高的权重。所以，在下次迭代中，决策树会对先前的错误进行修正。

​       对实例标签进行重新标记的机制由损失函数来指定。每次迭代过程中，梯度迭代树在训练数据上进一步减少损失函数的值。spark.ml为分类问题提供一种损失函数（Log Loss），为回归问题提供两种损失函数（平方误差与绝对误差）

```scala
object GradientBoostedTreeRegressorExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("DecisionTreeClassificationExample")
      .getOrCreate()

    val data = spark.read.format("libsvm").load("data/mllib/sample_libsvm_data.txt")
    val featureIndexer = new VectorIndexer()
      .setInputCol("features")
      .setOutputCol("indexedFeatures")
      .setMaxCategories(4)
      .fit(data)
    val Array(trainingData, testData) = data.randomSplit(Array(0.7, 0.3))
    val gbt = new GBTRegressor()
      .setLabelCol("label")
      .setFeaturesCol("indexedFeatures")
      .setMaxIter(10)

    val pipeline = new Pipeline()
      .setStages(Array(featureIndexer, gbt))

    val model = pipeline.fit(trainingData)
    val predictions = model.transform(testData)
    predictions.select("prediction","label", "features").show(5)

    val evaluator = new RegressionEvaluator()
      .setLabelCol("label")
      .setPredictionCol("prediction")
      .setMetricName("rmse")

    val rmse = evaluator.evaluate(predictions)
    println("Root Mean Squared Error (RMSE) on test data = " + rmse)

    val gbtModel = model.stages(1).asInstanceOf[GBTRegressionModel]
    println("Learned regression GBT model:\n" + gbtModel.toDebugString)
  }
}
```