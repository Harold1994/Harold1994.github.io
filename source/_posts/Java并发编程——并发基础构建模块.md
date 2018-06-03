---
title: Java并发编程——并发基础构建模块
date: 2018-05-27 00:39:52
tags: [Java, 多线程, 并发]
---

#### 一、同步容器类

同步容器类包括Vector和HashTable，其封装器类由Collections.synchronizedXxx等工厂方法创建

同步容器类实现线程安全的方式：将他们的状态封装起来，并对每个公有方法进行同步，使得每次只有一个线程能访问容器状态，即**串行化容器的访问**。

同步容器类支持客户端加锁，因此可能会创建一些新的操作，同步容器类通过其自身的锁来保护他的每个方法。

<!-- more--> 

**及时失败**：同步容器类的迭代器的并发修改问题，当容器在迭代过程中被修改时，会抛出ConcurrentModificationException异常。

> 在迭代期间对容器加锁可以解决及时失败问题，但是长时间对容器加锁会降低程序的可伸缩性，持有锁时间越长，在锁上的竞争就越激烈，降低吞吐量和cpu利用率。

> 另一种方式是“克隆容器”，并在副本上进行迭代，但这样存在明显的性能开销

容器的隐藏迭代：容器的toString(), hashCode(), equals()，removeAll(), retainsAll()等方法都会间接迭代容器，可能会发生ConcurrentModificationException异常。

#### 二、并发容器

同步容器串行化容器的访问，严重降低并发性，当多个线程竞争容器锁时，吞吐量严重降低。

并发容器是针对多个线程并发访问设计的。

- ConcurrentHashMap

  ConcurrentHashMap类似HashMap，也是基于散列的Map，它使用一种更细粒度的加锁机制——**分段锁**（Lock Striping）来实现更大程度的共享。任意数量的读取线程可以并发的访问Map，一定数量的写入线程可以并发修改Map，读写线程可以并发的访问Map。

  > ConcurrentHashMap不会抛出ConcurrentModificationException异常

  ConcurrentHashMap返回的迭代器具有弱一致性，可以容忍并发的修改，因此size(),isEmpty()等方法会返回近似值而不是精确值。

  ConcurrentHashMap没有实现对Map加锁以提供独占访问，提高了代码的伸缩性，只有在需要独占访问Map时才不使用ConcurrentHashMap。

  ConcurrentHashMap不能使用客户端加锁来创建新的原子操作。

- CopyOnWriteArrayList

  CopyOnWriteArrayList用于替代同步List，CopyOnWriteArraySet替代同步Set，提供了更好的并发性且不需要在迭代期间对容器加锁。

  Copy-On-Write写入时复制：只要正确发布一个事实不可变的对象，那么访问该对象时就不需要再进一步的同步，每次修改时都会创建并重新发布一个新的容器副本，从而实现可变性。“写入时复制”容器的迭代器保留一个指向底层基础数组的引用，这个数组当前位于迭代器的起始位置，由于它不会被修改，因此在对其进行同步时只需确保数组内容的可见性。因此多个线程可以同时对这个容器进行迭代，而不会彼此干扰活与修改容器的线程相互干扰。

  > 每次修改容器时都会复制底层数组，需要一定开销。当迭代操作远多于修改操作时，才应该使用“写入时复制”

#### 三、阻塞队列和生产者-消费者模式

  BlockingQueue提供了可阻塞的put和take方法，支持定时的poll和offer方法，若对列已满，put方法将阻塞直到有空间可用；若对列为空，take方法将阻塞直到有元素可用。队列可有界也可以无界，无界对列的take方法永远不会阻塞。

  阻塞队列简化了生产者-消费者设计模式，支持任意数量的生产者与消费者。

  offer方法：如果数据不能被添加到队列，将返回一个失败状态。

  BlockingQueue的实现：

- LinkedBlockingQueue

- ArrayBlockingQueue

  -------------------以上两者为FIFO队列-----------------

