---
title: Hadoop源码阅读——Hadoop RPC(二)
date: 2018-11-26 19:08:21
tags: [Hadoop,HDFS,大数据]
---

[书接上回](https://harold1994.github.io/2018/11/16/Hadoop%E6%BA%90%E7%A0%81%E9%98%85%E8%AF%BB%E2%80%94%E2%80%94RPC/)，继续Hadoop RPC源码分析，Hadoop RPC框架的抽象步骤：

- 定义RPC协议：只有定一个RPC协议，客户端才知道服务端对外提供了哪些服务
- 实现RPC协议：服务端的服务程序需要实现RPC协议。当RPC调用通过网络到达服务器时，实现RPC协议的服务程序会响应这个调用。
- 客户端获取代理对象：
- 服务器构造并启动RPC Server

##### 4. 服务器获取Server对象

RPC服务器需要构造一个Server对象，这个对象用于监听并响应来自RPc客户端的请求。Namenode会构造两个Server对象来分别响应来自HDFS客户端和Datanode的RPC请求。

<!-- more--> 

###### a. 构造NameNodeRPCServer

NameNodeRPCServer实现了NamenodeProtocols接口，NamenodeProtocols继承以下几个类：

```java
public interface NamenodeProtocols
  extends ClientProtocol,
          DatanodeProtocol,
          DatanodeLifelineProtocol,
          NamenodeProtocol,
          RefreshAuthorizationPolicyProtocol,
          RefreshUserMappingsProtocol,
          RefreshCallQueueProtocol,
          GenericRefreshProtocol,
          GetUserMappingsProtocol,
          HAServiceProtocol,
          TraceAdminProtocol {
}
```

Namenode会在它的初始化方法initialize()中调用createRpcServer()创建NameNodeRPCServer对象的实例，createRpcServer()方法会直接调用NameNodeRpcServer的构造方法。

```java
public NameNodeRpcServer(Configuration conf, NameNode nn)
    throws IOException {
  this.nn = nn;
  this.namesystem = nn.getNamesystem();
  this.retryCache = namesystem.getRetryCache();
  this.metrics = NameNode.getNameNodeMetrics();
  
  int handlerCount = 
    conf.getInt(DFS_NAMENODE_HANDLER_COUNT_KEY,
                DFS_NAMENODE_HANDLER_COUNT_DEFAULT);
  // 先设置RPC类的序列化引擎为protobuf
  RPC.setProtocolEngine(conf, ClientNamenodeProtocolPB.class,
      ProtobufRpcEngine.class);
  // 构造ClientNamenodeProtocolServerSideTranslatorPB对象
  // 用于适配ClientNamenodeProtocolPB到ClientNamenodeProtoco接口的转换
  ClientNamenodeProtocolServerSideTranslatorPB 
     clientProtocolServerTranslator = 
       new ClientNamenodeProtocolServerSideTranslatorPB(this);
  // 构造clientNNPbService对象
  // 用于将Server提取的请求转到clientProtocolServerTranslator对象
   BlockingService clientNNPbService = ClientNamenodeProtocol.
       newReflectiveBlockingService(clientProtocolServerTranslator);
...
  InetSocketAddress serviceRpcAddr = nn.getServiceRpcServerAddress(conf);
  if (serviceRpcAddr != null) {
    String bindHost = nn.getServiceRpcServerBindHost(conf);
    if (bindHost == null) {
      bindHost = serviceRpcAddr.getHostName();
    }
    LOG.info("Service RPC server is binding to " + bindHost + ":" +
        serviceRpcAddr.getPort());

    int serviceHandlerCount =
      conf.getInt(DFS_NAMENODE_SERVICE_HANDLER_COUNT_KEY,
                  DFS_NAMENODE_SERVICE_HANDLER_COUNT_DEFAULT);
    // 构建serviceRpcServer，并配置ClientProtocolPB响应类为clientNNPbService
    this.serviceRpcServer = new RPC.Builder(conf)
        .setProtocol(
            org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolPB.class)
        .setInstance(clientNNPbService)
        .setBindAddress(bindHost)
        .setPort(serviceRpcAddr.getPort()).setNumHandlers(serviceHandlerCount)
        .setVerbose(false)
        .setSecretManager(namesystem.getDelegationTokenSecretManager())
        .build();

    // Add all the RPC protocols that the namenode implements
    // 添加协议与BlockingService对象之间的关系
    // 确保RPC请求到了Server之后，Server可以找到正确的响应类。
    DFSUtil.addPBProtocol(conf, HAServiceProtocolPB.class, haPbService,
        serviceRpcServer);
...

  InetSocketAddress rpcAddr = nn.getRpcServerAddress(conf);
  String bindHost = nn.getRpcServerBindHost(conf);
  if (bindHost == null) {
    bindHost = rpcAddr.getHostName();
  }
  LOG.info("RPC server is binding to " + bindHost + ":" + rpcAddr.getPort());
  // 配置clientRpcServer，响应HDFS客户端的RPC请求
  this.clientRpcServer = new RPC.Builder(conf)
      .setProtocol(
          org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolPB.class)
      .setInstance(clientNNPbService).setBindAddress(bindHost)
      .setPort(rpcAddr.getPort()).setNumHandlers(handlerCount)
      .setVerbose(false)
      .setSecretManager(namesystem.getDelegationTokenSecretManager()).build();

  // Add all the RPC protocols that the namenode implements
  DFSUtil.addPBProtocol(conf, HAServiceProtocolPB.class, haPbService,
      clientRpcServer);
  ...
```

整个构造流程可以分为两个部分：

* 获取响应ClientNamenodeProtocolPB请求的BlockingService对象
* 构造RPC.Server

#### 三、Hadoop RPC实现

Hadoop RPC框架主要由三个类组成：RPC、Client和Server类。

##### 1. RPC类实现

![屏幕快照 2018-11-26 下午9.32.19.png](https://i.loli.net/2018/11/26/5bfbf5f75cd3e.png)

* 客户端：

  客户端程序可以调用waitForProxy()和getProxy()方法获取指定RPC协议的代理对象，之后就可以调用代理对象方法发送请求到Server端

* 服务器端：

  服务器端，服务程序会调用Builder.build()方法撞见一个RPC.Server类，之后调用RPC.Server.start()方法启动Server对象监听并响应RPC请求。

##### 2. Client类实现

DFSClient会获取一个ClientProtocolPB协议的代理对象，并在这个对象上调用RPC方法，代理对象会调用org.apache.hadoop.ipc.Client.call()方法将序列化之后的请求发送到Server。

###### a. Client发送请求与接收响应流程

```java
Writable call(RPC.RpcKind rpcKind, Writable rpcRequest,
    ConnectionId remoteId, int serviceClass,
    AtomicBoolean fallbackToSimpleAuth) throws IOException {
  // 构造Call对象，将请求封装成一个Call对象
  final Call call = createCall(rpcKind, rpcRequest);
  // 创建一个Connection，用于管理Client与Server的连接
  final Connection connection = getConnection(remoteId, call, serviceClass,
      fallbackToSimpleAuth);

  try {
    checkAsyncCall();
    try {
      connection.sendRpcRequest(call);                 // send the rpc request
    } catch (RejectedExecutionException e) {
      throw new IOException("connection has been closed", e);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      LOG.warn("interrupted waiting to send rpc request to server", e);
      throw new IOException(e);
    }
  } catch(Exception e) {
    if (isAsynchronousMode()) {
      releaseAsyncCall();
    }
    throw e;
  }
  // 异步模式
  if (isAsynchronousMode()) {
    final AsyncGet<Writable, IOException> asyncGet
        = new AsyncGet<Writable, IOException>() {
      @Override
      public Writable get(long timeout, TimeUnit unit)
          throws IOException, TimeoutException{
        boolean done = true;
        try {
            // 获取Server的响应
          final Writable w = getRpcResponse(call, connection, timeout, unit);
          if (w == null) {
            done = false;
            throw new TimeoutException(call + " timed out "
                + timeout + " " + unit);
          }
          return w;
        } finally {
          if (done) {
            releaseAsyncCall();
          }
        }
      }

      @Override
      public boolean isDone() {
        synchronized (call) {
          return call.done;
        }
      }
    };

    ASYNC_RPC_RESPONSE.set(asyncGet);
    return null;
  } else {
      // 同步模式，返回Serve的响应值，如果超时则返回null
    return getRpcResponse(call, connection, -1, null);
  }
}
```

![WechatIMG15.jpeg](https://i.loli.net/2018/11/27/5bfca1130abce.jpeg)

* org.apache.hadoop.ipc.Client#getRpcResponse

  ```java
  private Writable getRpcResponse(final Call call, final Connection connection,
      final long timeout, final TimeUnit unit) throws IOException {
    synchronized (call) {
        // 如果还在执行，则调用wait方法等待timeout
      while (!call.done) {
        try {
          AsyncGet.Util.wait(call, timeout, unit);
          // 如果等待时间过了或者等待时间为0，返回null
            // 如果timeout设置为小于0，则一直等到interrupt()方法唤醒线程
          if (timeout >= 0 && !call.done) {
            return null;
          }
        } catch (InterruptedException ie) {
          Thread.currentThread().interrupt();
          throw new InterruptedIOException("Call interrupted");
        }
      }
  
      if (call.error != null) {// 发送线程被唤醒，但是Server处理RPC请求时出现异常，从Call对象中获取异常并抛出
        if (call.error instanceof RemoteException) {
          call.error.fillInStackTrace();
          throw call.error;
        } else { // local exception
          InetSocketAddress address = connection.getRemoteAddress();
          throw NetUtils.wrapException(address.getHostName(),
                  address.getPort(),
                  NetUtils.getHostname(),
                  0,
                  call.error);
        }
      } else {
          // 服务器成功发回响应信息，返回RPC响应
        return call.getRpcResponse();
      }
    }
  }
  ```

###### b. 内部类——Call

RPC.Client中发送请求和接收响应由两个独立线程进行，发送请求线程就是调用Client.call()方法的线程，而接收响应线程则是call()启动的Connection线程。

> e.g 线程1调用Client.call()发送RPC请求到Server，然后再这个请求对应的Call对象上调用Call.wait()
>
> 方法等待Server发回响应信息， 当线程2从Server接收了响应信息后，会设置Call.rpcResponse字段保存响应信息，并调用Call.notify()方法唤醒线程1.线程1被唤醒后会取出Call.rpcResponse字段中记录的响应信息。

Call对象标识了一个RPC请求，定义了如下字段：

```java
final int id;               // call id
final int retry;           // retry count
final Writable rpcRequest;  // the serialized rpc request
Writable rpcResponse;       // null if rpc has error
IOException error;          // exception, null if success
final RPC.RpcKind rpcKind;      // Rpc EngineKind
```

接收线程对Server结果的响应方法：

```java
/** Set the exception when there is an error.
 * Notify the caller the call is done.
 *  如果Server执行出现异常
 * @param error exception thrown by the call; either local or remote
 */
public synchronized void setException(IOException error) {
  this.error = error; // 保存异常信息
  callComplete(); // 调用callComplete()方法唤醒在Call对象上等待的线程
}

/** Set the return value when there is no error. 
 * Notify the caller the call is done.
 * 如果Server成功执行并返回响应
 * @param rpcResponse return value of the rpc call.
 */
public synchronized void setRpcResponse(Writable rpcResponse) {
  this.rpcResponse = rpcResponse;
  callComplete();
}

/** Indicate when the call is complete and the
     * value or error are available.  Notifies by default.  */
    protected synchronized void callComplete() {
      this.done = true;
      notify();                                 // 唤醒在Call对象上等待的线程

      if (externalHandler != null) {
        synchronized (externalHandler) {
          externalHandler.notify();
        }
      }
    }
```

###### c. 内部类——Connection

Connection类继承了Thread类，注释上的功能介绍是：

```
读取响应并通知呼叫者的线程。每个连接都拥有一个连接到远程地址的套接字。呼叫通过此套接字进行多路复用：响应可能无序传递。
```

定义字段如下：

```java
private InetSocketAddress server;             // server ip:port
private final ConnectionId remoteId;                // connection id
private AuthMethod authMethod; // authentication method
private AuthProtocol authProtocol;
private int serviceClass;
private SaslRpcClient saslRpcClient;

private Socket socket = null;                 // connected socket
private IpcStreams ipcStreams; // 管理IPC通信的输入输出流
private final int maxResponseLength;
private final int rpcTimeout;
private int maxIdleTime; //connections will be culled if it was idle for 
//maxIdleTime msecs 最长空闲时间
private final RetryPolicy connectionRetryPolicy;
private final int maxRetriesOnSasl;
private int maxRetriesOnSocketTimeouts;
private final boolean tcpNoDelay; // if T then disable Nagle's Algorithm
private final boolean tcpLowLatency; // if T then use low-delay QoS
private final boolean doPing; //do we need to send ping message
private final int pingInterval; // how often sends ping to the server
private final int soTimeout; // used by ipc ping and rpc timeout
private byte[] pingRequest; // ping message

// currently active calls
// 使用这个Connection发送的请求
private Hashtable<Integer, Call> calls = new Hashtable<Integer, Call>();
private AtomicLong lastActivity = new AtomicLong();// last I/O activity time
private AtomicBoolean shouldCloseConnection = new AtomicBoolean();  // indicate if the connection is closed
private IOException closeException; // close reason
```

Client.call()方法首先调用getConnection()方法获取一个Connection对象，getConnection()方法会首先从org.apache.hadoop.ipc.Client#connections字段上 中提取缓存的Connection对象，connections是ConcurrentMap<ConnectionId, Connection>类型的，用于将已成功建立Socket连接的Connection对象缓存起来，这是因为Connection中与Server建立Socket连接的过程十分耗费资源。因此用connections保存未过期的Cinnection对象。如果connections中没有缓存则调用Connection的构造方法创建一个新Connection，并加入connections中保存。成功获取Connection后，getConnection()方法会调用addCall()方法将待发送的RPC请求对象Call添加到Connection对象的请求队列calls中。然后调用setupIOstreams()方法方法初始化到Server的Socket连接并获取IO流。

* org.apache.hadoop.ipc.Client#getConnection

  ```java
  private Connection getConnection(ConnectionId remoteId,
      Call call, int serviceClass, AtomicBoolean fallbackToSimpleAuth)
      throws IOException {
    if (!running.get()) {
      // the client is stopped
      throw new IOException("The client is stopped");
    }
    Connection connection;
    /* we could avoid this allocation for each RPC by having a  
     * connectionsId object and with set() method. We need to manage the
     * refs for keys in HashMap properly. For now its ok.
     */
    while (true) {
      // These lines below can be shorten with computeIfAbsent in Java8
        // connections是一个ConcurrentHashMap，存储没有过期的Connection
      connection = connections.get(remoteId);
      if (connection == null) {
        connection = new Connection(remoteId, serviceClass);
        Connection existing = connections.putIfAbsent(remoteId, connection);
        if (existing != null) {
          connection = existing;
        }
      }
      // 将待发送的RPC请求对象Call添加到Connection对象的请求队列calls中。
      if (connection.addCall(call)) {
        break;
      } else {
        // This connection is closed, should be removed. But other thread could
        // have already known this closedConnection, and replace it with a new
        // connection. So we should call conditional remove to make sure we only
        // remove this closedConnection.
        connections.remove(remoteId, connection);
      }
    }
  
    // If the server happens to be slow, the method below will take longer to
    // establish a connection.
    // 调用setupIOstreams()方法方法初始化到Server的Socket连接并获取IO流
    connection.setupIOstreams(fallbackToSimpleAuth);
    return connection;
  }
  ```

* org.apache.hadoop.ipc.Client.Connection#setupIOstreams

  ```java
  // 建立与Server的连接,向服务器发送一个连接头
  // 启动Connection线程，监听Socket并读取Server返回的响应信息
  private synchronized void setupIOstreams(
      AtomicBoolean fallbackToSimpleAuth) {
    if (socket != null || shouldCloseConnection.get()) {
      return;
    }
  ...
      while (true) {
          // 1. 调用setupConnection()，建立到远程服务器的连接
        setupConnection(ticket);
        ipcStreams = new IpcStreams(socket, maxResponseLength);
        // 2. 发送连接头域
        writeConnectionHeader(ipcStreams);
        ...
          // 3. 包装输入输出流
        if (doPing) {
          ipcStreams.setInputStream(new PingInputStream(ipcStreams.in));
        }
          // 4 . 写入连接上下文头域
        writeConnectionContext(remoteId, authMethod);
  
        // update last activity time
          // 5. 更新上次活跃时间
        touch();
  
        span = Tracer.getCurrentSpan();
        if (span != null) {
          span.addTimelineAnnotation("IPC client connected to " + server);
        }
  
        // start the receiver thread after the socket connection has been set
        // up
          // 6. 启动connection线程
        start();
        return;
      }
    } catch (Throwable t) {
      if (t instanceof IOException) {
        markClosed((IOException)t);
      } else {
        markClosed(new IOException("Couldn't set up IO streams: " + t, t));
      }
      close();
    }
  }
  ```

* 发送请求：org.apache.hadoop.ipc.Client.Connection#sendRpcRequest

```java
/** Initiates a rpc call by sending the rpc request to the remote server.
 * Note: this is not called from the Connection thread, but by other
 * threads.
 * 这个方法不是由Cinnection线程调用，而是由发起RPC请求的线程调用
 * @param call - the rpc request
 */
public void sendRpcRequest(final Call call)
    throws InterruptedException, IOException {
  if (shouldCloseConnection.get()) {
    return;
  }

  // Serialize the call to be sent. This is done from the actual
  // caller thread, rather than the sendParamsExecutor thread,
  
  // so that if the serialization throws an error, it is reported
  // properly. This also parallelizes the serialization.
  //
  // Format of a call on the wire:
  // 0) Length of rest below (1 + 2)
  // 1) RpcRequestHeader  - is serialized Delimited hence contains length
  // 2) RpcRequest
  //
  // Items '1' and '2' are prepared here.
    // 构造RPC请求头
  RpcRequestHeaderProto header = ProtoUtil.makeRpcRequestHeader(
      call.rpcKind, OperationProto.RPC_FINAL_PACKET, call.id, call.retry,
      clientId);

  final ResponseBuffer buf = new ResponseBuffer();
  // 将RPC流写入输出流
  header.writeDelimitedTo(buf);
  // 将RPC请求(包括元数据和请求参数)写入数据流
  RpcWritable.wrap(call.rpcRequest).writeTo(buf);
    // 用线程池将请求发送出去，请求包括三个部分：
    // 0) Length of rest below (1 + 2)
    // 1) RpcRequestHeader  - is serialized Delimited hence contains length
    // 2) RpcRequest(包括请求元数据和请求参数)
  synchronized (sendRpcRequestLock) {
    Future<?> senderFuture = sendParamsExecutor.submit(new Runnable() {
      @Override
      public void run() {
        try {
          synchronized (ipcStreams.out) {
            if (shouldCloseConnection.get()) {
              return;
            }
            if (LOG.isDebugEnabled()) {
              LOG.debug(getName() + " sending #" + call.id
                  + " " + call.rpcRequest);
            }
            // RpcRequestHeader + RpcRequest
            ipcStreams.sendRequest(buf.toByteArray());
            ipcStreams.flush();
          }
        } catch (IOException e) {
          // exception at this point would leave the connection in an
          // unrecoverable state (eg half a call left on the wire).
          // So, close the connection, killing any outstanding calls
            // 如果发生异常，直接关闭连接
          markClosed(e);
        } finally {
          //the buffer is just an in-memory buffer, but it is still polite to
          // close early
          IOUtils.closeStream(buf);
        }
      }
    });
  
    try {
        // 获取结果
      senderFuture.get();
    } catch (ExecutionException e) {
      Throwable cause = e.getCause();
      
      // cause should only be a RuntimeException as the Runnable above
      // catches IOException
      if (cause instanceof RuntimeException) {
        throw (RuntimeException) cause;
      } else {
        throw new RuntimeException("unexpected checked exception", cause);
      }
    }
  }
}
```

Client向Server发送的一个完整RPC请求格式如下图：

![屏幕快照 2018-12-02 下午10.43.01.png](https://i.loli.net/2018/12/02/5c03ef9383072.png)

​	Length:每个protobuf类型都包含一个length字段，在HDFS写入时，使用了writeDelimitedTo()方法，这个方法会先写入数据的length，然后写入数据

​	RpcRequestHeaderProto：RPC调用头域，Server发回的响应消息中会带回callid，clientid等信息，用于提取call鉴权等。

* 接收响应：org.apache.hadoop.ipc.Client.Connection#run

  Connection线程负责监听并接收从Server发回的RPC响应。Connection.run()方法会调用waitForWork()等待执行读取操作，等待结束后调用receiveRpcResponse()方法接收RPC响应。

  ```java
  @Override
  public void run() {
    if (LOG.isDebugEnabled())
      LOG.debug(getName() + ": starting, having connections " 
          + connections.size());
  
    try {
      while (waitForWork()) {//wait here for work - read or close connection
        // 接收响应
        receiveRpcResponse();
      }
    } catch (Throwable t) {
      // This truly is unexpected, since we catch IOException in receiveResponse
      // -- this is only to be really sure that we don't leave a client hanging
      // forever.
      LOG.warn("Unexpected error reading responses on connection " + this, t);
      markClosed(new IOException("Error reading responses", t));
    }
    // 关闭连接
    close();
    
    if (LOG.isDebugEnabled())
      LOG.debug(getName() + ": stopped, remaining connections "
          + connections.size());
  }
  ```

  waitForWork方法判断当前Connection的calls队列是否有Call对象，如果没有（说明Connection空闲）则等待maxIdleTime,等待之后还没有数据，则返回false，且关闭Connection对象。

  ```java
  /* wait till someone signals us to start reading RPC response or
   * it is idle too long, it is marked as to be closed, 
   * or the client is marked as not running.
   * 
   * Return true if it is time to read a response; false otherwise.
   */
  private synchronized boolean waitForWork() {
    if (calls.isEmpty() && !shouldCloseConnection.get()  && running.get())  {
      long timeout = maxIdleTime-
            (Time.now()-lastActivity.get());
      if (timeout>0) {
        try {
          wait(timeout);
        } catch (InterruptedException e) {}
      }
    }
    
    if (!calls.isEmpty() && !shouldCloseConnection.get() && running.get()) {
      return true;
    } else if (shouldCloseConnection.get()) {
      return false;
    } else if (calls.isEmpty()) { // idle connection closed or stopped关闭空闲连接
      markClosed(null);
      return false;
    } else { // get stopped but there are still pending requests 
      // 仍有待处理的请求但是连接被关闭了
      markClosed((IOException)new IOException().initCause(
          new InterruptedException()));
      return false;
    }
  }
  ```

  等待结束后，receiveRpcResponse会从输入流中读取序列化对象RpcResponseHeaderProto，然后根据RpcResponseHeaderProto中记录的callId字段获取对应的Call对象，接下来会从输入流中读取响应消息，然后调用call.setRpcResponse(value)将消息保存在Call对象中。如果Server在处理RPC请求时抛出异常，则receiveRpcResponse会从输入流中读取异常信息，并构造异常对象，然后调用call.setException(re)，将异常保存在call中。

  ```java
  /* Receive a response.
   * Because only one receiver, so no synchronization on in.
   */
  private void receiveRpcResponse() {
    if (shouldCloseConnection.get()) {
      return;
    }
    touch();
    
    try {
      ByteBuffer bb = ipcStreams.readResponse();
      RpcWritable.Buffer packet = RpcWritable.Buffer.wrap(bb);
      RpcResponseHeaderProto header =
          packet.getValue(RpcResponseHeaderProto.getDefaultInstance());
      checkResponse(header);
  
      int callId = header.getCallId();
      if (LOG.isDebugEnabled())
        LOG.debug(getName() + " got value #" + callId);
  
      RpcStatusProto status = header.getStatus();
      // 如果调用成功，则读取响应信息，在call实例中设置
      if (status == RpcStatusProto.SUCCESS) {
        Writable value = packet.newInstance(valueClass, conf);// 读取响应消息
        final Call call = calls.remove(callId);
        call.setRpcResponse(value);
      }
      // verify that packet length was correct
      if (packet.remaining() > 0) {
        throw new RpcClientException("RPC response length mismatch");
      }
      // 调用失败
      if (status != RpcStatusProto.SUCCESS) { // Rpc Request failed
        // 读取异常信息
        final String exceptionClassName = header.hasExceptionClassName() ?
              header.getExceptionClassName() : 
                "ServerDidNotSetExceptionClassName";
        final String errorMsg = header.hasErrorMsg() ? 
              header.getErrorMsg() : "ServerDidNotSetErrorMsg" ;
        final RpcErrorCodeProto erCode = 
                  (header.hasErrorDetail() ? header.getErrorDetail() : null);
        if (erCode == null) {
           LOG.warn("Detailed error code not set by server on rpc error");
        }
        // 构造异常
        RemoteException re = new RemoteException(exceptionClassName, errorMsg, erCode);
        if (status == RpcStatusProto.ERROR) {
          final Call call = calls.remove(callId);
          call.setException(re);
        } else if (status == RpcStatusProto.FATAL) {
          // Close the connection
          markClosed(re);
        }
      }
    } catch (IOException e) {
      markClosed(e);
    }
  }
  ```

  保存好响应消息或者异常之后，在Call对象上调用notify()方法，等待的发送请求线程会被唤醒，Client.call()方法会调用getRpcResponse从Call对象上取出保存的消息或者异常，若是消息则返回，是异常则抛出。

  ```java
  private Writable getRpcResponse(final Call call, final Connection connection,
      final long timeout, final TimeUnit unit) throws IOException {
    synchronized (call) {
        // 如果还在执行，则调用wait方法等待timeout
      while (!call.done) {
        try {
          AsyncGet.Util.wait(call, timeout, unit);
          // 如果等待时间过了或者等待时间为0，返回null
            // 如果timeout设置为小于0，则一直等到interrupt()方法唤醒线程
          if (timeout >= 0 && !call.done) {
            return null;
          }
        } catch (InterruptedException ie) {
          Thread.currentThread().interrupt();
          throw new InterruptedIOException("Call interrupted");
        }
      }
  
      if (call.error != null) {// 发送线程被唤醒，但是Server处理RPC请求时出现异常，从Call对象中获取异常并抛出
        if (call.error instanceof RemoteException) {
          call.error.fillInStackTrace();
          throw call.error;
        } else { // local exception
          InetSocketAddress address = connection.getRemoteAddress();
          throw NetUtils.wrapException(address.getHostName(),
                  address.getPort(),
                  NetUtils.getHostname(),
                  0,
                  call.error);
        }
      } else {
          // 服务器成功发回响应信息，返回RPC响应
        return call.getRpcResponse();
      }
    }
  }
  ```

