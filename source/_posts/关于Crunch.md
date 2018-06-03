---
title: 关于Crunch
date: 2018-03-21 10:20:16
tags: [Hadoop, 大数据, Crunch]
---
> 本篇文章主要来自<<Hadoop权威指南>>Crunch部分学习笔记

Crunch是用来写MapReduce管线的高层API,它注重程序员友好的JAVA类型和旧式的纯JAVA对象,还有一组丰富的数据变换操作和多级管线.因为Crunch位于上层,故Crunch管线是高度可组合的,可以把常用功能提取到库中给其他程序重用.Crunch不依赖于MapReduce,也可以用Spark作为分布式引擎来运行Crunch管线.
  <!-- more-->
示例
---
以如下实例引出基本概念:
```java
import org.apache.crunch.*;
import org.apache.crunch.fn.Aggregators;
import org.apache.crunch.impl.mr.MRPipeline;
import org.apache.crunch.io.To;

import static org.apache.crunch.types.writable.Writables.*;

public class MaxTemperatureCrunch {
    public static void main(String[] args) {
        if (args.length != 2) {
            System.err.printf("Usage: MaxtemperatureCrunch <input> <output>");
            System.exit(-1);
        }

        Pipeline pipeline = new MRPipeline(MaxTemperatureCrunch.class);
        PCollection<String> records = pipeline.readTextFile(args[0]);
        PTable<String, Integer> yearTemperatures = records.parallelDo(toYearTemPairFn(), tableOf(strings(), ints()));
        PTable<String, Integer> maxTemps = yearTemperatures.groupByKey().combineValues(Aggregators.MAX_INTS());
        maxTemps.write(To.textFile(args[1]));
        PipelineResult result = pipeline.done();
        System.exit(result.succeeded() ? 0 : 1);
    }

    static DoFn<String, Pair<String, Integer>> toYearTemPairFn() {
       return new DoFn<String, Pair<String, Integer>>() {
           NcdcRecordParser parser = new NcdcRecordParser();
           @Override
           public void process(String input, Emitter<Pair<String, Integer>> emitter) {
               parser.parse(input);
               if (parser.isValidTemperature()) {
                   emitter.emit(Pair.of(parser.getYear(), parser.getAirTemperature()));
               }
           }
       };
    }
}
```
先构建Crunch pipline对象,代表希望运行的计算, pipeline可以有多个阶段,即具有多个输入,输出,分支和迭代都是有可能的.

使用MapReduce运行管线,因此创建MRPipeline,也可使用MemPipeline在内存中运行管线或者SparkPipeline运行在Spark中.

Pipeline.readTextFile()可以将文本文件转换为String类型的PCollection对象,每个String代表一行文本.

PCollection< S >是最基本的Crunch数据类型,表示由S型元素组成的*不可修改*且*无序*的分布式集合,可被视为非物化的Collection,因为*它的元素没有被读取到内存*.Crunch对PCollection做各种操作并产生一个新的PCollection.
PCollection.parallellDo()为PCollection中的*每个元素*都执行某种操作,返回一个新的PCollection.
ParallelDo()的方法签名如下:
>`<T> PCollection <T> parallelDo(DoFn <S, T> var1, PType <T> var2);`

第二个参数PType< T >向Crunch传递有关T的java类型以及如何序列化该类型的信息
PTable < K,V >是一个扩展的PCollection,它是由键值对构成的分布式multi-map,可以具有重复键值对.
PTable.GroupBy执行的是MR的shuffle操作,按键对表分组,返回PGroupedTable < K,V >,它的combineValues()方法能把一个键的所有值聚合起来,就像MR中reducer做的那样.
管线的最后一步操作就是调用write()将表写入文件,write()输入就是通过静态工厂TO的textFile方法创建的一个文本文件对象,实际上使用了TextOutputFormat格式来完成这个操作.
为了执行管线,必须调用done()方法,程序阻塞直至管线执行完毕.

Crunch核心API
---
**基本操作**
- union() : 对两个PCollection进行"并集"操作(如果两个PCollection中有相同的元素,这个元素在union后会出现多次),进行union()操作时他们必须由同一管线创建,并且具有相同的类型.
```java
PCollection<Integer> a = MemPipeline.collectionOf(1, 2, 3);
PCollection<Integer> b = MemPipeline.collectionOf(2);
PCollection<Integer> c = a.union(b);
assertEquals("{2,1,2,3}", dump(c));```
- parallelDo() : 为输入的PCollection< S >中的每个元素调用某个函数,并返回包含该调用结果的一个新的输出PCollection<T>.
 ```java
        PCollection<String> a = MemPipeline.collectionOf("cherry", "apple", "banana");
        PCollection<Integer> b = a.parallelDo(new MapFn<String, Integer>() {
            @Override
            public Integer map(String input) {
                return input.length();
            }
        }, ints());
        assertEquals("{6,5,6}", dump(b));```
