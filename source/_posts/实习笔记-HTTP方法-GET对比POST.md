---
title: '实习笔记----HTTP方法:GET对比POST'
date: 2018-05-09 22:52:42
tags: [HTTP, 随笔, Java] 
---
## 什么是 HTTP？

超文本传输协议（HTTP）的设计目的是保证客户机与服务器之间的通信。

HTTP 的工作方式是客户机与服务器之间的请求-应答协议。

web 浏览器可能是客户端，而计算机上的网络应用程序也可能作为服务器端。
<!-- more-->
举例：客户端（浏览器）向服务器提交 HTTP 请求；服务器向客户端返回响应。响应包含关于请求的状态信息以及可能被请求的内容。

## 两种 HTTP 请求方法：GET 和 POST

在客户机和服务器之间进行请求-响应时，两种最常被用到的方法是：GET 和 POST。

- *GET* - 从指定的资源请求数据。
- *POST* - 向指定的资源提交要被处理的数据

## GET 方法

请注意，查询字符串（名称/值对）是在 GET 请求的 URL 中发送的：

```
/test/demo_form.asp?name1=value1&name2=value2
```

有关 GET 请求的其他一些注释：

- GET 请求可被缓存
- GET 请求保留在浏览器历史记录中
- GET 请求可被收藏为书签
- GET 请求不应在处理敏感数据时使用
- GET 请求有长度限制
- GET 请求只应当用于取回数据

## POST 方法

请注意，查询字符串（名称/值对）是在 POST 请求的 HTTP 消息主体中发送的：

```
POST /test/demo_form.asp HTTP/1.1
Host: xxx.com
name1=value1&name2=value2
```

有关 POST 请求的其他一些注释：

- POST 请求不会被缓存
- POST 请求不会保留在浏览器历史记录中
- POST 不能被收藏为书签
- POST 请求对数据长度没有要求

## 比较 GET 与 POST

下面的表格比较了两种 HTTP 方法：GET 和 POST。

|                  | GET                                                          | POST                                                         |
| ---------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 后退按钮/刷新    | 无害                                                         | 数据会被重新提交（浏览器应该告知用户数据会被重新提交）。     |
| 书签             | 可收藏为书签                                                 | 不可收藏为书签                                               |
| 缓存             | 能被缓存                                                     | 不能缓存                                                     |
| 编码类型         | application/x-www-form-urlencoded                            | application/x-www-form-urlencoded 或 multipart/form-data。为二进制数据使用多重编码。 |
| 历史             | 参数保留在浏览器历史中。                                     | 参数不会保存在浏览器历史中。                                 |
| 对数据长度的限制 | 是的。当发送数据时，GET 方法向 URL 添加数据；URL 的长度是受限制的（URL 的最大长度是 2048 个字符）。 | 无限制。                                                     |
| 对数据类型的限制 | 只允许 ASCII 字符。                                          | 没有限制。也允许二进制数据。                                 |
| 安全性           | 与 POST 相比，GET 的安全性较差，因为所发送的数据是 URL 的一部分。在发送密码或其他敏感信息时绝不要使用 GET ！ | POST 比 GET 更安全，因为参数不会被保存在浏览器历史或 web 服务器日志中。 |
| 可见性           | 数据在 URL 中对所有人都是可见的。                            | 数据不会显示在 URL 中。                                      |

## 其他 HTTP 请求方法

下面的表格列出了其他一些 HTTP 请求方法：

| 方法    | 描述                                              |
| ------- | ------------------------------------------------- |
| HEAD    | 与 GET 相同，但只返回 HTTP 报头，不返回文档主体。 |
| PUT     | 上传指定的 URI 表示。                             |
| DELETE  | 删除指定资源。                                    |
| OPTIONS | 返回服务器支持的 HTTP 方法。                      |
| CONNECT | 把请求连接转换到透明的 TCP/IP 通道。              |

