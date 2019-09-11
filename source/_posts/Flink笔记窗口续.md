---
title: Flink笔记——Window（续）
date: 2019-05-25 11:21:33
tags: [大数据, Flink]
---

#### 六、触发器

A `Trigger` determines when a window (as formed by the *window assigner*) is ready to be processed by the *window function*. 每个WindowAssigner都有一个默认的触发器，也可以使用trigger(...)方法自定义触发器。

<!-- more--> 

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

- EventTimeTrigger根据水印测量的事件时间进度触发。
- ProcessingTimeTrigger基于处理时间触发
- CountTrigger当窗口中时间数量超过设定的值时触发
- PurgingTrigger将另一个触发器作为参数，并将其转换为清除触发器。

#### 七、Evictors

Flink的窗口模型除了可以指定WindowAssigner和触发器外，还可以特别指定一个Evictor（逐出器），使用evictor(…)方法。evictor可以在窗口被触发且函数执行前或者后面移除元素，它有两个方法：

```java
[1] void evictBefore(Iterable<TimestampedValue<T>> elements, int size, W window, EvictorContext evictorContext);
[2] void evictAfter(Iterable<TimestampedValue<T>> elements, int size, W window, EvictorContext evictorContext);
```

The `evictBefore()` contains the eviction logic to be applied before the window function, while the `evictAfter()` contains the one to be applied after the window function. Elements evicted before the application of the window function will not be processed by it.

Flink有三种预定义的逐出器：

- CountEvictor:从窗口保持用户指定数量的元素，并从窗口缓冲区的开头丢弃剩余的元素。
- DeltaEvictor:用DeltaFunction和阈值，计算窗口缓冲区中最后一个元素与其余每个元素之间的差值，并删除delta大于或等于阈值的值。
- TimeEvictor：以一个以毫秒为单位的interval作为参数，在一个窗口的所有元素中，找到最大的时间戳作为max_ts，然后移除所有时间戳小于max_ts - interval的元素。

> 默认情况下，所有预定义的逐出器都在窗口函数之前执行它们的逻辑

<u>**Specifying an evictor prevents any pre-aggregation, as all the elements of a window have to be passed to the evictor before applying the computation.**</u>

另外需要注意的是Flink不保证一个窗口中的元素的顺序，这意味着尽管一个逐出器可能从窗口的开始移除元素，但他们并不一定是第一个或最后一个到达的

#### 八、延迟

当处理事件时间窗口时，可能会发生元素迟到的情况，即Flink用于跟踪事件时间进度的水印已经超过元素所属的窗口的结束时间戳。

By default, late elements are **dropped** when the watermark is past the end of the window. However, Flink allows to specify a maximum *allowed lateness* for window operators. Allowed lateness specifies by how much time elements can be late before they are dropped, and its default value is 0. Elements that arrive after the watermark has passed the end of the window but before it passes the end of the window plus the allowed lateness, are still added to the window. Depending on the trigger used, 一个迟到但是并未被dropped掉的元素可能导致窗口重新计算. This is the case for the `EventTimeTrigger`.

```java
DataStream<T> input = ...;

input
    .keyBy(<key selector>)
    .window(<window assigner>)
    .allowedLateness(<time>)
    .<windowed transformation>(<window function>);
```

##### 使用迟到的元素作为额外的输出side output

Using Flink’s [side output](https://ci.apache.org/projects/flink/flink-docs-release-1.8/dev/stream/side_output.html) feature you can get a stream of the data that was discarded as late.

You first need to specify that you want to get late data using `sideOutputLateData(OutputTag)` on the windowed stream. Then, you can get the side-output stream on the result of the windowed operation:

```java
final OutputTag<T> lateOutputTag = new OutputTag<T>("late-data"){};

DataStream<T> input = ...;

SingleOutputStreamOperator<T> result = input
    .keyBy(<key selector>)
    .window(<window assigner>)
    .allowedLateness(<time>)
    .sideOutputLateData(lateOutputTag)
    .<windowed transformation>(<window function>);

DataStream<T> lateStream = result.getSideOutput(lateOutputTag);
```

##### Late elements considerations

When specifying an allowed lateness greater than 0, the window along with its content is kept after the watermark passes the end of the window. In these cases, when a late but not dropped element arrives, it could trigger another firing for the window. These firings are called `late firings`, as they are triggered by late events and in contrast to the `main firing` which is the first firing of the window. In case of session windows, late firings can further lead to merging of windows, as they may “bridge” the gap between two pre-existing, unmerged windows.

**Attention** You should be aware that the elements emitted by a late firing should be treated as updated results of a previous computation, i.e., your data stream will contain multiple results for the same computation. Depending on your application, you need to take these duplicated results into account or deduplicate them.

#### 九、窗口结果

窗口操作的结果同样是DataStream，关于窗口操作的信息不会保留在结果元素中，因此如果要保留有关窗口的元信息，则必须在ProcessWindowFunction的结果元素中手动编码该信息。结果元素上仅有的相关信息是元素时间戳。在处理时间窗口中，它被设置为被允许的最大时间，即 *end timestamp - 1*，因为窗口的end timestamp 是独有的。对于事件时间窗口来说，时间戳和水印与窗口的交互方式联合起来使得能够以相同的窗口大小进行连续的窗口操作。

##### 水印和窗口的交互

When watermarks arrive at the window operator this triggers two things:

- 水印触发所有最大时间戳小于新水印的窗口的计算
- 水印被转发（按原样）到下游操作

##### 连续的窗口操作

As mentioned before, the way the timestamp of windowed results is computed and how watermarks interact with windows allows stringing together consecutive windowed operations. This can be useful when you want to do two consecutive windowed operations where you want to use different keys but still want elements from the same upstream window to end up in the same downstream window. Consider this example:

```java
DataStream<Integer> input = ...;

DataStream<Integer> resultsPerKey = input
    .keyBy(<key selector>)
    .window(TumblingEventTimeWindows.of(Time.seconds(5)))
    .reduce(new Summer());

DataStream<Integer> globalResults = resultsPerKey
    .windowAll(TumblingEventTimeWindows.of(Time.seconds(5)))
    .process(new TopKWindowFunction());
```

在该示例中，来自第一操作的时间窗口[0,5]的结果也将在随后的窗口化操作中的时间窗口[0,5]中结束。 这允许计算每个键的和，然后在第二个操作中计算同一窗口内的前k个元素。

