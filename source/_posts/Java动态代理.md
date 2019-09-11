---
title: Java动态代理
date: 2018-11-18 22:12:29
tags: [Java]
---

转自：

# **一、概述**

## 1. 什么是代理

我们大家都知道微商代理，简单地说就是代替厂家卖商品，厂家“委托”代理为其销售商品。关于微商代理，首先我们从他们那里买东西时通常不知道背后的厂家究竟是谁，也就是说，“委托者”对我们来说是不可见的;其次，微商代理主要以朋友圈的人为目标客户，这就相当于为厂家做了一次对客户群体的“过滤”。我们把微商代理和厂家进一步抽象，前者可抽象为代理类，后者可抽象为委托类(被代理类)。通过使用代理，通常有两个优点，并且能够分别与我们提到的微商代理的两个特点对应起来：

优点一：可以隐藏委托类的实现;

优点二：可以实现客户与委托类间的解耦，在不修改委托类代码的情况下能够做一些额外的处理。

<!-- more-->

## 2. 静态代理

若代理类在程序运行前就已经存在，那么这种代理方式被称为静态代理 ，这种情况下的代理类通常都是我们在Java代码中定义的。 通常情况下，静态代理中的代理类和委托类会实现同一接口或是派生自相同的父类。 下面我们用Vendor类代表生产厂家，BusinessAgent类代表微商代理，来介绍下静态代理的简单实现，委托类和代理类都实现了Sell接口，Sell接口的定义如下：

```java
/**
 * 委托类和代理类都实现了Sell接口
 */
public interface Sell { 
    void sell(); 
    void ad(); 
} 
```

Vendor类的定义如下：

```java
/**
 * 生产厂家
 */
public class Vendor implements Sell { 
    public void sell() { 
        System.out.println("In sell method"); 
    } 
    
    public void ad() { 
        System,out.println("ad method");
    }
} 
```

代理类BusinessAgent的定义如下：

```java
/**
 * 代理类
 */
public class BusinessAgent implements Sell {
    private Sell vendor;
    
    public BusinessAgent(Sell vendor){
        this.vendor = vendor;
    }

    public void sell() { 
        vendor.sell();
    } 
    
    public void ad() {
        vendor.ad();
    }
} 
```

从BusinessAgent类的定义我们可以了解到，**静态代理可以通过聚合来实现**，让代理类持有一个委托类的引用即可。

下面我们考虑一下这个需求：给Vendor类增加一个过滤功能，只卖货给大学生。通过静态代理，我们无需修改Vendor类的代码就可以实现，只需在BusinessAgent类中的sell方法中添加一个判断即可如下所示：

```java
/**
 * 代理类
 */
public class BusinessAgent(){ implements Sell {
    private Sell vendor;
    
    public BusinessAgent(Sell vendor){
        this.vendor = vendor;
    }

    public void sell() {
        if (isCollegeStudent()) {
            vendor.sell();
        }
    } 
    
    public void ad() {
        vendor.ad();
    }
} 
```

这对应着我们上面提到的使用代理的第二个优点：可以实现客户与委托类间的解耦，在不修改委托类代码的情况下能够做一些额外的处理。静态代理的局限在于运行前必须编写好代理类，下面我们重点来介绍下运行时生成代理类的动态代理方式。

# 二、动态代理

## 1. 什么是动态代理

**代理类在程序运行时创建**的代理方式被成为动态代理。 也就是说，这种情况下，代理类并不是在Java代码中定义的，而是在运行时根据我们在Java代码中的“指示”动态生成的。相比于静态代理， 动态代理的优势在于可以很方便的对代理类的函数进行统一的处理，而不用修改每个代理类的函数。 这么说比较抽象，下面我们结合一个实例来介绍一下动态代理的这个优势是怎么体现的。