## Java HTTP请求方式：

常用的HTTP库有HttpClient和HttpURLConnection，先来看两个例子再比较两种库。

- HttpURLConnection

  HttpURLConnection一般步骤：创建URL对象 ==》 获取URL的HttpURLConnection对象实例==》设置HTTP请求使用的方法==》设置超时和消息头==》对服务器响应码判断==》获得服务器返回的输入流==》关掉HTTP连接

  **GET请求**

```java
  URL url = new URL("xxx");
  //调用URL对象的openConnection( )来获取HttpURLConnection对象实例
  HttpURLConnection conn = (HttpURLConnection) url.openConnection();
  //请求方法为GET
  conn.setRequestMethod("GET");
  //设置连接超时为5秒
  conn.setConnectTimeout(5000);
  //服务器返回东西了，先对响应码判断
  if (conn.getResponseCode() == 200) {
      //用getInputStream()方法获得服务器返回的输入流
      InputStream in = conn.getInputStream();
      byte[] data = read(in); //流转换为二进制数组，read()自己写的是转换方法
      String html = new String(data, "UTF-8");
      System.out.println(html);
      in.close();
  }
```

  **POST请求**

  POST请求：POST请求大体和GET一致，只是设置相关参数的时候要注意设置允许输入、输出，还有POST方法不能缓存，要手动设置为false.

```java
  //创建URL对象,xxx是服务器API
  URL url = new URL("xxx");
  //调用URL对象的openConnection( )来获取HttpURLConnection对象实例
  HttpURLConnection conn = (HttpURLConnection) url.openConnection();
  //请求方法为GET
  conn.setRequestMethod("POST");
  //设置连接超时为5秒
  conn.setConnectTimeout(5000);
  //允许输入输出
  conn.setDoInput(true);
  conn.setDoOutput(true);
  //不能缓存
  conn.setUseCaches(false);
  //至少要设置的两个请求头
  conn.setRequestProperty("Content-Type","application/x-www-form-urlencoded");
  //输出流包含要发送的数据,要注意数据格式编码
  OutputStream op=conn.getOutputStream();//此时才发送http请求
  op.write(new String("name=zharold").getBytes());
  //服务器返回东西了，先对响应码判断
  if (conn.getResponseCode() == 200) {
      //用getInputStream()方法获得服务器返回的输入流
      InputStream in = conn.getInputStream();
      byte[] data = read(in); //流转换为二进制数组，read()是转换方法
      String html = new String(data, "UTF-8");
      System.out.println(html);
      in.close();
  }
```

> 说明：
>
> > - HttpURLConnection对象不能直接构造，需要通过URL类中的openConnection()方法来获得。
> > - HttpURLConnection的connect()函数，实际上**只是建立了一个与服务器的TCP连接**，并没有实际发送HTTP请求。HTTP请求实际上直到我们获取服务器响应数据（如调用getInputStream()、getResponseCode()等方法）时才正式发送出去。
> > - 对HttpURLConnection对象的配置都需要在connect()方法执行之前完成。
> > - HttpURLConnection是基于HTTP协议的，其底层通过socket通信实现。如果不设置超时（timeout），在网络异常的情况下，可能会导致程序僵死而不继续往下执行。
> > - HTTP正文的内容是通过OutputStream流写入的， **向流中写入的数据不会立即发送到网络，而是存在于内存缓冲区中，待流关闭时，根据写入的内容生成HTTP正文**。
> > - 调用getInputStream()方法时，返回一个输入流，用于从中读取服务器对于HTTP请求的返回信息。
> > - 我们可以使用HttpURLConnection.connect()方法手动的发送一个HTTP请求，但是如果要获取HTTP响应的时候，请求就会自动的发起，比如我们使用HttpURLConnection.getInputStream()方法的时候，所以完全没有必要调用connect()方法。

