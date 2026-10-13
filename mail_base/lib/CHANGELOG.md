## 1.0.0-Canary6
1. 一些工程调整，目录结构等
2. bug修复

## 1.0.0-Canary5

1. 将SyncStore从sdk迁移到base模块
2. 一些bug修复

## 1.0.0-Canary4

bugfix:
1. POP3同步逻辑：重复文件夹、未读数显示错误等
2. IMAP使用短连接，请求完数据后关闭连接
3. 显式调用socket的close方法，否则会导致CPU高。

## 1.0.0-Canary3

bugfix：

1. 发信时分块发送数据，解决一次发送太多，底层 socket 报 4 错误的问题
2. 处理 SMTP 错误

## 1.0.0-Canary2

mail_base 开发者试用版本 Canary2

该版本实现功能如下：

**标准邮件协议 SDK 主要支持特性如下：**

1.  支持标准协议（IMAP、POP3、SMTP）服务器配置、连接
2.  支持邮件收信、发信、读信、搜索等核心功能
3.  支持文件夹管理和操作
