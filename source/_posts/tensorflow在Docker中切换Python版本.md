---
title: [转]tensorflow在Docker中切换Python版本
date: 2018-07-06 22:45:47
tags: [tensorflow， 深度学习]
---

在 [TensorFlow 的 这个 Issue](https://link.jianshu.com?t=https%3A%2F%2Fgithub.com%2Ftensorflow%2Ftensorflow%2Fissues%2F10179) 可以看到，2017年5月已经支持[用 tag 提供不同的 image](https://link.jianshu.com?t=https%3A%2F%2Fhub.docker.com%2Fr%2Ftensorflow%2Ftensorflow%2Ftags%2F)。比如 `tensorflow/tensorflow:latest-py3` 就可以（安装并）打开 Python3 环境。

结合目录映射的需要，输入命令完成映射并在 python3 环境下打开：

<!-- more--> 	

```
docker run -it -p 8888:8888 -v ~/WorkStation/DeepLearning101-002/:/WorkStation/DeepLearning101-002 -w /WorkStation/DeepLearning101-002 tensorflow/tensorflow:latest-py3
```

然后用`docker ps -a`查看所有 image，然后使用命令 `docker rename CONTAINER ID XXX`，将默认的 Python2 的 image 重命名为 dl，将 Python3 的 image 重命名为 dlpy3：

```
CONTAINER ID        IMAGE                              COMMAND                  CREATED             STATUS                      PORTS               NAMES
f46533729239        tensorflow/tensorflow:latest-py3   "/run_jupyter.sh -..."   11 minutes ago      Exited (0) 6 minutes ago                        dlpy3
f7178713446b        tensorflow/tensorflow              "/run_jupyter.sh -..."   42 minutes ago      Exited (0) 15 minutes ago                       dl
```

以后就可以根据需要，打开不同 Python 环境的 image。

文章内容来自：https://www.jianshu.com/p/8779099784b2

 