---
title: Hive用户自定义聚合函数(UDAF)和表生成函数(UDTF)
date: 2018-05-30 21:45:40
tags: [大数据, Hive, Hadoop]
---

在之前关于Hive的[博文](https://harold1994.github.io/2018/03/17/%E5%85%B3%E4%BA%8EHIVE/)中写到了UDAF和UDTF,不过只是简单的带过,在UDAF部分继承是已经被废弃的的UDAF类,因此在这片博文中详细说明一下新的继承类的使用方法,算是还技术债吧.

#### 一. 用户自定义聚合函数

聚合函数会分多个阶段进行处理,基于UDAF执行的转换不同,在不同的阶段返回值类型也可能不同.聚合过程是在map或者reduce任务中执行的,任务task是一个[有内存限制](https://blog.csdn.net/androidlushangderen/article/details/50002015)的Java进程,因此在聚合过程中存储大的数据结构会产生溢出错误.

> 写UDAF时可以通过配置参数mapred.child.java.opts调整执行过程的内存需求量,但是此方式并非总是奏效.

##### 实例: 创建一个COLLECT UDAF来模拟GROUP_CONCAT

MySQL中的函数GROUP_CONCAT可以将一组中所有的元素按照用户指定的分隔符组装成一个字符串.

```sql
mysql> create table people( name varchar(10), friendname varchar(10) );
mysql> select * from people;
+--------+------------+
| name   | friendname |
+--------+------------+
| bob    | jone       |
| jone   | sara       |
| jone   | sara       |
| harold | lili       |
| bob    | sali       |
| bob    | sali       |
+--------+------------+
mysql> select name, group_concat(friendname SEPARATOR ',') from people group by name;
+--------+----------------------------------------+
| name   | group_concat(friendname SEPARATOR ',') |
+--------+----------------------------------------+
| bob    | jone,sali,sali                         |
| harold | lili                                   |
| jone   | sara,sara                              |
+--------+----------------------------------------+
```

在HIve中没有这个函数,但我们可以在Hive中无需增加新的语法实现同样的转换:

```mysql
hive> select name, concat_ws('|', collect_list(friend)) from people group by name;
bob	sara|john|ted
john	sara
ted	bob|sara
//或者
hive> select name, concat_ws('|', collect_set(friend)) from people group by name;
bob	["sara","john","ted"]
john	["sara"]
ted	["bob","sara"]
```

concat_ws()的第一个参数是分隔符,其它参数可以是字符串或字符串数组,collect_list()和collect_set()均返回集合中元素的数组,不过collect_set会对数组进行排重.

collect_set的UDAF将所有输入加入到一个java.util.Set集合中,这里将使用collect_set中的代码来将Set的实例替换成ArrayList实例,这样就不会实现对输入排重,相当于我们要手动实现collect_list.

用户聚合计算应该是允许数据任意划分为多个部分进行计算而不会影响结果的,使用的是分治的思想.

聚合过程的所有输入必须是基本数据类型,返回的是GenericUDAFEvaluator的子类对象.编写通用型UDAF需要两个类：解析器和计算器。解析器负责UDAF的参数检查，操作符的重载以及对于给定的一组参数类型来查找正确的计算器，建议继承AbstractGenericUDAFResolver类，具体实现如下：

```java
@Description(name = "collect", value = "_FUN_(x) - Returns a list of objects. " +
        "CAUTION will easilly OOM on large data sets")
public class GenericUDAFCollect extends AbstractGenericUDAFResolver {
    static final Log LOG = LogFactory.getLog(GenericUDAFCollect.class.getName());

    public GenericUDAFCollect() {
    }

    @Override
    public GenericUDAFEvaluator getEvaluator(TypeInfo[] parameters) throws SemanticException {
        if (parameters.length != 1) {
            throw new UDFArgumentTypeException((parameters.length-1),
                    "Exactly one argument is expeted");
        }

        if (parameters[0].getCategory() != ObjectInspector.Category.PRIMITIVE) {
            throw new UDFArgumentTypeException(0,
                    "Only Primitive type arguments are accepted but "
            + parameters[0].getTypeName() + " was passed as parameter 1.");
        }
        return new GenericUDAFMkListEvaluator();
    }
}
```

计算器实现具体的计算逻辑，需要继承GenericUDAFEvaluator抽象类。

计算器有4种模式，由枚举类GenericUDAFEvaluator.Mode定义：

```java
public static enum Mode {  
    PARTIAL1, //从原始数据到部分聚合数据的过程（map阶段），将调用iterate()和terminatePartial()方法。  
    PARTIAL2, //从部分聚合数据到部分聚合数据的过程（map端的combiner阶段），将调用merge() 和terminatePartial()方法。      
    FINAL,    //从部分聚合数据到全部聚合的过程（reduce阶段），将调用merge()和 terminate()方法。  
    COMPLETE  //从原始数据直接到全部聚合的过程（表示只有map，没有reduce，map端直接出结果），将调用merge() 和 terminate()方法。  
};  
```

计算器必须实现的方法：

1、getNewAggregationBuffer()：返回存储临时聚合结果的AggregationBuffer对象。

2、reset(AggregationBuffer agg)：重置聚合结果对象，以支持mapper和reducer的重用。

3、iterate(AggregationBuffer agg,Object[] parameters)：迭代处理原始数据parameters并保存到agg中。

4、terminatePartial(AggregationBuffer agg)：以持久化的方式返回agg表示的部分聚合结果，这里的持久化意味着返回值只能Java基础类型、数组、基础类型包装器、Hadoop的Writables、Lists和Maps。

5、merge(AggregationBuffer agg,Object partial)：合并由partial表示的部分聚合结果到agg中。

6、terminate(AggregationBuffer agg)：返回最终结果。

通常还需要覆盖初始化方法ObjectInspector init(Mode m,ObjectInspector[] parameters)，需要注意的是，在不同的模式下parameters的含义是不同的，比如m为 PARTIAL1 和 COMPLETE 时，parameters为原始数据；m为 PARTIAL2 和 FINAL 时，parameters仅为部分聚合数据（只有一个元素）。在 PARTIAL1 和 PARTIAL2 模式下，ObjectInspector  用于terminatePartial方法的返回值，在FINAL和COMPLETE模式下ObjectInspector 用于terminate方法的返回值。

```java
public class GenericUDAFMkListEvaluator extends GenericUDAFEvaluator {
    private PrimitiveObjectInspector inputOI;
    private StandardListObjectInspector loi;
    private StandardListObjectInspector internalMergeOI;

    //Hive会调用init方法来初始实例化一个UDAD的evaluator类
    @Override
    public ObjectInspector init(Mode m, ObjectInspector[] parameters) throws HiveException {
        super.init(m, parameters);
        if (m == Mode.PARTIAL1) {//map阶段
            inputOI = (PrimitiveObjectInspector) parameters[0];
            return ObjectInspectorFactory.getStandardListObjectInspector(
                    (PrimitiveObjectInspector) ObjectInspectorUtils.getStandardObjectInspector(inputOI)
            );
        } else {
            if (!(parameters[0] instanceof StandardListObjectInspector)) {
                inputOI = (PrimitiveObjectInspector) ObjectInspectorUtils
                        .getStandardObjectInspector(parameters[0]);
                return (StandardListObjectInspector) ObjectInspectorFactory
                        .getStandardListObjectInspector(inputOI);
            } else {
                internalMergeOI = (StandardListObjectInspector) parameters[0];
                inputOI = (PrimitiveObjectInspector) internalMergeOI.getListElementObjectInspector();
                loi = (StandardListObjectInspector) ObjectInspectorUtils.getStandardObjectInspector(internalMergeOI);
                return loi;
            }
        }
    }
    static class MKArrayAggregationBuffer implements AggregationBuffer {
        List<Object> container;
    }

    public void reset(AggregationBuffer agg) throws HiveException {
        ((MKArrayAggregationBuffer) agg).container = new ArrayList<Object>();
    }

    public AggregationBuffer getNewAggregationBuffer() throws HiveException {
        MKArrayAggregationBuffer ret = new MKArrayAggregationBuffer();
        reset(ret);
        return ret;
    }

    //map端
    public void iterate(AggregationBuffer agg, Object[] parameters) throws HiveException {
        /*
        （1）assert [boolean 表达式]
            如果[boolean表达式]为true，则程序继续执行。
            如果为false，则程序抛出AssertionError，并终止执行。
        （2）assert[boolean 表达式 : 错误表达式 （日志）]
            如果[boolean表达式]为true，则程序继续执行。
            如果为false，则程序抛出java.lang.AssertionError，输出[错误信息]。
         */
        assert (parameters.length == 1);
        Object p = parameters[0];

        if (p != null) {
            MKArrayAggregationBuffer myagg = (MKArrayAggregationBuffer) agg;
            putIntoList(p, myagg);
        }
    }

    private void putIntoList(Object p, MKArrayAggregationBuffer myagg) {
        Object cCopy = ObjectInspectorUtils.copyToStandardJavaObject(p, this.inputOI);
        myagg.container.add(cCopy);
    }
    //map端
    public Object terminatePartial(AggregationBuffer agg) throws HiveException {
        MKArrayAggregationBuffer myagg = (MKArrayAggregationBuffer) agg;
        ArrayList<Object> ret = new ArrayList<Object>(myagg.container.size());
        ret.addAll(myagg.container);
        return ret;
    }
    //reduce端,将terminatePartial返回的中间部分聚合结果聚合到当前聚合中
    public void merge(AggregationBuffer agg, Object partial) throws HiveException {
        MKArrayAggregationBuffer myagg = (MKArrayAggregationBuffer) agg;
        ArrayList<Object> partialResult = (ArrayList<Object>) internalMergeOI.getList(partial);
        for (Object i : partialResult) {
            putIntoList(i, myagg);
        }
    }

    public Object terminate(AggregationBuffer agg) throws HiveException {
        MKArrayAggregationBuffer myagg = (MKArrayAggregationBuffer) agg;
        ArrayList<Object> ret = new ArrayList<Object>(myagg.container.size());
        ret.addAll(myagg.container);
        return ret;

    }
}
```

HIve尝试尽量避免通过new创建对象,Hadoop和HIve依据这个规则创建尽可能少的临时对象,这样可以减轻JVM的垃圾回收过程.

使用collect函数的查询结果:

```sql
hive> select * from people;
OK
bob	sara
bob	john
bob	ted
john	sara
ted	bob
ted	sara
bob	sara
ted	bob
//去重了
hive> select name, concat_ws(",", collect_set(friend)) from people group by name;
bob	sara,john,ted
john	sara
ted	bob,sara

```

