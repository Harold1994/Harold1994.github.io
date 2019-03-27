---
title: Hadpoop和Spark实现矩阵相乘
date: 2018-07-04 19:31:22
tags: [Hadoop, Spark, 大数据]
---

矩阵的存储格式如下：

矩阵名 行号 列号 值

```reStructuredText
M 0 0 1
M 0 1 0
M 0 2 2
M 1 0 2									 
M 1 1 3                          
M 1 2 1							
N 0 0 1
N 0 1 0
N 1 0 2
N 1 1 3
N 2 0 2
N 2 1 0
```

<!-- more--> 

#### 一、Hadoop实现

**1.方法一**

**Map1**阶段：对于矩阵M，把列作为key,对于矩阵N,把行作为key

**Reduce1**阶段：对于相同key的值，M矩阵和N矩阵的值做笛卡尔积，输出key：`(M的行) + （N的列值）+ （MN相乘的value`，输出的value：`“”`

**Map2阶段**：读取**Reduce1**的输出值

**Reduce2阶段**：把所有相同key的value值相加，输出即可

第一次MapReduce:

```java
public class ReadMapper extends Mapper<LongWritable, Text, Text, Text> {
    @Override
    public void map(LongWritable key, Text value, Context context) throws IOException, InterruptedException {
        String str = value.toString();
        String[] strs = str.split(" ");
        if (strs[0].equals("M") && strs.length == 4)
            context.write(new Text(strs[2]), new Text(strs[0] + " " + strs[1] +" " + strs[3]));
        else if (strs[0].equals("N") && strs.length == 4)
            context.write(new Text(strs[1]), new Text(strs[0] + " " + strs[2] + " " + strs[3]));
    }
}

public class WriteReducer extends Reducer<Text, Text, Text, Text> {
    @Override
    public void reduce(Text key, Iterable<Text> values, Context context) throws IOException, InterruptedException {
        ArrayList<String> mTrix = new ArrayList<String>();
        ArrayList<String> nTrix = new ArrayList<String>();
        for (Text value : values) {
            if (value.toString().contains("M"))
                mTrix.add(value.toString());
            else
                nTrix.add(value.toString());
        }
        String [] mItems, nItems;
        for (String m : mTrix){
            mItems = m.split(" ");
            for (String n : nTrix) {
                nItems = n.split(" ");
                context.write(new Text(key + "+" + mItems[1] + "+" + nItems[1] + "+" + (Integer.parseInt(mItems[2]) * Integer.parseInt(nItems[2]))),new Text(""));
            }
        }
    }
    
public class MatrixMul extends Configured implements Tool {
    @Override
    public int run(String[] strings) throws Exception {
        Configuration conf = getConf();
        Job job = new Job(conf);
        job.setJarByClass(MatrixMul.class);
        job.setJobName("MatrixMul");

        FileInputFormat.setInputPaths(job, new Path(strings[0]));
       FileOutputFormat.setOutputPath(job, new Path(strings[1]));

        job.setMapperClass(ReadMapper.class);
        job.setReducerClass(WriteReducer.class);

        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(Text.class);

        return job.waitForCompletion(true) ? 0 : 1;
    }

    public static void main(String[] args) throws Exception {
        int returnStatus = ToolRunner.run(new MatrixMul(), args);
        System.exit(returnStatus);
    }
}
```

输出：

```reStructuredText
0+1+1+0
0+1+0+2
0+0+1+0
0+0+0+1
1+1+1+9
1+1+0+6
1+0+1+0
1+0+0+0
2+1+1+0
2+1+0+2
2+0+1+0
2+0+0+4
```

第二次MapReduce:

```java
public class MatrixMulStep2 extends Configured implements Tool {
    @Override
    public int run(String[] args) throws Exception {
        Configuration conf = getConf();
        Job job = new Job(conf);
        job.setJobName("MatrixMulStep2");
        job.setJarByClass(MatrixMulStep2.class);

        FileInputFormat.setInputPaths(job, new Path(args[0]));
        FileOutputFormat.setOutputPath(job, new Path(args[1]));

        job.setOutputValueClass(Text.class);
        job.setOutputKeyClass(Text.class);

        job.setMapperClass(ReadMapper1.class);
        job.setReducerClass(WriteReducer1.class);
        return job.waitForCompletion(true) ? 0 : 1;
    }

    public static void main(String[] args) throws Exception {
        int returnStatus = ToolRunner.run(new MatrixMulStep2(), args);
        System.exit(returnStatus);
    }
}
```

