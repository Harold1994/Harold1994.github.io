---
title: tensorflow中optimizer如何实现神经网络的权重，偏移等系数的更新和梯度计算
date: 2018-07-16 00:38:07
tags: [tensorflow, 深度学习, 机器学习]
---

文章转自：https://blog.csdn.net/shenxiaoming77/article/details/77197708

**1.案例代码：**

建立抽象模型

<!-- more--> 

```python
x = tf.placeholder(tf.float32, [None, 784])
y = tf.placeholder(tf.float32, [None, 10])  #实际分布的概率值

w = tf.Variable(tf.zeros([784, 10]))
b = tf.Variable(tf.zeros(10))

a = tf.nn.softmax(tf.matmul(x, w) + b)  #基于softmax多分类得到的预测概率
#定义损失函数和训练方法
cross_entropy = tf.reduce_mean(-tf.reduce_sum(y * tf.log(a), reduction_indices=[1]))  #交叉熵

optimizer = tf.train.GradientDescentOptimizer(0.5)  #梯度下降优化算法，学习步长为0.5

train = optimizer.minimize(cross_entropy)  #训练目标: 最小化损失函数
init = tf.global_variables_initializer()
print('start to run session:')
with tf.Session() as sess:
    sess.run(init)
    for i in range(2000):
        batch_xs, batch_ys = mnist.train.next_batch(100)
        sess.run(train, feed_dict={x : batch_xs, y : batch_ys})
    #test trained model
    correct_prediction = tf.equal(tf.argmax(a, 1), tf.argmax(y, 1))
    accuracy = tf.reduce_mean(tf.cast(correct_prediction, tf.float32))
    print (sess.run(accuracy, feed_dict={x : mnist.test.images, y : mnist.test.labels}))
```

* 第一步：

  * 神经网络模型系数w,  b 声明Variable变量，其中默认trainable=True, 那么这些variable变量就会自动放入到TensorFlow系统的`GraphKey.TRAINABLE_VARIABLES`列表中
  * 后面进行不断的目标函数优化，梯度计算过程中，这些变量就会被新的梯度进行更新，达到权重系数更新的目标。

* 第二步：

  ```python
  cross_entropy = tf.reduce_mean(-tf.reduce_sum(y * tf.log(a), reduction_indices=[1]))  #交叉熵
  optimizer = tf.train.GradientDescentOptimizer(0.5)  #梯度下降优化算法，学习步长为0.5
  train = optimizer.minimize(cross_entropy)  #训练目标: 最小化损失函数
  ```

  ​	这里定义损失函数，优化算法以及最终训练模型这三个operation， 前后存在的任务依赖关系，在TensorFlow的graph中这些operation会形成保存依赖关系，最终session执行train 这个operation时，会根据依赖关系，往前搜索，找到最早的operation，开始一步步往下执行，最早的operation 即为w、b 等声明的这些op。

  ​	在optimizer.minimize函数中， 主要执行两个函数：**compute_gradients **函数和 **apply_gradients**函数

  - compute_gradients 对var_list中的变量(没有特别指定var_list,则默认更新GraphKey.TRAINABLE_VARIABLES中的变量)，计算loss的梯度
  - apply_gradients 作用为将计算得到的梯度用于更新 var_list中的变量，如果没有指定var_list， 则更新GraphKey.TRAINABLE_VARIABLES中的变量

   