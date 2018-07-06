---
title: [转]用Docker安装tensorflow
date: 2018-07-06 22:50:08
tags: [tensorflow,深度学习]
---

#### 1 关于TensorFlow

------

TensorFlow 随着AlphaGo的胜利也火了起来。google又一次成为大家膜拜的大神了。google大神在引导这机器学习的方向。 同时docker 也是一个非常好的工具，大大的方便了开发环境的构建，之前需要配置安装。 看各种文档，现在只要一个 pull 一个 run 就可以把环境弄好了。 同时如果有写地方需要个性化定制，直接在docker的镜像上面再加一层补丁就好了。 自己的需求就能满足了，同时还可以将这个通用的方法分享出去。

<!-- more--> 	

#### 2 下载TensorFlow images

------

使用hub.docker.com的镜像

```
docker pull tensorflow/tensorflow:latest1
```

使用daocloud 的镜像，在国内用速度还是挺快的，如果docker.io的镜像慢，可以用daocloud的。 
这个速度非常的快。一样用的。版本也挺新的。

```
docker pull daocloud.io/daocloud/tensorflow:latest 1
```

#### 3 启动镜像 

------

启动命令，设置端口，同时配置volume 数据卷，用于永久保存数据。加上 –rm 在停止的时候删除镜像。

```
sudo mkdir -p /data/tensorflow/notebooks
docker run -it --rm --name myts -v /data/tensorflow/notebooks:/notebooks -p 8888:8888 daocloud.io/daocloud/tensorflow:latest12
```

启动的时候并不是daemon 模式的，而是前台模式，同时显示了运行的日志。

```
W 06:48:13.425 NotebookApp] WARNING: The notebook server is listening on all IP addresses and not using encryption. This is not recommended.
[I 06:48:13.432 NotebookApp] Serving notebooks from local directory: /notebooks
[I 06:48:13.432 NotebookApp] 0 active kernels 
[I 06:48:13.432 NotebookApp] The Jupyter Notebook is running at: http://[all ip addresses on your system]:8888/?token=2031705799dc7a5d58bc51b1f406d8771f0fdf3086b95642
[I 06:48:13.433 NotebookApp] Use Control-C to stop this server and shut down all kernels (twice to skip confirmation).
[C 06:48:13.433 NotebookApp] 

    Copy/paste this URL into your browser when you connect for the first time,
    to login with a token:
        http://localhost:8888/?token=2031705799dc7a5d58bc51b1f406d8771f0fdf3086b9564212345678910
```

打开浏览器就可以直接看到界面了，同时可以编辑内容：。

#### 4 固定token

------

vi run_jupyter.sh

```
#!/usr/bin/env bash
jupyter notebook --no-browser --NotebookApp.token='token1234' > /notebooks/jupyter-notebook.log 12
```

然后重新打一个docker镜像。 
vi Dockerfile

```
FROM daocloud.io/daocloud/tensorflow:latest
RUN rm -f /run_jupyter.sh
COPY run_jupyter.sh /run_jupyter.sh
ENTRYPOINT ["/run_jupyter.sh"]1234
```

这样就固定token了。

```
docker build -t mytf:1.0 .
docker run -it --rm --name myts -v /data/tensorflow/notebooks:/notebooks -p 8888:8888 -d mytf:1.012
```

然后就可以 -d 参数，将docker 运行放到后台。然后就可以使用 docker exec -it xxx bash 登录进去查看系统的状况了。

#### 5 总结

docker 真的是非常好的技术，能够快速的搭建好环境，省去了繁琐的安装配置过程。 最后使用参数将环境跑起来，同时也可以根据自己的需求，给镜像增加新的功能，就像是盖房子。 一层一层的盖。所有的层，构成了一个整体的房子。 同时对于 TensorFlow 来说是一个程序员必须的技能了。就像是 lucence一样，其实大家都不太了解那个索引算法的。但是还是可以创建出一个索引分词来。 TensorFlow 也是一样的。当做一个工具来使用就好了，具体的算法也不太精通。 有一个说法，数据量上去了，用大数据优化，比算法优化要效果好。

文章来自：https://blog.csdn.net/freewebsys/article/details/70237003