---
title: Scala快速学习
date: 2018-04-25 16:36:47
tags: scala
---
* 变量声明：
  var：可变变量
  val：不可变变量（推荐使用）

<!-- more-->

```scala
scala> val x = 3
x: Int = 3

scala> x = 4
<console>:12: error: reassignment to val
       x = 4
         ^
```

```scala
scala> var b = 45
b: Int = 45

scala> b = 12
b: Int = 12
```
* scala值类型（没有包装类型）：
Byte
Char
Short
Int
Long
Float
Double

* 条件表达式
scala中所有类的基类是`Any`类型
Unit类型相当于java中的void类型，用`()`表示

```scala
scala> val x = 4
x: Int = 4

scala> val y = if(x > 1) 1 else "error"
y: Any = 1

scala> print(y)
1
scala> val z = if(x < 1) 1 else "error"
z: Any = error

scala> print(z)
error
scala> val w = if (x < 1) 1
w: AnyVal = ()

scala> print(w)
()
scala> val b = if (x > 1) 1 else if (x < 1) -1 else 0
b: Int = 1

scala> val c = if (x < 1) 1 else ()
c: AnyVal = ()
```

* for循环

  a to b:返回[a,b]的闭区间

  a until b:返回[a,b),不包含b

  ```scala
  scala> 1 to 10
  res4: scala.collection.immutable.Range.Inclusive = Range 1 to 10

  scala> 1 until 10
  res5: scala.collection.immutable.Range = Range 1 until 10
  ```

  ​

  ```scala
  scala> for (i <- 1 to 10){
       | print(i)
       | }
  12345678910
  scala> for (i <- 1 until 10){
       | print(i)
       | }
  123456789
  scala> for (i <- arr) {
       | print(i)
       | }
  javascalapythonc#

  ```

  *嵌套循环*：用`;`隔开

  ```scala
  scala> for (i <- 1 to 3; j <- 1 to 3) if(i != j) println(i*10 + j+"")
  12
  13
  21
  23
  31
  32
  ```

  也可以用：

  ```scala
  for() {
      for(){
          ...
      }
  }
  ```

  yield:将每次迭代生成的值封装到集合中

  ```scala
   val res = for(i <- 1 until 10) yield i 
  res: scala.collection.immutable.IndexedSeq[Int] = Vector(1, 2, 3, 4, 5, 6, 7, 8, 9)
  scala> print(res)
  Vector(1, 2, 3, 4, 5, 6, 7, 8, 9)
  ```

  ​

* 方法和函数的申明以及转换

  scala中的各种操作符（+ - * /等）都是作为方法存在的，从源码中可以看出来，以int为例：

  ```scala
  final abstract class Int() extends scala.AnyVal {
    def toByte : scala.Byte
    def toShort : scala.Short
    def toChar : scala.Char
    def toInt : scala.Int
    def toLong : scala.Long
    def toFloat : scala.Float
    def toDouble : scala.Double
    def unary_~ : scala.Int
    def unary_+ : scala.Int
    def unary_- : scala.Int
    def +(x : scala.Predef.String) : scala.Predef.String
    def <<(x : scala.Int) : scala.Int
    def <<(x : scala.Long) : scala.Int
    def >>>(x : scala.Int) : scala.Int
    def >>>(x : scala.Long) : scala.Int
    def >>(x : scala.Int) : scala.Int
    def >>(x : scala.Long) : scala.Int
    def ==(x : scala.Byte) : scala.Boolean
    def ==(x : scala.Short) : scala.Boolean
    def ==(x : scala.Char) : scala.Boolean...
  ```

  测试：

  ```scala
  scala> 1+2
  res0: Int = 3

  scala> 1.+(2)
  res1: Int = 3
  ```

  方法的声明：def 方法名 （参数1：参数类型 ...)：  返回类型  = 方法体 

  ```scala
  scala> def m1(x:Int, y:Int): Int = x + y
  m1: (x: Int, y: Int)Int
  scala> m1(3,4)
  res3: Int = 7
  ```

  scala中的方法和函数不是一个东西，定义的方式都不一样。

  函数定义方式：

  ```scala
  scala> var f1 = (x :Int, y:Int) => x + y
  f1: (Int, Int) => Int = $$Lambda$1074/1012975233@1b3a9ef4
  ```

  函数调用方式：

  ```scala
  scala> f1(1,2)
  res4: Int = 3
  ```

  函数一般可以作为方法的参数被传入：

  ```scala
  scala> def m2(f: (Int, Int) => Int) = f(3,4)
  m2: (f: (Int, Int) => Int)Int

  scala> val f1 = (x:Int, y:Int) => x+y
  f1: (Int, Int) => Int = $$Lambda$1082/1413679210@5740ad76

  scala> m2(f1)
  res5: Int = 7
  ```

  方法转为函数：空格+下划线

  ```scala
  scala> def m1(x: Int, y: Int):Int = x + y
  m1: (x: Int, y: Int)Int

  scala> val f1 = m1 _
  f1: (Int, Int) => Int = $$Lambda$1087/504561103@1d0fc0bc

  scala> m2(f1)
  res6: Int = 7

  scala> m2(m1)//内部以隐式方法将方法转为函数
  res7: Int = 7
  ```