- PriorityBlockingQueue是一个按照优先级排序的队列，既可以根据自然顺序来比较元素，也可以使用Comparator来比较

- SynchronousQueue:实际上不是一个真正的队列，因为它不会为队列中的元素维护存储空间，它维护一组线程，这些线程在等待元素加入或移出队列。类似于洗碗没有盘架，洗完直接放到烘干机，SynchronousQueue的put和take会一直阻塞，直到有另一个线程已准备好参与到交付过程。仅当有足够多的消费者，并且总有一个消费者主备好交付的工作时，才使用同步队列。

  生产者——消费者模式的性能优势：生产者和消费者可以并发执行，如果一个是I/O密集型，一个是CPU密集型，那么并发执行的吞吐率高于串行的吞吐率。如果两者并行度不同，那么将他们紧密耦合会把整体并行度降低为二者中更小的并行度

- 串行线程封闭

  阻塞队列可以安全的将对象从生产者线程发布到消费者线程，线程封闭对象只能由单个线程拥有，但可以通过安全的发布对象来"转移"所有权.

- 双端队列与工作密取

  Deque和BlockingDeque分别扩展了Queue和BlockingQueue，Deque是一个双端队列，实现在队列头和队列尾高效插入和移出。具体实现包括ArrayDeque和LinkedBlockingDeque。

  双端队列适用于工作密取模式（Work Stealing）：每个消费者都有自己的双端队列，如果一个消费者完成了自己双端队列中的全部工作，它可以从其他消费者的双端队列**末尾**秘密的获取工作。这样有更高的伸缩性，从其他消费者尾部获取工作降低了竞争程度，适用于即是消费者又是生产者问题

#### 四、阻塞方法与中断方法

导致线程阻塞或暂停的原因：
    

- 等待I/O操作结束
- 等待获得一个锁
- 等待从Thread.sleep方法中醒来
- 等待另一个线程的计算结果

线程阻塞后一般会被挂起，并处于某种阻塞状态（BLOCKED,WATING,TIMED_WATING）。

阻塞线程与执行时间很长的操作的差别：被阻塞线程必须等待不受它控制的事件发生后才能继续执行。当某个外部事件发生时，线程状态被设置为RUNNABLE状态，并可以被再次调度执行。

当某方法抛出InterruptedException时，表示该方法是一个阻塞方法，如果这方法被中断，那么他将努力提前结束阻塞状态。

Thread提供了Interrupt方法，用于中断线程或查询线程是否已被中断，每个线程都有一个bool类型的属性，表示线程的中断状态，当线程中断时设置这个状态。

中断是一种协作机制，一个线程不能强制其他线程停止正在执行的操作而去执行其他操作。当线程A中断B时，A仅仅是要求B在执行到某个可以暂停的地方停止正在执行的操作——前提是B愿意停下来。

处理对中断的响应：

- 传递InterruptedException：避开这个异常通常是最明智的策略，将InterruptedException传给方法的调用者
- 恢复中断：捕获InterruptedException，并通过调用当前线程上的interrupt方法恢复中断状态

#### 五、 同步工具类

阻塞队列不仅能作为保存对象的容器，还能协调生产者和消费者之间的控制流，直到队列达到期望的状态。

同步工具类可以是任意对象，只要它根据自身情况状态来协调线程的控制流。
同步工具类包括：

1. 阻塞队列
2. 信号量（Semaphore）
3. 栅栏（Barrier）
4. 闭锁（Latch）

