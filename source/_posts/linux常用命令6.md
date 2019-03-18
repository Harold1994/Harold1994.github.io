---
title: linux常用命令——find、join
date: 2018-07-12 17:06:02
tags: Linux
---

**1.find**

Linux find命令用来在指定目录下查找文件。任何位于参数之前的字符串都将被视为欲查找的目录名。如果使用该命令时，不设置任何参数，则find命令将在当前目录下查找子目录与文件。并且将查找到的子目录和文件全部进行显示。

语法：

```shell
find   path   -option   [   -print ]   [ -exec   -ok   command ]   {} \;
```

参数说明：find 根据下列规则判断 path 和 expression，在命令列上第一个 - ( ) , ! 之前的部份为 path，之后的是 expression。如果 path 是空字串则使用目前路径，如果 expression 是空字串则使用 -print 为预设 expression。

<!-- more--> 

expression 中可使用的选项有二三十个之多，在此只介绍最常用的部份。

-mount, -xdev : 只检查和指定目录在同一个文件系统下的文件，避免列出其它文件系统中的文件

-amin n : 在过去 n 分钟内被读取过

-anewer file : 比文件 file 更晚被读取过的文件

-atime -n : 在过去 n 天过读取过的文件

-cmin -n : 在过去 n 分钟内被修改过

-cnewer file :比文件 file 更新的文件

-ctime -n : 在过去 n 天过修改过的文件

-empty : 空的文件-gid n or -group name : gid 是 n 或是 group 名称是 name

-ipath p, -path p : 路径名称符合 p 的文件，ipath 会忽略大小写

-name name, -iname name : 文件名称符合 name 的文件。iname 会忽略大小写

-size n : 文件大小 是 n 单位，b 代表 512 位元组的区块，c 表示字元数，k 表示 kilo bytes，w 是二个位元组。

-type c : 文件类型是 c 的文件。

d: 目录

c: 字型装置文件

b: 区块装置文件

p: 具名贮列

f: 一般文件

l: 符号连结

s: socket

-pid n : process id 是 n 的文件

你可以使用 ( ) 将运算式分隔，并使用下列运算。

exp1 -and exp2

! expr

-not expr

exp1 -or exp2

exp1, exp2

示例:

将目前目录及其子目录下所有延伸档名是 c 的文件列出来。

```shell
# find . -name "*.c"
```

将目前目录及其下子目录中所有一般文件列出：

```shell
# find . -type f
```

将目前目录及其子目录下所有最近 20 天内更新过的文件列出

```shell
# find . -ctime -20
```

查找/var/log目录中更改时间在7日以前的普通文件，并在删除之前询问它们：

```shell
# find /var/log -type f -mtime +7 -ok rm {} \;
```

查找当前目录中文件属主具有读、写权限，并且文件所属组的用户和其他用户具有读权限的文件：

```shell
# find . -type f -perm 644 -exec ls -l {} \;
```

为了查找系统中所有文件长度为0的普通文件，并列出它们的完整路径：

```shell
# find / -type f -size 0 -exec ls -l {} \;
```

-exec command：command 为其他指令，-exec后面可再接额外的指令来处理搜寻到的结果。