```java
public class ReadMapper1 extends Mapper<LongWritable, Text, Text, Text> {
    @Override
    protected void map(LongWritable key, Text value, Context context) throws IOException, InterruptedException {
        String[] str = value.toString().split("\\+");
        if (str.length >=4 ){
            context.write(new Text(str[1] + " " + str[2]), new Text(str[3]));
        }
    }
}
```

```java
public class WriteReducer1 extends Reducer<Text, Text, Text, Text> {
    @Override
    protected void reduce(Text key, Iterable<Text> values, Context context) throws IOException, InterruptedException {
        int sum = 0;
        for (Text t : values)
            sum += Integer.parseInt(t.toString());
        context.write(key, new Text(sum + ""));
    }
}
```

输出：

```reStructuredText
0 0	5
0 1	0
1 0	10
1 1	9
```

**2.方法二**

```java
public class SingleStep extends Configured implements Tool {
    public static final int WIDTH = 2;
    public static final int LENGTH = 2;
    public static final int MATRIX_K = 3;

    public static class MatrixMapper extends Mapper<LongWritable, Text, Text, Text> {
        @Override
        protected void map(LongWritable key, Text value, Context context) throws IOException, InterruptedException {
            String[] values = value.toString().split(" ");
            if (values[0].equals("M")) {
                for (int i = 0; i < LENGTH; i++)
                    context.write(new Text(values[1] + " " + i), new Text(values[0] + " " + values[2] + " " + values[3]));
            } else {
                for (int i = 0; i < WIDTH; i++)
                    context.write(new Text(i + " " + values[2]), new Text(values[0] + " " + values[1] + " " + values[3]));
            }
        }
    }

    public static class MatrixReducer extends Reducer<Text, Text, Text, Text> {
        @Override
        protected void reduce(Text key, Iterable<Text> values, Context context) throws IOException, InterruptedException {
            Integer[] m_matrix = new Integer[MATRIX_K];
            Integer[] n_matrix = new Integer[MATRIX_K];
            int i = 0;
            for (Text value : values) {
                String[] tmp = value.toString().split(" ");
                if (tmp[0].equals("M"))
                    m_matrix[Integer.parseInt(tmp[1])] = Integer.parseInt(tmp[2]);
                else n_matrix[Integer.parseInt(tmp[1])] = Integer.parseInt(tmp[2]);
            }

            //对两个矩阵相乘相加
            int result = 0;
            for (i = 0; i < MATRIX_K; i++) {
                if (m_matrix[i] != null && n_matrix[i] != null) {
                    result += m_matrix[i] * n_matrix[i];
                }
            }
            context.write(key, new Text(result + ""));
        }
    }

    @Override
    public int run(String[] strings) throws Exception {
        Configuration conf = getConf();
        Job job = new Job(conf);
        job.setJarByClass(MatrixMul.class);
        job.setJobName("SingleStep");

        FileInputFormat.setInputPaths(job, new Path(strings[0]));
        FileOutputFormat.setOutputPath(job, new Path(strings[1]));

        job.setMapperClass(MatrixMapper.class);
        job.setReducerClass(MatrixReducer.class);

        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(Text.class);

        return job.waitForCompletion(true) ? 0 : 1;
    }

    public static void main(String[] args) throws Exception {
        int returnStatus = ToolRunner.run(new SingleStep(), args);
        System.exit(returnStatus);
    }
}
```

#### 二、Spark实现

```scala
object MatrixMulSpark {
  def main(args: Array[String]): Unit = {
    val conf = new SparkConf()
      .setAppName("MatrixMulSpark")
      .setMaster("local")
    val sc = new SparkContext(conf);
    val input = sc.textFile("in/in.txt")
    val M = input.filter(line => line.contains("M"))
    val N = input.filter(line => line.contains("N"))

    val wordM = M.map(line => {
      val words = line.split(" ")
      (words(2), words)
    })

    val wordN = N.map( line => {
      val word = line.split(" ")
      (word(1), word)
    })

    val dword = wordM.join(wordN)
    dword.collect.foreach(println)
    val map = dword.values.map( x => {
      (x._1(1) + " " + x._2(2),x._1(3).toDouble * x._2(3).toDouble)
    })
    val reduceS = map.reduceByKey((x,y) => {
      x + y
    })
    reduce.foreach(x => println(x._1+" " + x._2))
  }
}
```