- 闭锁

  闭锁可以延迟线程的进度直到其到达终止状态。相当于一扇门，在闭锁到达结束状态之前，门一直关闭，并且没有任何线程能通过，当到达结束状态时，这扇门会打开并允许所有线程通过。当闭锁到达结束状态后，将不会再改变状态。闭锁可以确保某些活动直到其他活动都完成后才继续执行。

  CountDownLatch是闭锁的一种实现，可以使一个或多个事件等待一组事件发生。闭锁状态包含一个计数器，初始化为一个正数，表示需要等待的事件的数量，countDown方法递减计数器，表示有一个事件已经发生，await方法等待计数器达到零，表示等待的事件均已发生。若计数器非零，await方法会一直阻塞到计数器为零，或者等待中的线程中断，或者等待超时。

  ```java
  public class TestHarness {
  public long timeTasks (int nThreads, final Runnable task) throws InterruptedException {
      final CountDownLatch startGate = new CountDownLatch(1);
      final CountDownLatch endGate = new CountDownLatch(nThreads);

      for (int i = 0; i<nThreads; i++) {
          Thread t = new Thread() {
              @Override
              public void run() {
                  try {
                      startGate.await();
                      try{
                          task.run();
                      } finally {
                          endGate.countDown();
                      }
                  } catch (InterruptedException e) {
                  }
              }
          };
          t.start();
      }
      long start =System.nanoTime();
      startGate.countDown();
      endGate.await();
      long end = System.nanoTime();
      return end - start;
  }
  }
  ```

- FutureTask

FutureTask也可以用作闭锁，表示的计算是通过Callable实现的，相当于一种可生成结果的Runnable，有三种状态：

```
1.等待运行——waiting to run

2.正在运行——running

3.运行完成——completed
```

当FutureTask进入完成状态后，会永远停止在这个状态上。
Future.get的行为取决于任务的状态，若已完成，会立即返回结果，否则会阻塞直到任务进入完成状态。FutureTask将计算结果从计算线程传递到获取结果的线程，而FutureTask能确保传递过程能实现结果的安全发布。

FutureTask在Executor框架中表示异步任务，还可以用来表示一些时间较长的计算。

```java
public class Preloader {
    private final FutureTask<ProductInfo> future =
            new FutureTask<ProductInfo>(new Callable<ProductInfo>() {
                @Override
                public ProductInfo call() throws Exception {
                    return loadProductInfo();
                }
            });

    private final Thread thread = new Thread(future);

    public void start() {
        thread.start();
    }

    public ProductInfo get() {
        try {
            return future.get();
        } catch (ExecutionException e) {
            Throwable cause = e.getCause();
            if (cause instanceof  DataLoadException)
                throw (DataLoadException) cause;
            else 
                throw launderthrowable(cause);
        }
    }
}
```

Callable表示的任务可以抛出受检查的或者未受检查的异常，并且任何代码都可能抛出一个Error，无论代码抛出什么异常，都会被封装到一个ExecutionException中，并在Future.get中被重新排出。

- 信号量 Semaphore

  计数信号量用来控制访问某个特定资源的操作数量或者同时执行某个指定操作的数量

  信号量管理着一组虚拟的许可(permit)，许可的数量可通过构造函数指定，在执行操作时可以首先获得许可，并在以后释放许可即可。若没有许可，那么acquire将阻塞直到有许可（或者直到被中断获操作超时）。release方法将返回一个许可给信号量。

  **二值信号量**计算信号量的简化形式，初始值为1，二值信号量可以作为互斥体（mutex），并具备不可重入锁语义：谁唯一拥有了这个锁，谁就拥有了互斥锁。

```java
/**
 * @author harold
 * @Title: BoundedHashSet
 * @Description: 使用Semaphore为容器设置边界
 * @date 2018/5/23下午1:59
 */
public class BoundedHashSet<T> {
    private final Set<T> set;
    private final Semaphore sem;

    public BoundedHashSet(int bound) {
        this.set = Collections.synchronizedSet(new HashSet<T>());
        sem = new Semaphore(bound);
    }

    public boolean add(T o) throws InterruptedException {
        sem.acquire();
        boolean wasAdded = false;
        try {
            wasAdded = set.add(o);
            return wasAdded;
        } finally {
            if (!wasAdded) {
                sem.release();
            }
        }
    }
    
    public boolean remove(Object obj) {
        boolean wasRemoved = set.remove(obj);
        if (wasRemoved) {
            sem.release();
        }
        return wasRemoved;
    }
}
```

