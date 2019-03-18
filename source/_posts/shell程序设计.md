---
title: shell程序设计(一)
date: 2018-07-09 15:36:57
tags: Linux
---

shell是一个作为用户与Linux系统间接口的程序，它允许用户向操作系统输入需要执行的命令。可以使用`<`和`>`对输入输出重定向，使用`|`在同时执行的程序之间实现数据的管道传递，使用`${...}`获取子进程的输出。

#### 一、管道与重定向

**1.重定向输出**

`ls -l > test.txt`,这条命令将ls命令的输出保存到test.txt中，文件描述符0代表一个程序的标准输入、1代表标准输出、2代表标准错误输出。上面例子通过`>`将标准输出重定向到一个文件，默认情况下，如果该文件已经存在，他的文件将被覆盖。想改变默认行为，可以通过`set -o noclobber`命令设置noclobber选项，从而阻止重定向操作对一个已有文件的覆盖。通过`set -o noclobber`取消该选项。

<!-- more--> 

可以使用>> 操作符将输出文件附加到一个文件中，如`ps >> test.txt`

想对标准输出重定向，需要把想重定向的文件描述符编号加在>操作符前面，例如使用`2> err.log` 将标准错误流重定向到errl.log。下面的命令将标准输出和标准错误输出分别重定向到不同文件：
`kill -HUP 1234 > killout.txt 2>killerr.txt`

可以用`>&`结合两个流重定向到一个文件：

` kill -l 1234 > killouterr.txt 2>&1`，这条命令将标准输出和标准错误输出都重定向到一个文件，这里的**操作符顺序**很重要，含义是“将标准输出流重定向到killouterr.txt ，然后将标准错误流输出重定向到与标准输出相同的地方”。

​	因为可以通过返回码了解kill命令的执行结果，所以通常不需要保存标准输出和错误的内容，可以通过回收站/dev/null有效的丢弃所有输出信息：`kill -l 1234 >/dev/null 2&>1`

**2.重定向输入**

`more < kill.txt`

**3.管道**

可以使用`|`来连接进程，在Linux下通过管道连接的进程可以**同时运行**，并且随着数据流在它们之间自动协调。

例如：

```shell
$ ps > psout.txt
$ sort psout.txt > pssort.txt
```

可以用: 

```shell
$ ps | sort > pssort.txt
```

代替。

允许连接的进程数目是没有限制的，想查看系统之所有进程名字，但不包括shell,可以用如下命令:

```shell
$ ps -xo comm | sort | uniq | grep -v sh | more
```

上面命令先按照字母排序ps命令的输出，再用uniq去除相同名字的进程，然后用grep  -v删除名字为sh的进程，最终分页显示。

> 如果有一系列命令需要执行，先用的输出文件是在这一组命令被创建的同时立刻被创建或者写入烦人，所以绝不要在命令流中使用相同的文件名。

#### 二、 作为程序设计语言的shell

shell运行的方式有两种，可以通过输入一系列命令让shell交互执行，也可以将命令保存到一个文件中，然后将该文件作为一个程序来调用。

**1.交互式程序**

```shell
#列出包含“机器“二字的文件
$ for file in * 
> do 
> if grep -l 机器 $file
> then 
> more $file
> fi
> done
```

有更有效的方法执行上面简单的操作：

```shell
more `grep -l 机器 *`
```

或者：

```shell
 more $(grep -l 机器 *)
```

此外 `grep -l 机器 * `将列出所有包含”机器“的文件名。

**2.创建脚本**

```shell
#! /bin/sh
for file in *
do
    if grep -q 机器 $file
    then
      echo $file
    fi
done
exit 0 
```

第一行注释`#！`告诉系统同一行上紧跟在他后面的那个参数是用来执行本文件的程序，exit命令的作用是确保脚本程序能够返回一个有意义的退出码。在shell中，0表示成功。

#### 三、shell的语法

**1.变量**

在shell中，使用变量之前通常不需要事先声明，默认情况下，所有变量都被看作字符串并以字符串来存储，即使被赋值为数字也是如此，Linux是大小写敏感的，shell认为Foo与foo是不同的。

