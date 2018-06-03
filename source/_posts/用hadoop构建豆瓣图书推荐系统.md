---
title: 用hadoop构建豆瓣图书推荐系统
date: 2018-03-28 23:33:49
tags: [大数据, Hadoop, 推荐系统, 协同过滤]
---

《Hadoop权威指南》已经通读一遍，对于分布式数据处理大致有一些概念，从网上找一个合适的项目练练手，此博客记录了我基于[张丹大神的电影推荐系统](http://blog.fens.me/hadoop-mapreduce-recommend/)手搓的豆瓣图书推荐系统，Hadoop版本为2.8.0，爬虫用python scrapy框架来写。

**一、推荐系统概述**

互联网已经普及到了今天，更加上机器学习和大数据的浪潮火爆，几乎我们接触的所有网站、App等都会用到推荐系统，比如淘宝的猜你喜欢，头条的新闻推送等等。
<!-- more-->
常见的推荐原理有：
> *基于用户基本信息的推荐* : 例如可以根据用户的性别、职业、 年龄、 所在地等信息向他推荐感兴趣或者相关的内容
> *基于物品/内容基本信息推荐* ： 根据物品的类型、来源、主题等信息推荐
> *协同推荐* ： 协同过滤算法通过计算用户之间或者物品之间的相关性来进行推荐

协同过滤算法的实现分为两个步骤：
1.计算物品之间的相关度
2.根据物品的相似度和用户的历史行为给用户生成推荐列表
**二、算法模型**
这里我们用分步式基于物品的协同过滤算法实现为豆瓣用户推荐图书的系统。测试数据仍然用张丹大神原系统中的small.csv
```data
1,101,5.0
1,102,3.0
1,103,2.5
2,101,2.0
2,102,2.5
2,103,5.0
2,104,2.0
3,101,2.0
3,104,4.0
3,105,4.5
3,107,5.0
4,101,5.0
4,103,3.0
4,104,4.5
4,106,4.0
5,101,4.0
5,102,3.0
5,103,2.0
5,104,4.0
5,105,3.5
5,106,4.0
```
每行3个字段，依次代表用户ID，图书ID，用户对图书的评分(0-5分）。
本推荐系统执行的思路：
1. 建立物品的同现矩阵： 同现矩阵的值代表了某两本书同时出现在用户的评价列表中的次数
```data
      [101] [102] [103] [104] [105] [106] [107]
[101]   5     3     4     4     2     2     1
[102]   3     3     3     2     1     1     0
[103]   4     3     4     3     1     2     0
[104]   4     2     3     4     2     2     1
[105]   2     1     1     2     2     1     1
[106]   2     1     2     2     1     2     0
[107]   1     0     0     1     1     0     1```
2. 建立用户对物品的评分矩阵： 有多少个用户就有多少个评分矩阵
​```data
       U3
[101] 2.0
[102] 0.0
[103] 0.0
[104] 4.0
[105] 4.5
[106] 0.0
[107] 5.0```
3. 矩阵计算推荐结果： 同现矩阵*评分矩阵 = 推荐结果
![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/78005679.jpg)

**三、系统架构**
![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/71568403.jpg)

上图左边是Application业务系统，右边是本博客要实现的HDFS，MapReduce
1.业务系统记录了用户行为和用户对物品的打分（这里我们用爬取到的数据代替）
2.设置系统定时器CRON，隔一段时间增量向HDFS导入数据，即本系统需要的userId，itemId，value，time
3.完成导入后，设置系统定时器，启动MapReduce程序，运行推荐算法。
4.完成计算后，设置系统定时器，从HDFS导出推荐结果数据到数据库，方便以后的及时查询。

**四 程序开发：MapReduce程序的实现**
开发环境：Ubuntu 16.04, IntelliJ IDEA， 和Hadoop2.8.0
新建类：
    Recommend.java，主任务启动程序
    Step1.java，按用户分组，计算所有物品出现的组合列表，得到用户对物品的评分矩阵
    Step2.java，对物品组合列表进行计数，建立物品的同现矩阵
    Step3.java，对同现矩阵和评分矩阵转型
    *Step4.java，计算推荐结果列表，结果会出问题，最终不用这个类
    Step4_Update.java, 计算部分评分
    Step4_Update2.java, 计算最终评分，得到推荐结果
    HdfsDAO.java，HDFS操作工具类

*1）.Recommend.java,任务驱动程序*
​```java
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Pattern;

public class Recommend {
    public static final Pattern DELIMITER = Pattern.compile("[\t,]");
    public static final String HDFS = "hdfs://localhost/";

    public static void main(String[] args) throws InterruptedException, IOException, ClassNotFoundException {
        Map<String, String> path = new HashMap<String, String>();
        path.put("data", "resources/small.csv");
        path.put("Step1Input", HDFS + "/user/hdfs/recommend");
        path.put("Step1Output", path.get("Step1Input") + "/step1");
        path.put("Step2Input", path.get("Step1Output"));
        path.put("Step2Output", path.get("Step1Input") + "/step2");
        path.put("Step3Input1", path.get("Step1Output"));
        path.put("Step3Output1", path.get("Step1Input") + "/step3_1");
        path.put("Step3Input2", path.get("Step2Output"));
        path.put("Step3Output2", path.get("Step1Input") + "/step3_2");

        path.put("Step4Input1", path.get("Step3Output1"));
        path.put("Step4Input2", path.get("Step3Output2"));
        path.put("Step4Output", path.get("Step1Input") + "/step4");

        path.put("Step5Input1", path.get("Step3Output1"));
        path.put("Step5Input2", path.get("Step3Output2"));
        path.put("Step5Output", path.get("Step1Input") + "/step5");

        path.put("Step6Input", path.get("Step5Output"));
        path.put("Step6Output", path.get("Step1Input") + "/step6");

        Step1.run(path);
        Step2.run(path);
        Step3.run(path);
        Step3.run2(path);
        Step4.run(path);//NullPointerException,可能不会先构造同现矩阵
//        Step4_Update.run(path);
        Step4_Update2.run(path);

        System.exit(0);
    }
}
```
*2). Step1.java，按用户分组，计算所有物品出现的组合列表，得到用户对物品的评分矩阵*
```java
import hdfs.HdfsDAO;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.mapreduce.lib.output.TextOutputFormat;

import java.io.IOException;
import java.util.Iterator;
import java.util.Map;

public class Step1 {

    public static class Step1_ToItemPreMapper extends Mapper<Object, Text, IntWritable, Text> {

        @Override
        protected void map(Object key, Text value, Context context) throws IOException, InterruptedException {
            String tokens[] = Recommend.DELIMITER.split(value.toString());
            int userId = Integer.parseInt(tokens[0]);
            String itemId = tokens[1];
            String pref = tokens[2];
            context.write(new IntWritable(userId), new Text(itemId + ":" + pref));
        }
    }

    public static class Step1_ToUserVectorReducer extends Reducer<IntWritable, Text, IntWritable, Text> {
        @Override
        protected void reduce(IntWritable key, Iterable<Text> values, Context context) throws IOException, InterruptedException {
            StringBuilder sb = new StringBuilder();
            Iterator<Text> iter = values.iterator();
            while (iter.hasNext()) {
                sb.append("," + iter.next());
            }
            context.write(key, new Text(sb.toString().replaceFirst(",", "")));
        }
    }


    public static void run(Map<String, String> path) throws IOException, ClassNotFoundException, InterruptedException {
        String input = path.get("Step1Input");
        String output = path.get("Step1Output");

        Configuration conf = new Configuration();
//        conf.set("mapreduce.task.io.sort.mb","1024");//任务内部排序缓冲区大小,默认为100

        Job job = new Job(conf, "Step1");
        HdfsDAO hdfs = new HdfsDAO(Recommend.HDFS, conf);
        hdfs.rmr(input);
        hdfs.mkdirs(input);
        hdfs.copyFile(path.get("data"), input);

        job.setJarByClass(Step1.class);
        job.setMapOutputKeyClass(IntWritable.class);
        job.setMapOutputValueClass(Text.class);

        job.setOutputKeyClass(IntWritable.class);
        job.setOutputValueClass(Text.class);

        job.setInputFormatClass(TextInputFormat.class);
        job.setOutputFormatClass(TextOutputFormat.class);

        job.setMapperClass(Step1_ToItemPreMapper.class);
        job.setReducerClass(Step1_ToUserVectorReducer.class);
        job.setCombinerClass(Step1_ToUserVectorReducer.class);

        FileInputFormat.setInputPaths(job, new Path(input));
        FileOutputFormat.setOutputPath(job, new Path(output));

        job.waitForCompletion(true);
    }
}```
map阶段：用正则表达式分割输入数据，以userId为键，图书id和打分组合成字符串itemId：pref传递给Reducer
reduce阶段：此时传进来的key已经按照userId分好块，于是我们可以得到每个用户的评分矩阵
Step1的输出为：
![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/97798258.jpg)

*3). Step2.java，对物品组合列表进行计数，建立物品的同现矩阵*
​```java
import hdfs.HdfsDAO;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.mapreduce.lib.output.TextOutputFormat;

import java.io.IOException;
import java.util.Iterator;
import java.util.Map;

public class Step2 {
    public static class Step2_UserVectorToCooccurrenceMapper extends Mapper<LongWritable, Text, Text, IntWritable> {
        private final static Text k = new Text();
        private final static IntWritable v = new IntWritable(1);

        @Override
        protected void map(LongWritable key, Text value, Context context) throws IOException, InterruptedException {
            String[] tokens = Recommend.DELIMITER.split(value.toString());
            for (int i = 1; i < tokens.length; i++) {
                String itemId = tokens[i].split(":")[0];
                for (int j = 1; j < tokens.length; j++) {
                    String itemId2 = tokens[j].split(":")[0];
                    context.write(new Text(itemId + ":" + itemId2), v);
                }
            }
        }
    }

    public static class Step2_UserVectorToCooccurrenceReducer extends Reducer<Text, IntWritable, Text, IntWritable> {
        @Override
        protected void reduce(Text key, Iterable<IntWritable> values, Context context) throws IOException, InterruptedException {
            int sum = 0;
            Iterator<IntWritable> iter = values.iterator();
            while (iter.hasNext()) {
                sum += iter.next().get();
            }
            context.write(key, new IntWritable(sum));
        }
    }

    public static void run(Map<String, String> path) throws IOException, ClassNotFoundException, InterruptedException {
        Configuration conf = new Configuration();
        Job job = new Job(conf, "Step2");

        String input = path.get("Step2Input");
        String output = path.get("Step2Output");
        System.out.println(output);
        HdfsDAO hdfs = new HdfsDAO(Recommend.HDFS, conf);
        hdfs.rmr(output);

        job.setJarByClass(Step2.class);

        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(IntWritable.class);

        job.setMapperClass(Step2_UserVectorToCooccurrenceMapper.class);
        job.setCombinerClass(Step2_UserVectorToCooccurrenceReducer.class);
        job.setReducerClass(Step2_UserVectorToCooccurrenceReducer.class);

        job.setInputFormatClass(TextInputFormat.class);
        job.setOutputFormatClass(TextOutputFormat.class);


        FileInputFormat.setInputPaths(job, new Path(input));
        FileOutputFormat.setOutputPath(job, new Path(output));

        job.waitForCompletion(true);

    }
}
```
Step2的输入是Step1的输出，
map阶段：用正则表达式分割每行，利用双重循环构造每行中任意两个itemsId的组合作为键，用数字1作为值输出到Reducer
reduce阶段：Mapper传来的数据已经按键分块，累加每种键下的值即可得到item1和item2出现在同一个评分列表中的次数，即得到图书的同现矩阵
Step2的输出为：
![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/19253791.jpg)

