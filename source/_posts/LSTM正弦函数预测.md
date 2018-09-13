---
title: LSTM正弦函数预测
date: 2018-09-12 08:47:28
tags: [机器学习, tensorflow, 深度学习]
---

```python
import numpy as np
import tensorflow as tf

import matplotlib as mpl
%matplotlib inline
mpl.use('Agg')
from matplotlib import pyplot as plt

HIDDEN_SIZE=30#LSTM中隐藏节点个数
NUM_LAYERS=2 #LSTM层数

TIMESTEPS = 10 #rnn的训练序列长度
TRAINING_STEPS = 10000 #训练轮数
BATCH_SIZE = 32 #batch大小

TRAINING_EXAMPLE = 10000 #训练数据个数
TESTING_EXAMPLE = 1000 #测试数据个数
SAMPLE_GAP = 0.01 #采样间隔

def generate_data(seq):
    X = []
    Y = []
    #用sin函数前TIMESTEPS个点的信息，预测第i+TIMESTEPS的值
    for i in range(len(seq)-TIMESTEPS):
        X.append([seq[i:i+TIMESTEPS]])
        Y.append([seq[i + TIMESTEPS]])
    return np.array(X, dtype=np.float32), np.array(Y, np.float32)

def lstm_model(X,y,istraining):
    #使用多层LSTM结构
    cell = tf.nn.rnn_cell.MultiRNNCell([
        tf.nn.rnn_cell.BasicLSTMCell(HIDDEN_SIZE)
        for _ in range(NUM_LAYERS)])
    #outputs是最上层LSTM每一步输出的结果，维度是[batch_size, time, HODDEN_SIZE],这里只关心最后的结果
    outputs,_ = tf.nn.dynamic_rnn(cell, X, dtype=tf.float32)
    output = outputs[:,-1,:]
    #全连接层计算结果
    predictions = tf.contrib.layers.fully_connected(
        output, 1, activation_fn=None)
    
    if not istraining:
        return predictions, None, None
    
    #计算损失函数
    loss = tf.losses.mean_squared_error(labels=y, predictions=predictions)
    
    train_op = tf.contrib.layers.optimize_loss(
        loss,tf.train.get_global_step(),
        optimizer='Adagrad',learning_rate=0.1)
    return predictions, loss, train_op


def train(sess, train_X, train_Y):
    #将训练数据以数据集的方式提供给计算图
    ds = tf.data.Dataset.from_tensor_slices((train_X, train_Y))#作用是切分传入Tensor的第一个维度，生成相应的dataset。
    ds = ds.repeat().shuffle(1000).batch(BATCH_SIZE)
    #实例化了一个Iterator，这个Iterator是一个“one shot iterator”，即只能从头到尾读取一次
    X,y = ds.make_one_shot_iterator().get_next()
    with tf.variable_scope("model"):
        predictions, loss, train_op = lstm_model(X,y,True)
    
    sess.run(tf.global_variables_initializer())
    for i in range(TRAINING_STEPS):
        _,l = sess.run([train_op,loss])
    if i % 100 == 0:
        print("training step: " + str(i) + ", loss: " + str(1))

def run_eval(sess, test_X, test_Y):
    ds = tf.data.Dataset.from_tensor_slices((test_X, test_Y))
    ds=ds.batch(1)
    X,y = ds.make_one_shot_iterator().get_next()
    
    with tf.variable_scope("model", reuse=True):
        prediction, _,_ = lstm_model(X,[0.0],False)
        predictions = []
        labels=[]
        for i in range(TESTING_EXAMPLE):
            p,l = sess.run([prediction,y]) 
            predictions.append(p)
            labels.append(l)
        predictions=np.array(predictions).squeeze()
        labels =  np.array(labels).squeeze()
        rmse = np.sqrt(((predictions-labels)**2).mean(axis=0))
        print("MRSE is : %f" % rmse)

        plt.figure()
        plt.plot(predictions, label="predictions")
        plt.plot(labels, label = "real_sin")
        plt.legend()
        plt.show()

#用正弦函数产生数据集
tf.reset_default_graph()
test_start =  (TRAINING_EXAMPLE + TIMESTEPS)*SAMPLE_GAP
test_end = test_start+(TESTING_EXAMPLE+TIMESTEPS)*SAMPLE_GAP
train_X , train_Y = generate_data(np.sin(np.linspace(
0,test_start,TRAINING_EXAMPLE+TIMESTEPS, dtype=np.float32)))
test_X , test_Y = generate_data(np.sin(np.linspace(
test_start,test_end,TESTING_EXAMPLE+TIMESTEPS, dtype=np.float32)))

with tf.Session() as sess:
    train(sess, train_X, train_Y)
    run_eval(sess, test_X, test_Y)
```

