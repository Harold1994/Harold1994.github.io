---
title: Flink笔记——Flink中的Connectors
date: 2019-05-25 19:29:10
tags: [大数据, Flink]
---

#### 一、预定义的Sources和Sinks

Flink内置几种基本的Sources和Sinks，Sources包括文件、目录、socket以及聪集合或者迭代器中汲入数据，Sinks包括写入文件、标准输出、标准错误输出和socket。

#### 二、Bundled Connectors

Connectors provide code for interfacing with various third-party systems.可以连接到包括Kafka(source/sink)、Hadoop File(sink)、RabbitMQ（(source/sink)）、Elasticsearch（sink）等。

请记住，要在应用程序中使用其中一个连接器，通常需要其他第三方组件，例如， 数据存储或消息队列的服务器。 另请注意，虽然本节中列出的流连接器是Flink项目的一部分，并且包含在源版本中，但它们不包含在二进制分发版中。 

<!-- more-->

#### 三、数据源和接收器的容错保证

Flink的容错机制在出现故障时恢复程序并继续执行它们。 此类故障包括机器硬件故障，网络故障，瞬态程序故障等。

只有当源参与快照机制时，Flink才能保证对用户定义状态的一次性状态更新。 下表列出了Flink与捆绑连接器的状态更新保证。

| Source                | Guarantees                                   | Notes                                                |
| :-------------------- | :------------------------------------------- | :--------------------------------------------------- |
| Apache Kafka          | exactly once                                 | Use the appropriate Kafka connector for your version |
| AWS Kinesis Streams   | exactly once                                 |                                                      |
| RabbitMQ              | at most once (v 0.10) / exactly once (v 1.0) |                                                      |
| Twitter Streaming API | at most once                                 |                                                      |
| Collections           | exactly once                                 |                                                      |
| Files                 | exactly once                                 |                                                      |
| Sockets               | at most once                                 |                                                      |

为了保证端对端的exactly-once语义，数据接收器需要参与到检查点机制中。

| Sink                | Guarantees                   | Notes                                    |
| :------------------ | :--------------------------- | :--------------------------------------- |
| HDFS rolling sink   | exactly once                 | Implementation depends on Hadoop version |
| Elasticsearch       | at least once                |                                          |
| Kafka producer      | at least once                |                                          |
| Cassandra sink      | at least once / exactly once | exactly once only for idempotent updates |
| AWS Kinesis Streams | at least once                |                                          |
| File sinks          | at least once                |                                          |
| Socket sinks        | at least once                |                                          |
| Standard output     | at least once                |                                          |
| Redis sink          | at least once                |                                          |