*4). Step3.java，合并同现矩阵和评分矩阵*
```java
import hdfs.HdfsDAO;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.mapreduce.lib.output.TextOutputFormat;

import java.io.IOException;
import java.util.Map;

public class Step3 {
    public static class Step31_UserVectorSplitterMapper extends Mapper<LongWritable, Text, IntWritable, Text> {
        private IntWritable k = new IntWritable();
        private Text v = new Text();

        @Override
        protected void map(LongWritable key, Text value, Context context) throws IOException, InterruptedException {
            String[] tokens = Recommend.DELIMITER.split(value.toString());
            for (int i = 1; i < tokens.length; i++) {
                String[] vector = tokens[i].split(":");
                int itemId = Integer.parseInt(vector[0]);
                String pref = vector[1];
                k.set(itemId);
                v.set(tokens[0] + ":" + pref);
                context.write(k, v);
            }
        }
    }

    public static void run(Map<String, String> path) throws IOException, ClassNotFoundException, InterruptedException {
        Configuration conf = new Configuration();
        Job job = new Job(conf, "step31_spliteUserVector");
        String input = path.get("Step3Input1");
        String output = path.get("Step3Output1");

        HdfsDAO hdfs = new HdfsDAO(conf);
        hdfs.rmr(output);
        job.setJarByClass(Step3.class);
        job.setMapOutputKeyClass(IntWritable.class);
        job.setMapOutputValueClass(Text.class);

        job.setMapperClass(Step31_UserVectorSplitterMapper.class);

        job.setInputFormatClass(TextInputFormat.class);
        job.setOutputFormatClass(TextOutputFormat.class);

        FileInputFormat.setInputPaths(job, new Path(input));
        FileOutputFormat.setOutputPath(job, new Path(output));

        job.setNumReduceTasks(0);
        job.waitForCompletion(true);
    }

    public static class Step32_CooccurreceColumWrapperMapper extends Mapper<LongWritable, Text, Text, IntWritable> {
        private final static Text k = new Text();
        private final static IntWritable v = new IntWritable();

        @Override
        protected void map(LongWritable key, Text value, Context context) throws IOException, InterruptedException {
            String tokens[] = Recommend.DELIMITER.split(value.toString());
            k.set(tokens[0]);
            v.set(Integer.parseInt(tokens[1])); //这里和step2的输出有什么区别????
            context.write(k, v);
        }
    }

    public static void run2(Map<String, String> path) throws IOException, ClassNotFoundException, InterruptedException {
        Configuration conf = new Configuration();
        Job job = new Job(conf, "step32_cooccurreceMap");
        String input = path.get("Step3Input2");
        String output = path.get("Step3Output2");
        job.setJarByClass(Step3.class);
        HdfsDAO hdfs = new HdfsDAO(conf);
        hdfs.rmr(output);

        job.setMapOutputKeyClass(Text.class);
        job.setMapOutputValueClass(IntWritable.class);

        job.setMapperClass(Step32_CooccurreceColumWrapperMapper.class);

        job.setInputFormatClass(TextInputFormat.class);
        job.setOutputFormatClass(TextOutputFormat.class);

        FileInputFormat.setInputPaths(job, new Path(input));
        FileOutputFormat.setOutputPath(job, new Path(output));

        job.setNumReduceTasks(0);
        job.waitForCompletion(true);
    }
}
```
Step3_1将用户评分矩阵拆分为itemId	userId:pref的形式输出，为了方便之后的计算
Step3_2看起来输出结果与Step2相同
Step3_1输出：
![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/9400783.jpg)
Step3_1输出：
![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/22519877.jpg)

