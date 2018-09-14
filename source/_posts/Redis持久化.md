---
title: Redis持久化
date: 2018-09-14 22:06:09
tags: [NoSQL, Redis, 大数据]
---

redis持久化：

- 快照：将存在于某一时刻的所有数据都写入硬盘，适用于即使丢失一部分数据也不会造成问题的程序
- 只追加文件（AOF）：在执行写命令时，将被执行的写命令复制到硬盘

数据存到硬盘的原因：

- 为了在之后重用数据
- 防止数据丢失，做备份

快照持久化：Redis可以通过创建快照来获得存储在内存中的数据某个时间点上的副本，可迁移到其他服务器，也可以保留到本地.若系统、redis、硬件三者之一崩了，redis会丢失最新一次快照之后写入的所有数据

<!-- more-->

**1. 快照方式：**

- 客户端发送BGSAVE，redis创建子进程将快照写入硬盘
- 客户端发送SAVE，redis将停下来创建快照，不响应其他命令（不常用）
- 设置save选项，如save 60 10000,一旦满足从上次快照算起，60秒内有10000次写入，就自动创建快照
- Redis接收到SHUTDOWN或TERM信号时，会执行SAVE命令，执行后关闭
- 当一个Redis服务器（从服务器）连接另一个Redis服务器（主服务器），并向对方发送SYNC命令开始复制时，主服务器会执行BGSAVE命令

在处理日志过程中记录处理日志文件的名字和偏移量：

```python
import redis
import os
import unittest
import uuid
import time

#将被处理日志信息写入redis
#callback回调函数接受一个redis连接和一个日志行做参数
def process_logs(conn, path, callback):
    #获取当前文件处理进度
    current_file, offset = conn.mget('progress:file','progress:position')
    pipe = conn.pipeline()
    #如果在一个内部函数里，对在外部作用域（但不是在全局作用域）的变量进行引用，那么内部函数就被认为是闭包
    #更新正在处理的日志文件的名字和偏移量
    def update_progress():
        pipe.mset({
            'progress:file':fname,
            'progress:position':offset
        })
        pipe.execute()

    for fname in sorted(os.listdir(path)):
        #略过已处理日志文件
        if fname < current_file:
            continue
        inp = open(os.path.join(path, fname),'rb')

        #在接着处理一个因为崩溃而未完成处理的日志文件时，略过已处理内容
        if fname == current_file:
            inp.seek(int(offset,10))
        else:
            offset = 0
        current_file = None

        for lno, line in enumerate(inp):
            #处理日志行
            callback(pipe, line)
            offset += int(offset) + len(line)
            if not (lno+1)%1000:
                update_progress()
            update_progress()
            inp.close()
```

**2.AOF持久化**

AOF持久化将被执行的写命令写到AOF文件末尾，Redis只需要从头到尾执行一次AOF文件包含的所有命令，就可以恢复AOF文件记录的数据集。

通过appendfsync配置可以设置AOF持久化同步频率，有三种选项：

- always：每个命令都写入硬盘，会降低Redis速度
- everysec：每秒执行一次同步，显示将写命令同步到硬盘，推荐
- no: 让操作系统决定何时同步，不推荐

若AOF文件体积非常大，那么还原操作执行时间会非常长

**3.Redis复制的启动过程**

从服务器在连接一个主服务器的时候，主服务器会创建一个快照发送到从服务器，具体步骤如下：

| 步骤 | 主服务器                                                     | 从服务器                                                     |
| ---- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 1    | 等待命令进入                                                 | 连接(重连接)主服务器，发送SYNC命令                           |
| 2    | 开始执行BGSAVE，使用缓冲区记录BGSAVE后执行的所有写命令       | 根据配置选项决定继续使用现有数据来处理客户端请求，还是向客户端返回错误 |
| 3    | BGSAVE执行完毕，向从服务器发送快照文件，并在发送期间继续使用缓冲区记录被执行的写命令 | **丢弃所有旧数据**，开始载入主服务器发来的快照文件           |
| 4    | 快照文件发送完毕，开始向从服务器发送存储在缓冲区里的写命令   | 完成对快照文件的解释操作，像往常一样开始接受命令请求         |
| 5    | 缓冲区存储的写命令发送完毕，从现在开始，每执行一个写命令，就向从服务器发送相同的写命令 | 执行主服务器发来的所有缓冲区里的写命令，从现在开始，执行主服务器发来的每个写命令 |

注意：Redis不支持主主复制

**4.检验硬盘写入**

