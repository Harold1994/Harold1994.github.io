---
title: leetcode——Mysql题目(二)
date: 2018-07-14 15:32:14
tags: [Mysql, 数据库， Hive]
---

#### 一、部门工资最高的员工

`Employee` 表包含所有员工信息，每个员工有其对应的 Id, salary 和 department Id。

```
+----+-------+--------+--------------+
| Id | Name  | Salary | DepartmentId |
+----+-------+--------+--------------+
| 1  | Joe   | 70000  | 1            |
| 2  | Henry | 80000  | 2            |
| 3  | Sam   | 60000  | 2            |
| 4  | Max   | 90000  | 1            |
+----+-------+--------+--------------+
```

 <!-- more-->

`Department` 表包含公司所有部门的信息。

```
+----+----------+
| Id | Name     |
+----+----------+
| 1  | IT       |
| 2  | Sales    |
+----+----------+
```

编写一个 SQL 查询，找出每个部门工资最高的员工。例如，根据上述给定的表格，Max 在 IT 部门有最高工资，Henry 在 Sales 部门有最高工资。

```
+------------+----------+--------+
| Department | Employee | Salary |
+------------+----------+--------+
| IT         | Max      | 90000  |
| Sales      | Henry    | 80000  |
+------------+----------+--------+
```

* 解法一：自己写的，15个测试用例通过13个，结合max和groupby

  ```mysql
  SELECT B.Name as Department,A.name as Employee,A.Salary FROM
      Department B LEFT JOIN (
      SELECT C.* from 
      (SELECT DepartmentId,MAX(Salary) AS maxs from 
      Employee Group By(DepartmentId)
      ) D LEFT JOIN Employee C
      ON C.Salary=D.maxs AND C.DepartmentId=D.DepartmentId
      ) A
      ON A.DepartmentId=B.Id
      ORDER BY B.Id desc;
  ```

  看了一下错误的详细信息，原因在于null值的处理上，题目的意思是当工资表为空但是部门表不为空时，依然要显示每个部门的信息，将除部门名外的其他字段设为null.![](http://p5s7d12ls.bkt.clouddn.com/18-7-14/81554601.jpg)

  要解决这个问题并不困难，只需要将第二行的left join改成join即可

* 解法二：用join和in

  ```mysql
  SELECT
      Department.name AS 'Department',
      Employee.name AS 'Employee',
      Salary
  FROM
      Employee
          JOIN
      Department ON Employee.DepartmentId = Department.Id
  WHERE
      (Employee.DepartmentId , Salary) IN
      (   SELECT
              DepartmentId, MAX(Salary)
          FROM
              Employee
          GROUP BY DepartmentId
      )
  ;
  ```

#### 二、部门工资前三高的员工

`Employee` 表包含所有员工信息，每个员工有其对应的 Id, salary 和 department Id 。

```
+----+-------+--------+--------------+
| Id | Name  | Salary | DepartmentId |
+----+-------+--------+--------------+
| 1  | Joe   | 70000  | 1            |
| 2  | Henry | 80000  | 2            |
| 3  | Sam   | 60000  | 2            |
| 4  | Max   | 90000  | 1            |
| 5  | Janet | 69000  | 1            |
| 6  | Randy | 85000  | 1            |
+----+-------+--------+--------------+
```

`Department` 表包含公司所有部门的信息。

```
+----+----------+
| Id | Name     |
+----+----------+
| 1  | IT       |
| 2  | Sales    |
+----+----------+
```

编写一个 SQL 查询，找出每个部门工资前三高的员工。例如，根据上述给定的表格，查询结果应返回：

```
+------------+----------+--------+
| Department | Employee | Salary |
+------------+----------+--------+
| IT         | Max      | 90000  |
| IT         | Randy    | 85000  |
| IT         | Joe      | 70000  |
| Sales      | Henry    | 80000  |
| Sales      | Sam      | 60000  |
+------------+----------+--------+
```

* 解法一

  ```mysql
   select A.Name as Department,B.Name as Employee,B.Salary from
      Department A join (
      select Name,DepartmentId,Salary,dense_rank() OVER(PARTITION BY DepartmentId ORDER BY Salary DESC) rk from Employee) B
      ON A.Id=B.DepartmentId where B.rk<=3
  ```

  rank()是跳跃排序，有两个第二名时接下来就是第四名（同样是在各个分组内）．   　　

  dense_rank()l是连续排序，有两个第二名时仍然跟着第三名。相比之下row_number是没有重复值的 ．  

* 解法二

  ```mysql
  SELECT
      d.Name AS 'Department', e1.Name AS 'Employee', e1.Salary
  FROM
      Employee e1
          JOIN
      Department d ON e1.DepartmentId = d.Id
  WHERE
      3 > (SELECT
              COUNT(DISTINCT e2.Salary)
          FROM
              Employee e2
          WHERE
              e2.Salary > e1.Salary
                  AND e1.DepartmentId = e2.DepartmentId
          )
  ;
  ```

  