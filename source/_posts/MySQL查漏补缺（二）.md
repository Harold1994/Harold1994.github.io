---
title: MySQL查漏补缺（二）
date: 2018-04-04 22:55:35
tags: [数据库, MySQL]
---

* 在GROUP BY语句后使用WITH ROLLUP，在所有查询结果后会增加一条记录，计算查询出的所有记录的总和

* 使用WITH ROLLUP时，不能同时使用ORDER BY子句排序，两者相互排斥

* 使用LIMIT限制查询结果的数量，`LIMIT [位置偏移量（默认为0），] 行数`，偏移量表示从哪一行开始显示

* COUNT(*)计算表中总的行数，不管某列是否有空值，COUNT（字段名）会忽略字段列中的空值

* SUM（）函数计算时会忽略NULL的行

* MAX()和MIN()都不仅可以查找数据类型，还可以用于字符类型

* 连接查询条件：两个或多个列表存在相同意义的字段

* 在一个连接查询中，如果涉及到的两个表都为一个表，称为自连接查询，自连接是特殊的内连接。两表相同时，用AS取别名防止二义性

  <!-- more-->

* 子查询：一个查询语句嵌套到一个查询语句的内部

* SOME，ANY表示满足其中任一条件，允许创建一个表达式对子查询的返回列表进行比较，只要满足内层子查询中的任何一个比较条件，就返回一个结果作为外层查询的条件

* ALL关键字需要同时满足所有的内层查询条件

* EXISTS关键字后面跟任意子查询，子查询有返回行则返回TRUE，此时外层语句将进行查询，否则返回false，对称的操作时NOT EXISTS

* 利用UNION关键字可以给出多条SELECT语句，并将它们的结果组合成单个结果集。合并时，两个表对应的列和数据类型必须相同。UNION会删除重复的记录，所有返回的行都是唯一的，UNION ALL不删除重复行也不对结果自动排序。UNION ALL的效率高一点

* LIKE匹配的字符串如果在文本中间出现，则找不到它，相应的行也不会返回，REGEXP会返回

* 更新表UPDATE table_name SET column_name = val WHERE condition如果忽略WHERE子句，MySQL将更新表中所有的行

* TRUNCATE TABLE语句直接删除原来的表并新建一个表，比DELETE速度快

* 索引用于快速查找出某个列中有一特定行的值，是对数据库表中一列或者多列的值进行排序的一种结构，可提高特定数据的查询速度

* 索引是单独存储在磁盘上的数据结构，所有MySQL列类型都可以被索引

* 索引优点：
> 1. 通过创建唯一索引，可以保证数据库表中每一行数据的唯一性
> 2. 可以大大加快数据的查询速度
> 3. 在实现数据参考的完整性方面，可以加速表与表之间的连接
> 4. 在使用分组和排序子句进行数据查询时，可以显式减少查询中分组和排序的时间
* 索引缺点：
> . 创建索引和维护索引需要耗费时间，并且随着数据量的增加所耗费的时间也会增加
> . 索引需要占磁盘空间
> . 对表中的数据进行增加、删除和修改的时候，索引也要动态维护，降低了维护速度

索引分类：
> * 普通索引：基本索引类型，允许在定义索引的列中插入重复值和空值
> * 唯一索引：索引列必须是唯一的，允许有空值。主键索引是特殊唯一索引，不允许有空值
> * 单列索引：一个索引只允许包含一列，一个表可以有多个单列索引
> * 组合索引：在表的多个字段组合上创建的索引，只有在查询条件中使用了这些字段的左边字段时，索引才会被使用。遵循最左前缀原则
> * 全文索引：类型为FULLTEXT，在定义索引的列上支持全文查找，允许在这些索引列中插入重复值和空值MySQL中只有MyISAM存储引擎支持全文索引
> * 空间索引：对空间数据类型字段建立的索引。
创建表时创建索引：`CREATE TABLE table_name [col_name data_type] [UNIQUE|FULLTEXT|SPATIAL] [INDEX|KEY] [index_name] (col_name [length]) [ASC | DESC]`,UNIQUE|FULLTEXT|SPATIAL 可选，分别表示唯一索引，全文索引和空间索引，INDEX与KEY为同义词，用来指定创建索引，index_name为索引名，可选，若不指定，则默认以col_name为索引值;length可选，表示索引的长度，只有字符串类型的字段才能指定索引长度。

