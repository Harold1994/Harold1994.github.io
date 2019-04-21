---
title: fink官网学习笔记——Java Lambda表达式
date: 2019-04-20 17:28:12
tags: 大数据
---

Flink支持对Java API的所有运算符使用lambda表达式，但是，每当lambda表达式使用Java泛型时，需要显式声明类型信息。

Flink can automatically extract the result type information from the implementation of the method signature `OUT map(IN value)`because `OUT` is not generic but `Integer`.

<!-- more-->

Unfortunately, functions such as `flatMap()` with a signature `void flatMap(IN value, Collector<OUT> out)` are compiled into `void flatMap(IN value, Collector out)` by the Java compiler. This makes it impossible for Flink to infer the type information for the output type automatically.

Flink will most likely throw an exception similar to the following:

```java
org.apache.flink.api.common.functions.InvalidTypesException: The generic type parameters of 'Collector' are missing.
    In many cases lambda methods don't provide enough information for automatic type extraction when Java generics are involved.
    An easy workaround is to use an (anonymous) class instead that implements the 'org.apache.flink.api.common.functions.FlatMapFunction' interface.
    Otherwise the type has to be specified explicitly using type information.
```

这时就需要显式的指明类型信息，否则输出被当作Object对象处理，这会导致无效的序列化

```java
import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.api.java.DataSet;
import org.apache.flink.util.Collector;

DataSet<Integer> input = env.fromElements(1, 2, 3);

// collector type must be declared
input.flatMap((Integer number, Collector<String> out) -> {
    StringBuilder builder = new StringBuilder();
    for(int i = 0; i < number; i++) {
        builder.append("a");
        out.collect(builder.toString());
    }
})
// provide type information explicitly
.returns(Types.STRING)
// prints "a", "a", "aa", "a", "aa", "aaa"
.print();
```

使用带有范型返回值的map()函数也会导致同样的问题，A method signature `Tuple2<Integer, Integer> map(Integer value)` is erasured to `Tuple2 map(Integer value)` in the example below.

```java
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.java.tuple.Tuple2;

env.fromElements(1, 2, 3)
    .map(i -> Tuple2.of(i, i))    // no information about fields of Tuple2
    .print();
```

有多种方法解决这个问题：

```java
import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.api.java.tuple.Tuple2;

// 1.使用显式的".returns(...)"指定
env.fromElements(1, 2, 3)
    .map(i -> Tuple2.of(i, i))
    .returns(Types.TUPLE(Types.INT, Types.INT))
    .print();

// 使用一个Map类
env.fromElements(1, 2, 3)
    .map(new MyTuple2Mapper())
    .print();

public static class MyTuple2Mapper extends MapFunction<Integer, Tuple2<Integer, Integer>> {
    @Override
    public Tuple2<Integer, Integer> map(Integer i) {
        return Tuple2.of(i, i);
    }
}

// 使用匿名内部类
env.fromElements(1, 2, 3)
    .map(new MapFunction<Integer, Tuple2<Integer, Integer>> {
        @Override
        public Tuple2<Integer, Integer> map(Integer i) {
            return Tuple2.of(i, i);
        }
    })
    .print();

// 使用Tuple的子类
env.fromElements(1, 2, 3)
    .map(i -> new DoubleTuple(i, i))
    .print();

public static class DoubleTuple extends Tuple2<Integer, Integer> {
    public DoubleTuple(int f0, int f1) {
        this.f0 = f0;
        this.f1 = f1;
    }
}
```