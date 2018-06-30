---
title: MLlib-模型选择和超参数调优
date: 2018-06-30 15:55:59
tags: [机器学习, Spark, MLlib]
---

ji中的一个重要任务是模型选择，或使用数据找到给定任务的最佳模型或参数。这也叫调优。可以针对个体估算器（如Logistic回归）或包括多个算法，特征化和其他步骤的整个管道完成调整。用户可以一次调整整个流水线，而不是单独调整管道中的每个元素。

机器学习中的一个重要任务是模型选择，或使用数据找到给定任务的最佳模型或参数。这也叫调优.可以针对个体估算器（如Logistic回归）或包括多个算法，特征化和其他步骤的整个管道完成调整。用户可以一次调整整个流水线，而不是单独调整管道中的每个元素。

<!-- more--> 

MLlib支持使用 CrossValidator和TrainValidationSplit等工具进行模型选择。这些工具需要以下项目：

* Estimator（估算器）：算法或管道调整
* ParamMaps集：可供选择的参数，有时称为“参数网格”进行搜索
* Evaluator（评估者）：衡量拟合模型对延伸测试数据有多好的度量

在高层次上，这些模型选择工具的工作如下：

* 将输入数据分成单独的训练和测试数据集
* 对于每个（训练，测试）对，他们遍历一组ParamMaps：
  * 对于每个ParamMap，它们使用这些参数fit Estimator，获得拟合的Model，并使用Evaluator评估Model的性能。
* 选择由最佳性能参数组合生成的模型

Estimator可以是回归问题的RegressionEvaluator，二进制数据的BinaryClassificationEvaluator或多类问题的MulticlassClassificationEvaluator。用于选择最佳ParamMap的默认度量可以被这些评估器中的每一个的setMetricName方法覆盖。为了帮助构建参数网格，可以使用ParamGridBuilder实用程序。

#### 一. 交叉验证

 CrossValidator将数据集划分为若干子集分别地进行训练和测试。如当k＝3时，CrossValidator产生3个训练数据与测试数据对，每个数据对使用2/3的数据来训练，1/3的数据来测试。对于一组特定的参数表，CrossValidator计算基于三组不同训练数据与测试数据对训练得到的模型的评估准则的平均值。确定最佳参数表后，CrossValidator最后使用最佳参数表基于全部数据来重新拟合估计器。

 注意对参数网格进行交叉验证的成本是很高的。如下面例子中，参数网格hashingTF.numFeatures有3个值，lr.regParam有2个值，CrossValidator使用2折交叉验证。这样就会产生(3*2)*2=12中不同的模型需要进行训练。在实际的设置中，通常有更多的参数需要设置，且我们可能会使用更多的交叉验证折数（3折或者10折都是经使用的）。所以CrossValidator的成本是很高的，尽管如此，比起启发式的手工验证，交叉验证仍然是目前存在的参数选择方法中非常有用的一种。

```scala
object CrossValidationExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder
      .master("local")
      .appName("ALSExample")
      .getOrCreate()
    val training = spark.createDataFrame(Seq(
      (0L, "a b c d e spark", 1.0),
      (1L, "b d", 0.0),
      (2L, "spark f g h", 1.0),
      (3L, "hadoop mapreduce", 0.0),
      (4L, "b spark who", 1.0),
      (5L, "g d a y", 0.0),
      (6L, "spark fly", 1.0),
      (7L, "was mapreduce", 0.0),
      (8L, "e spark program", 1.0),
      (9L, "a e c l", 0.0),
      (10L, "spark compile", 1.0),
      (11L, "hadoop software", 0.0)
    )).toDF("id", "text", "label")

    //创建一个pipeline,包括平tokenizer,tf,lr三个步骤
    val tokenizer = new Tokenizer()
      .setInputCol("text")
      .setOutputCol("words")
    val hashingTF = new HashingTF()
      .setInputCol(tokenizer.getOutputCol)
      .setOutputCol("features")
    val lr = new LogisticRegression()
      .setMaxIter(10)
    val pipeline = new Pipeline()
      .setStages(Array(tokenizer, hashingTF, lr))

    //我们使用ParamGridBuilder构建一个参数网格来搜索。
    val paramGrid = new ParamGridBuilder()
      .addGrid(hashingTF.numFeatures, Array(10, 100, 1000))
      .addGrid(lr.regParam, Array(0.1, 0.01))
      .build()

    val cv = new CrossValidator()
      .setEstimator(pipeline)
      .setEvaluator(new BinaryClassificationEvaluator) //默认metric是AUC
      .setEstimatorParamMaps(paramGrid)
      .setNumFolds(2)
    //在实际中使用要大于3
    //运行交叉验证并使用最好的参数
    val cvModel = cv.fit(training)

    val test = spark.createDataFrame(Seq(
      (4L, "spark i j k"),
      (5L, "l m n"),
      (6L, "mapreduce spark"),
      (7L, "apache hadoop")
    )).toDF("id", "text")

    cvModel.transform(test)
      .select("id", "text", "probability", "prediction")
      .collect()
      .foreach {
        case Row(id: Long, text: String, prob: Vector, pred: Double) =>
          println(s"($id, $text) --> prob=$prob, prediction=$pred")
      }
  }
}
```

#### 二. 训练验证分裂

  除了交叉验证以外，Spark还提供训练验证分裂用以超参数调整。和交叉验证评估K次不同，训练验证分裂只对每组参数评估一次。因此它计算代价更低，但当训练数据集不是足够大时，其结果可靠性不高。

​      与交叉验证不同，训练验证分裂仅需要一个训练数据与验证数据对。使用训练比率参数将原始数据划分为两个部分。如当训练比率为0.75时，训练验证分裂使用75%数据以训练，25%数据以验证。

​     与交叉验证相同，确定最佳参数表后，训练验证分裂最后使用最佳参数表基于全部数据来重新拟合估计器。

 ```scala
object TrainValidationSplitExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder
      .master("local")
      .appName("ALSExample")
      .getOrCreate()

    val data = spark.read.format("libsvm").load("data/mllib/sample_linear_regression_data.txt")
    val Array(training, test) = data.randomSplit(Array(0.9, 0.1), seed = 12345)
    val lr = new LinearRegression()
      .setMaxIter(10)

    val paramGrid = new ParamGridBuilder()
      .addGrid(lr.regParam, Array(0.1, 0.01))
      .addGrid(lr.fitIntercept)
      .addGrid(lr.elasticNetParam, Array(0.0, 0.5, 1.0))
      .build()

    val trainValidationSplit = new TrainValidationSplit()
      .setEstimator(lr)
      .setEvaluator(new RegressionEvaluator)
      .setEstimatorParamMaps(paramGrid)
      .setTrainRatio(0.8)

    val model = trainValidationSplit.fit(training)
    model.transform(test)
      .select("features", "label", "prediction")
      .show()
  }
}
 ```