*5). Step4.java，计算推荐结果列表*
```java
import hdfs.HdfsDAO;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.mapreduce.lib.output.TextOutputFormat;

import java.io.IOException;
import java.util.*;

public class Step4 {
    public static class Step4_PartialMultiplyMapper extends Mapper<LongWritable, Text, IntWritable, Text> {
        private final static IntWritable k = new IntWritable();
        private final static Text v = new Text();
        private final static Map<Integer, List<Cooccurrence>> cooccurrenceMatrix = new HashMap<Integer, List<Cooccurrence>>();

        @Override
        protected void map(LongWritable key, Text value, Context context) throws IOException, InterruptedException {
            String[] tokens = Recommend.DELIMITER.split(value.toString());

            String[] v1 = tokens[0].split(":");
            String[] v2 = tokens[1].split(":");

            if (v1.length > 1) {// cooccurrence
                int itemID1 = Integer.parseInt(v1[0]);
                int itemID2 = Integer.parseInt(v1[1]);
                int num = Integer.parseInt(tokens[1]);

                List<Cooccurrence> list = null;
                if (!cooccurrenceMatrix.containsKey(itemID1)) {
                    list = new ArrayList<Cooccurrence>();
                } else {
                    list = cooccurrenceMatrix.get(itemID1);
                }
                list.add(new Cooccurrence(itemID1, itemID2, num));
                cooccurrenceMatrix.put(itemID1, list);
            }

            if (v2.length > 1) {// userVector
                int itemID = Integer.parseInt(tokens[0]);
                int userID = Integer.parseInt(v2[0]);
                double pref = Double.parseDouble(v2[1]);
                k.set(userID);
                for (Cooccurrence co : cooccurrenceMatrix.get(itemID)) {
                    v.set(co.getItemID2() + "," + pref * co.getNum());
                    context.write(k, v);
                }
            }
        }
    }

    public static class Step4_AggregateAndRecommendReducer extends Reducer<IntWritable, Text, IntWritable, Text> {
        private final static Text v = new Text();

        @Override
        protected void reduce(IntWritable key, Iterable<Text> values, Context context) throws IOException, InterruptedException {
            Map<String, Double> result = new HashMap<String, Double>();
            Iterator<Text> iter = values.iterator();
            while (iter.hasNext()) {
                String[] str = iter.next().toString().split(",");
                if (result.containsKey(str[0])) {
                    result.put(str[0], result.get(str[0]) + Double.parseDouble(str[1]));
                } else {
                    result.put(str[0], Double.parseDouble(str[1]));
                }
            }
            Iterator<String> iter2 = result.keySet().iterator();
            while (iter.hasNext()) {
                String itemID = iter2.next();
                double score = result.get(itemID);
                v.set(itemID + "," + score);
                context.write(key, v);
            }
        }
    }

    public static void run(Map<String, String> path) throws IOException, ClassNotFoundException, InterruptedException {
        String input1 = path.get("Step4Input1");
        String input2 = path.get("Step4Input2");
        String output = path.get("Step4Output");

        Configuration conf = new Configuration();
        Job job = new Job(conf, "Step4");
        HdfsDAO hdfs = new HdfsDAO(Recommend.HDFS, conf);
        hdfs.rmr(output);
        job.setJarByClass(Step4.class);

        job.setOutputKeyClass(IntWritable.class);
        job.setOutputValueClass(Text.class);

        job.setInputFormatClass(TextInputFormat.class);
        job.setOutputFormatClass(TextOutputFormat.class);

        job.setMapperClass(Step4_PartialMultiplyMapper.class);
        job.setReducerClass(Step4_AggregateAndRecommendReducer.class);
        job.setCombinerClass(Step4_AggregateAndRecommendReducer.class);

        FileInputFormat.setInputPaths(job, new Path(input1), new Path(input2));
        FileOutputFormat.setOutputPath(job, new Path(output));

        job.waitForCompletion(true);
    }
}

class Cooccurrence {
    private int itemID1;
    private int itemID2;
    private int num;

    public Cooccurrence(int itemID1, int itemID2, int num) {
        super();
        this.itemID1 = itemID1;
        this.itemID2 = itemID2;
        this.num = num;
    }

    public int getItemID1() {
        return itemID1;
    }

    public int getItemID2() {
        return itemID2;
    }

    public int getNum() {
        return num;
    }

    public void setItemID1(int itemID1) {
        this.itemID1 = itemID1;
    }

    public void setItemID2(int itemID2) {
        this.itemID2 = itemID2;
    }

    public void setNum(int num) {
        this.num = num;
    }
}```
Step4的输入来自两个路径，分别是step3_1和step3_2的输出，
map阶段：对输入的值进行分割，如果是同现矩阵其将被分割为`[101:102,3]`的形式，如果是评分矩阵将被分割为`[102,5:30]`的形式，然后以“：”为分隔符分别分割数组tokens中的元素，以此来判别输入是什么类型的矩阵。如果是同现矩阵，获取itemID1和itemID2以及num，在初始化时创建的静态map中填充以每一个itemID1为键，以List<Cooccurence>对象为值的数据，最后得到的map形象的表示为下图所示的方式：
```
{101：[cooccurence(101,101,5),cooccurence(101,102,3),...],
...
106:[cooccurence(106,101,2),cooccurence(106,101,1),...],
107:[cooccurence(107,101,1)}
```
如果输入来自用户评分矩阵，会先得到itemID，userID和评分pref，然后将userID设为键，利用itemID从上面的map中得到其对应的list，从list中可以得到*同现item*（通过`co.getItemID2()`）和*同现次数num*，对list中的每项都能得到一个输出，将输出值设为组合字符串“同现item，pref*同现num”，我将通过下图来解释第二项的意义，请读者自行体会。

