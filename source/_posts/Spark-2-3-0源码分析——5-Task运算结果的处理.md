---
title: Spark-2-3-0源码分析——5-Task运算结果的处理
date: 2018-10-06 17:12:01
tags: [大数据, Spark]
---

#### 一. Task运算结果的处理

Task在Executor执行完成时，会向Driver发送StatusUpdate的消息来通知Driver任务的状态更新为TaskStatus.FINISHED。

Driver首先会将任务的状态更新通知TaskScheduler，然后在这个Executor上重新分配新的计算任务。

我们从org.apache.spark.scheduler.cluster.CoarseGrainedSchedulerBackend.DriverEndpoint#receive的方法看起

###### A.org.apache.spark.scheduler.cluster.CoarseGrainedSchedulerBackend.DriverEndpoint#receive

```scala
override def receive: PartialFunction[Any, Unit] = {
      // 接收StatusUpdate发送过来的消息
      case StatusUpdate(executorId, taskId, state, data) =>
        // 调用TaskSchedulerImpl中的statusUpdate方法
        scheduler.statusUpdate(taskId, state, data.value)
        if (TaskState.isFinished(state)) {
          executorDataMap.get(executorId) match {
            case Some(executorInfo) =>
              // 释放资源并重新分配
              executorInfo.freeCores += scheduler.CPUS_PER_TASK
              makeOffers(executorId)
            case None =>
              // Ignoring the update since we don't know about the executor.
              logWarning(s"Ignored task status update ($taskId state $state) " +
                s"from unknown executor with ID $executorId")
          }
        }
    ...
```

###### B. org.apache.spark.scheduler.TaskSchedulerImpl#statusUpdate

