---
title: Flink笔记——Flink中访问外部数据的异步IO
date: 2019-05-25 16:24:58
tags: [大数据, Flink]
---

#### 一、异步I/O的需求

当与外部系统交互时（例如，当使用存储在数据库中的数据来丰富流事件时），需要注意与外部系统的通信延迟不应当主导流应用程序的工作。

普通的访问外部数据的方式是同步的：例如在一个MapFunction中，发送一个请求到数据库，然后MapFunction一直等待直到收到响应。在大多数情况下，这会造成函数的大量时间都用在等待响应上。

<!-- more--> 

与数据库的异步交互意味着单个并行函数实例可以同时处理许多请求并同时接收响应。这样，等待的通化市可以发送其他请求和接收响应。 至少，等待时间是在多个请求上摊销的。 这导致大多数情况下流量吞吐量更高。

![](https://ci.apache.org/projects/flink/flink-docs-release-1.8/fig/async_io.svg)

> 注意：
>
> 通过将MapFunction扩展到非常高的并行度来提高吞吐量在某些情况下也是可能的，但通常会产生非常高的资源成本：拥有更多并行MapFunction实例意味着更多任务、线程、Flink内部网络连、到数据库的网络连接，缓冲区和全局内部簿记开销。

#### 二、先决条件

如上所述，实现合适访问数据库（或 key/value store）的异步I/O需要一个到数据库的支持异步请求的客户端。许多流行的数据库提供这样的客户端支持。

在没有这样的客户端的情况下，可以通过创建多个客户端并使用线程池处理同步调用来尝试将同步客户端转变为有限的并发客户端。 但是，这种方法通常比适当的异步客户端效率低。

#### 三、异步I/O API

Flink的Async I / O API允许用户将异步请求客户端与数据流一起使用。 API处理与数据流的集成，以及处理顺序，事件时间，容错等。

假设有一个目标数据库的异步客户端，需要三个部分来实现对数据库的异步I / O流转换：

* An implementation of `AsyncFunction` that dispatches the requests
* A *callback* that takes the result of the operation and hands it to the `ResultFuture`
* Applying the async I/O operation on a DataStream as a transformation

```java
package flink.streaming;

import org.apache.flink.api.java.tuple.Tuple2;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.functions.async.ResultFuture;
import org.apache.flink.streaming.api.functions.async.RichAsyncFunction;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Future;
import java.util.function.Supplier;

/**
 * An implementation of the 'AsyncFunction' that sends requests and sets the callback.
 */
class AsyncDatabaseRequest extends RichAsyncFunction<String, Tuple2<String, String>> {
    private transient DatabaseClient client;
    @Override
    public void open(Configuration parameters) throws Exception {
        client = new DatabaseClient(host, post, credentials);
    }

    @Override
    public void close() throws Exception {
        client.close();
    }

    @Override
    public void asyncInvoke(String key, ResultFuture<Tuple2<String, String>> resultFuture) throws Exception {
        // 发出异步请求，接收结果Future
        final Future<String> result = clinet.query(key);
        // set the callback to be executed once the request by the client is complete
        // the callback simply forwards the result to the result future
        //CompletableFuture可以通过回调的方式处理计算结果，也提供了转换和组合 CompletableFuture 的方法
        CompletableFuture.supplyAsync(new Supplier<String>() {
            @Override
            public String get() {
                try {
                    return result.get();
                } catch (InterruptedException | ExecutionException e) {
                    // Normally handled explicitly.
                    return null;
                }
            }
        }).thenAccept((String dbResult) -> {
            resultFuture.complete(Collections.singleton(new Tuple2<>(key, dbResult)));
        });
    }
}
    // create the original stream
    DataStream<String> stream = ...;

// apply the async I/O transformation
        DataStream<Tuple2<String, String>> resultStream =
        AsyncDataStream.unorderedWait(stream, new AsyncDatabaseRequest(), 1000, TimeUnit.MILLISECONDS, 100);
```

**Important note**: The `ResultFuture` is completed with the first call of `ResultFuture.complete`. All subsequent `complete` calls will be ignored.

The following two parameters control the asynchronous operations:

- **Timeout**: The timeout defines how long an asynchronous request may take before it is considered failed. This parameter guards against dead/failed requests.
- **Capacity**: This parameter defines how many asynchronous requests may be in progress at the same time. Even though the async I/O approach leads typically to much better throughput, the operator can still be the bottleneck in the streaming application. Limiting the number of concurrent requests ensures that the operator will not accumulate an ever-growing backlog of pending requests, but that it will trigger backpressure once the capacity is exhausted.

#### 四、超时处理

When an async I/O request times out, **by default an exception is thrown** and job is restarted. If you want to handle timeouts, you can override the `AsyncFunction#timeout` method.

#### 五、result的顺序

The concurrent requests issued by the `AsyncFunction` frequently complete in some undefined order, based on which request finished first. To control in which order the resulting records are emitted, Flink offers two modes（两种模型控制输出结果的顺序）:

* 无序的：一旦异步请求结束就返回结果。The order of the records in the stream is different after the async I/O operator than before. 当使用处理时间作为基本时间机制时，这种模型具有低延迟，低开销的特性，Use `AsyncDataStream.unorderedWait(...)` for this mode.
* 有序的：Result records are emitted in the same order as the asynchronous requests are triggered (the order of the operators input records).To achieve that, the operator buffers a result record until all its preceding records are emitted (or timed out). This usually introduces some amount of **extra latency and some overhead in checkpointing,** because records or results are maintained in the checkpointed state for a longer time, compared to the unordered mode. Use `AsyncDataStream.orderedWait(...)` for this mode.

#### 六、事件时间

当流应用程序与事件时间一起工作时，异步I / O操作符将正确处理水印。 这意味着两种顺序模式具体如下：

* 无序的：水印不会超过记录，反之亦然，这意味着水印建立了顺序边界。记录只在水印之间无序发出，只有在发出水印后才会发出某个水印后发生的记录。 反过来，只有在发出水印之前输入的所有结果记录之后才会发出水印。
  - That means that in the presence of watermarks, the *unordered* mode introduces some of the same latency and management overhead as the *ordered* mode does. The amount of that overhead depends on the watermark frequency.

* 有序的：保留记录的水印顺序，就像保留记录之间的顺序一样。 与processing time相比，开销没有显着变化。

#### 七、容错保障

异步I/O操作符保证 exactly-once 语义。它在检查点中存储正在进行的异步请求的记录，并在从故障中恢复时恢复/重新触发请求。