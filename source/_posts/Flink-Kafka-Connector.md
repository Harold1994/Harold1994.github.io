---
title: Flink笔记——Kafka Connector
date: 2019-05-26 13:29:22
tags: [大数据, Flink]
---

#### 一、Kafka Connector

Flink provides special Kafka Connectors for reading and writing data from/to Kafka topics. The Flink Kafka Consumer integrates with Flink’s checkpointing mechanism to provide exactly-once processing semantics. To achieve that, Flink does not purely rely on Kafka’s consumer group offset tracking, **but tracks and checkpoints these offsets internally as well**.

<!-- more-->

```java
Properties properties = new Properties();
properties.setProperty("bootstrap.servers", "localhost:9092");
// only required for Kafka 0.8
properties.setProperty("zookeeper.connect", "localhost:2181");
properties.setProperty("group.id", "test");
DataStream<String> stream = env
	.addSource(new FlinkKafkaConsumer08<>("topic", new SimpleStringSchema(), properties));
```

##### 1.反序列化模式

For convenience, Flink provides the following schemas:

- `TypeInformationSerializationSchema` (and `TypeInformationKeyValueSerializationSchema`) which creates a schema based on a Flink’s `TypeInformation`. This is useful if the data is both written and read by Flink. This schema is a performant Flink-specific alternative to other generic serialization approaches.

- `JsonDeserializationSchema` (and `JSONKeyValueDeserializationSchema`) which turns the serialized JSON into an ObjectNode object, from which fields can be accessed using `objectNode.get("field").as(Int/String/...)()`. The KeyValue objectNode contains a “key” and “value” field which contain all fields, as well as an optional “metadata” field that exposes the offset/partition/topic for this message.
- `AvroDeserializationSchema` which reads data serialized with Avro format using a statically provided schema. It can infer the schema from Avro generated classes (`AvroDeserializationSchema.forSpecific(...)`) or it can work with `GenericRecords`with a manually provided schema (with `AvroDeserializationSchema.forGeneric(...)`). This deserialization schema expects that the serialized records DO NOT contain embedded schema.

当遇到因任何原因无法反序列化的损坏消息时，有两个选项 - 从deserialize（...）方法抛出异常会导致作业失败并重新启动，或者返回null以允许Flink Kafka 消费者默默地跳过损坏的消息。 请注意，由于使用者的容错能力（请参阅下面的部分以获取更多详细信息），在损坏的消息上失败作业将使消费者尝试再次反序列化消息。 因此，如果反序列化仍然失败，则消费者将在该损坏的消息上进入不间断重启和失败循环。

##### 2.Kafka 消费者其实位置配置

The Flink Kafka Consumer allows configuring how the start position for Kafka partitions are determined.

```java
final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

FlinkKafkaConsumer08<String> myConsumer = new FlinkKafkaConsumer08<>(...);
myConsumer.setStartFromEarliest();     // start from the earliest record possible
myConsumer.setStartFromLatest();       // start from the latest record
myConsumer.setStartFromTimestamp(...); // start from specified epoch timestamp (milliseconds)
myConsumer.setStartFromGroupOffsets(); // the default behaviour

DataStream<String> stream = env.addSource(myConsumer);
...
```

其中：

- setStartFromGroupOffsets(默认模式)：Start reading partitions from the consumer group’s (`group.id` setting in the consumer properties) committed offsets in Kafka brokers (or Zookeeper for Kafka 0.8). If offsets could not be found for a partition, the `auto.offset.reset` setting in the properties will be used.
- `setStartFromEarliest()` / `setStartFromLatest()`: Start from the earliest / latest record. Under these modes, committed offsets in Kafka will be ignored and not used as starting positions.
- `setStartFromTimestamp(long)`: 从指定的时间戳开始。 对于每个分区，时间戳大于或等于指定时间戳的记录将用作起始位置。 如果分区的最新记录早于时间戳，则只会从最新记录中读取分区。 在此模式下，Kafka中的已提交偏移将被忽略，不会用作起始位置。

用户甚至可以精确的指明Consumer在没每个分区从哪个offset开始读起：

