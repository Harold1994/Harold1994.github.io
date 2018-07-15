---
title: tenserflow——深层神经网络
date: 2018-07-14 23:55:12
tags: [tensorflow, 深度学习]
---

#### 一、激活函数

​	神经网络中激活函数的主要作用是提供网络的非线性建模能力，如不特别说明，激活函数一般而言是非线性函数。假设一个示例神经网络中仅包含线性卷积和全连接运算，那么该网络仅能够表达线性映射，即便增加网络的深度也依旧还是线性映射，难以有效建模实际环境中非线性分布的数据。加入（非线性）激活函数之后，深度神经网络才具备了分层的非线性映射学习能力。

<!-- more--> 	

- **非线性：**如果不用激励函数，每一层输出都是上层输入的线性函数，无论神经网络有多少层，输出都是输入的线性组合。如果使用的话，激活函数给神经元引入了非线性因素，使得神经网络可以任意逼近任何非线性函数，这样神经网络就可以应用到众多的非线性模型中。当激活函数是非线性的时候，一个两层的神经网络就可以逼近基本上所有的函数了。但是，如果激活函数是恒等激活函数的时候，就不满足这个性质了，而且如果MLP使用的是恒等激活函数，那么其实整个网络跟单层神经网络是等价的。
- **可微性：** 当优化方法是基于梯度的时候，这个性质是必须的。
- **单调性：** 当激活函数是单调的时候，单层网络能够保证是凸函数。当激活函数满足这个性质的时候，如果参数的初始化是random的很小的值，那么神经网络的训练将会很高效；如果不满足这个性质，那么就需要很用心的去设置初始值。
- **输出值的范围：** 当激活函数输出值是有限的时候，基于梯度的优化方法会更加稳定，因为特征的表示受有限权值的影响更显著；当激活函数的输出是无限的时候，模型的训练会更加高效，不过在这种情况小，一般需要更小的learning rate。

##### 常见的激活函数

