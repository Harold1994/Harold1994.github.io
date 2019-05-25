---
title: Flink笔记——Window
date: 2019-04-25 16:30:21
tags: [大数据, Flink]
---

#### 一、窗口概述

窗口是处理无限流的核心，窗口将流划分成有限大小的"桶"，可以在其上进行计算。窗口分为键控和非键控的。

**Keyed Windows**

```
stream
       .keyBy(...)               <-  keyed versus non-keyed windows
       .window(...)              <-  required: "assigner"
      [.trigger(...)]            <-  optional: "trigger" (else default trigger)
      [.evictor(...)]            <-  optional: "evictor" (else no evictor)
      [.allowedLateness(...)]    <-  optional: "lateness" (else zero)
      [.sideOutputLateData(...)] <-  optional: "output tag" (else no side output for late data)
       .reduce/aggregate/fold/apply()      <-  required: "function"
      [.getSideOutput(...)]      <-  optional: "output tag"
```

**Non-Keyed Windows**

```
stream
       .windowAll(...)           <-  required: "assigner"
      [.trigger(...)]            <-  optional: "trigger" (else default trigger)
      [.evictor(...)]            <-  optional: "evictor" (else no evictor)
      [.allowedLateness(...)]    <-  optional: "lateness" (else zero)
      [.sideOutputLateData(...)] <-  optional: "output tag" (else no side output for late data)
       .reduce/aggregate/fold/apply()      <-  required: "function"
      [.getSideOutput(...)]      <-  optional: "output tag"
```

#### 二、窗口生命周期

In a nutshell, a window is **created** as soon as the first element that should belong to this window arrives, and the window is **completely removed** when the time (event or processing time) passes its end timestamp plus the user-specified `allowed lateness` (see [Allowed Lateness](https://ci.apache.org/projects/flink/flink-docs-release-1.8/dev/stream/operators/windows.html#allowed-lateness)). Flink保证只删除基于时间的窗口，而不会删除类似全局窗口的其他窗口。

另外，每个窗口都有一个触发器Trigger和一个函数function (`ProcessWindowFunction`, `ReduceFunction`,`AggregateFunction` or `FoldFunction`)，这个函数对窗口内的数据进行计算。Trigger指明了函数可以开始计算的条件，A triggering policy might be something like “when the number of elements in the window is more than 4”, or “when the watermark passes the end of the window”。

#### 三、键控和非键控的窗口

在定义窗口之前，使用Keyby()将会将无限的流分割为逻辑上按键分隔的流。不使用Keyby()会产生一个非键控的流。键控的流允许窗口操作在多个task中并行的计算，因为每个逻辑上的键控流可以被独立的处理。同一个键下的所有元素与将被发送到相同的并行任务。

至于非键控流，并行度为1。

#### 四、窗口分配器

 The window assigner defines how elements are assigned to windows. This is done by specifying the `WindowAssigner` of your choice in the `window(...)` (for *keyed*streams) or the `windowAll()` (for *non-keyed* streams) call.

A `WindowAssigner` is responsible for assigning each incoming element to one or more windows.Flink预定义了几种最常用的窗口： Tumbling Windows、 *sliding windows*, *session windows* and *global windows*。也可以通过继承WindowAssigner类实现自定义窗口。All built-in window assigners (except the global windows) assign elements to windows based on time, which can either be processing time or event time. 

基于时间的窗口有一个左闭右开的时间戳区间来表述窗口大小。

##### 1. Tumbling Windows

按照固定的窗口大小分配元素。 Tumbling windows have a fixed size and do not overlap不重叠.

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/tumbling-windows.svg)

```java
DataStream<T> input = ...;

// tumbling event-time windows
input
    .keyBy(<key selector>)
    .window(TumblingEventTimeWindows.of(Time.seconds(5)))
    .<windowed transformation>(<window function>);

// tumbling processing-time windows
input
    .keyBy(<key selector>)
    .window(TumblingProcessingTimeWindows.of(Time.seconds(5)))
    .<windowed transformation>(<window function>);

// daily tumbling event-time windows offset by -8 hours.
input
    .keyBy(<key selector>)
    .window(TumblingEventTimeWindows.of(Time.days(1), Time.hours(-8)))
    .<windowed transformation>(<window function>);
```

tumbling window也可以指定一个偏移量offset参数，这样每个窗口不会按照时间单位的整数起始点开始， for example, get `1:15:00.000 - 2:14:59.999`, `2:15:00.000 - 3:14:59.999` etc

##### 2. Sliding Windows

滑动窗口分配器将元素分配给具有固定长度的窗口。它的第一个参数指定了窗口时间大小，另一个参数slide控制滑动窗口开始的频率（类似于Spark Streaming中的两个参数）。因此当slide参数小于窗口大小时滑动窗口是可以重叠的，即一个元素可能分配给多个窗口。

For example, you could have windows of size 10 minutes that slides by 5 minutes.

滑动窗口也可以指定一个偏移量。

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/sliding-windows.svg)