```java
Map<KafkaTopicPartition, Long> specificStartOffsets = new HashMap<>();
specificStartOffsets.put(new KafkaTopicPartition("myTopic", 0), 23L);
specificStartOffsets.put(new KafkaTopicPartition("myTopic", 1), 31L);
specificStartOffsets.put(new KafkaTopicPartition("myTopic", 2), 43L);

myConsumer.setStartFromSpecificOffsets(specificStartOffsets);
```

The above example configures the consumer to start from the specified offsets for partitions 0, 1, and 2 of topic `myTopic`. The offset values should be the next record that the consumer should read for each partition. Note that if the consumer needs to read a partition which does not have a specified offset within the provided offsets map, it will fallback to the default group offsets behaviour (i.e. `setStartFromGroupOffsets()`) for that particular partition.

请注意，当作业从故障中自动恢复或使用保存点手动恢复时，这些起始位置配置方法不会影响起始位置。 在恢复时，每个Kafka分区的起始位置由存储在保存点或检查点中的偏移量确定（有关检查点的信息，请参阅下一节，以便为消费者启用容错功能）。

##### 3.Kafka消费者和容错

>  Flink使用流重放和检查点的组合实现容错

Flink支持检查点，Flink Kafka 消费者会连续性的从一个topic消费记录并且周期性的将所有的Kafka偏移量和其他操作的状态存入检查点。如果作业失败，Flink会将流式程序恢复到最新检查点的状态，并从存储在检查点中的偏移量开始重新使用Kafka的记录。

因此，写入检查点的间隔决定了出现错误时最多需要回溯的数据。

To use fault tolerant Kafka Consumers, checkpointing of the topology needs to be enabled at the execution environment:

```java
final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
env.enableCheckpointing(5000); // checkpoint every 5000 msecs
```

Also note that Flink can only restart the topology if enough processing slots are available to restart the topology. So if the topology fails due to loss of a TaskManager, there must still be enough slots available afterwards. Flink on YARN supports automatic restart of lost YARN containers.

**If checkpointing is not enabled, the Kafka consumer will periodically commit the offsets to Zookeeper.**

##### 4.Kafka消费者主题和分区发现

###### a.分区发现

Flink Kafka Consumer支持发现动态创建的分区，然后保证exactly-once 的消费它们。在初始检索分区元数据之后（即，当作业开始运行时）发现的所有分区将从最早可能的偏移量中消耗。

By default, partition discovery is disabled. To enable it, set a non-negative value for `flink.partition-discovery.interval-millis`in the provided properties config, representing the discovery interval in milliseconds.

###### b.主题发现

At a higher-level, the Flink Kafka Consumer is also capable of discovering topics, based on pattern matching on the topic names using regular expressions. See the below for an example:

```java
final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

Properties properties = new Properties();
properties.setProperty("bootstrap.servers", "localhost:9092");
properties.setProperty("group.id", "test");

FlinkKafkaConsumer011<String> myConsumer = new FlinkKafkaConsumer011<>(
    java.util.regex.Pattern.compile("test-topic-[0-9]"),
    new SimpleStringSchema(),
    properties);

DataStream<String> stream = env.addSource(myConsumer);
...
```

To allow the consumer to discover dynamically created topics after the job started running, set a non-negative value for `flink.partition-discovery.interval-millis`. This allows the consumer to discover partitions of new topics with names that also match the specified pattern.

##### 5.Kafka Consumer提交偏移量的设置

Flink Kafka Consumer允许配置如何将偏移提交回Kafka Broker（或0.8中的Zookeeper）的行为。 请注意，Flink Kafka Consumer不依赖于承诺的偏移量来实现容错保证。提交偏移量仅是用于暴露消费者进展以进行监控的手段。

基于job是否允许检查点，偏移提交配置是不一样的：

* 不启动检查点： if checkpointing is disabled, the Flink Kafka Consumer relies on the automatic periodic offset committing capability of the internally used Kafka clients. Therefore, to disable or enable offset committing, simply set the `enable.auto.commit` (or `auto.commit.enable` for Kafka 0.8) / `auto.commit.interval.ms` keys to appropriate values in the provided `Properties` configuration.

* 启动检查点：如果启用了检查点，则Flink Kafka Consumer将在检查点完成时提交存储在检查点状态中的偏移量。This ensures that the committed offsets in Kafka brokers is consistent with the offsets in the checkpointed states. Users can choose to disable or enable offset committing by calling the`setCommitOffsetsOnCheckpoints(boolean)` method on the consumer (by default, the behaviour is `true`). Note that in this scenario, the automatic periodic offset committing settings in `Properties` is completely ignored.