![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/60596269.jpg)

reduce阶段逻辑比较简单，将每个item对应的值加起来就是用户对这个item的推荐的程度。
Step4在执行的时候会报错：
![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/51842026.jpg)

原因在于当输入是用户评分矩阵时，同现map并不是随时就绪的，可能不会先构造同现矩阵。因为hadoop从hdfs上读取小文件时，会先读占用空间大的文件，这样就不难保证先生成coocurenceMatrix了，所以Step4.java这个类不能使用，我们把矩阵乘法进行分开计算，先进行对于位置相乘Step4_Updata.java，最后进行加法Step4_Updata2.java
 
**5). Step4_Update.java，计算推荐结果列表**

​```java
import hdfs.HdfsDAO;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.FileSplit;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.mapreduce.lib.output.TextOutputFormat;

import java.io.IOException;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

public class Step4_Update {


    public static class Step4_PartialMultiplyMapper extends Mapper<LongWritable, Text, Text, Text> {
        private String flag;//A同现矩阵,B用户评分矩阵

        @Override
        protected void setup(Context context) throws IOException, InterruptedException {
            FileSplit split = (FileSplit) context.getInputSplit();
            flag = split.getPath().getParent().getName();
        }

        @Override
        protected void map(LongWritable key, Text value, Context context) throws IOException, InterruptedException {
            String[] tokens = Recommend.DELIMITER.split(value.toString());
            if (flag.equals("step3_2")) {
                String[] v1 = tokens[0].split(":");
                String itemID1 = v1[0];
                String itemID2 = v1[1];
                String num = tokens[1];

                Text k = new Text(itemID1);
                Text v = new Text("A:" + itemID2 + "," + num);
                context.write(k, v);
            } else if (flag.equals("step3_1")) {
                String[] v2 = tokens[1].split(":");
                String itemID = tokens[0];
                String userID = v2[0];
                String pref = v2[1];
                Text k = new Text(itemID);
                Text v = new Text("B:" + userID + "," + pref);
                context.write(k, v);
            }
        }
    }

    public static class Step4_AggregateReducer extends Reducer<Text, Text, Text, Text> {
        @Override
        protected void reduce(Text key, Iterable<Text> values, Context context) throws IOException, InterruptedException {
            //System.out.println(key.toString() + ":");
            Map<String, String> mapA = new HashMap<String, String>();
            Map<String, String> mapB = new HashMap<String, String>();
            for (Text line : values) {
                String val = line.toString();
                //System.out.println(val);

                if (val.startsWith("A:")) {
                    String[] kv = Recommend.DELIMITER.split(val.substring(2));
                    mapA.put(kv[0], kv[1]);
                } else if (val.startsWith("B:")) {
                    String[] kv = Recommend.DELIMITER.split(val.substring(2));
                    mapB.put(kv[0], kv[1]);
                }
            }

            double result = 0;
            Iterator<String> iter = mapA.keySet().iterator();
            while (iter.hasNext()) {
                String mapk = iter.next();//itemID2
                int num = Integer.parseInt(mapA.get(mapk));
                Iterator<String> iterb = mapB.keySet().iterator();//userID
                while (iterb.hasNext()) {
                    String mapkb = iterb.next();

                    double pref = Double.parseDouble(mapB.get(mapkb));
                    result = num * pref;
                    Text k = new Text(mapkb);
                    Text v = new Text(mapk + "," + result);
                    context.write(k, v);
                }
            }
        }
    }

    public static void run(Map<String, String> path) throws IOException, ClassNotFoundException, InterruptedException {
        Configuration conf = new Configuration();
        Job job = new Job(conf);
        String input1 = path.get("Step5Input1");
        String input2 = path.get("Step5Input2");
        String output = path.get("Step5Output");

        HdfsDAO hdfs = new HdfsDAO(Recommend.HDFS, conf);
        hdfs.rmr(output);

        job.setJarByClass(Step4_Update.class);

        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(Text.class);

        job.setMapperClass(Step4_Update.Step4_PartialMultiplyMapper.class);
        job.setReducerClass(Step4_Update.Step4_AggregateReducer.class);

        job.setInputFormatClass(TextInputFormat.class);
        job.setOutputFormatClass(TextOutputFormat.class);

        FileInputFormat.setInputPaths(job, new Path(input1), new Path(input2));
        FileOutputFormat.setOutputPath(job, new Path(output));

        job.waitForCompletion(true);
    }
}
```
在Mapper的setup阶段，通过`split.getPath().getParent().getName()`来确定输入来自那个文件，如果来自用户评分矩阵，则输出以A：打头的值，否则以B：打头，键均为itemID
redece阶段：键为item1，创建mapA和mapB，mapA的内容为（item2,num），mapB的值为(userId，pref),对于mapA中的每个item2和num，为每个user计算num*pref，输出的值为（userId，“itemID2,num*pref”）
![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/27264349.jpg)