- 栅栏Barrier

  闭锁是一次性对象，一旦进入终止状态，就不能被重置。

  栅栏类似于闭锁，它能阻塞一组线程直到某个事件发生。栅栏与闭锁的关键区别在于：所有线程必须**同时到达**栅栏位置，才能继续执行。闭锁用来等待事件，而栅栏用于等待其他线程。

  CyclicBarrier可以使一定数量的参与方反复的在栅栏位置汇集，在并行迭代算法中非常有用：这类算法通常将一个问题拆分成一系列相互独立的子问题。

  当线程到达栅栏位置时将调用await方法，这方法将阻塞直到所有线程都到达栅栏位置。如果所有线程都到达了栅栏位置，那么栅栏将打开，所有线程都被释放，栅栏将被重置以便下次使用。如果对await的调用超时，或者await的线程被中断，那么栅栏就被认为是打破了，所有阻塞的await调用都将终止并抛出BrokenBarrierException。若成功通过栅栏，那么await将为每个线程返回一个唯一的到达索引号。

  CyclicBarrier还可以将一个栅栏操作传递给构造函数，它是一个Runnable函数，当成功通过栅栏时会在一个子任务线程中执行它，但在阻塞线程被释放之前是不能执行的。

```java
 //通过cyclicbarrier协调细胞自动衍生系统中的运算
public class CellularAotumata {
    private final Board mainboard;
    private final CyclicBarrier barrier;
    private final Worker[] workers;

    public CellularAotumata(Board mainboard) {
        this.mainboard = mainboard;
        int count = Runtime.getRuntime().availableProcessors();
        this.barrier = new CyclicBarrier(count,
                new Runnable() {
                    @Override
                    public void run() {
                        mainboard.commitNewValues();
                    }
                });
        this.workers = new Worker[count];
        for (int i=0; i<count; i++) 
            workers[i] = new Worker(mainboard.getSubBoard(count, i));
    }
    private class Worker implements Runnable{
        private final Board board;

        public Worker(Board board) {
            this.board = board;
        }

        @Override
        public void run() {
            while(!board.hasConverged()) {
                for (int i = 0; i < board.getMaxX(); i++){
                    for (int j = 0; i < board.getMaxY(); j++) {
                        board.setNewValue(x,y, compute(x,y));
                    }
                }
                try {
                    barrier.await();
                } catch (InterruptedException ex) {
                    return;
                }
                 catch (BrokenBarrierException ex) {
                    return ;
                 }
            }
        }
    }
    public void start() {
        for (int i = 0; i< workers.length; i++) {
            new Thread(workers[i]).start();
        }
        mainboard.waitForConvergence();
    }
}
```

```
另一种形式的栅栏是Exchanger，是一种两方栅栏，各方在栅栏上交换数据，当两方执行不对称操作时，Exchanger非常有用。
```

#### 六、构建高效可伸缩结果缓存

几乎所有服务器应用程序都会使用某种形式的缓存，重用之前的结果能降低延迟，提高吞吐量，但需要消耗更多的内存。

程序清单：