##### 6.Kafka Consumers and Timestamp Extraction/Watermark Emission

在许多场景下，记录的时间戳是显式或者隐式的内嵌在记录中的。另外用户可能想要周期性的或者不规则的发射水印，例如Kafka流中包含当前事件时间水印的特殊记录。在这些情况下，Flink Kafka Consumer允许指定一个AssignerWithPeriodicWatermarks或者AssignerWithPunctuatedWatermarks。

You can specify your custom timestamp extractor/watermark emitter as described [here](https://ci.apache.org/projects/flink/flink-docs-release-1.8/apis/streaming/event_timestamps_watermarks.html), or use one from the [predefined ones](https://ci.apache.org/projects/flink/flink-docs-release-1.8/apis/streaming/event_timestamp_extractors.html). After doing so, you can pass it to your consumer in the following way:

```java
Properties properties = new Properties();
properties.setProperty("bootstrap.servers", "localhost:9092");
// only required for Kafka 0.8
properties.setProperty("zookeeper.connect", "localhost:2181");
properties.setProperty("group.id", "test");

FlinkKafkaConsumer08<String> myConsumer =
    new FlinkKafkaConsumer08<>("topic", new SimpleStringSchema(), properties);
myConsumer.assignTimestampsAndWatermarks(new CustomWatermarkEmitter());

DataStream<String> stream = env
	.addSource(myConsumer)
	.print();
```

Internally, an instance of the assigner is executed per Kafka partition. When such an assigner is specified, for each record read from Kafka, the `extractTimestamp(T element, long previousElementTimestamp)` is called to assign a timestamp to the record and the `Watermark getCurrentWatermark()` (for periodic) or the `Watermark checkAndGetNextWatermark(T lastElement, long extractedTimestamp)` (for punctuated) is called to determine if a new watermark should be emitted and with which timestamp.

> 如果水印分配器依赖于从Kafka读取的记录来推进其水印（通常是这种情况），则所有主题和分区都需要具有连续的记录流。 否则，整个应用程序的水印无法前进，并且所有基于时间的操作（例如时间窗口或具有计时器的功能）都无法取得进展。

#### 二、Kafka Producer

Flink’s Kafka Producer is called `FlinkKafkaProducer011` (or `010` for Kafka 0.10.0.x versions, etc. or just `FlinkKafkaProducer` for Kafka >= 1.0.0 versions). It allows writing a stream of records to one or more Kafka topics.

```java
DataStream<String> stream = ...;

FlinkKafkaProducer011<String> myProducer = new FlinkKafkaProducer011<String>(
        "localhost:9092",            // broker list
        "my-topic",                  // target topic
        new SimpleStringSchema());   // serialization schema

// versions 0.10+ allow attaching the records' event timestamp when writing them to Kafka;
// this method is not available for earlier Kafka versions
myProducer.setWriteTimestampToKafka(true);

stream.addSink(myProducer);
```

there are other constructor variants that allow providing the following:

- *Providing custom properties*: The producer allows providing a custom properties configuration for the internal `KafkaProducer`. 
- *Custom partitioner*: To assign records to specific partitions, you can provide an implementation of a `FlinkKafkaPartitioner` to the constructor. This partitioner will be called for each record in the stream to determine which exact partition of the target topic the record should be sent to. 
- *Advanced serialization schema*: Similar to the consumer, the producer also allows using an advanced serialization schema called `KeyedSerializationSchema`, which allows serializing the key and value separately. It also allows to override the target topic, so that one producer instance can send data to multiple topics.

##### 1.生产者分区方案

By default, if a custom partitioner is not specified for the Flink Kafka Producer, the producer will use a `FlinkFixedPartitioner` that maps each Flink Kafka Producer parallel subtask to a single Kafka partition (i.e., all records received by a sink subtask will end up in the same Kafka partition).

可以继承FlinkKafkaPartitioner类实现自己的分区函数， All Kafka versions’ constructors allow providing a custom partitioner when instantiating the producer. 分区器必须是可序列化的，因为它们将会被传送到Flink集群的其他节点上。另外，任何在 分区器中的状态都会在任务失败时丢失，因为分区器并不是生产者检查点要保存的的状态对象。

It is also possible to completely avoid using and kind of partitioner, and simply let Kafka partition the written records by their attached key (as determined for each record using the provided serialization schema). To do this, provide a `null` custom partitioner when instantiating the producer. It is important to provide `null` as the custom partitioner; as explained above, if a custom partitioner is not specified the `FlinkFixedPartitioner` is used instead.

##### 2.Kafka 生产者和容错性

###### Kafka 0.8

Before 0.9 Kafka did not provide any mechanisms to guarantee at-least-once or exactly-once semantics.

###### Kafka 0.9 and 0.10

With Flink’s checkpointing enabled, the `FlinkKafkaProducer09` and `FlinkKafkaProducer010` can provide **at-least-once delivery guarantees**.

除了开启Flink检查点，应该适当的配置setLogFailuresOnly(boolean)和setFlushOnCheckpoint(boolean)。

* setLogFailuresOnly(boolean)：by default, this is set to `false`. Enabling this will let the producer only log failures instead of catching and rethrowing them. This essentially accounts the record to have succeeded, even if it was never written to the target Kafka topic. This must be disabled for at-least-once.
* setFlushOnCheckpoint(boolean)：默认情况下，此值设置为true。 启用此功能后，Flink的检查点将在检查点成功之前等待Kafka确认检查点时的任何即时记录。 这可确保检查点之前的所有记录都已写入Kafka。 This must be enabled for at-least-once.

Kafka 生产者versions 0.9 和 0.10默认保证**至少一次**语义

###### Kafka 0.11 and newer

With Flink’s checkpointing enabled, the `FlinkKafkaProducer011` (`FlinkKafkaProducer` for Kafka >= 1.0.0 versions) can provide exactly-once delivery guarantees.

Besides enabling Flink’s checkpointing, you can also choose three different modes of operating chosen by passing appropriate `semantic` parameter to the `FlinkKafkaProducer011` (`FlinkKafkaProducer` for Kafka >= 1.0.0 versions):

- `Semantic.NONE`: Flink will not guarantee anything. Produced records can be lost or they can be duplicated.
- `Semantic.AT_LEAST_ONCE` (default setting): similar to `setFlushOnCheckpoint(true)` in`FlinkKafkaProducer010`. This guarantees that no records will be lost (although they can be duplicated).
- `Semantic.EXACTLY_ONCE`: uses Kafka 事务 to provide **exactly-once semantic**. Whenever you write to Kafka using transactions, do not forget about setting desired `isolation.level`（记得设置事务隔离级别） (`read_committed` or `read_uncommitted` - the latter one is the default value) for any application consuming records from Kafka.

Semantic.EXACTLY_ONCE模式依赖于在从所述检查点恢复之后提交在获取检查点之前启动的事务的能力。如果Flink应用失败和重启应用之间的时间大于Kafka事务的最长等待时间，就会出现数据丢失（Kafka会自动取消超时的事务）。因此必须合理设置事务超时时间。

Kafka broker默认的transaction.max.timeout.ms是15分钟。此属性不允许为生产者设置大于其值的事务超时。FlinkKafkaProducer011默认这只事务超时时间是1小时，因此， 应该在使用 `Semantic.EXACTLY_ONCE`之前增加`transaction.max.timeout.ms`的时长。

在KafkaConsumer的read_committed模式中，任何未完成的事务（既未被中止也没有完成）将阻塞所有来自指定Topic的读取未完成事务的请求。也就是说如下事件：

1. User started `transaction1` and written some records using it
2. User started `transaction2` and written some further records using it
3. User committed `transaction2`

即使来自transaction2的记录已经提交，在提交或中止transaction1之前，消费者也不会看到它们。 这有两个含义：

* 在Flink应用程序的正常工作期间，用户可以预期Kafka主题中生成的记录的可见性会延迟，等于已完成检查点之间的平均时间。
* 在Flink应用程序失败的情况下，reader将被阻止读取此应用程序所写入的主题，直到应用程序重新启动或配置的事务超时时间过去为止。 这仅适用于有多个代理/应用程序写入同一Kafka主题的情况。