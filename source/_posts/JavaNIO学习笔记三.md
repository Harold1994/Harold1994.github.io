---
title: JavaNIO 学习笔记三
date: 2018-11-17 20:47:44
tags: [NIO,Java]
---

#### 九、ServerSocketChannel

 NIO ServerSocketChannel 的作用等价于于ServerSocket，作为Socket的服务端等待客户端连接。

```java
// Opening a ServerSocketChannel
ServerSocketChannel ssc = ServerSocketChannel.open();
ssc.socket().bind(new InetSocketAddress(8088));
while (true) {
    // Listening for incoming connections
    // 在阻塞模式下accept()会一直阻塞到有一个客户端连接它，非阻塞模式下会立即返回一个null
    SocketChannel channel = ssc.accept();
    if (channel.finishConnect()) {
        ByteBuffer buffer = ByteBuffer.allocate(48);
        channel.read(buffer);
        buffer.flip();
        while (buffer.hasRemaining()) {
            System.out.println((char) buffer.get());
        }
    }
}
// Closing a ServerSocketChannel
ssc.close()
```

<!-- more-->

##### 非阻塞模式

A `ServerSocketChannel` can be set into non-blocking mode. In non-blocking mode the `accept()` method returns immediately, and may thus return null, if no incoming connection had arrived. Therefore you will have to check if the returned`SocketChannel` is null. 

```java
ServerSocketChannel ssc = ServerSocketChannel.open();
ssc.socket().bind(new InetSocketAddress(8088));
ssc.configureBlocking(false);
while (true) {
    SocketChannel channel = ssc.accept();
    if (channel != null) {
        ...
    }
}
```

#### 十、非阻塞式服务器

##### 非阻塞IO管道

一个非阻塞式IO管道是由各个处理非阻塞式IO组件组成的链。其中包括读/写IO。下图就是一个简单的非阻塞式IO管道组成：

