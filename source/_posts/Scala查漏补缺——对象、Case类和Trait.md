---
title: Scala查漏补缺——对象、Case类和Trait
date: 2018-10-01 21:32:32
tags: Scala
---

#### 一、对象

​	对象(object)是一个类类型，只能有不超过1个实例，在面向对象设计中称为一个**单例**，对象不适用new创建的，只需要按名直接访问。对象会在首次访问时在当前JVM中自动实例化，也即在第一次访问它之前，对象并不会实例化。
​	Scala中的对象提供了类似Java中“静态”和“全局”的功能，不过将它们与可实例化的类解耦合。对象和类没有完全解耦合，对象可以扩展另一个类，从而在一个全局实例中使用它的字段和方法。

<!-- more-->

```scala
scala> object hello {println("i'm hello"); def hi="hi"}
defined object hello
//第一次访问对象时会调用第一句println
scala> println(hello.hi)
i'm hello
hi
//不会重新初始化
scala> println(hello.hi)
hi
```

最适合对象的方法是纯函数和外部I/O函数，纯函数会完全返回尤其输入计算得到的结果而没有任何副作用，I/O函数是处理外部数据的函数。这些函数都不适合作为类方法，因为它们与类的字段关系不大。

```scala
scala> object HtmlUtils {
     | def removeMarkup(input : String) = {
     | input.replaceAll("""</?\w[^>]*>""","")
     | .replaceAll("<.*>","")
     | }
     | }
defined object HtmlUtils

scala> val html = "<html><body><h1>Introduction</h1></body></html>"
html: String = <html><body><h1>Introduction</h1></body></html>

scala> val text = HtmlUtils.removeMarkup(html)
text: String = Introduction
```

* 伴生对象是你与类同名的一个对象，与类在同一个文件中定义。伴生对象和类可以认为是单个单元，它们可以相互访问私有和保护字段及方法

  ```scala
  scala> :paste
  // Entering paste mode (ctrl-D to finish)
  
  class Multiplier(val x: Int) { def product(y: Int) = x * y }
  //伴生对象的apply方法作为类的一个工厂方法
  object Multiplier {def apply(x: Int) = new Multiplier(x)}
  
  // Exiting paste mode, now interpreting.
  
  defined class Multiplier
  defined object Multiplier
  
  scala> val tripler = Multiplier(3)
  tripler: Multiplier = Multiplier@45753c22
  
  scala> val result = tripler.product(32)
  result: Int = 96
  ```

  ```scala
  scala> :paste
  // Entering paste mode (ctrl-D to finish)
  
  object DBConnection {
  private val db_url = "jdbc://localhost"
  private val db_user = "harold"
  private val db_pass = "12344"
  def apply() = new DBConnection
  }
  
  class DBConnection {
  private val props = Map(
  "url" -> DBConnection.db_url,
  "user" -> DBConnection.db_user,
  "pass" -> DBConnection.db_pass
  )
  println(s"Create new connection for " + props("url"))
  }
  
  // Exiting paste mode, now interpreting.
  
  defined object DBConnection
  defined class DBConnection
  
  scala> val conn = DBConnection()
  Create new connection for jdbc://localhost
  conn: DBConnection = DBConnection@2ab40d2d
  ```

#### 二、Case类

​	Case类是不可实例化的类，包含多个自动生成的方法，还包括一个自动生成的伴生对象，这个对象也有其自己的自动生成的方法。类中以及伴生对象中的所有这些方法都建立在类的参数表基础上，这些参数用来构成equals实现和toString等方法。

​	Case类对数据传输对象很适用，根据所生成的基于数据的方法，这些类主要用于存储数据。不过不适用于层次类结构，因为继承的字段不能用来构建工具方法。

生成的case类方法：

