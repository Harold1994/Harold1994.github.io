---
title: MLlib-特征的提取、转换与选择
date: 2018-06-26 10:18:30
tags: [机器学习, Spark, MLlib]
---

本博客介绍使用功能的算法，大致分为以下几类：

- 提取：从“原始”数据中提取特征
- 转换：缩放，转换或修改特征
- 选择：从较大的一组特征中选择一个子集
- 局部敏感哈希（LSH）：这类算法将特征变换的方面与其他算法相结合。

<!-- more--> 

#### 一、特征提取

**1.TF-IDF**

[词频（Term Frequency）- 逆向文档频率（Inverse Document Frequency）](http://en.wikipedia.org/wiki/Tf%E2%80%93idf) 是一种在文本挖掘中广泛使用的特征向量化方法，以反映一个单词在语料库中的重要性。定义：*t* 表示由一个单词，*d* 表示一个文档，*D* 表示语料库（corpus），词频 *TF(t,d)* 表示某一个给定的单词 *t* 出现在文档 *d* 中的次数， 而文档频率 *DF(t,D)* 表示包含单词 *t*  的文档次数。如果我们只使用词频 *TF* 来衡量重要性，则很容易过分强调出现频率过高并且文档包含少许信息的单词，例如，'a'，'the'，和 'of'。如果一个单词在整个语料库中出现的非常频繁，这意味着它并没有携带特定文档的某些特殊信息（换句话说，该单词对整个文档的重要程度低）。逆向文档频率是一个数字量度，表示一个单词提供了多少信息：

​                                                                  $IDF(t,D) = \log \frac {|D| + 1}{DF(t,D) + 1}$

 其中，|*D*| 是在语料库中文档总数。由于使用对数，所以如果一个单词出现在所有的文件，其IDF值变为0。注意，应用平滑项以避免在语料库之外的项除以零（为了防止分母为0，分母需要加1）。因此，TF-IDF测量只是TF和IDF的产物：（对TF-IDF定义为TF和IDF的乘积）

​                                                      $TD-IDF(t,d,D) = TF(t,d) \cdot IDF(t,D)$

 关于词频TF和文档频率DF的定义有多种形式。在MLlib，我们分离TF和IDF，使其灵活。

**TF（词频Term Frequency）**：`HashingTF`与`CountVectorizer都可以`用于生成词频TF向量。

HashingTF是一个需要特征词集的转换器（Transformer），它可以将这些集合转换成固定长度的特征向量。在文本处理中，“特征词集”有一系列的特征词构成。`HashingTF`利用[hashing trick](http://en.wikipedia.org/wiki/Feature_hashing)，原始特征（raw feature）通过应用哈希函数映射到索引中。这里使用的哈希函数是[murmurHash 3](https://en.wikipedia.org/wiki/MurmurHash)。然后根据映射的索引计算词频。这种方法避免了计算全局特征词对索引映射的需要，这对于大型语料库来说可能是昂贵的，但是它具有潜在的哈希冲突，其中不同的原始特征可以在散列之后变成相同的特征词。为了减少碰撞的机会，我们可以增加目标特征维度，即哈希表的桶数。由于使用简单的模数将散列函数转换为列索引，建议使用两个幂作为特征维，否则不会将特征均匀地映射到列。默认功能维度为$2^{18} = 262144$。可选的二进制切换参数控制词频计数,当设置为true时，所有非零频率计数设置为1。这对于模拟二进制而不是整数的离散概率模型尤其有用。

**IDF（逆向文档频率）**：IDF是一个适合数据集并生成IDFModel的评估器（`Estimator），`IDFModel获取特征向量（通常由HashingTF或CountVectorizer创建）并缩放每列。直观地说，它下调了在语料库中频繁出现的列。

CountVectorizer将文本文档转换为关键词计数的向量。

在下面的代码段中，我们从一组句子开始。我们使用Tokenizer将每个句子分成单词。对于每个句子（词袋，词集：bag of words），我们使用HashingTF将该句子哈希成特征向量。我们使用IDF来重新缩放特征向量；这通常会在使用文本作为功能时提高性能。然后，我们的特征向量可以被传递给学习算法。

```scala
object TfIdfExample {
  def main(args: Array[String]): Unit = {
    val spark= SparkSession.builder()
      .master("local")
      .appName("TfIdfExample")
      .getOrCreate()
    val sentenceData = spark.createDataFrame(Seq(
      (0.0, "Hi I heard about Spark"),
      (0.0, "I wish Java could use case classes"),
      (1.0, "Logistic regression models are neat")
    )).toDF("label","sentence")

    val tokenizer = new Tokenizer().setInputCol("sentence").setOutputCol("words")
    val wordsData = tokenizer.transform(sentenceData)

    val hashingTF =new HashingTF()
      .setInputCol("words").setOutputCol("rawFeatures").setNumFeatures(20)

    val featurizedData = hashingTF.transform(wordsData)

    val idf = new IDF().setInputCol("rawFeatures").setOutputCol("features")
    val idfModel = idf.fit(featurizedData)

    val rescaledData = idfModel.transform(featurizedData)
    rescaledData.select("label","features").foreach(println(_))
  }
}
```

**2.Word2Vec**

Word2Vec是一个Estimator(评估器)，它采用表示文档的单词序列，并训练一个Word2VecModel。 该模型将每个单词映射到一个唯一的固定大小向量。 Word2VecModel使用文档中所有单词的平均值将每个文档转换为向量; 该向量然后可用作预测，文档相似性计算等功能。

在下面的代码段中，我们从一组文档开始，每一个文档都用一个单词序列表示。 对于每个文档，我们将其转换为特征向量。 然后可以将该特征向量传递给学习算法。

```scala
object Word2VecExample {
  def main(args: Array[String]): Unit = {
    val spark= SparkSession.builder()
      .master("local")
      .appName("Word2VecExample")
      .getOrCreate()

    val documentDF = spark.createDataFrame(Seq(
      "Hi I heard about Spark".split(" "),
      "I wish Java could use case classes".split(" "),
      "Logistic regression models are neat".split(" ")
    ).map(Tuple1.apply)).toDF("text")

     val word2Vec = new Word2Vec()
      .setInputCol("text")
      .setOutputCol("result")
      .setVectorSize(3)
      .setMinCount(0)

    val model = word2Vec.fit(documentDF)
    val result = model.transform(documentDF)
    result.collect().foreach{
      case Row(text:Seq[_],feature:Vector) =>
        println(s"Text : [${text.mkString(", ")}] => \nVector: $feature")
    }
  }
}
```

**3.CountVectorizer**

CountVectorizer和CountVectorizerModel旨在帮助将文本文档集合转换为标记数的向量。 当先验词典不可用时，CountVectorizer可以用作估计器来提取词汇表，并生成CountVectorizerModel。 该模型通过词汇生成文档的稀疏表示，然后可以将其传递给其他算法，如LDA。

在拟合过程中，CountVectorizer将选择通过语料库按术语频率排序的top前几vocabSize词。 可选参数minDF还通过指定术语必须出现以包含在词汇表中的文档的最小数量（或小于1.0）来影响拟合过程。 另一个可选的二进制切换参数控制输出向量。 如果设置为true，则所有非零计数都设置为1.对于模拟二进制而不是整数的离散概率模型，这是非常有用的。假设我们有如下的DataFrame包含id和texts两列：

```
 id | texts
----|----------
 0  | Array("a", "b", "c")
 1  | Array("a", "b", "b", "c", "a")
```

文本中的每一行都是Array[String]类型的文档。调用CountVectorizer的拟合产生一个具有词汇表（a, b, c）的CountVectorizerModel。然后转换后的输出列 包含“向量”这一列：

```
 id | texts                           | vector
----|---------------------------------|---------------
 0  | Array("a", "b", "c")            | (3,[0,1,2],[1.0,1.0,1.0])
 1  | Array("a", "b", "b", "c", "a")  | (3,[0,1,2],[2.0,2.0,1.0])
```

每个向量表示文档在词汇表上的标记数。

```scala
object CountVectorizerExample {
  def main(args: Array[String]): Unit = {
    val spark= SparkSession.builder()
      .master("local")
      .appName("Word2VecExample")
      .getOrCreate()

    val df = spark.createDataFrame(Seq(
      (0, Array("a", "b", "c","d")),
      (1, Array("a", "b", "b", "c", "a","d","d"))
    )).toDF("id", "words")

    val cvModel : CountVectorizerModel = new CountVectorizer()
      .setInputCol("words")
      .setOutputCol("features")
      .setVocabSize(3)
      .setMinDF(2)
      .fit(df)
   //也可以使用先验词汇
    val cvm = new CountVectorizerModel(Array("a","b","c"))
      .setInputCol("words")
      .setOutputCol("result")

    cvModel.transform(df).show(false)
//    cvm.transform(df).show(false)
  }
}
```

#### 二、特征变换

**1.Tokenizer分词器**

[Tokenization](http://en.wikipedia.org/wiki/Lexical_analysis#Tokenization)（文本符号化）是将文本 （如一个句子）拆分成单词的过程。（在Spark ML中）[Tokenizer](http://spark.apache.org/docs/2.0.2/api/scala/index.html#org.apache.spark.ml.feature.Tokenizer)（分词器）提供此功能。下面的示例演示如何将句子拆分为词的序列。

[RegexTokenizer](http://spark.apache.org/docs/2.0.2/api/scala/index.html#org.apache.spark.ml.feature.RegexTokenizer) 提供了（更高级的）基于正则表达式 (regex) 匹配的（对句子或文本的）单词拆分。默认情况下，参数"pattern"(默认的正则表达式: `"\\s+"`) 作为分隔符用于拆分输入的文本。或者，用户可以将参数“gaps”设置为 false ，指定正则表达式"pattern"表示"tokens"，而不是分隔符，这样作为划分结果找到的所有匹配项。

```scala
object TokenizerExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("TokenizerExample")
      .getOrCreate()

    val sentenceDataFrame = spark.createDataFrame(Seq(
      (0, "Hi I heard about Spark"),
      (1, "I wish Java could use case classes"),
      (2, "Logistic,regression,models,are,neat")
    )).toDF("id", "sentence")

    val tokenizer = new Tokenizer().setInputCol("sentence").setOutputCol("words")
    val regexTokenizer = new RegexTokenizer()
      .setInputCol("sentence")
      .setOutputCol("words")
      .setPattern("\\w")

    val countTokens = udf { (words: Seq[String]) => words.length }

    val tokenized = tokenizer.transform(sentenceDataFrame)
    tokenized.select("sentence", "words")
      .withColumn("tokens", countTokens(col("words"))).show(false)

    val regexTokenized = regexTokenizer.transform(sentenceDataFrame)
    regexTokenized.select("sentence", "words")
      .withColumn("tokens", countTokens(col("words"))).show(false)
  }
}
```

**2.StopWordsRemover去停用词**

[Stop words （停用字）](https://en.wikipedia.org/wiki/Stop_words)是（在文档中）频繁出现，但未携带太多意义的词语，它们不应该参与算法运算。

 `StopWordsRemover（的作用是）将`输入的字符串 （如分词器 [Tokenizer](http://spark.apache.org/docs/2.0.2/ml-features.html#tokenizer) 的输出）中的停用字删除（后输出）。停用字表由 `stopWords `参数指定。对于某些语言的默认停止词是通过调用 `StopWordsRemover.loadDefaultStopWords(language) 设置的`，可用的选项为"丹麦"，"荷兰语"、"英语"、"芬兰语"，"法国"，"德国"、"匈牙利"、"意大利"、"挪威"、"葡萄牙"、"俄罗斯"、"西班牙"、"瑞典"和"土耳其"。布尔型参数 `caseSensitive `指示是否区分大小写 （默认为否）。

假设有如下DataFrame，有id和raw两列：

|  id  | raw                          |
| :--: | ---------------------------- |
|  0   | [I, saw, the, red, baloon]   |
|  1   | [Mary, had, a, little, lamb] |

通过对 raw 列调用 StopWordsRemover，我们可以得到筛选出的结果列如下：

|  id  | raw                          | filtered             |
| :--: | ---------------------------- | -------------------- |
|  0   | [I, saw, the, red, baloon]   | [saw, red, baloon]   |
|  1   | [Mary, had, a, little, lamb] | [Mary, little, lamb] |

其中，“I”, “the”, “had”以及“a”被移除。

```scala
object StopWordsRemoverExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("TokenizerExample")
      .getOrCreate()

    val remover = new StopWordsRemover()
      .setInputCol("raw")
      .setOutputCol("filtered")

    val dataSet = spark.createDataFrame(Seq(
      (0, Seq("I", "saw", "the", "red", "baloon")),
      (1, Seq("Mary", "had", "a", "little", "lamb"))
    )).toDF("id", "raw")

    remover.transform(dataSet).show(false)
  }
}
```

**3.n-gram N元模型**

一个 [n-gram](https://en.wikipedia.org/wiki/N-gram)是一个长度为n（整数）的字的序列。NGram可用于将输入特征转换成n-grams。

N-Gram 的输入为一系列的字符串（例如：[Tokenizer](http://spark.apache.org/docs/2.0.2/ml-features.html#tokenizer)分词器的输出）。参数 n 表示每个 n-gram 中单词（terms）的数量。输出将由 n-gram 序列组成，其中每个 n-gram 由空格分隔的 n 个连续词的字符串表示。如果输入的字符串序列少于n个单词，NGram 输出为空。

```scala
object NGramExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("NGramExample")
      .getOrCreate()

    val wordDataFrame = spark.createDataFrame(Seq(
      (0, Array("Hi", "I", "heard", "about", "Spark")),
      (1, Array("I", "wish", "Java", "could", "use", "case", "classes")),
      (2, Array("Logistic", "regression", "models", "are", "neat"))
    )).toDF("id", "words")

    val ngram = new NGram().setN(2).setInputCol("words").setOutputCol("ngrams")

    val ngramDataFrame = ngram.transform(wordDataFrame)
    ngramDataFrame.select("ngrams").show(false)
  }
}
输出：
+------------------------------------------------------------------+
|ngrams                                                            |
+------------------------------------------------------------------+
|[Hi I, I heard, heard about, about Spark]                         |
|[I wish, wish Java, Java could, could use, use case, case classes]|
|[Logistic regression, regression models, models are, are neat]    |
+------------------------------------------------------------------+
```

**4.Binary二值化**

Binarization （二值化）是将数值特征阈值化为二进制（0/1）特征的过程。

Binarizer（ML提供的二元化方法）二元化涉及的参数有 inputCol（输入）、outputCol（输出）以及threshold（阀值）。（输入的）特征值大于阀值将二值化为1.0，特征值小于等于阀值将二值化为0.0。inputCol 支持向量（Vector）和双精度（Double）类型。

```scala
object BinaryExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("BinaryExample")
      .master("local")
      .getOrCreate()

    val data = Array((0,0.1),(1,0.8),(2,0.2))
    val dataFrame = spark.createDataFrame(data).toDF("id", "feature")

    val binarizer : Binarizer = new Binarizer()
      .setInputCol("feature")
      .setOutputCol("binarized_feature")
      .setThreshold(0.5)

    val binarizedDataFrame = binarizer.transform(dataFrame)
    println(s"Binarizer output with Threshold = ${binarizer.getThreshold}")
    binarizedDataFrame.show()
  }
}
```

**5.主成分分析**

PCA 是使用正交变换将可能相关变量的一组观察值转换为称为主成分的线性不相关变量的值的一组统计过程。 PCA 类训练使用 PCA 将向量投影到低维空间的模型。下面的例子显示了如何将5维特征向量投影到3维主成分中。

```scala
object PCAExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("PCAExample")
      .master("local")
      .getOrCreate()

    val data = Array(
      Vectors.sparse(5, Seq((1, 1.0), (3, 7.0))),
      Vectors.dense(2.0, 0.0, 3.0, 4.0, 5.0),
      Vectors.dense(4.0, 0.0, 0.0, 6.0, 7.0)
    )

    val df = spark.createDataFrame(data.map(Tuple1.apply)).toDF("features")

    val pca = new PCA()
      .setInputCol("features")
      .setOutputCol("pcaFeatures")
      .setK(3)
      .fit(df)

    val result = pca.transform(df).select("pcaFeatures")
    result.show(false)
  }
}
```

**6.StringIndexer（字符串-索引变换）**

StringIndexer（字符串-索引变换）将标签的字符串列编号变成标签索引列。标签索引序列的取值范围是[0，numLabels（字符串中所有出现的单词去掉重复的词后的总和）]，按照标签出现频率排序，出现最多的标签索引为0。如果输入是数值型，我们先将数值映射到字符串，再对字符串进行索引化。如果下游的 pipeline（例如：Estimator 或者 Transformer）需要用到索引化后的标签序列，则需要将这个 pipeline 的输入列名字指定为索引化序列的名字。大部分情况下，通过 setInputCol 设置输入的列名。

假设我们有如下的 DataFrame ，包含有 id 和 category 两列、

| id   | category |
| ---- | -------- |
| 0    | a        |
| 1    | b        |
| 2    | c        |
| 3    | a        |
| 4    | a        |
| 5    | c        |

标签类别（category）是有3种取值的标签：“a”，“b”，“c”。使用 StringIndexer 通过 category 进行转换成 categoryIndex 后可以得到如下结果：

+---+--------+-------------+
| id|category|categoryIndex|
+---+--------+-------------+
|  0|       a|          0.0|
|  1|       b|          2.0|
|  2|       c|          1.0|
|  3|       a|          0.0|
|  4|       a|          0.0|
|  5|       c|          1.0|
+---+--------+-------------+

“a”因为出现的次数最多，所以得到为0的索引（index）。第二多的“c”得到1的索引，“b”得到2的索引

另外，StringIndexer 在转换新数据时提供两种容错机制处理训练中没有出现的标签

- StringIndexer 抛出异常错误（默认值）
- 跳过未出现的标签实例。

```scala
val df = spark.createDataFrame(Seq(
      (0, "a"),
      (1, "b"),
      (2, "c"),
      (3, "a"),
      (4, "a"),
      (5, "c")
    )).toDF("id","category")

    val indexer = new StringIndexer()
      .setInputCol("category")
      .setOutputCol("categoryIndex")
      .fit(df)
    val indexed = indexer.transform(df)
    println(s"Transformed string column '${indexer.getInputCol}' " +
      s"to indexed column '${indexer.getOutputCol}'")
    indexed.show()
```

**7.OneHot独热编码**

[独热编码（One-hot encoding）](http://en.wikipedia.org/wiki/One-hot)将一列标签索引映射到一列二进制向量，最多只有一个单值。 该编码允许期望连续特征（例如逻辑回归）的算法使用分类特征。

```scala
object OneHotExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("BinaryExample")
      .master("local")
      .getOrCreate()

    val df = spark.createDataFrame(Seq(
      (0, "a"),
      (1, "b"),
      (2, "c"),
      (3, "a"),
      (4, "a"),
      (5, "c")
    )).toDF("id","category")

    val indexer = new StringIndexer()
      .setInputCol("category")
      .setOutputCol("categoryIndex")
      .fit(df)
    val indexed = indexer.transform(df)

    val encoder = new OneHotEncoder()
      .setInputCol("categoryIndex")
      .setOutputCol("categoryVec")

    val encoded = encoder.transform(indexed)
    encoded.show(false)
  }
}
```

**8.VectorIndexer(向量类型索引化)**

VectorIndexer可以帮助指定向量数据集中的分类特征。它可以自动确定哪些功能是分类的，并将原始值转换为类别索引。具体来说，它执行以下操作：

1. 取一个Vector类型的输入列和一个参数maxCategories。
2. 根据不同值的数量确定哪些功能应分类，其中最多maxCategories的功能被声明为分类。
3. 为每个分类功能计算基于0的类别索引。
4. 索引分类特征并将原始特征值转换为索引。

索引分类功能允许诸如决策树和树组合之类的算法适当地处理分类特征，提高性能。

在下面的示例中，我们读取标注点的数据集，然后使用VectorIndexer来确定哪些功能应被视为分类。我们将分类特征值转换为其索引。然后，该转换的数据可以传递给诸如DecisionTreeRegressor之类的算法来处理分类特征。

```scala
object VectorIndexerExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("VectorIndexerExample")
      .master("local")
      .getOrCreate()

    val data = spark.read.format("libsvm").load("data/mllib/sample_libsvm_data.txt")

    val indexer = new VectorIndexer()
      .setInputCol("features")
      .setOutputCol("indexed")
      .setMaxCategories(10)

    val indexerModel = indexer.fit(data)
    val categoricalFeatures : Set[Int] = indexerModel.categoryMaps.keys.toSet
    println(s"Choose ${categoricalFeatures.size} categorical features: " + categoricalFeatures.mkString(", "))

    val indexedData = indexerModel.transform(data)
    indexedData.show()
  }
}
```

**9.Interaction相互作用**

交互是一个变换器，它采用向量或双值列，并生成一个单个向量列，其中包含来自每个输入列的一个值的所有组合的乘积。

例如，如果有2个向量类型的列，每个列具有3个维度作为输入列，那么将获得一个9维向量作为输出列。

 假设我们有如下DataFrame，列为“id1”, “vec1” 和 “vec2”:

| id1  | vec1    | vec2    |
| ---- | ------- | ------- |
| 1    | 1, 2, 3 | 8, 4, 5 |
| 2    | 4, 3, 8 | 7, 9, 8 |

应用与这些输入列的交互，然后将交互作为输出列包含：

| id1  | vec1    | vec2    | interactedCol                           |
| ---- | ------- | ------- | --------------------------------------- |
| 1    | 1, 2, 3 | 8, 4, 5 | 8, 4, 5, 16, 8, 10, 24, 12, 15          |
| 2    | 4, 3, 8 | 7, 9, 8 | 56,  72,  64, 42, 54, 48, 112, 144, 128 |

```scala
object InteractionExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("VectorIndexerExample")
      .master("local")
      .getOrCreate()

    val df = spark.createDataFrame(Seq(
      (1, 1, 2, 3, 8, 4, 5),
      (2, 4, 3, 8, 7, 9, 8),
      (3, 6, 1, 9, 2, 3, 6),
      (4, 10, 8, 6, 9, 4, 5),
      (5, 9, 2, 7, 10, 7, 3),
      (6, 1, 1, 4, 2, 8, 4)
    )).toDF("id1", "id2", "id3", "id4", "id5", "id6", "id7")

    val assembler1 = new VectorAssembler()
      .setInputCols(Array("id2","id2","id4"))
      .setOutputCol("vec1")

    val assembled1 = assembler1.transform(df)

    val assembler2 = new VectorAssembler().
      setInputCols(Array("id5", "id6", "id7")).
      setOutputCol("vec2")

    val assembled2 = assembler2.transform(assembled1).select("id1","vec1","vec2")

    val interaction = new Interaction()
      .setInputCols(Array("id1", "vec1", "vec2"))
        .setOutputCol("interactedCol")

    val interacted = interaction.transform(assembled2)

    interacted.show(false)
  }
}
```

**10.Normalizer(范数p-norm规范化)**

Normalizer是一个转换器，它可以将一组特征向量（通过计算p-范数）规范化。参数为p（默认值：2）来指定规范化中使用的p-norm。规范化操作可以使输入数据标准化，对后期机器学习算法的结果也有更好的表现。

下面的例子展示如何读入一个libsvm格式的数据，然后将每一行转换为$L^2$以及$L^\infty$形式。

```scala
object NormalizerExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("NormalizerExample")
      .master("local")
      .getOrCreate()

    val dataFrame = spark.createDataFrame(Seq(
      (0, Vectors.dense(1.0, 0.5, -1.0)),
      (1, Vectors.dense(2.0, 1.0, 1.0)),
      (2, Vectors.dense(4.0, 10.0, 2.0))
    )).toDF("id", "features")

    val normalizer = new Normalizer()
      .setInputCol("features")
      .setOutputCol("normFeatures")
      .setP(1.0)

    val l1NormData = normalizer.transform(dataFrame)
    println("Normalized using L^1 norm")
    l1NormData.show()

    val lInfNormData = normalizer.transform(dataFrame, normalizer.p -> Double.PositiveInfinity)
    println("Normalized using L^inf norm")
    lInfNormData.show()
  }
}
```

**11.StandardScalaer标准化**

StandardScaler转换Vector行的数据集，使每个要素标准化以具有单位标准偏差和 或 零均值。它需要参数：

- withStd：默认为True。将数据缩放到单位标准偏差。
- withMean：默认为false。在缩放之前将数据中心为平均值。它将构建一个密集的输出，所以在应用于稀疏输入时要小心。

StandardScaler是一个Estimator，可以适合数据集生成StandardScalerModel; 这相当于计算汇总统计数据。 然后，模型可以将数据集中的向量列转换为具有单位标准偏差和/或零平均特征。

请注意，如果特征的标准偏差为零，它将在该特征的向量中返回默认的0.0值。

以下示例演示如何以libsvm格式加载数据集，然后将每个要素归一化以具有单位标准偏差。

```scala
object StandardScalerExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("NormalizerExample")
      .master("local")
      .getOrCreate()

    val dataFrame = spark.read.format("libsvm").load("data/mllib/sample_libsvm_data.txt")

    val scaler = new StandardScaler()
      .setInputCol("features")
      .setOutputCol("scalerFeatures")
      .setWithStd(true)
      .setWithMean(false)

    val scalerModel = scaler.fit(dataFrame)

    val scaledData = scalerModel.transform(dataFrame)
    scaledData.show()
  }
}
```

**12.MinMaxScaler最大最小规范化**

MinMaxScaler转换Vector行的数据集，将每个要素的重新映射到特定范围（通常为[0，1]）。它需要参数：

- min：默认为0.0，转换后的下限，由所有功能共享。
- max：默认为1.0，转换后的上限，由所有功能共享。

MinMaxScaler计算数据集的统计信息，并生成MinMaxScalerModel。然后，模型可以单独转换每个要素，使其在给定的范围内。

特征E的重新缩放值被计算为：

​                           $Rescaleed(e_i) = \frac {e_i - E_min}{E_max - E_min}*(max-min) + min$

对于$E_{max}  = E_{min},Rescaled(e_i) = 0.5*(max+min)$

请注意，由于零值可能会转换为非零值，即使对于稀疏输入，变压器的输出也将为DenseVector。

以下示例演示如何以libsvm格式加载数据集，然后将每个要素重新缩放为[0，1]。

```scala
object MinMaxScalerExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("NormalizerExample")
      .master("local")
      .getOrCreate()

    val dataFrame = spark.createDataFrame(Seq(
      (0, Vectors.dense(1.0,0.1,-1.0)),
      (1, Vectors.dense(2.0, 1.1, 1.0)),
      (2, Vectors.dense(3.0, 10.1, 3.0))
    )).toDF("id", "features")

    val scaler = new MinMaxScaler()
      .setInputCol("features")
      .setOutputCol("scaledFeatures")

    val scalerModel = scaler.fit(dataFrame)

    val scaledData = scalerModel.transform(dataFrame)
    println(s"Features scaled to range [${scaler.getMin}, ${scaler.getMax}]")
    scaledData.select("features","scaledFeatures").show()
  }
}
```

**13.Bucketizer分箱器**

**Bucketizer** 将一列连续的特征转换为特征 **buckets**（区间），**buckets**（区间）由用户指定。**Bucketizer** 需要一个参数：

splits（分割）：这是个将连续的特征转换为 **buckets**（区间）的参数. **n+1**次分割时，将产生n个 **buckets（**区间）。一个**bucket（**区间）通过范围 **[x,y)** 中 **x** , **y** 来定义除了最后一个 **bucket** 包含 **y** 值。Splits（分割）应该是严格递增的。**-inf, inf** 之间的值必须明确提供来覆盖所有的 **Double** 值;另外,**Double** 值超出 **splits**（分割）指定的值将认为是错误的. 两个**splits** （拆分）的例子为 Array(Double.NegativeInfinity, 0.0, 1.0, Double.PositiveInfinity)以及Array(0.0, 1.0, 2.0)。

请注意,如果你不知道目标列的上线和下限,则应将 **Double.NegativeInfinity** 和  **Double.PositiveInfinity** 添加为**splits**（分割）的边界,以防止 **Bucketizer** 界限出现异常.

还请注意,提供的 **splits**（分割）必须严格按照增加的顺序,即 **s0 < s1 < s2 < ... < sn.**

下面这个例子演示了如何将包含 **Doubles 的一列 bucketize** （分箱）为另外一个索引列.

```scala
object BucketizerExample {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .master("local")
      .appName("BucketizerExample")
      .getOrCreate()

    val splits = Array(Double.NegativeInfinity, -0.5, 0.0, 0.5, Double.PositiveInfinity)
    val data = Array(-0.5,-0.3,0.0,0.2,0.8)
    val dataFrame = spark.createDataFrame(data.map(Tuple1.apply)).toDF("features")

    val bucketizer = new Bucketizer()
      .setInputCol("features")
      .setOutputCol("bucketedFeatures")
      .setSplits(splits)

    val bucketedData = bucketizer.transform(dataFrame)
    bucketedData.show()
  }
}
```