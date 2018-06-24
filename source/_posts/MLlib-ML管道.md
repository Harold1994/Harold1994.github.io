---
title: MLlib----ML管道
date: 2018-06-18 17:12:32
tags:　[机器学习, Spark, MLlib]
---

#### 一、从RDD到DataFrame

在之前的几篇MLlib机器学习博文中，使用的都是基于RDD的api,从Spark 2.0开始，spark.mllib软件包中的基于[RDD](http://spark.apache.org/docs/latest/programming-guide.html#resilient-distributed-datasets-rdds)的API已进入维护模式。 Spark的主要学习API现在是spark.ml包中基于[DataFrame](http://www.apache.wiki/pages/viewpage.action?pageId=2883736)的API。所以之后的博文都会以DataFrame为主，进入正题之前先说一下DataFrame相对于RDD的优点：

- DataFrames提供比RDD更加用户友好的API。 DataFrames的许多好处包括Spark Datasources，SQL / DataFrame查询，Tungsten和Catalyst优化以及跨语言的统一API。
- 用于MLlib的基于DataFrame的API为ML算法和跨多种语言提供了统一的API。
- DataFrames有助于实际的ML管道，特别是特征转换。

DataFrame是一种不可变的结构化的分布式数据集合，数据被组织在已命名的表格中，像我们常使用的表格，这使得处理大数据集更加方便。

关于RDD,DataFrame,DataSet的优缺点，[这篇文章](https://databricks.com/blog/2016/07/14/a-tale-of-three-apache-spark-apis-rdds-dataframes-and-datasets.html)进行了很细致的描述，这里不再赘述。

#### 二、Pipelines的主要概念

ML Pipelines提供了构建在 DataFrames 之上的一系列上层 API，帮助用户创建和调整切合实际的 ML Pipelines.**MLlib** 将机器学习算法的API标准化，以便将多种算法更容易地组合成单个 **Pipeline** （管道）或者工作流。

- **DataFrame**（数据模型）：**ML API** 将从**Spark SQL**查出来的 **DataFrame** 作为 **ML** 的数据集,数据集支持许多数据类型。例如,一个 **DataFrame** 可以有不同的列储存 text（文本）、feature（特征向量）、true labels（标注）、predictions（预测结果）等机器学习数据类型.
- **Transformer**（转换器）：使用 **Transformer** 将一个 **DataFrame** 转换成另一个 **DataFrame** 的算法，例如，一个 **ML Model** 是一个 **Transformer,**它将带有特征的 **DataFrame** 转换成带有预测结果的 **DataFrame.**
- **Estimator**（模型学习器）：**Estimator** 是一个适配 **DataFrame** 来生成 **Transformer（转换器）**的算法.例如,一个学习算法就是一个 **Estimator** 训练 **DataFrame** 并产生一个模型的过程**.**
- **Pipeline**（管道）：Pipeline 将多个 **Transformers** 和 **Estimators** 绑在一起形成一个工作流.
- **Parameter**（参数）：所有的 **Transformers** 和 **Estimators** 都已经使用标准的 **API** 来指定参数.

##### 1.DataFrame

机器学习可以应用于各种各样的数据类型，比如向量，文本，图形和结构化数据API采用 Spark Sql 的 DataFrame 就是为了支持各种各样的数据类型.

DataFrame支持许多基本的结构化的数据，另外除了 Spark SQL guide 列举的类型,DataFrame 还支持使用 ML Vector类型。

DataFrame 可以用标准的 RDD 显式或者非显式创建。DataFrame 中的列是有名称的．

##### 2.PipeLines组件

* 转换器Transformers

  转换器是特征变换和机器学习模型的抽象。转换器必须实现transform方法，这个方法将一个 DataFrame 转换成另一个 DataFrame，通常是附加一个或者多个列。比如：

  - 一个特征变换器是输入一个 DataFrame，读取一个列（比如：text），将其映射成一个新列（比如，特征向量），然后输出一个新的 DataFrame 并包含这个映射的列.
  - 一个机器学习模型是输入一个 DataFrame，读取包含特征向量的列,预测每个特征向量的标签,并输出一个新的 DataFrame ，并附加预测标签作为一列.

* 模型学习器Estimators

  Estimators 模型学习器是拟合和训练数据的机器学习算法或者其他算法的抽象。技术上来说, Estimator实现 fit()方法，这个方法输入一个 DataFrame*并产生一个 **Model** 即一个 **Transformer**（转换器）。举个例子，一个机器学习算法是一个 **Estimator** 模型学习器,比如这个算法是 **LogisticRegression**（逻辑回归），调用 **fit()** 方法训练出一个 **LogisticRegressionModel,**这是一个 **Model,**因此也是一个 Transformer（转换器）.

* Pipeline组件的参数

  **Transformer.transform()** 和 **Estimator.fit()** 都是无状态。以后,可以通过替换概念来支持有状态算法.每一个 **Transformer**（转换器）和 **Estimator （**模型学习器）都有一个唯一的ID，这在指定参数上非常有用

#### 三、PipeLine

在机器学习中,通常会执行一系列算法来处理和学习模型，比如，一个简单的文本文档处理流程可能包括这几个步骤：

- 把每个文档的文本分割成单词.
- 将这些单词转换成一个数值型特征向量.
- 使用特征向量和标签学习一个预测模型.

**MLlib** 代表一个流水线,就是一个 **Pipeline（管道）**，**Pipeline**（管道） 包含了一系列有特定顺序的管道步骤Transformers** 和 Estimator。

一个 **pipeline** 由多个步骤组成，每一个步骤都是一个 **Transformer**（转换器）或者 **Estimator**（模型学习器）。这些步骤按顺序执行，输入的 **DataFrame** 在通过每个阶段时进行转换。在 **Transformer** （转换器）步骤中，**DataFrame** 会调用 **transform()** 方法；在 **Estimator（**模型学习器）步骤中，**fit()** 方法被调用并产生一个 **Transformer**（转换器）(会成为 **PipelineModel**（管道模型）的一部分,或者适配 **Pipeline** ),并且 **DataFrame** 会调用这个 转换器的transform()方法.

![http://spark.apache.org/docs/latest/img/ml-Pipeline.png](http://spark.apache.org/docs/latest/img/ml-Pipeline.png)

如上图所示,顶部的一行代表 **Pipeline**（管道）有三个步骤。分词器和 HashingTF（词频））是转换器，第三个是模型学习器。下面一行表示流经管道的数据,其中圆柱表示 DataFrame。最初的DataFrame 有少量的文本文档和标签, 会调用 Pipeline.fit() 方法.Tokenizer.transform()方法将原始文本分割成单词,并将这些单词作为一列添加到 DataFrame。接下HashingTF.transform() 方法将单词列转换成特征向量,并向 DataFrame 添加带有这些向量的新列。由于**LogisticRegression**是一个模型学习器，**Pipeline** 会首先调用 **LogisticRegression.fit()** 来生成一个**LogisticRegressionModel**,然后在DataFrame 传送到下一个步骤之前调用 LogisticRegressionModel的transform() 方法。

同时 **Pipeline** 也是一个模型学习器。因此,Pipeline的fit()方法运行完之后,会生成一个 PipelineModel,即一个**Transformer**（转换器）,**PipelineModel** 用来在测试的时候使用。

![http://spark.apache.org/docs/latest/img/ml-PipelineModel.png](http://spark.apache.org/docs/latest/img/ml-PipelineModel.png)

在上图中，**PipelineModel** 有和原始的 **Pipeline（管道）**一样的步骤，但是在原始 **Pipeline** 所有的 **Estimators （**模型学习器）都会变成 **Transformers**（转换器）。当在测试集上调用 PipelineModel的 transform() 方法时,数据会按顺序通过装配的管道。每个步骤的 **transform()** 方法都会更新数据集并将 **DataFrame** 传递到下一个步骤.`

**Pipeline** 和 **PipelineModel 有助于**确保了训练集和测试集经过相同的处理步骤.

 ####　四、PipeLine实例

