---
title: shell程序设计（二）
date: 2018-07-09 20:27:54
tags: Linux
---

**1.条件**

一个shell脚本能够对任何可以从命令行上调用的命令的退出码进行测试，包括自己写的脚本。

**test或[命令**

`[`或``test`是布尔判断命令，在使用`[`时，使用符号`]`来结尾。

以下示例检查文件是否存在，用于实现这一操作的命令是`test -f <filename>`

<!-- more--> 

可以使用如下所示代码：

```shell
if test -f fred.c
then 
...
fi
```

或：

```shell
if [ if fred.c ]
then
...
fi
```

test命令的退出码(表明条件是否被满足)决定是否需要执行后面的代码。

> 注意，必须在`[`符合和被检查的条件之间留出空格
>
> 如果想把then和if放到同一行，必须用一个分号把test语句和then分隔开：
>
> if [ -f fred.c ]; then
>
> ...
>
> fi

test命令可以使用的条件可以归为3类：字符串比较、算数比较和与文件有关的条件测试。

| 字符串比较         | 结果                         |
| ------------------ | ---------------------------- |
| string1 = string2  | 如果两个字符串相同结果为真   |
| string1 != string2 | 两个字符串不相同为真         |
| -n string          | 如果字符串不为空则为真       |
| -z string          | 如果字符串为null，则结果为真 |

| 算数比较      | 结果                       |
| ------------- | -------------------------- |
| exp1 -eq exp2 | 如果两个表达式相等则为真   |
| exp1 -ne exp2 | 如果两个表达式不相等则为真 |
| exp1 -gt exp2 | 如果exp1大于exp2则为真     |
| exp1 -ge exp2 | 如果exp1大于等于exp2则为真 |
| exp1 -lt exp2 | 如果exp1小于exp2则为真     |
| exp1 -le exp2 | 如果exp1小于等于exp2则为真 |
| ！exp1        | 表达式为假则为真           |

| 文件条件测试 | 结果                                    |
| ------------ | --------------------------------------- |
| -d file      | 如果文件是一个目录则为真                |
| -e file      | 如果文件存在则为真                      |
| -f file      | 如果文件是一个普通文件则为真            |
| -g file      | 如果文件的set-group-id位被设置则为真    |
| -r file      | 文件可读则为真                          |
| -s file      | 如果文件大小不为0则为真                 |
| -u file      | 如果文件的set-user-id位被设置则结果为真 |
| -w file      | 文件可写则为真                          |
| -x file      | 如果文件可执行则为真                    |

> set-user-id(set-uid)授予程序其拥有者的访问权限而不是其他使用者的访问权限，set-group-id(set-gid)授予其所在组的访问权限，是通过chmod命令的s和g设置的。

```shell
#! /bin/sh
if [ -f /bin/bash ]
then
    echo "file /bin/bash exists"
fi

if [ -d /bin/bash ]
then
    echo "/bin/bash"
else
    echo "/bin/bash is not a directory"
fi
测试结果：
./iftest.sh
file /bin/bash exists
/bin/bash is not a directory
```

**2.控制结构**

* if 语句

  语法：

  ```shell
  if condition
  then
  	statements
  else
  	statements
  fi
  ```

  实验：

  ```shell
  #!/bin/sh
  echo "Is it morning? please answer yes or no"
  read timeofday
  
  if [ $timeofday = "yes" ]; then
      echo "good morning"
  else 
      echo "good afternoon"
  fi
  exit 0
  ```

* elif语句

  ```shell
  #!/bin/sh
  echo "Is it morning? please answer yes or no"
  read timeofday
  
  if [ $timeofday = "yes" ]; then
      echo "good morning"
  elif [ $timeofday = "no" ]; then
      echo "good afternoon"
  else
      echo "Sorry, $timeofday not recognized. Enter yes or no"
      exit 1
  fi
  exit 0
  ```

* 一个与变量有关的问题

  上面的程序存在一个隐含的问题，当输入为空（直接按enter）时，会出现`[: =: unexpected operator`的错误，因为在if语句中对变量timeofday进行测试的时候，它包含了一个空字符串`if [ = "yes" ]`，而这不是一个合法的条件，为了避免这个问题，需要给变量加上引号，如`if [ "$timeofday" = "yes" ]`,这样空变量提供的就是一个合法的测试了。

* for语句

  语法：

  ```shell
  for variable in values
  do
  	statements
  done
  ```

  实验：

  ```shell
  #!/bin/sh
  
  for foo in bar fud 43
  do
      echo $foo
  done
  exit 0
  ```

  实验：通过通配符扩展的for循环

  在字符串的值中使用一个通配符，并由shell在程序执行时填写所有的值

  ```shell
  #!/bin/sh
  for file in $(ls f*.sh); do
  # 打印文件
      lpr $file
  done
  exit 0
  ```

* while语句

  语法：

  ```shell
  while condition do
  	statement
  done
  ```

  实验：读取密码

  ```shell
  #!/bin/sh
  echo "Enter password"
  read trythis
  
  while [ "$trythis" != "secret" ]; do
      echo "Sorry, try again"
      read trythis
  done
  exit 0
  ```

* until语句

  语法：

  ```shell
  until condition
  do
  	statement
  done
  ```

  与while循环类似，循环将反复执行直到条件为真，如果需要循环至少执行一次，就是用while;如果可能根本都不用执行循环，就使用until.

  实验：特定用户登录报警

  ```shell
  #!/bin/bash
  
  until who | grep "$1" > /dev/null
  do
      sleep 60
  done
  
  #用户登录，发出警报
  echo -e '\a'
  echo "***** $1 has just logged in *****"
  exit 0
  ```

* case语句

  语法：

  ```shell
  case variable in
    pattern [ | pattern ] ...) statements;;
    pattern [ | pattern ] ...) statements;;
    ...
  esac
  ```

  case允许通过一种比较复杂的方式将变量内容和模式进行匹配，再根据匹配的模式执行不同的代码。

  > 注意：每个模式以双分号(;;)结尾，因为可以再前后模式之间放置多条语句，所以用双分号标记一个语句的结束

  实验一：用户输入

  ```shell
  #!/bin/bash
  
  echo "Is it morning? answer yes or no"
  read timeofday
  
  case "$timeofday" in
      yes) echo "good morning";;
      no ) echo "good afternoon";;
      y  ) echo "good morning";;
      n  ) echo "good afternoon";;
      *  ) echo "sorry, answer not recongnized";;
  esac
  exit 0
  ```

  实验二：合并匹配模式

  ```shell
  #! /bin/bash
  
  echo "Is it morning?"
  read timeofday
  
  case "$timeofday" in
      yes | y | Yes | YES ) echo "good morning";;
      no | n | No | NO )    echo "good afternoon";;
      * )                   echo "sorry"
  esac
  
  exit 0
  ```

  > 通配符*在引号中不起作用

  实验三：执行多条语句

  ```shell
  #! /bin/bash
  
  echo "Is it morning?"
  read timeofday
  
  case "$timeofday" in
      yes | y | Yes | YES )
          echo "good morning"
          echo "up bright and early this morning"
          ;;
      [nN]* )
          echo "good afternoon"
          echo "have a good rest"
          ;;
  
      * )                   echo "sorry"
  esac
  
  exit 0
  ```

  > 需要把最精确的匹配放到最开始，而把一般匹配放到最后，因为case执行他找到的第一个匹配而不是最佳匹配。esac前的双分号是可选的，

* 命令列表

  * AND列表】

    AND列表结构类似与C语言中的与逻辑：只有前面的所有命令都执行成功才执行下一条命令

    语法：

    ```shell
    state1 && state2 && state3 && ...
    ```

    实验：

    ```shell
    #!/bin/bash
    
    touch file_one
    rm -f file_two
    
    if [ -f file_one ] && echo "hello" && [ -f file_two ] && echo "there"
    then
        echo "in if"
    else
        echo "in else"
    fi
    
    exit 0
    ```

  * OR列表

    OR结构允许持续执行一系列命令知道有一条命令成功为止，其后命令将不再被执行。

    语法：

    ```shell
    state1 || state2 || ...
    ```

    实验：

    ```shell
    #!/bin/bash
    
    rm -r file_one
    if [ -f file_one ] || echo "hello" || echo " there"
    then
        echo "in if"
    else
        echo "in else"
    fi  
    exit 0
    ```

* 语句块

  可以用{}构造语句块，其中有多条语句。

**3. 函数**

shell中定义函数，只需写出名字、然后一对空括号，再把函数中的语句放到一对花括号之中：

```shell
function_name() {
    statements
}
```

实验：

```shell
#!/bin/bash

