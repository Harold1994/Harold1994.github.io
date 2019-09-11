---
title: JavaNIO 学习笔记二
date: 2018-11-17 10:24:39
tags: [NIO,Java]
---

#### 五、Chanel到Channel的传输

在NIO中，可以直接从一个Channel传数据到另一个Channel，f one of the channels is a `FileChannel`. The `FileChannel` class has a `transferTo()` and a `transferFrom()` method which does this for you.

##### transferFrom()

The `FileChannel.transferFrom()` method transfers data from a source channel into the`FileChannel`.

```java
RandomAccessFile inFile = new RandomAccessFile("data/test.txt","rw");
FileChannel inChannel = inFile.getChannel();

RandomAccessFile outFile = new RandomAccessFile("data/out.txt","rw");
FileChannel outChannel = outFile.getChannel();
long position = 0;
long count = inChannel.size();
outChannel.transferFrom(inChannel, position, count);
inFile.close();
outFile.close();
```

<!-- more-->

The parameters position and count, tell where in the destination file to start writing (`position`), and how many bytes to transfer maximally (`count`). 

##### transferTo()

The `transferTo()` method transfer from a `FileChannel` into some other channel. Here is a simple example:

```java
RandomAccessFile fromFile = new RandomAccessFile("fromFile.txt", "rw");
FileChannel      fromChannel = fromFile.getChannel();

RandomAccessFile toFile = new RandomAccessFile("toFile.txt", "rw");
FileChannel      toChannel = toFile.getChannel();

long position = 0;
long count    = fromChannel.size();

fromChannel.transferTo(position, count, toChannel);
```

#### 六、NIO Selector

Selector（选择器）是Java NIO中能够检测一到多个NIO通道，并能够知晓通道是否为诸如读写事件做好准备的组件。这样，一个单独的线程可以管理多个channel，从而管理多个网络连接。

##### 使用Selector的原因

