#!/bin/bash

comment=$1
echo $comment：
`sudo git add .`
`sudo git commit -m $comment`
`sudo git push origin`
`sudo hexo d -g`
exho "上传结束"