parallelDo常用来过滤在后续步骤中不需要的数据,Crunch专门提供了filter()方法,参数是一个特殊DoFn,为FilterFn,只用实现accept()即可只是是否保留该数据到输出中,他的方法签名没有PType,因为输入与输出类型相同.
```java
        PCollection<String> a = MemPipeline.collectionOf("cherry", "apple", "banana");
        PCollection<String> b = a.filter(new FilterFn<String>() {
            @Override
            public boolean accept(String s) {
                return s.length() %2 == 0;
            }
        });
        assertEquals("{cherry,banana}", dump(b));```
从由某些值构成的PCollection中提取键以形成一个PTable是常见操作,Crunch为此提供了by()方法,参数是MapFn()< S, K >,将值映S射成键K.
```java
        PCollection<String> a = MemPipeline.typedCollectionOf(strings(), "cherry", "apple",
                "banana");
        PTable<Integer,String> b = a.by(new MapFn<String, Integer>() {
            @Override
            public Integer map(String input) {
                return input.length();
            }
        }, ints());
        assertEquals("{(6,cherry),(5,apple),(6,banana)}", dump(b));
```
- groupByKey() : 把PTable< K,V >中具有相同键的所有值聚合起来,可以看做MR中的混洗操作,返回PGroupedTable< K,V >,Crunch可以根据表的大小为groupByKey()设置分区数量,也可以通过重载groupByKey(int i)指定分区数量.
```java
        PGroupedTable<Integer,String> c = b.groupByKey();
        assertEquals("{(5,[apple]),(6,[cherry,banana])}", dump(c));```
- combineValues() : 最常见以组合函数CombineFn< K,V >作为输入,CombineFn< K,V >就是`DoFn<Pair<K,Iterable<V>>, Pair<K,V>>`的简写,返回一个```PTable<K,V>```
```java
        PTable<Integer, String> d = c.combineValues(new CombineFn<Integer, String>() {
            @Override
            public void process(Pair<Integer, Iterable<String>> integerIterablePair, Emitter<Pair<Integer, String>> emitter) {
                StringBuilder sb = new StringBuilder();
                for (Iterator i = integerIterablePair.second().iterator(); i.hasNext(); ) {
                    sb.append(i.next());
                    if(i.hasNext())
                        sb.append(";");
                }
                emitter.emit(Pair.of(integerIterablePair.first(), sb.toString()));
            }
        });
        assertEquals("{(5,apple),(6,cherry;banana)}", dump(d));```
由于没有对键进行改变,可以使用重载的combineValues(),以Aggregator对象作为输入,仅对值进行操作,可以使用Aggregators内置的Aggregator实现操作,比如之前的Aggregators.MAX_INTS().
```java
        PTable<Integer, String> e = c.combineValues(Aggregators.STRING_CONCAT(";",false));
        assertEquals("{(5,apple),(6,cherry;banana)}", dump(e));```
想要聚合PGroupedTable中的值并返回一个与被分组的值的类型不同的结果,可用mapValues()实现,
```java
 PTable<Integer, Integer> f = c.mapValues(new MapFn<Iterable<String>, Integer>() {
            @Override
            public Integer map(Iterable<String> strings) {
                return Iterables.size(strings);
            }
        },ints());
        assertEquals("{(5,1),(6,2)}", dump(f));```
combineValues()可被当作MR的combiner来运行,而mapValues()被解释为ParallelDo()操作,只能在reduce端运行.

**类型**

每个PCollection< S >都有一个关联的类PType< S >,用于封装有关PCollection中的元素类型的信息,也给出了从持久化存储器读取到PCollection的序列化格式和反方向的序列化格式.
两个PType家族,用哪个取决于管线的文件格式,都可用于文本文件:
1. Hadoop Writables: 顺序文件
2. Avro: Avro数据文件

PCollection使用的PType在PCollection创建时指定,有时隐式指定,例如读取文本文件时使用默认的Writables.

*记录和元组*
记录record : 通过名称来访问字段的类,用记录写的Crunch程序更易于理解和阅读
元组tuple : 通过位置来访问字段的类,用于少量元素组成元组的便捷类:Pair< K,V >, Tuple3< V1, V2, V3 >等

