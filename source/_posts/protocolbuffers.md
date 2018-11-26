---
title: Protocol Buffers
date: 2018-11-19 22:32:29
tags: [大数据, 分布式]
---

在看Hadoop源码的时候涉及到了Protocol buffers，因此这里单开一篇博客写一下自己学习的笔记。主要内容来源于官网文档。

-----

 Protocol buffers是一种语言中立，平台无关，可扩展的序列化数据的格式，可用于通信协议，数据存储等。

Protocol buffers are a flexible, efficient, automated mechanism for serializing structured data – think XML, but smaller, faster, and simpler. You define how you want your data to be structured once, then you can use special generated source code to easily write and read your structured data to and from a variety of data streams and using a variety of languages. **You can even update your data structure without breaking deployed programs that are compiled against the "old" format.**

<!-- more-->

**Protocol buffers 很适合做数据存储或 RPC 数据交换格式。可用于通讯协议、数据存储等领域的语言无关、平台无关、可扩展的序列化结构数据格式**。

Protocol Buffer的特性：

- 可以很容易地引入新的字段，并且不需要检查数据的中间服务器可以简单地解析并传递数据，而无需了解所有字段。
- 数据格式更加具有自我描述性，可以用各种语言来处理(C++, Java 等各种语言)
- 自动生成的序列化和反序列化代码避免了手动解析的需要。
- 除了用于 RPC（远程过程调用）请求之外，人们开始将 protocol buffers 用作持久存储数据的便捷自描述格式（例如，在Bigtable中）。

- 服务器的 RPC 接口可以先声明为协议的一部分，然后用 protocol compiler 生成基类，用户可以使用服务器接口的实际实现来覆盖它们。

**protocol buffers 诞生之初是为了解决服务器端新旧协议(高低版本)兼容性问题，名字叫“协议缓冲区”。只不过后期慢慢发展成用于传输数据**。

简单的使用：

在 proto 中，所有结构化的数据都被称为 message。

You specify how you want the information you're serializing to be structured by defining protocol buffer message types in `.proto` files. Each protocol buffer message is a small logical record of information, containing a series of name-value pairs.

```protobuf
message Person {
  required string name = 1;
  required int32 id = 2;
  optional string email = 3;

  enum PhoneType {
    MOBILE = 0;
    HOME = 1;
    WORK = 2;
  }

  message PhoneNumber {
    required string number = 1;
    optional PhoneType type = 2 [default = HOME];
  }

  repeated PhoneNumber phone = 4;
}
```

Once you've defined your messages, you run the protocol buffer compiler for your application's language on your `.proto` file to generate data access classes. These provide simple accessors for each field (like `name()` and `set_name()`) as well as methods to serialize/parse the whole structure to/from raw bytes

每个消息定义中的每个字段都有**唯一的编号**。这些字段编号用于标识消息二进制格式中的字段，并且在使用消息类型后不应更改。

- 字段名不能重复，必须唯一。
- repeated 字段：可以在一个 message 中重复任何数字多次(包括 0 )，不过这些重复值的顺序被保留。

![](https://img.halfrost.com/Blog/ArticleImage/84_3.png)

在 message 中可以嵌入枚举类型。

枚举类型需要注意的是，一定要有 0 值。

- 枚举为 0 的是作为零值，当不赋值的时候，就会是零值。
- 为了和 proto2 兼容。在 proto2 中，零值必须是第一个值。