![](http://p5s7d12ls.bkt.clouddn.com/18-7-15/83868805.jpg)

**1. Sigmoid函数** 
  Sigmoid图形为一个S型曲线,函数定义如下： 

​                                                                            $f(x)=\frac 1{1+e^{-x}}$

  Sigmoid函数将实数压缩到0~1区间。大的负数变成0，大的正数变成1。sigmoid函数由于其强大的解释力，常被用来表示神经元的活跃度程度：从不活跃（0）到假设上最大的（1）。在实践中，sigmoid函数最近从受欢迎到不受欢迎，很少再被使用。 
它有两个主要缺点： 

1. sigmoid容易饱和，出现梯度消失的现象。sigmoid神经元的一个很差的属性就是神经元的活跃度在0和1处饱和，它的梯度在这些地方接近于0。回忆在反向传播中，某处的梯度和其目标输出的梯度相乘，以得到整个目标。因此，如果某处的梯度过小，就会很大程度上出现梯度消失，使得几乎没有信号经过这个神经元以及所有间接经过此处的数据。除此之外，人们必须额外注意sigmoid神经元权值的初始化来避免饱和。例如，当初始权值过大，几乎所有的神经元都会饱和以至于网络几乎不能学习。 
2. Sigmoid 的输出不是0均值的，这是我们不希望的，因为这会导致后层的神经元的输入是非0均值的信号，这会对梯度产生影响：假设后层神经元的输入都为正(e.g. x>0 elementwise in f=wTx+b),那么对w求局部梯度则都为正，这样在反向传播的过程中w要么都往正方向更新，要么都往负方向更新，导致有一种捆绑的效果，使得收敛缓慢。 但是如果你是按batch去训练，那么每个batch可能得到不同的符号（正或负），那么相加一下这个问题还是可以缓解。 

**2. tanh函数**

tanh和sigmoid函数是有异曲同工之妙的，不同的是它把实值得输入压缩到-1~1的范围。

优点：因为其输入的范围为-1~1，因此它基本是0均值的，这也就解决了上述sigmoid缺点中的第二个，所以实际中tanh会比sigmoid更常用。    

缺点：它依然存在梯度饱和的问题。 

**3. ReLU函数 **

优点：  

1. 其在梯度下降上与tanh/sigmoid相比有更快的收敛速度。这被认为时其线性、非饱和的形式。    
2. 不会出现梯度消失的问题。    
3. Relu会使一部分神经元的输出为0，这样就造成了网络的稀疏性，并且减少了参数的相互依存关系，缓解了过拟合问题的发生。    
4. sigmoid和tanh涉及了很多很expensive的操作（比如指数），ReLU可以更加简单的实现。  

缺点：    

​	ReLU单元脆弱且可能会在训练中死去。例如，大的梯度流经过ReLU单元时可能导致神经不会在以后任何数据节点再被激活。当这发生时，经过此单元的梯度将永远为零。ReLU单元可能不可逆地在训练中的数据流中关闭。例如，比可能会发现当学习速率过快时你40%的网络都“挂了”（神经元在此后的整个训练中都不激活）。当学习率设定恰当时，这种事情会更少出现。 

#### 二、 交叉熵

在信息论中，交叉熵是表示两个概率分布p,q，其中p表示真实分布，q表示非真实分布，在相同的一组事件中，其中，用非真实分布q来表示某个事件发生所需要的平均比特数。

假设现在有一个样本集中两个概率分布p,q，其中p为真实分布，q为预测分布，通过q来表示p的交叉熵为：

​                                      $H(p,q)=-\sum_xp(s)\log {q(x)}$	

实际上，交叉熵是衡量两个概率分布p，q之间的相似性,而神经网络的输出却不一定是一个概率分布。SoftMax回归可以将神经网络前向传播得到的结果变成概率分布。

![](http://p5s7d12ls.bkt.clouddn.com/18-7-15/91325298.jpg)

#### 三、自定义损失函数

tf中greater方法会返回输入张量中每个元素的比较结果，where方法类似于C语言中的`？：`操作符，有三个参数，第一个为选择条件，选择条件为真，返回第二个参数的值，为假，返回第三个参数的值。

```python
import tensorflow as tf
v1 = tf.constant([1.0,2.0,3.0,4.0])
v2 = tf.constant([4.0,3.0,2.0,1.0])

sess = tf.InteractiveSession()
print(tf.greater(v1,v2).eval())
print(tf.where(tf.greater(v1,v2),v1,v2).eval())
```

Tensorflow中封装了许多损失函数供用户调用，如

```python
#使用了softmax回归之后的交叉损失函数，y_代表真实值
tf.nn.softmax_cross_entropy_with_logiTensorflow(y,y_)
```

```python
#均方差的实现
tf.reduce_mean(tf.square(y_ - y))
```

Tensorflow不仅支持经典损失函数，还可以自定义损失函数，如：

​                     $Loss(y,y') = \sum_{i=1}^nf(y_i,y_i'), \ f(x,y) = \begin{cases} a(x-y) & x>y\\ b(y-x)&x\le y\end{cases}$

可以用如下方式实现：

```python
loss = tf.reduce_sum(tf.where(tf.greater(v1,v2), (v1-v2)*a,(v2-v1)*b))
```

#### 四、神经网络优化算法

反向传播算法是训练神经网络的核心算法，可以根据定义好的损失函数优化神经网络中参数的取值。目前没有通用方法可以对任意损失函数直接球的最佳参数取值，在实践中，梯度下降法是最常用的优化方法。

梯度下降法有不能达到全局最优和计算时间长的缺点，而随机梯度下降优化的不是在全部训练数据上的损失函数，而是在每一轮迭代中，随机优化某一条训练数据上的损失函数，所有问题也很明显，某一条数据上损失函数更小并不代表全局损失更小，所以可能连局部最优都达不到。在实际应用中，采用折中办法，每次计算一小部分（一个batch）训练数据的损失函数,这样每次在一个batch上优化的参数并不会比单个数据慢太多，此外可以大大减少迭代次数，是收敛到更接近梯度下降的结果。

#### 五、 神经网络进一步优化

**1. 学习率设置**

学习率控制参数更新速度，幅度过大，可能导致参数在最优值两侧来回移动，过小，速度会降低。Tensorflow提供了**指数衰减法**，`tf.train.exponential_decay`实现了指数衰减学习率，这样学习率先大后小，使模型在后期逐渐稳定。

**2. 过拟合**

解决方法：正则化

L1正则化会让参数变得更稀疏，即有更多参数变为零，这样可以达到类似特征选取的功能。L2正则做不到这一点是因为当参数很小时，这个参数的平方基本可被忽略，于是模型不会进一步将这个参数调整为0。

其次L1正则化的计算公式不可导，L2正则化公式可导，因为在优化时需要计算损失函数偏导数，所以对含有L2正则化的损失函数的优化会更加简洁。实践中也可以将两种正则共同使用。

下面给出了带L2正则化的损失函数定义：

```python
w=tf.Variable(tf.random_normal([2,1], stddev=1,seed=1))
t=tf.matmul(x,w)
#loss为损失函数，lambda表示正则化项的权重，w是需要计算正则化损失的参数
loss = tf.reduce_mean(tf.square(y_-y)) + tf.contrib.layers.l2_regularizer(lambda)(w)
```

`tf.contrib.layers.l2_regularizer`和`tf.contrib.layers.l1_regularizer`分别可以计算了L1和L2正则化项，其中tfh会将L2的正则化损失除以2使得求导得到的结果更加简洁。

```python
weighTensorflow= tf.constant([[1.0,-2.0],[-3.0,4.0]])
with tf.Session() as sess:
    #输出（1+2+3+4）*0.5=5
    print(sess.run(tf.contrib.layers.l1_regularizer(0.5)(weighTensorflow)))
    #输出（1+4+9+16）/2*0.5=7.5
    print(sess.run(tf.contrib.layers.l2_regularizer(.5)(weighTensorflow)))
```

对于简单神经网络，这种方式可以很好地计算带正则化的损失函数，但是当神经网络参数增多之后，这样可能导致损失函数loss的定义很长，可读性差且易出错，更主要的，网络结构复杂之后定义网络结构的部分和计算损失的部分可能不在同一个函数中，通过这样的方式计算损失函数就更不方便了。为解决此问题，可以使用Tensorflow提供的集合collection,它可以在一个计算图中保存一组实体（如张量）。

```python
#获取一层神经网络边上的权重，并将这个权重的L2正则化损失加入名称为‘losses’的集合中
def get_weight(shape, lambda):
    var = tf.Variable(tf.random_normal(shape), dtype=tf.float32)
    #add_to_collection函数将这个新生成变量的L2正则化损失加入集合
    #函数的第一个参数‘losses’是集合的名字，第二个参数是要加入这个集合的内容
    tf.add_to_collection('losses', tf.contrib.layers.l2_regularizer(lambda)(var))
    return var

x = tf.placeholder(tf.float32, shape=(None,2))
y_ = tf.placeholder(tf.float32, shape=(None,2))
batch_size = 8 
#定义每层网络中节点的个数
layers_dimension = [2,10,10,10,1]
#神经网络的层数
n_layers = len(layers_dimensions)

#这个变量维护前向传播时最深的结点，开始的时候就是输入层
cur_layer = x
#当前层节点个数
in_dimension = layers_dimensions[0]

#通过一个循环来生成5层全连接的神经网络结构
for i in range(1, n_layers):
    #layer_dimension[i]为下一层节点个数
    out_dimension = layers_dimension[i]
    #生成当前层中权重的变量，并将这个变量的L2正则化损失加入计算图上的集合
    weight = get_weight([in_dimension, out_dimension],0.01)
    bias = tf.Variable(tf.constant(0.1, shape=[out_dimension]))
    #使用ReLU激活函数
    curl_layer = tf.nn.relu(tf.matmul(cur_layer, weight) + bias)
    #进入下一层之前将下一层节点个数更新为当前节点个数
    in_dimension= layers_dimension[i]
#在定义神经网络前向传播的同时已经将所有L2正则化损失加入了图上的集合
#这里只需要计算科化模型在训练数据上表现的损失函数
mse_loss = tf.reduce_mean(tf.square(y_ - cur_layer))
#将均方误差损失函数加入损失集合
tf.add_to_collection('losses', mse_loss)

#get_collection返回集合元素列表，加起来就是最终损失函数
loss = tf.add_n(tf.get_collection('losses'))
```

**3. 滑动平均模型**

滑动平均模型可以使模型在测试数据上更鲁棒，在Tensorflow中提供了`tf.train.ExponentialMovingAverage`来实现滑动平均模型，在初始化ExponentialMovingAverage时，需要提供一个衰减率(decay).这个衰减率将用于控制模型的更新速度。ExponentialMovingAverage对每个变量维护一个影子变量，这个影子变量的初始值就是相应变量的初始值，每次运行变量更新时，影子变量的值会更新为：
                             $shadow\_variable=decay * shadow\_variable + (1-decay)*variable$

其中shadow_variable为影子变量，variable为待更新的变量，decay为衰减率。decay决定了模型更新的速度，decay越大模型越趋于稳定。在实际应用中，decay一般设为非常接近1的数，为了使模型在训练前期可以更新的更快，ExponentialMovingAverage提供了num_updatyes参数来动态设置decay的大小，如果在ExponentialMovingAverage初始化时提供了num_updates参数，那么每次使用的衰减率将是：
                                              $min\lbrace decay, \frac {1+num_updates}{10+num_updates}\rbrace$

```python
#定义一个变量用于计算滑动平均，初始值为0，手动指定类型为float32
#所有需要计算滑动平均的变量必须是实数型
v1 = tf.Variable(0, dtype=tf.float32)
#setp模拟神经网络中迭代的轮数，可用于动态控制衰减率
step = tf.Variable(0, trainable=False)

#定义一个滑动平均的类，初始化时给定了衰减率0.99，和控制衰减率的变量step
ema = tf.train.ExponentialMovingAverage(0.99, step)
#定义一个更新变量滑动平均的操作，需要给定一个列表，每次执行这个动作时
#这个列表中的变量都会被更新
maintain_average_op = ema.apply([v1])
with tf.Session() as sess:
    init_op = tf.global_variables_initializer()
    sess.run(init_op)
    #通过ema.average(v1)获取滑动平均之后变量的取值，在初始化之后变量v1的值和v1的滑动平均都是0
    print(sess.run([v1,ema.average(v1)])) #[0.0, 0.0]
    
  
    #更新变量v1的值到10
    sess.run(tf.assign(v1,5))
    #更新v1的滑动平均值，衰减率为min{0.99,(1+step)/(10+step)=0.1} = 0.1
    #所以v1的滑动平均值会被更新为0.1*0+0.9*5 =4.5
    sess.run(maintain_average_op)
    print(sess.run([v1,ema.average(v1)]))
    
      #更新变量step的值到5
    sess.run(tf.assign(step,10000))
    #更新变量v1的值到10000
    sess.run(tf.assign(v1,10))
    #更新v1的滑动平均值，衰减率为min{0.99,(1+step)/(10+step)=0.999} = 0.99
    #所以v1的滑动平均值会被更新为0.99*4.5+0.01*5 =4.5555
    sess.run(maintain_average_op)
    print(sess.run([v1,ema.average(v1)]))
    
    #再次更新滑动平均值，得到新的滑动平均值为0.94*4.555+0.01*10 = 4.60945
    sess.run(maintain_average_op)
    print(sess.run([v1, ema.average(v1)]))
```