```java
/**
 * @author harold
 * @Title:
 * @Description:  构建可伸缩缓存
 * @date 2018/5/23下午3:47
 */
interface Computerable<A, V> {
    V compute(A arg) throws InterruptedException;
}

class ExpensiveFunction implements Computerable<String, BigInteger> {
    @Override
    public BigInteger compute(String arg) throws InterruptedException {
        //再经过长时间计算后
        return new BigInteger(arg);
    }
}

//使用HashMap和同步机制来初始化缓存
public class Memorizer1 <A, V> implements Computerable<A, V> {
    private final Map<A,V> cache = new HashMap<A,V>();
    private final Computerable<A, V> c;

    public Memorizer1(Computerable<A, V> c) {
        this.c = c;
    }

    @Override
    public synchronized V compute(A arg) throws InterruptedException {
        V result = cache.get(arg);
        if (result == null) {
            result = c.compute(arg);
            cache.put(arg, result);
        }
        return  result;
    }
}
//用ConcurrentHashMap代替HashMap
public class Memorizer2<A, V> implements Computerable<A, V> {
    private final Map<A, V> cache = new ConcurrentHashMap<A, V>();
    private final Computerable<A, V> c;

    public Memorizer2(Computerable<A, V> c) {
        this.c = c;
    }

    @Override
    public V compute(A arg) throws InterruptedException {
        V result = cache.get(arg);
        if (result == null) {
            result = c.compute(arg);
            cache.put(arg, result);
        }
        return  result;
    }
}

//基于FutureTask的Memorizing封装器
public class Memorizer3<A,V> implements Computerable<A, V> {
    private final Map<A, Future<V>> cache = new ConcurrentHashMap<A, Future<V>>();
    private final Computerable<A, V> c;

    public Memorizer3(Computerable<A, V> c) {
        this.c = c;
    }

    @Override
    public V compute(A arg) throws InterruptedException {
        Future<V> f = cache.get(arg);
        if (f == null) {
            Callable<V> eval = new Callable<V>() {
                @Override
                public V call() throws Exception {
                    return c.compute(arg);
                }
            };
            FutureTask<V> ft = new FutureTask<V>(eval);
            f = ft;
            cache.put(arg, ft);
            ft.run();
        }
        try {
            return f.get();
        } catch (ExecutionException e) {
           throw launderthrowable(e.getCause());
        }
    }
}

public class Memorizer<A, V> implements Computerable<A, V> {
    private final Map<A, Future<V>> cache = new ConcurrentHashMap<A, Future<V>>();
    private final Computerable<A, V> c;

    public Memorizer(Computerable<A, V> c) {
        this.c = c;
    }
    @Override
    public V compute(A arg) throws InterruptedException {
        while (true) {
            Future<V> f = cache.get(arg);
            if (f == null) {
                Callable<V> eval = new Callable<V>() {
                    @Override
                    public V call() throws Exception {
                        return c.compute(arg);
                    }
                };
                FutureTask<V> ft = new FutureTask<V>(eval);
                f = cache.putIfAbsent(arg, ft);
                if (f == null) {
                    f = ft;
                    ft.run();
                }
            }
            try {
                return f.get();
            } catch (CancellationException e) {
                cache.remove(arg,f);
            } cache (ExecutionException e) {
                throw launderThrowable(e.getCause());
            }
        }
    }
}
```

Memorizer1使用HashMap和同步机制来保存之前的计算结果，HashMap非线程安全，于是对整个compute方法同步，这样可能用的时间比没有缓存用的更长，效果不好。
![](http://p5s7d12ls.bkt.clouddn.com/18-5-23/48498421.jpg)

Memorizer2用ConcurrentHashMap代替HashMap，多线程可以并发的使用它，但是当两个线程同时调用compute时存在一个漏洞，可能会导致重复计算，与我们缓存的初衷违背。
![](http://p5s7d12ls.bkt.clouddn.com/18-5-23/98285594.jpg)

Memorizer3使用ConcurrentHashMap<A,Future<V>>，先检查某个相应的计算是否已经开始，若还未启动，就创建一个FutureTask，并注册到Map中，然后启动计算，若已启动，的等待现有的计算结果。但是有一个漏洞，仍然可能出现两个线程计算出相同的值，因为compute方法中的if代码块仍然是非原子的“先检查、再执行”操作。
![](http://p5s7d12ls.bkt.clouddn.com/18-5-23/36335384.jpg)

Memorizer是缓存的最终实现，当缓存的是Future而不是值时，将导致缓存污染问题：如果某个计算被取消或失败，那么在计算这个结果时将指明计算过程被取消或者失败。为避免这种情况，如果Memorizer发现计算被取消，那么将把Future从缓存中移出，如果监测到RuntimeException，也会移出Future。