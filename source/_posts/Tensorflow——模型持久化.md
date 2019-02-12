---
title: Tensorflow——模型持久化
date: 2018-07-16 20:30:48
tags: [tensorflow, 深度学习, 机器学习]
---

​	前一篇MNIST数字数字识别的代码在训练完成之后就直接退出了，并没有将训练得到的模型保存下来方便下次直接使用，为了让训练结果可复用，需要将训练得到的神经网络模型持久化。

#### 一、持久化代码设计

ts提供了tf.train.Save类来还原一个神经网络,下面实现了持久化一个简单的tf模型，虽然只指定了一个文件路径，但是在文件目录下会出现三个文件，因为tf将计算图和图上参数取值分开保存。

<!-- more--> 	

```python
import tensorflow as tf
v1 = tf.Variable(tf.constant(1.0, shape=[1]), name="v1")
v2 = tf.Variable(tf.constant(2.0, shape=[1]), name="v2")
result = v1 + v2

init_op = tf.initialize_all_variables()
#用于保存模型
saver = tf.train.Saver()
with tf.Session() as sess:
    sess.run(init_op)
    saver.save(sess, "/data/model/model.ckpt")
```

下面演示如何加载模型：

```python
tf.reset_default_graph()
v1 = tf.Variable(tf.constant(3.0, shape=[1]), name="v1")#将v1设为3.0并不影响最后的结果为3.0
v2 = tf.Variable(tf.constant(2.0, shape=[1]), name="v2")
result = v1 + v2
saver = tf.train.Saver()
with tf.Session() as sess:
    #加载模型，通过已保存模型中的变量值来计算加法
    saver.restore(sess, "/data/model/model.ckpt")
    print(sess.run(result))#[3.]
```

加载的代码与保存的代码相比只是少了运行变量初始化的过程，而是将变量的值通过已保存的模型加载进来.

> 注：在本来的代码中没有第一句`tf.reset_default_graph()`会报错Key v1_1 not found in checkpoint，
>
> 原因： 保存和加载在前后进行，在前后两次定义了`v1= tf.Variable(xxx,name=”v1”)`
>
> 相当于 在TensorFlow 图的堆栈创建了两次 name = “v1” 的变量，第二个（第n个）的实际 name 会变成 “v1_1” ，之后我们在保存 checkpoint 中实际搜索的是 “v1_1” 这个变量 而不是 “v1” ，因此就会出错。
>
> 解决方案： 
> 在加载过程中，定义 name 相同的变量前面加 `tf.reset_default_graph()` 清除默认图的堆栈，并设置全局图为默认图

也可以直接加载已经持久化的图,以下代码默认加载了ts计算图上定义的全部变量。

```python
#直接加载持久化的图
saver = tf.train.import_meta_graph(
    "/data/model/model.ckpt.meta")
with tf.Session() as sess:
    saver.restore(sess, "/data/model/model.ckpt")
    print(sess.run(tf.get_default_graph().get_tensor_by_name("add:0")))
```

有时可能只需要保存或加载部分变量，比如神经网络前几层的参数，为保存或加载部分变量,声明tf.train.Saver类时可以提供一个需要保存或加载的列表。ts还支持在保存或加载时给变量重命名，可以通过字典将模型保存时的变量名和需要加载的变量联系在一起，这样可以方便使用滑动平均值

```python
import tensorflow as tf
v1 = tf.Variable(tf.constant(1.0, shape=[1]), name="other-v1")
v2 = tf.Variable(tf.constant(2.0, shape=[1]), name="other-v2")
result = v1 + v2
#用于保存模型
saver = tf.train.Saver({"v1":v1,"v2":v2})
with tf.Session() as sess:
    tf.global_variables_initializer().run()
    #模型一般后缀为ckpt
    saver.save(sess, "/data/model/model.ckpt")
    print(sess.run(result))
```

```python
import tensorflow as tf
v = tf.Variable(0, dtype=tf.float32, name="v")
#在没有申明滑动平均模型时只有一个变量v,所以下面语句只会输出“v：0”
for variables in tf.global_variables():
    print(variables.name)#v:0

ema = tf.train.ExponentialMovingAverage(0.99)
maintain_average_op = ema.apply(tf.global_variables())
#申明滑动平均模型之后，ts会自动生成一个影子变量v/ExponentialMoving Average
for variables in tf.global_variables():
    print(variables.name)
    #v:0
    #v/ExponentialMovingAverage:0

saver = tf.train.Saver()
with tf.Session() as sess:
    tf.global_variables_initializer().run()
    sess.run(tf.assign(v,10))
    sess.run(maintain_average_op)
    saver.save(sess, "/data/model/model.ckpt")
    print(sess.run([v, ema.average(v)]))#[10.0, 0.099999905]
```