| 方法名   | 位置 | 描述                                                         |
| -------- | ---- | ------------------------------------------------------------ |
| apply    | 对象 | 一个工厂方法，用于实例化case类                               |
| copy     | 类   | 返回实例的一个副本，并完成所需的修改，参数是类的字段，默认值为当前字段值 |
| equals   | 类   |                                                              |
| hashCode | 类   |                                                              |
| toString | 类   |                                                              |
| unapply  | 对象 | 将实例抽取到一个字段元组，从而可以使用case类实例完成模式匹配 |

```scala
scala> case class Character(name: String, isThief: Boolean)
defined class Character
//伴生对象的工厂方法Character.apply
scala> val h = Character("Harold", true)
h: Character = Character(Harold,true)

scala> val r = h.copy(name = "Buuce")
r: Character = Character(Buuce,true)

scala> h == r
res0: Boolean = false

scala> h match {
     | case Character(x, true) => s"$x is a thief"
     | case Character(x, false) => s"$x is not a thief"
     | }
res1: String = Harold is a thief
```

#### 三、Trait

trait是一种支持多重继承的类。类、case类、对象以及trait都只能扩展不超过一个类，但是可以同时扩展多个trait，不过trait不能实例化，trait可以由类型参数，这使他有很好的重用性。

```scala
trait HtmlUtils {
     | def removeMarkup(input: String) = {
     | input
     | 		.replaceAll("""</?\w[^>]*>""", "")
     | 		.replaceAll("<.*>","")
     | }
     | }

scala> class Page(val s: String) extends HtmlUtils {
     | def asPlainText = removeMarkup(s)
     | }

scala> new Page("<html><body><h1>intrucuct</h1></body></html>").asPlainText
res9: String = intrucuct
```

如果扩展了一个类以及一个或多个trait，需要先扩展这个类，然后再使用with关键字增加trait，如果指定了父类，非父类必须放在所有父trait前面。

​	尽管Scala支持多重继承trait，但是实际上会创建各个trait的副本，形成类和trait组成的一个很高的单列层次体系，这里将所扩展的类和trait的水平列表变换为一个垂直的链，各个类分别扩展另一个类，这个过程称为**线性化**，多重继承的顺序是从右到左(从最低的子类到最高基类)

如果一个类定义为class  D extends A with B with C ,其中A是一个类，B和C是trait，将由编译器重新实现为class D extends C extends B extends A

```scala
scala> class A extends Base { override def toString = "A -> " + super.toString }
defined class A

scala> trait B extends Base { override def toString = "B -> " + super.toString }
defined trait B

scala> trait C extends Base { override def toString = "C -> " + super.toString }
defined trait C

scala> class D extends A with B with C {override def toString = "D -> " + super.toString }
defined class D

scala> new D()
res13: D = D -> C -> B -> A -> Base
```

线性化的好处：1. 提供了一个确定调用的可靠方法，因为所构建的层次结构可以确保在编译时就能确定方法，而不是运行时才知道。2. 可以编写trait来覆盖共享父类的行为

#### 四、自类型

自类型是一个trait注解，向一个类增加这个trait时，要求这个类必需有一个特定的类型或子类型。有自类型注解的trait不能增加到未扩展指定类型的类。这可以保证trait总是扩展该类型，尽管不是直接扩展。

自类型的一种流行用法是用trait为需要输入参数的类增加功能。trait扩展有输入的类并不容易，因为trait本身不能有输入参数，不过trait可以用一个自类型注解声明自己是这个父类的一个自类型，然后增加相应的功能。

有自类型的trait可以访问该类型的字段，就好像显式扩展了它一样。

```scala
scala> class A {def hi = "hi"}
defined class A
//trait B 有一个自类型，这要求这个trait只能增加到指定类型（A）的一个自类型
scala> trait B { self: A =>
     | override def toString = "B: " + hi
     | }
defined trait B
//没有扩展指定类，失败
scala> class C extends B
<console>:12: error: illegal inheritance;
 self-type C does not conform to B's selftype B with A
       class C extends B
                       ^
scala> class C extends A with B
defined class C
//实例化C时，会调用B.toString,再调用A.hi，实际上B trait在这里用作A的一个子类型
scala> new C()
res0: C = B: hi
```

