---
title:  Scala查漏补缺——集合
date: 2018-09-30 16:54:41
tags: scala
---

* Cons操作符：Scala支持使用cons(construct)操作构建列表，使用Nil作为基础，使用右结合的cons操作符::绑定元素，就可以构建一个链表。

  ```scala
  scala> val numbers = 1 :: 2 :: 3 :: Nil
  numbers: List[Int] = List(1, 2, 3)
  
  scala> val first = Nil.::(1)
  first: List[Int] = List(1)
  
  scala> first.tail==Nil
  res19: Boolean = true
  ```

  ::只是List的一个方法，它的参数取一个值，这个值会成为新的表头，表尾为调用::的列表。

  <!-- more-->

* 可变集合类型没有默认值，因此要创建一个空集合，必须要用类型参数指定集合的类型：

  ```scala
  scala> val nums = collection.mutable.Buffer()
  nums: scala.collection.mutable.Buffer[Nothing] = ArrayBuffer()
  
  scala> nums += 'a'
  <console>:16: error: type mismatch;
   found   : Char('a')
   required: Nothing
         nums += 'a'
                 ^
  
  scala> nums += 1
  <console>:16: error: type mismatch;
   found   : Int(1)
   required: Nothing
         nums += 1
  //指定类型参数后              ^
  scala> val nums = collection.mutable.Buffer[Int]()
  nums: scala.collection.mutable.Buffer[Int] = ArrayBuffer()
  
  scala> nums += 1
  res72: nums.type = ArrayBuffer(1)
  ```

* 集合构建器Builder是Buffer的简化形式，仅限于生成指定的集合类型，而且只支持追加操作。调用构建器的result方法可以将它转换为最终的Set。

  ```scala
  scala> val l = List.newBuilder[Int]
  l: scala.collection.mutable.Builder[Int,List[Int]] = ListBuffer()
  
  scala> l += 1
  res2: l.type = ListBuffer(1)
  
  scala> l ++= List(1,2,3,4)
  res3: l.type = ListBuffer(1, 1, 2, 3, 4)
  
  scala> l.result
  res4: List[Int] = List(1, 1, 2, 3, 4)
  ```

