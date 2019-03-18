---
title: scala——Actor、柯里化与隐式转换
date: 2018-04-28 21:09:45
tags: scala
---

* 高阶函数：
  接受一个或多个函数作为输入或输出一个函数的函数称为高阶函数
  <!-- more-->

  ```scala
  scala> val func : Int => Int = x => x*x
  func: Int => Int = $$Lambda$1046/1620041759@2687725a
  
  scala> func(4)
  res0: Int = 16
  scala> val arr = Array(1,2,3,4,5,6)
  arr: Array[Int] = Array(1, 2, 3, 4, 5, 6)
  
  scala> arr.map(x => func(x))//匿名函数
  res1: Array[Int] = Array(1, 4, 9, 16, 25, 36)
  
  scala> def m1(x :Int) = x*x
  m1: (x: Int)Int
  
  scala> arr.map(x => m1(x))//方法转换为函数
  res2: Array[Int] = Array(1, 4, 9, 16, 25, 36)
  
  scala> arr.map(m1)
  res3: Array[Int] = Array(1, 4, 9, 16, 25, 36)
  
  scala> arr.map(func)
  res4: Array[Int] = Array(1, 4, 9, 16, 25, 36)
  ```

* 柯里化：

  将接受多个参数的函数转变为接受一个参数的函数的过程

  柯里化方法会在上下文中找最的隐式的值，作为柯里化方法的值，如果有多个隐式的值会报错

  ```scala
  scala> arr.map(func) 
  res4: Array[Int] = Array(1, 4, 9, 16, 25, 36)
  
  scala> def currying(x: Int)(y: Int) = x * y
  currying: (x: Int)(y: Int)Int
  
  scala> currying(3)(4)
  res5: Int = 12
  
  scala> val curry = currying(3) _//柯里化方法第一种用法
  curry: Int => Int = $$Lambda$1187/1535571147@468646ea
  
  scala> curry(4)
  res6: Int = 12
  
  scala> def m1(x: Int, y: Int) = x*y
  m1: (x: Int, y: Int)Int
  
  scala> m1(5,10)
  res8: Int = 50
  
  scala> def m2(x:Int)(implicit y :Int = 5) = x * y//柯里化的第2种用法，指定默认值，调用是不指定参数就使用默认值
  m2: (x: Int)(implicit y: Int)Int
  
  scala> m2(4)
  res9: Int = 20
  
  scala> m2(4)(6)
  res11: Int = 24
  
  scala> implicit val x = 100//设置一个隐式的量
  x: Int = 100
  
  scala> m2(4)
  res12: Int = 400
  
  scala> implicit val y = 200//设置第二个隐式的量
  y: Int = 200
  
  scala> m2(5)//此时会发生错误，因为有两个隐式量
  <console>:15: error: ambiguous implicit values:
   both value x of type => Int
   and value y of type => Int
   match expected type Int
         m2(5)
           ^
  
  scala> val arr = Array(("scala",1),("scala",2),("scala",3))
  arr: Array[(String, Int)] = Array((scala,1), (scala,2), (scala,3))
  
  scala> arr.foldLeft(0)(_ + _._2)
  res14: Int = 6
  
  scala> def curry(x:Int) = (y:Int) => x * y
  curry: (x: Int)Int => Int
  
  scala> val func = curry(2)//柯里化方法第3中用法
  func: Int => Int = $$Lambda$1058/191351920@45c9b3
  
  scala> func(3)
  res0: Int = 6
  ```
  ```scala
  object Content {//这个静态块只有放在Currying上面才能用a或b替代默认值，因为scala是顺序编译执行的
    implicit val a = "java"
    implicit val b = "python"
  }
  
  object CurryingDemo {
    def m1(str: String)(implicit name : String = "scala") = {
      println(str + name)
    }
    def main(args: Array[String]): Unit = {
      m1("Hi~")
    }
  }
  ```

* 隐式转换与隐式参数

  1. 作用：能够丰富现有类库的功能，对类的方法进行增强
  2. 隐式转换函数：以implicit关键字声明带有单个参数的函数
  3. 隐式转换用到了装饰模式和门面模式

  ```scala
  object ImplicitContext {
    implicit object OrderingGirl extends Ordering[Girl]{
    override def compare(x: Girl, y: Girl): Int = if (x.faveValue > y.faveValue) 1 else  -1}
  }
  class Girl(val name: String, var faveValue: Int){
    override def toString: String = s"name:$name"
  }
  
  class Goddess[T: Ordering](val v1 :T, val v2: T) {
    def choose()(implicit ord :Ordering[T]) =if (ord.gt(v1,v2)) v1 else v2
  }
  
  object Goddess {
    def main(args: Array[String]): Unit = {
      import ImplicitContext.OrderingGirl
      val g1 = new Girl("lili",90)
      val g2 = new Girl("huahua",70)
      val goddess = new Goddess(g1, g2)
      val res = goddess.choose()
      println(res)
    }
  }
  ```

* 泛型

  [B <: A]  UpperBound 上界： B类型的上界是A类型，即B类型的父类是A类型

  [B >: A] LowerBound 下界： B类型的下界是A类型，即B类型的子类是A类型

  [B <% A]  ViewBound 表示B类型要转换成A类型，需要一个隐式转换函数

  [B : A]  ContextBound 需要一个隐式转换的值

[-A, +B]

​	[-A]  逆变，作为参数类型。如果A是T的子类，那C[T]是C[A]的子类

​	[+B ]协变，作为返回类型。如果B是T的子类，那么C[B]是C[T]的子类

```scala
/*
上界 UpperBound
 */
class UpperBoundDemo[T <: Comparable[T]] {
  def select(first: T, second: T) = {
    if (first.compareTo(second) > 0)
      first
    else
      second
  }
}

object UpperBoundDemo {
  def main(args: Array[String]): Unit = {
    val u = new UpperBoundDemo[MissRight]
    val m1 = new MissRight("LILI", 95)
    val m2 = new MissRight("erniu", 999)

    println(u.select(m1, m2))
  }
}

class MissRight(val name: String, val faceValue: Int) extends Comparable[MissRight] {
  override def compareTo(o: MissRight): Int = {
    this.faceValue - o.faceValue
  }

  override def toString: String = s"name:$name"
}
```

