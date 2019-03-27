---
title: Hadoop源码阅读——Hadoop RPC(三)
date: 2018-12-04 22:08:31
tags: [Hadoop,HDFS,大数据]
---

#### 三、Hadoop RPC实现

上一篇文章分析了Hadoop RPC框架的RPC、Client类的实现，还有一个Server类用于实现服务器端的功能，本篇文章将详细分析Server类。

##### 3. Server类实现

Server类采用了很多技术来提供并发能力，包括线程池、JavaNIO提供的Reactor模式等，其中Reactor模式贯穿了整个Server的设计。

###### a. Reactor模式

reactor设计模式，是一种基于事件驱动的设计模式。处理流程是：应用业务向一个中间人注册一个回调（event handler），当IO就绪后，就这个中间人产生一个事件，并通知此handler进行处理。这里的中间人其实是一个不断等待和循环的线程，它接受所有应用程序的注册，并检查应用程序注册的IO事件是否就绪，如果就绪则通知应用程序进行处理。

<!-- more--> 

​							图一：**单线程的基于Reactor模式的网络服务器设计**

![5555632-b56f7cfaaccf62c7.png](https://i.loli.net/2018/12/04/5c0690fd7ae3e.png)

Reactor：负责响应IO事件，当检测到一个新的事件，将其发送给相应的Handler去处理。

Handler：负责处理非阻塞的行为，标识系统管理的资源；同时将handler与事件绑定。

Acceptor：Handler的一种，绑定了connect事件。当客户端发起connect请求时，Reactor会将accept事件分发给Acceptor处理。

上面的设计中服务器端只有一个线程，存在如下缺点：

* 一个连接里完整的网络处理过程一般分为accept、read、decode、process(compute)、encode、send这几步，如果在process这个过程中需要处理大量的耗时业务，比如连接DB或者进行耗时的计算等，整个线程都被阻塞，无法处理其他的链路

* 单线程，不能充分利用多核处理器

* 单线程处理I/O的效率确实非常高，没有线程切换，只是拼命的读、写、选择事件。但是如果有成千上万个链路，即使不停的处理，一个线程也无法支撑

* 单线程，一旦线程意外进入死循环或者抛出未捕获的异常，整个系统就挂掉了

因此提出了**基于多线程Reactor模式的网络服务器结构：**

![2.png](https://i.loli.net/2018/12/04/5c0693255666c.png)

将占用时间较长的读取请求部分以及业务逻辑交给两个独立的线程池处理，RPC的请求读取和响应是在两个不同的线程中执行的，提高了服务器的并发性。

对于像NameNode这样的分布式节点中的Master节点来说，同一时间可能有非常多的Scoket连接请求和RPC请求到达，可能造成Reactor在处理和分发这些IO事件时出现拥塞，导致整体性能降低，因此可以将上面的一个Reactor扩展成多个Reactor，他们分别用于并发的监听不同的IO事件。

​				图二：**基于多Reactor多线程模式的网络服务器结构**

![屏幕快照 2018-12-05 上午9.45.34.png](https://i.loli.net/2018/12/05/5c072dc99cb8c.png)

mainReactor负责监听Scoket连接事件

readReactor负责监听IO读事件

respondReactor负责监听IO写事件

###### b.Server类设计

Hadoop Server类是一个典型的多Reactor加多线程的网络服务结构，相对于上图，Server类用一个Listener类代替了上图中的MainReactor，Listener对象中有一个Selector对象，负责负责监听来自客户端的RPC请求。Handler类用来处理RPC请求并发回响应。Responder类用于向客户端发回RPC响应，**与Handler类的功能有重复**，原因在于在响应很大或者网络条件不佳的情况下，Handler很难将完整的响应发回客户端，这会造成Handler线程阻塞，从而影响其响应效率，所以Handler会在没有将完整响应发回客户端时在Responder内部的writeSelector上注册一个写响应事件，当writeSelector检测到网络条件具备写响应条件是，会通知Responder将剩余响应发回客户端。

[![屏幕快照 2019-02-12 下午3.53.03.png](https://i.loli.net/2019/02/12/5c627b71a8f22.png)](https://i.loli.net/2019/02/12/5c627b71a8f22.png)

Server类处理RPC请求的流程：

* Listener线程的selector在ServerSocketChannel上注册OP_ACCEPT事件，并且创建readers数组。每个reader的readSelector此时并不监听任何Channel
* Client发送Socket连接请求，触发Listener的selector唤醒Listener线程
* Listener调用ServerSocketChannel.accept()获得一个新的SocketChannel
* Listener从readers数组中挑选一个线程，并在Reader的readSelector上注册OP_READ事件
* Client发送RPC请求数据包，触发Reader的selector唤醒Reader线程
* Reader从SocketChannel中读取数据，封装成Call对象，然后放入共享队列callQueue中
* 起初，handlers数组中的线程都在callQueue上阻塞，当有Call对象被放入时，其中一个Handler被唤醒，然后根据Call对象的信息调用BlockingService对象的callBlockingMethod()方法，随后Handler尝试将响应写入SocketChannel。
* 如果Handler发现无法将响应完全写入SocketChannel，将在Responder的writeSelector上注册OP_WRITE事件。如果一个Call长时间都未被写入，则会被Responder移除。

-------

* Listener类

  整个Server只有一个Listener线程，监听来自客户端的Socket请求，对于每一个Socket请求，Listener都会从readers中选择一个Reader线程来处理。

  ```java
  /**
   * run方法判断是否监听到了OP_ACCEPT事件
   */
  @Override
  public void run() {
    LOG.info(Thread.currentThread().getName() + ": starting");
    SERVER.set(Server.this);
    connectionManager.startIdleScan();
    while (running) {
      SelectionKey key = null;
      try {
        getSelector().select();
        // 循环判断是否有新的连接建立请求
        Iterator<SelectionKey> iter = getSelector().selectedKeys().iterator();
        while (iter.hasNext()) {
          key = iter.next();
          iter.remove();
          try {
            if (key.isValid()) {
              if (key.isAcceptable())
                  // 如果有则调用doAccept()方法响应
                doAccept(key);
            }
          } catch (IOException e) {
          }
          key = null;
        }
      } catch (OutOfMemoryError e) {
        // we can run out of memory if we have too many threads
        // log the event and sleep for a minute and give 
        // some thread(s) a chance to finish
          // 线程太多可能导致内存溢出
        LOG.warn("Out of Memory in server select", e);
        closeCurrentConnection(key, e);
        connectionManager.closeIdle(true);
        try { Thread.sleep(60000); } catch (Exception ie) {}
      } catch (Exception e) {
        closeCurrentConnection(key, e);
      }
      // running === false
        LOG.info("Stopping " + Thread.currentThread().getName());
  
        synchronized (this) {
          try {
            acceptChannel.close();
            selector.close();
          } catch (IOException e) { }
  
          selector= null;
          acceptChannel= null;
          
          // close all connections
          connectionManager.stopIdleScan();
          connectionManager.closeAll();
        }
      }
  ```

```java
void doAccept(SelectionKey key) throws InterruptedException, IOException,  OutOfMemoryError {
  ServerSocketChannel server = (ServerSocketChannel) key.channel();
  SocketChannel channel;
  while ((channel = server.accept()) != null) {
    // 设置为非阻塞
    channel.configureBlocking(false);
    channel.socket().setTcpNoDelay(tcpNoDelay);
    channel.socket().setKeepAlive(true);
    // round robin方式选择一个Reader线程
    Reader reader = getReader();
    // Connection类封装了Server与Client之间的Socket连接，因此Reader可以知道在哪个Socket上读取数据
    Connection c = connectionManager.register(channel);
    // If the connectionManager can't take it, close the connection.
    if (c == null) {
      if (channel.isOpen()) {
        IOUtils.cleanup(null, channel);
      }
      connectionManager.droppedConnections.getAndIncrement();
      continue;
    }
    key.attach(c);  // so closeCurrentConnection can get the object
      // 向Reader对象中的Connection队列添加这个Connection并激活readSelector
    reader.addConnection(c);
  }
}
```

* Reader类

  Reader类是Listener类的子类，也是一个线程类，每个Reader线程会负责读取若干个客户端连接发来的RPC请求，Listener类中有一个Reader类型的数组readers。Reader类定义了自己的readSelector对象，还定义了阻塞队列pendingConnections，用来存储分配到本线程的Connection对象。

  Reader线程的主循环在doRunLoop()方法中,

  **org.apache.hadoop.ipc.Server.Listener.Reader#doRunLoop**

  ```java
  private synchronized void doRunLoop() {
    while (running) {
      SelectionKey key = null;
      try {
        // consume as many connections as currently queued to avoid
        // unbridled acceptance of connections that starves the select
        int size = pendingConnections.size();
        // 取出pendingConnections中所有的Connection并注册OP_READ事件
        for (int i=size; i>0; i--) {
          Connection conn = pendingConnections.take();
          conn.channel.register(readSelector, SelectionKey.OP_READ, conn);
        }
        // 阻塞，直到有一个可读事件
        readSelector.select();
  
        Iterator<SelectionKey> iter = readSelector.selectedKeys().iterator();
        while (iter.hasNext()) {
          key = iter.next();
          iter.remove();
          try {
            if (key.isReadable()) {
                // 有可读事件，调用doRead方法处理
              doRead(key);
            }
          } catch (CancelledKeyException cke) {
            // something else closed the connection, ex. responder or
            // the listener doing an idle scan.  ignore it and let them
            // clean up.
            LOG.info(Thread.currentThread().getName() +
                ": connection aborted from " + key.attachment());
          }
          key = null;
        }
      } catch (InterruptedException e) {
        if (running) {                      // unexpected -- log it
          LOG.info(Thread.currentThread().getName() + " unexpectedly interrupted", e);
        }
      } catch (IOException ex) {
        LOG.error("Error in Reader", ex);
      } catch (Throwable re) {
        LOG.fatal("Bug in read selector!", re);
        ExitUtil.terminate(1, "Bug in read selector!");
      }
    }
  }
  ```

  **org.apache.hadoop.ipc.Server.Listener#doRead**

  ```java
  void doRead(SelectionKey key) throws InterruptedException {
    int count;
    // 获取在Listener的doAccept方法中绑定的Connection对象
    Connection c = (Connection)key.attachment();
    if (c == null) {
      return;  
    }
    c.setLastContact(Time.now());
    
    try {
        // 调用Connection的readAndProcess方法处理读取请求
      count = c.readAndProcess();
    } catch (InterruptedException ieo) {
      LOG.info(Thread.currentThread().getName() + ": readAndProcess caught InterruptedException", ieo);
      throw ieo;
        ...
  ```

* Connection类

  **org.apache.hadoop.ipc.Server.Connection#readAndProcess**

  ```java
  public int readAndProcess() throws IOException, InterruptedException {
    while (!shouldClose()) { // stop if a fatal response has been sent.
      int count = -1;
      if (dataLengthBuffer.remaining() > 0) {
        count = channelRead(channel, dataLengthBuffer);       
        if (count < 0 || dataLengthBuffer.remaining() > 0) 
          return count;
      }
      // 先读取连接头域
      if (!connectionHeaderRead) {
        //Every connection is expected to send the header.
        if (connectionHeaderBuf == null) {
          connectionHeaderBuf = ByteBuffer.allocate(3);
        }
        count = channelRead(channel, connectionHeaderBuf);
        if (count < 0 || connectionHeaderBuf.remaining() > 0) {
          return count;
        }
        int version = connectionHeaderBuf.get(0);
        // TODO we should add handler for service class later
        this.setServiceClass(connectionHeaderBuf.get(1));
        dataLengthBuffer.flip();
        
        // Check if it looks like the user is hitting an IPC port
        // with an HTTP GET - this is a common error, so we can
        // send back a simple string indicating as much.
        if (HTTP_GET_BYTES.equals(dataLengthBuffer)) {
          setupHttpRequestOnIpcPortResponse();
          return -1;
        }
        
        if (!RpcConstants.HEADER.equals(dataLengthBuffer)
            || version != CURRENT_VERSION) {
          //Warning is ok since this is not supposed to happen.
          LOG.warn("Incorrect header or version mismatch from " + 
                   hostAddress + ":" + remotePort +
                   " got version " + version + 
                   " expected version " + CURRENT_VERSION);
          setupBadVersionResponse(version);
          return -1;
        }
        
        // this may switch us into SIMPLE
        authProtocol = initializeAuthContext(connectionHeaderBuf.get(2));          
        
        dataLengthBuffer.clear();
        connectionHeaderBuf = null;
        connectionHeaderRead = true;
        continue;
      }
       // 读取完整RPC请求
      if (data == null) {
        dataLengthBuffer.flip();
        dataLength = dataLengthBuffer.getInt();
        checkDataLength(dataLength);
        data = ByteBuffer.allocate(dataLength);
      }
      
      count = channelRead(channel, data);
      
      if (data.remaining() == 0) {
        dataLengthBuffer.clear();
        data.flip();
        ByteBuffer requestData = data;
        data = null; // null out in case processOneRpc throws.
        boolean isHeaderRead = connectionContextRead;
        processOneRpc(requestData);// 处理RPC请求体
        if (!isHeaderRead) {
          continue;
        }
      } 
      return count;
    }
    return -1;
  }
  ```

  **org.apache.hadoop.ipc.Server.Connection#processOneRpc**

  ```java
  /**
   * Process one RPC Request from buffer read from socket stream 
   *  - decode rpc in a rpc-Call
   *  - handle out-of-band RPC requests such as the initial connectionContext
   *  - A successfully decoded RpcCall will be deposited in RPC-Q and
   *    its response will be sent later when the request is processed.
   * 
   * Prior to this call the connectionHeader ("hrpc...") has been handled and
   * if SASL then SASL has been established and the buf we are passed
   * has been unwrapped from SASL.
   * 
   * @param bb - contains the RPC request header and the rpc request
   * @throws IOException - internal error that should not be returned to
   *         client, typically failure to respond to client
   * @throws InterruptedException
   */
  private void processOneRpc(ByteBuffer bb)
      throws IOException, InterruptedException {
    // exceptions that escape this method are fatal to the connection.
    // setupResponse will use the rpc status to determine if the connection
    // should be closed.
    int callId = -1;
    int retry = RpcConstants.INVALID_RETRY_COUNT;
    try {
      final RpcWritable.Buffer buffer = RpcWritable.Buffer.wrap(bb);
      // 解析出RPC请求头
      final RpcRequestHeaderProto header =
          getMessage(RpcRequestHeaderProto.getDefaultInstance(), buffer);
      callId = header.getCallId(); // 解析callId
      retry = header.getRetryCount();// 重试次数
      if (LOG.isDebugEnabled()) {
        LOG.debug(" got #" + callId);
      }
      checkRpcHeaders(header);
      // 如果请求头域异常
      if (callId < 0) { // callIds typically used during connection setup
        processRpcOutOfBandRequest(header, buffer);
      } else if (!connectionContextRead) {
        throw new FatalRpcServerException(
            RpcErrorCodeProto.FATAL_INVALID_RPC_HEADER,
            "Connection context not established");
      } else {
          // 如果请求头域正常工行，则直接调用processRpcRequest处理RPC请求体
        processRpcRequest(header, buffer);
      }
    } catch (RpcServerException rse) { // 直接发回异常，通知Client
      // inform client of error, but do not rethrow else non-fatal
      // exceptions will close connection!
      if (LOG.isDebugEnabled()) {
        LOG.debug(Thread.currentThread().getName() +
            ": processOneRpc from client " + this +
            " threw exception [" + rse + "]");
      }
      // use the wrapped exception if there is one.
      Throwable t = (rse.getCause() != null) ? rse.getCause() : rse;
      final RpcCall call = new RpcCall(this, callId, retry);
      setupResponse(call,
          rse.getRpcStatusProto(), rse.getRpcErrorCodeProto(), null,
          t.getClass().getName(), t.getMessage());
      sendResponse(call);
    }
  }
  ```

  processRpcRequest()会从输入流中解析出完整的请求对象，然后根据RPC请求头信息构造Call对象，最后将这个Call对象放到callQueue保存，等待Handler处理：

  **org.apache.hadoop.ipc.Server.Connection#processRpcRequest**

  ```java
  ...
  Writable rpcRequest;
  try { //Read the rpc request
    rpcRequest = buffer.newInstance(rpcRequestClass, conf);
  } catch (RpcServerException rse) { // lets tests inject failures.
    throw rse;
  } catch (Throwable t) { // includes runtime exception from newInstance
    LOG.warn("Unable to read call parameters for client " +
             getHostAddress() + "on connection protocol " +
        this.protocolName + " for rpcKind " + header.getRpcKind(),  t);
    String err = "IPC server unable to read call parameters: "+ t.getMessage();
    throw new FatalRpcServerException(
        RpcErrorCodeProto.FATAL_DESERIALIZING_REQUEST, err);
  }
    
  TraceScope traceScope = null;
  if (header.hasTraceInfo()) {
    if (tracer != null) {
      // If the incoming RPC included tracing info, always continue the
      // trace
      SpanId parentSpanId = new SpanId(
          header.getTraceInfo().getTraceId(),
          header.getTraceInfo().getParentId());
      traceScope = tracer.newScope(
          RpcClientUtil.toTraceName(rpcRequest.toString()),
          parentSpanId);
      traceScope.detach();
    }
  }
  
  CallerContext callerContext = null;
  if (header.hasCallerContext()) {
    callerContext =
        new CallerContext.Builder(header.getCallerContext().getContext())
            .setSignature(header.getCallerContext().getSignature()
                .toByteArray())
            .build();
  }
    //创建Call对象封装RPC请求信息
  RpcCall call = new RpcCall(this, header.getCallId(),
      header.getRetryCount(), rpcRequest,
      ProtoUtil.convert(header.getRpcKind()),
      header.getClientId().toByteArray(), traceScope, callerContext);
  
  // Save the priority level assignment by the scheduler
  call.setPriorityLevel(callQueue.getPriorityLevel(call));
  
  try {
      // 将call入队
    internalQueueCall(call);
  } catch (RpcServerException rse) {
    throw rse;
      ...
  ```

* Handler类

  Handler类负责执行RPC请求对应的本地函数，然后将结果发回客户端。在Server中有多个Handler线程并发处理RPC请求。

  Handler线程的Run方法会调用Call对象的run方法，其具体实现如下：

  **org.apache.hadoop.ipc.Server.RpcCall#run**

  ```java
  @Override
  public Void run() throws Exception {
    if (!connection.channel.isOpen()) {
      Server.LOG.info(Thread.currentThread().getName() + ": skipped " + this);
      return null;
    }
    String errorClass = null;
    String error = null;
    RpcStatusProto returnStatus = RpcStatusProto.SUCCESS;
    RpcErrorCodeProto detailedErr = null;
    Writable value = null;
  
    try {
      // 调用BlockingService对象的callBlockingMethod()方法
        // 通过call()发起本地调用并返回结果
      value = call(
          rpcKind, connection.protocolName, rpcRequest, timestamp);
    } catch (Throwable e) {
      if (e instanceof UndeclaredThrowableException) {
        e = e.getCause();
      }
      logException(Server.LOG, e, this);
      // 调用过程中发生异常，将异常信息保存下来
      if (e instanceof RpcServerException) {
        RpcServerException rse = ((RpcServerException)e);
        returnStatus = rse.getRpcStatusProto();
        detailedErr = rse.getRpcErrorCodeProto();
      } else {
        returnStatus = RpcStatusProto.ERROR;
        detailedErr = RpcErrorCodeProto.ERROR_APPLICATION;
      }
      errorClass = e.getClass().getName();
      error = StringUtils.stringifyException(e);
      // Remove redundant error class name from the beginning of the
      // stack trace
      String exceptionHdr = errorClass + ": ";
      if (error.startsWith(exceptionHdr)) {
        error = error.substring(exceptionHdr.length());
      }
    }
    // 构造RPC响应， 如果正常就返回结果，否则返回异常
    setupResponse(this, returnStatus, detailedErr,
        value, errorClass, error);
    // 返回响应
    sendResponse();
    return null;
  }
  ```