在shell中，可以通过在变量名前加一个`$`符号来访问它的内容，要为变量赋值时，只需要使用变量名，该变量会根据需要自动创建。一种检查方式是在变量名前加一个 `$`符号，再用echo命令将它的内容输出到终端。

> 注意：如果字符串中包含空格，就必须用引号将他们括起来，此外，**等号两边不能有空格**

可以用`read`命令将用户的输入赋值给一个变量，这个命令需要一个参数，即准备读入用户输入数据的变量名，然后他会等待用户输入数据，用户按下回车,read结束,从终端读取一个变量时，一般不需要使用引号，

```shell
$ read test
harsdjkask
$ echo $test
harsdjkask
```

* 使用引号

  ​	一般情况下，脚本文件中的参数以空白字符分隔，如果想要在一个参数中包含一个或多个空白字符，就必须给参数加上引号。

  ​	如果把一个`$`变量表达式放在双引号中，程序执行到这一行时会把变量替换为它的值；如果放到**单引号中就不会发生替换**现象，可以通过在`$`前加上一个`\`字符以取消它的特殊含义。字符串通常放在双引号中，以防止变量被空白字符分开，同时又允许`$`扩展。

  ```shell
  #！ /bin/sh
  myvar="Hi there"
  echo $myvar
  echo "$myvar"
  echo '$myvar'
  echo \$myvar
  
  echo "enter some thing"
  read myvar
  
  echo '$myvar' noe equals $myvar
  exit 0 
  输出：
  Hi there
  Hi there
  $myvar
  $myvar
  enter some thing
  123
  $myvar noe equals 12
  ```

* 环境变量

  在一个shell脚本开始执行时，会根据环境设置中的值进行初始化，通常用大写字母做名字，以便和普通变量区分。

| 环境变量 | 说明                                                         |
| -------- | ------------------------------------------------------------ |
| $HOME    | 当前用户家目录                                               |
| $PATH    | 用冒号分隔的用来搜索命令的目录列表                           |
| $PS1     | 命令提示符，通常是$                                          |
| $PS2     | 二级提示符，提示后续输入，通常是>                            |
| $IFS     | 输入域分隔符，shell读取输入时，它给出用来分隔单词的一组字符，通常是空格、制表符 |
| $0       | shell脚本的名字                                              |
| $#       | 传递给脚本的参数个数                                         |
| $$       | shell脚本进程号                                              |

* 参数变量

  如果脚本程序在调用时带有参数，一些额外变量就会被创建。即使没有任何参数，环境变量$#也任然存在，只不过是0.

  | 参数变量       | 说    明                                                     |
  | -------------- | ------------------------------------------------------------ |
  | `$1`, `$2`,... | 脚本程序的参数                                               |
  | $*             | 列出所有参数，各个参数用环境变量IFS中第一个字符分隔开。      |
  | $@             | $*的一个变体，不使用IFS环境变量，所以即使IFS为空，参数也不会挤在一起 |

  ```shell
  harold@harold-Lenovo-G510:~$ IFS=''
  harold@harold-Lenovo-G510:~$ set foo bar bam
  harold@harold-Lenovo-G510:~$ echo "$@"
  foo bar bam
  harold@harold-Lenovo-G510:~$ echo "$*"
  foobarbam
  harold@harold-Lenovo-G510:~$ unset IFS
  harold@harold-Lenovo-G510:~$ echo "$*"
  foo bar bam
  ```

  一般使用$@是个明智的选择。

  ```shell
  #! /bin/sh
  salutation="Hello"
  echo $salutation
  echo "the program $0 is now running"
  echo "the second parameter is $2"
  echo "the 1st  parameter is $1"
  echo "the parameter list is $*"
  echo "the user's home dir is $HOME"
  
  echo "Please enter a new greeting"
  read salutation
  
  echo $salutation
  echo the script is now completed
  exit 0
  
  输出：
  ./try_var.sh foo bar baz
  Hello
  the program ./try_var.sh is now running
  the second parameter is bar
  the 1st  parameter is foo
  the parameter list is foo bar baz
  the user's home dir is /home/harold
  Please enter a new greeting
  gello
  gello
  the script is now completed
  ```

  