---
title: Redis中的锁和信号量
date: 2018-09-21 10:01:55
tags: [NoSQL, Redis, 大数据]
---

### 分布式锁

Redis使用WATCH命令代替对数据行加锁，WATCH是一种**乐观锁**，因为它只会在数据被其他客户端抢先修改的情况下通知执行了这个命令的客户端，而不会阻止其他客户端对数据进行修改。

WATCH,MULTI,EXEC组成的事务不具有可扩展性，因为程序在尝试完成一个事务的时候，可能因为事务执行失败而反复重试。

<!-- more--> 	

#### 1.简易锁

锁出现不正常行为的原因：

* 持有锁的进程因为长操作时间过长而导致=锁被自动释放，但进程本身不知晓，可能会错误地释放掉其他进程拥有的锁
* 一个持有锁并打算执行长时间操作的进程已经崩溃，但其他想要获取锁的进程不知道哪个进程拥有锁，也无法检测持有锁的进程已经崩溃，会造成时间浪费
* 一个进程持有的锁过期后，多个进程尝试获取这个锁，并且都获得了锁

> **命令：SETNX key value**
>
> 将 `key` 的值设为 `value` ，当且仅当 `key` 不存在。
>
> 若给定的 `key` 已经存在，则 [SETNX](http://redisdoc.com/string/setnx.html#setnx) 不做任何动作。
>
> SETNX是『SET if Not eXists』(如果不存在，则 SET)的简写。

SETNX可以用来实现锁的获取功能，在代表锁的键不存在的情况下为键设置一个值，以此来获得锁；获取锁失败时，会在给定时限内重试。

```python
def acquire_lock(conn, lockname, acquire_timeout = 10):
    identifier = str(uuid.uuid4())
    end = time.time() + acquire_timeout
    #重复尝试直到超时或者获得锁
    while time.time() < end:
        if conn.setnx('lock:' + lockname, identifier):
            return identifier
        time.sleep(.001)
    return False
```

在程序执行期间，其他客户端可能会擅自对锁进行修改，因此要谨慎释放锁。

```python
def release_lock(conn, lockname, identifier):
    pipe = conn.pipeline(True)
    lockname = 'locked:'+identifier
    lockname = 'locked:'+lockname
    while True:
        try:
            #监视代表锁的键
            pipe.watch(lockname)
            #检查目前键的值是否和加锁时设置的值一样
            if pipe.get(lockname) == identifier:
                pipe.multi()
                pipe.delete(lockname)
                pipe.execute()
                return True

            pipe.unwatch()
            break
        except redis.exceptions.WatchError:#有其他客户端修改了锁，重试
            pass
    return False
```

#### 2. 带有超时限制特性的锁

上一小节的锁在持有者崩溃的时候不会自动释放，这将导致锁一直处于被获取的状态，本节将为锁加上超时限制。

程序在获得锁之后，调用EXPIRE命令来为锁设置过期时间，使得Redis可以自动删除锁。

```python
def acquire_lock_with_timeout(conn, lockname, acquire_timeout=10, lock_timeout=10):
    identifier = str(uuid.uuid4())
    lockname = "lock:" + lockname
    lock_timeout = int(math.ceil(lock_timeout))
    end = time.time() + acquire_timeout
    while time.time() < end:
        if conn.setnx(lockname, identifier):
            conn.expire(lockname, lock_timeout)
            return identifier
        #检查过期时间，并在需要时对其进行更新
        #以秒为单位，返回给定 key 的剩余生存时间(TTL, time to live)。
        elif not conn.ttl(lockname):
            conn.expire(lock_timeout)
        time.sleep(.001)
    return False
```

新的acquire_lock_with_timeout函数给锁增加了超时限制特性，这确保了锁总会在需要的时候被释放，而不会被一个客户端一直把持。

### 计数信号量

计数信号量是一种锁，可以让用户限制一项资源最多能同时被多少个进程访问，通常用于限定能够同时使用的资源数量。

计数信号量和普通锁的区别：当客户端获取锁失败时，通常会等待，而当客户端获取计数信号量失败时会立即返回失败结果。

#### 1. 构建基本计数信号量

为了将多个信号量持有者的信息都存储在同一个结构里，使用有序集合来构建计数信号量。

程序将为每个尝试获取信号量的进程生成一个唯一标识符，并将这个标识符用作有序信号量的成员，分值对应获取信号量的时间。

进场在尝试获取信号量时会生成一个标识符，并使用当前时间戳作为分值，并将标识符添加到有序集合里。接着进程会检查标识符在有序集合里的排名，若小于可获取信号量的总数，则表明获取成功，否则失败，他必须从有序集合里移除自己的标识符。

```python
def acquire_semaphore(conn, semname, limit, timeout = 10):
    identifier = str(uuid.uuid4())
    now = time.time()
    pipeline = conn.pipeline(True)
    #先移除有序集合中所有时间戳大雨超时数值的标识符
    pipeline.zremrangebyscore(semname, '-inf', now - timeout)
    pipeline.zadd(semname, identifier, now)
    pipeline.zrank(semname, identifier)
    if pipeline.execute()[-1] < limit:
        return identifier
    #获取失败，移除自己的标识符
    conn.zrem(semname, identifier)
    return None
```

上面这段代码实现的计数信号量假设进程访问到的系统时间都是相同的，但这在多主机环境下并不现实，因此可能会有系统时间满的进程偷走别人已经取得的信号量。

每当锁或者信号量因为系统始终的细微不同而导致锁的获取结果出现剧烈变化时，这个锁或者信号量就是不公平的。这会导致客户端永远无法获取本该得到的信号量。

#### 2. 公平信号量

为了尽可能的减少系统时间不一致带来的问题，需要给信号量实现添加一个计数器以及一个有序集合。其中计数器通过持续的执行自增操作，创建出一种类似于计时器的机制，确保最先对计数器执行自增操作的客户端能够获得信号量。程序会将计数器生成的值用作分值，存储到一个“信号量拥有者”的有序集合里，然后通过检查客户端生成的标识符在有序集合中的排名来判断客户端是否取得了信号量。公平信号量还会通过ZINTERSTORE命令和WEIGHTS参数，将信号量的超时时间传递给新的信号量拥有者有序集合。

> 默认情况下，destination中元素的score是各个有续集key中元素的score之和。使用weights为每个有续集指定个乘法因子，每个有续集的score在传递给集合函数（aggregate）之前，先乘以乘法因子。如果没指定乘法因子weight，默认是1

```python
def acquire_fair_semaphore(conn, semname, limit, timeout = 10):
    identifier = str(uuid.uuid4())
    czset = semname + ":owner"
    ctr = semname + ":counter"
    
    now = time.time()
    pipeline = conn.pipeline(True)
    #删除超时信号量
    pipeline.zremrangebyscore(semname, '-inf', now-timeout)
    #对超时有序集合和信号量拥有者有序集合求交集，将结果保存到信号量拥有者有序集合，指定weights
    pipeline.zinterstore(czset, {czset:1, semname:0})
    #对计数器执行自增操作，并获取自增后的值
    pipeline.incr(ctr)
    counter = pipeline.execute()[-1]
	#尝试获取信号量
    pipeline.zadd(semname, identifier, now)
    pipeline.zadd(czset, identifier, counter)
	#通过检查排名来判断客户端是否获得了信号量
    pipeline.zrank(czset, identifier)
    if pipeline.execute()[-1] < limit:
        return identifier
    #未获得信号量，清理无用数据
    pipeline.zrem(semname, identifier)
    pipeline.zrem(czset, identifier)
    pipeline.execute()
    return None
```

公平信号量的释放操作需要同时从信号量拥有者有序集合以及差事有序集合里面删除当前客户端的标识符。

```python
def release_fair_semaphore(conn, semname, identifier):
    pipeline = conn.pipeline(True)
    pipeline.zrem(semname, identifier)
    pipeline.zrem(semname+":owner", identifier)
    return pipeline.execute()[0]
```

上面的信号量的实现不要求所有主机都拥有相同的系统时间，但是各个主机的系统时间差距仍要控制在1-2s，从而避免信号量**过早释放**或**过晚释放**。

#### 3. 刷新信号量

前面的信号量实现默认只能设置10秒的超时时间，主要用于实现超时特性并掩盖自身潜在的缺陷，但是这点时间对于流API的使用者远远不够，因此要想办法对信号量进行刷新，防止其过期。

公平信号量将超时有序集合和信号量拥有者集合分开了，所以只需要对超时有序集合进行更新，就可以立即刷新信号量的超时时间。

```python
def refresh_fair_semaphore(conn, semname, identifier):
    if conn.zadd(semname, identifier, time.time()):
        #客户端已经失去了信号量
        release_fair_semaphore(conn, semname, identifier)
        return False
    return True
```

#### 4. 消除竞争条件

```python
def acquire_semaphore_with_lock(conn, semname, limit, timeout = 100):
    identifier = acquire_lock(conn, semname, acquire_timeout=.01)
    if identifier :
        try:
            return acquire_fair_semaphore(conn,semname, limit, timeout)
        finally:
            release_fair_semaphore(conn, semname, identifier)
```