- 验证主服务器是否已经将写数据发送至从服务器：

  ​	用户在向主服务器写入真正的数据之后，再向*主服务器*写入一个**唯一的虚构值**，通过检查虚构值是否存在于从服务器来判断写数据是否到达从服务器。

- 验证数据是否被写入硬盘

  ​	以每秒同步一次AOF文件的Redis服务器来说，检查INFO命令的输出结果中aof_pending_bio_fsync属性值是否为0，为0表示服务器将已知数据写入了硬盘。主服务器写入数据后，下面代码可以自动检查写入硬盘操作：

  ```python
  #以主从服务器连接作为参数
  def wait_for_sync(mconn, sconn):
      identifier  =str(uuid.uuid4())
      #添加令牌到主服务器
      mconn.add('sync:wait',identifier, time.time())
      #等待从服务器完成同步
      while not sconn.info()['master_link_status'] != 'up':  #slave端可查看它与master之间同步状态,当复制断开后表示down
          time.sleep(0.05)
      #等待从服务器接受数据更新
      while not sconn.zscore('sync:wait', identifier):
          time.sleep(.001)
      deadline = time.time() + 1.01#最多等一秒
      while time.time()<deadline:
          #aof_pending_bio_fsync表示后台I/O队列里面，等待执行的fsync调用数量
          if sconn.info()['aof_pending_bio_fsync'] == 0:
              break
          time.sleep(.001)
      # 清理刚刚创建的新令牌以及之前的令牌
      mconn.zrem('sync:wait', identifier)
      mconn.zremrangebyscore('sync:wait', 0, time.time()-900)
  ```

