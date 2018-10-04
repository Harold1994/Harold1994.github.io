---
title: Scala查漏补缺——高级类型
date: 2018-10-02 11:58:05
tags: Scala
---

#### 一、元组和函数值类

​	有一组常规的类来支持元组和函数值的特殊语法，创建类似`（1，2，true)`的元组和`（n: String） => s"hello, $n"`的函数字面量这些实例的语法快捷方式很简短，而且很有表述性，但是它们的具体实现只是**普通的类**。也就是说元组和函数值这些高层构造是由安全的、类型参数化的类支持的。

​	元组实现的是`TupleX[Y]`case类的实例，X是一个1-22的数，表示其元数（输入参数的个数），类型参数Y可以是单个类型参数，对应Tuple1，或者两个类型参数，对应Tuple2，直到22个类型参数。Tuple1[A]只有一个字段`_1`,Tuple2[A,B]有字段`_1`和`_2`,以此类推。用小括号创建元组时，会用这个值实例化一个参数个数相同的元组类。换句话说，元组的表述性语法实际上就是case类的快捷方式。

<!-- more-->

TupleX[Y] case类分别用相同的数扩展一个ProductX trait,这些trait提供了一些操作，如productArity可以返回元组的元数，productElement提供了一种非类型安全的方式来访问元组的第n个元素。

```scala
scala> val x:(Int, Int) = Tuple2(10, 20)
x: (Int, Int) = (10,20)

scala> println("Does the arity = 2?" + (x.productArity == 2))
Does the arity = 2?true
```

元组case类是表述性语法的一个数据为中心的实现，函数值提供了一种逻辑为中心的实现。

函数值实现为FunctionX[Y] trait的实例，根据函数的元数总0-22编号。类型参数“Y”可以是单个类型参数，对应Function0(因为和返回值需要一个参数)，直到23个类型参数，对应Function22.不论调用一个现有函数还是一个新的函数字面量，函数的具体逻辑逻辑都在类的apply()方法中实现。也就是说，写一个函数字面量时，编译器会把它转换为扩展FunctionX的一个新类中的apply()方法体。

```scala
scala> val hello1 = (n:String) => s"Hello, $n"
hello1: String => String = $$Lambda$1037/140702728@178f268a

scala> val h1 = hello1("Function Literals")
h1: String = Hello, Function Literals

scala> val hello2 = new Function1[String, String] {
     | def apply(n: String) = s"Hello, $n"
     | }
hello2: String => String = <function1>

scala> val h2 = hello2("Function1 Instance")
h2: String = Hello, Function1 Instance
```

Function1 trait包含两个特殊方法andThen和compose，而其他任何FunctionX trait中没有这两个方法。可以使用这两个方法将两个或多个Function1实例结合为一个新的Function1实例，调用时会安顺序执行左右函数。唯一的限制是，第一个函数的返回值必须与第二个函数的输入类型一致。

* andThen:由两个函数值创建一个新的函数值，按照从左到右的顺序执行实例
* compose：与andThen功能相同，顺序相反

```scala
scala> val doubler = (i:Int) => i*2
doubler: Int => Int = $$Lambda$1266/264380404@5864798

scala> val plus3 = (i:Int) => i+3
plus3: Int => Int = $$Lambda$1279/1394617094@44ba9f25

scala> val prepend = (doubler compose plus3)(1)
prepend: Int = 8

scala> val append = (doubler andThen plus3)(1)
append: Int = 5
```

#### 二、隐含参数

如果调用一个函数但不指定所有参数，一种方法是为函数定义默认参数，另一种方法是使用隐含参数，调用者在自己的命名空间提供默认值。函数可以定义一个隐含参数，通常作为与其他非隐含参数相区别的单独参数组。调用者可以指示一个局部值为隐含值，作为隐含参数填入。调用函数时，如果没有为隐含参数指定值，就会使用局部隐含值，将它增加到函数调用中。使用implicit关键字标示一个值、变量或函数参数为隐含的。

