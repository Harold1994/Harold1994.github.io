---
title: nohuph和&后台运行
date: 2018-11-09 19:58:10
tags: Linux
---

1.nohup

用途：不挂断地运行命令。

语法：nohup Command \[ Arg … ][ & ]

　　无论是否将 nohup 命令的输出重定向到终端，输出都将附加到当前目录的 nohup.out 文件中。

　　如果当前目录的 nohup.out 文件不可写，输出重定向到 $HOME/nohup.out 文件中。

　　如果没有文件能创建或打开以用于追加，那么 Command 参数指定的命令不可调用。

<!-- more-->

退出状态：该命令返回下列出口值： 　　

　　126 可以查找但不能调用 Command 参数指定的命令。 　　

　　127 nohup 命令发生错误或不能查找由 Command 参数指定的命令。 　　

　　否则，nohup 命令的退出状态是 Command 参数指定命令的退出状态。

2.&

用途：在后台运行

一般两个一起用

nohup command &

eg:

```
`nohup /usr/local/node/bin/node /www/im/chat.js >> /usr/local/node/output.log 2>&1 &`
```

查看运行的后台进程

（1）jobs -l

`[1]    2229 running    nohup sh storm dev-zookeeper`

jobs命令只看当前终端生效的，关闭终端后，在另一个终端jobs已经无法看到后台跑得程序了，此时利用ps（进程查看命令）

注：

　　用ps -def | grep查找进程很方便，最后一行总是会grep自己

3.如果某个进程起不来，可能是某个端口被占用

查看使用某端口的进程

```shell
$ lsof -i:8080
COMMAND  PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
java    2301 harold   36u  IPv6 0x912be89f2ea06925      0t0  TCP *:http-alt (LISTEN)
```

