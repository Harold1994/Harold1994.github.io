---
title: linux常用命令————前后台进程管理
date: 2018-07-05 22:33:48
tags: Linux
---

**1、&**

在Linux终端运行命令的时候，在命令末尾加上 & 符号，就可以让程序在后台运行

```
./tcpserv01 &
```

**2、 Ctrl+z 和 bg**

 如果程序正在前台运行，可以使用 Ctrl+z 选项把程序暂停，然后用 bg %[number] 命令把这个程序放到后台运行.通过bg %num 即可将挂起的job的状态由stopped改为running，仍在后台执行；当需要改为在前台执行时，执行命令fg %num即可

<!-- more--> 

**3. fg**

 将后台中的命令调至前台继续运行.如果后台中有多个命令，可以用 fg %jobnumber将选中的命令调出，%jobnumber是通过jobs命令查到的后台正在执行的命令的序号(不是pid)

**4.jobs**

查看当前有多少在后台运行的命令

jobs命令执行的结果，**＋（加号）**表示是一个当前的作业，**- （减号）**表示是一个当前作业之后的一个作业，jobs -l选项可显示所有任务的PID.

jobs的状态可以是running, stopped, Terminated,但是如果任务被终止了（kill），shell 从当前的shell环境已知的列表中删除任务的进程标识；也就是说，jobs命令显示的是当前shell环境中所起的后台正在运行或者被挂起的任务信息；

**5.jps**

jps -- Java Virtual Machine Process Status Tool  

可以列出本机所有java进程的pid 

-q 仅输出VM标识符，不包括class name,jar name,arguments in main method 
-m 输出main method的参数 
-l 输出完全的包名，应用主类名，jar的完全路径名 
-v 输出jvm参数 
-V 输出通过flag文件传递到JVM中的参数(.hotspotrc文件或-XX:Flags=所指定的文件

-Joption 传递参数到vm,例如:-J-Xms48m



下列命令可以用来操纵进程任务：

　　ps 列出系统中正在运行的进程；

　　kill 发送信号给一个或多个进程（经常用来杀死一个进程）；

　　jobs 列出当前shell环境中已启动的任务状态，若未指定jobsid，则显示所有活动的任务状态信息；

如果报告了一个任务的终止(即任务的状态被标记为Terminated)，shell 从当前的shell环境已知的列表中删除任务的进程标识；

　　bg 将进程搬到后台运行（Background）；

　　fg 将进程搬到前台运行（Foreground）； 

**概念：当前任务** 
　　如果后台的任务号有2个，[1],[2]；如果当第一个后台任务顺利执行完毕，第二个后台任务还在执行中时，当前任务便会自动变成后台任务号码“[2]”的后台任务。

所以可以得出一点，即当前任务是会变动的。当用户输入“fg”、“bg”和“stop”等命令时，如果不加任何引号，则所变动的均是当前任务。

**==== 前台进程的挂起**： ctrl+Z;
**==== 进程的终止:　　  ----  后台进程的终止：**

　　 方法一：通过jobs命令查看job号（假设为num），然后执行kill %num   **$ kill %1**
　　 方法二：通过ps命令查看job的进程号（PID，假设为pid），然后执行kill pid  **$ kill 5270**

-----  ctrl+c,ctrl+d,ctrl+z在linux中意义：

​        ctrl-c 发送 SIGINT 信号给前台进程组中的所有进程。常用于终止正在运行的程序。
        ctrl-z 发送 SIGTSTP 信号给前台进程组中的所有进程，常用于挂起一个进程。
        ctrl-d 不是发送信号，而是表示一个特殊的二进制值，表示 EOF。
        ctrl-\ 发送 SIGQUIT 信号给前台进程组中的所有进程，终止前台进程并生成 core 文件。