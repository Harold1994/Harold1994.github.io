---
title: Java和Hadoop序列化机制浅讲
date: 2018-06-08 15:33:51
tags: [Java, Hadoop]
---

转自：https://blog.csdn.net/zq602316498/article/details/45190175

#### Java 和 Hadoop 序列化机制浅讲

序列化  (Serialization)将对象的状态信息转换为可以存储或传输的形式的过程（**字节流**）。在序列化期间，对象将其当前状态写入到临时或持久性存储区。以后，可以通过从存储区中读取或反序列化对象的状态，重新创建该对象。

通常来说有三个用途：

- 持久化：对象可以被存储到磁盘上
- 通信：对象可以通过网络进行传输
- 拷贝、克隆：可以通过将某一对象序列化到内存的缓冲区，然后通过反序列化生成该对象的一个深拷贝（破解单例模式的一种方法）
  <!-- more-->
在Java中要实现序列化，只需要实现Serializable即可（说是实现，其实不需要实现任何成员方法）。

```java
public interface Serializable {
}
```

如果想对某个对象进行序列化的操作，只需要在OutputStream对象上创建一个输出流 ObjectOutputStream 对象，然后调用 writeObject（）。

在序列化过程中，对象的类、类签名、类似所有非暂态和非静态成员变量的值，以及它所有的父类都会被写入。

```Java
Date d = new Date();
OutputStream out = new ByteArrayOutputStream();
ObjectOutputStream objOut = new ObjectOutputStream(out);
objOut.writeObject(d);
```

如果想对某个基本类型进行序列化，ObjectOutputStream 还提供了多种 writeBoolean、writeByte等方法

![20150422091844504.png](https://i.loli.net/2019/03/10/5c851c78cb315.png)

反序列过程类似，只需要调用 ObjectInputStream 的 readObject() ，并向下转型，就可以得到正确结果。

**优点**：实现简便，对于循环引用和重复引用的情况也能处理，允许一定程度上的类成员改变。支持加密，验证。

**缺点**：序列化后的对象占用空间过大，数据膨胀。反序列会不断创建新的对象。同一个类的对象的序列化结果只输出一份元数据（描述类关系），导致了文件不能分割。

对于需要保存和处理大规模数据的Hadoop来说，其序列化机制要达到以下目的：

- 排列紧凑：尽量减少带宽，加快数据交换速度
- 处理快速：进程间通信需要大量的数据交互，使用大量的序列化机制，必须减少序列化和反序列的开支
- 跨语言：可以支持不同语言间的数据交互啊，如C++
- 可扩展：当系统协议升级，类定义发生变化，序列化机制需要支持这些升级和变化

为了支持以上特性，引用了Writable接口。和说明性Serializable接口不一样，它要求实现两个方法。

```java
public interface Writable {
  void write(DataOutput out) throws IOException;
  void readFields(DataInput in) throws IOException;
}
```

比如，我们需要实现一个表示某一时间段的类，就可以这样写

```java
public class StartEndDate implements Writable{
	private Date startDate;
	private Date endDate;

	@Override
	public void write(DataOutput out) throws IOException {
		out.writeLong(startDate.getTime());
		out.writeLong(endDate.getTime());
	}

	@Override
	public void readFields(DataInput in) throws IOException {
		startDate = new Date(in.readLong());
		endDate = new Date(in.readLong());
	}

	public Date getStartDate() {
		return startDate;
	}
	public void setStartDate(Date startDate) {
		this.startDate = startDate;
	}
}
```

 Hadoop 还提供了另外几个重要的接口：

**WritableComparable:**它不仅提供序列化功能，而且还提供比较的功能。这种比较式是于反序列后的对象成员的值，速度较慢。

**RawComparator:**由于MapReduce十分依赖基于键的比较排序（自定义键还需要重写hashCode和equals方法），因此提供了一个优化接口   RawComparator。该接口允许直接比较数据流中的记录，无需把数据流反序列化为对象，这样避免了新建对象的额外开销。RawComparator定义如下，compare方法可以从每个字节数组b1和b2中读取给定起始位置(s1和s2)以及长度l1和l2的一个整数直接进行比较。

```java
public interface RawComparator<T> extends Comparator<T> {
  public int compare(byte[] b1, int s1, int l1, byte[] b2, int s2, int l2);
}
```

**WritableComparator:** 是 RawComparator 的一个通用实现，提供两个功能：提供了一个 RawComparator的compare()的默认实现，该默认实现只是反序列化了键然后再比较，没有什么性能优势。其次、充当了  RawComaprator 实例的一个工厂方法。

当我们要实现自定key排序时（自定义分组），需要指定自己的排序规则。

如需要以StartEndDate为键且以开始时间分组，则需要自定义分组器：

```Java
class MyGrouper implements RawComparator<StartEndDate> {
    @Override
    public int compare(StartEndDate o1, StartEndDate o2) {
        return (int)(o1.getStartDate().getTime()- o2.getEndDate().getTime());
    }
    @Override
    public int compare(byte[] b1, int s1, int l1, byte[] b2, int s2, int l2) {
        int compareBytes = WritableComparator.compareBytes(b1, s1, 8, b2, s2, 8);
        return compareBytes;
    }

}
```

然后在job中设置

job.setGroupingComparatorClass(MyGrouper.class);
 最好将equals和hashcode也进行重写：

```java
1. @Override  
2. public boolean equals(Object obj) {  
3.     if(!(obj instanceof StartEndDate))  
4.         return false;  
5.     StartEndDate s = (StartEndDate)obj;  
6.     return startDate.getTime()== s.startDate.getTime()&&endDate.getTime() == s.endDate.getTime();   
7. }  
8. @Override  
9. public int hashCode() {  
10.     int result = 17;    
11.      result = 31*result +startDate.hashCode();   
12.      result = 31*result +endDate.hashCode();    
13.      return result;  
14. };  
```

ps： equal 和 hashcode 方法中应该还要对成员变量判空，以后还需要修改。
