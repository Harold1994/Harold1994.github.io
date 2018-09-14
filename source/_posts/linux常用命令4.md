---
title: linux常用命令————read、col、cat、tail、查看日志命令
date: 2018-07-05 22:53:52
tags: Linux
---

**1.read**

Linux read命令用于从标准输入读取数值。

read 内部命令被用来从标准输入读取单行数据。这个命令可以用来读取键盘输入，当使用重定向的时候，可以读取文件中的一行数据。

```
read [-ers] [-a aname] [-d delim] [-i text] [-n nchars] [-N nchars] [-p prompt] [-t timeout] [-u fd] [name ...]
```

<!-- more--> 	

**参数说明:**

- -a 后跟一个变量，该变量会被认为是个数组，然后给其赋值，默认是以空格为分割符。
- -d 后面跟一个标志符，其实只有其后的第一个字符有用，作为结束的标志。
- -p 后面跟提示信息，即在输入前打印提示信息。
- -e 在输入的时候可以时候命令补全功能。
- -n 后跟一个数字，定义输入文本的长度，很实用。
- -r 屏蔽\，如果没有该选项，则\作为一个转义字符，有的话 \就是个正常的字符了。
- -s 安静模式，在输入字符时不再屏幕上显示，例如login时输入密码。
- -t 后面跟秒数，定义输入字符的等待时间。
- -u 后面跟fd，从文件描述符中读入，该文件描述符可以是exec新开启的。

**a、简单读取**

```
#!/bin/bash
#这里默认会换行  
echo "输入网站名: "  
#读取从键盘的输入  
read website  
echo "你输入的网站名是 $website"  
exit 0  #退出
```

**b、-p 参数，允许在 read 命令行中直接指定一个提示**

```
#!/bin/bash

read -p "输入网站名:" website
echo "你输入的网站名是 $website" 
exit 0
```

**c.读取文件**

每次调用 read 命令都会读取文件中的 "一行" 文本。当文件没有可读的行时，read 命令将以非零状态退出。

通过什么样的方法将文件中的数据传给 read 呢？使用 cat 命令并通过管道将结果直接传送给包含 read 命令的 while 命令。

测试文件 test.txt 内容如下：

```
123
456
runoob
```

测试代码：

```
#!/bin/bash
  
count=1    # 赋值语句，不加空格
cat test.txt | while read line      # cat 命令的输出作为read命令的输入,read读到>的值放在line中
do
   echo "Line $count:$line"
   count=$[ $count + 1 ]          # 注意中括号中的空格。
done
echo "finish"
exit 0
```

**2.col**

Linux col命令用于过滤控制字符。

在许多UNIX说明文件里，都有RLF控制字符。当我们运用shell特殊字符">"和">>"，把说明文件的内容输出成纯文本文件时，控制字符会变成乱码，col指令则能有效滤除这些控制字符。

```
col [-bfx][-l<缓冲区列数>] 
```

**参数**：

- -b 过滤掉所有的控制字符，包括RLF和HRLF。
- -f 滤除RLF字符，但允许将HRLF字符呈现出来。
- -x 以多个空格字符来表示跳格字符。
- -l<缓冲区列数> 预设的内存缓冲区有128列，您可以自行指定缓冲区的大小。

 下面以 man 命令帮助文档为例，讲解col 命令的使用。

将man 命令的帮助文档保存为man_help，使用-b 参数过滤所有控制字符。在终端中使用如下命令：

```
man man | col-b > man_help  
```

**3.tail**

tail 命令可用于查看文件的内容，有一个常用的参数 -f 常用于查阅正在改变的日志文件。

tail -f filename 会把 filename 文件里的最尾部的内容显示在屏幕上，并且不断刷新，只要 filename 更新就可以看到最新的文件内容。

**命令格式：**

```
tail [参数] [文件]  
```

**参数：**

- -f 循环读取
- -q 不显示处理信息
- -v 显示详细的处理信息
- -c<数目> 显示的字节数
- -n<行数> 显示行数
- --pid=PID 与-f合用,表示在进程ID,PID死掉之后结束.
- -q, --quiet, --silent 从不输出给出文件名的首部
- -s, --sleep-interval=S 与-f合用,表示在每次反复的间隔休眠S秒

 要显示 notes.log 文件的最后 10 行，请输入以下命令：

```
tail notes.log
```

要跟踪名为 notes.log 的文件的增长情况，请输入以下命令：

```
tail -f notes.log
```

此命令显示 notes.log 文件的最后 10 行。当将某些行添加至 notes.log 文件时，tail 命令会继续显示这些行。 显示一直继续，直到您按下（Ctrl-C）组合键停止显示。

显示文件 notes.log 的内容，从第 20 行至文件末尾:

```
tail +20 notes.log
```

显示文件 notes.log 的最后 10 个字符:

```
tail -c 10 notes.log
```

**4.cat**

cat 命令用于连接文件并打印到标准输出设备上。

```
cat [-AbeEnstTuv] [--help] [--version] fileName
```

### 参数说明：

**-n 或 --number**：由 1 开始对所有输出的行数编号。

**-b 或 --number-nonblank**：和 -n 相似，只不过对于空白行不编号。

**-s 或 --squeeze-blank**：当遇到有连续两行以上的空白行，就代换为一行的空白行。

**-v 或 --show-nonprinting**：使用 ^ 和 M- 符号，除了 LFD 和 TAB 之外。

**-E 或 --show-ends** : 在每行结束处显示 $。

**-T 或 --show-tabs**: 将 TAB 字符显示为 ^I。

**-e** : 等价于 -vE。

**-A, --show-all**：等价于 -vET。

**-e：**等价于"-vE"选项；

**-t：**等价于"-vT"选项；

**5.Linux查看日志命令**

当日志文件存储日志很大时，我们就不能用vi直接进去查看日志，需要Linux的命令去完成我们的查看任务.

- **混合使用命令**

```
A.  tail web.2016-06-06.log -n 300 -f  
    查看底部即最新300条日志记录，并实时刷新      

B.  grep 'nick' | tail web.2016-04-04.log -C 10   
    查看字符‘nick’前后10条日志记录, 大写C  

C.  cat -n test.log |tail -n +92|head -n 20  
    tail -n +92表示查询92行之后的日志  
    head -n 20 则表示在前面的查询结果里再查前20条记录  
```