---
title: NIO AsynchronousFileChannel
date: 2018-11-18 20:37:03
tags: [NIO,Java]
---

在Java7中AsynchronousFileChannel被加入到NIO中， The `AsynchronousFileChannel` makes it possible to read data from, and write data to files asynchronously. 

##### 创建一个AsynchronousFileChannel

```java
Path path = Paths.get("data/test.txt");
// 通过open()方法打开一个AsynchronousFileChannel
// The second parameter is one or more open options which tell the
// AsynchronousFileChannel what operations is to be performed on the underlying file.
AsynchronousFileChannel fileChannel = AsynchronousFileChannel.open(path, StandardOpenOption.READ);
```

<!-- more-->

##### 读取数据

可以通过两种方式从`AsynchronousFileChannel`读取数据。读取数据的每一种方法都调用`AsynchronousFileChannel`的`read()`方法.

###### 通过Future阅读数据

从`AsynchronousFileChannel`读取数据的第一种方法是调用返回`Future`的read()方法。

```java
public abstract Future<Integer> read(ByteBuffer dst, long position);
```

This method initiates the reading of a sequence of bytes from this channel into the given buffer, starting at the given file position. This method returns a {@code Future} representing the pending result of the operation. The {@code Future}'s {@link Future#get() get} method returns the number of bytes read or {@code -1} if the given position is greater than or equal to the file's size at the time that the read is attempted.

```java
Path path = Paths.get("data/test.txt");
// 通过open()方法打开一个AsynchronousFileChannel
// The second parameter is one or more open options which tell the
// AsynchronousFileChannel what operations is to be performed on the underlying file.
AsynchronousFileChannel fileChannel = AsynchronousFileChannel.open(path, StandardOpenOption.READ);
ByteBuffer buf = ByteBuffer.allocate(48);
Future<Integer> operation = fileChannel.read(buf,0);
// 通过调用read()方法返回的Future实例的isDone()方法，可以检查读取操作是否完成。
while (!operation.isDone());
buf.flip();
byte[] data = new byte[buf.limit()];
buf.get(data);
System.out.println(new String(data));
buf.clear();
```

###### 通过一个CompletionHandler读取数据

该方法将一个`CompletionHandler`作为参数。

```java
public abstract <A> void read(ByteBuffer dst,
                              long position,
                              A attachment,
                              CompletionHandler<Integer,? super A> handler);
```

The {@code handler} parameter is a completion handler that is invoked when the read operation completes (or fails). The result passed to the completion handler is the number of bytes read or {@code -1} if no bytes could be read because the channel has reached end-of-stream.

```java
Path path = Paths.get("data/test.txt");
AsynchronousFileChannel channel = AsynchronousFileChannel.open(path, StandardOpenOption.READ);
ByteBuffer buffer = ByteBuffer.allocate(1300);
long position = 0;
channel.read(buffer, position, buffer,
        new CompletionHandler<Integer, ByteBuffer>() {
            @Override
            public void completed(Integer result, ByteBuffer attachment) {
                System.out.println("read done");
                System.out.println(result + "");
                attachment.flip();
                byte [] data = new byte[attachment.limit()];
                attachment.get(data);
                System.out.println(new String(data));
                attachment.clear();
            }

            @Override
            public void failed(Throwable exc, ByteBuffer attachment) {
                System.out.println("read fail");
            }
        });
// 给终端显示留一些时间，不然会来不及显示读取的信息进程就结束了
Thread.sleep(3000);
```

#### 写数据

you can write data to an `AsynchronousFileChannel` in two ways. Each way to write data call one of the `write()` methods of the `AsynchronousFileChannel`. 

##### 通过Future写

```java
Path path = Paths.get("data/test-write.txt");
if (!Files.exists(path))
    Files.createFile(path);
// the file must already exist before this code will work
AsynchronousFileChannel fileChannel =
        AsynchronousFileChannel.open(path, StandardOpenOption.WRITE);
ByteBuffer buffer = ByteBuffer.allocate(1024);
long position = 0;
// 尽管只有这几个字符，最终还是会写够1024个，没有的用空格占位
buffer.put("test data".getBytes());
buffer.flip();

Future<Integer> operation = fileChannel.write(buffer, position);
buffer.clear();

while(!operation.isDone());

System.out.println("Write done");
```

##### Writing Data Via a CompletionHandler

```java
fileChannel.write(buffer, position, buffer,
        new CompletionHandler<Integer, ByteBuffer>() {
            @Override
            public void completed(Integer result, ByteBuffer attachment) {
                System.out.println("bytes written: " + result);
            }

            @Override
            public void failed(Throwable exc, ByteBuffer attachment) {
                System.out.println("Write failed");
                exc.printStackTrace();
            }
        });
Thread.sleep(300);
```

