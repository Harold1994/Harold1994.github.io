#!/bin/bash

comment=$1
echo $comment
`sudo git add .`
`sudo git commit -m $comment`
`sudo git push origin`
echo "上传结束"