ts为了方便加载时重命名滑动平均值，tf.train.ExponentialMovingAverage类提供了variables_to_restore函数来生成tf.train.Saver类所需要的变量重命名字典。

```python
import tensorflow as tf
tf.reset_default_graph()
v = tf.Variable(0, dtype=tf.float32, name="v")
ema = tf.train.ExponentialMovingAverage(0.99)
print(ema.variables_to_restore())
#输出：{'v/ExponentialMovingAverage': <tf.Variable 'v:0' shape=() dtype=float32_ref>}
#后面的Variable类代表v1
saver = tf.train.Saver(ema.variables_to_restore())
with tf.Session() as sess:
    saver.restore(sess, "/data/model/model.ckpt")
    print(sess.run(v))#输出：0.99999905,即原来变量的滑动平均值
```

使用tf.train.Saver会保存运行ts程序所需要的全部信息，然而有时候并不需要某些信息，ts提供了convert_variables_to_constants函数，将计算图中的变量及取值通过常量方式保存，这样整个图可以放到一个文件中：

```python
with tf.Session() as sess:
    tf.global_variables_initializer().run()
    #导出计算图GraphDef部分，只需要这一部分就可以完成从输入层到输出层的计算
    graph_def = tf.get_default_graph().as_graph_def()
    #将图中变量及取值转换为常量，去掉不必要节点，‘add’给出了需要保存的计算节点名称
    output_graph_def = graph_util.convert_variables_to_constants(
        sess, graph_def, ['add'])
    #将模型存入文件
    with tf.gfile.GFile("/data/model/combined_model.pb","wb") as f:
        f.write(output_graph_def.SerializeToString())
```

通过下面的代码可以直接计算定义的加法运算的结果，当只需要知道计算图中某个节点的取值时，这提供了一个更加方便的方法：

```python
from tensorflow.python.platform import gfile
with tf.Session() as sess:
    model_filename = "/data/model/combined_model.pb"
    #将文件解析成对应的GraphDef Protocol Buffer
    with gfile.FastGFile(model_filename,'rb') as f:
        graph_def = tf.GraphDef()
        graph_def.ParseFromString(f.read())
    #将graph_def中保存的图加载到当前的图中,加载的时候给出的是张量的名称，所以是add:0
    result = tf.import_graph_def(graph_def, return_elements=["add:0"])
    print(sess.run(result))
```

#### 二、重构MNIST数字识别代码

现在回顾上一篇博客中的代码中的弊端：

* 可扩展性差：计算前向传播函数需要将所有变量都传入，当神经网络结构变得更加复杂，参数更多时，程序可读性变得非常差
* 没有持久化训练好的模型：当程序退出时，无法使用训练好的模型，无法重用，没有在训练过程中每隔一段时间保存一次训练的中间结果，避免因死机造成的时间和资源浪费

本节将重构之前的代码，将训练和测试分成两个独立的程序，是的组件更加灵活。将前向传播的过程抽象成一个单独的库函数，使得使用方便且保证训练和测试过程中的前向传播算法一定是一致的。

**1. mnist_inference.py：前向传播过程集神经网络参数的定义**

```python
import tensorflow as tf
#结构参数
INPUT_NODE = 784
OUTPUT_NODE = 10
LAYER1_NODE = 500

def get_weight_variable(shape, regularizer):
    weights = tf.get_variable("weights",shape,initializer=tf.truncated_normal_initializer(stddev=0.1))
    #将正则化损失加入losses集合
    if regularizer != None:
        tf.add_to_collection('losses', regularizer(weights))
    return weights

def inference(input_tensor, regularizer):
    #声明第一层变量并完成前向传播
    with tf.variable_scope("layer1"):
        #因为在训练或者测试中没有在同一个程序中多次调用这个函数，所以不用考虑reuse
        weights = get_weight_variable(
            [INPUT_NODE,LAYER1_NODE],regularizer)
        biases = tf.get_variable("biases",[LAYER1_NODE],initializer=tf.constant_initializer(0.0))
        layer1 = tf.nn.relu(tf.matmul(input_tensor, weights) + biases)
        
    with tf.variable_scope("layer2"):
        weights = get_weight_variable([LAYER1_NODE, OUTPUT_NODE], regularizer)
        biases = tf.get_variable("biases", [OUTPUT_NODE],initializer=tf.constant_initializer(0.0))
        layer2 = tf.nn.relu(tf.matmul(layer1,weights) + biases)
    return layer2
```

**2.mnist_train.py:训练神经网络**

