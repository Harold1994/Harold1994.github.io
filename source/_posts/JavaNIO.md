---
title: JavaNIO 学习笔记一
date: 2018-11-16 19:23:47
tags: [NIO,Java]
---

#### 一、NIO预览

Java NIO (New IO) is an alternative IO API for Java 

##### NIO使用channels and buffers进行工作而不是之前的字节流或字符流

In the standard IO API you work with byte streams and character streams. In NIO you work with **channels and buffers**. Data is always read from a channel into a buffer, or written from a buffer to a channel.

##### 非阻塞IO

Java NIO enables you to do non-blocking IO. For instance, a thread can ask a channel to read data into a buffer. While the channel reads data into the buffer, the thread can do something else. Once data is read into the buffer, the thread can then continue processing it.

<!-- more-->

##### 关键组件

1. Channels

2. Buffers

3. Selectors

###### 通道和缓存

Typically, all IO in NIO starts with a `Channel`. A `Channel` is a bit like a stream. From the `Channel` data can be read into a `Buffer`. Data can also be written from a `Buffer` into a `Channel`. Here is an illustration of that:

![屏幕快照 2018-11-16 下午7.35.30.png](https://i.loli.net/2018/11/16/5beeab93aa293.png)

Java NIO中主要的Channel实现：（these channels cover UDP + TCP network IO, and file IO.)

- FileChannel
- DatagramChannel
- SocketChannel
- ServerSocketChannel

Java NIO中主要的Buffer实现：覆盖了所有能被发送的基础数据类型

- ByteBuffer
- CharBuffer
- DoubleBuffer
- FloatBuffer
- IntBuffer
- LongBuffer
- ShortBuffer

###### 选择器

A `Selector` allows a single thread to handle multiple `Channel`'s. This is handy if your application has many connections (Channels) open, but only has low traffic on each connection.