![屏幕快照 2018-11-17 下午9.34.58.png](https://i.loli.net/2018/11/17/5bf01910741ed.png)

一个组件使用 [**Selector**](http://tutorials.jenkov.com/java-nio/selectors.html) 监控 [**Channel**](http://tutorials.jenkov.com/java-nio/channels.html) 什么时候有可读数据。然后这个组件读取输入并且根据输入生成相应的输出。最后输出将会再次写入到一个Channel中。

一个非阻塞IO管道可能同时读取多个Channel里的数据。举个例子：从多个SocketChannel管道读取数据。

##### Non-blocking对比Blocking IO Pipelines

非阻塞和阻塞IO管道两者之间最大的区别在于他们如何从底层Channel(Socket或者file)读取数据。

IO管道通常**从流中读取数**据（来自socket或者file）并且将这些数据拆分为一系列连贯的消息。

###### 阻塞式管道

一个阻塞IO管道可以使用类似InputStream的接口每次一个字节地从底层Channel读取数据，并且这个接口阻塞直到有数据可以读取。

缺点：每一个要分解成消息的流都需要一个独立的线程。必须要这样做的理由是每一个流的IO接口会阻塞，直到它有数据读取。这就意味着一个单独的线程是无法尝试从一个没有数据的流中读取数据转去读另一个流。一旦一个线程尝试从一个流中读取数据，那么这个线程将会阻塞直到有数据可以读取。

为了将线程数量降下来，许多服务器使用了服务器维持线程池（例如：常用线程为100）的设计，从而一次一个地从入站链接（inbound connections）地读取。入站链接保存在一个队列中，线程按照进入队列的顺序处理入站链接。这一设计如下图所示

![屏幕快照 2018-11-17 下午10.00.05.png](https://i.loli.net/2018/11/17/5bf01ef12ac8e.png)

然而，这一设计需要入站链接合理地发送数据。如果入站链接长时间不活跃，那么大量的不活跃链接实际上就造成了线程池中所有线程阻塞。这意味着服务器响应变慢甚至是没有反应。

###### 基础非阻塞式IO管道设计

A non-blocking IO pipeline can use a single thread to read messages from multiple streams. This requires that the streams can be switched to non-blocking mode. 在非阻塞模式下，当你读取流信息时可能会返回0个字节或更多字节的信息。

To avoid checking streams that has 0 bytes to read we use a [Java NIO Selector](http://tutorials.jenkov.com/java-nio/selectors.html). One or more `SelectableChannel` instances can be registered with a `Selector`. 

![屏幕快照 2018-11-17 下午10.04.43.png](https://i.loli.net/2018/11/17/5bf02007a899c.png)

#### 十一、DatagramChannel

A Java NIO DatagramChannel is a channel that can send and receive **UDP packets.** 因为UDP是无连接的网络协议，所以不能像其它通道那样读取和写入。它发送和接收的是数据包。

###### 接收数据

```java
public class DatagramChannelReceiveDemo {
    public static void main(String[] args) throws IOException {
        // open a DatagramChannel
        DatagramChannel channel = DatagramChannel.open();
        //创建一个可以从9999UDP端口接收数据包的DatagramChannel
        channel.socket().bind(new InetSocketAddress(9999));
        ByteBuffer buffer = ByteBuffer.allocate(48);
        buffer.clear();
        //  receive() will copy the content of a received packet of data into the Buffer
        while (true) {
            channel.receive(buffer);
            buffer.flip();
            while (buffer.hasRemaining()) {
                System.out.print((char)buffer.get());
            }
            buffer.clear();
        }
    }
}
```

###### 发送数据

```java
public class DatagramChannelSendDemo {
    public static void main(String[] args) throws IOException {
        // open a DatagramChannel
        DatagramChannel channel = DatagramChannel.open();
//        channel.socket().bind(new InetSocketAddress(9999));
        String newData = "New String to write to file..."
                + System.currentTimeMillis();
        ByteBuffer buf = ByteBuffer.allocate(48);
        buf.clear();
        buf.put(newData.getBytes());
        buf.flip();
        int bytesSent = channel.send(buf, new InetSocketAddress("127.0.0.1", 9999));
        channel.close();
    }
}
```

#### 十二、NIO Pipe

A Java NIO Pipe is a one-way data connection between two threads. . A `Pipe` has a source channel and a sink channel. 数据会被写到sink通道，从source通道读取。

![屏幕快照 2018-11-17 下午10.46.09.png](https://i.loli.net/2018/11/17/5bf029c0389b7.png)

```java
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.Pipe;



public class PipeDemo {
    static Pipe pipe;

    static {
        try {
            pipe = Pipe.open();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public PipeDemo() throws IOException {
    }

    static class RunnableA implements Runnable {
        String newData = "New String to write to ThraedB...";
        public RunnableA() throws IOException {
        }

        @Override
        public void run() {
            Pipe.SinkChannel sc = pipe.sink();
            ByteBuffer buffer = ByteBuffer.allocate(48);
            buffer.put(newData.getBytes());
            buffer.flip();
            while (buffer.hasRemaining()) {
                try {
                    sc.write(buffer);
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }
        }
    }

    static class RunnableB implements Runnable{
        @Override
        public void run() {
            Pipe.SourceChannel sourceChannel = pipe.source();
            ByteBuffer buf = ByteBuffer.allocate(48);
            try {
                int bytesRead = sourceChannel.read(buf);
            } catch (IOException e) {
                e.printStackTrace();
            }
            buf.flip();
            while (buf.hasRemaining()) {
                System.out.print((char)buf.get());
            }
        }
    }

    public static void main(String[] args) throws IOException {
        RunnableA a = new RunnableA();
        RunnableB b = new RunnableB();
        Thread t1 = new Thread(a);
        Thread t2 = new Thread(b);
        t1.start();
        t2.start();
    }
}
```

#### 十三、NIO对比IO

##### NIO和IO的主要区别

|   IO   |   NIO    |
| :----: | :------: |
| 面向流 | 面向缓冲 |
| 阻塞IO | 非阻塞IO |
|        |  选择器  |

##### 面向流和面向缓冲

* 面向流意味着一次从流中阅读一个或多个字节，它们没有被缓存在任何地方。此外，它不能前后移动流中的数据。
* 面向缓冲数据读取到一个它稍后处理的缓冲区，需要时可在缓冲区中前后移动。这就增加了处理过程中的灵活性。但是，还需要检查是否该缓冲区中包含所有您需要处理的数据。需确保当更多的数据读入缓冲区时，不要覆盖缓冲区里尚未处理的数据。

##### 阻塞与非阻塞

* 阻塞：when a thread invokes a `read()` or `write()`, that thread is blocked until there is some data to read, or the data is fully written. The thread can do nothing else in the meantime.

* 非阻塞：Java NIO's non-blocking mode enables a thread to request reading data from a channel, and only get what is currently available, or nothing at all, if no data is currently available.线程通常将非阻塞IO的空闲时间用于在其它通道上执行IO操作，所以一个单独的线程现在可以管理多个输入和输出通道

##### 选择器

Java NIO's selectors allow a single thread to monitor multiple channels of input. You can register multiple channels with a selector, then use a single thread to "select" the channels that have input available for processing, or select the channels that are ready for writing. 

从通道读取字节到ByteBuffer。当这个方法调用返回时，你不知道你所需的所有数据是否在缓冲区内。你所知道的是，该缓冲区包含一些字节，这使得处理有点困难。

所以，你怎么知道是否该缓冲区包含足够的数据可以处理呢？好了，你不知道。发现的方法只能查看缓冲区中的数据。其结果是，在你知道所有数据都在缓冲区里之前，你必须检查几次缓冲区的数据。这不仅效率低下，而且可以使程序设计方案杂乱不堪。例如：

```java
ByteBuffer buffer = ByteBuffer.allocate(48);

int bytesRead = inChannel.read(buffer);
// 判断buffer是否读满了
while(! bufferFull(bytesRead) ) {
    bytesRead = inChannel.read(buffer);
}
```

The `bufferFull()` method has to keep track of how much data is read into the buffer, and return either `true` or `false`, depending on whether the buffer is full. 

![屏幕快照 2018-11-18 下午12.09.43.png](https://i.loli.net/2018/11/18/5bf0e617cc730.png)

##### 用来处理数据的线程数

NIO可只使用一个（或几个）单线程管理多个通道（网络连接或文件），但付出的代价是解析数据可能会比从一个阻塞流中读取数据更复杂。

如果需要管理同时打开的成千上万个连接，这些连接每次只是发送少量的数据，例如聊天服务器，实现NIO的服务器可能是一个优势。同样，如果你需要维持许多打开的连接到其他计算机上，如P2P网络中，使用一个单独的线程来管理你所有出站连接，可能是一个优势。

**Java NIO: 单线程管理多个连接**

如果有少量的连接使用非常高的带宽，一次发送大量的数据，也许典型的IO服务器实现可能非常契合。

#### NIO Path

A Java `Path` instance represents a *path* in the file system. A path can point to either a file or a directory. 

在很多方面，java.nio.file.Path接口和[java.io.File](http://tutorials.jenkov.com/java-io/file.html)有相似性，但也有一些细微的差别。在很多情况下，可以用Path来代替File类。

##### 创建Path实例

可以使用Paths 类的静态方法Paths.get()来产生一个实例

```java
Path path = Paths.get("data/test.txt");
```

#### NIO File

NIO File要搭配NIO Path一起使用。

Java IO API中的FIle类可以让你访问底层文件系统，通过File类，你可以做到以下几点：

- 检测文件是否存在
- 读取文件长度
- 重命名或移动文件
- 删除文件
- 检测某个路径是文件还是目录
- 读取目录中的文件列表

请注意：File只能访问文件以及文件系统的元数据。如果你想读写文件内容，需要使用FileInputStream、FileOutputStream或者RandomAccessFile。如果你正在使用Java NIO，并且想使用完整的NIO解决方案，你会使用到java.nio.FileChannel(否则你也可以使用File)。