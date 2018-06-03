---
title: MySQL查漏补缺（一）
date: 2018-04-03 14:36:40
tags: [数据库, MySQL]
---
本篇博客记录本人在复习MySQL基本操作过程中碰到的之前忽略或者忘记的知识点
* 命令`HOW DATABASES`后出现的mysql数据库是必需的，它描述用户访问权限
* 创建数据库是在系统磁盘上划分一块区域用于数据的存储和管理
* `show engines`查看系统支持的引擎
* InnoDB是事务型数据库的首选引擎，支持事务安全表（ACID），支持行锁定和外键
> 特点：
> - InnoDB给MySQL提供了具有提交、回滚、和崩溃恢复能力的事务安全存储引擎
> - 为处理巨大数据量的最大性能设计，CPU效率高
> - 完全与MySQL服务器整合
> - 支持外键完整约束
>   <!-- more-->
* MyISAM拥有较高的插入、查询速度，但不支持事务
* MEMORY存储引擎将数据存储到内存中，为查询和引用其他表数据提供快速访问
* 主键是表中*一列或者多列的组合*，主键约束要求主键数据唯一，并且不能为空，主键可以和外键结合起来定义不同数据表之间的关系，可以加快查询的速度
* 主键类型：单字段主键、多字段联合主键
* 创建多字段主键：`PRIMARY KET [VAR1,VAR2,...]`
* 外键用来在两个表的数据之间建立链接，可以是一列或者多列，外键对应参照完整性
* 一个表的外键可以为空，可以不是本表的主键，若不为空，则每个外键的值必须等于另一个表中主键的某个值
* 定义外键后，不允许删除在另一个表中具有关联关系的行
* 创建外键语法:`[CONSTRAINT <外键名>] FOREIGN KEY 字段名1 [，字段名2，...] REFRENCES <主表名> 主键列1[， 主键列2...]`
* 一个表中不能有相同名称的外键
* 一个表只能有一个字段使用AUTO_INCREMENT约束，且该字段必须为主键的一部分
* 查看表的基本结构：
> DESC:查看基本结构
> SHOW CREATE TABLE:查看详细表结构，可以显示创建表的语句，加上‘\G‘参数显示的结果更直观
* 修改表名：`alter table 表名 rename to 新表名`
* 修改字段数据类型：`alter table 表名 modify 字段名 数据类型`
* 修改字段名：`alter table 表名 change 旧字段名 新字段名 新数据类型`
* 添加字段：`alter table 表名 add 新字段名 数据类型 约束类型 [FIRST|AFTER 已存在字段名]` FIRST和AFTER为可选参数，将新字段置于首位或者添加到以存在字段名之后， 默认添加到最后列
* 删除字段： `alter table 表名 drop 字段名 `
* 修改表名的排列顺序：`alter table 表名 modify 字段名 数据类型 FIRST | AFTER 已存在字段`
* 修改引擎： `alter table 表名 engin=引擎名`
* 删除外键约束：`alter table 表名 drop foreign kei 外键名`
* 数据表之间存在关联关系时，删除父表会报错
* 并不是每个表都需要主键
* 表示小数：浮点数：float double 定点数：decimal,都可以用（M，N）表示，M为精度，表示总共位数，N为标度，表示小数位数
* decimal以串存放，其可能的最大取直与double一样
* CHAR(M)定长字符串，检索到CHAR值时，尾部空格将删除
* VARCHAR(M)长度可变字符串，M表示最大列长度，0-65535，实际占用空间为字符串实际长度加一，在值保存和检索时尾部的空格任保留
* ENUM是字符串对象，值为表在创建时在列规定中枚举的一列直，语法`字段名 enum （'val1'，'val2',...'valn'）`
* ENUM类型的字段在取值时只能在指定枚举列表中取且一次只能取一个，成员尾部空格将自动被删除，ENUM值在内部用整数表示，每个枚举值均有一个索引值，列表索引值从一开始编号，NULL的索引为NULL，字段值区分大小写
![](/home/harold/Pictures/Selection_050.png)
![](/home/harold/Pictures/Selection_051.png)

* SET是一个字符串对象，可以有0-64个成员，SET类型的列可以从定义的列值中选择多个字符的联合，SET会删除重复的值
* BIN()函数将数字转换为二进制
* 二进制字符串类型：
> - BIT:位字段
> - BINARY(M):长度二进制字符串
>  - VARBINARY(M): 变长
>  - BLOB(M):小BLOB，BLOB是二进制大对象，存储可变数量的数据
* TEXT和BLOB比较：

