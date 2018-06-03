---
title: 关于HBase
date: 2018-03-21 10:32:23
tags: [大数据, Hadoop, HBase]
---
HBase是一个在HDFS上开发的面向列的分布式数据库,可以用来实时的随机访问超大规模数据集,它自底向上的进行构建,能够简单的通过增加节点来达到线性扩展,HBase不是关系型数据库,不支持SQL,它能在廉价的硬件构成的集群上管理超大规模的稀疏表.

相关概念
---
应用将数据存放在带标签的表中,表格的"单元格"由行和列的坐标交叉决定,是*有版本*的,版本号默认是自动分配的,为插入单元格的时间戳.单元格内容是未解释的字节数组.
 <!-- more-->

![](http://p5s7d12ls.bkt.clouddn.com/18-3-21/37375528.jpg)

表中行的键也是字节数组,行根据行的键进行排序,排序根据字节序进行,所有对表的访问都要通过表的主键,HBase不支持表中的其他列建立索引.
行中的列被分为列族,同一个列族成员具有相同的前缀,info:format和info:geo都是列族info的成员,列族前缀必须是"可打印的",修饰符可以是任意字节,列族和修饰符用(:)分隔.

一个表的*列族*必须作为表模式的定义一部分*预先给出*,但*列组成员*可以随后按需加入.物理上,所有的*列族成员*都一起存放在文件系统中,HBase更确切地说是面向列族的存储器.调优和存储都是在列族层面上进行的,所以最好使所有列族成员有相同的访问模式和大小特征.
*区域*
HBase自动将表水平划分为区域,每个区域由表中行的子集构成,每个区域由他所属于的表,它包含的第一行和最后一行(不包括这行)来表示.一开始一个表只有一个区域,当区域大小超出设定的阈值是便会在某行的边界上分成*两个大小基本相同的新分区*,区域是在HBase集群上分布数据最小的单位,因为太大而无法存放在单台服务器上的表会被放到服务器集群上,每个节点负责管理所有区域的一个子集.在线的所有区域按次序排列就构成了表的所有内容.

*加锁*
HBase对行的更新是原子的

**实现**
Hbase = 1个master节点 + 多个regionserver从属机
主控机master负责启动一个全新的安装,把区域分配给注册的regionserver,恢复regionserver故障.
regionserver负责将0个或者多个区域的管理和响应客户端的读写请求.还负责区域划分并告知master有新的子区域.

![](http://p5s7d12ls.bkt.clouddn.com/18-3-21/16805306.jpg)
HBase依赖于ZooKeeper,zookeeper集合体负责管理诸如hbase:meta目录表的位置以及当前集群主控机地址等重要信息.

HBase使用基于SSH的机制来运行远程命令,其配置方式类似于Hadoop,HBase通过Hadoop文件系统API来持久化存储数据,但在默认情况下,HBase会将存储写入本地文件系统,因此需要把它的存储配置指向要使用的HDFS集群.

*运行中的HBase*
HBase内部保留名为hbase:meta的特殊目录表,维护当前集群上所有区域的列表,状态和位置.区域变化时,目录表会重新进行相应的更新,这样集群上的信息状态就能保持是最新的.
新连接到zookeeper集群上的客户端首先查找hbase:meta位置,然后客户端通过查找合适的hbase:meta区域来获取用户空间区域所在节点和位置,接设客户端就可以直接和管理那个区域的regionserver交互.

每个行操作可能要访问三次远程节点,为节省代价,客户端会缓存hbase:meta时获取的信息.
到达regionserver的写操作首先追加到"提交日志",然后加入内存中的memstore.如果memstore满,它的内容会刷入文件系统.

简单使用
---
配置好hbase后,可用mingling`hbase shell`进入shell,输入help可以查看命令列表.
*创建一个表*
要新建一个表,必须为表起一个名字,并为其定义模式,一个表的模式包含表的属性和列族的列表,列族本身也有属性.模式可以被修改,需要修改时用`disable`将其设为'离线'即可,`alter`命令可以进行修改,`enable`将表定义为在线.
```sql
hbase(main):002:0> create 'test','data'
0 row(s) in 1.2920 seconds
```
新建一个名为test的表,只包含一个名为data的列,表和列族属性都为默认值.
```SQL
hbase(main):003:0> list
TABLE
test
1 row(s) in 0.0110 seconds```
list输出所有表.
```sql
hbase(main):004:0> put 'test','row1','data:1','value1'
0 row(s) in 0.1720 seconds

hbase(main):005:0> put 'test','row2','data:2','value2'
0 row(s) in 0.0120 seconds

hbase(main):006:0> put 'test','row3','data:3','valle3'
0 row(s) in 0.0080 seconds

hbase(main):007:0> get 'test','row1'
COLUMN                        CELL
 data:1                       timestamp=1521615103952, value=value1
1 row(s) in 0.0250 seconds

hbase(main):008:0> scan 'test'
ROW                           COLUMN+CELL
 row1                         column=data:1, timestamp=1521615103952, value=value1                              
 row2                         column=data:2, timestamp=1521615113126, value=value2                              
 row3                         column=data:3, timestamp=1521615131948, value=valle3                              
3 row(s) in 0.0210 seconds```
在列表中三行插入数据,get获取第一行,scan预览表的内容.
```sql
hbase(main):003:0> disable 'test'
0 row(s) in 2.3790 seconds

hbase(main):004:0> drop 'test'
0 row(s) in 1.2580 seconds

hbase(main):005:0> list
TABLE
0 row(s) in 0.0060 seconds
```
删除表之前先禁用.

客户端
---
**Java**
```java
public class ExampleClient {
    public static void main(String[] args) throws IOException {
       Configuration config = HBaseConfiguration.create();
       Connection conn = ConnectionFactory.createConnection(config);
       Admin admin  = conn.getAdmin();

        try {
            TableName tableName = TableName.valueOf("test");
            HTableDescriptor htd = new HTableDescriptor(tableName);
            HColumnDescriptor hcd = new HColumnDescriptor("data");
            htd.addFamily(hcd);
            admin.createTable(htd);
            HTableDescriptor[] tables = admin.listTables();
            if (tables.length != 1 && Bytes.equals(tableName.getName(), tables[0].getTableName().getName())) {
                throw new IOException("Failed create of table");
            }

            Table table = conn.getTable(tableName);
            try {
                for (int i = 1; i <= 3; i++) {
                    byte[] row = Bytes.toBytes("row" + i);
                    Put put = new Put(row);
                    byte[] columnFalily = Bytes.toBytes("data");
                    byte[] qualifier = Bytes.toBytes(String.valueOf(i));
                    byte[] value = Bytes.toBytes("value" + i);
                    put.add(columnFalily, qualifier, value);
                    table.put(put);
                }
                Get get = new Get(Bytes.toBytes("row1"));
                Result result = table.get(get);
                System.out.println("Get: " + result);
                Scan scan = new Scan();//scanner和cursor类似,不过在使用后要关闭
                ResultScanner scanner = table.getScanner(scan);
                try {
                    for (Result scannerResult : scanner) {
                        System.out.println("Scan: " + scannerResult);
                    }
                } finally {
                    scanner.close();
                }
                //先禁用,再丢弃
                admin.disableTable(tableName);
                admin.deleteTable(tableName);
            } finally {
                table.close();
            }
        } finally {
            admin.close();
        }
    }
}```
Configuration对象读入了程序classpath下hbase-site.xml等文件中的配置,客户端用ConnectionFactory创建了一个Connection对象,可以检索Admin和Table实例.Admin用于管理HBase集群,添加和丢弃表,Table用于访问指定的表.

**MapReduce**
HBase可以作为MR的源和输出,TableInputFormat类可以在区域边界进行分隔,使map能够拿到单个的区域进行处理,TableOutputFormat将把reduce的结果写入HBase;
```java
public class SimpleRowCounter extends Configured implements Tool {
    static class RowCounterMapper extends TableMapper<ImmutableBytesWritable, Result> {
        public static enum Counters { Rows }

        @Override
        protected void map(ImmutableBytesWritable key, Result value, Context context) throws IOException, InterruptedException {
            context.getCounter(Counters.Rows).increment(1);
        }
    }
    public int run(String[] args) throws Exception {
        if (args.length != 1) {
            System.err.println("Usage SimpleRowCounter <tablename>");
            return -1;
        }

        String tableName = args[0];
        Scan scan = new Scan();
        scan.setFilter(new FirstKeyOnlyFilter());
        Job job  = new Job(getConf(), getClass().getSimpleName());
        job.setJarByClass(getClass());
        TableMapReduceUtil.initTableMapperJob(tableName, scan, RowCounterMapper.class, ImmutableBytesWritable.class, Result.class, job);
        job.setNumReduceTasks(0);
        job.setOutputFormatClass(NullOutputFormat.class);
        return job.waitForCompletion(true) ? 0 : 1;
    }

    public static void main(String[] args) throws Exception {
        int exitCode = ToolRunner.run(HBaseConfiguration.create(), new SimpleRowCounter(), args);
        System.exit(exitCode);
    }
}```
 TableMapper是MR.Mapper的特化,他设定map输入类型由TableInputFormat来传递,输入键为ImmutableBytesWritable(行键), 值为Result(扫描行结果).TableMapReduceUtil.initTableMapperJob()对作业进行配置.

**加载数据**将要写入的数据库必须在作业配置中通过设置TableOutoputFormat.OUTPUTTABLE属性来指定.
```java
        FileInputFormat.addInputPath(job, new Path(args[0]));
        job.getConfiguration().set(TableOutputFormat.OUTPUT_TABLE, "observations");
        job.setMapperClass(HBaseTemperatureMapper.class);
        job.setNumReduceTasks(0);
        job.setOutputFormatClass(TableOutputFormat.class);```
*批量加载*
HBase有批量加载(bulk loading)工具,他从MR把以内部格式表示的数据直接写入文件系统,从而实现批量加载.这样比用API写入数据的方式快至少一个数量级.
>在使用Jar包向hbase加载数据时会出现如下错误
>2018-03-21 20:38:01,165 INFO  [main] mapreduce.Job: Running job: job_1521635550341_0002
2018-03-21 20:38:06,216 INFO  [main] mapreduce.Job: Job job_1521635550341_0002 running in uber mode : false
2018-03-21 20:38:06,217 INFO  [main] mapreduce.Job:  map 0% reduce 0%
2018-03-21 20:38:06,234 INFO  [main] mapreduce.Job: doop.util.Shell.run(Shell.java:869)
        at org.apache.hadoop.util.Shell$ShellCommandExecutor.execute(Shell.java:1170)
        at org.apache.hadoop.yarn.server.nodemanager.DefaultContainerExecutor.launchContainer(DefaultContainerExecutor.java:236)
        at org.apache.hadoop.yarn.server.nodemanager.containermanager.launcher.ContainerLaunch.call(ContainerLaunch.java:305)
        at org.apache.hadoop.yarn.server.nodemanager.containermanager.launcher.ContainerLaunch.call(ContainerLaunch.java:84)
        at java.util.concurrent.FutureTask.run(FutureTask.java:266)
        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
        at java.lang.Thread.run(Thread.java:748)
解决办法:yarn-site.xml的yarn.application.classpath配置项中，加上hbase相关的jar包。


Container exited with a non-zero exit code 1
For more detailed output, check the application tracking page: http://*********:8088/cluster/app/application_1521635550341_0002 Then click on links to logs of each attempt.
. Failing the application.

批量加载过程:
1. 使用HFileOutputFormat2通过一个MR作业将HFile写入HDFS目录
2. 将HFiles从HDFS一如现有的HBase表中,该表在此过程可以是活跃的

HBase和RDBMS比较
---
HBASE:
分布式,面向列的数据存储系统,在HDFS上提供随机读写,聚焦于各种可伸缩问题,表可以很宽,很高,水平分区在上千个普通商用机节点复制.
RDBMS:
模式固定, 面向行,ACID性质,扩展性不强