foo () {
	echo "Function foo is executing"
}

echo "script starting"
foo
echo "script ends"
exit 0
```

>  必须在调用一个函数之前先对它进行定义，因为所有脚本程序都是从顶部开始执行，所以只要把所有函数定义都放在任何一个函数调用之前，就可以保证函数被调用之前就被定义了。
>
> 当一个函数被调用时，脚本程序的位置参数（`$*`,`$@`,`$1`等）会被替换为函数的参数，当函数执行完毕后，参数会恢复为他们先前的值。

​	通过return命令让函数返回数字值，函数返回字符串的常用方法是让函数将字符串保存在一个变量中，该变量可以在函数结束之后被使用，还可以echo一个字符串并捕获其结果。

​	可以使用local关键字声明局部变量，局部变量仅在函数作用域内有效，此外函数可以访问全局范围内的其他shell变量，如果一个局部变量和全局变量重名，前者会覆盖后者，但仅限于函数作用范围之内。

```shell
#!/bin/bash
sample_text="global variable"
foo () {
    local sample_text="local variable"
    echo "Function foo is executing"
    echo "$sample_text"
}

echo "script starting"
echo "$sample_text"
foo
echo "script ends"
echo "$sample_text"
exit 0
```

如果函数没有return命令指定返回值，则返回执行的最后一条命令的退出码。

实验：从函数中返回一个值

```shell
#!/bin/bash

