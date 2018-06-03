---
title: Java并发编程——结构化并发应用程序(一)
date: 2018-04-08 21:08:17
tags: [Java, 多线程, 并发]
---

## 一、任务执行（Task Execution）

---

任务通常是一些抽象且离散的工作单元，通过把应用程序的工作分解到多个任务中，可以简化程序的组织结构，提供一种自然的事务边界来优化错误恢复过程，以及提供一种自然的并行工作结构来提升并发性。

### 1.在线程中执行任务
当围绕“任务执行”来设计应用程序时，第一步就是要找到清晰的任务边界。大多数服务器应用程序都以*独立的客户请求*为边界.将独立的请求作为任务边界，即可以实现任务的独立性，又可以实现合理的任务规模。
<!-- more-->
* 串行的执行任务
```java
public class SingleThreadWebServer {
    public static void main(String[] args) throws IOException {
        ServerSocket socket = new ServerSocket(80);
        while (true) {
            Socket conn = socket.accept();
            handleREquest(conn);
        }
    }
}
```

串行处理机制通常无法提供高吞吐率或快速响应性，每次只能处理一个请求。在Web请求的处理中包含了一组不同的运算与I/O操作。服务器必须处理套接字I/O以读取请求和写回响应，这些操作通常会由于网络拥塞或连通性问题而被阻塞，此外服务器还可能处理文件I/O或者数据库请求,这些操作同样会阻塞。单线程服务器中，阻塞会推迟当前请求的完成时间，还会彻底阻止等待中的请求被处理。如果阻塞时间过长，用户将认为服务器是不可用的，同时服务器的资源利用率非常低，因为线程在等待I/O操作完成时，CPU将处于空闲状态。

* 显式地为任务创建线程

  ```java
  public class ThreadPerTaskWebServer {
      public static void main(String[] args) throws IOException {
          ServerSocket socket = new ServerSocket(80);
          while (true) {
              final Socket connection = socket.accept();
              Runnable task = new Runnable() {
                  @Override
                  public void run() {
                      handleRequest(connection);
                  }
              };
              new Thread(task).start();
          }
      }
  }
  ```

>* 任务处理过程从主线程分离出来，使得主循环能够更快的等待下一个到来的连接，提高响应性
>* 任务可以并行处理，从而同时服务多个请求
>* 任务处理代码必须是线程安全的因为当有多个任务时会并发的调用这段代码

* 无限制创建线程的不足
> *线程生命周期的开销非常高*：线程的创建和销毁并不是没有代价的，平台不同，开销也不同。但线程的创建过程都需要时间，延迟处理的请求，并且需要JVM和操作系统提供一些辅助操作。
>
> *资源消耗*:活跃的线程会消耗系统资源，尤其是内存。如果可用线程数量多于可用CPU的数量，有些线程将闲置。大量的空闲线程会占用许多内存，给垃圾回收器带来压力，而且大量线程在竞争CPU资源时还将产生其他的性能开销。
>
> *稳定性*：在可创建线程的数量上存在一個限制，与平台相关，并受JVM的启动参数、Thread构造函数中请求的栈大小以及底层操作系统对线程的限制等约束。破坏了限制可能抛出OutOfMemoryError异常。

为每个任务创建一个线程”的问题在于没有限制可创建线程的数量，只限制了远程用户提交HTTP请求的速率。
### 2.Executer框架
线程池简化了线程的管理工作，Executor框架能支持多种不同类型的任务执行策略，提供了一种标准的方法将任务的提交过程与执行过程解耦开来，用Runnable表示任务。Executor的实现还提供了对生命周期的支持，以及统计信息收集，应用程序管理机制和性能监视等机制。
Executor基于生产者-消费者模式，提交任务的操作相当于生产者，执行任务的线程相当于消费者。

#### 线程池

线程池是与工作队列密切相关的，其中在工作队列中保存了所有等待执行的任务。工作者线程（Work Thread）从工作队列中获取一个任务，执行任务，然后返回线程池等待下一个任务。
使用线程池的好处：
>. 通过重用而不是创建新线程，可以在处理多个请求时分摊在线程创建和销毁过程中产生的巨大开销
>. 请求到达时，工作线程通常已经存在，不会由于等待创建线程而延迟任务的执行，提高了响应性
>. 通过适当调整线程池的大小，可以使处理器保持忙碌状态，还可以放置过多线程相互竞争资源而使应用程序耗尽内存或失败

可以通过Executors中的静态工厂方法创建线程池：
*newFixedThreadPool*:固定长度的线程池

*newCachedThreadPool*:可缓存线程池，如果线程池的当前规模超过了处理需求时，将回收空闲的线程，当需求增加时，可以增加新的线程，线程池的规模不存在限制

*newSingleThreadExecutor*：单线程Executor，它创建单个工作线程来执行任务，如果这个线程异常结束，他会创建另外一個线程来代替。newSingleThreadExecutor能确保依照任务在队列中的顺序来串行执行。