step4_update.java输出是：
![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/96688878.jpg) 

**6).Step4_Update2.java:计算推荐结果**
```java
import hdfs.HdfsDAO;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.mapreduce.lib.output.TextOutputFormat;

import java.io.IOException;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

public class Step4_Update2 {
    public static class Step4_RecommendMapper extends Mapper<LongWritable, Text, Text, Text> {
        @Override
        protected void map(LongWritable key, Text value, Context context) throws IOException, InterruptedException {
            String[] tokens = Recommend.DELIMITER.split(value.toString());
            Text k = new Text(tokens[0]);
            Text v = new Text(tokens[1] + "," + tokens[2]);
            context.write(k,v);
        }
    }

    public static class Step4_RecommendReducer extends Reducer<Text,Text, Text, Text> {
        @Override
        protected void reduce(Text key, Iterable<Text> values, Context context) throws IOException, InterruptedException {
            System.out.println(key.toString());
            Map<String, Double> map = new HashMap<String, Double>();
            for (Text line : values) {
                System.out.println(line.toString());
                String [] tokens = Recommend.DELIMITER.split(line.toString());
                String itemID = tokens[0];
                Double score = Double.parseDouble(tokens[1]);

                if (map.containsKey(itemID)) {
                    map.put(itemID, map.get(itemID) + score);
                } else {
                    map.put(itemID, score);
                }
            }

            Iterator<String> iter = map.keySet().iterator();
            while (iter.hasNext()) {
                String itemID = iter.next();
                double score = map.get(itemID);
                Text v = new Text(itemID + "," + score);
                context.write(key,v);
            }
        }
    }
    public static void run(Map<String, String> path) throws InterruptedException, IOException, ClassNotFoundException {
        Configuration conf = new Configuration();

        String input = path.get("Step6Input");
        String output = path.get("Step6Output");

        HdfsDAO hdfs = new HdfsDAO(Recommend.HDFS, conf);
        hdfs.rmr(output);
        Job job = new Job(conf);
        job.setJarByClass(Step4_Update2.class);

        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(Text.class);

        job.setMapperClass(Step4_Update2.Step4_RecommendMapper.class);
        job.setReducerClass(Step4_Update2.Step4_RecommendReducer.class);

        job.setInputFormatClass(TextInputFormat.class);
        job.setOutputFormatClass(TextOutputFormat.class);

        FileInputFormat.setInputPaths(job, new Path(input));
        FileOutputFormat.setOutputPath(job, new Path(output));

        job.waitForCompletion(true);
    }
}
```
较为简单，求和即可，结果如下：
![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/61332065.jpg)
五、程序开发：爬虫的编写
本爬虫爬取图书的信息，未整理完毕，可以根据需求更改
item.py
```python
import scrapy


class DoubanbooksItem(scrapy.Item):
    book_name = scrapy.Field()  # 图书名
    book_star = scrapy.Field()  # 图书评分
    book_pl = scrapy.Field()  # 图书评论数
    book_author = scrapy.Field()  # 图书作者
    book_publish = scrapy.Field()  # 出版社
    book_date = scrapy.Field()  # 出版日期
    book_price = scrapy.Field()  # 图书价格
    book_tag = scrapy.Field()
    book_desc = scrapy.Field()
    book_id = scrapy.Field()```