* 数组

  *定长数组*：不需要引入第三方的定长数组包

  ```scala
  scala> val arr1 = new Array[Int](8)
  arr1: Array[Int] = Array(0, 0, 0, 0, 0, 0, 0, 0)

  scala> val arr1 = new Array[String](8)//静态数组，需要new，不指明成员
  arr1: Array[String] = Array(null, null, null, null, null, null, null, null)

  scala> print(arr1)//输出数组引用
  [Ljava.lang.String;@13835bdc
  scala> println(arr1.toBuffer)//转换为数组缓存输出
  ArrayBuffer(null, null, null, null, null, null, null, null)
   
  scala> val arr2 = Array("java", "scala", "python")//普通类，不需要new，写new会报错
  arr2: Array[String] = Array(java, scala, python)
   
  scala> print(arr2(0))
  java
  ```

  *变长数组*：需要引入包 

  ```scala
  scala> val arr3 = ArrayBuffer[Int]()//不导入包会报错
  <console>:11: error: not found: value ArrayBuffer
         val arr3 = ArrayBuffer[Int]()
                    ^
  scala> import scala.collection.mutable.Array//此处导入变长数组的包
  scala> val arr3 = ArrayBuffer[Int]()
  arr3: scala.collection.mutable.ArrayBuffer[Int] = ArrayBuffer()
  //向变长数组中添加元素，用+=
  scala> arr3 += 1
  res11: arr3.type = ArrayBuffer(1)

  scala> arr3 += (2,3,4)
  res12: arr3.type = ArrayBuffer(1, 2, 3, 4)
  //向变长数组添加数组，用++=
  scala> arr3 ++= Array(5,6)
  res13: arr3.type = ArrayBuffer(1, 2, 3, 4, 5, 6)

  scala> arr3 ++= ArrayBuffer(7,8)
  res14: arr3.type = ArrayBuffer(1, 2, 3, 4, 5, 6, 7, 8)
  //向变长数组中从某个位置起添加数据，用insert方法
  scala> arr3.insert(0,-1,0)//从第0个位置起添加-1,0,其他元素依次向后

  scala> arr3
  res16: scala.collection.mutable.ArrayBuffer[Int] = ArrayBuffer(-1, 0, 1, 2, 3, 4, 5, 6, 7, 8)
  scala> arr3.remove(0,2)//从变长数组中的某个位置起删除几个数据

  scala> arr3
  res18: scala.collection.mutable.ArrayBuffer[Int] = ArrayBuffer(1, 2, 3, 4, 5, 6, 7, 8)
  //注意：定长数组没有+= ++= insort remove等方法
  ```

  数组的遍历和常用操作：

  ```scala
  scala> val arr = Array(1,2,3,4,5,6,7,8,9)
  arr: Array[Int] = Array(1, 2, 3, 4, 5, 6, 7, 8, 9)

  scala> for(i <- arr) println(i)
  1
  2
  3
  4
  5
  6
  7
  8
  9

  scala> for(i <- 0 until arr.length) println(arr(i))
  1
  2
  3
  4
  5
  6
  7
  8
  9

  scala> for(i <- (0 until arr.length).reverse) println(arr(i))
  9
  8
  7
  6
  5
  4
  3
  2
  1

  //数组的常用操作：
  scala> arr.sum
  res22: Int = 45

  scala> arr.max
  res23: Int = 9

  scala> arr.sorted
  res24: Array[Int] = Array(1, 2, 3, 4, 5, 6, 7, 8, 9)
  ```

