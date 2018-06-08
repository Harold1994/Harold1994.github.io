---
title: lightGbm简要原理
date: 2018-06-07 01:47:18
tags: 机器学习
---

本文转自:https://blog.csdn.net/niaolianjiulin/article/details/76584785

和https://www.cnblogs.com/wanglei5205/p/8722237.html

# 1. lightGBM简介

xgboost的出现，让数据民工们告别了传统的机器学习算法们：RF、GBM、SVM、LASSO……..。现在微软推出了一个新的boosting框架，想要挑战xgboost的江湖地位。

顾名思义，lightGBM包含两个关键点：light即轻量级，GBM 梯度提升机。

LightGBM 是一个梯度 boosting 框架，使用基于学习算法的决策树。它可以说是分布式的，高效的，有以下优势：

- 更快的训练效率
- 低内存使用
- 更高的准确率
- 支持并行化学习
- 可处理大规模数据
<!-- more-->
与常用的机器学习算法进行比较：速度飞起

![这里写图片描述](https://img-blog.csdn.net/20170802163943148?watermark/2/text/aHR0cDovL2Jsb2cuY3Nkbi5uZXQvbmlhb2xpYW5qaXVsaW4=/font/5a6L5L2T/fontsize/400/fill/I0JBQkFCMA==/dissolve/70/gravity/SouthEast)

# 2. xgboost缺点

XGB的介绍见[此篇博文](http://blog.csdn.net/niaolianjiulin/article/details/76574216)

其缺点，或者说不足之处：

- 每轮迭代时，都需要遍历整个训练数据多次。如果把整个训练数据装进内存则会限制训练数据的大小；如果不装进内存，反复地读写训练数据又会消耗非常大的时间。
- 预排序方法（pre-sorted）：首先，空间消耗大。这样的算法需要保存数据的特征值，还保存了特征排序的结果（例如排序后的索引，为了后续快速的计算分割点），这里需要消耗训练数据两倍的内存。其次时间上也有较大的开销，在遍历每一个分割点的时候，都需要进行分裂增益的计算，消耗的代价大。
- 对cache优化不友好。在预排序后，特征对梯度的访问是一种随机访问，并且不同的特征访问的顺序不一样，无法对cache进行优化。同时，在每一层长树的时候，需要随机访问一个行索引到叶子索引的数组，并且不同特征访问的顺序也不一样，也会造成较大的cache miss。

# 3. lightGBM特点

以上与其说是xgboost的不足，倒不如说是lightGBM作者们构建新算法时着重瞄准的点。解决了什么问题，那么原来模型没解决就成了原模型的缺点。

概括来说，lightGBM主要有以下特点：

- **基于Histogram的决策树算法**
- **带深度限制的Leaf-wise的叶子生长策略**
- 直方图做差加速
- 直接支持类别特征(Categorical Feature)
- Cache命中率优化
- 基于直方图的稀疏特征优化
- 多线程优化

前2个特点使我们尤为关注的。

**Histogram算法**

直方图算法的基本思想：先把连续的浮点特征值离散化成k个整数，同时构造一个宽度为k的直方图。遍历数据时，根据离散化后的值作为索引在直方图中累积统计量，当遍历一次数据后，直方图累积了需要的统计量，然后根据直方图的离散值，遍历寻找最优的分割点。

**带深度限制的Leaf-wise的叶子生长策略**

Level-wise过一次数据可以同时分裂同一层的叶子，容易进行多线程优化，也好控制模型复杂度，不容易过拟合。但实际上Level-wise是一种低效算法，因为它不加区分的对待同一层的叶子，带来了很多没必要的开销，因为实际上很多叶子的分裂增益较低，没必要进行搜索和分裂。

Leaf-wise则是一种更为高效的策略：每次从当前所有叶子中，找到分裂增益最大的一个叶子，然后分裂，如此循环。因此同Level-wise相比，在分裂次数相同的情况下，Leaf-wise可以降低更多的误差，得到更好的精度。

Leaf-wise的缺点：可能会长出比较深的决策树，产生过拟合。因此LightGBM在Leaf-wise之上增加了一个最大深度限制，在保证高效率的同时防止过拟合。

# 4. lightGBM调参

（1）num_leaves

LightGBM使用的是leaf-wise的算法，因此在调节树的复杂程度时，使用的是num_leaves而不是max_depth。

大致换算关系：num_leaves = 2^(max_depth)

（2）样本分布非平衡数据集：可以param[‘is_unbalance’]=’true’

（3）Bagging参数：bagging_fraction+bagging_freq（必须同时设置）、feature_fraction

（4）min_data_in_leaf、min_sum_hessian_in_leaf

```python
// 01. train set and test set
train_data = lgb.Dataset(dtrain[predictors],label=dtrain[target],feature_name=list(dtrain[predictors].columns), categorical_feature=dummies)

test_data = lgb.Dataset(dtest[predictors],label=dtest[target],feature_name=list(dtest[predictors].columns), categorical_feature=dummies)

// 02. parameters
param = {
    'max_depth':6,
    'num_leaves':64,
    'learning_rate':0.03,
    'scale_pos_weight':1,
    'num_threads':40,
    'objective':'binary',
    'bagging_fraction':0.7,
    'bagging_freq':1,
    'min_sum_hessian_in_leaf':100
}

param['is_unbalance']='true'
param['metric'] = 'auc'

// 03. cv and train
bst=lgb.cv(param,train_data, num_boost_round=1000, nfold=3, early_stopping_rounds=30)

estimators = lgb.train(param,train_data,num_boost_round=len(bst['auc-mean']))

// 04. test predict
ypred = estimators.predict(dtest[predictors])12345678910111213141516171819202122232425262728
```

**# lightgbm关键参数**

[![image](https://images2018.cnblogs.com/blog/1307402/201804/1307402-20180405133821380-233032611.png)](https://images2018.cnblogs.com/blog/1307402/201804/1307402-20180405133820459-1387924067.png)

**# lightgbm调参方法cv**

[代码github地址](https://github.com/wanglei5205/Machine_learning/blob/master/Boosting--LightGBM/lgb-python/2.lightgbm%E8%B0%83%E5%8F%82%E6%A1%88%E4%BE%8B.py)

[![复制代码](https://common.cnblogs.com/images/copycode.gif)](javascript:void(0);)

```python
1 # -*- coding: utf-8 -*-
2 """
3 # 作者：wanglei5205
4 # 邮箱：wanglei5205@126.com
5 # 博客：http://cnblogs.com/wanglei5205
6 # github：http://github.com/wanglei5205
7 """
8 ### 导入模块
9 import numpy as np
10 import pandas as pd
11 import lightgbm as lgb
12 from sklearn import metrics
13
14 ### 载入数据
15 print('载入数据')
16 dataset1 = pd.read_csv('G:/ML/ML_match/IJCAI/data3.22/3.22ICJAI/data/7_train_data1.csv')
17 dataset2 = pd.read_csv('G:/ML/ML_match/IJCAI/data3.22/3.22ICJAI/data/7_train_data2.csv')
18 dataset3 = pd.read_csv('G:/ML/ML_match/IJCAI/data3.22/3.22ICJAI/data/7_train_data3.csv')
19 dataset4 = pd.read_csv('G:/ML/ML_match/IJCAI/data3.22/3.22ICJAI/data/7_train_data4.csv')
20 dataset5 = pd.read_csv('G:/ML/ML_match/IJCAI/data3.22/3.22ICJAI/data/7_train_data5.csv')
21
22 print('数据去重')
23 dataset1.drop_duplicates(inplace=True)
24 dataset2.drop_duplicates(inplace=True)
25 dataset3.drop_duplicates(inplace=True)
26 dataset4.drop_duplicates(inplace=True)
27 dataset5.drop_duplicates(inplace=True)
28
29 print('数据合并')
30 trains = pd.concat([dataset1,dataset2],axis=0)
31 trains = pd.concat([trains,dataset3],axis=0)
32 trains = pd.concat([trains,dataset4],axis=0)
33
34 online_test = dataset5
35
36 ### 数据拆分(训练集+验证集+测试集)
37 print('数据拆分')
38 from sklearn.model_selection import train_test_split
39 train_xy,offline_test = train_test_split(trains,test_size = 0.2,random_state=21)
40 train,val = train_test_split(train_xy,test_size = 0.2,random_state=21)
41
42 # 训练集
43 y_train = train.is_trade                                               # 训练集标签
44 X_train = train.drop(['instance_id','is_trade'],axis=1)                # 训练集特征矩阵
45
46 # 验证集
47 y_val = val.is_trade                                                   # 验证集标签
48 X_val = val.drop(['instance_id','is_trade'],axis=1)                    # 验证集特征矩阵
49
50 # 测试集
51 offline_test_X = offline_test.drop(['instance_id','is_trade'],axis=1)  # 线下测试特征矩阵
52 online_test_X  = online_test.drop(['instance_id'],axis=1)              # 线上测试特征矩阵
53
54 ### 数据转换
55 print('数据转换')
56 lgb_train = lgb.Dataset(X_train, y_train, free_raw_data=False)
57 lgb_eval = lgb.Dataset(X_val, y_val, reference=lgb_train,free_raw_data=False)
58
59 ### 设置初始参数--不含交叉验证参数
60 print('设置参数')
61 params = {
62           'boosting_type': 'gbdt',
63           'objective': 'binary',
64           'metric': 'binary_logloss',
65           }
66
67 ### 交叉验证(调参)
68 print('交叉验证')
69 min_merror = float('Inf')
70 best_params = {}
71
72 # 准确率
73 print("调参1：提高准确率")
74 for num_leaves in range(20,200,5):
75     for max_depth in range(3,8,1):
76         params['num_leaves'] = num_leaves
77         params['max_depth'] = max_depth
78
79         cv_results = lgb.cv(
80                             params,
81                             lgb_train,
82                             seed=2018,
83                             nfold=3,
84                             metrics=['binary_error'],
85                             early_stopping_rounds=10,
86                             verbose_eval=True
87                             )
88
89         mean_merror = pd.Series(cv_results['binary_error-mean']).min()
90         boost_rounds = pd.Series(cv_results['binary_error-mean']).argmin()
91
92         if mean_merror < min_merror:
93             min_merror = mean_merror
94             best_params['num_leaves'] = num_leaves
95             best_params['max_depth'] = max_depth
96
97 params['num_leaves'] = best_params['num_leaves']
98 params['max_depth'] = best_params['max_depth']
99
100 # 过拟合
101 print("调参2：降低过拟合")
102 for max_bin in range(1,255,5):
103     for min_data_in_leaf in range(10,200,5):
104             params['max_bin'] = max_bin
105             params['min_data_in_leaf'] = min_data_in_leaf
106
107             cv_results = lgb.cv(
108                                 params,
109                                 lgb_train,
110                                 seed=42,
111                                 nfold=3,
112                                 metrics=['binary_error'],
113                                 early_stopping_rounds=3,
114                                 verbose_eval=True
115                                 )
116
117             mean_merror = pd.Series(cv_results['binary_error-mean']).min()
118             boost_rounds = pd.Series(cv_results['binary_error-mean']).argmin()
119
120             if mean_merror < min_merror:
121                 min_merror = mean_merror
122                 best_params['max_bin']= max_bin
123                 best_params['min_data_in_leaf'] = min_data_in_leaf
124
125 params['min_data_in_leaf'] = best_params['min_data_in_leaf']
126 params['max_bin'] = best_params['max_bin']
127
128 print("调参3：降低过拟合")
129 for feature_fraction in [0.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0]:
130     for bagging_fraction in [0.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0]:
131         for bagging_freq in range(0,50,5):
132             params['feature_fraction'] = feature_fraction
133             params['bagging_fraction'] = bagging_fraction
134             params['bagging_freq'] = bagging_freq
135
136             cv_results = lgb.cv(
137                                 params,
138                                 lgb_train,
139                                 seed=42,
140                                 nfold=3,
141                                 metrics=['binary_error'],
142                                 early_stopping_rounds=3,
143                                 verbose_eval=True
144                                 )
145
146             mean_merror = pd.Series(cv_results['binary_error-mean']).min()
147             boost_rounds = pd.Series(cv_results['binary_error-mean']).argmin()
148
149             if mean_merror < min_merror:
150                 min_merror = mean_merror
151                 best_params['feature_fraction'] = feature_fraction
152                 best_params['bagging_fraction'] = bagging_fraction
153                 best_params['bagging_freq'] = bagging_freq
154
155 params['feature_fraction'] = best_params['feature_fraction']
156 params['bagging_fraction'] = best_params['bagging_fraction']
157 params['bagging_freq'] = best_params['bagging_freq']
158
159 print("调参4：降低过拟合")
160 for lambda_l1 in [0.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0]:
161     for lambda_l2 in [0.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0]:
162         for min_split_gain in [0.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0]:
163             params['lambda_l1'] = lambda_l1
164             params['lambda_l2'] = lambda_l2
165             params['min_split_gain'] = min_split_gain
166
167             cv_results = lgb.cv(
168                                 params,
169                                 lgb_train,
170                                 seed=42,
171                                 nfold=3,
172                                 metrics=['binary_error'],
173                                 early_stopping_rounds=3,
174                                 verbose_eval=True
175                                 )
176
177             mean_merror = pd.Series(cv_results['binary_error-mean']).min()
178             boost_rounds = pd.Series(cv_results['binary_error-mean']).argmin()
179
180             if mean_merror < min_merror:
181                 min_merror = mean_merror
182                 best_params['lambda_l1'] = lambda_l1
183                 best_params['lambda_l2'] = lambda_l2
184                 best_params['min_split_gain'] = min_split_gain
185
186 params['lambda_l1'] = best_params['lambda_l1']
187 params['lambda_l2'] = best_params['lambda_l2']
188 params['min_split_gain'] = best_params['min_split_gain']
189
190
191 print(best_params)
192
193 ### 训练
194 params['learning_rate']=0.01
195 lgb.train(
196           params,                     # 参数字典
197           lgb_train,                  # 训练集
198           valid_sets=lgb_eval,        # 验证集
199           num_boost_round=2000,       # 迭代次数
200           early_stopping_rounds=50    # 早停次数
201           )
202
203 ### 线下预测
204 print ("线下预测")
205 preds_offline = lgb.predict(offline_test_X, num_iteration=lgb.best_iteration) # 输出概率
206 offline=offline_test[['instance_id','is_trade']]
207 offline['preds']=preds_offline
208 offline.is_trade = offline['is_trade'].astype(np.float64)
209 print('log_loss', metrics.log_loss(offline.is_trade, offline.preds))
210
211 ### 线上预测
212 print("线上预测")
213 preds_online =  lgb.predict(online_test_X, num_iteration=lgb.best_iteration)  # 输出概率
214 online=online_test[['instance_id']]
215 online['preds']=preds_online
216 online.rename(columns={'preds':'predicted_score'},inplace=True)           # 更改列名
217 online.to_csv("./data/20180405.txt",index=None,sep=' ')                   # 保存结果
218
219 ### 保存模型
220 from sklearn.externals import joblib
221 joblib.dump(lgb,'lgb.pkl')
222
223 ### 特征选择
224 df = pd.DataFrame(X_train.columns.tolist(), columns=['feature'])
225 df['importance']=list(lgb.feature_importance())                           # 特征分数
226 df = df.sort_values(by='importance',ascending=False)                      # 特征排序
227 df.to_csv("./data/feature_score_20180331.csv",index=None,encoding='gbk')  # 保存分数
```
