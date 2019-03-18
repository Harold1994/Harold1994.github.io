---
title: scala面向对象和模式匹配
date: 2018-04-25 22:08:26
tags: scala
---

**1.创建类、属性**

* scala声明类时不需要加public关键字，默认为public，一个类文件可以声明多个类，用object声明的与class同名的类为class的伴生类

* 属性不需要创建getter和setter，val默认只有get方法，因为他不可变;var有get 和 set 方法

* 用private修饰的属性，该属性属于私有变量，只有本类和伴生对象中才能访问

* 用private[this] 修饰的属性属于对象私有变量，只有本类可访问，伴生对象也无法访问

  <!-- more-->

```scala
class Person {//声明类
  val id: String = "100"
  var name: String = _
  private var age: Int = _
  private[this] val gender = "male"
}

object Person {//伴生类
  def main(args: Array[String]): Unit = {
    val p = new Person()
    //    println(p.id = "123")//val不可修改
    p.name = "ningning"
    p.age = 26
    println(p.name)
    println(p.age)
    println(p.gender)//无法访问
  }
}

object Test {
  def main(args: Array[String]): Unit = {
    val p = new Person()
    println(p.age) // 无法访问
    println(p.name)
  }
}
```

**2.构造器和辅助构造器**

* 主构造器：在类名后给一个参数列表，相当于构造器
* 主构造器中的属性变量如果没有val或var修饰，默认是val类型，只能在本类调用，创建出来的实例无法访问该属性,可以给定初始值，这样在创建对象传参的时候可以不给该值传参
* 辅助构造器：在class作用范围内定义：`def this(主构造器参数列表，其他参数列表)`，类似于java当中的不同的构造器拥有不同的参数列表，但是都要实现默认构造器
* 在辅助构造器第一行必须调用主构造器
* 返回方法：不用`retrun`,最后一句代码的值作为返回值

```scala
/***
  * 主构造器参数列表放到类名后面，和类名放在一起
  * @param name
  * @param age
  * @param faceValue
  */
class StructDemo(val name: String, var age:Int, faceValue: Int = 90) { /
  var gender: String = _//此处定义为var，方便在后面的构造器变值
  // /faceValue没有val或var修饰，只能在本类调用，创建出来的实例无法访问该属性,可以给定初始值，在创建对象的时候可以不指定faceValue的值
  def getFaceValue() :Int = {
//    faceValue = 100//此时值不可更改，默认是val类型
    faceValue
  }

  def this(name: String, age:Int, faceValue: Int, gender:String){//辅助构造器
        this(name, age, faceValue)//第一行必须调用主构造器
        this.gender = gender
  }
}



object StructDemo {
  def main(args: Array[String]): Unit = {
//    val s = new StructDemo("ningning", 23)
     val s = new StructDemo("ningning",26,98,"女")
    s.age = 29
    println(s.age)
    println(s.name)
    println(s.getFaceValue())
    println(s.gender)
  }
}
```



**3.单例对象**

* scala中没有static修饰符，没有静态方法或静态字段，但可以用object关键字加类名语法结构实现同样的功能

  > 1.工具类，存放常量和个工具方法
  >
  > 2.实现单例模式

```scala
object SingletonDemo {
  def main(args: Array[String]): Unit = {
    val factory = SessionFactory
    println(factory.getSessions)
    println(factory.getSessions.size)
    println(factory.getSessions(0))
    println(factory.removeSession)
  }
}

object SessionFactory {
  /**
    * 相当于java中的静态块
    */
  println("SessionFactory executed")
  var i = 5
  private val session = new ArrayBuffer[Session]()
  while (i > 0) {
    session += new Session
    i -= 1
  }

  def getSessions = session

  def removeSession: Unit = {
    val s = session(0)
    session.remove(0)
    println("session removed:" + s)
  }
}

class Session {

}
```

**4.伴生对象**

* 名字与类名相同，且用object修饰的对象叫伴生对象
* 类和其伴生对象可以相互访问私有的方法和属性
* 和单例对象的关系：单例对象不一定是伴生对象，但是伴生对象一定是单例对象
* 互相访问的作用：

```scala
class Dog {
  private var name = "erha"
  def printName() : Unit = {
    //访问伴生对象的私有属性
    println(Dog.CONSTANT + name)
  }
}

/*
伴生对象
 */
object Dog {
  private val CONSTANT = "BARK! BARK!"

  def main(args: Array[String]): Unit = {
    val p = new Dog
    //访问类中的私有字段
    println(p.name)
    p.name = "dahuang"
    p.printName()
  }
}
```

**5.apply和unapply方法**

* 一般被声明在伴生对象中
* apply方法一般称为注入方法，可以用来初始化对象
* apply方法的参数列表不需要和构造器参数列表统一
* unapply方法常称为提取方法，可以用来提取固定对象
* unapply方法会返回一个序列（Option）,内部产生一个Some对象来存放一些值
* apply和unapply方法会被隐式调用