在Crunch管线中使用记录的便捷方式是定义一个字段能够被Avro Reflect序列化的,和一个无参构造器.
```java
public class WeatherRecord {
    private int year;
    private int temperature;
    private String stationId;

    public WeatherRecord() {
    }

    public WeatherRecord(int year, int temperature, String stationId) {
        this.year = year;
        this.temperature = temperature;
        this.stationId = stationId;
    }
    ...
}```
这样就可以从PCollection< String >生成PCollection< WeatherRecord >,并利用parallelDo()将每一行文本解析到WeatherRecord中:
```java
        PCollection<String> lines = pipeline.read(From.textFile(inputPath));
        PCollection<WeatherRecord> records = lines.parallelDo(new DoFn<String, WeatherRecord>() {
                NcdcRecordParser parser = new NcdcRecordParser();
            public void process(String s, Emitter<WeatherRecord> emitter) {
                parser.parse(s);
                if(parser.isValidTemperature()) {
                    emitter.emit(new WeatherRecord(parser.getYearInt(), parser.getAirTemperature(), parser.getStationId()));
                }
            }
        }, Avros.records(WeatherRecord.class));
        //按照字段定义的顺序对记录排序
        PCollection<WeatherRecord> sortedREcords = Sort.sort(records);```
上段代码末尾Avro.records()方法为Avro Reflect数据类型返回了一个Crunch PType.

**源和目标**
- 读取源
Crunch管线的起点是一个或多个Source< T >实例,它们指明了输入数据的存储位置和PType<T>,读取文本用readTextFile就可以,但是其他类型的数据源则需要使用read()方法,以Source<T>对象为输入,From类是各种文件源静态工厂方法的集合,用作为read()的参数.

Crunch的数据源包括:
 * From.textFile(inputPath)
 * From.AvroFile(inputPath, Avros.records())
 * From.SequenceFile(inputPath, Writable(), Writable())
 * AvroParquetFileSource
 * FromHbase.table() 等.

- 写入文件
在写入目标时调用PCollection.write()方法,传入Traget即可,可以通过TO类的静态工厂方法来选择文件类型

- 输入已存在
如果目标文件已经存在,再调用write()方法时会引发错误, 除非在write()方法中传入参数Target.WriteMode.OVERWRITE.
> 写入模式:
> * OVERWRITE:管线运行前删除已存在文件
> * APPEND:在输出目录下新建文件,保留旧文件,通过文件名区分新旧文件
> * CHECKPOINT:将当前工作保存在一个文件中,从而使新管线可从检查点而不是管线起点开始执行.

- 组合的源和目标
希望一个文件既作为写入目标又作为读取的源,在AT类中有一些静态方法可用于创建SourceTarget实例.

**函数**
- 函数序列化
Crunch在管线执行时将所有DoFn实例都序列化到一个文件中,并通过Hadoop分布式缓存机制将文件分发给各任务节点,然后任务本身反序列化,使得能被调用.因此,需要确保自己的DoFn实现能通过标准的Java序列化机制进行序列化.
如果DoFn作为内部类被定义在没有实现Serializable的外部类中,会出现问题.
如果函数依赖于一个以实例变量形式表示的非序列化状态,且他的类没有被Serializable,这种情况下将该实例标为transient(瞬态),从而不会序列化该状态.