现在，假设我们要实现这样一个需求：在执行委托类中的方法之前输出“before”，在执行完毕后输出“after”。我们还是以上面例子中的Vendor类作为委托类，BusinessAgent类作为代理类来进行介绍。首先我们来使用静态代理来实现这一需求，相关代码如下：

```java
public class BusinessAgent implements Sell {
    private Vendor mVendor; 
 
    public BusinessAgent(Vendor vendor) {
        this.mVendor = vendor; 
    } 
 
    public void sell() {
        System.out.println("before"); 
        mVendor.sell(); 
        System.out.println("after"); 
    } 
 
    public void ad() {
        System.out.println("before"); 
        mVendor.ad(); 
        System.out.println("after"); 
    }
} 
```

从以上代码中我们可以了解到，通过静态代理实现我们的需求需要我们在每个方法中都添加相应的逻辑，这里只存在两个方法所以工作量还不算大，假如Sell接口中包含上百个方法呢?这时候使用静态代理就会编写许多冗余代码。通过使用动态代理，我们可以做一个“统一指示”，从而对所有代理类的方法进行统一处理，而不用逐一修改每个方法。下面我们来具体介绍下如何使用动态代理方式实现我们的需求。

## 2. 使用动态代理

### 2.1 InvocationHandler接口

在使用动态代理时，我们需要定义一个位于代理类与委托类之间的中介类，这个中介类被要求实现InvocationHandler接口，这个接口的定义如下：

```java
/**
 * 调用处理程序
 */
public interface InvocationHandler { 
    Object invoke(Object proxy, Method method, Object[] args); 
} 
```

从InvocationHandler这个名称我们就可以知道，实现了这个接口的中介类用做“调用处理器”。当我们调用代理类对象的方法时，这个“调用”会转送到invoke方法中，代理类对象作为proxy参数传入，参数method标识了我们具体调用的是代理类的哪个方法，args为这个方法的参数。这样一来，我们对代理类中的所有方法的调用都会变为对invoke的调用，这样我们可以在invoke方法中添加统一的处理逻辑(也可以根据method参数对不同的代理类方法做不同的处理)。因此我们只需在中介类的invoke方法实现中输出“before”，然后调用委托类的invoke方法，再输出“after”。下面我们来一步一步具体实现它。

### 2.2 委托类的定义

动态代理方式下，要求委托类必须实现某个接口，这里我们实现的是Sell接口。委托类Vendor类的定义如下：

```java
public class Vendor implements Sell { 
    public void sell() { 
        System.out.println("In sell method"); 
    }

    public void ad() {
        System,out.println("ad method");
    }
} 
```

### 2.3 中介类

上面我们提到过，中介类必须实现InvocationHandler接口，作为调用处理器”拦截“对代理类方法的调用。中介类的定义如下：

```java
public class DynamicProxy implements InvocationHandler { 
    //obj为委托类对象; 
    private Object obj; 
 
    public DynamicProxy(Object obj) {
        this.obj = obj;
    } 
 
    @Override 
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable { 
        System.out.println("before"); 
        Object result = method.invoke(obj, args); 
        System.out.println("after"); 
        return result; 
    }
} 
```

从以上代码中我们可以看到，中介类持有一个委托类对象引用，在invoke方法中调用了委托类对象的相应方法，看到这里是不是觉得似曾相识?通过聚合方式持有委托类对象引用，把外部对invoke的调用最终都转为对委托类对象的调用。这不就是我们上面介绍的静态代理的一种实现方式吗?实际上，中介类与委托类构成了静态代理关系，在这个关系中，中介类是代理类，委托类就是委托类; 代理类与中介类也构成一个静态代理关系，在这个关系中，中介类是委托类，代理类是代理类。也就是说，**动态代理关系由两组静态代理关系组成，这就是动态代理的原理**。下面我们来介绍一下如何”指示“以动态生成代理类。

### 2.4动态生成代理类

动态生成代理类的相关代码如下：

