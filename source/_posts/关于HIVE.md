---
title: 关于Hive
date: 2018-03-17 11:43:31
tags: [大数据, Hive, Hadoop]
---

>本篇博客主要来自于本人学习<<Hadoop权威指南>>Hive部分的笔记和一些理解

Hive是构建在Hadoop上的数据仓库框架,它把SQL查询转换为一系列在Hadoop集群上运行的作业,它的数据组织为表,元数据(eg.表模式)存储在metastore数据库中. metastore默认模本式为运行在本机上.

Hive shell环境
---

HiveQL是Hive的查询语言,类似Mysql,运行方式有:
  <!-- more-->
*	**交互模式** : hive命令进入shell
	
    > 第一次使用时会花几秒时间,因为系统采用**"延迟"**策略,直到执行第一个命令才在运行hive命令的那个位置下的metastore_db目录中创建metastore数据库.

*	**非交互模式** : 
	`hive -f script.q` -f选项运行指定文件中的命令
	`hive -e 'SELECT * FROM DUMMY'` -e选项在行内嵌入命令
    
**用到的HiveQL特有的关键字**:

>`create table records (year STRING, temperature INT, quality INT) ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t';`

* 	ROW FORMAT : 声明数据文件的每一行是由制表符分割的文本

> `LOAD DATA LOCAL INPATH 'input/ncdc/micro-tab/sample.txt' OVERWRITE INTO TABLE records;`

* 告诉Hive将本地文件放入其仓库目录,此操作并不解析文件或将它存储为内部数据库格式,因为Hive不强制使用任何特定文件格式. 在Hive中,表存储为目录,可由hive.metastore.warehouse.dir控制目录位置.

* OVERWRITE	: 删除表对应目录中的所有文件

>`select year ,MAX(temperature) from records where temperature != 9999 and quality in (0,1,4,5,9) group by year;`

* Hive 将查询转化为一个作业并执行作业,将结果打印到console

**Hive设置属性优先级(顺序递减)**:

	. SET命令
	. 命令行 -hiveconf选项
	. hive-site.xml 和 Hadoop站点文件
	. Hive默认值和Hadoop默认值