关于info的信息，从[另一篇博客中](https://blog.csdn.net/mysqldba23/article/details/68066322)借用以下内容：

**Server(服务器信息)**

redis_version:3.0.0                              #redis服务器版本
redis_git_sha1:00000000                  #Git SHA1
redis_git_dirty:0                                    #Git dirty flag
redis_build_id:6c2c390b97607ff0    #redis build id
redis_mode:cluster                              #运行模式，单机或者集群
os:Linux 2.6.32-358.2.1.el6.x86_64 x86_64 #redis服务器的宿主操作系统
arch_bits:64                                         #架构(32或64位)
multiplexing_api:epoll                        #redis所使用的事件处理机制
gcc_version:4.4.7                                #编译redis时所使用的gcc版本
process_id:12099                               #redis服务器进程的pid
run_id:63bcd0e57adb695ff0bf873cf42d403ddbac1565  #redis服务器的随机标识符(用于sentinel和集群)
tcp_port:9021                                #redis服务器监听端口
uptime_in_seconds:26157730   #redis服务器启动总时间，单位是秒
uptime_in_days:302                    #redis服务器启动总时间，单位是天
hz:10                                #redis内部调度（进行关闭timeout的客户端，删除过期key等等）频率，程序规定serverCron每秒运行10次。
lru_clock:14359959      #自增的时钟，用于LRU管理,该时钟100ms(hz=10,因此每1000ms/10=100ms执行一次定时任务)更新一次。
config_file:/redis_cluster/etc/9021.conf  #配置文件路径



**Clients(已连接客户端信息)**
connected_clients:1081       #已连接客户端的数量(不包括通过slave连接的客户端)
client_longest_output_list:0 #当前连接的客户端当中，最长的输出列表，用client list命令观察omem字段最大值
client_biggest_input_buf:0   #当前连接的客户端当中，最大输入缓存，用client list命令观察qbuf和qbuf-free两个字段最大值
blocked_clients:0                   #正在等待阻塞命令(BLPOP、BRPOP、BRPOPLPUSH)的客户端的数量

\# Memory(内存信息)
used_memory:327494024                 #由redis分配器分配的内存总量，以字节为单位
used_memory_human:312.32M       #以人类可读的格式返回redis分配的内存总量
used_memory_rss:587247616         #从操作系统的角度，返回redis已分配的内存总量(俗称常驻集大小)。这个值和top命令的输出一致
used_memory_peak:1866541112    #redis的内存消耗峰值(以字节为单位) 
used_memory_peak_human:1.74G #以人类可读的格式返回redis的内存消耗峰值
used_memory_lua:35840                   #lua引擎所使用的内存大小(以字节为单位)
mem_fragmentation_ratio:1.79          #used_memory_rss和used_memory之间的比率，小于1表示使用了swap，大于1表示碎片比较多
mem_allocator:jemalloc-3.6.0            #在编译时指定的redis所使用的内存分配器。可以是libc、jemalloc或者tcmalloc



**# Persistence(rdb和aof的持久化相关信息)**
loading:0                                                    #服务器是否正在载入持久化文件
rdb_changes_since_last_save:28900855 #离最近一次成功生成rdb文件，写入命令的个数，即有多少个写入命令没有持久化
rdb_bgsave_in_progress:0                  #服务器是否正在创建rdb文件
rdb_last_save_time:1482358115        #离最近一次成功创建rdb文件的时间戳。当前时间戳 - rdb_last_save_time=多少秒未成功生成rdb文件
rdb_last_bgsave_status:ok                   #最近一次rdb持久化是否成功
rdb_last_bgsave_time_sec:2                #最近一次成功生成rdb文件耗时秒数
rdb_current_bgsave_time_sec:-1        #如果服务器正在创建rdb文件，那么这个域记录的就是当前的创建操作已经耗费的秒数
aof_enabled:1                                          #是否开启了aof
aof_rewrite_in_progress:0                     #标识aof的rewrite操作是否在进行中
aof_rewrite_scheduled:0              
#rewrite任务计划，当客户端发送bgrewriteaof指令，如果当前rewrite子进程正在执行，那么将客户端请求的bgrewriteaof变为计划任务，待aof子进程结束后执行rewrite 
aof_last_rewrite_time_sec:-1            #最近一次aof rewrite耗费的时长
aof_current_rewrite_time_sec:-1      #如果rewrite操作正在进行，则记录所使用的时间，单位秒
aof_last_bgrewrite_status:ok             #上次bgrewriteaof操作的状态
aof_last_write_status:ok                     #上次aof写入状态
aof_current_size:4201740                 #aof当前尺寸
aof_base_size:4201687                    #服务器启动时或者aof重写最近一次执行之后aof文件的大小
aof_pending_rewrite:0                       #是否有aof重写操作在等待rdb文件创建完毕之后执行?
aof_buffer_length:0                             #aof buffer的大小
aof_rewrite_buffer_length:0              #aof rewrite buffer的大小
aof_pending_bio_fsync:0                  #后台I/O队列里面，等待执行的fsync调用数量

aof_delayed_fsync:0                          #被延迟的fsync调用数量

**Stats(一般统计信息)**
total_connections_received:209561105 #新创建连接个数,如果新创建连接过多，过度地创建和销毁连接对性能有影响，说明短连接严重或连接池使用有问题，需调研代码的连接设置
total_commands_processed:2220123478  #redis处理的命令数
instantaneous_ops_per_sec:279                  #redis当前的qps，redis内部较实时的每秒执行的命令数
total_net_input_bytes:118515678789          #redis网络入口流量字节数
total_net_output_bytes:236361651271       #redis网络出口流量字节数
instantaneous_input_kbps:13.56                  #redis网络入口kps
instantaneous_output_kbps:31.33               #redis网络出口kps
rejected_connections:0                                   #拒绝的连接个数，redis连接个数达到maxclients限制，拒绝新连接的个数
sync_full:1                                                          #主从完全同步成功次数
sync_partial_ok:0                                             #主从部分同步成功次数
sync_partial_err:0                                            #主从部分同步失败次数
expired_keys:15598177                                #运行以来过期的key的数量
evicted_keys:0                                                 #运行以来剔除(超过了maxmemory后)的key的数量
keyspace_hits:1122202228                          #命中次数
keyspace_misses:577781396                     #没命中次数
pubsub_channels:0                                       #当前使用中的频道数量
pubsub_patterns:0                                         #当前使用的模式的数量
latest_fork_usec:15679                                 #最近一次fork操作阻塞redis进程的耗时数，单位微秒
migrate_cached_sockets:0                          #

**Replication(主从信息，slave上显示的信息)**

role:slave                                        #实例的角色，是master or slave
master_host:192.168.64.102       #此节点对应的master的ip
master_port:9021                          #此节点对应的master的port
master_link_status:up                   #slave端可查看它与master之间同步状态,当复制断开后表示down
master_last_io_seconds_ago:0  #主库多少秒未发送数据到从库?
master_sync_in_progress:0        #从服务器是否在与主服务器进行同步
slave_repl_offset:6713173818   #slave复制偏移量
slave_priority:100                          #slave优先级
slave_read_only:1                         #从库是否设置只读
connected_slaves:0                      #连接的slave实例个数
master_repl_offset:0         
repl_backlog_active:0                  #复制积压缓冲区是否开启
repl_backlog_size:134217728   #复制积压缓冲大小
repl_backlog_first_byte_offset:0 #复制缓冲区里偏移量的大小
repl_backlog_histlen:0           #此值等于 master_repl_offset - repl_backlog_first_byte_offset,该值不会超过repl_backlog_size的大小