```SQL
mysql> show create table book\G
*************************** 1. row ***************************
       Table: book
Create Table: CREATE TABLE `book` (
  `book_id` int(11) NOT NULL,
  `book_name` varchar(255) NOT NULL,
  `authors` varchar(255) NOT NULL,
  `info` varchar(255) DEFAULT NULL,
  `comment` varchar(255) DEFAULT NULL,
  `year_publication` year(4) NOT NULL,
  KEY `year_publication` (`year_publication`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
1 row in set (0.00 sec)
```
使用EXPLAIN语句查看索引是否正在使用。
```SQL
mysql> explain select * from book where year_publication=1990 \G
*************************** 1. row ***************************
           id: 1
  select_type: SIMPLE
        table: book
   partitions: NULL
         type: ref
possible_keys: year_publication
          key: year_publication
      key_len: 1
          ref: const
         rows: 1
     filtered: 100.00
        Extra: Using index condition
1 row in set, 1 warning (0.01 sec)

```
* `ALTER TABLE table_name ADD [UNIQUE|FULLTEXT|SPATIAL] [INDEX|KEY] [index_name] (col_name[length]) [ASC|DESC]`在已存在的表上添加索引
* `CREATE [UNIQUE|FULLTEXT|SPATIAL] INDEX index_name ON table_name (col_name[length],...) [ASC|DESC]`在已存在的表上添加索引
* `ALTER TABLE table_name DROP INDEX index_name`删除索引
* 添加AUTO_INCREMENT约束字段的唯一索引不能被删除
* DROP INDEX index_name ON table_name;
* 存储过程是一条或多条SQL语句的集合，可视为批文件。
* 存储程序可以分为存储过程和函数。创建存储过程，只能用输出变量返回值。`CREATE PROCEDURE`,创建函数`CREATE FUNCTION`，使用`CALL`语句调用存储过程。函数可以从语句外部调用，也能返回标量值。存储过程可以调用其他存储过程。
* `CREATE PROCEDURE sp_name ([proc_parameter]) [characteristics ...] routine_body`,proc_parameter指定参数列表，列表形式：`[IN | OUT | INOUT] param_name type`,type参数类型可以时MySQL数据库中的任意类型。characteristic指定存储过程的特性，取值有：
> LANGUAGE SQL:说明routine_body部分是由SQL语句组成的
> [NOT] DETERMINISTIC：指明存储过程结果是否确定，即相同的输入是否能得到相同的输出
> {CONSTRAINS SQL | NO SQL | READS SQL DATA | MODIFIES SQL DATA}，指明子程序使用SQL语句的限制
> SQL SECURITY {DEFINER（定义者——默认） | INVOKER（拥有权限的调用者）}：指定谁有权执行
> COMMENT'string':注释信息

routine_body是SQL代码内容，用BEGIN...END表示开始和结束

```SQL
mysql> DELIMITER //
mysql> CREATE PROCEDURE CountProc (OUT param1 INT)
    -> SELECT COUNT(*) INTO param1 FROM fruits;
    -> END //
```
将计算结果放入参数param1,`DELIMITER //`语句设置结束符，避免与存储过程中的;相冲突
* 创建存储函数`CREATE FUNCTION func_name ([func_parameter]) RETURNS type [characteristic...] routine_body`,RETURNS type表示函数返回数据的类型
* ```sql
  mysql> CREATE FUNCTION NameByZip()
    -> RETURNS CHAR(50)
    -> RETURN (SELECT f_name FROM fruits WHERE s_price>5.0);
    -> //
  Query OK, 0 rows affected (0.01 sec)
  ```

如果存储函数中RETURN语句返回的类型不同于函数RETURNS子句中指定类型不同，返回值将被强制为恰当的类型。函数体必须包含一个RETURN value语句
* 变量可以在子程序中声明使用，作用范围是BEGIN...END程序中
* 定义变量：`DECLARE var_name[,var_name]... data_type [DEFAULT value]`
* 改变变量值：`SET var_name = expr [,var_name = expr]...`
* 通过`SELECT col_name[,...] INTO var_name[,...] table_expr`向变量赋值
* 定义条件是事先定义程序执行过程中遇到的问题，处理程序定义了在遇到问题时应当采取的处理方式，并且保证存储过程或函数在遇到警告或错误时能继续执行。
* 定义条件：
* ```SQL
    CREATE condition_name CONDITION FOR [condition type]
    
    [condition_type]:
    SQLSTATE [VALUE] sqlstate_value | mysql_error_code```
    condition type表示条件的类型，sqlstate_value 和 mysql_error_code都表示MySQL的错误
    ```
* 定义处理程序：

```SQL
DECALRE handler_type HANDLER FOR condition_value[,...] sp_statement
handler_type:
CONTINUE | EXIT | UNDO

