---
title: tensorflow入门
date: 2018-07-08 20:22:33
tags: [tensorflow, 深度学习]
---

#### 一、Tensorflow计算模型——计算图

计算图是Tensorflow中最基本的一个概念，Tensorflow中所有计算都会被转化为计算图上的结点。Tensor就是张量，在tensorflow中可以理解为多维数组，Flow是“流”，体现了Tensorflow的计算模型，flow表达了张量之间通过计算相互转化的过程。Tensorflow是一个通过计算图的形式来表达计算的编程系统，它的每个计算都是计算图上的一个节点，节点之间的边描述了计算之间的依赖关系。

 <!-- more-->

Tensorflow程序分为**定义图中所有的计算**和**执行计算**两个阶段：

```python
#载入Tensorflow
import tensorflow as tf
a = tf.constant([1.0,2.0], name = "a")
b = tf.constant([2.0,3.0], name = "b")
result = a + b
```

在这个过程中，Tensorflow会自动将定义的计算转为计算图上的节点，在Tensorflow中，系统会维护一个默认计算图。通过tf.get_default_graph可以获得：

```python
#a.graph查看张量所属计算图，因为没有特定指定，所以
#这个计算图应该等于当前默认计算图
print(a.graph is tf.get_default_graph())
```

除了默认计算图，Tensorflow支持通过tf.Graph函数来生成新的计算图。**不同计算图上的张量和运算都不会共享**。

```python
g1 = tf.Graph()

with g1.as_default():
    #在g1中定义v，设值为0
    v = tf.get_variable("v", initializer=tf.zeros_initializer()(shape=[1]))

g2 = tf.Graph()

with g2.as_default():
    #在g2中定义v,设值为2
    v = tf.get_variable("v", initializer=tf.ones_initializer()(shape=[1]))

#在计算图2中读取变量“v的取值”
with tf.Session(graph=g2) as sess:
    tf.initialize_all_variables().run()
    with tf.variable_scope("", reuse=True):
        print(sess.run(tf.get_variable("v")))
输出：[1.]
```

Tensorflow中的计算图不仅仅可以用来隔离张量和计算，还提供了管理张量和计算的机制，计算图可以通过tf.Graph.device函数指定运算的设备。

```python
g = tf.Graph()

with g.device('gpu:0'):
    result = a + b
```

在一个计算图中，可以通过集合("collection")管理不同类别的资源。比如通过tf.add_to_collection函数可将资源加入一个或多个集合中，然后通过tf.get_collection获取一个集合中的所有资源。

​								------Tensorflow中维护的集合列表------

| 集合名称                                | 集合内容                               | 使用场景                     |
| --------------------------------------- | :------------------------------------- | :--------------------------- |
| `tf.GraphKeys.VARIABLES`                | 所有变量                               | 持久化Tensorflow模型         |
| `tf.GraphKeys.TRAINABLE_VARIABLES`      | 可学习的变量（一般指神经网络中的参数） | 模型训练、生成模型可视化内容 |
| `tf.GraphKeys.SUMMARIES`                | 日志生成相关的张量                     | Tensorflow计算可视化         |
| `tf.GraphKeys.QUEUE_RUNNERS`            | 处理输入的QueueRunner                  | 输入处理                     |
| `tf.GraphKeys.MOVING_AVERAGE_VARIABLES` | 所有计算了滑动平均值的变量             | 计算变量的滑动平均值         |

#### 二、Tensorflow数据模型——张量

在Tensorflow中，所有数据通过张量形式表示，可被理解为多维数组。零阶张量表示**标量**，就是一个数；一阶张量为**向量**，就是一维数组；n阶张量可以理解为一个n维数组。但是Tensorflow中张量并非采用数组形式，它只是对Tensorflow中运算结果的引用，张量中保存的不是数字，而是得到这些数字的计算过程。

```python
#载入Tensorflow
import tensorflow as tf
#tf.constant是一个计算，结果是一个张亮，保存在a中
a = tf.constant([1.0,2.0], name = "a")
b = tf.constant([2.0,3.0], name = "b")
result = tf.add(a,b,name="add")
print(result)
输出：
# 名字：节点的第一个输出 维度     类型:每个张量类型唯一，不匹配会报错
Tensor("add_2:0", shape=(2,), dtype=float32)
```