```java
DataStream<T> input = ...;

// sliding event-time windows
input
    .keyBy(<key selector>)
    .window(SlidingEventTimeWindows.of(Time.seconds(10), Time.seconds(5)))
    .<windowed transformation>(<window function>);

// sliding processing-time windows
input
    .keyBy(<key selector>)
    .window(SlidingProcessingTimeWindows.of(Time.seconds(10), Time.seconds(5)))
    .<windowed transformation>(<window function>);

// sliding processing-time windows offset by -8 hours
input
    .keyBy(<key selector>)
    .window(SlidingProcessingTimeWindows.of(Time.hours(12), Time.hours(1), Time.hours(-8)))
    .<windowed transformation>(<window function>);
```

##### 3. Session Windows

会话窗口通过活动的会话将元素聚集起来，相较前面两个窗口，它并不会重叠也没有一个固定的开端和结尾。当窗口一段时间接收不到数据时它就会关闭。A session window assigner can be configured with either a static *session gap* or with a *session gap extractor* function which defines how long the period of inactivity is.  When this period expires, the current session closes and subsequent elements are assigned to a new session window.

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/session-windows.svg)

```java
DataStream<T> input = ...;

// event-time session windows with static gap
input
    .keyBy(<key selector>)
    .window(EventTimeSessionWindows.withGap(Time.minutes(10)))
    .<windowed transformation>(<window function>);
    
// event-time session windows with dynamic gap
input
    .keyBy(<key selector>)
    .window(EventTimeSessionWindows.withDynamicGap((element) -> {
        // determine and return session gap
    }))
    .<windowed transformation>(<window function>);

// processing-time session windows with static gap
input
    .keyBy(<key selector>)
    .window(ProcessingTimeSessionWindows.withGap(Time.minutes(10)))
    .<windowed transformation>(<window function>);
    
// processing-time session windows with dynamic gap
input
    .keyBy(<key selector>)
    .window(ProcessingTimeSessionWindows.withDynamicGap((element) -> {
        // determine and return session gap
    }))
    .<windowed transformation>(<window function>);
```

> 在会话窗口内部，算子为每一个到来的记录创建一个窗口，然后将窗口合并在一起，如果他们之间的间隔比设置的gap小。

##### 4. Global Windows

全局窗口将所有包含同一个key的元素分配到一个全局的窗口。这个窗口必须配合一个trigger一起使用，否则不会进行任何计算，因为全局窗口没有一个自然的终结点来让我们进行聚合计算。

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/non-windowed.svg)

```java
DataStream<T> input = ...;

input
    .keyBy(<key selector>)
    .window(GlobalWindows.create())
    .<windowed transformation>(<window function>);
```

#### 五、窗口函数

