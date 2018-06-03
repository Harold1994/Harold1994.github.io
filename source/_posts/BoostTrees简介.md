---
title: BoostTrees简介
date: 2018-05-28 00:11:25
tags: 机器学习
---
本文翻译自陈天奇大神的英文ppt,喜欢看英文的同学可以[直接跳转](https://homes.cs.washington.edu/~tqchen/pdf/BoostedTree.pdf),翻译当中也增加了一些个人的补充.

## 一、监督学习的关键概念

#### 监督学习中的元素

$x_i \in R^D$ :训练集中第i条记录

**模型**： 根据$x_i$预测$\hat y_i$
<!-- more--> 
线性模型：$\hat y_i = \sum_j \omega_jx_{ij}$（包括线性回归和逻辑回归）

在不同的任务中$y^i$有不同的解释：

- 线性回归中：$y^i$是预测得分
- 逻辑回归中：$1/(1+exp(- \hat y))$是结果为正例的概率
- 其他任务，比如打分中，表示预测的分数

**参数**：我们需要从数据中习得的东西

线性模型：$\Theta = \lbrace\omega_j|j=1,…,d\rbrace$

#### 目标函数

$object(\Theta) = L(\Theta) + \Omega(\Theta)$

**训练集的损失**：$L = \sum_{i=1}^nl(y_i, \hat y_i)$

- 平方损失：$l(y_i, \hat y_i) = (y_i - \hat y_i)^2$
- Logistic损失：$l(y_i, \hat y_i) = y_iln(1+e^{-y^i}) + (1+e^{\hat y_i})$

**正则化项**：描述模型结构复杂程度

- L2正则化：$\Omega(\omega) = \lambda||\omega||^2$
- L1正则化：$\Omega(\omega) = \lambda||\omega||_1$ 

#### 已知的线性回归目标函数

**岭回归**：$\sum_{i=1}^n(y_i-\omega^Tx_i)^2 - \lambda||\omega||^2$

​	线性模型，平方损失， L2正则化

**Lasso回归：**$\sum_{i=1}^n(y_i-\omega^Tx_i)^2 - \lambda||\omega||_1$

​	线性回归， 平方损失， L1正则化

**Logistic回归：**$\sum_{i=1}^n[ y_iln(1+e^{-\omega^Tx_i})+ (1+e^{\omega^Tx_i})^2] - \lambda||\omega||^2$

​	线性回归， logistic损失， L2正则化

模型，参数，目标之间的概念分离也为带来了工程上的好处。



#### 方差与偏差的权衡

- 偏差.

  这里的偏指的是 **偏离** , 那么它偏离了什么到导致了误差? 潜意识上, 当谈到这个词时, 我们可能会认为它是偏离了某个潜在的 “标准”, 而这里这个 “标准” 也就是真实情况 (ground truth). 在分类任务中, 这个 “标准” 就是真实标签 (label).

- 方差.

  很多人应该都还记得在统计学中, 一个随机变量的方差描述的是它的离散程度, 也就是该随机变量在其期望值附近的 **波动程度** . 

先从下面的靶心图来对方差与偏差有个直观的感受：

![img](https://liuchengxu.github.io/blog-cn/assets/images/posts/bulls-eye-diagram.png)

假设红色的靶心区域是学习算法完美的正确预测值, 蓝色点为每个数据集所训练出的模型对样本的预测值, 当我们从靶心逐渐向外移动时, 预测效果逐渐变差.

很容易看出有两副图中蓝色点比较集中, 另外两幅中比较分散, 它们描述的是方差的两种情况. 比较集中的属于方差小的, 比较分散的属于方差大的情况.

再从蓝色点与红色靶心区域的位置关系, 靠近红色靶心的属于偏差较小的情况, 远离靶心的属于偏差较大的情况.

![img](https://liuchengxu.github.io/blog-cn/assets/images/posts/bulls-eye-label-diagram.png)

[本节偏差方差解释部分来自博客]https://blog.csdn.net/simple_the_best/article/details/71167786

将目标函数分为损失函数和正则化项的原因在于：

- 优化训练损失会激励预测模型

  ​	对训练数据集的良好拟合，至少可以让模型在训练数据上表现良好，有可能更接近数据的底层分布

- 优化正则化项有利于产生简单的模型

  ​	简单的模型在预测数据上方差更小，使模型可靠性更强

## 二、回归树和集成方法

**回归树（CART,又叫分类回归树）**

- 像决策树一样制定规则
- 每个叶节点包含一个值

例子：判断是否喜欢电脑游戏

![](http://p5s7d12ls.bkt.clouddn.com/18-5-10/74239098.jpg)



**回归树集成：最终的得分是每个树得分的和**
![](http://p5s7d12ls.bkt.clouddn.com/18-5-10/14929391.jpg)



**树集成方法 ——模型和参数**

- 模型：假设我们有K个树

  $\hat y_i = \sum_{k=1}^Kf_k(x_i)  ,  f_k\in F$，F是包含所有回归树的函数空间

考虑：回归树是将属性对应为得分的函数

- 参数
  - 包括每棵树的结构和叶子结点的得分
  - 或简单的被当作参数适用：$\Theta = \lbrace f_1, f_2,…,f_K\rbrace$
  - 我们学习的是functions(trees)而不是$R^d$中的权重

#### 在单变量上学习回归树

- 如何学习目标函数？


- 定义目标函数(loss， regularization),然后优化它。
- 比如：
  - 考虑在单输入t = (time)上的回归树
  - 想要预测是否想在t时刻听浪漫音乐

![](http://p5s7d12ls.bkt.clouddn.com/18-5-10/86261125.jpg)

- 需要学习的东西：

  ![](http://p5s7d12ls.bkt.clouddn.com/18-5-10/41162967.jpg)

- 单变量回归树（阶梯函数）的目标：

  - 训练损失：函数对点的拟合程度如何？
  - 结构损失：如何定义函数的结构复杂度？
    - 分裂点的数量，每段高度的L2正则化。

![](http://p5s7d12ls.bkt.clouddn.com/18-5-11/75298105.jpg)



#### 集成回归树的目标函数

- 模型：假设我们有K棵树

  $\hat y_i = \sum_{k=1}^Kf_k(x_i)  ,  f_k\in F$

- 目标函数：

  $Obj = \sum_{i=1}^nl(y,\hat y_i) + \sum_{k=1}^K\Omega(k)$

- 定义$\Omega$可能的方式：

  - 树的节点数，深度
  - L2正规项叶子权重的
  - ...

#### 客观性与启发式

- 当谈及决策树时，经常是启发式的
  - 同个信息增益进行分割
  - 剪枝
  - 最大化树深度
  - 平滑叶节点
- 大多数启发式方法都符合目标，采取正式的（客观）观点让我们知道我们正在学习什么：
  - 信息增益 -》减少训练损失
  - 剪枝 -》根据节点正则化
  - 最大化树深度 -》函数空间的约束
  - 平滑叶子value -》 叶子权重的L2正则化

#### 回归树不仅仅是为了回归问题

- 集成回归树定义了如何获取得分，可被用于分类，回归，打分等场景，取决于如何定义目标函数：

  - 使用平方损失：梯度提升回归树（common gradient boosted machine）
  - 使用Logistic损失：LogitBoost

  ​

### 三、Gradient Boosting

- 目标函数：

  ​	$Obj = \sum_{i=1}^nl(y,\hat y_i) + \sum_{k=1}^K\Omega(f_k), f_k\in F$

- 我们不能使用梯度下降法来得到f，因为他们是树而不是简单的数值向量。

- 解决办法：*additive training*(boosting)

  - 从常量预测开始， 每次增加一个新的函数

![](http://p5s7d12ls.bkt.clouddn.com/18-5-11/97010343.jpg)



#### 模型学习：additive training

现在还剩下一个问题，我们如何选择每一轮加入什么f呢？答案是非常直接的，选取一个f来使得我们的目标函数尽量最大地降低。
[![5](http://dataunion.org/wp-content/uploads/2015/04/510.png)](http://dataunion.org/wp-content/uploads/2015/04/510.png)
这个公式可能有些过于抽象，我们可以考虑当l是平方误差的情况。这个时候我们的目标可以被写成下面这样的二次函数9：
[![6](http://dataunion.org/wp-content/uploads/2015/04/61.png)](http://dataunion.org/wp-content/uploads/2015/04/61.png)
更加一般的，对于不是平方误差的情况，我们会采用如下的泰勒展开近似来定义一个近似的目标函数，方便我们进行这一步的计算。
[![7](http://dataunion.org/wp-content/uploads/2015/04/72.png)](http://dataunion.org/wp-content/uploads/2015/04/72.png)
当我们把常数项移除之后，我们会发现如下一个比较统一的目标函数。这一个目标函数有一个非常明显的特点，它只依赖于每个数据点的在误差函数上的一阶导数和二阶导数。有人可能会问，这个材料似乎比我们之前学过的决策树学习难懂。为什么要花这么多力气来做推导呢？
[![8](http://dataunion.org/wp-content/uploads/2015/04/82.png)](http://dataunion.org/wp-content/uploads/2015/04/82.png)

- 因为这样做使得我们可以很清楚地理解整个目标是什么，并且一步一步推导出如何进行树的学习。
- 这一个抽象的形式对于实现机器学习工具也是非常有帮助的。传统的GBDT可能大家可以理解如优化平法a残差，但是这样一个形式包含可所有可以求导的目标函数。也就是说有了这个形式，我们写出来的代码可以用来求解包括回归，分类和排序的各种问题，**正式的推导可以使得机器学习的工具更加一般**。

#### 树的复杂度

到目前为止我们讨论了目标函数中训练误差的部分。接下来我们讨论如何定义树的复杂度。我们先对于f的定义做一下细化，把树拆分成结构部分q和叶子权重部分w。下图是一个具体的例子。结构函数q把输入映射到叶子的索引号上面去，而w给定了每个索引号对应的叶子分数是什么。
[![9](http://dataunion.org/wp-content/uploads/2015/04/94.png)](http://dataunion.org/wp-content/uploads/2015/04/94.png)
当我们给定了如上定义之后，我们可以定义一棵树的复杂度如下。这个复杂度包含了一棵树里面节点的个数，以及每个树叶子节点上面输出分数的$L2$模平方。当然这不是唯一的一种定义方式，不过这一定义方式学习出的树效果一般都比较不错。下图还给出了复杂度计算的一个例子。

[![10](http://dataunion.org/wp-content/uploads/2015/04/102.png)](http://dataunion.org/wp-content/uploads/2015/04/102.png)

#### 重新审视目标

- 定义叶子j上面样本集合$ I_j =\lbrace i|q(x_i)=j\rbrace$

- 根据叶子重新组织目标

  [![a](http://dataunion.org/wp-content/uploads/2015/04/a-1024x199.png)](http://dataunion.org/wp-content/uploads/2015/04/a.png)

- 由二次函数零点定理,有:

  ​	$argmin_x$  $Gx+\frac {1}{2}Hx^2 = -\frac {G}{H}, H>0$

- 二次函数的最低点性质有: $min_x$ $Gx+\frac {1}{2}Hx^2 = -\frac {1}{2}G^2/H$

- 可以定义

  ​	[![QQ截图20150423163401](http://dataunion.org/wp-content/uploads/2015/04/QQ截图20150423163401.png)](http://dataunion.org/wp-content/uploads/2015/04/QQ截图20150423163401.png)

  那么这个目标函数可以进一步改写成如下的形式[![QQ截图20150423163423](http://dataunion.org/wp-content/uploads/2015/04/QQ截图20150423163423.png)](http://dataunion.org/wp-content/uploads/2015/04/QQ截图20150423163423.png)

  假设我们已经知道树的结构q(x)，我们可以通过这个目标函数来求解出最优的w，以及最好的w对应的目标函数最大的增益[![QQ截图20150423163446](http://dataunion.org/wp-content/uploads/2015/04/QQ截图20150423163446.png)](http://dataunion.org/wp-content/uploads/2015/04/QQ截图20150423163446.png)

#### 结构分数的计算

Obj代表了当我们指定一个树的结构的时候，我们在目标上面最多减少多少。我们可以把它叫做结构分数(structure score)。你可以认为这个就是类似吉尼系数一样更加一般的对于树结构进行打分的函数。下面是一个具体的打分函数计算的例子
[![1](http://dataunion.org/wp-content/uploads/2015/04/143.png)](http://dataunion.org/wp-content/uploads/2015/04/143.png)

#### 枚举所有不同树结构

- 枚举所有可能的树结构

- 利用得分等式,计算q的结构分数

  ​	$Obj = -\frac{1}{2}\sum_{j=1}^T \frac{G_j^2}{H_j+\lambda} + \gamma T$

- 找到最好的树结构,使用最优的叶子权重 $\omega_j^*=-\frac{G_i}{H_j+\lambda}$

- 但是,可能有无穷尽的树结构,

#### 树结构的贪心法

常用的方法是贪心法，每一次尝试去对已有的叶子加入一个分割。

- 从深度为0的树开始
- 对每一个叶子节点尝试进行分割,我们可以获得的增益可以由如下公式计算

[](http://www.52cs.org/wp-content/uploads/2015/04/12.png)[![image1](http://dataunion.org/wp-content/uploads/2015/04/image1.png)](http://dataunion.org/wp-content/uploads/2015/04/image1.png)
对于每次扩展，我们还是要枚举所有可能的分割方案，如何高效地枚举所有的分割呢？

假设我们要枚举所有 x<a 这样的条件，对于某个特定的分割a我们要计算a左边和右边的导数和。
[![13](http://dataunion.org/wp-content/uploads/2015/04/133.png)](http://dataunion.org/wp-content/uploads/2015/04/133.png)
我们可以发现对于所有的a，我们只要做一遍从左到右的扫描就可以枚举出所有分割的梯度和GL和GR。然后用上面的公式计算每个分割方案的分数就可以了。

观察这个目标函数，大家会发现第二个值得注意的事情就是引入分割不一定会使得情况变好，因为我们有一个引入新叶子的惩罚项。优化这个目标对应了树的剪枝， 当引入的分割带来的增益小于一个阀值的时候，我们可以剪掉这个分割。大家可以发现，当我们正式地推导目标的时候，像计算分数和剪枝这样的策略都会自然地出现，而不再是一种因为heuristic而进行的操作了。

#### 总操作概述

![](http://p5s7d12ls.bkt.clouddn.com/18-5-28/19435924.jpg)

讲到这里文章进入了尾声，虽然有些长，希望对大家有所帮助，这篇文章介绍了如何通过目标函数优化的方法比较严格地推导出boosted tree的学习。因为有这样一般的推导，得到的算法可以直接应用到回归，分类排序等各个应用场景中去。