从上面看出：Tensorflow计算结果不是一个具体数字而是一个张量的结构。

张量的使用主要分为两类：

* 对中间计算结果的引用

  ```python
  #使用张量记录中间结果
  a = tf.constant([1,2], name = "a", dtype=tf.float32)
  b = tf.constant([2.0,3.0], name = "b")
  result = tf.add(a,b,name="add")
  
  #直接计算向量和,可读性差
  result= tf.constant([1.0,2.0], name="a") + tf.constant([2.0,3.0], name='b')
  ```

* 获取计算结果

  可以使用tf.Session().run(result)得到计算结果

#### 三、Tensorflow运行模型——会话（session）

session拥有并管理Tensorflow程序运行时的所有资源，当所有计算完成后需要关闭session来帮助系统回收资源。否则可能资源泄露。

创建会话有两种模式：

* 明确会话生成和关闭函数: 当程序异常退出时将不能关闭会话导致资源泄露

  ```python
  #创建会话
  sess = tf.Session()
  #运算
  sess.run(...)
  # 关闭会话，释放资源
  sess.close()
  ```

* 通过Python上下文管理器使用会话

  ```python
  #创建会话，通过上下文管理器管理会话
  with tf.Session() as sess:
      sess.run(...)
  #上下文退出时自动关闭session与释放资源
  ```

Tensorflow可以制定默认的session,默认session被指定后可通过tf.Tensor.eval函数计算一个张量的取值，有如下几种设定方式：

```python
1.
sess = tf.Session()
with sess.as_default():
    print(result.eval())
```

```python
2.
sess = tf.Session()
print(result.eval(session=sess))
```

```python
3.交互环境下直接构造默认会话，tf.InteractiveSession会自动将生成的会话注册为默认会话。
sess = tf.InteractiveSession()
print(result.eval())
sess.close()
```

无论使用哪种方法都可以通过ConfigProto Protocol Bufefer配置要生成的会话，通过ConfigProto可以配置类似并行的线程数、GPU分配策略、运算超时时间等参数。

```python
config = tf.ConfigProto(allow_soft_placement = True,#当某些运算无法被GPU支持时，自动调整到cpu
                       log_device_placement = True)#日志中记录每个节点被安排在那个设备上
sess1 = tf.InteractiveSession(config=config)
sess2 = tf.Session(config=config)
```

#### 四、Tensorflow实现神经网络

在Tensorflow中，变量的作用就是保存和更新神经网络中的参数，Tensorflow变量需要赋初始值，在神经网络中，给参数赋予随机初始值最常见，所以一般使用随机数给Tensorflow中变量初始化。

`weighTensorflow = tf.Variable(tf.random_normal([2,3], stddev = 2))`会产生一个2*3的随机数矩阵，矩阵元素均值为0，标准差为2，random_normal还可以通过参数mean指定平均数，在没指定时默认为零。通过满足正态分布的随机数来初始化神经网络中的参数是一个很常用的方法，还有一些其他随机数生成器：

