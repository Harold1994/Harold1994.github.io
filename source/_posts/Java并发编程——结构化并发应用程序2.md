---
title: Java并发编程——结构化并发应用程序(二)
date: 2018-05-27 00:36:58
tags: [Java, 多线程, 并发]
---

#### CompletionService：Executor和BlockingQueue

若向Executor提交了一组计算任务，并希望在计算技术之后获得结果，有一下两种方法：

> - 保留与任务关联的Future，反复使用get方法，同时将参数timeout指定为0，从而通过轮训判断任务是否完成
> - 使用完成服务（CompletionService）

**CompletionService：**                     CompletionService将Executor和BlockingQueue功能结合起来，可以将Callable任务提交给它来执行，然后使用类似队列操作的take和poll等方法获得已经完成的结果，这些结果会**在完成时**被封装为Future。
<!-- more--> 
ExecutorCompletionService实现了CompletionService，并将计算部分委托给了一个Executor。实现方式：在构造函数中创建一个BlockingQueue来保存完成的结果，计算完成时，调用Future-Task中的done方法，当提交某个任务时，该任务首先将包装为一个QueueingFuture，这是FutureTask的一个子类，然后再改写子类的done方法，将结果放入BlockingQueue中。take和poll方法委托给了BlockingQueue，这些方法会在得出结果之前阻塞。

```java
//ExecutorCompletionService部分源码
public class ExecutorCompletionService<V> implements CompletionService<V> {
    private final Executor executor;
    private final AbstractExecutorService aes;
    private final BlockingQueue<Future<V>> completionQueue;

    /**
     * FutureTask extension to enqueue upon completion
     */
    private class QueueingFuture extends FutureTask<Void> {
        QueueingFuture(RunnableFuture<V> task) {
            super(task, null);
            this.task = task;
        }
        protected void done() { completionQueue.add(task); }
        private final Future<V> task;
    }
...
 public Future<V> take() throws InterruptedException {
        return completionQueue.take();
    }

    public Future<V> poll() {
        return completionQueue.poll();
    }

    public Future<V> poll(long timeout, TimeUnit unit)
            throws InterruptedException {
        return completionQueue.poll(timeout, unit);
    }
```

- 示例：使用CompletionService实现页面渲染

通过CompletionService从**缩短总运行时间**和**提高相应性**两个方面提高渲染性能，为每幅图像下载创建一个独立的任务，并在线程池中执行他们，从而将串行的下载转换为并行的过程，这将减少总下载时间；通过CompletionService中获取结果以及使每张图片在下载完后立刻显示出来，提高了响应性。

```java
/**
 * @author harold
 * @Title:
 * @Description: 使用CompletionService实现页面渲染
 * @date 2018/5/24上午11:17
 */
public class Renderer {
    public final ExecutorService executor;
    Renderer(ExecutorService executor) {
        this.executor = executor;
    }
    
    void renderPage(CharSequence source) {
        List<ImageInfo> info = scanForImageInfo(source);
        CompletionService <ImageData> completionService = new ExecutorCompletionService<ImageData>(executor);
        for (final ImageInfo imageInfo : info) {
            completionService.submit(new Callable<ImageData>() {
                @Override
                public ImageData call() throws Exception {
                    return imageInfo.downloadImage();
                }
            });
        }
        renderText(source);
        try {
            for (t = 0, n = info.size(); t<n; t++) {
                Future<ImageData> f = completionService.take();
                ImageData imageData = f.get();
                renderImage(imageData);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (ExecutionException e) {
            throw launderThrowable(e.getCause());
        }
    }
}
```

多个ExecutorCompletionService可以共享一个Executor，因此可以创建一个对于特定计算私有，又能共享一个公共Executor的ExecutorCompletionService。

#### 为任务设置时限

有时候，如果某个任务无法在指定时间内完成，将不再需要它的结果，此时可以放弃这个任务。在有限时间内执行任务的难点在于：要确保得到答案的时间不会超出限定的时间，或者在限定的时间内无法获得答案。Future.get支持这种需求：当结果可用时，他将立即返回，若在指定时间没有计算出来，将抛出TimeoutException。

传递给get的timeout参数的计算方式是将指定时限减去当前时间，这可能会得到负数，但java.util.concurrent中所有与时限相关的方法都将视负数为0.

Future.cancel参数为true表示任务线程可以在啊运行过程中中断。

```java
//在指定时间内获取广告时间
    Page renderPageWithAd() throws InterruptedException {
        long endNanos = System.nanoTime() + TIME_BUGET;
        Future<Ad> f = executor.submit(new FetchAdTask());
        //在等待广告时显示页面
        Page page = renderPageBody();
        Ad ad;
        try {
            //只等待指定时间长度
            long timeLeft = endNanos - System.nanoTime();
            ad = f.get(timeLeft, TimeUnit.NANOSECONDS);
        } catch (ExecutionException e) {
            ad = DEFAULT_AD;
        } catch (TimeoutException e) {
            ad = DEFAULT_AD;
            f.cancel(true);
        }
        page.setAd(ad);
        return page;
    }
}
```

- invokeAll
  创建n个线程，将其提交到一个线程池，保留n个Future，并使用现实的get方法通过Future串行的获取每一个结果，这个过程可以通过更简单的invokeAll实现。

  invokeAll方法的参数为一组任务，并返回一组Future。这两个集合有着相同的结构。invokeAll按照任务集合中迭代器的顺序将所有Future添加到返回集合中，从而使调用者可以将各个Future与其表示的Callable关联起来。当所有任务都执行完毕后，或者调用线程被中断时没或者超过指定时间，invokeAll将返回。当超过指定时限后，任何还未完成的任务都会取消。当invokeAll返回后，每个任务要么正常执行完毕，要么被取消。客户端代码可以用get或isCanceled判断情况。



