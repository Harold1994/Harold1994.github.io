---
title: Flink笔记——Flink中的JOIN连接
date: 2019-05-25 15:17:18
tags: [大数据, Flink]
---

#### 一、窗口连接

窗口连接连接位于同一个窗口中的具有相同key值的两个流。可以使用窗口分配器定义这些窗口，并对来自两个流的元素进行评估。

来自双方的元素被传递给一个用户自定义的JoinFunction或者FlatJoinFunction，这两个函数可以发射出符合join规范的结果值。

<!-- more--> 

```java
stream.join(otherStream)
    .where(<KeySelector>)
    .equalTo(<KeySelector>)
    .window(<WindowAssigner>)
    .apply(<JoinFunction>)
```

需要注意的是：

* 两个流中的join类似于inner-join，意味着只有两个流中都有彼此对应的元素才会被join
* 那些被join的元素将的时间戳中是他们所位于的相应窗口中的最大时间戳。 例如，以[5,10）作为其边界的窗口将导致连接的元素具有9作为其时间戳。

##### 1.Tumbling Window join

When performing a tumbling window join, all elements with a common key and a common tumbling window are joined as pairwise combinations and passed on to a `JoinFunction` or `FlatJoinFunction`. Because this behaves like an inner join, elements of one stream that do not have elements from another stream in their tumbling window are not emitted!

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/tumbling-window-join.svg)

As illustrated in the figure, we define a tumbling window with the size of 2 milliseconds, which results in windows of the form `[0,1], [2,3], ...`. The image shows the pairwise combinations of all elements in each window which will be passed on to the `JoinFunction`. Note that in the tumbling window `[6,7]` nothing is emitted because no elements exist in the green stream to be joined with the orange elements ⑥ and ⑦.

```java
import org.apache.flink.api.java.functions.KeySelector;
import org.apache.flink.streaming.api.windowing.assigners.TumblingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
 
...

DataStream<Integer> orangeStream = ...
DataStream<Integer> greenStream = ...

orangeStream.join(greenStream)
    .where(<KeySelector>)
    .equalTo(<KeySelector>)
    .window(TumblingEventTimeWindows.of(Time.milliseconds(2)))
    .apply (new JoinFunction<Integer, Integer, String> (){
        @Override
        public String join(Integer first, Integer second) {
            return first + "," + second;
        }
    });
```

##### 2.滑动窗口连接

When performing a sliding window join, all elements with a common key and common sliding window are joined as pairwise combinations and passed on to the `JoinFunction` or `FlatJoinFunction`. Elements of one stream that do not have elements from the other stream in the current sliding window are not emitted! Note that some elements might be joined in one sliding window but not in another!

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/sliding-window-join.svg)

In this example we are using sliding windows with a size of two milliseconds and slide them by one millisecond, resulting in the sliding windows `[-1, 0],[0,1],[1,2],[2,3], …`. The joined elements below the x-axis are the ones that are passed to the `JoinFunction`for each sliding window. Here you can also see how for example the orange ② is joined with the green ③ in the window `[2,3]`, but is not joined with anything in the window `[1,2]`.

```java
import org.apache.flink.api.java.functions.KeySelector;
import org.apache.flink.streaming.api.windowing.assigners.SlidingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;

...

DataStream<Integer> orangeStream = ...
DataStream<Integer> greenStream = ...

orangeStream.join(greenStream)
    .where(<KeySelector>)
    .equalTo(<KeySelector>)
    .window(SlidingEventTimeWindows.of(Time.milliseconds(2) /* size */, Time.milliseconds(1) /* slide */))
    .apply (new JoinFunction<Integer, Integer, String> (){
        @Override
        public String join(Integer first, Integer second) {
            return first + "," + second;
        }
    });
```

##### 3.会话窗口连接

When performing a session window join, all elements with the same key that when *“combined”* fulfill the session criteria are joined in pairwise combinations and passed on to the `JoinFunction` or `FlatJoinFunction`. Again this performs an inner join, so if there is a session window that only contains elements from one stream, no output will be emitted!

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/session-window-join.svg)

```java
import org.apache.flink.api.java.functions.KeySelector;
import org.apache.flink.streaming.api.windowing.assigners.EventTimeSessionWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
 
...

DataStream<Integer> orangeStream = ...
DataStream<Integer> greenStream = ...

orangeStream.join(greenStream)
    .where(<KeySelector>)
    .equalTo(<KeySelector>)
    .window(EventTimeSessionWindows.withGap(Time.milliseconds(1)))
    .apply (new JoinFunction<Integer, Integer, String> (){
        @Override
        public String join(Integer first, Integer second) {
            return first + "," + second;
        }
    });
```

##### 4.间隔连接

interval join 连接具有相同key值的两个流（A和B）,要求B流中的值的时间戳在A的元素的时间戳前后相对时间间隔内。用公式表达为：`b.timestamp ∈ [a.timestamp + lowerBound; a.timestamp + upperBound]` 或者`a.timestamp + lowerBound <= b.timestamp <= a.timestamp + upperBound`

时间上界和下界都可以为正值或负值，只要下界永远比上界小即可，interval join 目前只执行inner join。

当一对元素被传递给ProcessJoinFunction，它们将会被分配两者之间较大的时间戳，时间戳可以通过ProcessJoinFunction.Context来访问。

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/interval-join.svg)

In the example above, we join two streams ‘orange’ and ‘green’ with a lower bound of -2 milliseconds and an upper bound of +1 millisecond. Be default, these boundaries are inclusive(集合是全闭的), but `.lowerBoundExclusive()` and `.upperBoundExclusive` can be applied to change the behaviour.

```java
import org.apache.flink.api.java.functions.KeySelector;
import org.apache.flink.streaming.api.functions.co.ProcessJoinFunction;
import org.apache.flink.streaming.api.windowing.time.Time;

...

DataStream<Integer> orangeStream = ...
DataStream<Integer> greenStream = ...

orangeStream
    .keyBy(<KeySelector>)
    .intervalJoin(greenStream.keyBy(<KeySelector>))
    .between(Time.milliseconds(-2), Time.milliseconds(1))
    .process (new ProcessJoinFunction<Integer, Integer, String(){

        @Override
        public void processElement(Integer left, Integer right, Context ctx, Collector<String> out) {
            out.collect(first + "," + second);
        }
    });
```