```scala
scala> object Doubly {
     | def print(num: Double)(implicit fmt: String) = {
     | println(fmt format num)
     | }
     | }
defined object Doubly
//需要在命名空间中指定一个隐含值变量或者显式的增加函数
scala> Doubly.print(1.324)
<console>:13: error: could not find implicit value for parameter fmt: String
       Doubly.print(1.324)
                    ^
//显式增加函数
scala> Doubly.print(1.232)("%.1f")
1.2

scala> case class USD(amount: Double) {
    //指定隐含值
     | implicit val printFmt = "%.2f"
     | def print = Doublyb.print(amount)
     | }
defined class USD

scala> new USD(1.2322).print
1.23
```

#### 三、隐含类

隐含类是一种类类型，可以与另一个类自动转换。Scala编译器发现要在一个实例上访问未知的字段或方法时，就会使用隐含转换。他会检查当前命名空间的隐含转换：

1. 取这个实例作为一个参数
2. 实现缺少的字段或方法。

如果它发现一个匹配，就会向隐含类增加一个自动转换，从而支持在这个隐含类型上访问这个字段或方法，没有找到匹配就会得到一个编译错误。

```scala
scala> object IntUtils {
    //fishes方法在对象中定义，隐含的将整数转换为自身
     | implicit class Fishies(val x: Int) {
     | def fishes = "Fish" * x
     | }
     | }
defined object IntUtils
//使用之前，必须将这个隐含类增加到命名空间
scala> import IntUtils._
import IntUtils._

scala> println(3.fishes)
FishFishFish
```

定义和使用隐含类的限制：

* 隐含类必须在另一个对象、类、或者trait中定义。
* 它们必须取一个非隐含类参数
* 隐含类的类名不能语=与当前命名空间的另一个对象、类或trait冲突。因此不能使用case类作为隐含类，因为它有自动生成的伴生对象，这会违反这个规则。

#### 四、类型

类(class)是一个可以包含数据和方法的实体，有一个特定的定义。

类型(type)是一个类规范，与符合其需求的一个类或一组类匹配。类型可以是一个关系，指定“类A或其任何子孙类”，或“类B或其他任何父类”。类型还可以更为抽象，指定“定义这个方法的任何类”

##### 1.类型别名

类型别名(type alias)会为一个特定的现有类型或类创建一个新的命名类型。可以从类型别名创建一个新实例，用它取代类型参数的类，也可以直接在值、变量和函数返回类型中指定类型别名。

对象不能用来创建类型别名。

用type关键字定义新的类型别名

```scala
scala> object TypeFun {
     | type Whole = Int
     | val x: Whole = 5
     |
     | type UserInfo = Tuple2[Int, String]
     | val u: UserInfo = new UserInfo(123, "Harold")
     |
     | type T3[A,B,C] = Tuple3[A,B,C]
     | val things = new T3(1,'a',true)
     | }
defined object TypeFun

scala> val x = TypeFun.x
x: TypeFun.Whole = 5

scala> val u = TypeFun.u
u: TypeFun.UserInfo = (123,Harold)

scala> val things = TypeFun.things
things: (Int, Char, Boolean) = (1,a,true)
```

##### 2. 抽象类型

抽象类型是规范，可以解析为0，1个或多个类。它们的做法与类型别名类似，不过他们是抽象的名不能用来创建实例。抽象类型常用于类型参数，来指定一组可以接受的类型，还可以用来创建抽象类中的类型声明，即声明具体自类必须实现的类型。

```scala
scala> class User(val name: String)
defined class User

scala> trait Factory {type A; def create: A}
defined trait Factory

scala> trait UserFactory extends Factory {
     | type A = User
     | def create = new User("")
     | }
defined trait UserFactory

scala> trait Factory[A] { def create: A }
defined trait Factory

scala> trait UserFactory extends Factory[User] { def create = new User("") }
```

