---
title: tensorflow——MNIST数字识别问题
date: 2018-07-15 21:40:42
tags: [tensorflow, 深度学习, 机器学习]
---

#### 一、 MNIST数据处理

**1. input_data.read_data_seTensorflow函数**

**功能**: 该函数生成的类能将MNIST数据集划分为train, validation和test三个数据集:

- train: 55000张图片
- validation: 5000张
- test: 10000张

trian和validation组成了训练数据集. 每一张图片是一个长度为784(=28*28像素)的一维数组.

<!-- more--> 

**2. mnist.train.next_batch函数**

从所有的训练数据集中读取一小部分(batch)用来训练.

#### 二、神经网络训练及不同模型结果对比

**1.Tensorflow训练神经网络**

```python
import tensorflow as tf
from tensorflow.examples.tutorials.mnist import input_data
#MNIST数据集相关常数
INPUT_NODE = 784
OUTPUT_NODE = 10
#配置神经网络的参数
LAYER1_NODE = 500#隐藏层节点个数
BATCH_SIZE = 100

LEARNING_RATE_BASE = 0.8
LEARNING_RATE_DECAY = 0.99

REGULARAZTION_RATE = 0.0001#正则化项系数
TRAINING_STEPS = 5000
MOVING_AVERAGE_DECAY = 0.99

#计算神经网络前向传播结果，定义了一个用ReLU激活函数的全连接神经网络
def inference(input_tensor, avg_class, weighTensorflow1, biases1, weighTensorflow2, biases2):
    #如果没有提供滑动平均类，直接用参数当前取值
    if avg_class == None:
        layer1 = tf.nn.relu(
            tf.matmul(input_tensor, weighTensorflow1) + biases1)
        return tf.matmul(layer1,weighTensorflow2) + biases2
    else:
        layer1 = tf.nn.relu(
            tf.matmul(input_tensor, avg_class.average(weighTensorflow1)) + avg_class.average(biases1))
        return tf.matmul(layer1, avg_class.average(weighTensorflow2)) + avg_class.average(biases2)

#训练模型的过程
def train(mnist):
    x = tf.placeholder(tf.float32,[None, INPUT_NODE], name='x-input')
    y_ = tf.placeholder(tf.float32,[None, OUTPUT_NODE],name='y-inpit')
    
    # 隐藏层参数
    weighTensorflow1 = tf.Variable(tf.truncated_normal([INPUT_NODE,LAYER1_NODE], stddev=0.1))
    biases1 = tf.Variable(tf.constant(0.1, shape=[LAYER1_NODE]))
    #输出层参数
    weighTensorflow2 = tf.Variable(tf.truncated_normal([LAYER1_NODE,OUTPUT_NODE],stddev=0.1))
    biases2 = tf.Variable(tf.constant(0.1, shape=[OUTPUT_NODE]))
    
    #计算在当前参数下前向传播的结果，不使用滑动平均
    y = inference(x, None, weighTensorflow1, biases1, weighTensorflow2, biases2)
    
    #定义存储训练轮数的变量，不需要计算滑动平均，因此指定为不可训练变量
    global_step = tf.Variable(0, trainable=False)
    # 初始化滑动平均类
    variable_average = tf.train.ExponentialMovingAverage(MOVING_AVERAGE_DECAY, global_step)
    #在所有代表神经网络参数的变量上使用滑动平均
    variable_average_op = variable_average.apply(tf.trainable_variables())
    #计算使用了滑动平均之后的前向传播结果
    average_y = inference(x, variable_average, weighTensorflow1, biases1, weighTensorflow2, biases2)
    
    #交叉熵，当分类问题中只有一个正确答案时，sparse_softmax_cross_entropy_with_logiTensorflow函数
    #可以加速交叉熵的计算。标准答案是长度为10的一维数组，而该函数需要提供的是一个正确答案的数字，因此用tf.argmax函数
    #来得到正确答案对应类别编号
    cross_entropy = tf.nn.sparse_softmax_cross_entropy_with_logiTensorflow(logiTensorflow=y, labels=tf.argmax(y_,1))
    #计算当前batch中所有样例的平均交叉熵
    cross_entropy_mean = tf.reduce_mean(cross_entropy)
    
    #L2损失函数
    regularizer = tf.contrib.layers.l2_regularizer(REGULARAZTION_RATE)
    regularization = regularizer(weighTensorflow1) + regularizer(weighTensorflow2)
    
    #总损失等于交叉熵损失加正则化损失
    loss = cross_entropy_mean + regularization
    
    #指数衰减的学习率
    learning_rate = tf.train.exponential_decay(
        LEARNING_RATE_BASE,#基础学习率
        global_step, #当前迭代轮数
        mnist.train.num_examples/BATCH_SIZE,#过完所有数据需要的迭代次数
        LEARNING_RATE_DECAY)#衰减速度

    # 优化损失函数
    train_step = tf.train.GradientDescentOptimizer(learning_rate).minimize(
        loss, global_step=global_step)

    #在训练神经网络模型时，每过一遍数据既需要通过反向传播来更新神经网络中的参数，
    #又要更新每一个参数的滑动平均值。为了一次完成多个操作，Tensorflow提供了tf.control_dependencies
    #和tf.group两种机制，下面两行等价于：train_op = tf.group(train_step, variable_average_op)
    with tf.control_dependencies([train_step, variable_average_op]):
        train_op = tf.no_op(name = 'train')


    #检验使用了滑动平均模型的神经网络前向传播结果是否正确，tf.argmax(average_y,1)
    #计算每个样例的预测答案，第二个参数1表示选取最大值的操作仅在第一个维度进行。于是得到结果是一个长度为batch
    #的一维bool数组
    correct_prediction = tf.equal(tf.argmax(average_y,1), tf.argmax(y_,1))
    #将bool数组转换为实数型，然后计算均值，即正确率
    accuracy = tf.reduce_mean(tf.cast(correct_prediction, tf.float32))

    with tf.Session() as sess:
        tf.initialize_all_variables().run()
        #验证数据
        validate_feed = {x: mnist.validation.images,
                         y_:mnist.validation.labels}
        #测试数据
        test_feed = {x: mnist.test.images, 
                     y_:mnist.test.labels}
        #迭代训练
        for i in range(TRAINING_STEPS):
            #每1000轮输出一次验证集上的测试结果
            if i%1000 == 0:
                validate_acc = sess.run(accuracy, feed_dict = validate_feed)
                print("After %d training steps(s), validation accuracy using average model is  %g"%(i,validate_acc))
            xs,ys = mnist.train.next_batch(BATCH_SIZE)
            sess.run(train_op, feed_dict = {x:xs, y_:ys})
        test_acc = sess.run(accuracy, feed_dict=test_feed)
        print("After %d training steps(s), test accuracy using average model is  %g"%(TRAINING_STEPS,test_acc))

def main(argv=None):
    mnist = input_data.read_data_seTensorflow('/data/', one_hot=True)
    train(mnist)

if __name__ == '__main__':
    tf.app.run()
```