![find 相關的額外動作](http://linux.vbird.org/linux_basic/0220filemanager/centos7_find_exec.gif)

{ }代表的是「由 find 找到的内容」，如上图所示，找到的结果会被放置到 { } 位置中;
-exec一直到 ; 是关键字，代表找到额外动作的开始（-exec）到结束（），在这中间的就是找到指令内的额外动作

因为「;」在bash的环境下是有特殊意义的，因此利用反斜线来跳脱。

**2.grep**

​	Linux grep命令用于查找文件里符合条件的字符串。grep指令用于查找内容包含指定的范本样式的文件，如果发现某文件的内容符合所指定的范本样式，预设grep指令会把含有范本样式的那一列显示出来。若不指定任何文件名称，或是所给予的文件名为"-"，则grep指令会从标准输入设备读取数据。

语法：

```shell
grep [-abcEFGhHilLnqrsvVwxy][-A<显示列数>][-B<显示列数>][-C<显示列数>][-d<进行动作>][-e<范本样式>][-f<范本文件>][--help][范本样式][文件或目录...]
```

参数：

- **-a 或 --text** : 不要忽略二进制的数据。
- **-A<显示行数> 或 --after-context=<显示行数>** : 除了显示符合范本样式的那一列之外，并显示该行之后的内容。
- **-b 或 --byte-offset** : 在显示符合样式的那一行之前，标示出该行第一个字符的编号。
- **-B<显示行数> 或 --before-context=<显示行数>** : 除了显示符合样式的那一行之外，并显示该行之前的内容。
- **-c 或 --count** : 计算符合样式的列数。
- **-C<显示行数> 或 --context=<显示行数>或-<显示行数>** : 除了显示符合样式的那一行之外，并显示该行之前后的内容。
- **-d <动作> 或 --directories=<动作>** : 当指定要查找的是目录而非文件时，必须使用这项参数，否则grep指令将回报信息并停止动作。
- **-e<范本样式> 或 --regexp=<范本样式>** : 指定字符串做为查找文件内容的样式。
- **-E 或 --extended-regexp** : 将样式为延伸的普通表示法来使用。
- **-f<规则文件> 或 --file=<规则文件>** : 指定规则文件，其内容含有一个或多个规则样式，让grep查找符合规则条件的文件内容，格式为每行一个规则样式。
- **-F 或 --fixed-regexp** : 将样式视为固定字符串的列表。
- **-G 或 --basic-regexp** : 将样式视为普通的表示法来使用。
- **-h 或 --no-filename** : 在显示符合样式的那一行之前，不标示该行所属的文件名称。
- **-H 或 --with-filename** : 在显示符合样式的那一行之前，表示该行所属的文件名称。
- **-i 或 --ignore-case** : 忽略字符大小写的差别。
- **-l 或 --file-with-matches** : 列出文件内容符合指定的样式的文件名称。
- **-L 或 --files-without-match** : 列出文件内容不符合指定的样式的文件名称。
- **-n 或 --line-number** : 在显示符合样式的那一行之前，标示出该行的列数编号。
- **-q 或 --quiet或--silent** : 不显示任何信息。
- **-r 或 --recursive** : 此参数的效果和指定"-d recurse"参数相同。
- **-s 或 --no-messages** : 不显示错误信息。
- **-v 或 --revert-match** : 显示不包含匹配文本的所有行。
- **-V 或 --version** : 显示版本信息。
- **-w 或 --word-regexp** : 只显示全字符合的列。
- **-x --line-regexp** : 只显示全列符合的列。
- **-y** : 此参数的效果和指定"-i"参数相同。

示例：

1、在当前目录中，查找后缀有 file 字样的文件中包含 test 字符串的文件，并打印出该字符串的行。此时，可以使用如下命令：

```shell
grep test *file 
```

2、以递归的方式查找符合条件的文件。例如，查找指定目录/etc/acpi 及其子目录（如果存在子目录的话）下所有文件中包含字符串"update"的文件，并打印出该字符串所在行的内容，使用的命令为：

```shell
grep -r update /etc/acpi 
```

3、反向查找。前面各个例子是查找并打印出符合条件的行，通过"-v"参数可以打印出不符合条件行的内容。

查找文件名中包含 test 的文件中不包含test 的行，此时，使用的命令为：

```shell
grep -v test *test*
```

**3. join**

Linux join命令用于将两个文件中，指定栏位内容相同的行连接起来。

找出两个文件中，指定栏位内容相同的行，并加以合并，再输出到标准输出设备。

语法：

```shell
join [-i][-a<1或2>][-e<字符串>][-o<格式>][-t<字符>][-v<1或2>][-1<栏位>][-2<栏位>][--help][--version][文件1][文件2]
```

参数：

- -a<1或2> 除了显示原来的输出内容之外，还显示指令文件中没有相同栏位的行。
- -e<字符串> 若[文件1]与[文件2]中找不到指定的栏位，则在输出中填入选项中的字符串。
- -i或--igore-case 比较栏位内容时，忽略大小写的差异。
- -o<格式> 按照指定的格式来显示结果。
- -t<字符> 使用栏位的分隔字符。
- -v<1或2> 跟-a相同，但是只显示文件中没有相同栏位的行。
- -1<栏位> 连接[文件1]指定的栏位。
- -2<栏位> 连接[文件2]指定的栏位。
- --help 显示帮助。
- --version 显示版本信息。

示例：

连接两个文件。

为了清楚地了解join命令，首先通过cat命令显示文件testfile_1和 testfile_2 的内容。

然后以默认的方式比较两个文件，将两个文件中指定字段的内容相同的行连接起来，在终端中输入命令：

```shell
join testfile_1 testfile_2 
```

首先查看testfile_1、testfile_2 中的文件内容：

```shell
$ cat testfile_1 #testfile_1文件中的内容  
Hello 95 #例如，本例中第一列为姓名，第二列为数额  
Linux 85  
test 30  
cmd@hdd-desktop:~$ cat testfile_2 #testfile_2文件中的内容  
Hello 2005 #例如，本例中第一列为姓名，第二列为年份  
Linux 2009  
test 2006 
```

然后使用join命令，将两个文件连接，结果如下：

```
$ join testfile_1 testfile_2 #连接testfile_1、testfile_2中的内容  
Hello 95 2005 #连接后显示的内容  
Linux 85 2009  
test 30 2006 
```

文件1与文件2的位置对输出到标准输出的结果是有影响的。例如将命令中的两个文件互换，即输入如下命令：

```shell
join testfile_2 testfile_1
```

最终在标准输出的输出结果将发生变化，如下所示：

```shell
$ join testfile_2 testfile_1 #改变文件顺序连接两个文件  
Hello 2005 95 #连接后显示的内容  
Linux 2009 85  
test 2006 30 
```

```shell
指定输出字段：
-o <FILENO.FIELDNO> ...
其中FILENO=1表示第一个文件，FILENO=2表示第二个文件，FIELDNO表示字段序号，从1开始编号。默认会全部输出，但关键字列只输出一次。
比如：-o 1.1 1.2 2.2 表示输出第一个文件的第一个字段、第二个字段，第二个文件的第二个字段。
```

```shell
使用示例
示例一 内连接（忽略不匹配的行）
不指定任何参数的情况下使用join命令，就相当于数据库中的内连接，关键字不匹配的行不会输出。
[root@rhel55 linux]# cat month_cn.txt 
1       一月
2       二月
3       三月
4       四月
5       五月
6       六月
7       七月
8       八月
9       九月
10      十月
11      十一月
12      十二月
13      十三月，故意的 
[root@rhel55 linux]# cat month_en.txt 
1       January
2       February
3       March
4       April
5       May
6       June
7       July
8       August
9       September
10      October
11              November
12      December
14      MonthUnknown
注：注意两个文件的内容，中文版的多了十三月，英文版的多了14月，这纯粹是为了方便演示。 
[root@rhel55 linux]# join month_cn.txt month_en.txt  
1 一月 January
2 二月 February
3 三月 March
4 四月 April
5 五月 May
6 六月 June
7 七月 July
8 八月 August
9 九月 September
10 十月 October
11 十一月 November
12 十二月 December
[root@rhel55 linux]#
示例二 左连接（又称左外连接，显示左边所有记录）
显示左边文件中的所有记录，右边文件中没有匹配的显示空白。
[root@rhel55 linux]# join -a1 month_cn.txt month_en.txt   
1 一月 January
2 二月 February
3 三月 March
4 四月 April
5 五月 May
6 六月 June
7 七月 July
8 八月 August
9 九月 September
10 十月 October
11 十一月 November
12 十二月 December
13 十三月，故意的 
[root@rhel55 linux]#
 
示例三 右连接（又称右外连接，显示右边所有记录）
显示右边文件中的所有记录，左边文件中没有匹配的显示空白。
[root@rhel55 linux]# join -a2 month_cn.txt month_en.txt  
1 一月 January
2 二月 February
3 三月 March
4 四月 April
5 五月 May
6 六月 June
7 七月 July
8 八月 August
9 九月 September
10 十月 October
11 十一月 November
12 十二月 December
14 MonthUnknown 
[root@rhel55 linux]#
 
示例四 全连接（又称全外连接，显示左边和右边所有记录）
[root@rhel55 linux]# join -a1 -a2 month_cn.txt month_en.txt 
1 一月 January
2 二月 February
3 三月 March
4 四月 April
5 五月 May
6 六月 June
7 七月 July
8 八月 August
9 九月 September
10 十月 October
11 十一月 November
12 十二月 December
13 十三月，故意的
14 MonthUnknown 
[root@rhel55 linux]#
 
示例五 指定输出字段
比如参数 -o 1.1 表示只输出第一个文件的第一个字段。
[root@rhel55 linux]# join -o 1.1 month_cn.txt month_en.txt 
1
2
3
4
5
6
7
8
9
10
11
12
[root@rhel55 linux]# join -o 1.1 2.2 month_cn.txt month_en.txt   
1 January
2 February
3 March
4 April
5 May
6 June
7 July
8 August
9 September
10 October
11 November
12 December
[root@rhel55 linux]# join -o 1.1 2.2 1.2 month_cn.txt month_en.txt 
1 January 一月
2 February 二月
3 March 三月
4 April 四月
5 May 五月
6 June 六月
7 July 七月
8 August 八月
9 September 九月
10 October 十月
11 November 十一月
12 December 十二月
[root@rhel55 linux]# join -o 1.1 2.2 1.2 1.3 month_cn.txt month_en.txt   <== 字段1.3并不存在 
1 January 一月 
2 February 二月 
3 March 三月 
4 April 四月 
5 May 五月 
6 June 六月 
7 July 七月 
8 August 八月 
9 September 九月 
10 October 十月 
11 November 十一月 
12 December 十二月 
[root@rhel55 linux]#
 
示例六 指定分隔符
[root@rhel55 linux]# join -t ':' /etc/passwd /etc/shadow 
```