![](http://p5s7d12ls.bkt.clouddn.com/18-7-8/22556167.jpg)

Tensorflow也支持通过常熟来初始化一个变量：

| 函数名      | 功能                         | 样例                                     |
| ----------- | ---------------------------- | ---------------------------------------- |
| tf.zeros    | 产生全0数组                  | tf.zeros([2,3],tf.int32) ->[[000],[000]] |
| tf.ones     | 产生全1数组                  |                                          |
| tf.fill     | 产生一个全部为给定数字的数组 | tf.fill([2,3],9)->[[9,9,9],[9,9,9]]      |
| tf.constant | 产生一个给定值的数组         |                                          |

神经网络的前向传播：

![](http://p5s7d12ls.bkt.clouddn.com/18-7-9/34664713.jpg)



![](http://p5s7d12ls.bkt.clouddn.com/18-7-9/39006147.jpg)

```python
import tensorflow as tf
#声明变量，通过seed设定随机数种子
w1 = tf.Variable(tf.random_normal([2,3], stddev=1, seed=1))
w2 = tf.Variable(tf.random_normal([3,1], stddev=1, seed=1))
#将输入特征向量定义为常量，这里x是一个1*2的矩阵
x = tf.constant([[0.7,0.9]])
#通过前向算法，计算矩阵乘法
a = tf.matmul(x,w1)
y = tf.matmul(a,w2)

sess = tf.Session()
#初始化变量的两种方式
#1.分开挨个初始化
# sess.run(w1.initializer)
# sess.run(w2.initializer)
#2.一次性初始化所有变量tf.global_variables_initializer
init_op = sess.run(tf.global_variables_initializer())
sess.run(y)

print(sess.run(y))
sess.close()
```

上述代码实现了神经网络的前向传播过程,在计算y之前，需运行w1.initializer和w2.initializer给变量赋值，虽然直接调用变量的初始化过程是一个可行方案，但是当变量数目增多时，或者变量之间存在依赖关系时，单个调用就比较麻烦。因此可以使用tf.global_variables_initializer一次性初始化所有变量。

Tensorflow中所有变量都会被自动加入GraphKeys.VARIABLES集合，当构建机器学习模型时，可以通过变量生命函数中的trainable参数来区分需要优化的参数（比如神经网络中的参数）和其他参数（如迭代的轮数），如果声明trainable为True,变量会被加入GraphKeys.TRAINABLE_VARIABLES集合，可以通过tf.trainable_variable函数得到需要优化的参数。， Tensorflow中提供的神经网络优化算法会将GraphKeys.TRAINABLE_VARIABLES集合中的变量作为默认的优化对象。

**维度**和**类型**也是变量的两个重要属性，变量类型不可改变，维度在运行中可改变，通过设置参数validate_shape=False。

在神经网络优化算法中，最常用的是反向传播法（bp）,流程图如下：

![](http://p5s7d12ls.bkt.clouddn.com/18-7-9/44477907.jpg)



​	每次迭代开始前要先选取一小部分训练数据，这一小部分叫一个batch,如果每轮迭代选取的数据都要通过常量来表示，那么Tensorflow的计算图会太大，因为每生成一个常量，Tensorflow都会在计算图中增加一个节点。为此，Tensorflow提供了placeholder机制用于提供输入数据，相当于定义了一个位置，这个位置中的数据在程序运行时再指定。在定义placeholder时，这个位置上的数据类型需要指定，且不可改变。

​	在得到一个batch的前向传播结果之后，需要定义一个损失函数来刻画当前的预测值和真实值之间的差距，然后通过反向传播算法来调整网络参数的取值使差距缩小。

例子：利用神经网络解决二分类问题

```python
import tensorflow as tf
from numpy.random import RandomState
# 定义训练数据batch大小
batch_size = 8
#定义神经网络参数
w1 = tf.Variable(tf.random_normal([2,3],stddev=1,seed=1))
w2 = tf.Variable(tf.random_normal([3,1],stddev=1,seed=1))
#在shape的一个维度上使用none可以方便使用不大的batch大小
x = tf.placeholder(tf.float32, shape=(None, 2), name='x-input')
y_ = tf.placeholder(tf.float32, shape=(None,1), name='y-input')

a = tf.matmul(x,w1)
y = tf.matmul(a, w2)
#定义损失函数和反向传播算法
cross_entropy = - tf.reduce_mean(y_ * tf.log(tf.clip_by_value(y, 1e-10,1.0)))
train_step = tf.train.AdamOptimizer(0.01).minimize(cross_entropy)
#随机数模拟数据集
rdm  = RandomState(1)
dataset_size = 128
X = rdm.rand(dataset_size, 2)
# 根据x1+x2<1判断正反例
Y= [[int (x1 + x2 <1)] for (x1,x2) in X]
with tf.Session() as sess:
    init_op = tf.initialize_all_variables()
    sess.run(init_op)
    print(sess.run(w1))
    print(sess.run(w2))
    STEPS = 5000
    for i in range(STEPS):
        start = (i * batch_size) % dataset_size
        end = min(start + batch_size, dataset_size)
        #通过选取的样本训练网络并更新参数
        sess.run(train_step, feed_dict={x:X[start:end], y_:Y[start:end]})
        if i % 1000 == 0:
            #每隔一段时间计算交叉熵
            total_cross_entropy = sess.run(cross_entropy, feed_dict={x:X,y_:Y})
            print("After %d training steps(s), cross entropy on all data is %g" % (i, total_cross_entropy))
```

总结：神经网络训练步骤：

1. 定义网络结构和前向传输的输出结果
2. 定义损失函数及选择反向传播优化算法
3. 生成会话并在训练数据上反复运行反向传播优化算法