<table>
<tr><td>TEXT</td>
<td>BLOB</td></tr>
<tr><td>存储非二进制字符串(字符字符串)</td>
<td>存储二进制字符串(字节字符串)</td></tr>
<tr><td>有一个字符集,根据字符集对值比较和排序</td>
<td>没有字符集，排序和比较基于列值字节的数值</td></tr>
<tr><td>只能存纯文本文件</td>
<td>主要存图片，音频等</td></tr>
<table>
* `=`操作符：
 若有一个或两个参数为NULL，比较结果为NULL
 若两个参数都是字符串，则按字符串进行比较
 都为整数，按整数比较
 若一个字符串一个整数比较，自动将字符串转换为整数

* 安全等于运算符`<=>`,可用来判断null值
* `LEAST（val1,val2,...valn）`运算符返回参数中的最小值，如果参数中有NULL，返回NULL
* `GREATEST(val1,val2,...)`返回最大值，有NULL时，返回NULL
* `exp REGEXP 匹配条件`，用来匹配字符串，匹配返回1,否则返回0，若expr或匹配条件中有一个NULL，结果为NULL，通配符比LIKE多，不区分大小写
* 函数CEIL(x),CEILING(x),FLOOR(x)获取整数值，前两个向上取整，floor()向下取整
* 函数RAND(x)返回0-1间的浮点数，x作为种子
* ROUND(x)函数四舍五入,ROUND(x,y)返回最接近x的数，结果保留小数点后y位，若y为负值，则将小数点保留x只到小数点左边y位
* TRUNCATE(x,y)返回被舍去小数点后y位的数字x，若y为0，则结果不带有小数部分，若y为负数，则截取(归零)x小数点做起y位开始后所有低位的值。
* CHAR_LENGTH(str)返回字符串str所包含的字符个数，一个多字节字符算作一个单字符。
* LENGTH(str）返回字符串的字节长度
* CONCAT(s1,s2,...)连接字符串，如果有一个参数为NULL，则结果为NULL，若自变量中存在二进制字符串，则结果为一个二进制字符串
* CONCAT(X,S1,S2,...)以x作为分隔符连接字符串
* `INSERT(S1,X，LEN,s2)`替换字符串函数，从s1的x位置用s2取代len个字符，若x超过字符串长度，则返回原始字符串，有一个参数为NULL则返回NULL
* 大小写转换LOWER(STR),LCASE(STR),UPPER(STR),UCASE(STR)
* 获取指定长度字符串`LEFT(s,n)`,`RIGHT(s,n)`
* `TRIM(s1 FROM s)`从s两端删除所有子字符s1
* 匹配子串str1在str中开始位置的函数:`LOCATE(str1,str),POSITION(str1 IN str),INSTR(str,str1)`
* `ELT(N,str1,str2,...)`返回指定位置N的字符串,若N小于1或大于参数的个数，则返回NULL
* `IF(expr,v1,v2)`若expr为真，返回v1,否则返回v2
* `IFNULL(v1,v2)`若v1不为NULL，则返回v1.否则返回v2
* `CASE expr WHEN v1 THEN r1 [WHEN v2 THEN r2] [ELSE rn] END`如果expr的值等于某个vn，则返回对应rn
* 查看系统信息`select version()` `select connection_ID()`
* `SELECT USER(),CURRENT_USER(),SYSTEM_USER();`获取用户名函数
* `LAST_INSERT_ID()`获取最后一格自动生成的ID值
* `FORMAT(x,n)`将数字格式化，四舍五入保留小数点后n位。以字符串形式返回，若n=0,则返回函数不包含小数部分
* `CONV(n,FROM_BASE,TO_BASE)`对N进制转换
* ip地址与数字相互转换：`INET_ATON(expr)`返回一个代表地址数值的整数，`INET_NTOA(EXPR)`将数值转换为网络地址
* 查询语句中AND和OR一起使用时，AND优先级高于OR
* DISTINCT关键字去重
* ORDER BY关键字默认按ASC(升序)方式排序，DESC只对其前面的列进行降序排序
* [GROUP BY 字段] [HAVING <条件表达式>]分组查询
* HAVING和WHERE比较：两个都是用来过滤数据的，HAVING在数据分组之后进行过滤来选择分组，WHERE在分组之前来选择记录。WHERE排除的记录不再包括在分组中。

