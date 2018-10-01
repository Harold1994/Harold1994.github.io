---
title: Scala查漏补缺——表达式、条件式和函数
date: 2018-09-29 10:22:58
tags: scala
---

#### 一、字面量、值、变量和类型

* 变量var可以重新赋值，但是不可以改变它指定的类型，所以不能将一个变量赋值为不兼容的类型

* 操作符命名不可包涵中括号和点号，但是可以是一个或多个除了反引号外的任意字符，所有这些字符包围在一对反引号中，用反引号包围的名字可以是Scala中的保留字，如true, while,=和var

  ```scala
  scala> val a.b = 25
  <console>:11: error: not found: value a
         val a.b = 25
             ^
  
  scala> val `a.b` = 25
  a.b: Int = 25
  ```

* Scala中没有基本类型的概念，它的核心数值类型类型是同名的核心JVM类型的包装器，包装JVM类型可以确保Scala和Java互操作，且Scala可以使用所有Java库

  <!-- more-->

* 与Java不同，Scala中的相等操作符（==）会检查真正的相等性，而不是对象引用相等性。

* 可以用三重引号创建多行String，多行字符串是字面量，其中的反斜杠不代表特殊字符的开头

  ```scala
  scala> val greeting = """ she suggerfvnfjkljnfkls
       | njknjkl,nmkl\fcsdf\\sdfsdf(\n)
       | dfnhjskf"""
  greeting: String =
  " she suggerfvnfjkljnfkls
  njknjkl,nmkl\fcsdf\\sdfsdf(\n)
  dfnhjskf"
  ```

* 在一个字符串中插入一个值除了可以使用“+”连接字符串和值，更方便的是使用**字符串内插**，在第一个双引号钱加"s"前缀，使用"$"指示外部数据的引用

  ```scala
  scala> val approx = 355/113f
  approx: Float = 3.141593
  
  scala> println(s"the value is $approx .")
  the value is 3.141593 .
  ```

* 如果引用中有非字字符（如算式）或者引用与周围文本无法区分，需要使用可选的大括号

  ```scala
  scala> val item = "apple"
  item: String = apple
  
  scala> s"How do you like these ${item}s?"
  res1: String = How do you like these apples?
  
  scala> s"Fisj n banana ,${"prpprer "*3} salt"
  res2: String = Fisj n banana ,prpprer prpprer prpprer  salt
  ```

* 字符串内插的替代格式是printf记法，可以控制数据格式化，使用这种记法需要把前缀改为“f”

  ```scala
  scala> val item = "apple"
  item: String = apple
  
  scala> f"I wrote a new $item%.3s today"
  res3: String = I wrote a new app today
  
  scala> f"Enjoy this $item ${355/113}%.5f times today"
  res4: String = Enjoy this apple 3.00000 times today
  ```