* 映射

  类似于Java中的Map类，存储键值对，默认值是不可改变的，想要改变需要导入mutable包

  定义方式：

  ```scala
  scala> val map1 = Map("scala" -> 1, "java" -> 2, "python" -> 3)
  map1: scala.collection.immutable.Map[String,Int] = Map(scala -> 1, java -> 2, python -> 3)
  //通过元组定义
  scala> val map2 = Map(("scala",1),("java",2))
  map2: scala.collection.immutable.Map[String,Int] = Map(scala -> 1, java -> 2)
  ```

  获取和修改Map值：

  ```scala
  scala> map1("scala")//获取值
  res28: Int = 1

  scala> map1("scala") = 6//默认不可变，修改会报错，需要导包
  <console>:14: error: value update is not a member of scala.collection.immutable.Map[String,Int]
         map1("scala") = 6
         ^
  scala> import scala.collection.mutable._
  import scala.collection.mutable._

  scala> val map1 = Map("scala" -> 1, "java" -> 2, "python" -> 3)
  map1: scala.collection.mutable.Map[String,Int] = Map(scala -> 1, java -> 2, python -> 3)

  scala> map1("scala") = 6
  //当查询一个不存在的键的时候会报错
  scala> map1("c#")
  java.util.NoSuchElementException: key not found: c#
    at scala.collection.MapLike.default(MapLike.scala:232)
    at scala.collection.MapLike.default$(MapLike.scala:231)
    at scala.collection.AbstractMap.default(Map.scala:59)
    at scala.collection.mutable.HashMap.apply(HashMap.scala:65)
    ... 28 elided
  //不存在时指定默认值
  scala> map1.getOrElse("c#", -1)
  res32: Int = -1
  ```

* 元组

  由小括号括起来的多个值，可以是多个类型，下标从1开始

  ```scala
  //声明元组
  scala> val t = ("scala", 100L, 3.14, ("apark",1))
  t: (String, Long, Double, (String, Int)) = (scala,100,3.14,(apark,1))
  //获取元素
  scala> t._1
  res33: String = scala

  scala> t._4
  res34: (String, Int) = (apark,1)

  scala> t._4._2
  res35: Int = 1

  //另一种取值方式：
  scala> val t, (a,b,c,d) = ("scala", 100L, 3.14, ("apark",1))
  t: (String, Long, Double, (String, Int)) = (scala,100,3.14,(apark,1))
  a: String = scala
  b: Long = 100
  c: Double = 3.14
  d: (String, Int) = (apark,1)

  scala> a
  res36: String = scala
  ```

  元组操作：

  ```scala
  scala> val arr = Array(("a",1),("b",2),("c",3))
  arr: Array[(String, Int)] = Array((a,1), (b,2), (c,3))
  //数组转换为不可变的Map
  scala> arr.toMap
  res37: scala.collection.immutable.Map[String,Int] = Map(a -> 1, b -> 2, c -> 3)

  //拉链操作：将两个数组组成一一对应组成键值对
  scala> val arr1 = Array("a","b","c")
  arr1: Array[String] = Array(a, b, c)

  scala> val arr2 = Array(1,2,3)
  arr2: Array[Int] = Array(1, 2, 3)

  scala> arr1 zip arr2
  res38: Array[(String, Int)] = Array((a,1), (b,2), (c,3))
  //位置靠前的为键
  scala> arr2 zip arr1
  res39: Array[(Int, String)] = Array((1,a), (2,b), (3,c))

  scala> arr2.zip(arr1)
  res40: Array[(Int, String)] = Array((1,a), (2,b), (3,c))
  //当两个数组长度不一样时，也能zip，此时会截取掉长出来的那一部分
  scala> val arr3 = Array(1,2,3,4,5,6)
  arr3: Array[Int] = Array(1, 2, 3, 4, 5, 6)

  scala> arr1.zip(arr3)
  res41: Array[(String, Int)] = Array((a,1), (b,2), (c,3))

  scala> arr3.zip(arr1)
  res42: Array[(Int, String)] = Array((1,a), (2,b), (3,c))

  scala> arr1.zip(arr1)
  res43: Array[(String, String)] = Array((a,a), (b,b), (c,c))
  ```

