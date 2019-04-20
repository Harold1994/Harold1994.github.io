---
title: fink官网学习笔记——基本API概念
date: 2019-04-20 15:15:58
tags: 大数据
---

> 翻译自Flink文档：https://ci.apache.org/projects/flink/flink-docs-release-1.8/dev/api_concepts.html

#### 1. Lazy Evaluation（惰性计算）

程序的main方法执行后不久立即执行数据的加载和转换，每个操作被创建后加入执行计划，这些操作只有在execute()被显式调用后才会真正执行。程序被本地执行还是在集群上执行取决于执行环境

 <!-- more-->

#### 2.Specifying Keys（指定键）

join, coGroup, keyBy, groupBy等操作需要元素集合指明一个键才能执行，其他的转换操作（如Reduce, GroupReduce, Aggregate, Windows）允许数据先被分组后在执行。

A DataSet is grouped as

```java
DataSet<...> input = // [...]
DataSet<...> reduced = input
  .groupBy(/*define key here*/)
  .reduceGroup(/*do something*/);
```

while a key can be specified on a DataStream using

```java
DataStream<...> input = // [...]
DataStream<...> windowed = input
  .keyBy(/*define key here*/)
  .window(/*window specification*/);
```

**Flink的数据模型不是基于键值对的**，因此使用者并需要在物理上将数据集打包成键值对的形式，"key"是虚拟的，他们可以被定义成在实际数据上的函数来指导grouping操作的执行。

##### （1）为Tuple定义键

最简单的形式是在一个或多个字段上做分组操作：

```java
// 元组在第一个字段（整数类型）上分组。
DataStream<Tuple3<Integer,String,Long>> input = // [...]
KeyedStream<Tuple3<Integer,String,Long>,Tuple> keyed = input.keyBy(0)
```

```java
//将元组分组在由第一个和第二个字段组成的复合键上。
DataStream<Tuple3<Integer,String,Long>> input = // [...]
KeyedStream<Tuple3<Integer,String,Long>,Tuple> keyed = input.keyBy(0,1)
```

> 嵌套的Tuple：
>
> 在类似DataStream<Tuple3<Tuple2<Integer, Float>,String,Long>> ds;上执行KeyBy(0)将会导致使用Tuple2<Integer, Float>这个整体成为分组的依据，如果想只是用Tuple2中的一个字段作为key，就需要使用到下面的"使用字段表达式定义键"

##### （2）使用字段表达式定义键

可以使用基于字符串的字段表达式来指定嵌套的字段并定义key，方便进行grouping, sorting, joining, coGrouping等操作：

```java
// some ordinary POJO (Plain old Java Object)
public class WC {
  public String word;
  public int count;
}
DataStream<WC> words = // [...]
DataStream<WC> wordCounts = words.keyBy("word").window(/*window specification*/);
```

###### 字段表达式的句法：

*  POJO中字段的字段名
* Tuple字段中的字段名或者从0开始的偏移量
* 可以选择POJO或Tuple嵌套的字段，支持任意嵌套和混合POJO和元组，例如f1.user.zip或user.f3.1.zip

* 使用"*"通配符选择完整类型

##### （3）使用键选择函数定义键

键选择函数使用一个element作为输入，返回这个element的键，键可以是任何类型，并且可以从确定性计算中导出。

```java
// some ordinary POJO
public class WC {public String word; public int count;}
DataStream<WC> words = // [...]
KeyedStream<WC> keyed = words
  .keyBy(new KeySelector<WC, String>() {
     public String getKey(WC wc) { return wc.word; }
   });
```

#### 3.指定转换函数

大多数转换擦欧哦需要用户自定义函数，以下是几种实例：

##### 实现接口

```java
class MyMapFunction implements MapFunction<String, Integer> {
  public Integer map(String value) { return Integer.parseInt(value); }
};
data.map(new MyMapFunction());
```

##### 匿名函数

```java
data.map(new MapFunction<String, Integer> () {
  public Integer map(String value) { return Integer.parseInt(value); }
});
```

##### Lambda表达式

```java
data.filter(s -> s.tartsWith("http://"))
```

```java
data.reduce((i1,i2) -> i1 + i2);
```

##### Rich Function

所有需要用户自定义函数作为参数的转换函数，都可以使用 rich function作为参数，如

```java
class MyMapFunction implements MapFunction<String, Integer> {
  public Integer map(String value) { return Integer.parseInt(value); }
};
```

可被写为：

```java
class MyMapFunction extends RichMapFunction<String, Integer> {
  public Integer map(String value) { return Integer.parseInt(value); }
};
```

rich function也可以作为匿名方法实现。