```scala
class applyDemo(val name: String, var age: Int, var faceValue: Int) {

}

object applyDemo {
  def apply(name: String, age: Int, gender: Int, faceValue: Int): applyDemo =
    new applyDemo(name, age, faceValue)

  def unapply(arg: applyDemo): Option[(String, Int, Int)] = {
    if (arg == null) {
      None
    } else {
      Some(arg.name, arg.age, arg.faceValue)
    }
  }
}

/**
  * 调用方式
  */
object Test2 {
  def main(args: Array[String]): Unit = {
    val res = applyDemo("ningning", 23, 1, 86) //不用new，用apply方法创建了一个对象
    res match {
      //模式匹配，调用unapply方法
      case applyDemo("ningning", age, faceValue) => println(s"age: $age") //在字符串中输出值的方式
      case _ => println("no match")
    }

  }
}
```

**6.private关键字**

* 变量前加private，该变量为私有字段
* 变量前加private[this]，表示*对象私有字段*，只能在本类访问，伴生对象也不能访问
* 方法前加private，表示私有方法
* 类名前加private[包名]，表示该类只有包访问权限
* 构造器参数列表前加private是指伴生对象权限，只有伴生对象才能访问

```scala
//包访问权限
private[ch02] class PrivateDemo private(val gender: Int, val faceValue: Int) {
  //私有字段
  private val name = "jingjing"
  //对象私有字段
  private[this] var age = 24;

  //私有方法
  private def sayHello(): Unit = {
    println(name + "say hello")
  }
}

object PrivateDemo {
  def main(args: Array[String]): Unit = {
    val privateDemo = new PrivateDemo(1, 88)
    privateDemo.sayHello()
  }
}

object Test3 {
  def main(args: Array[String]): Unit = {
    val privateDemo = new PrivateDemo(0, 90)
    //    privateDemo.sayHello() 访问不到
    print(privateDemo.faceValue) //编译不能通过
  }
}
```

**7.特质、重写、抽象类和重写**

* 特质：类似java中的接口，用`trait 类名`声明
* 抽象类： `abstract 类名`声明，抽象类没有实现的方法，继承它的类一定要实现。
* 继承：extends关键字
* 实现接口：with关键字，与java中的implements类似，实现特质中没有实现的方法可以不用override
* 重现方法或字段：override

```scala
object ClassDEmo {
  def main(args: Array[String]): Unit = {
    val human = new Human
    println(human.name)
    println(human.fight)
    println(human.distance)
  }
}

trait Flyable {
  //声明一个没有值的字段
  val distance: Int = 1000

  //声明一个没有实现的方法
  def fight: String

  //声明一个实现的方法
  def fly: Unit = {
    print("I can fly")
  }
}

/**
  * 抽象类
  */
abstract class Animal {
  //声明一个没有值的字段
  val name: String

  //声明一个没有实现的方法
  def run(): String

  //声明一个实现的方法
  def climb: String = {
    "In can climb"
  }
}

class Human extends Animal with Flyable {
  override val name: String = "zhangsan"

  //重写抽象类没有实现的方法
  override def run(): String = "I can run"

  override val distance: Int = 900

  //实现特质中没有实现的方法
  def fight: String = "With rob"

  //实现特质中实现了的方法
  override def fly: Unit = println("override fly")
}
```

**8.模式匹配**

* 类似java中的switch...case,但是功能更强大
* case_的作用队标java中的default

```scala
/**
  * 匹配字符串
  */
object MatchStr {
  def main(args: Array[String]): Unit = {
    val arr = Array("java","scala","python","c++")
    val name = arr(Random.nextInt(arr.length))
    println(name)
    name match  {
      case "java" => print("java")
      case "scala" => print("scala")
      case "python" => print("python")
      case "c++" => print("c++")
      case _ => print("nothing match")
    }
  }
}
```

```scala
/**
  * 匹配类型
  */
object MatchType {
  def main(args: Array[String]): Unit = {
    val arr = Array("abcds", 100, 3.14, true)
    val element = arr(Random.nextInt(arr.length))
    print(element)
    element match {
      case str:String => println(s"a matches String:$str")
      case int: Int=> println(s"a matches String:$int")
      case bool:Boolean => println(s"a matches String:$bool")
      case matchTest:MatchTest => println(s"a matches MatchTest:$matchTest")
      case _: Any =>  println("not match")
    }
  }
}
```

```scala
/**
  * 样例类匹配
  */
object CaseClassDemo {
  def main(args: Array[String]): Unit = {
    val arr = Array(CheckTimeOutTask, SubmiTask("1000","task-01"), HeartBeat(3000))

    arr(Random.nextInt(arr.length))  match {
      case CheckTimeOutTask => println("Check")
      case SubmiTask(port,taskName) => println("submit")
      case HeartBeat(time) => println("heart")
    }
  }
}

case class HeartBeat(time: Long)
case class SubmiTask(id:String, taskName: String)
case object CheckTimeOutTask
```

```scala
/**
* 偏函数模式匹配
**/
object PartialFunctionDemo {
  def m1: PartialFunction[String, Int] = {
    //String是输入类型，Int是输出类型
    case "one" => {
      println("case 1")
      1
    }
    case "two" => {
      println("case2")
      2
    }
  }

  def m2(num: String): Int = num match {
    case "one" => 1
    case "two" => 2
    case _ => 0
  }

  def main(args: Array[String]): Unit = {
    println(m1("one"))
    println(m2("three"))
  }
}
```

