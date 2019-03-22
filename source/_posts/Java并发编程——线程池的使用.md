---
title: Java并发编程——线程池的使用
date: 2018-06-04 00:07:56
tags: [Java, 多线程, 并发]
---

#### 一、在任务与执行策略之间的隐性耦合
Executor框架可以将任务的提交与任务的执行策略解耦开来，虽然Executor框架为制定和修改执行策略都提供了相当大的灵活性，但并非所有任务都适用于所有执行策略，有些类型的任务需要明确指定执行策略：
* 依赖性任务： 在线程池中执行独立的任务时，可以随意的改变线程池的大小和配置，这只会影响其执行性能。但是若提交到线程池的任务依赖于其他的任务，那么就隐含的给执行策略带来了约束。
<!-- more--> 
* 使用线程封闭机制的任务： 单线程的Executor能够对并发性做出更强的承诺，他们能保证任务不会并发的执行，对象可以封闭在任务线程中，使得在该线程中执行的任务在访问该对象时不需要同步。这种情形将在任务与执行策略之间形成隐式的耦合——任务要求其执行所在的Executor是单线程的。
* 对响应时间敏感的任务：将一个耗时的任务提交到单线程Executor中或者将多个耗时任务提交到包含少量线程的线程池中，将降低服务的响应性。
* 使用ThreadLocal的任务： 只要条件允许，Executor可以自由的重用其中的线程，当执行需求较低时将回收空闲线程，当需求增加时将添加新的线程，并且如果从任务中抛出一个未检查异常，那么将用一个新的工作者线程来替代抛出异常的线程。只有当线程本地值的生命周期受限于任务的生命周期时，在线程池中使用ThreadLocal才有意义。

只有当任务都是同类型并且相互独立时，线程池的性能才能达到最佳，如果运行的任务耗时差别很大，那么除非线程池很大，否则将引起**“拥塞”**。如果提交的任务有依赖关系，那么除非线程池无限大，否则将引起**死锁**。

**1.线程饥饿死锁**

在线程池中，如果任务依赖于其他任务，那么可能产生死锁。
线程饥饿死锁（Thread Starvation Deadlock）: 只要线程池中的任务需要无限期的等待一些必须由池中其他任务才能提供的资源或条件，那么除非线程池足够大，否则将发生线程饥饿死锁。

> 如果线程池不够大，那么当多个任务通过栅栏机制彼此协调时，将导致线程饥饿死锁

饥饿死锁示例：
```java
/**
 * @author harold
 * @Title:
 * @Description: 在单线程Executor中任务发生死锁
 * @date 2018/6/1下午6:19
 */
public class ThreadDeadlocl {
    ExecutorService executorService = Executors.newSingleThreadExecutor();
    public class RenderpageTask implements Callable<String> {
        @Override
        public String call() throws Exception {
            Future<String> header, footer;
            header = executorService.submit(new loadFileTask("head.txt"));
            footer = executorService.submit(new loadFileTask("foot.txt"));
            //将发生死锁——由于任务在等待子任务完成
            return header.get() + footer.get();
        }
    }
    
}
```
> 除了线程池大小的显示限制外，还可能由于其他资源上的约束而存在隐式限制，例如JDBC的连接池。

**2.运行时间较长的任务**

执行时间较长的任务不仅会造成线程池拥塞，甚至还会增加执行事件较短任务的服务时间。解决办法：限定等待资源的时间。在平台类库的大多数可阻塞方法中，都同时定义了限时版本和不限时版本，如Thread.join,BlockingQueue.put,CountDownLatch.await等。如果等待超市，那么可以把任务标识为失败，然后终止任务或者将任务重新放回队列以便随后执行。

#### 二、设置线程池大小
线程池的理想大小取决于被提交任务的类型以及所部属系统的特性，通常在代码中不会固定线程池大小，而应该通过某种配置机制来提供，或者根据Runtime。availableProcessors来动态配置。
> 线程池过大：大量线程将在相对较少的cpu和内存资源上发生竞争，这会导致高内存使用量，还可能导致资源耗尽。

> 线程池过小：许多空闲的处理器无法执行工作，从而降低吞吐率

对于计算密集型的任务，在拥有N_cpu个处理器的系统上，当线程池大小为N_cpu+1时，通常能实现最优的利用率。

#### 3.配置ThreadPollExetutor

ThreadPoolExecutor为一些Executor提供了基本的实现，这些Executor是有Executors中的newCachedThreadPool，newFixedThreadPool和newScheduledThreadPool等工厂方法返回的。ThreadPoolExecutor很灵活，允许各种定制。 

**1.线程的创建与销毁**