窗口函数负责当窗口准备好后在每个窗口中执行计算。The window function can be one of `ReduceFunction`, `AggregateFunction`, `FoldFunction` or `ProcessWindowFunction`.The first two can be executed more efficiently (see [State Size](https://ci.apache.org/projects/flink/flink-docs-release-1.8/dev/stream/operators/windows.html#state size) section) because Flink can incrementally aggregate the elements for each window as they arrive. 其中 ProcessWindowFunction获得一个窗口中所有元素的迭代器和元素所属窗口的元信息。而且ProcessWindowFunction的效率没有其他几个窗口函数的执行效率高，因为Flink只有将所有元素都缓存后才能进行计算。可以通过结合ProcessWindowFunction`with a `ReduceFunction`, `AggregateFunction`, or `FoldFunction，既能增量聚集窗口元素，又能获取额外的窗口元数据。

##### ReduceFunction

A `ReduceFunction` specifies how two elements from the input are combined to produce an output element of the same type. Flink uses a `ReduceFunction` to incrementally aggregate the elements of a window.

```java
DataStream<Tuple2<String, Long>> input = ...;

input
    .keyBy(<key selector>)
    .window(<window assigner>)
    .reduce(new ReduceFunction<Tuple2<String, Long>> {
      public Tuple2<String, Long> reduce(Tuple2<String, Long> v1, Tuple2<String, Long> v2) {
        return new Tuple2<>(v1.f0, v1.f1 + v2.f1);
      }
    });
```

##### AggregateFunction

AggregateFunction是ReduceFunction的泛化版本，它拥有三个类型：输入类型IN，累加器类型ACC和输出类型OUT。输入类型是输入流中元素的类型，AggregateFunction具有将一个输入元素添加到累加器的方法。 该接口还具有用于创建初始累加器的方法，用于将两个累加器合并到一个累加器中以及用于从累加器提取输出（类型OUT）的方法。

```java
public class AverageAggregate implements AggregateFunction<Tuple2<String, Long>, Tuple2<Long, Long>, Double> {

    @Override
    public Tuple2<Long, Long> createAccumulator() {
        return new Tuple2<>(0l, 0l);
    }

    @Override
    public Tuple2<Long, Long> add(Tuple2<String, Long> value, Tuple2<Long, Long> accumulator) {
        return new Tuple2<>(accumulator.f0 + value.f1, accumulator.f1 + 1);
    }

    @Override
    public Double getResult(Tuple2<Long, Long> accumulator) {
        return ((double) accumulator.f0 / accumulator.f1);
    }

    @Override
    public Tuple2<Long, Long> merge(Tuple2<Long, Long> longLongTuple2, Tuple2<Long, Long> acc1) {
        return new Tuple2<>(longLongTuple2.f0 + acc1.f0, longLongTuple2.f1 + acc1.f1);
    }
}
```

##### FoldFunction

A `FoldFunction` specifies how an input element of the window is combined with an element of the output type. 对于添加到窗口的每个元素和当前输出值，将逐步调用FoldFunction。 第一个元素与输出类型的预定义初始值组合。

```java
input
    .keyBy(<key selector>)
    .window(<window assigner>)
    .fold("", new FoldFunction<Tuple2<String, Long>, String>> {
       public String fold(String acc, Tuple2<String, Long> value) {
         return acc + value.f1;
       }
    });
```

> `fold()` cannot be used with session windows or other mergeable windows.

##### ProcessWindowFunction

ProcessWindowFunction获得一个窗口中全部元素的迭代器和一个可以访问时间和状态信息的Context对象，这使得ProcessWindowFunction更加灵活。灵活性的代价是性能降低和资源消耗， because elements cannot be incrementally aggregated but instead need to be buffered internally until the window is considered ready for processing.

```java
DataStream<Tuple2<String, Long>> input = ...;

input
  .keyBy(t -> t.f0)
  .timeWindow(Time.minutes(5))
  .process(new MyProcessWindowFunction());

/* ... */

public class MyProcessWindowFunction 
    extends ProcessWindowFunction<Tuple2<String, Long>, String, String, TimeWindow> {

  @Override
  public void process(String key, Context context, Iterable<Tuple2<String, Long>> input, Collector<String> out) {
    long count = 0;
    for (Tuple2<String, Long> in: input) {
      count++;
    }
    out.collect("Window: " + context.window() + "count: " + count);
  }
}
```

> Note that using `ProcessWindowFunction` for simple aggregates such as count is quite inefficient. The next section shows how a `ReduceFunction` or `AggregateFunction` can be combined with a `ProcessWindowFunction` to get both incremental aggregation and the added information of a `ProcessWindowFunction`.

##### 具有增量聚合功能的ProcessWindowFunction

A `ProcessWindowFunction` can be combined with either a `ReduceFunction`, an `AggregateFunction`, or a `FoldFunction` to incrementally aggregate elements as they arrive in the window.当窗口关闭时，将为ProcessWindowFunction提供聚合结果。 这允许它在访问ProcessWindowFunction的附加窗口元信息的同时递增地计算窗口。

###### Incremental Window Aggregation with ReduceFunction

```java
DataStream<SensorReading> input = ...;

input
  .keyBy(<key selector>)
  .timeWindow(<duration>)
  .reduce(new MyReduceFunction(), new MyProcessWindowFunction());

// Function definitions

private static class MyReduceFunction implements ReduceFunction<SensorReading> {

  public SensorReading reduce(SensorReading r1, SensorReading r2) {
      return r1.value() > r2.value() ? r2 : r1;
  }
}

private static class MyProcessWindowFunction
    extends ProcessWindowFunction<SensorReading, Tuple2<Long, SensorReading>, String, TimeWindow> {

  public void process(String key,
                    Context context,
                    Iterable<SensorReading> minReadings,
                    Collector<Tuple2<Long, SensorReading>> out) {
      SensorReading min = minReadings.iterator().next();
      out.collect(new Tuple2<Long, SensorReading>(context.window().getStart(), min));
  }
}
```

###### Incremental Window Aggregation with AggregateFunction

```java
DataStream<Tuple2<String, Long>> input = ...;

input
  .keyBy(<key selector>)
  .timeWindow(<duration>)
  .aggregate(new AverageAggregate(), new MyProcessWindowFunction());

// Function definitions

/**
 * The accumulator is used to keep a running sum and a count. The {@code getResult} method
 * computes the average.
 */
private static class AverageAggregate
    implements AggregateFunction<Tuple2<String, Long>, Tuple2<Long, Long>, Double> {
  @Override
  public Tuple2<Long, Long> createAccumulator() {
    return new Tuple2<>(0L, 0L);
  }

  @Override
  public Tuple2<Long, Long> add(Tuple2<String, Long> value, Tuple2<Long, Long> accumulator) {
    return new Tuple2<>(accumulator.f0 + value.f1, accumulator.f1 + 1L);
  }

  @Override
  public Double getResult(Tuple2<Long, Long> accumulator) {
    return ((double) accumulator.f0) / accumulator.f1;
  }

  @Override
  public Tuple2<Long, Long> merge(Tuple2<Long, Long> a, Tuple2<Long, Long> b) {
    return new Tuple2<>(a.f0 + b.f0, a.f1 + b.f1);
  }
}

private static class MyProcessWindowFunction
    extends ProcessWindowFunction<Double, Tuple2<String, Double>, String, TimeWindow> {

  public void process(String key,
                    Context context,
                    Iterable<Double> averages,
                    Collector<Tuple2<String, Double>> out) {
      Double average = averages.iterator().next();
      out.collect(new Tuple2<>(key, average));
  }
}
```

##### 在ProcessWindowFunction中使用窗口状态

除了可以访问键控状态，ProcessWindowFunction也可以使用当前处理的窗口独有的状态—— *per-window*state

要理解这个概念需要了解两种窗口状态：

* 当指定window操作符时定义的窗口（概念上的）：This might be *tumbling windows of 1 hour* or *sliding windows of 2 hours that slide by 1 hour*.
* 对于指定key的真正的window实例（实际的）：This might be *time window from 12:00 to 13:00 for user-id xyz*. This is based on the window definition and there will be many windows based on the number of keys that the job is currently processing and based on what time slots the events fall into.

per-window state指的是上面两者之间的后者， Meaning that if we process events for 1000 different keys and events for all of them currently fall into the *[12:00, 13:00)* time window then there will be 1000 window instances that each have their own keyed per-window state.

process()方法中的Context对象上有两种方法可以访问这两种状态：

- `globalState()`, which allows access to keyed state that is not scoped to a window
- `windowState()`, which allows access to keyed state that is also scoped to the window

#### 六、触发器

A `Trigger` determines when a window (as formed by the *window assigner*) is ready to be processed by the *window function*. 每个WindowAssigner都有一个默认的触发器，也可以使用trigger(...)方法自定义触发器。

The trigger interface has five methods that allow a `Trigger` to react to different events:

- The `onElement()` method is called for each element that is added to a window.
- The `onEventTime()` method is called when a registered event-time timer fires.
- The `onProcessingTime()` method is called when a registered processing-time timer fires.
- The `onMerge()` method is relevant for stateful triggers and merges the states of two triggers when their corresponding windows merge, *e.g.* when using session windows.
- Finally the `clear()` method performs any action needed upon removal of the corresponding window.

上面方法中的前三个通过返回一个TriggerResult来决定当它们的调用时间发生时该做什么操作，可能的操作包括：

- `CONTINUE`: do nothing,
- `FIRE`: trigger the computation,
- `PURGE`: clear the elements in the window, and
- `FIRE_AND_PURGE`: trigger the computation and clear the elements in the window afterwards.

##### Fire and Purge

一旦Trigger认为窗口可以开始处理数据，他就会返回FIRE或FIRE_AND_PURGE。这是窗口操作符返回当前窗口计算结果的信号。Given a window with a `ProcessWindowFunction` all elements are passed to the `ProcessWindowFunction` (possibly after passing them to an evictor). Windows with `ReduceFunction`, `AggregateFunction`, or `FoldFunction` simply emit their eagerly aggregated result. FIRE保留窗口内容，而FIRE_AND_PURGE会删除其内容。 默认情况下，预定义的触发器只需FIRE而不会清除窗口状态。

> The default trigger of the `GlobalWindow` is the `NeverTrigger` which does never fire. Consequently, you always have to define a custom trigger when using a `GlobalWindow`.

> By specifying a trigger using `trigger()` you are overwriting the default trigger of a `WindowAssigner`.

##### 内置的和常用的Trigger

* EventTimeTrigger根据水印测量的事件时间进度触发。
* ProcessingTimeTrigger基于处理时间触发
* CountTrigger当窗口中时间数量超过设定的值时触发
* PurgingTrigger将另一个触发器作为参数，并将其转换为清除触发器。

#### 七、Evictors

Flink的窗口模型除了可以指定WindowAssigner和触发器外，还可以特别指定一个Evictor（逐出器），使用evictor(…)方法。evictor可以在窗口被触发且函数执行前或者后面移除元素，它有两个方法：

```java
[1] void evictBefore(Iterable<TimestampedValue<T>> elements, int size, W window, EvictorContext evictorContext);
[2] void evictAfter(Iterable<TimestampedValue<T>> elements, int size, W window, EvictorContext evictorContext);
```

The `evictBefore()` contains the eviction logic to be applied before the window function, while the `evictAfter()` contains the one to be applied after the window function. Elements evicted before the application of the window function will not be processed by it.

Flink有三种预定义的逐出器：

* CountEvictor:从窗口保持用户指定数量的元素，并从窗口缓冲区的开头丢弃剩余的元素。
* DeltaEvictor:用DeltaFunction和阈值，计算窗口缓冲区中最后一个元素与其余每个元素之间的差值，并删除delta大于或等于阈值的值。
* TimeEvictor：以一个以毫秒为单位的interval作为参数，在一个窗口的所有元素中，找到最大的时间戳作为max_ts，然后移除所有时间戳小于max_ts - interval的元素。

> 默认情况下，所有预定义的逐出器都在窗口函数之前执行它们的逻辑

<u>**Specifying an evictor prevents any pre-aggregation, as all the elements of a window have to be passed to the evictor before applying the computation.**</u>

另外需要注意的是Flink不保证一个窗口中的元素的顺序，这意味着尽管一个逐出器可能从窗口的开始移除元素，但他们并不一定是第一个或最后一个到达的

