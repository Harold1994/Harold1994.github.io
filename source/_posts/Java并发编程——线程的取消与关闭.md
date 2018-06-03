---
title: Java并发编程——线程的取消与关闭
date: 2018-06-04 00:10:55
tags: [Java, 多线程, 并发]
---

Java没有提供任何机制来安全的终止线程，但是提供了**中断**（Interruption），这是一种协作机制，能够使一个线程终止另外一个线程。
#### 一、任务取消
* 可取消操作：如果外部代码能在某个正常操作完成之前将其置入“完成”状态，称这个任务可取消
* 取消某个操作的原因：
    * 用户请求取消
    * 有时间限制的操作：计时器超时时，取消正在进行的任务
    * 应用程序事件；应用程序对某个问题空间进行分解并搜索，从而不同任务可以搜索问题空间中的不同区域当其中一个任务找到了解决方案时，其他所有正在搜索的任务都要被取消
    * 错误
    * 关闭

Java中没有安全的抢占式方法来停止线程，只有一些协作的机制，其中一种协作机制能设置某个“已请求取消”标志，而任务将定期的查看该标志。如果设置了这个标志，任务将提前结束
```java
/**
 * @author  harold
 * @Title:
 * @Description: 使用volatile类型的域来保存取消状态
 * @date 2018/5/29下午5:18
 */

public class PrimeGenerator implements Runnable {
    private final List<BigInteger> primes = new ArrayList<BigInteger>();
    private volatile boolean cancled;
    //持续的枚举素数
    @Override
    public void run() {
        BigInteger p = BigInteger.ONE;
        while (!cancled) {
            p = p.nextProbablePrime();
            synchronized (this) {
                primes.add(p);
            }
        }
    }
    public void cancel() {
        cancled = true;
    }

    public synchronized List<BigInteger> get() {
        return new ArrayList<BigInteger>(primes);
    }

    public static void main(String[] args) throws InterruptedException {
        //让素数生成器1s后取消
        PrimeGenerator generator = new PrimeGenerator();
        new Thread(generator).start();
        try {
            SECONDS.sleep(1);
        } finally {
            generator.cancel();
        }
        System.out.println(generator.get());
    }
}
```

**1.中断**

PrimeGenerator中的取消机制最终会使得任务退出，但退出时需要花费一定时间。更严重的是，当使用这种方法的任务调用了一个阻塞方法，如BlockingQueue.put，任务可能永远不会检查取消标志，因此永远不会结束。
```java
/**
 * @author harold
 * @Title: BrokenPrimeProducer
 * @Description: 不可靠的取消操作将把生产者置于阻塞的操作中
 * @date 2018/5/29下午5:38
 */
public class BrokenPrimeProducer extends Thread {
    private final BlockingQueue<BigInteger> queue;
    private volatile boolean cancelled = false;

    public BrokenPrimeProducer(BlockingQueue<BigInteger> queue) {
        this.queue = queue;
    }

    @Override
    public void run() {
        try {
            BigInteger p = BigInteger.ONE;
            while (!cancelled) {
                queue.put(p = p.nextProbablePrime());
            }
        } catch (InterruptedException consumed){
            
        }
    }
    
    public void cancel() {
        cancelled = true;
    }
    //消费者
    void consumerPrimes() throws InterruptedException {
        BlockingQueue<BigInteger> primes = new BlockingQueue<BigInteger>() {
          ...
        };
        BrokenPrimeProducer producer = new BrokenPrimeProducer(primes);
        producer.start();
        try {
            while (needMorePrimes()) {
                consume(primes.take());
            }
        } finally {
            producer.cancel();
        }
    }
}
```
一些特殊的阻塞库的方法支持中断，线程可以通过这种机制来通知另一个线程，告诉它在合适的时候停止当前工作，并转而执行其他工作。

每个线程都有一个boolean类型的中断状态，线程中断时，这个状态将被设置为true。在Thread中包含了**中断线程**和*查询中断*的方法。
> Thread中的中断方法：
>
> public void interrupt():中断目标线程
>
> public boolean isInterrupted():查询目标线程的中断状态
>
> public static boolean interrupted():清除当前线程的中断状态，并返回它之前的值

阻塞库方法，如Thread.sleep()和Object.wait()等，都会检查线程何时中断，并在发现中断时提前返回。

* 阻塞库方法响应中断执行的操作包括：
    * 清除中断状态 
    * 抛出InterruptedException异常
    * 表示阻塞操作由于中断而提前结束

当线程在非阻塞状态下中断时，它的中断状态将被设置，然后根据将被取消的操作来检查中断状态以判断发生了中断。
> 调用interrupt并不意味着立即停止目标线程正在进行的工作，而只是传递了请求中断的消息。

> 注意：使用静态方法interrupted时应该小心，它会清除当前线程的中断状态。如果在调用interrupted时返回了true，除非想要屏蔽这个中断，否则必须对它作出处理——可以抛出InterruptedException或者再次调用interrupt来恢复中断状态。

