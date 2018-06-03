---
title: KMP算法
date: 2018-03-29 20:28:00
tags: [算法, 字符串匹配]
---
在编辑文本程序过程中，经常需要在文本中找到某个模式的所有出现位置。典型情况是，一段正在被编辑的文本构成一个文件，而所要搜寻的模式是用户正在输入的特定的关键字。有效的解决这个问题的算法叫做字符串匹配算法，该算法能极大提高编辑文本程序时的响应效率。


KMP算法是一种改进的字符串匹配算法，它的关键是利用匹配失败后的信息，尽量减少模式串与主串的匹配次数以达到快速匹配的目的。我们以一道字符串匹配的题目来学习KMP算法。
  <!-- more-->
***题目：***
对于一个非空字符串，判断其是否可由一个子字符串重复多次组成。字符串只包含小写字母且长度不超过10000。
**样例1**：
*输入* "abab"
*输出* True
*样例解释：*输入可由"ab"重复两次组成
 --
**样例2**：
*输入* "aba"
*输出* False

***思路1：***
笔者在看到题的第一眼产生的想法是非常质朴的遍历，枚举出字符串所有长度为lenSub的子串，然后将字符串分割成长度为lenSub的串，挨个与字串比较，如果相同则返回true，否则返回false

***代码1***
```java
public static int strStr(String source) {
        int n = source.length();
       for (int i=1; i<=source.length()/2; i++) {
           String substr = source.substring(0,i);
           boolean flag = true;
           if ((n-i) % i == 0){
               int div = n/i;
               String other = null;
               for (int j=1; j<div; j++){
                   other = source.substring(i*j,i*j+i);
                   if (!other.equals(substr)) {
                       flag = false;
                       break;
                   }
               }
               if (flag == true)
                   return 1;
           }
       }
       return -1;
    }```
***思路2：KMP算法***
由kmp算法中的next数组实现。
1. 字符串s的下标从0到n-1，n为字符串长度，记s(i)表示s的第i位字符，s(i,j)表示从s的第i位到第j位的子字符串，若i>j，则s(i,j)=””(空串）。
1. next数组的定义为：next(i)=p，表示p为小于i且满足s(0 , p) = s(i-p , i)的最大的p，如果不存在这样的p，则next(i) = -1，显然next(0) = -1。我们可以用O(n)的时间计算出next数组。假设我们已知next(0)，next(1)，……，next(i-1) ，现在要求next(i)，不妨设next(i-1) = j0，则由next数组定义可知s(0 , j0) = s(i-1-j0 , i-1)。
 * 若s(j0+1) = s(i)，则结合s(0 , j0) = s(i-1-j0 , i-1)可知s(0 , j0+1) = s(i - (j0+1) , i)，由此可知，next(i)=j0+1。

  * 若s(j0+1)!=s(i)但s(next(j0)+1)=s(i)，记j1=next(j0)，则s(j1+1)=s(i)，由next数组的定义，s(0 , j1) = s(j0 - j1 , j0) = s(i - 1 - j1 , i - 1)，即s(0，j1) = s(i - 1 - j1 , i - 1)，由假设s(j1+1) = s(i)，则s(0 , j1+1) = s(i - (j1+1) , i)，故next(i) = j1+1。

 * 同前两步的分析，如果我们能找到一个k，使得对于所有小于k的k0，s(j(k0)+1)!=s(i)，但有s(j(k)+1) = s(i)，则由next数组的定义可以得到next(i)=j(k)+1，否则需进一步考虑j(k+1) = next(j(k))，如果我们找不到这样的k，则next(i)=-1。

1. 对于字符串s，如果j满足，0<=j<=n-1，且s(0，j) = s(n-1-j，n-1)，令k=n-1-j，若k整除n，不妨设n=mk，则s(0，(m-1)k - 1) = s(k，mk - 1)，即s(0，k-1) = s(k，2k-1) = …… = s((m-1)k - 1，mk - 1)，即s满足题设条件。故要判断s是否为重复子串组成，只需找到满足上述条件的j，且k整除n，即说明s满足条件，否则不满足。

1. 利用已算出的next(n-1)，令k=n-1-next(n-1)，由c可知，若k整除n，且k<n，则s满足条件，否则不满足。上述算法的复杂度可证明为O(n)。

***代码2***
```java
public static int KMP(String source) {
        int l = source.length();
        int [] next = new int[l];
        next[0] = -1;
        int i, j=-1;
        for (i = 1; i < l; i++) {
            while (j >= 0 && source.charAt(i) != source.charAt(j+1)) {
                j = next[j];
            }
            if (source.charAt(i) == source.charAt(j+1)) {
                j++;
            }
            next[i] = j;
        }
        int lenSub = l-1-next[l - 1];
        return lenSub != l && l%lenSub == 0 ? 1 : -1;
    }```