**2. 使用验证集判断模型效果**

​	在上一节程序的开始设置了初始学习率，隐藏层节点数量，迭代轮数等参数，这些参数的取值是需要通过实验调整的，不能使用模型在测试数据上的效果选择参数，使用测试集可能导致模型过度拟合，从而失去对未知数据的预测能力，因此一般从训练集中选一部分做验证集，验证数据就可以评判不同参数取值下模型的表现。除了使用验证集，还可以使用交叉验证来验证模型效果，但是神经网络训练时间本身较长，用cv会花费大量时间，所以在海量数据情况下，一般更多使用验证集来评估模型效果。

#### 三、变量管理

​	在inference函数中传入了计算前向传播结果所需要的参数，当神经网络更复杂，参数更多的时候，就需要更好的方式来传递和管理神经网络中的参数。Tensorflow提供了通过**变量名**来创建和获取一个变量的机制，这样在不同的函数中可以直接通过变量的名字来使用变量。主要通过tf.get_variable和tf.variable_scope函数来实现。

除了tf.Variable，Tensorflow还可以用tf.get_variable函数来创建或获取变量，它和tf.Variable基本等价。

```python
v = tf.get_variable("v", shape=[1], 
                    initializer=tf.constant_initializer(1.0))
v = tf.Variable(tf.constant(1.0,shape=[1]), name="v")
```