* Scala类型

  ![](http://p5s7d12ls.bkt.clouddn.com/18-9-29/98683302.jpg)

* 布尔比较符&和&&

  &&和||都很懒，若第一个组以得出结论就不会计算第二个参数，操作符&则会在返回结果之前对两个参数都进行检查

* scala不支持其他类型到Boolean的自动转换，非null字符串不会转换为true，0不会转换为false

* Unit字面量是一对小括号，表示没有任何值

#### 二、表达式和条件式

* 可以使用大括号{}结合多个表达式创建一个表达式块，表达式有自己的作用域，可以包含表达式块中的局部值和变量。块中的最后一个表达式作为整个表达式块的返回值

* Scala的匹配表达式类似于“switch”语句，但与它不同的是，只能有0个或一个模式可以匹配，而不会从一个模式贯穿到下一个模式，也不需要break来避免这种贯穿行为。

* 利用模式替换式，通过多个模式重用相同的case块，可以避免重复的代码

  ```scala
  scala> val day = "MON"
  day: String = MON
  scala> val kind = day match {
       | case "MON"|"TUE"|"WED"|"THU"|"FRI" => "weekday"
       | case "SAT"|"SUN" => "weekend"
       | }
  kind: String = weekday
  ```

* 匹配表达式中有两种通配模式：值绑定和通配符（“即_”）

#### 三、函数

* 过程是没有返回值的函数，以一个语句结尾的函数也是一个过程。

* 为了避免栈溢出问题，Scala编译器可以用**尾递归**（tail-recursion）优化一些递归函数,是的递归递归调用不使用额外的栈空间。对于利用尾递归优化的函数，递归函数不会使用新的栈空间，而是使用当前函数的栈空间，只有最后一个语句是递归调用的函数才能由Scala编译器完成尾递归优化。如果函数本身的结果不作为直接返回值，而是有其他用途，这个函数就不能优化。可以利用**函数注解**@annotation.tailrec来标识一个函数将完成尾递归优化。

  ```scala
  //最后一个语句不是递归语句
  scala> @annotation.tailrec
       | def power(x:Int,n:Int) : Long = {
       | if(n>=1) x*power(x,n-1)
       | else 1}
  <console>:15: error: could not optimize @tailrec annotated method power: it contains a recursive call not in tail position
         if(n>=1) x*power(x,n-1)
                   ^
  //最后一句是乘法而不是递归语句
  scala> @annotation.tailrec
       | def power(x:Int,n:Int) : Long = {
       | if(n<1) 1
       | else x*power(x,n-1)
       | }
  <console>:16: error: could not optimize @tailrec annotated method power: it contains a recursive call not in tail position
         else x*power(x,n-1)
               ^
  
  scala> @annotation.tailrec
       | def power(x:Int,n:Int,t:Int=1):Int = {
       | if(n<1) t
       | else power(x,n-1,x*t)
       | }
  ```

* 嵌套函数：

  ```scala
  scala> def max(a:Int,b:Int,c:Int)={
       | def max(x:Int,y:Int)=if (x>y) x else y
       | max(a, max(b,c))
       | }
  ```

  Scala函数按照函数名以及参数类型来区分，不过即使max函数名和参数类型一样也不会冲突，因为局部函数优先于外部函数。

* Vararg参数：Vararg可以调用匹配者的0个或多个实参，Scala中vararg参数后不能跟非vararg，因为无法区分。要标志一个参数匹配一个或多个输入实参，在函数定义中需要在该参数后增加一个星号*

  ```scala
  scala> def sum(items:Int*) : Int = {
       | var total=0
       | for (i<-items) total+=i
       | total}
  sum: (items: Int*)Int
  
  scala> sum(1,3,5,7,9)
  res35: Int = 25
  
  scala> sum()
  ```

* 参数组：Scala中可以将参数分解为参数组，每个参数组分别用小括号分隔。

  ```scala
  scala> def max(x:Int)(y:Int)=if(x>y) x else y
  max: (x: Int)(y: Int)Int
  
  scala> var larger = max(20)(30)
  larger: Int = 30
  ```

* 类型参数：之前讨论的函数参数都是“值参数”，即数据的类型参数，Scala中还可以传递类型参数，类似于Java中的范型，类型参数指示了值参数或返回值使用的类型，通过使用类型参数，函数的参数或返回值类型不再固定，而是可以由函数调用者设置。

  > 类型参数定义方式：
  >
  > def <functionname> [type-name] (parameter-name>:<type_name>):<type_name>={...}

  ```scala
  scala> def identify[A](a:A):A=a
  identify: [A](a: A)A
  
  scala> val s:String = identify[String]("hello")
  s: String = hello
  
  scala> val s:Double = identify[Double](2.121)
  s: Double = 2.121
  //这里利用了Scala中的类型推断
  scala> val s:String = identity("hello")
  s: String = hello
  ```

#### 四、首类函数

* 函数式编程的一个关键是函数应当是首类的，“首类”表示函数不仅能得到声明和调用，还可以作为一个数据类型用在语言的任何地方。

* 函数与其他数据类型一样，也有类型，函数类型是其输入类型和返回值类型的简单组合，由一个箭头从输入类型指向输出类型，由于函数签名包括函数名，输入和输出，所以函数类型就是输入和输出。

  语法：函数类型 ([<type>,...]) => <type>

  ```scala
  scala> def double(x:Int):Int=x*2
  double: (x: Int)Int
  
  scala> double(6)
  res0: Int = 12
  //myDouble就是一个值，只不过与其他值不同，可以调用myDouble，必须显示的制定类型，以区分它是一个函数值而不是函数调用
  scala> val myDouble: (Int) => Int = double
  myDouble: Int => Int = $$Lambda$1069/911201454@245253d8
  
  scala> myDouble(6)
  res1: Int = 12
  //将一个函数值赋给一个新值
  scala> val myDoubleCopy = myDouble
  myDoubleCopy: Int => Int = $$Lambda$1069/911201454@245253d8
  
  scala> myDoubleCopy(8)
  res2: Int = 16
  //用通配符为函数赋值
  scala> val myDouble = double _
  myDouble: Int => Int = $$Lambda$1178/2046578329@6e7fa4b0
  
  scala> val amo画nt = myDouble(20)
  amount: Int = 40
  ```

* 占位符语法：占位符语法是函数字面量的一种缩写形式，将命名参数替换为通配符（_），在以下两种情况可以使用：

  * 函数的显示类型在字面量之外指定

  * 参数最多只使用一次

    ```scala
    scala> def combination(x:Int, y:Int, f:(Int,Int)=>Int) = f(x,y)
    combination: (x: Int, y: Int, f: (Int, Int) => Int)Int
    //多个占位符会按位置替换输入，占位符数必须与输入参数个数一样
    scala> combination(12,3,_*_)
    res11: Int = 36
    //利用类型参数实现更灵活的用法
    scala> def tripleOp[A,B](a:A,b:A,c:A,f:(A,A,A)=>B)=f(a,b,c)
    tripleOp: [A, B](a: A, b: A, c: A, f: (A, A, A) => B)B
    
    scala> tripleOp[Int,Int](1,2,3,_*_+_)
    res12: Int = 5
    
    scala> tripleOp[Int,Boolean](1,2,3,_>_+_)
    res13: Boolean = false
    ```


* 部分应用函数：如果想重用一个函数，而且希望保留一些参数不变，就可以部分应用这个函数。

  ```scala
  scala> def factoryOf(x:Int,y:Int) = y%x == 0
  factoryOf: (x: Int, y: Int)Boolean
  //multipleOf3是一个部分应用函数，包含部分参数，通配符需要显式类型，因为它要用于生成一个函数值
  scala> val multipleOf3 = factoryOf(3,_: Int)
  multipleOf3: Int => Boolean = $$Lambda$1303/107969734@2bcbc231
  
  scala> multipleOf3(18)
  res14: Boolean = true
  ```

* 实现部分应用函数的另一种方式是**函数柯里化**：使用有多个参数表的函数，应用一个参数表的参数，另一个参数表不应用

  ```scala
  //此时函数类型变为Int => Int => Boolean
  scala> def factoryOf(x:Int)(y:Int) = y % x == 0
  factoryOf: (x: Int)(y: Int)Boolean
  
  scala> val isEvev = factoryOf(2) _
  isEvev: Int => Boolean = $$Lambda$1314/978663398@7a48b916
  
  scala> val z = isEvev(16)
  z: Boolean = true
  ```

  有多个参数表的函数可以认为是多个函数的一个链，但个参数表则认为是一个单独的函数调用。