bookspider.py
​```python
# -*- coding: utf-8 -*-
import urllib

import scrapy
from PIL import Image
from scrapy.linkextractors import LinkExtractor
from scrapy.spiders import CrawlSpider, Rule
from scrapy.selector import Selector
from doubanBooks.items import DoubanbooksItem


class BookspiderSpider(CrawlSpider):
    name = 'bookspider'
    allowed_domains = ['douban.com']
    start_urls = ["https://book.douban.com/tag/"]
    rules = (
        Rule(LinkExtractor(allow=r'tag/.{2,4}'), callback='parse_item', follow=False),
        Rule(LinkExtractor(allow=r'https://book.douban.com/tag/.+/?start=\d+&type=T'), callback='parse_item2', follow=True),
        # Rule(LinkExtractor(allow=r'https://book.douban.com/subject/\d+/'), callback='parse_item2',follow=False),
        # Rule(LinkExtractor(allow=r'https://book.douban.com/subject/\d/reviews'), callback='parse_item3', follow=False),
    )




    # def start_requests(self):
    #     '''
    #     重写start_requests，请求登录页面
    #     '''
    #     return [scrapy.FormRequest("https://accounts.douban.com/login", meta={"cookiejar": 1},
    #                                callback=self.parse_before_login)]
    #


    def parse_item0(self, response):
        sel = Selector(response);
        # item['book_tag'] = sel.xpath('/html/body/div[3]/div[1]/h1/text()').extract()[0].split(':')[1].strip()

    def parse_item(self, response):
        pass
       # print(response)

    def parse_item2(self, response):
        sel = Selector(response)
        item = DoubanbooksItem()
        item['book_tag'] = sel.xpath('/html/body/div[3]/div[1]/h1/text()').extract()[0].strip().split(':')[1]
        book_list = sel.css('#subject_list > ul > li')
        for book in book_list:

            try:
                # strip() 方法用于移除字符串头尾指定的字符（默认为空格）
                item['book_name'] = book.xpath('div[@class="info"]/h2/a/text()').extract()[0].strip()
                item['book_star'] = book.xpath("div[@class='info']/div[2]/span[@class='rating_nums']/text()").extract()[0].strip()
                item['book_pl'] = book.xpath("div[@class='info']/div[2]/span[@class='pl']/text()").extract()[0].strip()
                item['book_desc'] = book.xpath("div[2]/p/text()").extract()[0]
                item['book_id'] = book.xpath('div[@class="info"]/h2[@class=""]/a/@href').extract()[0].strip().split('/')[-2]
                pub = book.xpath('div[@class="info"]/div[@class="pub"]/text()').extract()[0].strip().split('/')
                item['book_price'] = pub.pop()
                item['book_date'] = pub.pop()
                item['book_publish'] = pub.pop()
                item['book_author'] = '/'.join(pub)

                yield item
            except:
                pass

# def parse_item4(self, response):
#         sel = Selector(response);
#         item = DoubanbooksItem()
#         item['user_name'] = sel.xpath('div[@class="aside"]/div[@class="sidebar-info-wrapper"]/div[2]/a/text()').extract()[0].strip()
#         item['user_score'] = sel.xpath('div[@class="aside"]/div[@class="sidebar-info-wrapper"]/div[2]/a/text()').extract()[0].strip()
#         yield item

    def parse_before_login(self, response):
        print("登录前表单填充")
        captcha_id = response.xpath('//input[@name="captcha-id"]/@value').extract_first()
        captcha_image_url = response.xpath('//img[@id="captcha_image"]/@src').extract_first()
        if captcha_image_url is None:
            print("登录时无验证码")
            formdata = {
                "form_email": "18911341910",
                # 请填写你的密码
                "form_password": "lh1994114",
                "login": "登录",
                "redir": "https://www.douban.com/",
                "source": "index_nav",
            }
        else:
            print("登录时有验证码")
            save_image_path = "/media/harold/SpareDisk/pythonProject/captcha.jpeg"
            # 将图片验证码下载到本地
            urllib.request.urlretrieve(captcha_image_url, save_image_path)
            # 打开图片，以便我们识别图中验证码
            try:
                im = Image.open(save_image_path)
                im.show()
            except:
                pass
            # 手动输入验证码
            captcha_solution = input('根据打开的图片输入验证码:')
            formdata = {
                "source": "None",
                "redir": "https://www.douban.com/",
                "form_email": "13227708059@163.com",
                # 此处请填写密码
                "form_password": "*******",
                "captcha-solution": captcha_solution,
                "captcha-id": captcha_id,
                "login": "登录",
            }

        print("登录中")
        # 提交表单
        return scrapy.FormRequest.from_response(response, meta={"cookiejar": response.meta["cookiejar"]},
                                                formdata=formdata,
                                                callback=self.parse_after_login)


    def parse_after_login(self, response):
        '''
        验证登录是否成功
        '''
        account = response.xpath('/html/body/div[1]/div/div[1]/ul/li[2]/a/span[1]').extract_first()
        print(account)
        if account is None:
            print("登录失败")
        else:
            print(u"登录成功,当前账户为 %s" % account)
            yield self.make_requests_from_url("https://book.douban.com/tag/")

```
pipeline.py 输出到csv
```python
from scrapy import signals
from scrapy.contrib.exporter import CsvItemExporter


class BookPipeline(object):
    @classmethod
    def from_crawler(cls, crawler):
        pipeline = cls()
        crawler.signals.connect(pipeline.spider_opened, signals.spider_opened)
        crawler.signals.connect(pipeline.spider_closed, signals.spider_closed)
        return pipeline

    def spider_opened(self, spider):
        self.file = open('output.csv', 'w+b')
        self.exporter = CsvItemExporter(self.file)
        self.exporter.start_exporting()

    def spider_closed(self, spider):
        self.exporter.finish_exporting()
        self.file.close()

    def process_item(self, item, spider):
        self.exporter.export_item(item)
        return item```

部分结果

![](http://p5s7d12ls.bkt.clouddn.com/18-3-28/51973032.jpg)

github地址：
爬虫：https://github.com/Harold1994/doubanBooks
推荐系统：https://github.com/Harold1994/HadoopFileRecommendation

```