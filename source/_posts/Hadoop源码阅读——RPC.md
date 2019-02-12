---
title: Hadoop源码阅读——Hadoop RPC(一)
date: 2018-11-16 19:17:53
tags: [Hadoop,HDFS,大数据]
---

HadoopRPC框架基于IPC模型实现了一套轻量级RPC框架，底层采用了JavaNIO、Java动态代理以及protobuf等基础技术。

RPC(远程过程调用协议)是一种通过网络调用远程计算服务的协议。RPC采用客户端/服务端模式，请求程序就是一个客户端，而服务提供程序就是一个服务端。

![nnpg4.jpg](https://i.loli.net/2018/11/20/5bf4109e86d6d.jpg)

<!-- more--> 

#### 一、Hadoop RPC框架

##### 1. 通信模块

Hadoop实现了org.apache.hadoop.ipc.Client和org.apache.hadoop.ipc.Server类提供的基于TCP/IP Socket的网络通信功能。客户端使用Client类将序列化的请求发送到远程服务器，服务器通过Server类接受来自客户端的请求。

客户端在发送请求前先将请求序列化，然后调用Client.call()方法发送请求到服务端。

```java
/** 
 * Make a call, passing <code>rpcRequest</code>, to the IPC server defined by
 * <code>remoteId</code>, returning the rpc respond.
 *
 * @param rpcKind
 * @param rpcRequest -  contains serialized method and method parameters
 * @param remoteId - the target rpc server
 * @param fallbackToSimpleAuth - set to true or false during this method to
 *   indicate if a secure client falls back to simple auth
 * @returns the rpc response
 * Throws exceptions if there are network problems or if the remote code
 * threw an exception.
 */
public Writable call(RPC.RpcKind rpcKind, Writable rpcRequest,
    ConnectionId remoteId, AtomicBoolean fallbackToSimpleAuth)
    throws IOException {
    ...
```

HadoopRPC允许客户端配置使用不同的序列化框架序列化RPC请求，rpcKind用于描述RPC请求的序列化工具类。rpcRequest记录序列化后的RPC请求。

Server接收到一个RPC请求后，会调用call()方法相应这个请求：

```java
public abstract Writable call(RPC.RpcKind rpcKind, String protocol,
    Writable param, long receiveTime) throws Exception;
```

##### 2.客户端Stub

客户端Stub可以看作是一个代理对象，它会将请求程序的RPC调用序列化，并调用Client.call()方法。

Hadoop2.X默认使用protobuf作为序列化工具，Hadoop RPC也支持其他序列化框架，Hadoop定义了RpcEngine接口抽象使用不同序列化框架的的RPC引擎。

![屏幕快照 2018-11-20 下午10.43.16.png](https://i.loli.net/2018/11/20/5bf41d978869c.png)

* getProxy:客户端调用这个方法获取一个本地接口的代理对象，然后在这个代理对象上调用本地接口的方法。
* getServer：用于产生一个RPC Server对象，，服务器会启用这个Server对象监听来自客户端的请求。

##### 3. 服务器端Stub

服务端Stub会将通信模块接收的数据反序列化，然后调用服务器call()方法来响应这个请求。

```java
public Writable call(RPC.RpcKind rpcKind, String protocol,
    Writable rpcRequest, long receiveTime) throws Exception {
  return getRpcInvoker(rpcKind).call(this, protocol, rpcRequest,
      receiveTime);
}
```

不同的RpcEngine会实现自己的Server子类，Server内部又会实现一个RpcInvoker对象，它会反序列化请求，然后调用服务相应该请求。

服务器端调用org.apache.hadoop.ipc.RPC.Builder#build方法获取Server对象的引用。

```java
 // build（）是一个工厂方法，
  public Server build() throws IOException, HadoopIllegalArgumentException {
      // 先检查工厂参数是否设置
    if (this.conf == null) {
      throw new HadoopIllegalArgumentException("conf is not set");
    }
    if (this.protocol == null) {
      throw new HadoopIllegalArgumentException("protocol is not set");
    }
    if (this.instance == null) {
      throw new HadoopIllegalArgumentException("instance is not set");
    }
    // 再调用getProtocolEngine()获取特定序列化框架
      // 最后getServer()方法返回Server类
    return getProtocolEngine(this.protocol, this.conf).getServer(
        this.protocol, this.instance, this.bindAddress, this.port,
        this.numHandlers, this.numReaders, this.queueSizePerHandler,
        this.verbose, this.conf, this.secretManager, this.portRangeConfig);
  }
}
```

#### 二、Hadoop RPC的使用

##### 1.RPC 使用概述

关于RPC的使用用下面ClientProtocol.rename()调用为例子，直接贴图，方便日后回味。

![WechatIMG8.jpeg](https://i.loli.net/2018/11/21/5bf571dabf06c.jpeg)

![WechatIMG9.jpeg](https://i.loli.net/2018/11/21/5bf571daaf959.jpeg)

![WechatIMG10.jpeg](https://i.loli.net/2018/11/21/5bf571daaa41c.jpeg)

Hadoop RPC框架的抽象步骤：

* 定义RPC协议：只有定一个RPC协议，客户端才知道服务端对外提供了哪些服务
* 实现RPC协议：服务端的服务程序需要实现RPC协议。当RPC调用通过网络到达服务器时，实现RPC协议的服务程序会响应这个调用。
* 客户端获取代理对象：
* 服务器构造并启动RPC Server

下面继续以ClientProtocal为例，介绍这些支持类的代码实现。

##### 2. 定义RPC协议

###### a. ClientProtocol协议

![屏幕快照 2018-11-22 下午9.08.19.png](https://i.loli.net/2018/11/22/5bf6aa587a67d.png)

* ClientNamenodeProtocolTranslatorPB：将客户端请求参数封装成可以序列化的protobuf格式，然后通过代理类发送出去
* NameNodeRpcServer：NameNode侧响应ClientProtocol调用的类

###### b. ClientNamenodeProtocolPB协议

ClientNamenodeProtocolPB协议对ClientProtocol协议中方法的参数和返回值进行包装，使其可序列化。ClientNamenodeProtocolPB协议定义的方法与ClientProtocol一致，可以理解为用protobuf定义参数和返回值的ClientProto协议。

ClientNamenodeProtocolPB协议由ClientNamenodeProtocol.proto生成，与rename()方法相关的几处代码：

```protobuf
...
message RenameRequestProto {
  required string src = 1; // rename()方法的第一个参数src
  required string dst = 2; // rename()方法的第二个参数dst
}

message RenameResponseProto {
  required bool result = 1; // 封装rename返回结果
}
...
rpc rename(RenameRequestProto) returns(RenameResponseProto);
```

* org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolPB

```java
@InterfaceAudience.Private
@InterfaceStability.Stable
@KerberosInfo(
    serverPrincipal = HdfsClientConfigKeys.DFS_NAMENODE_KERBEROS_PRINCIPAL_KEY)
@TokenInfo(DelegationTokenSelector.class)
@ProtocolInfo(protocolName = HdfsConstants.CLIENT_NAMENODE_PROTOCOL_NAME,
    protocolVersion = 1)
/**
 * Protocol that a clients use to communicate with the NameNode.
 *
 * Note: This extends the protocolbuffer service based interface to
 * add annotations required for security.
 */
// ClientNamenodeProtocolPB接口是ClientNamenodeProtocol.BlockingInterface接口的子类
// 而不是直接使用ClientNamenodeProtocol作为序列化协议是为了添加Annotation支持
// ClientNamenodeProtocol是由protobuf工具生成的RPC调用的接口类
public interface ClientNamenodeProtocolPB extends
    ClientNamenodeProtocol.BlockingInterface {
}
```

###### c. ClientNamenodeProtocolTranslatorPB类

ClientNamenodeProtocolTranslatorPB实现了ClientProtocol接口，并拥有一个ClientNamenodeProtocolPB类型的rpcProxy对象。

```java
/**
 * This class forwards NN's ClientProtocol calls as RPC calls to the NN server
 * while translating from the parameter types used in ClientProtocol to the
 * new PB types.
 */
@InterfaceAudience.Private
@InterfaceStability.Stable
public class ClientNamenodeProtocolTranslatorPB implements
    ProtocolMetaInterface, ClientProtocol, Closeable, ProtocolTranslator {
  final private ClientNamenodeProtocolPB rpcProxy;
```

ClientNamenodeProtocolTranslatorPB将ClientProtocol请求的参数序列化，然后调用rpcProxy对象上的对应方法。

```java
@Override
public boolean rename(String src, String dst) throws IOException {
  // 构建PB参数
  RenameRequestProto req = RenameRequestProto.newBuilder()
      .setSrc(src)
      .setDst(dst).build();

  try {
    // 调用底层方法并返回
    return rpcProxy.rename(null, req).getResult();
  } catch (ServiceException e) {
    throw ProtobufHelper.getRemoteException(e);
  }
}
```

###### d. ClientNamenodeProtocolServerSideTranslatorPB类

ClientNamenodeProtocolServerSideTranslatorPB是是RPC Server侧的适配器类，将ClientNamenodeProtocolPB请求转换为ClientProtocol请求。

```java
/**
 * This class is used on the server side. Calls come across the wire for the
 * for protocol {@link ClientNamenodeProtocolPB}.
 * This class translates the PB data types
 * to the native data types used inside the NN as specified in the generic
 * ClientProtocol.
 */
@InterfaceAudience.Private
@InterfaceStability.Stable
public class ClientNamenodeProtocolServerSideTranslatorPB implements
    ClientNamenodeProtocolPB {
  final private ClientProtocol server;
    ...
```

先反序列化参数再执行本地方法，最后再将返回值序列化并返回：

```java
@Override
public RenameResponseProto rename(RpcController controller,
    RenameRequestProto req) throws ServiceException {
  try {
    boolean result = server.rename(req.getSrc(), req.getDst());
    return RenameResponseProto.newBuilder().setResult(result).build();
  } catch (IOException e) {
    throw new ServiceException(e);
  }
}
```

##### 3. 客户端获取Proxy对象

DFSClient持有一个ClientProtocol对象向NameNode发送请求。这个对象其实是ClientNamenodeProtocolTranslatorPB的实例，ClientNamenodeProtocolTranslatorPB持有一个实现了ClientNamenodeProtocolPB接口的对象，这个对象是通过Java动态代理机制获取的ClientNamenodeProtocolPB接口的代理对象。

**在ClientNamenodeProtocolPB代理对象上的调用都会通过ProtobufRpcEngine.Invoker对象代理，Invoker对象会创建请求头，然后调用RPC.Client.call()方法将请求头和序列化后的参数发送到服务端。**

通过DFSClient.rename()方法分析：

###### a. DFSClient在namenode引用上调用rename2()方法

```java
// namenode字段保存一个ClientProtocol引用
final ClientProtocol namenode;
...
// 构造方法
this.namenode = proxyInfo.getProxy();   
// 创建支持或者不支持HA模式的ClientProtocol代理对象，根据nameNodeUri来判断返回哪种代理对象
proxyInfo = NameNodeProxiesClient.createProxyWithClientProtocol(conf,
          nameNodeUri, nnFallbackToSimpleAuth);    
...
public void rename(String src, String dst, Options.Rename... options)
      throws IOException {
    checkOpen();
    try (TraceScope ignored = newSrcDstTraceScope("rename2", src, dst)) {
      namenode.rename2(src, dst, options);
    }
    ...
```

Hadoop2.X引入了HA机制，同一时刻DFSClient只会将ClientProtocol RPC请求发送给集群中的Active NameNode，NameNodeProxiesClient.createProxyWithClientProtocol用于构建支持HA模式的ClientProtocol代理对象，它会根据配置文件判断当前HDFS集群是否处于HA模式，对于处于HA模式的情况，createProxyWithClientProtocol()方法会调用createFailoverProxyProvider()方法创建支持HA模机制的ClientProtocol对象，而对于非HA模式，会调用createNonHAProxyWithClientProtocol()方法创建普通ClientProtocol对象。

```java
public static ProxyAndInfo<ClientProtocol> createProxyWithClientProtocol(
    Configuration conf, URI nameNodeUri, AtomicBoolean fallbackToSimpleAuth)
    throws IOException {
  AbstractNNFailoverProxyProvider<ClientProtocol> failoverProxyProvider =
      createFailoverProxyProvider(conf, nameNodeUri, ClientProtocol.class,
          true, fallbackToSimpleAuth);
  // 非HA情况
  if (failoverProxyProvider == null) {
    InetSocketAddress nnAddr = DFSUtilClient.getNNAddress(nameNodeUri);
    Text dtService = SecurityUtil.buildTokenService(nnAddr);
    ClientProtocol proxy = createNonHAProxyWithClientProtocol(nnAddr, conf,
        UserGroupInformation.getCurrentUser(), true, fallbackToSimpleAuth);
    return new ProxyAndInfo<>(proxy, dtService, nnAddr);
  } else {
    // HA情况
    return createHAProxy(conf, nameNodeUri, ClientProtocol.class,
        failoverProxyProvider);
  }
}
```

###### a.非HA模式

```java
public static ClientProtocol createNonHAProxyWithClientProtocol(
    InetSocketAddress address, Configuration conf, UserGroupInformation ugi,
    boolean withRetries, AtomicBoolean fallbackToSimpleAuth)
    throws IOException {
    // 先设置ProtocolEngine，定义当前使用Protobuf作为序列化工具
  RPC.setProtocolEngine(conf, ClientNamenodeProtocolPB.class,
      ProtobufRpcEngine.class);

  final RetryPolicy defaultPolicy =
      RetryUtils.getDefaultRetryPolicy(
          conf,
          HdfsClientConfigKeys.Retry.POLICY_ENABLED_KEY,
          HdfsClientConfigKeys.Retry.POLICY_ENABLED_DEFAULT,
          HdfsClientConfigKeys.Retry.POLICY_SPEC_KEY,
          HdfsClientConfigKeys.Retry.POLICY_SPEC_DEFAULT,
          SafeModeException.class.getName());

  final long version = RPC.getProtocolVersion(ClientNamenodeProtocolPB.class);
  // 构造ClientNamenodeProtocolPB协议的代理对象
  ClientNamenodeProtocolPB proxy = RPC.getProtocolProxy(
      ClientNamenodeProtocolPB.class, version, address, ugi, conf,
      NetUtils.getDefaultSocketFactory(conf),
      org.apache.hadoop.ipc.Client.getTimeout(conf), defaultPolicy,
      fallbackToSimpleAuth).getProxy();

  if (withRetries) { // create the proxy with retries
    Map<String, RetryPolicy> methodNameToPolicyMap = new HashMap<>();
    ClientProtocol translatorProxy =
        new ClientNamenodeProtocolTranslatorPB(proxy);
    return (ClientProtocol) RetryProxy.create(
        ClientProtocol.class,
        new DefaultFailoverProxyProvider<>(ClientProtocol.class,
            translatorProxy),
        methodNameToPolicyMap,
        defaultPolicy);
  } else {
      // 构造ClientNamenodeProtocolTranslatorPB对象并返回
    return new ClientNamenodeProtocolTranslatorPB(proxy);
  }
}
```

* org.apache.hadoop.ipc.RPC#getProtocolProxy()

```java
// 获取指定RPC接口的代理对象
 public static <T> ProtocolProxy<T> getProtocolProxy(Class<T> protocol,
                              long clientVersion,
                              InetSocketAddress addr,
                              UserGroupInformation ticket,
                              Configuration conf,
                              SocketFactory factory,
                              int rpcTimeout,
                              RetryPolicy connectionRetryPolicy,
                              AtomicBoolean fallbackToSimpleAuth)
     throws IOException {
  if (UserGroupInformation.isSecurityEnabled()) {
    SaslRpcServer.init(conf);
  }
   // 先获取当前序列化引擎，再用getProxy获取使用特定序列化方式的接口代理对象
  return getProtocolEngine(protocol, conf).getProxy(protocol, clientVersion,
      addr, ticket, conf, factory, rpcTimeout, connectionRetryPolicy,
      fallbackToSimpleAuth);
}
```

* org.apache.hadoop.ipc.RPC#getProtocolEngine

  ```java
  // return the RpcEngine configured to handle a protocol
  static synchronized RpcEngine getProtocolEngine(Class<?> protocol,
      Configuration conf) {
    RpcEngine engine = PROTOCOL_ENGINES.get(protocol);
    // 通过反射创建RpcEngine实例
    if (engine == null) {
      Class<?> impl = conf.getClass(ENGINE_PROP+"."+protocol.getName(),
                                    WritableRpcEngine.class);
      engine = (RpcEngine)ReflectionUtils.newInstance(impl, conf);
      PROTOCOL_ENGINES.put(protocol, engine);
    }
    return engine;
  }
  ```

真正构造代理对象的方法是RpcEngine.getProxy()方法。

```java
public <T> ProtocolProxy<T> getProxy(Class<T> protocol, long clientVersion,
    InetSocketAddress addr, UserGroupInformation ticket, Configuration conf,
    SocketFactory factory, int rpcTimeout, RetryPolicy connectionRetryPolicy,
    AtomicBoolean fallbackToSimpleAuth) throws IOException {
  // 先构造InvocationHandler对象
  final Invoker invoker = new Invoker(protocol, addr, ticket, conf, factory,
      rpcTimeout, connectionRetryPolicy, fallbackToSimpleAuth);
  // 调用Proxy.newProxyInstance方法构造动态代理对象，然后封装成ProtocolProxy对象返回
  return new ProtocolProxy<T>(protocol, (T) Proxy.newProxyInstance(
      protocol.getClassLoader(), new Class[]{protocol}, invoker), false);
}
```

Java动态代理特性决定了再代理对象上所有的调用都会由InvocationHandler对象的invoke()方法代理,所以所有ClientNamenodeProtocolPB代理对象上的调用都会由ProtobufRpcEngine.Invoker对象的invoker()方法代理。

org.apache.hadoop.ipc.ProtobufRpcEngine.Invoker#invoke方法主要做了三件事：

* 构造请求头域，使用protobuf将请求头序列化
* 通过RPC.Client类发送请求头以及序列化了的参数
* 获取响应信息，序列化响应信息并返回

```java
public Message invoke(Object proxy, final Method method, Object[] args)
    throws ServiceException {
 ...
  // 构造请求头，表明在什么接口上调用什么方法
  RequestHeaderProto rpcRequestHeader = constructRpcRequestHeader(method);
  
  if (LOG.isTraceEnabled()) {
    LOG.trace(Thread.currentThread().getId() + ": Call -> " +
        remoteId + ": " + method.getName() +
        " {" + TextFormat.shortDebugString((Message) args[1]) + "}");
  }

  // 获取请求的参数
  final Message theRequest = (Message) args[1];
  final RpcWritable.Buffer val;
  try {
    // 调用RPC.Client发送请求
    val = (RpcWritable.Buffer) client.call(RPC.RpcKind.RPC_PROTOCOL_BUFFER,
        new RpcProtobufRequest(rpcRequestHeader, theRequest), remoteId,
        fallbackToSimpleAuth);
  ...
    return getReturnMessage(method, val);
  }
```

```java
private Message getReturnMessage(final Method method,
    final RpcWritable.Buffer buf) throws ServiceException {
  Message prototype = null;
  try {
    // 获取返回参数类型
    prototype = getReturnProtoType(method);
  } catch (Exception e) {
    throw new ServiceException(e);
  }
  Message returnMessage;
  try {
    // 序列化响应信息并返回
    returnMessage = buf.getValue(prototype.getDefaultInstanceForType());

    if (LOG.isTraceEnabled()) {
      LOG.trace(Thread.currentThread().getId() + ": Response <- " +
          remoteId + ": " + method.getName() +
            " {" + TextFormat.shortDebugString(returnMessage) + "}");
    }

  } catch (Throwable e) {
    throw new ServiceException(e);
  }
  // 返回结果
  return returnMessage;
```

###### b.HA模式

对于HA模式，NameNodeProxiesClient调用RetryProxy.create()方法构造实现了RPC协议的对象，RetryProxy是一个工厂类，它会支持构造HA模式的协议对象，这个协议对象会首先尝试连接HDFS中的ActiveNamenode，如果连接失败会重试，重试达到多次后会切换到HDFS中的StandbyNamenode。

* org.apache.hadoop.io.retry.RetryProxy#creat()

  ```java
  public static <T> Object create(Class<T> iface,
      FailoverProxyProvider<T> proxyProvider, RetryPolicy retryPolicy) {
    // 直接调用Java动态代理的构造方法，返回代理对象
    return Proxy.newProxyInstance(
        proxyProvider.getInterface().getClassLoader(),
        new Class<?>[] { iface },
        new RetryInvocationHandler<T>(proxyProvider, retryPolicy)
        );
  }
  ```

由上面代码可知，在协议的代理对象上的调用都会由RetryInvocationHandler的invoke()方法代理。

RetryInvocationHandler在构造时传入了两个参数，proxyProvider提供proxy对象，retryPolicy指定了出现错误时的重试逻辑，这里默认的是failoverOnNetworkException。

* org.apache.hadoop.io.retry.RetryInvocationHandler#invoke()

  ```java
  public Object invoke(Object proxy, Method method, Object[] args)
      throws Throwable {
    // 先通过看是不是ProtocolTranslator的子类判断是不是RPC调用
    final boolean isRpc = isRpcInvocation(proxyDescriptor.getProxy());
    final int callId = isRpc? Client.nextCallId(): RpcConstants.INVALID_CALL_ID;
     // 根据同步或者异步方式创建一个新的调用
    final Call call = newCall(method, args, isRpc, callId);
    while (true) {
        // Invoke the call once without retrying.
      final CallReturn c = call.invokeOnce();
      final CallReturn.State state = c.getState();
      if (state == CallReturn.State.ASYNC_INVOKED) {
        return null; // return null for async calls
      } else if (c.getState() != CallReturn.State.RETRY) {
        return c.getReturnValue();
      }
    }
  }
  ```

  invoke()方法先判断proxy是否是远程过程调用，来决定是否更新CallId，然后创建一个Call对象，Call类中包含了调用方法，处理retryInfo等逻辑。然后调用call.invokeOnce()方法，先执行一次目标方法，如果失败再进行判断是否重新执行，最后返回一个CallReturn类型的返回值，CallReturn中包含了执行调用后的各种结果：

  ```java
  enum State {
    /** Call is returned successfully. */
    RETURNED,
    /** Call throws an exception. */
    EXCEPTION,
    /** Call should be retried according to the {@link RetryPolicy}. */
    RETRY,
    /** Call should wait and then retry according to the {@link RetryPolicy}. */
    WAIT_RETRY,
    /** Call, which is async, is still in progress. */
    ASYNC_CALL_IN_PROGRESS,
    /** Call, which is async, just has been invoked. */
    ASYNC_INVOKED
  }
  ```

  最后根据返回状态返回null（异步执行）或者实际的返回值（同步）。

  下面详细看Call类中的方法。

* org.apache.hadoop.io.retry.RetryInvocationHandler.Call#invokeOnce

  ```java
  /** Invoke the call once without retrying. */
  synchronized CallReturn invokeOnce() {
    try {
      if (retryInfo != null) {
          // 如果retryInfo不为空，调用processWaitTimeAndRetryInfo方法
         // 先处理等待时间，然后修改retryInfo
        return processWaitTimeAndRetryInfo();
      }
      // The number of times this invocation handler has ever been failed over
      // before this method invocation attempt. Used to prevent concurrent
      // failed method invocations from triggering multiple failover attempts.
        // 此前失败的次数
      final long failoverCount = retryInvocationHandler.getFailoverCount();
      try {
          // 调用目标方法
        return invoke();
      } catch (Exception e) {
        if (LOG.isTraceEnabled()) {
          LOG.trace(toString(), e);
        }
        if (Thread.currentThread().isInterrupted()) {
          // If interrupted, do not retry.
          throw e;
        }
          // 处理异常
        retryInfo = retryInvocationHandler.handleException(
            method, callId, retryPolicy, counters, failoverCount, e);
        // 重试
        return processWaitTimeAndRetryInfo();
      }
    } catch(Throwable t) {
      return new CallReturn(t);
    }
  }
  ```

* org.apache.hadoop.io.retry.RetryInvocationHandler.Call#invoke

  ```java
  CallReturn invoke() throws Throwable {
    return new CallReturn(invokeMethod());
  }
  ```

* org.apache.hadoop.io.retry.RetryInvocationHandler.Call#invokeMethod

  ```java
  protected Object invokeMethod(Method method, Object[] args) throws Throwable {
    try {
      if (!method.isAccessible()) {
        method.setAccessible(true);
      }
      // 通过调用failoverProxyProvider.getProxy()获得代理对象
      final Object r = method.invoke(proxyDescriptor.getProxy(), args);
      hasSuccessfulCall = true;
      // 返回结果
      return r;
    } catch (InvocationTargetException e) {
      throw e.getCause();
    }
  }
  ```

* org.apache.hadoop.io.retry.RetryPolicies.FailoverOnNetworkExceptionRetry#shouldRetry

  ```java
  @Override
    public RetryAction shouldRetry(Exception e, int retries,
        int failovers, boolean isIdempotentOrAtMostOnce) throws Exception {
      // 已经超出了最大重试次数
      // 返回RetryAction.RetryDecision.FAIL表示调用失败
      if (failovers >= maxFailovers) {
        return new RetryAction(RetryAction.RetryDecision.FAIL, 0,
            "failovers (" + failovers + ") exceeded maximum allowed ("
            + maxFailovers + ")");
      }
      if (retries - failovers > maxRetries) {
        return new RetryAction(RetryAction.RetryDecision.FAIL, 0, "retries ("
            + retries + ") exceeded maximum allowed (" + maxRetries + ")");
      }
      // 判断异常类型
      if (e instanceof ConnectException ||
          e instanceof EOFException ||
          e instanceof NoRouteToHostException ||
          e instanceof UnknownHostException ||
          e instanceof StandbyException ||
          e instanceof ConnectTimeoutException ||
          isWrappedStandbyException(e)) {
        // 发生上面异常中的一个，说明底层协议代理对象无法连接到ActiveNamenode或ActiveNamenode宕机
        // 返回一个RetryAction.RetryDecision.FAILOVER_AND_RETRY的RetryAction表示需要执行performFailover操作更新ActiveNamenode的引用
        return new RetryAction(RetryAction.RetryDecision.FAILOVER_AND_RETRY,
            getFailoverOrRetrySleepTime(failovers));
      } else if (e instanceof RetriableException
          || getWrappedRetriableException(e) != null) {
        // RetriableException or RetriableException wrapped 
        return new RetryAction(RetryAction.RetryDecision.RETRY,
              getFailoverOrRetrySleepTime(retries));
      } else if (e instanceof InvalidToken) {
        return new RetryAction(RetryAction.RetryDecision.FAIL, 0,
            "Invalid or Cancelled Token");
      } else if (e instanceof SocketException
          || (e instanceof IOException && !(e instanceof RemoteException))) {
        // 如果是SocketException或IOException等非RemoteException的异常
        // 无法判断RPC命令是否执行成功了，因此需要进一步判断
        // 如果被调用的方法是Idempotent(幂等)的，则多次执行没有副作用，就重试
        // 否则返回RetryAction.RetryDecision.FAIL表示失败
        if (isIdempotentOrAtMostOnce) {
          return RetryAction.FAILOVER_AND_RETRY;
        } else {
          return new RetryAction(RetryAction.RetryDecision.FAIL, 0,
              "the invoked method is not idempotent, and unable to determine "
                  + "whether it was invoked");
        }
      } else {
          return fallbackPolicy.shouldRetry(e, retries, failovers,
              isIdempotentOrAtMostOnce);
      }
    }
  }
  ```

* org.apache.hadoop.io.retry.RetryInvocationHandler.ProxyDescriptor#failover

  在processRetryInfo()方法中会判断上一次执行是否产生了失败，如果retryInfo.isFailover()返回true，则调用RetryInvocationHandler.ProxyDescriptor#failover方法。

  ```java
  synchronized void failover(long expectedFailoverCount, Method method,
                             int callId) {
    // Make sure that concurrent failed invocations only cause a single
    // actual failover.
    if (failoverCount == expectedFailoverCount) {
        // 更新proxy到新的ActiveNamenode
      fpp.performFailover(proxyInfo.proxy);
      failoverCount++;
    } else {
      LOG.warn("A failover has occurred since the start of call #" + callId
          + " " + proxyInfo.getString(method.getName()));
    }
    proxyInfo = fpp.getProxy();
  }
  ```