- HttpClient

  HttpClient的使用步骤：创建HttpClient对象==》创建Http请求对象（GET、POST不同）==》设置请求参数==》执行请求==》获取响应对象==》对响应对象处理==》关闭相应对象==》关闭HttpClient

  **GET请求**

  ```java
  //构造uri
  URI uri = new URIBuilder()
          .setScheme("https")
          .setHost("xxx")
          .setPath("/xxx")
          .setParameter("key1", "value1")
          .setParameter("key2", "value2")
          .build();
  //创建httpclient对象
  CloseableHttpClient client = HttpClients.createDefault();
  //创建GET对象
  HttpGet httpget = new HttpGet(uri);
  //执行请求
  CloseableHttpResponse response = client.execute(httpget);
  if (response.getStatusLine().getStatusCode() == 200 ) {
      HttpEntity entity = response.getEntity();
      String detail = EntityUtils.toString(entity, "utf-8");
      System.out.println(detail);

  }
  response.close();
  client.close();
  ```

  **POST请求**

  POST一般用于提交一些特别的东西，内容多种多样，HttpClient针对不同内容提供了不同的数据容器，如最常见的字符串（StringEntity），字节数组（ByteArrayEntity），输入流（InputStreamEntity），和文件（FileEntity）,请注意`InputStreamEntity`是不可重复的，因为它只能从底层数据流中读取一次。一般建议实现一个自定义`HttpEntity`类，而不是使用泛型`InputStreamEntity`。 

  ```java
  public String postInfo(String infoType, String aimUrl, String jsonBody) {
          System.out.println(infoType + "发送数据");
  		String str = "";
  		CloseableHttpClient httpclient = HttpClients.createDefault();
  		HttpPost httpPost = new HttpPost(aimUrl);
  		//DES加密
  		byte[] encrypt = SecureUtil.des(HexUtil.decodeHex(ZhengzhouData.DES)).encrypt(jsonBody);
  		//apache.commons.codec.Base64 编码
  		String data = Base64.encodeBase64String(encrypt);
  		StringEntity strEntity = new StringEntity(data, "UTF-8");
  		httpPost.setEntity(strEntity);
  		strEntity.setContentEncoding("UTF-8");
  		strEntity.setContentType("application/json");
  		try {
  			CloseableHttpResponse response = httpclient.execute(httpPost);
  			if (response.getStatusLine().getStatusCode() == HttpStatus.SC_OK) {
  				str = EntityUtils.toString(response.getEntity(), "UTF-8");
  			}else {
                  throw new Exception("发送" + infoType + "信息异常 code : " + response.getStatusLine().getStatusCode());
              }
  			response.close();
  		} catch (Exception e) {
  			e.printStackTrace();
  		}
  		return str;
      }
  ```

  ​

 在一般情况下，如果只是需要向Web站点的某个简单页面提交请求并获取服务器响应，HttpURLConnection完全可以胜任。但在绝大部分情况下，Web站点的网页可能没这么简单，这些页面并不是通过一个简单的URL就可访问的，可能需要用户登录而且具有相应的权限才可访问该页面。在这种情况下，就需要涉及Session、Cookie的处理了，如果打算使用HttpURLConnection来处理这些细节，当然也是可能实现的，只是处理起来难度就大了。

为了更好地处理向Web站点请求，包括处理Session、Cookie等细节问题，Apache开源组织提供了一个HttpClient项目，看它的名称就知道，它是一个简单的HTTP客户端（并不是浏览器），可以用于发送HTTP请求，接收HTTP响应。但不会缓存服务器的响应，不能执行HTML页面中嵌入的Javascript代码；也不会对页面内容进行任何解析、处理。

简单来说，HttpClient就是一个增强版的HttpURLConnection，HttpURLConnection可以做的事情HttpClient全部可以做；HttpURLConnection没有提供的有些功能，HttpClient也提供了，但它只是关注于如何发送请求、接收响应，以及管理HTTP连接。