Tensorflow提供了七种不同的初始化函数：

![](http://p5s7d12ls.bkt.clouddn.com/18-7-15/22335461.jpg)

​	tf.get_variable和tf.Variable函数最大的区别是制定变量名称的参数，后者的name=""参数可选,而对于tf.get_variable，变量名是一个必填的参数。tf.get_variable会根据这个名字去创建或获取变量，根据tf.get_variable创建的变量的变量名都是不可重复的。

​	如果需要通过tf.get_variable获取一个已经创建的变量，需要通过tf.variable_scope函数来生成一个上下文管理器，并明确指定在这个上下文管理器中，tf.get_variable将直接获取已经生成的变量。

```python
#在名字为foo的命名空间中创建名字为v的变量
with tf.variable_scope("foo"):
    v = tf.get_variable(
        "v", shape=[1], initializer=tf.constant_initializer(1.0))
    
#因为在foo中已经存在名字为v的变量，所以下面会报错
#riable foo/v already exisTensorflow, disallowed. Did you mean to set reuse=True or reuse=tf.AUTO_REUSE in VarScope? Originally defined at:

# with tf.variable_scope("foo"):
#     tf.get_variable("v",[1])

#在声明上下文管理器时，将参数reuse设为true，这样tf.get_variable函数将直接获取以声明的变量
with tf.variable_scope("foo",reuse=True):
    v1 = tf.get_variable("v",[1])
    print(v==v1) #True
```

Tensorflow中，tf.variable_scope可以嵌套：

```python
with tf.variable_scope("root"):
    #可以tf.get_variable_scope().reuse获取上下文中reuse参数的取值
    print(tf.get_variable_scope().reuse)#False,最外层reuse是False
    
    with tf.variable_scope("foo", reuse=True):
        print(tf.get_variable_scope().reuse)#True
        with tf.variable_scope("bar"):
            print(tf.get_variable_scope().reuse)#True,虽然bar没有制定
                                                #reuse,这时会和外层foo保持一致
    print(tf.get_variable_scope().reuse)#False，退出reuse为True的上下文后，又回到False
```

tf.variable_scope函数生成的上下文也会创建一个Tensorflow中的命名空间，在命名空间内创建的变量名称都会带上命名空间作为前缀，tf.variable_scope提供了一个管理变量命名空间的方式。

```python
v1 = tf.get_variable("v",[1])
print(v1.name) #v:0,v是变量名，0表示这个变量是生成变量这个运算的第一个结果

with tf.variable_scope("foo", reuse=True):
    v2 = tf.get_variable("v",[1])
    print(v2.name) #foo/v:0 在/前加了命名空间名称

with tf.variable_scope("foo",reuse=True):
    with tf.variable_scope("bar"):
        v3 = tf.get_variable("v",[1])
        print(v3.name)#foo/bar/v:0
    
    v4 = tf.get_variable("v",[1])
    print(v4.name)#foo/v:0

with tf.variable_scope("", reuse=True):
    #可以通过带命名空间名称的变量名来获取其他命名空间下的变量
    v5 = tf.get_variable("foo/bar/v",[1])
    print(v5 == v3)#True
    v6 = tf.get_variable("foo/v",[1])
    print(v6 == v4)
```