condition_value:
	SQLSTATE [VALUE]  sqlstate_value
    | condition_name
    | SQLWARNING
    | NOT FOUND
    | SQLEXCEPTION
    | mysql_error_code
```

handler_type为错误处理方式，有三个取值，UNDO表示遇到错误后撤回之前的操作，MySQL不支持UNDO
`e.g:DECLARE CONTINUE HANDLER FOR 1146 SET @info='NO_SUCH_TABLE'`;

* @var_name表示用户变量，使用SET赋值，与连接有关，一个客户端定义的变量不能被其他客户端看到或使用，客户端退出时，其连接的用户变量将自动释放。

* 光标：数据量大时，在存储过程和函数中逐条读取查询结果集中的记录。必须在声明处理程序之前声明光标，并且变量和条件还必须在声明光标或处理程序之前被声明。

* `DECLARE cursor_name CURSOR FOR select_statement`声明标签

* `OPEN cursor_name`:打开先前声明的光标

* `FETCH cursore_name INTO var_name,...`使用光标，将光标存入var_name,var_name必须在声明光标前就定义好

* `CLOSE cursor_name`:关闭光标

* MySQL中光标只能在存储过程和函数中使用

* 流程控制语句：根据条件控制语句的执行，IF，CASE，LOOP，LEAVE，ITERATE，REPEAT，WHILE语句等

* IF语句：

  ```sql
   IF expr_condition THEN statement_list
   	[ELSEIF expr_condition THEN statement_list]...
   	[ELSE statement_list]
   END IF
  ```

* CASE语句：

  ```sql
  CASE case_expr
  	WHEN when_value THEN statement_list
      [WHEN when_value THEN statement_list] ...
      [ELSE statement_list]
  END CASE
  ```
* LOOP语句：

  ```java
  [loop_label：] LOOP
  	statement_list
  END LOOP [loop_label]
  ```

使用LEAVE语句退出LOOP
* LEAVE语句用来退出任何被标注的控制流程构造，语法`LEAVE label`
* ITERATE语句将执行顺序转到语句段开头处，语法`ITERATE label`
* REPEAT语句创建一个带条件判断的循环过程：
```SQL
·[repeat_label:] REPEAT
	statement_list
UNTIL expr_condition
END REPEAT [repeat_label]
```
* WHILE语句：
```SQL
[while_label:] WHILE expr_condition DO
	statement_list
END WHILE [while_label]
```
* 调用存储过程：`CALL sp_name(parameter[,...])`
* `SHOW {PROCEDURE | FUNCTION} STATUS [LIKE 'pattern']`查看存储过程和函数的状态
* `SHOW CREATE {PROCEDURE | FUNCTION} sp_name `查看存储过程和函数的定义
* `SELECT * FROM information_schema.Routines WHERE ROUTINE_NAME = 'sp_name'`,从information_schema.Routines表中查看procedure和函数信息。
* 修改存储过程和函数`ALTER {PROCEDURE | FUNCTION} sp_name [characteristic...]`,characteristic表示存储函数的特性
* `DROP {PROCEDURE | FUNCTION} [IF EXISTS] sp_name`删除过程和函数
* 存储程序和函数的比较：本质上都是存储程序，函数只能通过return语句返回单个值或者表对象，而存储过程不允许执行return，但是可以通过OUT返回多个值。函数限制比较多，不能用临时表，只能用表变量，还有一些函数不可用;存储过程限制较少。函数可以嵌入在SQL语句中使用，存储过程一般作为一个独立的部分来执行
* 在存储过程中可以用CALL调用其他存储过程，但是不能用DROP语句删除其他存储过程
* 传入中文参数时，要在定义存储过程的语句中加入`character set gbk`