***MetaStore***
---
metastore是Hive元数据的存放地,包括*服务*和*后台数据*的存储,默认情况下metastore和Hive运行在同个JVM,包含一个内嵌的以本地磁盘作为存储的[Derby数据库](https://www.cnblogs.com/zuzZ/p/8107915.html)实例,称为**内嵌metastore配置**.

> 内嵌配置的缺点:每次只有一个内嵌Derby数据库可访问磁盘上的数据库文件,一次只能为每个metast打开一个Hive会话.

要支持多个会话,需使用一个独立的数据库,称为**本地metastore配置**需要设置本地Mysql的用户名,密码等,还可以利用**远程metastore配置**使得一个或多个metastore服务器和Hive服务器运行在不同进程内,客户端不需数据库凭据.

传统数据库与Hive对比
---
1. 传统数据库: **写时模式**,表的模式在加载时强制确定
	>缺点: 加载慢,需要读取数据进行解析->序列化->以内部格式存入磁盘.
	>优点: 有利于提升查询性能,因为可以对列进行索引,对数据压缩.

   Hive: **读时模式**,在查询时才验证数据模式,加载迅速,仅仅是文件的复制和移动

2. 更新,事务和索引

 	HDFS不支持就地更新,插入,更新删除操作引起的一切变化都被保存在一个增量文件中,由metastore在后台运行的mapreduce作业会定期将增量文件合并到基表.
    
    Hive引入了表级和分区级的锁,由ZooKeeper透明管理,用户不用执行获得和释放锁的操作.
    
    Hive索引分为*紧凑*和*位图*索引,可插拔,紧凑索引存储每个值的HDFS块号而不是文件内偏移量,不会占用过多磁盘空间;位图索引使用压缩的bitset来高效存储具有特殊值的行,适用于具有极少取值的列.
    
表
---
Hive中的表在逻辑上由存储的数据和描述表中数据形式的相关元数据组成.*数据*一般存放在HDFS上,也可以是其他Hadoop文件系统,Hive把*元数据*存放在关系型数据库

**托管表和外部表**
Hive创建表时,默认由Hive管理数据,将数据移入它的"仓库目录",称为*托管表*.另一种方式是*外部表*,Hive到仓库目录以外的位置访问数据. 区别体现在DROP 和 LOAD上.

* 托管表:
> 加载操作就是文件系统中文件移动或重命名,执行速度快,如果要手动检查是否满足模式,可以通过查询为缺失字段返回的空值NULL才知道不匹配的行.
>`load data local inpath 'input/hive/dummy.txt' into table managed_table;`
>执行删除操作后,它的元数据和数据会被一起删除,在HDFS中可以看到删除表后/user/hive/warehouse中的managed_table也被删除了.
>`drop table managed_table;`

* 外部表
> 创建表示需要指明外部数据的位置,定义时Hive不会检查外部位置是否存在,故可以在创建表之后再创建数据
> `create external table external_table (dummy STRING) LOCATION /user/harold/external_table`;
> 丢弃外部表时,Hive只会删除元数据,不会删除数据

**分区和桶**
Hive把表组织成*分区*,使用分区可以加快数据分片的查询速度.表或分区可以进一部分为桶(bucket)它会为数据提供额外的结构以获得更高效的查询处理.

- *分区* : 分区使得表对限制到某个特定范围的数据的查询变得非常高效(比如按照日期分区),只需扫描查询范围内分区中的文件,而且不会影响大范围查询的执行.一个表可以以多个维度分区,即进行子分区.

分区是在创建表时用PARTITIONED BY子句定义的:
 >`CREATE TABLE logs (ts BIGINT, line STRING) PARTITIONED BY (dt STRING, country      STRING);`

  在将数据加载到分区表时,要显示指定分区值:
 > `LOAD DATA LOCAL INPATH 'input/hive/partitions/file1' INTO TABLE logs PARTITION (dt='2001-01-01', country='GB');`
 > `SHOW PARTITON logs;` 可以展示表中的分区

- *桶* :
	将表或分区组织成桶的理由:
   > . 获得高效的查询处理效率
   > . 使取样更高效
创建被划分成桶的表:
   >`CREATE TABLE bucketed_users (id INT, name STRING) CLUSTERED BY (id) INTO 4 BUCKETS;`
   桶中的数据可以根据一个列或者多个列排序,这样对每个桶的连接变成了高效的归并排序,提升了map端连接的效率:
   > `CREATE TABLE bucketed_users (id INT, name STRING) CLUSTERED BY (id) SORTED BY (id) INTO 4 BUCKETS;`

   Hive并不检查数据文件中的桶是否和表定义中的桶一致,无论是桶的数量还是用来划分的列, 如果不匹配会 ,查询时会碰到错误或未定义的结果.
   将一个没有划分桶的数据集users填充进分桶后的表的步骤如下:
   > `SET hive.enforce.bucketing=true;` 这样Hive就知道用表中声明的数量来创建桶
   > `INSERT OVERWRITE TABLE bucketed_users SELECT * FROM users;`Insert 即可
   
物理上,每个桶就是表目录中的一个文件,一个作业产生的桶(输出文件)和reduce任务个数相同.
   
用TABLESAMPLE子句对表取样:
`SELECT * FROM bucketed_users TABLESAMPLE(BUCKET 1 OUT OF 4 ON id);`
和
`SELECT * FROM users TABLESAMPLE(BUCKET 1 OUT OF 4 ON id);`
 
得到的结果一样.
 
**存储格式**
 
 Hive从两个维度对表的存储进行管理:
 * 行格式: 行和行中的字段如何存储,行格式由SerDe(Serializer-Deserializer)定义. 当作为反序列化工具使用时(即查询表),SerDe将把文件中字节形式的数据反序列化为Hive内部操作行时所使用的对象形式,作为序列化工具时(INSERT,CTAS),表的SerDe会把Hive的数据行内部表示形式序列化成字节形式并写道输出文件中.
 * 文件格式: 一行中字段容器的格式
 
*默认的存储格式----分隔的文本*

在创建表时如果没有用ROW FORMAT或STORED AS子句,Hive所使用的默认格式是分隔的文本,每行存储一个数据行.

默认行内分隔符不是制表符,而是ASCII控制码集合中的Control-A,原因是它出现在字段文本中的可能性较小,Hive中无法对分隔符进行转义,因此挑选一个不会在数据字段中用到的字符作为分隔符非常重要.
> 集合类的默认分隔符为Control-B,用于分隔ARRAY,STRUCT或MAP的键值对中的元素
> 默认的映射键(map key)分隔符为Control-C,用于分隔map的键和值
> 表中各行用换行符分隔
> 可以用hexdump查看输出文件的分隔符

Hive支持8级分隔符,对应ASCII编码的1-8,但只能重载前三个.可用8进制形式表示分隔符,如001表示Control-A.

Hivene内部使用LazySimpleSerDe来处理这种分隔格式以及面向行的MapReduce文本输入输出格式,他对字段的反序列化是延时处理的,只有在访问字段时才进行反序列化.

*二进制存储格式: 顺序文件 Avro数据文件 Parquet文件 RCFile ORCFile*

二进制格式:
1. 面向行的格式(Avro,顺序文件): 适合同时处理一行中很多列
	> `SET hive.exec.compress.output=true;`
	> `SET avro.output.codec=snappy;`
	> `CREATE TABLE ... STORE AS AVRO;`
	> 可以将表存储为Avro格式
2. 面向列的格式(Parquet文件 RCFile ORCFile): 对于只访问表中一小部分列的查询有效

使用定制的SerDe: RegexSerDe
>`REATE TABLE stations (usaf STRING, wban STRING, name STRING) ROW FORMAT SERDE 'org.apache.hadoop.hive.contrib.serde2.RegexSerDe' WITH SERDEPROPERTIES ("input.regex" = "(\\d{6}) (\\d{5}) (\\.{29}) .*");`
>
>使用SERDE关键字和JAVA类完整类名指明使用哪个SerDe.用 WITH SERDEPROPERTIES设置SERDE的额外属性.
>
>`LOAD DATA LOCAL INPATH "input/ncdc/metadata/stations-fixed-width.txt" INTO TABLE stations;`
>
>`hive> SELECT * FROM stations LIMIT 4;
OK
010000	99999	BOGUS NORWAY
010003	99999	BOGUS NORWAY
010010	99999	JAN MAYEN
010013	99999	ROST `
效率比较低,一般用二进制存储格式

*导入数据*
> **INSERT语句**
> 动态分区插入:
>>`INSERT OVERWRITE TABLE target PARTITION(dt) SELECT COL1, CLO2, dt FROM source`

>**多表插入**
>>`FROM records2`
`INSERT OVERWRITE TABLE stations_by_year SELECT year,COUNT(DISTINCT station) GROUP BY year`
`INSERT OVERWRITE TABLE records_by_year SELECT year, COUNT(1) GROUP BY year`
`INSERT OVERWRITE TABLE good_records_by_year SELECT year, COUNT(1) WHERE temperature != 9999 AND quality IN (0, 1, 4, 5, 9) GROUP BY year;`
比单表效率高,只需扫一遍原表就可以生成多个不想交的输出

>**CTAS**
>`CREATA TABLE target AS SELECT col1, col2 FROM source;`
>CTAS操作是原子的,如select查询由于某种原因失败,则不会创建表target

*表的修改*
Hive使用读时模式,创建表后可以灵活的支持对表的修改,但是需要警惕确保修改数据以符合新的结构.
>`ALTER TABLE source RENAME TO target;`

重命名表,在更新元数据以外ALTER TABLE还把表目录移到新名称对应的目录下,对于外部表则只更新元数据.

>`ALTER TABLE target ADD COLUMNS (cols3 STRING);`

添加新的列cols3在已有(非分区)列的后面,数据文件并没有更新,原来的查询会为cols3的结果返回null,Hive不允许更新已有的记录,故一般创建一个定义了新列的新表.然后使用SELECT语句把数据填充进去.

*表的丢弃*
DROP TABLE;删除表中数据和元数据(外部表数据除外)
TRUNCATE TABLE my_table;删除表内所有数据,但保留定义(对外部表不起作用)
CREATE TABLE new_table LIKE existing_table;达到类似TRUNCATE的目的.

查询数据
---
**排序和聚集**
* ORDER BY : 对输入执行并行全排序
* SORT BY : 为每个reducer产生一个排序文件
* DISTRIBUTE BY : 控制特定行到某个reducer,便于后续的聚集操作
>`FROM records2 SELECT year, temperature DISTRIBUTE BY year SORT BY year ASC, temperature DESC;`

**MapReduce脚本**
TRANSFORM,MAP,REDUCE子句可在Hive中调用外部脚本或程序.
> ``` python
>#is_good_quality.py
>import re
import sys
for line in sys.stdin:
    (year,temp,q) = line.strip().split()
    if (temp != "9999" and re.match("[01459]"),q)):
        print("%s\t%s" % (year, temp))```

>`ADD FILE /input/is_good_quality.py;` 在Hive中注册脚本,Hive将脚本文件传到Hadoop集群
>`FROM records2 select TRANSFORM(year,temperature,quality) USING 'is_good_quality.py' as year, temperature;` 

这一实例并未使用reducer.如果要使用嵌套模式,可以指定map和reduce函数:
>```python
>FROM (
  FROM records2
  MAP year, temperature, quality
  USING 'is_good_quality.py'
  AS year, temperature) map_output
REDUCE year, temperature
USING 'max_temperature_reduce.py'
AS year, temperature;```
和
```python
FROM (
  FROM records2
  SELECT TRANSFORM(year, temperature, quality)
  USING 'is_good_quality.py'
  AS year, temperature) map_output
SELECT TRANSFORM(year, temperature)
USING 'max_temperature_reduce.py'
AS year, temperature;```
结果一致

**连接**

*内连接*:输入表之间每次匹配都会在输出行里生成一行:
>```
>SELECT * FROM sales;
Joe	2
Hank	4
Ali	0
Eve	3
Hank	2```
>```
> SELECT * FROM things;
2	Tie
4	Coat
3	Hat
1	Scarf```

>```
SELECT sales.*, things.* FROM sales JOIN things ON (sales.id = things.id);
Joe	2	2	Tie
Hank	4	4	Coat
Eve	3	3	Hat
Hank	2	2	Tie
```
>JOIN子句中的顺序很重要:一般将最大的表放到最后,因为JOIN前一阶段生成的数据会存在于Reducer的buffer中，通过stream最后面的表，直接从Reducer的buffer中读取已经缓冲的中间结果数据（这个中间结果数据可能是JOIN顺序中，前面表连接的结果的Key，数据量相对较小，内存开销就小），这样，与后面的大表进行连接时，只需要从buffer中读取缓存的Key，与大表中的指定Key进行连接，速度会更快，也可能避免内存缓冲区溢出.(出自[简单之美](http://shiyanjun.cn/archives/588.html))
>
Hive只支持等值连接,在连接谓词中只能使用等号,还可以在在查询中使用多个JOIN...ON...子句来连接多个表,Hive会智能的以最少的MapReduce作业数来执行连接.单个连接用一个MR作业实现,如果多个连接条件中使用了相同的列那么平均每个连接可以使用少于一个MR作业来实现.

**外连接**
外连接可以找到表中不能匹配的数据行:
>```
>左连接
SELECT sales.*, things.* FROM sales LEFT OUTER JOIN things ON (sales.id = things.id);
Joe	2	2	Tie
Hank	4	4	Coat
Ali	0	NULL	NULL
Eve	3	3	Hat
Hank	2	2	Tie
```
当然Hive也支持右连接和全外连接:
>```右连接
SELECT sales.*, things.* FROM sales RIGHT OUTER JOIN things ON (sales.id = things.id);
Joe	2	2	Tie
Hank	2	2	Tie
Hank	4	4	Coat
Eve	3	3	Hat
NULL	NULL	1	Scarf```
>```
>SELECT sales.*, things.* FROM sales FULL OUTER JOIN things ON (sales.id = things.id)
>Ali	0	NULL	NULL
NULL	NULL	1	Scarf
Hank	2	2	Tie
Joe	2	2	Tie
Eve	3	3	Hat
Hank	4	4	Coat
```
**半连接**
LEFT SEMI JOIN:
>```
select * from sales left semi join things on (sales.id = things.id);
Joe	2
Hank	4
Eve	3
Hank	2```
右表只能在ON子句中出现,不能在SELECT表达式中引用右表.

**map连接**
如果有一个连接表小到足以放入内存,Hive就将较小的表放入每个mapper的内存来执行连接操作.
map连接不适用Reducer,因此对于RIGHT或者FULL OUTER JOIN无效,因为只有在对所有输入上进行聚集的步骤(reduce)才能检测到那个数据行无法匹配.
map连接可以利用分桶的表,因为作用于左侧表的桶的mapper加载右侧表中对应的桶即可执行连接.需要`SET hive.optimize.bucketmapjoin=true`启用优化选项.

**子查询**
子查询是内嵌在另一个SQL语句中的SELECT语句,Hive只允许子查询出现在SELECT语句的FROM子句中,或某些特殊情况下的WHERE子句中.
>```
>hive> SELECT station, year, AVG(max_temperature)
     FROM (
     SELECT station, year, MAX(temperature) AS max_temperature
     FROM records2
     WHERE temperature != 9999 AND quality IN (0,1,4,5,9)
     GROUP BY station, year
     ) mt
     GROUP BY station, year;
```
外层查询像访问表那样访问子查询的结果,所以必须为子查询赋予一个别名(mt),子查询中的列必须有唯一的名称,以便外层访问引用这些列.

**视图**
用SELECT语句定义的虚表,可以限制用户,使其只能访问被授权可以看到的表的子集.Hive中,创建视图并不把视图物化存储到磁盘上,视图的SELECT语句只在执行引用视图的语句时才执行.要手工物化视图,可以新建一个表,将视图内容存储到新表中.
创建方式:CREATE VIEW
> ```
> CREATE VIEW valid_records AS SELECT * FROM records2 WHERE temperature != 9999 AND quality IN (0,1,4,5,9);```
> 创建视图时并不执行查询,查询只是存储在metastore中,SHOW TABLES命令结果包含视图,可用DESCRIBE EXTENDED view_name来查看视图的详细信息.
> ![](/home/harold/Pictures/Selection_021.png)

Hive可以把使用视图的查询组织为一系列作业,效果与不使用视图一样.即使在执行时,Hive也不会再不必要的情况下物化视图.

Hive中的视图是只读的,无法通过视图为基表加载或插入数据.

用户定义函数----UDF
---
用户定义函数(user-defined function)必须用Java编写,其他语言可以用之前用过的`SELECT TRANSFORM`查询.

Hive三种UDF, 他们所接受的输入和产生的输出的数据行的数量不同 :
* 普通UDF : 作用于单个数据行,产生一个数据行
* 用户定义聚集函数 UDAF : 接受多个数据行,产生一个输出行, 类似COUNT , MAX
* 用户定义表生成函数 UDTF : 作用于单个数据行, 产生多个输出行

*UDTF*:
```>
hive> create table arrays (x ARRAY<STRING>) ROW
    > FORMAT DELIMITED
    > FIELDS TERMINATED BY '\001'
    > COLLECTION ITEMS TERMINATED BY '\002';```

```>
hive> SELECT * FROM arrays;
OK
["a","b"]
["c","d","e"]
```
explode UDTF对表进行变换,为数组中的每一项输出一行.
```>
hive> SELECT explode(x) AS y from arrays;
OK
a
b
c
d
e```

常用的UDTF还有SPLIT() 等,还有更强大的LATERAL VIEW查询,笔者会在之后的博客详细介绍.

**写UDF**
```java
import org.apache.commons.lang.StringUtils;
import org.apache.hadoop.hive.ql.exec.UDF;
import org.apache.hadoop.io.Text;

public class Strip extends UDF {
    private Text result = new Text();
    public Text evaluate (Text str) {
        if (str == null) {
            return null;
        }

        result.set(StringUtils.strip(str.toString()));
        return result;
    }

    public Text evaluate(Text str, String stripChars) {
        if(str == null) {
            return null;
        }
        result.set(StringUtils.strip(str.toString(), stripChars));
        return result;
    }
}```

一个UDF必须满足:
1. 是org.apache.hadoop.hive.ql.exec.UDF的子类
2. 至少实现了evaluate()方法

evaluate()不是由接口定义的,它接受的参数个数和类型以及返回值都是不确定的,Hive会检查UDF,看能否找到相匹配的evaluate().

使用UDF:
1.在metastore中注册函数并用CTREATE FUNCTION为它取名:
> CREATE FUNCTION strip AS 'com.hadoopbook.hive.Strip' USING JAR 'path/hive-example.jar'

2.使用内置函数:
>SELECT strip(' bee ') FROM dummy; UDF名对大小写不敏感

3.删除函数:
>DROP FUNCTION strip;

4.用TEMPORARY创建仅在Hive会话期间有效的函数,不在metastore中持久化:
>`ADD JAR /path/hive-example.jar;`
>`CREATE TEMPORARY FUNCTION strip AS 'com.hadoopbook.hive.Strip';`

**写UDAF**
```java
import org.apache.hadoop.hive.ql.exec.UDAF;
import org.apache.hadoop.hive.ql.exec.UDAFEvaluator;
import org.apache.hadoop.io.IntWritable;

public class Maximum extends UDAF{
    public static class MaximumIntUDAFEvaluator implements UDAFEvaluator{
        private IntWritable result;

        @Override
        public void init() {
            result = null;
        }


        public boolean iterate(IntWritable value) {
            if (value == null) {
                return true;
            }
            if (result == null) {
                result = new IntWritable(value.get());
            } else {
                result.set(Math.max(result.get(), value.get()));
            }
            return true;
        }

        public IntWritable terminatePartial() {
            return result;
        }

        public boolean merge(IntWritable other) {
            return iterate(other);
        }

        public IntWritable terminate() {
            return result;
        }
    }
}
```
UDAF必须是org.apache.hadoop.hive.ql.exec.UDAF的子类(*UDAF类已经过时弃用了，现在是实现GenericUDAFResolver2接口,请看本博客另一篇相关的文内容*), 且包含一个或多个嵌套的实现了Org.apache.hadoop.hive.ql.exec.UDAFEvaluator的*静态类*.

一个计算函数必须实现以下五个方法:

* init() : 负责初始化计算函数并设置他的内部状态

* inerate() : 每次对一个新值进行聚集计算都会调用此方法,iterate()接受的参数和Hive中被调用函数的参数是对应的.

* terminate() : Hive需要部分聚集结果时会调用此方法,这个方法必须返回一个封装了聚集计算当前状态的对象.

*  merge()方法 : 在Hive合并两个部分聚集值时会调用merge()方法.该方法接受一个对象作为输入,其类型必须和terminatePartial()方法的返回类型一致.
 
*  terminate()方法 : Hive需要最终聚集结果时会调用此方法

*  计算流程见下图:
![](http://p5s7d12ls.bkt.clouddn.com/18-3-18/61809116.jpg)