##### 3.定界类型

定界类型限制为只能是一个特定的类或者它的子类型或基类型。上界限制一个类型只能是该类型或它的某个子类型，上界定义了一个类型必须是什么；下界限制一个类型只能是该类型或它扩展的某个基类型。

**上界界定类型：`<identifier> <: <upper bound type>`**

**下界界定类型：`<identifier> >: <lower bound type>`**

```scala
scala> class BaseUser(val name: String)
defined class BaseUser

scala> class Admin(name: String, val level: String) extends BaseUser(name)
defined class Admin

scala> class Customer(name: String) extends BaseUser(name)
defined class Customer

scala> class PreferredCustomer(name: String) extends Customer(name)
defined class PreferredCustomer
//A限制为等于或扩展了BaseUser类型的类型
scala> def check[A <: BaseUser](u:A) { if (u.name.isEmpty) println("Fail!") }
check: [A <: BaseUser](u: A)Unit

scala> check(new Customer("Fred"))

scala> check(new Admin("", "strick"))
Fail!
```

上界操作符的不严格形式：视界操作符**<%**,上界要求是一个类型，视界还支持可以处理为该类型的任何类型，因此视界支持隐含转换。上界更限定，因为类型需求不包括隐含转换。

```scala
scala> def recruit[A >: Customer](u: Customer): A = u match {
     | case p:PreferredCustomer => new PreferredCustomer(u.name)
     | case c:Customer => new Customer(u.name)
     | }
recruit: [A >: Customer](u: Customer)A

scala> val customer = recruit(new Customer("Fred"))
customer: Customer = Customer@5b7f9eaa

scala> val customer = recruit(new PreferredCustomer("Fred"))
customer: Customer = PreferredCustomer@3167c0d

scala> val customer = recruit(new User("Fred"))
<console>:13: error: type mismatch;
 found   : User
 required: Customer
       val customer = recruit(new User("Fred"))
                              ^
```

##### 4. 类型变化

增加类型变化会减少类型参数的限制，类型变化指定一个类型参数如何调整以满足一个基类型或子类型。

类型参数默认是不变的，对于一个类型参数化的类，它的实例只与该类以及参数化类型兼容，这个实例不能存储在类型参数为基类型的值中。

尽管可以把一个Custom实例赋至类型为BaseUser的一个值，但是不能将Item[Customer]实例赋给类行为Item[BaseUser]的值。**类型参数是不变的，不能替换为兼容的类型**

> 在Java中也不允许这么做

```scala
scala> val a: BaseUser = new Customer("har")
a: BaseUser = Customer@3463851a

scala> case class Item[A](a: A) { def get: A = a}
defined class Item

scala> val c: Item[BaseUser] = new Item[Customer](new Customer)
<console>:15: error: not enough arguments for constructor Customer: (name: String)Customer.
Unspecified value parameter name.
       val c: Item[BaseUser] = new Item[Customer](new Customer)
                                                  ^
<console>:15: error: type mismatch;
 found   : Item[Customer]
 required: Item[BaseUser]
Note: Customer <: BaseUser, but class Item is invariant in type A.
You may wish to define A as +A instead. (SLS 4.5)
       val c: Item[BaseUser] = new Item[Customer](new Customer)
                               ^
```

为了修正这个问题，需要吧类型参数放到Item covariant中。**协变类型参数**可以自动在必要时间调整为其基类型。通过在类型参数前面加一个加号（+），可以标志一个类型参数为协变类型参数。

```scala
scala> case class Item[+A](a:A) { def get: A = a }
defined class Item

scala> val c:Item[BaseUser] = new Item[Customer](new Customer("harold"))
c: Item[BaseUser] = Item(Customer@20e1361d)

scala> val auto = c.get
auto: BaseUser = Customer@20e1361d
```

