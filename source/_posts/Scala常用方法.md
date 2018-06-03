---
title: Scala常用方法
date: 2018-04-25 20:48:43
tags: scala
---

* lazy关键字

  lazy一般在变量前边作为修饰字符，表示该变量是一个**惰性变量**（想想spark里面的转换操作），会实现**延迟加载**，惰性变量只能是*不可变变量*， 只有在调用惰性变量时才会实例化该变量。

<!-- more-->

  未使用lazy：

  ```scala
  object ScalaLazyDemo {
    def init(): Unit = {
      println("call init()")
    }
    def main(args: Array[String]): Unit = {
      val property = init()//未使用lazy关键字
      println("after init")
      println(property)
    }
  }

  output：
  call init()
  after init
  ()
  ```

  使用lazy：

  ```scala
  object ScalaLazyDemo2 {
    def init(): Unit = {
      println("call init()")
    }
    def main(args: Array[String]): Unit = {
      lazy val property = init()//使用lazy关键字
      println("after init")//先执行这一句
      println(property)//到这里才执行init（）
    }
  }
  output：
  after init
  call init()
  ()
  ```

* 函数式编程连续

  ```scala
  object Exercise {
    def main(args: Array[String]): Unit = {
      //创建一个list
      val list0 = List(5, 9, 5, 152, 85, 41)
      //list中的每个元素乘2
      val list1 = list0.map(_ * 2)
      //将list中的偶数取出来生成一个新集合
      val list2 = list0.filter(_ % 2 == 0)
      //将list排序
      val list3 = list0.sorted
      //反转list
      val listt4 = list0.reverse
      //将list中的元素4个一组，类型为Iterator[List[Int]]
      val it = list0.grouped(4)
      //将iterator转为list
      val list5 = it.toList
      //输出为：List(List(5, 9, 5, 152), List(85, 41))
      //将多个list压扁
      val list6 = list5.flatten

      val lines = List("hello dd sdjjs sj wehjh", "hello ddd ws", "sawdxgyua hello jjs")
      //先按照空格切分，再压平
      //    val words = lines.map(_.split(" "))
      //    val flatten_words = words.flatten 比较费事，可以用flatMap
      val word = lines.flatMap(_.split(" "))

      /*
     tips：系统中有多个任务同时存在可称之为“并发”，系统内有多个任务同时执行可称之为“并行”；
           并发是并行的子集。比如在单核CPU系统上，只可能存在并发而不可能存在并行。
      */
      //并行计算求和
      val arr = Array(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
      //val res = arr.sum
      //和线程有关，每个线程计算一部分，（1，+2+3+4）+ （5+6+7+8）+（9+10）//
      val res = arr.par.sum //par方法实现并行计算

      //按照特定顺序进行聚合 res2 和 res3
      //    （（（（1 + 2）+ 3） + 4） + 5）   ...
      val res2 = arr.reduce(_ + _)
      val res3 = arr.reduceLeft(_ + _)
      val res4 = arr.par.reduce(_ + _) //没有顺序

      //折叠：有初始值（无特定顺序）
      val res5 = arr.par.fold(10)(_ + _) //有初始值时，在每个线程中都会加一次初始值，但是调用有顺序的fold就只计算一次初始值，比如foldLeft

      //折叠：有初始值（有特定顺序）
      val res6 = arr.foldLeft(10)(_ + _) //有初始值时，在每个线程中都会加一次初始值

      //聚合
      val list7 = List(List(1, 2, 3), List(3, 4, 5), List(2), List(0))
      //val res7 = list7.flatten.reduce(_+_)
      val res8 = list7.aggregate(0)(_ + _.sum, _ + _)

      val l1 = List(1, 2, 3, 4)
      val l2 = List(2, 3, 4, 5)

      //并集
      val res9 = l1 union l2 //不会去重

      //交集
      val res10 = l1 intersect l2

      //差集
      val res11 = l1 diff l2
    }
  }

  ```

  ​
