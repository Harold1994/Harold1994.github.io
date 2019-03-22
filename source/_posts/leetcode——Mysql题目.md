---
title: leetcode——Mysql题目（一）
date: 2018-07-06 09:22:10
tags: [Mysql, 数据库, Hive]
---

**1.寻找第n大**

Write a SQL query to get the *n*th highest salary from the `Employee` table.

```
+----+--------+
| Id | Salary |
+----+--------+
| 1  | 100    |
| 2  | 200    |
| 3  | 300    |
+----+--------+
```

```mysql
//方法一：171ms
CREATE FUNCTION getNthHighestSalary(N INT) RETURNS INT
BEGIN
DECLARE M INT;
SET M=N-1;
  RETURN (
      # 这里的distinct是关键
      select distinct Salary from Employee Order by(Salary) desc limit M,1
  );
END
```

<!-- more--> 	

需要回忆一下mysql的执行顺序：MySQL的语句一共分为11步，如下图所标注的那样，最先执行的总是FROM操作，最后执行的是LIMIT操作。其中每一个操作都会产生一张虚拟的表，这个虚拟的表作为一个处理的输入，只是这些虚拟的表对用户来说是透明的，但是只有最后一个虚拟的表才会被作为结果返回。如果没有在语句中指定某一个子句，那么将会跳过相应的步骤。

![082230505368061.png](https://i.loli.net/2019/03/11/5c866e947b5be.png)

1. **FORM**: 对FROM的左边的表和右边的表计算笛卡尔积。产生虚表VT1
2. **ON**: 对虚表VT1进行ON筛选，只有那些符合<join-condition>的行才会被记录在虚表VT2中。
3. **JOIN**： 如果指定了OUTER JOIN（比如left join、 right join），那么保留表中未匹配的行就会作为外部行添加到虚拟表VT2中，产生虚拟表VT3, 如果from子句中包含两个以上的表的话，那么就会对上一个join连接产生的结果VT3和下一个表重复执行步骤1~3这三个步骤，一直到处理完所有的表为止。
4. **WHERE**： 对虚拟表VT3进行WHERE条件过滤。只有符合<where-condition>的记录才会被插入到虚拟表VT4中。
5. **GROUP BY**: 根据group by子句中的列，对VT4中的记录进行分组操作，产生VT5.
6. **CUBE | ROLLUP**: 对表VT5进行cube或者rollup操作，产生表VT6.
7. **HAVING**： 对虚拟表VT6应用having过滤，只有符合<having-condition>的记录才会被 插入到虚拟表VT7中。
8. **SELECT**： 执行select操作，选择指定的列，插入到虚拟表VT8中。
9. **DISTINCT**： 对VT8中的记录进行去重。产生虚拟表VT9.
10. **ORDER BY**: 将虚拟表VT9中的记录按照<order_by_list>进行排序操作，产生虚拟表VT10、
11. **LIMIT**：取出指定行的记录，产生虚拟表VT11, 并将结果返回。

```mysql
//方法二：480ms
CREATE FUNCTION getNthHighestSalary(N INT) RETURNS INT
BEGIN
  RETURN (
     SELECT IFNULL(
     (
         SELECT e1.Salary 
         from Employee e1
         join Employee e2
         on e2.Salary >= e1.Salary
         group by e1.Salary
         HAVING count(distinct e2.Salary) = N
     ),null)      
  );
END
```

 **2.排名**

Write a SQL query to rank scores. If there is a tie between two scores, both should have the same ranking. Note that after a tie, the next ranking number should be the next consecutive integer value. In other words, there should be no "holes" between ranks.

```sql
+----+-------+
| Id | Score |
+----+-------+
| 1  | 3.50  |
| 2  | 3.65  |
| 3  | 4.00  |
| 4  | 3.85  |
| 5  | 4.00  |
| 6  | 3.65  |
+----+-------+
```

For example, given the above `Scores` table, your query should generate the following report (order by highest score):

```sql
+-------+------+
| Score | Rank |
+-------+------+
| 4.00  | 1    |
| 4.00  | 1    |
| 3.85  | 2    |
| 3.65  | 3    |
| 3.65  | 3    |
| 3.50  | 4    |
+-------+------+
```

方法一：634ms

```mysql
select s1.Score, (select count(distinct s2.Score) from Scores s2 where s2.Score>=s1.Score) as Rank from Scores s1 order by s1.Score desc;
```

方法二：257ms

```mysql
select s.Score, CAST(temp.Rank as SIGNED) as Rank from Scores s left join 
(
	select t.Score, @rank := @rank + 1 as Rank from 
	(
		select Score
		from Scores
		group by Score 
		order by Score desc
	) t, (select @rank := 0) r
) temp on s.Score = temp.Score
order by s.Score desc
```

方法三：193ms

```mysql
select s.Score, CAST(temp.Rank as signed) Rank from
Scores s left join (
    Select t.Score,@row := @row +1 Rank from (
    select distinct Score
    from Scores order by Score desc
    ) t,(select @row :=0) r
) temp on s.Score = temp.Score order by s.Score desc
```

在MySQl中可以利用SQL语句将值存储在用户自定义变量中，然后再利用另一条SQL语句来查询用户自定义变量。这样一来，可以在不同的SQL间传递值。

用户自定义变量的声明方法形如：@var_name，其中变量名称由字母、数字、“.”、“_”和“$”组成。当然，在以字符串或者标识符引用时也可以包含其他字符（例如：@’my-var’，@”my-var”，或者@`my-var`）。

用户自定义变量是会话级别的变量。其变量的作用域仅限于声明其的客户端链接。当这个客户端断开时，其所有的会话变量将会被释放。

用户自定义变量是不区分大小写的。

使用SET语句来声明用户自定义变量：

```sql
SET @var_name = expr[, @var_name = expr] ...
```

在使用SET设置变量时，可以使用“=”或者“:=”操作符进行赋值。

当然，除了SET语句还有其他赋值的方式。比如下面这个例子，但是赋值操作符只能使用“:=”。因为“=”操作符将会被认为是比较操作符。

```
mysql> SET @t1=1, @t2=2, @t3:=4;
mysql> SELECT @t1, @t2, @t3, @t4 := @t1+@t2+@t3;
+------+------+------+--------------------+
| @t1  | @t2  | @t3  | @t4 := @t1+@t2+@t3 |
+------+------+------+--------------------+
|    1 |    2 |    4 |                  7 |
+------+------+------+--------------------+
```

用户变量的类型仅限于：整形、浮点型、二进制与非二进制串和NULL。在赋值浮点数时，系统不会保留精度。其他类型的值将会被转成相应的上述类型。比如：一个包含时间或者空间数据类型（temporal or spatial data type）的值将会转换成一个二进制串。

**方法四：**在Mysql中没有`ROW_NUMBER() over (PARTITION BY xx ORDER BY ** DESC)`这样的函数，但是在Hive或者Oracle中是存在的简单的说row_number()从1开始，为每一条分组记录返回一个数字，这里的ROW_NUMBER() OVER (ORDER BY xlh DESC) 是先把xlh列降序，再为降序以后的每条xlh记录返回一个序号。 

row_number() 是没有重复值的排序(即使两条记录相等也是不重复的)，可以利用它来实现分页 
dense_rank() 是连续排序，两个第二名仍然跟着第三名 
rank() 是跳跃排序，两个第二名下来就是第四名

使用方法 fun() over( partition by field,field… order by flag.. asc/desc)