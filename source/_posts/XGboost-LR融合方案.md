---
title: XGboost+LR融合方案
date: 2018-06-20 16:43:27
tags: 机器学习
---

最近在做比赛，是一道用户活跃度预测的题目，在讨论中发现大牛说XGboost+LR融合效果不错，想要动手试一下，学习笔记记录在此处，之前已经翻译过关于BoostTree的ppt，有兴趣的可以移步到本站的[另一篇博客](https://harold1994.github.io/2018/05/28/BoostTrees%E7%AE%80%E4%BB%8B/).

<!-- more-->

本博客借鉴了以下博客的内容：

https://blog.csdn.net/a358463121/article/details/77993198?locationNum=10&fps=1

https://cloud.tencent.com/developer/article/1006009

https://www.deeplearn.me/1797.html

LR (逻辑回归) 算法因其简单有效，成为工业界最常用的算法之一。但 LR  算法是线性模型，不能捕捉到非线性信息，需要大量特征工程找到特征组合。为了发现有效的特征组合，Facebook 在 2014年介绍了通过 GBDT （Gradient Boost Decision Tree）+ LR 的方案 （XGBoost 是 GBDT 的后续发展）。随后 Kaggle 竞赛实践证明此思路的有效性。

#### 1. XGBoost + LR 的原理

XGBoost + LR 融合方式原理很简单。先用数据训练一个 XGBoost 模型，然后将训练数据中的实例给 XGBoost 模型得到实例的叶子节点，然后将叶子节点当做特征训练一个 LR 模型。它的核心思想是将boosting看作是一个将样本进行非线性变换的方法。那么我们处理特征变换的一般方法有：

- 对于连续的特征：一个简单的非线性变化就是将特征划分到不同的区域(bin)，然后再将这些区域的编号看作一个离散的特征来进行训练。这也就是俗称的连续变量离散化方法，这有非常多的方法可以完成这项事情。
- 对于离散的特征：我们可以直接对离散特征做一个笛卡尔积从而得到一系列特征的组合，当然有些组合是没用的，那些没用的组合可以删掉。

XGBoost + LR 的结构如下所示。

![](http://p5s7d12ls.bkt.clouddn.com/18-6-20/29693732.jpg)

我们知道对每一个样本，都对应着每颗树上的一个叶子结点，比如说如上图，我们一共训练了2颗树，一共有5个叶子结点，那么我们可以将这5个叶子结点进行编号，然后用1- k ont  hot来表示他们的取值，如果x样本在第一颗树中经过映射到达第2个叶子结点，在第二颗树上到达第二棵树上的第一个叶子结点，那么我们就可以得到样本经过变化后的向量为 [0,1,0,1,0] ,这5个数就表示叶子结点的，1对应的就是将样本是否落在了这个叶子结点上。直观来看，我们将一个样本向量，经过变换成了一个0,1的向量。最后我们使用经过变换后的特征再放进任意一个训练器中训练，比如说LR。需要注意的是在 sklearn 或者 xgboost 输出的结果都是叶子节点的 index，所以需要自己动手去做 onehot 编码，然后交给 lr 训练，onehot 你可以在 sklearn 的预处理包中调用即可

#### 2. XGBoost 叶子节点不能取代特征工程

为了验证 XGBoost + LR 是尝试自动替代特征工程的方法，还只是一种特征工程的方法，我们在自己业务的数据上做了一些实验。下图便是实验结果，其中: “xgboost+lr1" 是 XGBoost 的叶子节点特征、原始属性特征和二阶交叉特征一起给 LR 进行训练；"xgboost+lr2" 则只有叶子节点特征给 LR；"lr1" 是原始属性特征和二阶交叉特征; "lr2" 只有原始属性特征。

![img](https://blog-10039692.file.myqcloud.com/1505977730620_2673_1505977730658.png)

从上面的实验来看：1) "xgboost+lr2" 明显弱于 "lr1" 方法，说明只用叶子节点特征的 XGBoost + LR 弱于有特征工程的 LR 算法。即 XGBoost 叶子节点不能取代特征工程，XGBoost + LR 无法取代传统的特征工程。2) "xgboost+lr1" 取得了所有方法中的最好效果，说明了保留原来的特征工程 XGBoost + LR 方法拥有比较好的效果。即 XGBoost 叶子节点特征是一种有效的特征，XGBoost + LR 是一种有效的特征工程手段。

上面的实验结果和我同事二哥之前的实验结果一致。在他实验中没有进行二阶交叉的特征工程技巧，结果 XGBoost > XGBoost + LR > LR，其中 XGBoost +LR 类似我们的 "xgboost+lr2" 和 LR 类似于我们的 "lr2"。

#### 3. 强大的 XGBoost

只用 XGBoost 叶子节点特征， XGBoost + LR 接近或者弱于 XGBoost 。在下图中，我们发现 XGBoost 的每个叶子节点都有权重 w, 一个实例的预测值和这个实例落入的叶子节点的权重之和有关。

![img](https://blog-10039692.file.myqcloud.com/1505977752394_385_1505977752517.png)

如果二分类 XGBoost 使用了 sgmoid 做激活函数, 即参数为 "binary:logistic", 则 XGBoost 的最终预测值等于 sgmoid(叶子节点的权重之和)。而 LR 的最终预测值等于 sgmoid (特征对应的权重之后)。因此 LR 只要学到叶子节点的权重，即可以将 XGBoost 模型复现出来。因此理论上，如果 LR 能学到更好的权重，即使只有叶子节点特征的 XGBoost + LR 效果应该好于 XGBoost。总结起来，XGBoost + LR 相当于对 XGBoost 的权重进行 reweight。

但是从上面的结果来看，XGBoost + LR 要接近或者弱于 XGBoost。XGBoost 赋予叶子节点的权重是很不错的，LR 学到的权重无法明显地超过它。

#### 4.XGboost+LR实例

```Python
import xgboost as xgb
from sklearn.datasets import load_svmlight_file
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_curve, auc, roc_auc_score
from sklearn.externals import joblib
from sklearn.preprocessing import  OneHotEncoder
import numpy as np
from scipy.sparse import hstack
 
def xgb_feature_encode(libsvmFileNameInitial):
 
    # load 样本数据
    X_all, y_all = load_svmlight_file(libsvmFileNameInitial)
 
    # 训练/测试数据分割
    X_train, X_test, y_train, y_test = train_test_split(X_all, y_all, test_size = 0.3, random_state = 42)
 
    # 定义模型
    xgboost = xgb.XGBClassifier(nthread=4, learning_rate=0.08,
                            n_estimators=50, max_depth=5, gamma=0, subsample=0.9, colsample_bytree=0.5)
    # 训练学习
    xgboost.fit(X_train, y_train)

    # 预测及 AUC 评测
    y_pred_test = xgboost.predict_proba(X_test)[:, 1]
    xgb_test_auc = roc_auc_score(y_test, y_pred_test)
    print('xgboost test auc: %.5f' % xgb_test_auc)
 
    # xgboost 编码原有特征
    X_train_leaves = xgboost.apply(X_train)
    X_test_leaves = xgboost.apply(X_test)
    # 训练样本个数
    train_rows = X_train_leaves.shape[0]
    # 合并编码后的训练数据和测试数据
    X_leaves = np.concatenate((X_train_leaves, X_test_leaves), axis=0)
    X_leaves = X_leaves.astype(np.int32)
 
    (rows, cols) = X_leaves.shape
 
    # 记录每棵树的编码区间
    cum_count = np.zeros((1, cols), dtype=np.int32)
 
    for j in range(cols):
        if j == 0:
            cum_count[0][j] = len(np.unique(X_leaves[:, j]))
        else:
            cum_count[0][j] = len(np.unique(X_leaves[:, j])) + cum_count[0][j-1]
 
    print('Transform features genenrated by xgboost...')
    # 对所有特征进行 ont-hot 编码，注释部分是直接使用 onehot 函数，结果输出保证是 libsvm 格式也可以使用
    #sklearn 中的 dump_svmlight_file 操作，这个文件代码是参考别人的代码，这些点都是可以优化的。
 
    # onehot=OneHotEncoder()
    # onehot.fit(X_leaves)
    # x_leaves_encode=onehot.transform(X_leaves)
    for j in range(cols):
        keyMapDict = {}
        if j == 0:
            initial_index = 1
        else:
            initial_index = cum_count[0][j-1]+1
        for i in range(rows):
            if X_leaves[i, j] not in keyMapDict:
                keyMapDict[X_leaves[i, j]] = initial_index
                X_leaves[i, j] = initial_index
                initial_index = initial_index + 1
            else:
                X_leaves[i, j] = keyMapDict[X_leaves[i, j]]
 
    # 基于编码后的特征，将特征处理为 libsvm 格式且写入文件
    print('Write xgboost learned features to file ...')
    xgbFeatureLibsvm = open('xgb_feature_libsvm', 'w')
    for i in range(rows):
        if i < train_rows:
            xgbFeatureLibsvm.write(str(y_train[i]))
        else:
            xgbFeatureLibsvm.write(str(y_test[i-train_rows]))
        for j in range(cols):
            xgbFeatureLibsvm.write(' '+str(X_leaves[i, j])+':1.0')
        xgbFeatureLibsvm.write('\n')
    xgbFeatureLibsvm.close()
 
 
def xgboost_lr_train(xgbfeaturefile, origin_libsvm_file):
 
    # load xgboost 特征编码后的样本数据
    X_xg_all, y_xg_all = load_svmlight_file(xgbfeaturefile)
    X_train, X_test, y_train, y_test = train_test_split(X_xg_all, y_xg_all, test_size = 0.3, random_state = 42)
 
    # load 原始样本数据
    X_all, y_all = load_svmlight_file(origin_libsvm_file)
    X_train_origin, X_test_origin, y_train_origin, y_test_origin = train_test_split(X_all, y_all, test_size = 0.3, random_state = 42)
 
 
    # lr 对原始特征样本模型训练
    lr = LogisticRegression(n_jobs=-1, C=0.1, penalty='l1')
    lr.fit(X_train_origin, y_train_origin)
    joblib.dump(lr, 'lr_orgin.m')
    # 预测及 AUC 评测
    y_pred_test = lr.predict_proba(X_test_origin)[:, 1]
    lr_test_auc = roc_auc_score(y_test_origin, y_pred_test)
    print('基于原有特征的 LR AUC: %.5f' % lr_test_auc)
 
    # lr 对 load xgboost 特征编码后的样本模型训练
    lr = LogisticRegression(n_jobs=-1, C=0.1, penalty='l1')
    lr.fit(X_train, y_train)
    joblib.dump(lr, 'lr_xgb.m')
    # 预测及 AUC 评测
    y_pred_test = lr.predict_proba(X_test)[:, 1]
    lr_test_auc = roc_auc_score(y_test, y_pred_test)
    print('基于 Xgboost 特征编码后的 LR AUC: %.5f' % lr_test_auc)
 
    # 基于原始特征组合 xgboost 编码后的特征
    X_train_ext = hstack([X_train_origin, X_train])
    del(X_train)
    del(X_train_origin)
    X_test_ext = hstack([X_test_origin, X_test])
    del(X_test)
    del(X_test_origin)
 
    # lr 对组合后的新特征的样本进行模型训练
    lr = LogisticRegression(n_jobs=-1, C=0.1, penalty='l1')
    lr.fit(X_train_ext, y_train)
    joblib.dump(lr, 'lr_ext.m')
    # 预测及 AUC 评测
    y_pred_test = lr.predict_proba(X_test_ext)[:, 1]
    lr_test_auc = roc_auc_score(y_test, y_pred_test)
    print('基于组合特征的 LR AUC: %.5f' % lr_test_auc)
 
if __name__ == '__main__':
    xgb_feature_encode("/Users/leiyang/xgboost/demo/data/agaricus.txt.train")
    xgboost_lr_train("xgb_feature_libsvm","/Users/leiyang/xgboost/demo/data/agaricus.txt.train")
```

