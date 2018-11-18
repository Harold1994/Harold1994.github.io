---
title: Hadoop源码阅读——Hadoop RPC
date: 2018-11-16 19:17:53
tags: [Hadoop,HDFS,大数据]
---

HadoopRPC框架基于IPC模型实现了一套轻量级RPC框架，底层采用了JavaNIO、Java动态代理以及protobuf等基础技术。