*newScheduledThreadPool*:创建一个固定长度的线程池，以延迟或定时的方式执行任务。

#### Executord的生命周期
JVM只有在所有线程（非守护）全部终止才会退出，如果无法正确的关闭Executor，那么JVM将无法结束。
* 最平缓的关闭过程： 完成所有已启动的任务，并且不再接受任何新的任务
* 最粗暴的关闭方式： 直接断电

Executor扩展了ExecutorService来解决执行服务的生命周期问题。ExecutorService的生命周期有三种状态：运行、关闭和已终止。
ExecutorService在初建时期处于运行状态。shutdown将执行平缓的关闭过程：不再接受新的任务，同时等待已提交任务完成，包括那些还未执行的任务。shutdownNow方法将执行粗暴的关闭过程：尝试取消所有运行中的任务，并且不再启动队列中尚未开始执行的任务。

所有任务执行完毕，ExecutorService会进入终止状态。可调用awaitTermination来等待ExecutorService到达终止状态。或者通过isTerminated方法轮询是否已經终止。通常在调用awaitTermination后会立即调用shutdown，从而产生同步的关闭ExecutorService的效果。
```java
class lifecycleWebServer {
    private static final int NTHREADS = 100;
    private static final ExecutorService exec = Executors.newFixedThreadPool(NTHREADS);

    public void start() throws IOException {
        ServerSocket socket = new ServerSocket(80);
        while (!exec.isShutdown()) {
            try {
                final Socket conn = socket.accept();
                exec.execute(new Runnable() {
                    @Override
                    public void run() {
                        handleRequest(conn);
                    }
                });
            } catch (RejectedExecutionException) {
                if (!exec.isShutdown()) {
                    System.out.println("task submission rejected");
                }
            }
        }
    }

    public void stop() {
        exec.shutdown();
    }

    void handleRequest(Socket connection) {
        Request req = readRequest(connection);
        if (isShutDownRequest(req)) {
            stop();
        }
        else {
            dispatchRequest(req);
        }
    }
}

public class OutOfTime {
    public static void main(String[] args) throws InterruptedException {
        Timer timer = new Timer();
        timer.schedule(new ThrowTask(), 1);
        SECONDS.sleep(1);
        timer.schedule(new ThrowTask(), 1);
        SECONDS.sleep(5);
    }

    static class ThrowTask extends TimerTask {
        @Override
        public void run() {
            throw new RuntimeException();
        }
    }
}
```

报错：

```java
Exception in thread "Timer-0" java.lang.RuntimeException
	at com.OutOfTime$ThrowTask.run(OutOfTime.java:23)
	at java.util.TimerThread.mainLoop(Timer.java:555)
	at java.util.TimerThread.run(Timer.java:505)
Exception in thread "main" java.lang.IllegalStateException: Timer already cancelled.
	at java.util.Timer.sched(Timer.java:397)
	at java.util.Timer.schedule(Timer.java:193)
	at com.OutOfTime.main(OutOfTime.java:15)
```

 	要构建自己的调度服务，可以使用DelayQueue，它实现了BlockingQueue,并为ScheduledThreadPoolExecutor提供了调度功能。DelayQueue管理着一组Delayed对象，每个对象有一个相应的延迟时间。在DelayQueue中，只有某个元素逾期后，才能从DelayQueue中执行take操作。从DelayQueue中返回的对象将根据他们的延迟时间进行排序。

### 找出可利用并行性
有时候任务边界并非显而易见，即使是服务器应用程序，在单个客户请求中任可能存在可挖掘的并发性。
#### 携带结果的任务Callable与Future
Runnable局限：不能返回一个值或者抛出受检查的异常，在延迟计算上有弱点，如数据库查询、获取网络资源等
Callable：认为主入口点（即call）将返回一个值，并可抛出一个异常。
Executor执行的任务有四个生命周期阶段：创建、提交、开始和完成。
在Executor框架中，已提交但尚未开始的任务可以取消，但对于那些已经开始执行的任务，只有当他们能响应中断时，才能取消。
Future表示一个任务的生命周期，并提供了相应的方法来判断任务是否已经完成或者取消，以及获取任务的结果和取消任务等。Future规范包含的隐含含义是：任务的生命周期只能前进，不能后退。
ExecutorService中的所有submit方法都将返回一个Future，从而将一个Rrunnable或Callable提交给Executor，并得到一个Future来获得任务执行结果或者取消任务。FutureTask实现了Runnable，可以将它提交给Executor来执行，或者直接调用他的run方法。
#### 在异构任务并行化中存在的局限
两个问题：
1. 将不同类型的任务平均分配给每个线程并不容易，当线程数增加时，如何确保他们相互协作而不是相互妨碍，或者在重新分配任务时并不是容易的问题
2. 任务的大小可能完全不同，相差太大的话性能提升不多;当有多个线程分解任务时，还需要一定的任务协调开销，为了使任务分解提高性能，这种开销不饿能高于并行实现的提升。