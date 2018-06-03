---
title: 用Mahout编写一个基本推荐系统
date: 2018-04-10 09:44:25
tags: [大数据,  推荐系统,  Mahout,  Hadoop]
---

Mahout是一个机器学习Java类库的集合用于完成各种任务，如分类、评价性的聚类和模式挖掘等。相对于Weka和RapidMIner等库，Mahout真正是为大规模数据集设计的，它的算法用Hadoop环境。
我们将使用Slope On推荐算法，它基于协同过滤方法，因为在Mahout0.9之后已经没有此方法，因此需要在pom文件中指定0.8版本。
<!-- more-->
**准备工作**
数据集：GroupLens
下载方式：`wget http://www.grouplens.org/system/files/ml-1m.zip`
下载后有四个文件：
> user.dat:包含6000个用户
> movies.dat:包含电影名字
> ratings.dat: 包含用户和电影的关系，一个数字表示用户对电影的喜爱程度
> README： 说明文件格式

**实现过程**
1.将GroupLens格式的rating.转换成CSV格式，将1::1193::5::978300760转为1,1193形式
2.创建一个Model类来处理将要使用的新文件rating.csv的文件格式
3.在该模型上创建一个简单的推荐系统
4.从文件rating.csv中提取整个用户列表需要花费一段时间，之后，在标题上将会看到每个用户的推荐

```java
package com.manhoutcookbook.recommendsys;
import org.apache.mahout.cf.taste.common.TasteException;
import org.apache.mahout.cf.taste.impl.common.LongPrimitiveIterator;
import org.apache.mahout.cf.taste.impl.model.file.FileDataModel;
import org.apache.mahout.cf.taste.impl.recommender.CachingRecommender;
import org.apache.mahout.cf.taste.impl.recommender.slopeone.SlopeOneRecommender;
import org.apache.mahout.cf.taste.model.DataModel;
import org.apache.mahout.cf.taste.recommender.RecommendedItem;

import java.io.*;
import java.util.List;

public class App {
    static final String  inputFile = "ml-1m/ratings.dat";
    static final String outputFile = "ml-1m/ratings.csv";

    public static void main(String[] args) throws IOException, TasteException {
        CreateCvsRatingFile();//修改文件格式
        //基于CSV文件建立模型
        File  ratingsFile = new File(outputFile);
        DataModel model;
        model = new FileDataModel(ratingsFile);
        //创建SlopeRecommender
        CachingRecommender cachingRecommender = new CachingRecommender(new SlopeOneRecommender(model));
        for (LongPrimitiveIterator it = model.getUserIDs(); it.hasNext(); ) {
            long userId = it.nextLong();
            //显示推荐结果
            List<RecommendedItem> recommendations = cachingRecommender.recommend(userId, 10);
            if (recommendations.size() == 0) {
                System.out.println("User ");
                System.out.println(userId);
                System.out.println(": no recommendations");
            }

            for(RecommendedItem recommendedItem : recommendations) {
                System.out.println("User ");
                System.out.println(userId);
                System.out.println(recommendedItem);
            }
        }
    }

    private static void CreateCvsRatingFile() throws IOException {
        BufferedReader reader = new BufferedReader(new FileReader(inputFile));
        BufferedWriter writer = new BufferedWriter(new FileWriter(outputFile));
        String line = null;
        String line2write = null;
        String [] temp;
        int i = 0;
        //仅转换1000条，避免单机运行堆异常
        while((line  = reader.readLine()) != null && i<10000) {
            i++;
            temp = line.split("::");
            line2write = temp[0] + "," + temp[1];
            writer.write(line2write);
            writer.newLine();
            writer.flush();
        }
        reader.close();
        writer.close();
    }
}```
运行结果：
![](http://p5s7d12ls.bkt.clouddn.com/18-4-10/23573009.jpg)
Slope One推荐算法：使用线性函数结合用户和条目来估计接近程度，计算简单快速，对新用户推荐效果不错