yes_or_no() {
    echo "Is your name $*?"
    while true 
    do
      echo -n "Enter yes or no"
      read x
      case "$x" in 
        y | yes ) return 0;;
        n | no  ) return 1;;
        * )       echo "Answer yes or no"
      esac
    done
}

echo "Original parameter are $*"

if yes_or_no "$1"
then
    echo "Hi $1 ,nice name"
else 
    echo "never mind"
fi
exit 0	
```

**4.命令**

可以再shell脚本中执行两类命令，一类是在命令提示符中进行的**外部命令**，另一种是**内置命令**，内置命令是在shell中实现的，不能作为外部程序被调用。

* break命令

  可以跳出for 、while或until，可以为break命令提供一个额外的数值参数来表明需要跳出的循环参数，默认情况下只跳出一层循环。

  ```shell
  #!/bin/bash
  
  yes_or_no() {
      echo "Is your name $*?"
      while true 
      do
        echo -n "Enter yes or no"
        read x
        case "$x" in 
          y | yes ) return 0;;
          n | no  ) return 1;;
          * )       echo "Answer yes or no"
        esac
      done
  }
  
  echo "Original parameter are $*"
  
  if yes_or_no "$1"
  then
      echo "Hi $1 ,nice name"
  else 
      echo "never mind"
  fi
  exit 0
  ```

* ：命令

  冒号（：）是一个空命令，偶尔用于简化条件逻辑，相当于true的一个别名，运行比true快，但是作为输出可读性较差。

* continue

  类似C语言中的同名语句

* eval命令

  eval命令允许对参数求值。它是shell的内置命令，通常不会以单独命令的形式存在。

  ![](http://p5s7d12ls.bkt.clouddn.com/18-7-12/65806701.jpg)

  如上面的实验所示，eval命令有点像一个额外的`$`,它给出一个变量的值。

* exit n

  exit命令使脚本程序以退出码n结束运行，如果在任何一个交互式shell的命令提示符中使用这个命令，将会退出系统。如果允许自己的脚本程序存在退出时不指定一个退出状态，那么脚本中最后一条执行命令的状态将被用作返回值。在shell中，退出码0表示成功，退出码1-125是可以使用的错误码，其余数字有保留含义：

  | 退 出 码  |    说 明     |
  | :-------: | :----------: |
  |    126    | 文件不可执行 |
  |    127    |  命令未找到  |
  | 128及以上 | 出现一个信号 |

* export

  export命令将作为它参数的变量导出到子shell中，并使之在子shell有效，在默认情况下，在一个shell中被创建的变量在这个shell调用的下级shell中是不可用的。export命令将自己的参数创建为一个环境变量，而这个环境变量可以被当前程序调用的其他脚本和程序看见。即，被导出的变量构成从shell衍生的任何子进程的环境变量。

  实验：导出变量

  export2.sh:

  ```shell
  #！/bin/sh
  echo "$foo"
  echo "$bar"
  ```

  export1.sh

  ```shell
  #!/bin/sh
  foo="The first meta-syntactic variable"
  export bar="the second meta-syntactic variable"
  ./export2.sh
  ```

  运行结果：

  ```shell
  $ ./export1.sh
  
  the second meta-syntactic variable
  ```

  可见，在运行export2时，foo值已经丢失，但是变量bar的值被导出到了第二个脚本中。一旦一个变量被shell导出，他就可以被该shell调用的任何脚本使用，也可以被后续依次调用的任何shell使用。

  > set -a或set --allexport命令将导出它之后声明的所有变量。

* expr命令

  expr将它的参数当做一个表达式来求值，常见用法：

  ```shell
  x=`expr $x + 1`
  ```

  反引号（``） 使x取值为命令$expr \ \ x+1$的执行结果，可以用语法 $()代替反引号 ，如下所示：

  ```shell
  x=$(expr $x + 1)
  ```