```java
public class Main { 
    public static void main(String[] args) {
        //创建中介类实例 
        DynamicProxy inter = new DynamicProxy(new Vendor()); 
        //加上这句将会产生一个$Proxy0.class文件，这个文件即为动态生成的代理类文件
        System.getProperties().put("sun.misc.ProxyGenerator.saveGeneratedFiles","true"); 

        //获取代理类实例sell 
        Sell sell = (Sell)(Proxy.newProxyInstance(Sell.class.getClassLoader(), new Class[] {Sell.class}, inter)); 
 
        //通过代理类对象调用代理类方法，实际上会转到invoke方法调用 
        sell.sell(); 
        sell.ad(); 
    }
} 
```

在以上代码中，我们调用Proxy类的newProxyInstance方法来获取一个代理类实例。这个代理类实现了我们指定的接口并且会把方法调用分发到指定的调用处理器。这个方法的声明如下：

```java
public static Object newProxyInstance(ClassLoader loader, Class<?>[] interfaces, InvocationHandler h) throws IllegalArgumentException 
```

方法的三个参数含义分别如下：

loader：定义了代理类的ClassLoder; 

interfaces：代理类实现的接口列表 

h：调用处理器，也就是我们上面定义的实现了InvocationHandler接口的类实例

**上面我们已经简单提到过动态代理的原理，这里再简单的总结下：首先通过newProxyInstance方法获取代理类实例，而后我们便可以通过这个代理类实例调用代理类的方法，对代理类的方法的调用实际上都会调用中介类(调用处理器)的invoke方法，在invoke方法中我们调用委托类的相应方法，并且可以添加自己的处理逻辑。**

# 三、代理模式

这个应该是设计模式中最简单的一个了，类图

![wKiom1mfl_KzjkkuAABH7wa50aI36.jpeg-wh_651x-s_3199586012.jpeg](https://i.loli.net/2018/11/25/5bfa3218ed84c.jpeg)

代理模式最大的特点就是代理类和实际业务类实现同一个接口（或继承同一父类），代理对象持有一个实际对象的引用，外部调用时操作的是代理对象，而在代理对象的内部实现中又会去调用实际对象的操作

**Java动态代理其实内部也是通过Java反射机制来实现**的，即已知的一个对象，然后在运行时动态调用其方法，这样在调用前后作一些相应的处理，这样说的比较笼统，举个简单的例子

比如我们在应用中有这样一个需求，在对某个类的一个方法的调用前和调用后都要做一下日志操作，

一个普通的接口

```java
public interface AppService {  
    public boolean createApp(String name);  
}  
```

该接口的默认实现类

```java
public class AppServiceImpl implements AppService {  
    public boolean createApp(String name) {  
        System.out.println("App["+name+"] has been created.");  
        return true;  
    }  
}
```

日志处理器（实质充当了中介类）

```java
/**
 * 注意需实现Handler接口  
 */
public class LoggerInterceptor implements InvocationHandler {
    private Object target;//目标对象的引用，这里设计成Object类型，更具通用性  
    public LoggerInterceptor(Object target){  
        this.target = target;  
    }
    
    public Object invoke(Object proxy, Method method, Object[] arg)  throws Throwable {  
        System.out.println("Entered "+target.getClass().getName()+"-"+method.getName()+",with arguments{"+arg[0]+"}");  
        Object result = method.invoke(target, arg);//调用目标对象的方法  
        System.out.println("Before return:"+result);  
        return result;  
    }  
}  
```

外部调用

```java
public class Main {  
    public static void main(String[] args) {  
        AppService target = new AppServiceImpl();//生成目标对象  
        //接下来创建代理对象  
        AppService proxy = (AppService) Proxy.newProxyInstance(  
                target.getClass().getClassLoader(),  
                target.getClass().getInterfaces(), new LoggerInterceptor(target));  
        proxy.createApp("Kevin Test");  
    }  
}  
```