```python
import os
import tensorflow as tf
from tensorflow.examples.tutorials.mnist import input_data
import mnist_inference

BATCH_SIZE=100
LEARNING_RATE_BASE=0.8
LEARNING_RATE_DECAY=0.99
REGULARAZTION_RATE=0.0001
TRAINING_STEPS = 30000
MOVING_AVERAGE_DECAY=0.99

MODEL_SAVE_PATH="/data/model/"
MODEL_NAME="mnist_classify.ckpt"

def train(mnist):
    x = tf.placeholder(
        tf.float32,[None, mnist_inference.INPUT_NODE], name="x-input")
    y_ = tf.placeholder(
        tf.float32, [None, mnist_inference.OUTPUT_NODE], name="y-input")
    
    regularizer = tf.contrib.layers.l2_regularizer(REGULARAZTION_RATE)
    y= mnist_inference.inference(x,regularizer)
    global_step = tf.Variable(0,trainable=False)
    
    variable_averages = tf.train.ExponentialMovingAverage(MOVING_AVERAGE_DECAY, global_step)
    variable_averages_op = variable_averages.apply(tf.trainable_variables())
    
    cross_entropy = tf.nn.sparse_softmax_cross_entropy_with_logits(logits=y,labels=tf.argmax(y_,1))
    cross_entropy_mean = tf.reduce_mean(cross_entropy)
    loss = cross_entropy_mean + tf.add_n(tf.get_collection('losses'))
    learning_rate = tf.train.exponential_decay(
    LEARNING_RATE_BASE,
    global_step,
    mnist.train.num_examples/BATCH_SIZE,
    LEARNING_RATE_DECAY)
    train_step = tf.train.GradientDescentOptimizer(learning_rate).minimize(loss,global_step=global_step)
    with tf.control_dependencies([train_step, variable_averages_op]):
        train_op = tf.no_op(name="train")
        
    saver = tf.train.Saver()
    with tf.Session() as sess:
        tf.global_variables_initializer().run()
        for i in range(TRAINING_STEPS):
            xs,ys = mnist.train.next_batch(BATCH_SIZE)
            _,loss_value,step = sess.run([train_op, loss, global_step],
                                         feed_dict={x:xs,y_:ys})
            if i %1000 == 0:
                print("after %d training steps, loss on training batch is %g." % (step,loss_value))
                saver.save(sess, os.path.join(MODEL_SAVE_PATH, MODEL_NAME), global_step=global_step) 
                
def main(argv=None):
    mnist = input_data.read_data_sets("/data/", one_hot=True)
    train(mnist)
    
if __name__=='__main__':
    tf.app.run()
```

**3.mnist_eval.py**

```python
import time
import tensorflow as tf
from tensorflow.examples.tutorials.mnist import input_data
import mnist_inference
import mnist_train

#每10秒加载一次 模型
EVAL_INTERVAL_SECS = 10

def evaluate(mnist):
    with tf.Graph().as_default() as g:
        x = tf.placeholder(tf.float32,[None, mnist_inference.INPUT_NODE], name='x-input')
        y_ = tf.placeholder(tf.float32,[None,mnist_inference.OUTPUT_NODE], name='y-input')
        validate_feed = {x:mnist.validation.images,
                        y_:mnist.validation.labels}
        y = mnist_inference.inference(x,None)
        correct_prediction = tf.equal(tf.argmax(y,1), tf.argmax(y_,1))
        accuracy = tf.reduce_mean(tf.cast(correct_prediction, tf.float32))
        
        variable_averages = tf.train.ExponentialMovingAverage(mnist_train.MOVING_AVERAGE_DECAY)
        variables_to_restore = variable_averages.variables_to_restore()
        saver = tf.train.Saver(variables_to_restore)
        
        while True:
            with tf.Session() as sess:
                #get_checkpoint_state会通过checkpoint文件自动找到目录中最新模型的文件名
                ckpt = tf.train.get_checkpoint_state(mnist_train.MODEL_SAVE_PATH)
                if ckpt and ckpt.model_checkpoint_path:
                    saver.restore(sess, ckpt.model_checkpoint_path)
                    global_step = ckpt.model_checkpoint_path.split('/')[-1].split('-')[-1]
                    accuracy_score = sess.run(accuracy, feed_dict=validate_feed)
                    print("after %s training steps, validation accuracy  %g" % (global_step,accuracy_score))
                else:
                    print("no check point found")
                    return
            time.sleep(EVAL_INTERVAL_SECS)
def main(argv=None):
    mnist = input_data.read_data_sets("/data/", one_hot=True)
    evaluate(mnist)
if __name__=='__main__':
    tf.app.run()
```

