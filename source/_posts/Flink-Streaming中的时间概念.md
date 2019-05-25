---
title: Flink笔记——Flink Streaming中的事件时间和Watermark机制
date: 2019-04-21 16:29:30
tags: [大数据, Flink]
---

#### 一、Event Time / Processing Time / Ingestion Time（事件时间、处理时间、摄入时间）

Flink streaming编程支持几种不同的时间概念：

* 处理时间： Processing time refers to the system time of the machine that is executing the respective （各自的）operation.

  When a streaming program runs on processing time, all time-based operations (like time windows) will use the system clock of the machines that run the respective operator. 

  Processing time is the simplest notion of time and requires no coordination between streams and machines. It provides the best performance and the lowest latency. However, in distributed and asynchronous environments processing **time does not provide determinism**, because it is susceptible to the speed at which records arrive in the system (for example from the message queue), to the speed at which the records flow between operators inside the system, and to outages (scheduled, or otherwise).

<!-- more--> 

* 事件时间：事件时间是每个单独事件在其生产设备上发生的时间。事件时间在他进入Flink之前就已经被存入记录中，并且可以从record中提取出来。在事件时间，时间的进展取决于数据，而不是任何系统时钟。 事件时间程序必须指定如何生成事件时间水印，这是指示事件时间进度的机制。 该水印机制在下面的后面部分中描述。

  在理想状况下，事件时间处理将产生完全一致和确定的结果，无论事件何时到达或其排序。 但是，除非事件已知按顺序到达（按时间戳），否则事件时间处理会在等待无序事件时产生一些延迟。 由于只能等待一段有限的时间，因此限制了确定性事件时间应用程序的运行方式。

  假设所有数据都已到达，事件时间操作将按预期运行，即使在处理无序或延迟事件或重新处理历史数据时也会产生正确且一致的结果。 例如，每小时事件时间窗口将包含带有落入该小时的事件时间戳的所有记录，无论它们到达的顺序如何，或者何时处理它们。 

  请注意，**有时当事件时间程序实时处理实时数据时，它们将使用一些处理时间操作**，以保证它们及时进行。

* 摄入时间：Ingestion time is the time that events enter Flink. At the source operator each record gets the source’s current time as a timestamp, and time-based operations (like time windows) refer to that timestamp.

  摄取时间在概念上位于事件时间和处理时间之间。 与处理时间相比，它代价稍高一些，但可以提供更可预测的结果。 因为摄取时间使用稳定的时间戳（在源处分配一次），所以对记录的不同窗口操作将引用相同的时间戳，而在处理时间中，每个窗口操作符可以将记录分配给不同的窗口（基于本地系统时钟和 任何运输延误）。

  与事件时间相比，摄取时间程序无法处理任何无序事件或后期数据，但程序不必指定如何生成水印。

  Internally, *ingestion time* is treated much like *event time*, but with automatic timestamp assignment and automatic watermark generation.

  ![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/times_clocks.svg)

##### 设置时间特性

The first part of a Flink DataStream program usually sets the base *time characteristic*. That setting defines how data stream sources behave (for example, whether they will assign timestamps), and what notion of time should be used by window operations like `KeyedStream.timeWindow(Time.seconds(30))`.

The following example shows a Flink program that aggregates events in hourly time windows. The behavior of the windows adapts with the time characteristic.

```java
final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

env.setStreamTimeCharacteristic(TimeCharacteristic.ProcessingTime);

// alternatively:
// env.setStreamTimeCharacteristic(TimeCharacteristic.IngestionTime);
// env.setStreamTimeCharacteristic(TimeCharacteristic.EventTime);

DataStream<MyEvent> stream = env.addSource(new FlinkKafkaConsumer09<MyEvent>(topic, schema, props));

stream
    .keyBy( (event) -> event.getUser() )
    .timeWindow(Time.hours(1))
    .reduce( (a, b) -> a.add(b) )
    .addSink(...);
```

请注意，为了以事件时间运行此示例，程序需要使用直接定义数据事件时间的源并自行发出水印，或者程序必须在源之后注入时间戳分配器和水印生成器。

#### 二、事件时间和水印

支持事件时间的流处理器需要一种方法来衡量事件时间的进度。Flink在事件时间中衡量进度的机制是**watermarks**，水印流是数据流的一部分，并且携带一个时间戳t。*Watermark(t)* 表示事件时间已经到达事件流中的时间t，意味着流中不会再有事件的时间戳 *t’ <= t*

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/stream_watermark_in_order.svg)

水印对于无序流是至关重要的，如下所示，其中事件不按时间戳排序。 通常，水印是一种声明，通过流中的那一时间点，到达某个时间戳的所有事件都应该到达。 一旦水印到达操作符，操作符就可以将其内部事件时钟提前到水印的值。

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/stream_watermark_out_of_order.svg)

Note that event time is inherited by a freshly created stream element (or elements) from either the event that produced them or from watermark that triggered creation of those elements.

##### 并行流中的水印

在源函数处或之后生成水印。 源函数的每个并行子任务通常独立地生成其水印。 这些水印定义了该特定并行源的事件时间。

在流处理程序中，水印流会推进它所到达的算子的事件时间。无论算子何时更新事件时间，都会在下游的后继算子产生一个新水印。

某些算子消费多个输入流，如 union， 或者跟在KeyBy()和partition()后的算子。这些算子的当前事件时间是它的所有输入流的事件时间中最小的值。由于输入流更新其事件时间，因此算子也是如此。

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/parallel_streams_watermarks.svg)

#### 三、Late Elements

某些特定元素可能违反水印的条件，这意味着新来的的元素的时间戳可能小于等于水印的值。实际上，在许多实际情况中，某些元素可以被任意延迟，从而无法指定某个时间点，截止这个时间点之前，拥有特定时间时间戳的所有元素都以发生。此外，即使延迟有下限，通常也不希望水印延迟太久，因为它在事件时间窗口的评估中引起太多延迟。

出于这个原因，流程序可能明确地指明一些迟到的元素。 Late Elements是指一些元素，而系统的事件时钟已经pass了这些元素的时间戳。

#### 四、空闲数据源

目前，对于纯事件时间水印生成器，如果没有要处理的元素，则水印不能进展。 这意味着在输入数据存在间隙的情况下，事件时间将不会进展，例如窗口操作符将不会被触发，因此现有窗口将不能产生任何输出数据。

为了避免这种情况，可以使用定期水印分配器，它们不仅基于元素时间戳进行分配。 示例解决方案可以是在不观察新事件一段时间之后切换到使用当前处理时间作为时间基础的分配器。