![屏幕快照 2018-11-16 下午7.45.14.png](https://i.loli.net/2018/11/16/5beeadd6e7403.png)

To use a `Selector` you register the `Channel`'s with it. Then you call it's `select()` method. This method will block until there is an event ready for one of the registered channels.

#### 二、NIO Channel

##### NIO Channel和Stream的区别：

* 一个Channel可以实现InputStream和OutputStream两个Stream的功能
* Channels可以异步读写
* Channels always read to, or write from, a Buffer.

##### 各种Channel的作用：

The `FileChannel` reads data from and to files.

The `DatagramChannel` can read and write data over the network via UDP.

The `SocketChannel` can read and write data over the network via TCP.

The `ServerSocketChannel` allows you to listen for incoming TCP connections, like a web server does. For each incoming connection a `SocketChannel` is created.

```java
/**
 * RandomAccessFile是Java中输入，输出流体系中功能最丰富的文件内容访问类，
 * 它提供很多方法来操作文件，包括读写支持，与普通的IO流相比，
 * 它最大的特别之处就是支持任意访问的方式，程序可以直接跳到任意地方来读写数据。
 */
RandomAccessFile file = new RandomAccessFile("data/test.txt","rw");
FileChannel in = file.getChannel();
ByteBuffer buf = ByteBuffer.allocate(48);
int bytesRead = in.read(buf);
// if the channel has reached end-of-stream,return -1
while (bytesRead != -1) {
    System.out.println("read " + bytesRead);
    // Flips this buffer.  The limit is set to the current position and then
    // the position is set to zero.
    buf.flip();
    while (buf.hasRemaining()) {
        System.out.println((char) buf.get());
    }
    buf.clear();
    bytesRead = in.read(buf);
}
file.close();
```

#### 三、NIO Buffer

Data is read from channels into buffers, and written from buffers into channels.

buffer本质上是内存块，被包装在 NIO Buffer对象中。

A buffer is essentially a block of memory into which you can write data, which you can then later read again. This memory block is wrapped in a NIO Buffer object, which provides a set of methods that makes it easier to work with the memory block.

##### Buffer的基础使用

Using a `Buffer` to read and write data typically follows this little 4-step process:

1. Write data into the Buffer
2. Call `buffer.flip()`
3. Read data out of the Buffer
4. Call `buffer.clear()` or `buffer.compact()`

When you write data into a buffer, the buffer keeps track of how much data you have written. Once you need to read the data, you need to switch the buffer from writing mode into reading mode using the `flip()`method call. In reading mode the buffer lets you read all the data written into the buffer.

读完buffer中的数据后，需要调清空buffer，这样可以使它再次被写入，有两种方式清空buffer：

* clear(): clears the whole buffer
* compact(): only clears the data which you have already read. Any unread data is moved to the beginning of the buffer, and data will now be written into the buffer after the unread data.

##### Buffer Capacity, Position and Limit

Buffer有三个关键属性：

- capacity：Being a memory block, a `Buffer` has a certain fixed size, also called its "capacity". Once the Buffer is full, you need to empty it (read the data, or clear it) before you can write more data into it.
- position：
  - Write Mode：Initially the position is 0. When a byte, long etc. has been written into the `Buffer` the position is advanced to point to the next cell in the buffer to insert data into. 
  - Read Mode：从指定位置开始读数据，When you flip a`Buffer` from writing mode to reading mode, the position is reset back to 0. As you read data from the `Buffer` you do so from `position`, and `position` is advanced to next position to read.
- limit
  - In write mode the limit of a `Buffer` is the limit of how much data you can write into the buffer.
  - When flipping the `Buffer` into read mode, limit means the limit of how much data you can read from the data. 

position和limit的定义与Buffer是读或写模式有关，capacity定义永远一致

![屏幕快照 2018-11-16 下午8.50.50.png](https://i.loli.net/2018/11/16/5beebd3de185f.png)

##### flip()

The `flip()` method switches a `Buffer` from writing mode to reading mode. Calling `flip()` sets the `position` back to 0, and sets the `limit` to where position just was.

##### 从Buffer中读数据

There are two ways you can read data from a `Buffer`.

1. 从Buffer中读数据写入到Channel

   ```java
   //read from buffer into channel.
   int bytesWritten = inChannel.write(buf);
   ```

2. Read data from the buffer yourself, using one of the get() methods.

   ```java
   byte aByte = buf.get();    
   ```

#### 四、NIO Scatter / Gather（分散和聚集）

Java NIO支持内建的Scatter和Gather。这两个概念应用在从Channel中读取和写入。

A scattering read from a channel is a read operation that **reads data into more than one buffer.** Thus, the channel "scatters" the data from the channel into multiple buffers.

A gathering write to a channel is a write operation that **writes data from more than one buffer into a single channel**. Thus, the channel "gathers" the data from multiple buffers into one channel.

##### Scattering Reads

![屏幕快照 2018-11-16 下午10.35.23.png](https://i.loli.net/2018/11/16/5beed5b8e5468.png)

```java
RandomAccessFile file = new RandomAccessFile("data/test.txt","rw");
FileChannel inChannel = file.getChannel();
ByteBuffer header = ByteBuffer.allocate(128);
ByteBuffer body   = ByteBuffer.allocate(1024);

ByteBuffer[] bufferArray = {header, body};
inChannel.read(bufferArray);
header.flip();
System.out.println( header.array().length + "");
System.out.println(body.array().length + "");
file.close();
```

先将Buffer插入一个数组，然后把数组作为参数传入channel.read()方法，channel按照数组中Buffer的顺序依次向其中写入，一旦一个Buffer写满了就向数组中下一个Buffer写入。因此Scatter read不适合动态大小的消息。

##### Gathering Writes

![屏幕快照 2018-11-17 上午9.57.30.png](https://i.loli.net/2018/11/17/5bef76181c3de.png)

```java
RandomAccessFile inFile = new RandomAccessFile("data/test.txt","rw");
FileChannel inChannel = inFile.getChannel();

ByteBuffer header = ByteBuffer.allocate(128);
ByteBuffer body = ByteBuffer.allocate(1024);
ByteBuffer [] bufferArray = {header, body};

inChannel.read(bufferArray);
header.flip();
body.flip();
RandomAccessFile outFile = new RandomAccessFile("data/out.txt","rw");
FileChannel outChannel = outFile.getChannel();
outChannel.write(bufferArray);
inFile.close();
outFile.close();
```