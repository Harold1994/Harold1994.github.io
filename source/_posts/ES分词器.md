---
title: ES分词器
date: 2018-06-04 00:15:12
tags: [ElasticSearch, 大数据]
---

ES逗号分词
1：新建分析器
```
curl -XPOST 'http://172.18.0.4:9200/demo/?pretty' -d '

{

　　"settings":

　　{

　　　　"analysis":
<!-- more--> 
　　　　　　{

　　　　　　　　"analyzer":

　　　　　　　　　　{

　　　　　　　　　　　　"douhao":

　　　　　　　　　　　　　　{

　　　　　　　　　　　　　　　　"type":"pattern",

　　　　　　　　　　　　　　　　"pattern":","

　　　　　　　　　　　　　　}

　　　　　　　　　　}

　　　　　　}

　　}

}'
```
 

2：将分析器mapping到新的字段上（旧的字段上是无法修改mapping），当然最好的办法是使用别名，可以零停机切换
```

curl -XPOST 'http://172.18.0.4:9200/demo/_mapping/master?pretty' -d '

{

　　"properties":

　　{

　　　　"master_id":

　　　　{

　　　　　　"type":"string",

　　　　　　"index":"not_analyzed"

　　　　},

　　　　"serve_regions":

　　　　{

　　　　　　"type":"string",

　　　　　　"analyzer":"douhao",

　　　　　　"search_analyzer":"douhao"

　　　　}

　　}

}'
```
 

3：同步MYSQL的数据到ES（或者手动添加两条数据）

curl -PUT 'http://172.18.0.4:9200/demo/master/?pretty' -d '{"master_id":"123","serve_regions":"1,2,3"}'

curl -PUT 'http://172.18.0.4:9200/demo/master/?pretty' -d '{"master_id":"321","serve_regions":"1"}'

curl -PUT 'http://172.18.0.4:9200/demo/master/?pretty' -d '{"master_id":"231","serve_regions":"2,3"}'

 

4：测试 http://172.18.0.4:9200/_plugin/head

 

参考文档

　　1：ES中如何使用逗号来分词[http://yangshangchuan.iteye.com/blog/2280720]