- 对象重用
在MR中,reducer的值迭代器中的对象是可重用的,其目的是为了提高效率,对于PGroupedTable的conbineValues()和mapValues()方法的迭代器来说,Crunch有相同的行为.因此想要在迭代器外部引用一个对象,就应当复制该对象,以避免对象标识错误.
> 可重用:[reduce方法会反复执行多次，但key和value相关的对象只有两个，reduce会反复重用这两个对象。所以如果要保存key或者value的结果，只能将其中的值取出另存或者重新clone一个对象（例如Text store = new Text(value) 或者 String a = value.toString()），而不能直接赋引用。因为引用从始至终都是指向同一个对象，你如果直接保存它们，那最后它们都指向最后一个输入记录。会影响最终计算结果而出错。](http://blog.csdn.net/fxdaniel/article/details/50255197)
```java
 public static <K,V> PTable<K,Collection<V>> uniqueValues(PTable<K, V> table) {
        PTypeFamily tf = table.getTypeFamily();
        final PType<V> valueType = table.getValueType();
        return table.groupByKey().mapValues("unique", new MapFn<Iterable<V>, Collection<V>>() {
            @Override
            public void initialize() {
                valueType.initialize(getConfiguration());//初始化PType使其能够访问配置以执行复制操作
            }
            @Override
            public Collection<V> map(Iterable<V> vs) {
                Set<V> collected = new HashSet<V>();
                for(V value : vs){
                    collected.add(valueType.getDetachedValue(value));//PType.getDetachedValue()复制JAVA类.
                }
                return collected;
            }
        },tf.collections(table.getValueType()));
    }```

**物化**

物化(Materlization)是让PCollection中的值变得可用的过程,只有物化后的值才能被程序读取
物化最直接的方法是调用PCollection.materialize(),它返回了一个Iterable集合.
```java
 Pipeline pipeline = new MRPipeline(getClass());
    PCollection<String> lines = pipeline.readTextFile(inputPath);
    PCollection<String> lower = lines.parallelDo(new ToLowerFn(), strings());

    Iterable<String> materialized = lower.materialize();
    for (String s : materialized) { // pipeline从这个位置开始执行
      System.out.println(s);
    }```
 调用materlize并不会导致管线执行,只有从Iterable中创建一个Iterator后,Crunch才执行管线,执行完毕后才执行迭代操作.

* PObject
  物化PCollection的另一种方式是使用PObject,PObject<T>是一个被标记为future的对象,程序在创建PObject时,类型为T的值得计算可能还未完成.计算结果调用getValue()方法获取,计算完成之前他会一直处于阻塞状态.
 ```java
    Pipeline pipeline = new MRPipeline(getClass());
    PCollection<String> lines = pipeline.readTextFile(inputPath);
    PCollection<String> lower = lines.parallelDo(new ToLowerFn(), strings());

    PObject<Collection<String>> po = lower.asCollection();
    for (String s : po.getValue()) { // pipeline is run
      System.out.println(s);
    }
    assertEquals(expectedContent, po.getValue());

    System.out.println("About to call done()");
    PipelineResult result = pipeline.done();```
   asCollection()方法将PCollection<T>变换为普通的Java Collection<T>.

管线执行
---
管线构建期间,Crunch会建立一个内部执行计划,每个计划都是由PCollection操作构成的一个有向无环图,每个计划内的PCollection都与产生它的操作之间存在引用关系,另外,每个PCollection都有一个内部状态,用于记录他是否已被物化.
**运行管线**
调用Pipeline.run()可以显式执行管线操作,步骤:
优化处理,将执行计划分为若干阶段 --> 执行优化计划中的各阶段,使得到的PCololection物化(此时可能会得到中间文件) --> 向调用者返回PipelineResult对象,包含每个阶段的信息以及管线是否成功.
clean()清除物化PCollection时创建的临时中间文件.
done() = 先run()后clean()
runAsync()是run()的配对方法,它在管线启动后立刻返回,返回类型是PipelineExecution,它实现了Future< PiplineResult >.
```java
        pipeline.writeTextFile(table, tmpDir.getFileName("output"));
        PipelineExecution execution = pipeline.runAsync();
        PipelineResult result = execution.get();
        assertTrue(result.succeeded());```
**停止管线**
为了正确停止管线,需要异步启动该管线,以保留对PipelineExecution对象的引用.
`PipelineExecution execution = pipeline.runAsync();`
这种情况调用kill()方法并等待其完成即可关闭管线.这样管线在此之前运行在这个集群上的所有作业都将被杀死
```java
execution.kill();
execution.waitUntilDone();
```
**查看Crunch计划**
通过 PipelineExecution.getPlanDotFile()可以获得一个以字符串形式表现的管线操作图的DOT文件.
另一种在隐式运行的管线中获取操作图的方式是将DOT文件的表示存储在作业配置中,一边在管线执行完后检查.
```JAVA
        PCollection<String> lines = pipeline.readTextFile(inputPath);
        PCollection<String> lower = lines.parallelDo("lower", new ToLowerFn(), strings());
        PTable<String, Long> counts = lower.count();
        PTable<Long, String> inverseCounts = counts.parallelDo("inverse", new InversePairFn<String, Long>(), tableOf(longs(), strings()));
        PTable<Long, Integer> hist = inverseCounts.groupByKey().mapValues("count values", new CountValuesFn<String>(), ints());
        hist.write(To.textFile(outputPath), Target.WriteMode.OVERWRITE);
        PipelineExecution execution = pipeline.runAsync();
        String dot = execution.getPlanDotFile();
        Files.write(dot, dotFile(), Charsets.UTF_8);
        execution.waitUntilDone();
        pipeline.done();```
用命令`dot -Tpng -O *.dot`将.dot文件转换为.png文件
![](http://p5s7d12ls.bkt.clouddn.com/18-3-21/79771268.jpg)

每个GBK操作将作为MapReduce的混洗步骤实现.