通常，中断是取消的最合理方式。
 ```java
 /**
 * @author lihe
 * @Title: PrimeProducer
 * @Description: 通过中断来取消
 * @date 2018/5/29下午6:48
 */
public class PrimeProducer extends Thread {
    private final BlockingQueue<BigInteger> queue;

    public PrimeProducer(BlockingQueue<BigInteger> queue) {
        this.queue = queue;
    }

    @Override
    public void run() {
        try {
            BigInteger p = BigInteger.ONE;
            //显式执行检测可以使代码对中断有更高的响应性
            while (!Thread.currentThread().isInterrupted()) {
                queue.put(p.nextProbablePrime());
            }
        } catch (InterruptedException e) {
           //允许线程退出
        }
    }

    public void cancel() {
        interrupt();
    }
}
```
**2.中断策略**

中断策略指定线程如何解释某个中断请求，最合理的中断策略是某种形式的线程级（thread——level）取消操作或者服务级（Service-Level）取消操作：尽快退出，在必要时清理，通知某个所有者该线程已经退出。

一个中断请求可以有一个或多个接收者，中断线程池中的某个工作者线程，同时意味着“取消当前任务”和“关闭工作者线程”。线程应该只能由其所有者中断，所有者可以将线程的中断策略信息封装到某个合适的取消机制中，例如shutdown方法。

**3.响应中断**

在调用可中断的阻塞函数时，有两种策略可用于处理InterruptedException：
* 传递异常，从而使你的方法也成为可中断的方法，通过throws InterruptedException
* 恢复中断状态，从而使调用栈上层代码能够对其进行处理，通过再次调用interrut()方法

> 只有实现了线程中断策略的代码才可以屏蔽中断请求（catch块中捕获异常却不做处理），在常规的任务和库代码中都不应该屏蔽中断请求‘

对于一些不支持取消但仍可以调用可中断阻塞方法的操作，它们必须在循环中调用这些方法。并在发现中断后重新尝试。这种情况下，应该在本地保存中断状态，并在返回前恢复中断状态而不是在捕获InterruptedException时恢复状态，如果过早的设置中断状态，可能会引起无限循环，因为大多数阻塞方法会在入口处检查中断状态，摒弃在发现该状态已被设置时会立即抛出interruptedException.
```java
/**
 * @author harold
 * @Title: getNextTask
 * @Description: 不可取消的任务在退出前恢复中断
 * @date 2018/5/31下午2:10
 */

public Task getNextTask(BlockingQueue<Task> queue) {
    boolean interrupted = false;
    try {
        while (true) {
            try {
                return queue.take();
            } catch (InterruptedException e) {
                interrupted = true;
            }
        }
    }
    finally {
        if (interrupted)
            Thread.currentThread().interrupt();
    }
}
```
**4.通过Future实现取消**

ExecutorService.submit将返回一个Future来描述任务。Future.cancel带有一个boolean类型的参数mayInterruptIfRunning，表示取消操作是否成功（只是表示任务能否接收中断，而不是表示任务能否检测并处理中断）。

**5.处理不可中断的阻塞**
并非所有方法或阻塞机制都能响应中断，例如一个线程执行同步的Socket I/O或者等待获得内置锁而阻塞，那么中断请求只能设置线程的中断状态，此外没有其他作用。对于由于执行不可中断操作而被阻塞的线程，可以使用类似于中断的手段来停止这些线程，前提是知道线程阻塞的原因：

* Java.io包中的同步Socket I/O：虽然InputStream，OutputStream中的read、write方法不会响应中断，但关闭底层的套接字，可以使得正在执行read和write等方法而被阻塞的线程抛出SocketException
* Java.io包中的同步I/O：当中断一个正在InterruptableChannel上等待的线程时，会抛出closedByInterruptedException并关闭链路。
* 获取某个锁：如果一个线程由于等待某个内置锁而阻塞，他将无法响应中断，因为线程默认它肯定会获得锁，所以不会理会中断请求。但在Lock类中提供了lockInterruptibly方法，该方法允许在等待一个锁的同时仍能响应中断。
```java
/**
 * @author harold
 * @Title: ReaderThread
 * @Description: 通过改写interrupt方法将给标准的取消操作封装在Thread中
 * @date 2018/6/1下午1:12
 */
public class ReaderThread  extends Thread {
    private final Socket socket;
    private final InputStream inputStream;

    public ReaderThread(Socket socket, InputStream inputStream) {
        this.socket = socket;
        this.inputStream = inputStream;
    }

    @Override
    public void interrupt() {//既能处理标准中断，又能关闭底层套接字
        try {
            socket.close();
        } catch (IOException e) {
        }
        finally {
            super.interrupt();
        }
    }

    @Override
    public void run() {
        byte [] mbuffer = new byte[128];
        while (true) {
            try {
                int count = inputStream.read(mbuffer);
                if (count < 0)
                    break;
                else if (count > 0) {
                    processBuffer(buf, count);
                }
            } catch (IOException e) {
                /*
                允许线程退出
                 */
            }
        }
    }
}
```
**6.采用newTaskFor来封装非标准的取消**
newTaskFor是一个工厂方法，他将创建Future来创建任务。newTaskFor还能返回一个RunnableFuture接口，该接口扩展了Future和Runnable。通过定制表示任务的Future可以改变Future.cancel行为