通用的ThreadPoolExecutor构造函数：
```java
/**
     * Creates a new {@code ThreadPoolExecutor} with the given initial
     * parameters.
     *
     * @param corePoolSize the number of threads to keep in the pool, even
     *        if they are idle, unless {@code allowCoreThreadTimeOut} is set
     * @param maximumPoolSize the maximum number of threads to allow in the
     *        pool
     * @param keepAliveTime when the number of threads is greater than
     *        the core, this is the maximum time that excess idle threads
     *        will wait for new tasks before terminating.
     * @param unit the time unit for the {@code keepAliveTime} argument
     * @param workQueue the queue to use for holding tasks before they are
     *        executed.  This queue will hold only the {@code Runnable}
     *        tasks submitted by the {@code execute} method.
     * @param threadFactory the factory to use when the executor
     *        creates a new thread
     * @param handler the handler to use when execution is blocked
     *        because the thread bounds and queue capacities are reached
     * @throws IllegalArgumentException if one of the following holds:<br>
     *         {@code corePoolSize < 0}<br>
     *         {@code keepAliveTime < 0}<br>
     *         {@code maximumPoolSize <= 0}<br>
     *         {@code maximumPoolSize < corePoolSize}
     * @throws NullPointerException if {@code workQueue}
     *         or {@code threadFactory} or {@code handler} is null
     */
public ThreadPoolExecutor(int corePoolSize,
                              int maximumPoolSize,
                              long keepAliveTime,
                              TimeUnit unit,
                              BlockingQueue<Runnable> workQueue,
                              ThreadFactory threadFactory,
                              RejectedExecutionHandler handler) { ... }
```
各参数的详细解释参照代码中的注释即可。
> newFixedThreadPool工厂方法将线程池的基本大小和最大大小设置为参数中指定的值，而且创建的线程池不会超时。

```java
public static ExecutorService newFixedThreadPool(int nThreads) {
        return new ThreadPoolExecutor(nThreads, nThreads,
                                      0L, TimeUnit.MILLISECONDS,
                                      new LinkedBlockingQueue<Runnable>());
    }
```

> newCachedThreadPool工厂方法将线程池的最大大小设置为Integer.MAX_VALUE,而将基本大小设置为0，并将超时设置为1分钟，这种方法创建出来的线程可以被无限扩展，并且在需求降低时自动收缩。

```java
public static ExecutorService newCachedThreadPool() {
        return new ThreadPoolExecutor(0, Integer.MAX_VALUE,
                                      60L, TimeUnit.SECONDS,
                                      new SynchronousQueue<Runnable>());
    }
```

**2.管理任务队列**

在线程池中，任务请求会在一个由Executor管理的Runnable队列中等待，而不是像线程那样去竞争cpu资源，通过一个Runnable和一个链表节点来表现一个等待中的任务，开销比用线程表示低很多，但如果客户端提交给服务器请求的速率超过了服务器的处理速率，那么仍可能会耗尽资源。

ThreadPoolExecutor允许提供一个BlockingQueue来保存等待执行的任务，基本任务队列有三种：
* 无界队列：newFixedThreadPool和newSingleThreadExecutor默认使用LinkedBlockingQueue，如果所有工作者线程都忙碌，那么任务将在队列中等候，缺点是队列可能无限制增加，造成资源耗尽。
* 有界队列：如ArrayBlockingQueue、有界的LinkedBlockingQueue、PriorityBlockingQueue。有界队列有助于避免资源耗尽，但是如果队列满了，新来的任务的处理成为了问题，**饱和策略**可以解决此类问题。
* 同步移交（SynchronousQueue）:直接将任务从生产者移交给工作者线程，SynchronousQueue是一种线程之间的移交机制，要将一个元素放入SynchronousQueue，必须有另外一个线程正在等待接受这个元素。如果没有线程正在等待并且线程池当前大小小于最大值，SynchronousQueue将创建一个新线程，否则根据饱和策略，这个任务将被拒绝。newCachedThreadPool工厂方法中使用了SynchronousQueue。

> 只有当任务相互独立时，为线程池工作队列设置界限才是合理的。若任务之间存在依赖关系，那么有界队列可能导致“饥饿”死锁问题，此时应该使用无界线程池，如newCachedThreadPool.

**3.饱和策略**
当有界队列被填满后，饱和策略开始发挥作用。ThreadPoolExecutor饱和策略可以通过setRejectedExecutionHandler来修改。（若某个任务被提交到已经关闭的Executor，也会用到饱和策略）。

* **中止（Abort）**：默认的饱和策略，该策略将会抛出未受检查的RejectedEcecutionExeption，调用者捕获后可以自行处理
* **抛弃（Discard）**：该策略会悄悄抛弃该任务
* **抛弃最旧的（Discard-Oldest）**：抛弃下一个将被执行的任务，然后尝试重新提交新任务。
* **调用者运行（Caller-Runs）**：实现了一种调节机制，既不会抛弃任务，也不会抛出异常，而是将任务回退到调用者，由调用者执行，从而降低新任务的流量。