![屏幕快照 2018-11-17 上午11.20.47.png](https://i.loli.net/2018/11/17/5bef89c8b40f9.png)

```java
// create a Selector by calling the Selector.open() method
Selector selector = Selector.open();
```

##### 向Selector注册Channel

In order to use a `Channel` with a `Selector` you must register the `Channel` with the `Selector`. This is done using the `SelectableChannel.register()` method, like this:

```java
channel.configureBlocking(false);
SelectionKey key = channel.register(selector, SelectionKey.OP_READ);
```

与Selector一起使用时，Channel必须处于非阻塞模式下。这意味着不能将FileChannel与Selector一起使用，因为FileChannel不能切换到非阻塞模式。而套接字通道都可以。

Notice the second parameter of the `register()` method. This is an "interest set", meaning **what events you are interested in listening for in the Channel** via the`Selector`. There are four different events you can listen for:

1. Connect
2. Accept
3. Read
4. Write

A channel that "fires an event" is also said to be "ready" for that event. 

如果想要监听多个事件，那么可以用“位或”操作符将常量连接起来，如下：

```java
int interestSet = SelectionKey.OP_READ | SelectionKey.OP_WRITE;    
```

###### SelectionKey's

当Channel通过register()方法向Selector注册时会返回一个SelectionKey，源码中给的解释这个SelectionKey是A token representing the registration of a SelectableChannel with a  Selector.

SelectionKey有如下属性：

- The interest set
- The ready set
- The Channel
- The Selector
- An attached object (optional)

###### Interest Set

The <i>interest set</i> determines which operation categories will be tested for readiness the next time one of the selector's selection methods is invoked. You can read and write that interest set via the `SelectionKey` like 

```java
int interestSet = selectionKey.interestOps();

boolean isInterestedInAccept  = interestSet & SelectionKey.OP_ACCEPT;
boolean isInterestedInConnect = interestSet & SelectionKey.OP_CONNECT;
boolean isInterestedInRead    = interestSet & SelectionKey.OP_READ;
boolean isInterestedInWrite   = interestSet & SelectionKey.OP_WRITE; 
```

通过&操作可以判断Selector是否有监听某一种事件。

###### Ready set

The <i>ready set</i> identifies the operation categories for which the key's channel has been detected to be ready by the key's selector.当key创建的时候Ready set被初始化为0，只能被selector修改，不能被直接改动，可以通过如下代码获取Ready set：

```java
int readySet = selectionKey.readyOps();
```

可以查看Ready set状态：

```java
selectionKey.isAcceptable();
selectionKey.isConnectable();
selectionKey.isReadable();
selectionKey.isWritable();
```

###### 附加的对象

可以将一个对象或者更多信息附着到SelectionKey上，这样就能方便的识别某个给定的通道。例如，可以附加 与通道一起使用的Buffer，或是包含聚集数据的某个对象。使用方法如下：

```java
selectionKey.attach(theObject);

Object attachedObj = selectionKey.attachment();
```

还可以在用register()方法向Selector注册Channel的时候附加对象。如：

```
SelectionKey key = channel.register(selector, SelectionKey.OP_READ, theObject);
```

##### 通过Selector选择通道

一旦向Selector注册了一或多个通道，就可以调用几个重载的select()方法。这些方法返回你所感兴趣的事件（如连接、接受、读或写）已经准备就绪的那些通道。换句话说，如果你对“读就绪”的通道感兴趣，select()方法会返回读事件已经就绪的那些通道。

下面是select()方法：

- int select()：`select()`阻塞到至少有一个通道在你注册的事件上就绪了。
- int select(long timeout)：最长会阻塞timeout毫秒(参数)。
- int selectNow()：不会阻塞，不管什么通道就绪都立刻返回

The `int` returned by the `select()` methods tells how many channels are ready. That is, how many channels that became ready since last time you called `select()`. If you call `select()` and it returns 1 because one channel has become ready, and you call `select()` one more time, and one more channel has become ready, it will return 1 again. If you have done nothing with the first channel that was ready, you now have 2 ready channels, but only one channel had become ready between each `select()` call.

##### selectedKeys()

一旦调用了select()方法，并且返回值表明有一个或更多个通道就绪了，然后可以通过调用selector的selectedKeys()方法，访问“已选择键集（selected key set）”中的就绪通道。如下所示：

```java
Set<SelectionKey> selectedKeys = selector.selectedKeys();    
```

当像Selector注册Channel时，Channel.register()方法会返回一个SelectionKey 对象。这个对象代表了注册到该Selector的通道。可以通过SelectionKey的selectedKeySet()方法访问这些对象。

可以遍历这个已选择的键集合来访问就绪的通道。如下：

```java
Set<SelectionKey> selectedKeys = selector.selectedKeys();
Iterator<SelectionKey> keyIterator = selectedKeys.iterator();
while(keyIterator.hasNext()) {
    SelectionKey key = keyIterator.next();
    if(key.isAcceptable()) {
        // a connection was accepted by a ServerSocketChannel.
    } else if (key.isConnectable()) {
        // a connection was established with a remote server.
    } else if (key.isReadable()) {
        // a channel is ready for reading
    } else if (key.isWritable()) {
        // a channel is ready for writing
    }
    keyIterator.remove();
}
```

#### 七、FileChannel

FileChannel不能被设置为非阻塞模式，它永远运行在阻塞模式下。

FileChannel 可以通过 RandomAccessFile 获取,或者FileChannel.open,亦或 FileInputStream/ FileOutputStream获取。write 和 read 都是通过 ByteBuffer 来存储。

读写操作之前的代码都展示过了，这里不赘述。

##### FileChannel Position

When reading or writing to a `FileChannel` you do so at a specific position. You can obtain the current position of the `FileChannel` object by calling the `position()` method.

You can also **set the position** of the `FileChannel` by calling the `position(long pos)` method.

##### FileChannel Truncate

You can truncate a file by calling the `FileChannel.truncate()` method. When you truncate a file, you cut it off at a given length. Here is an example:

```
channel.truncate(1024);
```

This example truncates the file at 1024 bytes in length.

##### FileChannel Force

The `FileChannel.force()` method flushes all unwritten data from the channel to the disk. 

#### 八、 SocketChannel

There are two ways a `SocketChannel` can be created:

1. You open a `SocketChannel` and connect to a server somewhere on the internet.
2. A `SocketChannel` can be created when an incoming connection arrives at a ServerSocketChannel

##### 打开方式

```java
SocketChannel socketChannel = SocketChannel.open();
socketChannel.connect(new InetSocketAddress("http://jenkov.com",8080));
```

##### 从SocketChannel读取数据

To read data from a `SocketChannel` you call one of the `read()` methods. Here is an example:

```java
SocketChannel socketChannel = SocketChannel.open();
socketChannel.connect(new InetSocketAddress("localhost",8088));
ByteBuffer buf = ByteBuffer.allocate(48);
while (true) {
    int byteRead = socketChannel.read(buffer);
    buffer.flip();
    if (byteRead != -1) {
        while (buffer.hasRemaining()) {
            System.out.print((char)buffer.get());
        }
    }
    buffer.clear();
}
```

##### 向SocketChannel写入数据

Writing data to a `SocketChannel` is done using the `SocketChannel.write()` method, which takes a `Buffer` as parameter. 

```java
SocketChannel socketChannel = SocketChannel.open();
socketChannel.connect(new InetSocketAddress("localhost",8088));

String newData = "New String to write to file...Ne." + System.currentTimeMillis();

ByteBuffer buffer = ByteBuffer.allocate(48);
buffer.clear();
buffer.put(newData.getBytes());
buffer.flip();
while (buffer.hasRemaining()) {
    socketChannel.write(buffer);
}
socketChannel.close();
```

##### 非阻塞模式

You can set a `SocketChannel` into non-blocking mode. When you do so, you can call`connect()`, `read()` and `write()` in asynchronous mode.

###### connect()

If the `SocketChannel` is in non-blocking mode, and you call `connect()`, the method may return **before a connection is established**. To determine whether the connection is established, you can call the `finishConnect()` method, like this:

```
socketChannel.configureBlocking(false);
socketChannel.connect(new InetSocketAddress("http://jenkov.com", 80));

while(! socketChannel.finishConnect() ){
    //wait, or do something else...    
}
```