* 序列集合层次体系

  ![](http://p5s7d12ls.bkt.clouddn.com/18-9-30/99927396.jpg)

  * Vector类型以一个Array提供后备存储，可以根据索引直接访问Vector中的项。而要访问一个List中的第n个元素，则需要从头到尾访问n-1步
  * Stream类型集合在访问元素时完成构建

* Stream类型是一个lazy集合，有一个或多个其实元素和一个递归函数生成。第一次访问元素时才会把这个元素增加到集合中。流生成的元素会缓存，以备以后获取。流可能是无界的，理论上是无限的集合。流可以以Stream.Empty结束，这对应List.Nil

* Stream是递归数据结构，包括一个表头（当前元素），和一个表尾（集合的其余部分）。可以用Streams.cons用表头和表尾构建一个新的流。

  ```scala
  //流包含一个递归函数调用，可以用来无限的生成新元素
  scala> def inc(i:Int):Stream[Int] = Stream.cons(i, inc(i+1))
  inc: (i: Int)Stream[Int]
  
  scala> val s = inc(1)
  s: Stream[Int] = Stream(1, ?)
  
  scala> val l = s.take(5).toList
  l: List[Int] = List(1, 2, 3, 4, 5)
  
  scala> s
  res15: Stream[Int] = Stream(1, 2, 3, 4, 5, ?)
  //另一种构建流的操作符 #:: 右结合
  scala> def incr(head:Int): Stream[Int] = head #:: inc(head+1)
  incr: (head: Int)Stream[Int]
  
  scala> inc(10).take(10).toList
  res16: List[Int] = List(10, 11, 12, 13, 14, 15, 16, 17, 18, 19)
  
  scala> inc(10).take(10).toList
  res16: List[Int] = List(10, 11, 12, 13, 14, 15, 16, 17, 18, 19)
  //创建一个有界的流
  scala> def to(head: Char, end:Char) : Stream[Char] = (head > end) match {
       | case true => Stream.empty
       | case false => head #:: to((head + 1).toChar, end)
       | }
  to: (head: Char, end: Char)Stream[Char]
  
  scala> val hexChar = to('A','F').take(20).toList
  hexChar: List[Char] = List(A, B, C, D, E, F)
  ```

* 一元集合支持类似Iterable中的变换操作，但是包含的元素不能多于1个。

* Option类型是一个扩展了Iterable的一元集合，它表示一个值的存在或不存在。Option集合可以指示一个值可能不存在。Option类型本身没有实现，而是依赖两个子类型提供具体的实现：Some和None，Some是一个类型参数化的单元素集合，None是一个空集合，None类型没有类型参数，因为它永远不包含任何内容。可以直接使用Some和None，或者Option()来检测null值。

  ```scala
  scala> var x : String = "indeed"
  x: String = indeed
  
  scala> var a = Option(x)
  a: Option[String] = Some(indeed)
  
  scala> x = null
  x: String = null
  
  scala> var b = Option(x)
  b: Option[String] = None
  //可以用isDefined和isEmpty分别检查一个给定的是Some还是None
  scala> println(s"a is defined? ${a.isDefined}")
  a is defined? true
  
  scala> println(s"b is not defined? ${b.isEmpty}")
  b is not defined? true
  
  scala> def divide(amt: Double, divisor: Double): Option[Double] = {
       | if (divisor == 0) None
       | else Option(amt / divisor)
       | }
  divide: (amt: Double, divisor: Double)Option[Double]
  
  scala> val legit = divide(5,2)
  legit: Option[Double] = Some(2.5)
  
  scala> val legit = divide(5,0)
  legit: Option[Double] = None
  ```

  如果一个函数会返回包装在Option集合中的值，说明他可能不能应用于输入数据，因此无法返回一个合法的结果。Option可以提供一种类型安全的方法来处理函数结果。

* headOption可以替代head操作符，避免空列表时抛出一个错误。

* find操作结合了filter和headOption，将返回与第一个谓词函数匹配的似一个元素。

  ```scala
  scala> val words = List("risible","scavenger","gist")
  words: List[String] = List(risible, scavenger, gist)
  
  scala> val uppercase = words find (w => w == w.toUpperCase)
  uppercase: Option[String] = None
  
  scala> val lowercase = words find (w => w == w.toLowerCase)
  lowercase: Option[String] = Some(risible)
  ```

* Option.get()是一种不安全的抽取操作，如果对一个实际上是Some实例的Option调用此方法，可以成功的接收到其包含的值，如果对None调用这个方法，将返回没有这样的元素的错误，因此要避免使用get()

* 安全的抽取操作

  | 操作名     | 示例                                                         | 描述                                                         |
  | ---------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
  | Fold       | nextOption.fold(-1)(x x)                                     | 对于Some，从给定函数返回值                                   |
  | getOrElse  | nextOption getOrElse 5<br />nextOption getOrElse {println("error") -1} | 为Some返回值，为None返回传名参数的结果                       |
  | orElse     | nextOption orElse nextOption                                 | 并不真正返回值，而是试图为None填入一个值，如果非空。则返回这个Option，否则从给定的传名参数返回一个Option |
  | 匹配表达式 | nextOption match { case Some(x) => x; case None => -1}       |                                                              |

* Try和Future是两个有特定用途的一元集合，Try对应成功的值，Future对应最终的值

* Scala中要捕获一个异常，需要把可能有问题的代码包围在util.Try集合中，util.Try没有具体实现，而是有两个已实现的子类型Success和Failer， Success类型包含表达式相应的返回值， Failer类型包含所抛出的Exception

  ```scala
  scala> def loopAndFail(end:Int, failAt : Int) : Int = {
       | for (i <- 1 to end) {
       | println(s"$i)")
       | if(i==failAt) throw new Exception("Too many iterations")
       | }
       | end
       | }
  loopAndFail: (end: Int, failAt: Int)Int
  
  scala> val t1 = util.Try(loopAndFail(2,3))
  1)
  2)
  t1: scala.util.Try[Int] = Success(2)
  
  scala> val t1 = util.Try(loopAndFail(4,3))
  1)
  2)
  3)
  t1: scala.util.Try[Int] = Failure(java.lang.Exception: Too many iterations)
  ```

> Scala也支持try{} catch(){}块，但是util.Try()更安全，更有表述性

* 使用Try的错误处理方法

  | 方法名     | 示例                                            | 描述                                                         |
  | ---------- | ----------------------------------------------- | ------------------------------------------------------------ |
  | flatMap    | nextError flatMap {_ => nextError}              | 对于Succcess，调用一个同样返回util.Try的函数，从而将当前返回值映射到一个新的内嵌返回值 |
  | foreach    | nextError foreach (x => println("success" + x)) | 一旦Success，则执行给定的函数，或对于Failure，则不执行       |
  | getOrElse  | nextError getOrElse 0                           | 返回Success中的内嵌值，或者对于Failure则返回传名参数的值     |
  | orElse     | nextError orElse nextError                      | 与FlatMap相反                                                |
  | toOption   | nextError.toOption                              |                                                              |
  | Map        |                                                 | 对于Success，将内嵌值映射到一个新值                          |
  | 匹配表达式 |                                                 |                                                              |
  | 什么都不做 | nextError                                       |                                                              |

* 一元集合concurrent.Future会发起一个后台任务，future表示一个可能的值，并提供了安全操作来串联其他操作或者抽取值。future的值不是立即可用的，因为创建future时后台任务可能仍在工作。
* Scala代码默认在主线程中运行，不过可以支持在并发线程中运行后台任务，调用future并提供一个函数会在一个单独的线程中执行该函数，而当前线程继续执行。