RichFuction除了提供原来MapFuction的方法之外，还提供open, close, getRuntimeContext 和setRuntimeContext方法，这些功能可用于参数化函数（传递参数），创建和完成本地状态，访问广播变量以及访问运行时信息以及有关迭代中的信息。

#### 4.支持的数据类型

Flink对DataSet或DataStream中可以包含的元素类型设置了一些限制。 原因是系统分析类型以确定有效的执行策略。

有6种不同的数据类型：

1. **Java Tuples** and **Scala Case Classes**
2. **Java POJOs**
3. **Primitive Types（原始数据类型）**
4. **Regular Classes**
5. **Values**
6. **Hadoop Writables**
7. **Special Types**

需要注意的有：

* 对于POJO数据类型，POJO的泪必须是public的，必须要有一个无参构造器，类中的所有变量必须是public的或者可以通过getter和setter访问到，类中变量的类型必须是Flink支持的数据类型。
* 对于Regular Classes，要求类中的字段可序列化，Flink支持大多数Java和Scala类，所有未标识为POJO类型的类（请参阅上面的POJO要求）都由Flink作为常规类类型处理。 Flink将这些数据类型视为黑盒子，并且无法访问其内容（例如，用类中的字段用于有效排序）。使用序列化框架Kryo对常规类型进行序列化和反序列化。

* Value类型是实现了org.apache.flinktypes.Value接口的数据类型，通过read和write方法，它可以手动描述其序列化和反序列化。当传统的序列化工具比较低效时就可以使用Value类型的数据。Flink内置了预先定义好的Value数据类供使用，包括ByteValue`, `ShortValue`, `IntValue`, `LongValue`, `FloatValue`, `DoubleValue`, `StringValue`, `CharValue`, `BooleanValue，这些Value类型充当基本数据类型的可变变体：它们的值可以更改，允许程序员重用对象并减轻垃圾收集器的压力。
* 特殊数据类型：可以使用特殊类型，包括Scala的Either，Option和Try。 Java API有自己的自定义Either实现。 与Scala的Either类似，它代表两种可能类型的值，左或右。 两者都可用于错误处理或需要输出两种不同类型记录的运算符。

##### 类型擦除和类型推断

> 这仅适用于Java

Java在编译后会丢掉泛型类型信息，Flink在准备执行程序时需要类型信息，Flink Java API尝试以各种方式重建丢弃的类型信息，并将其显式存储在数据集和运算符中。可以通过DataStream.getType()检索类型.该方法返回TypeInformation的一个实例，这是Flink表示类型的内部方式。

类型推断有其局限性，在某些情况下需要程序员的“合作”.这方面的示例是从集合创建数据集的方法，例如ExecutionEnvironment.fromCollection(),可以在其中传递描述类型的参数。 但是像MapFunction <I，O>这样的通用函数也可能需要额外的类型信息。

ResultTypeQueryable接口可以通过输入格式和函数实现，以明确告知API其返回类型。 调用函数的输入类型通常可以通过先前操作的结果类型来推断

#### 5.Accumulators & Counters（累加器和计数器）

累加器是一个简单的结构，它包含add操作和一个最终累加的result值，这个值在job结束之后任仍然可用。

计数器是最简单的累加器，: You can increment it using the `Accumulator.add(V value)` method. At the end of the job Flink will sum up (merge) all partial results and send the result to the client. Accumulators are useful during debugging or if you quickly want to find out more about your data.

Flink内置累加器：

* IntCounter LongCounter DoubleCounte
* Histogram（直方图）:A histogram implementation for a discrete(分散的) number of bins. Internally it is just a map from Integer to Integer. You can use this to compute distributions of values, e.g. the distribution of words-per-line for a word count program.

使用方法：

First you have to create an accumulator object (here a counter) in the user-defined transformation function where you want to use it.

```java
private IntCounter numLines = new IntCounter();
```

Second you have to register the accumulator object, typically in the `open()` method of the *rich* function. Here you also define the name.

```java
getRuntimeContext().addAccumulator("num-lines", this.numLines);
```

You can now use the accumulator anywhere in the operator function, including in the `open()` and `close()` methods.

```java
this.numLines.add(1);
```

The overall result will be stored in the `JobExecutionResult` object which is returned from the `execute()` method of the execution environment (currently this only works if the execution waits for the completion of the job).

```java
myJobExecutionResult.getAccumulatorResult("num-lines")
```

一个job中的所有累加器共享一个命名空间，因此可以在job的不同的操作函数中使用同一个累加器，Flink将在内部合并所有具有相同名称的累加器。

目前累加器的结果仅在整个作业结束后才可用。 