* 集合

  scala中的集合有三大类，分别是Seq(序列)，Set(集)，Map(映射)

  1.Seq

  分为可变和不可变的Seq，

  不可变Seq：

  ```scala
  scala> val list = List(1,2,3)
  list: List[Int] = List(1, 2, 3)
  //默认不可变，需要添加新的元素只能通过：：或+：创建新的List
  scala> val list2 = 0 :: list
  list2: List[Int] = List(0, 1, 2, 3)

  scala> val list3 = list.::(0)
  list3: List[Int] = List(0, 1, 2, 3)

  scala> val list4 = 0 +: list
  list4: List[Int] = List(0, 1, 2, 3)

  scala> val list5 = List(5,6,7)
  list5: List[Int] = List(5, 6, 7)
  //两个List中的元素合并到一起，用++
  scala> val list6 = list ++ list5
  list6: List[Int] = List(1, 2, 3, 5, 6, 7)
  //List中元素可以重复
  scala> val list7 = list ++ list
  list7: List[Int] = List(1, 2, 3, 1, 2, 3)
  //想要改变合并后List中的元素的位置，改变++左右顺序即可
  scala> val list8 = list5 ++ list
  list8: List[Int] = List(5, 6, 7, 1, 2, 3)

  ```

  可变Seq：

  ```scala
  scala> val list1 = ListBuffer(1,2,3)//创建
  list1: scala.collection.mutable.ListBuffer[Int] = ListBuffer(1, 2, 3)

  scala> list1 += 4//追加元素，用+=
  res44: list1.type = ListBuffer(1, 2, 3, 4)

  scala> list1.append(5)//也可以用append()

  scala> list1
  res46: scala.collection.mutable.ListBuffer[Int] = ListBuffer(1, 2, 3, 4, 5)
  //两个List合并并赋值给list1：+++
  scala> list1 ++= list2
  res48: list1.type = ListBuffer(1, 2, 3, 4, 5, 6, 7, 8)

  scala> val list1 = ListBuffer(3)
  list1: scala.collection.mutable.ListBuffer[Int] = ListBuffer(3)

  scala> val list2 = ListBuffer(4,5,6)
  list2: scala.collection.mutable.ListBuffer[Int] = ListBuffer(4, 5, 6)

  scala> list1 ++ list2
  res50: scala.collection.mutable.ListBuffer[Int] = ListBuffer(3, 4, 5, 6)
  //仅进行++操作并不会影响list1和2的元素，会创建一个新的ListBuffer
  scala> list1
  res51: scala.collection.mutable.ListBuffer[Int] = ListBuffer(3)
  //可变类型调用不可变方法不会改变原来的值，会创建一个新的值
  scala> list1 :+ 4
  res52: scala.collection.mutable.ListBuffer[Int] = ListBuffer(3, 4)
  ```

  2.Set，此处只展示可变的Set

  ```scala
  scala> val set1 = new HashSet[Int]()//此处[Int]为泛型
  set1: scala.collection.mutable.HashSet[Int] = Set()
  //set中追加元素，用+=或add方法
  scala> set1 += 1
  res54: set1.type = Set(1)

  scala> set1 += 2
  res55: set1.type = Set(1, 2)

  scala> set1.add(3)
  res56: Boolean = true

  scala> set1
  res57: scala.collection.mutable.HashSet[Int] = Set(1, 2, 3)
  //set与另一个set合并，用++=
  scala> set1 ++= Set(4,5,6)
  res58: set1.type = Set(1, 5, 2, 6, 3, 4)

  scala> set1 ++= Set(5,6,7)
  res59: set1.type = Set(1, 5, 2, 6, 3, 7, 4)
  //删除元素：-=、remove()方法
  scala> set1 -= 1
  res60: set1.type = Set(5, 2, 6, 3, 7, 4)

  scala> set1.remove(2)
  res61: Boolean = true

  scala> set1
  res62: scala.collection.mutable.HashSet[Int] = Set(5, 6, 3, 7, 4)
  ```

  3.Map

  仅分析可变类型

  ```scala
  scala> val map = new HashMap[String, Int]()//定义一个map
  map: scala.collection.mutable.HashMap[String,Int] = Map()

  scala> map("scala") = 1

  scala> map
  res64: scala.collection.mutable.HashMap[String,Int] = Map(scala -> 1)
  //添加元素 += put 
  scala> map += (("java",2))
  res65: map.type = Map(scala -> 1, java -> 2)

  scala> map += (("python",3),("c#",4))
  res66: map.type = Map(scala -> 1, java -> 2, c# -> 4, python -> 3)

  scala> map.put("c++",5)
  res67: Option[Int] = None

  scala> map
  res68: scala.collection.mutable.HashMap[String,Int] = Map(scala -> 1, c++ -> 5, java -> 2, c# -> 4, python -> 3)
  //删除元素 -= remove方法
  scala> map -= "java"
  res70: map.type = Map(scala -> 1, c++ -> 5, c# -> 4, python -> 3)

  scala> map.remove("c++")
  res71: Option[Int] = Some(5)

  scala> map
  res72: scala.collection.mutable.HashMap[String,Int] = Map(scala -> 1, c# -> 4, python -> 3)
  ```

  ​
