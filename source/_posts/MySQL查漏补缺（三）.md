---
title: MySQL查漏补缺（三）
date: 2018-04-08 00:05:51
tags: [数据库, MySQL]
---
* 视图：虚拟表，从数据库中的一个或多个表中导出来的表，还可以在已定义视图的基础上定义。
* 视图中看到的数据只是存放在基本表中的数据，若基本表数据发生变化，则这种变化可以自动反映到视图中。
*  创建视图：
```SQL
CREATE [OR REPLACE] [ALGORITHM = {UNDEFINED | MERGE | TEMPTABLE}]
		VIEW view_name [(column_list)]
    	AS SELECT_statement
    	[WITH [CASCADED | LOCAL] CHECK OPTION]
```
<!-- more-->
REPLACE表示替换已有视图，WITH [CASCADED | LOCAL] CHECK OPTION表示视图在更新时保证在视图的权限范围之内。CASCADE（级联的）为默认值，表示视图更新时要满足所有相关视图和表的条件;LOCAL表示更新时满足该视图本身定义的条件即可。
视图选择的算法有三种，UNDEFINED表示MySQL将自动选择算法;MERGE表示将使用的视图语句与视图定义合并起来，使得视图定义的某一部分取代语句对应的部分;TEMPTABLE表示将视图结果存入临时表，然后用临时表执行语句。

* 默认情况下，将在当前数据库创建新视图。要在给定数据库创建视图，创建时应将名称指定为：db_name.view_name
* 查看视图：`DESCRIBE 视图名`，`SHOW TABLE STATUS LIKE '视图名'`，`SHOW CREATE VIEW 视图名`
* `SELECT * FROM information_schema.views`,MySQL中，information_schema数据库中的views表中存储了所有视图的定义，可以查看视图的详细信息。
* 修改视图：
```sql
CREATE [OR REPLACE] [ALGORITHM = {UNDEFINED | MERGE | TEMPTABLE}]
	VIEW view_name [(column_list)]
    	AS SELECT_statement
    	[WITH [CASCADED | LOCAL] CHECK OPTION]
```

```sql
ALTER [ALGORITHM = {UNDEFINED | MERGE | TEMPTABLE}]
	VIEW view_name [(column_list)]
    	AS SELECT_statement
    	[WITH [CASCADED | LOCAL] CHECK OPTION]
```

* 更新视图：`UPDATE 视图名 SET col_name = val `,`DELETE FROM 视图名 WHERE condition_expr`

* 当视图中包含如下内容时，视图的更新不能被执行：
> 1. 视图中不包含基表中被定义为非空的列
> 2. 在定义视图的SELECT语句后的字段列表中使用了数学表达式
> 3. 在定义视图的SELECT语句后的字段列表中使用了聚合函数
> 4. 在定义视图的SELECT语句中使用了DISTINCT，UNION，TOP，GROUP BY或HAVING子句
* 删除视图：
```SQL
DROP VIEW [IF EXISTS]
	view_name [,view_name] ...
    [RESTRICT | CASCADE]
```

* 触发器是个特殊的存储过程，不需要CALL语句来调用，只要当一个预定义的事件发生时，就会被自动调用，可以查询其他表。
* 创建触发器：
```SQL
CREATE TRIGGER trigger_name trigger_time trigger_event
ON tb1_name FOR EACH ROW trigger_stmt
```

trigger_time标识触发时机，可指定为before或after;trigger_event标识触发事件，包括INSERT，UPDATE，DELETE;tb1_name指明在哪张表上建立触发器;trigger_stmt是触发器程序体。可以为单条语句，也可以使用BEGIN和END作为开始和结束执行多条语句。

* 实例：

```SQL
mysql> CREATE TRIGGER ins_sum BEFORE INSERT ON account
    -> for each row SET @SUM=@SUM+NEW.amount;
Query OK, 0 rows affected (0.01 sec)

mysql> set @SUM=0
    -> ;
Query OK, 0 rows affected (0.00 sec)

mysql> INSERT INTO account values(1,1.00),(2,2.00);
Query OK, 2 rows affected (0.00 sec)
Records: 2  Duplicates: 0  Warnings: 0

mysql> select @SUM;
+------+
| @SUM |
+------+
| 3.00 |
+------+
1 row in set (0.00 sec)
```
使用OLD和NEW关键字，能够访问受触发程序影响的行中的列（OLD和NEW不区分大小写），可以使用OLD.col_name来引用更新前的某一行的列，也能使用NEW.col_name来引用更新后的行中的列。
* 查看触发器：`SHOW TRIGGERSV`，`SELECT * FROM INFORMATION_SCHEMA.TRIGGERS WHERE condition`
* 删除触发器：`DROP TRIGGER [schema_name.]trigger_name`
* 对于相同的表，相同的事件只能创建一个触发器
* 用CREATE USER创建新用户：

    ```SQL
    CREATE USER user_sprcification
        [, user_specification] ...

    user_specification:
        user@host
        [
            IDENTIFIED BY [PASSWORD] 'password'
          |	IDENTIFIED WITH auth_plugin [AS 'auth_string']
        ]
    ```
这样创建的账户没有任何权限，如果添加的账户已经存在则会返回一个错误。[PASSWORD]表示使用哈希值设置密码。host表示允许登陆的用户主机名称，默认为%，即对所有主机开放访问权限。如果用户不需要密码登陆，则可以省略`IDENTIFIED  BY`语句。IDENTIFIED WITH为用户指定一个身份验证插件，与IDENTIFIED BY 互斥。
* GRANT创建用户同时授权：
	```SQL
    GRANT privileges ON db.table
    TO user@host [IDENTIFIED BY 'password'] [, user [IDENTIFIED BY 'password']]
    [WITH GRANT OPTION];
  ```
* 直接操作MySQL用户表创建用户：
  ```SQL
  INSERT INTO mysql.user(Host,User,Password,[privilegelist])
  VALUES ('host','username',PASSWORD('password'),privilegevaluelist)
  ```
* 删除用户：`DROP USER user` ，DROP USER不能自动关闭任何打开的用户对话，如果用户有打开的回话，此时取消用户，命令不会生效，直到对话关闭后生效。
* 删除用户2： `DELETE FROM MySQL user WHERE host='hostname' and user = 'username'`
