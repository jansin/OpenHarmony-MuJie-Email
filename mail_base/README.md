# 标准邮件协议 SDK

英文文档：[English](https://gitee.com/openharmony-sig/mail_base/blob/master/README.en.md)

## 介绍

**mail_base**是专为**OpenHarmony**系统开发的标准邮件协议 SDK，采用纯**TypeScript**语言实现。本仓库包含标准邮件协议 SDK 源码和相关使用说明文档。

**SDK 主要支持特性如下：**

1. 支持邮件标准协议(**IMAP**, **POP3**, **SMTP**)：连接，登录，协议解析等
2. 支持MIME格式邮件的解析和组信
3. 支持MSG格式邮件的读取
4. 一套邮件客户端引擎的架构，方便扩展协议

标准协议的支持情况：

- **POP3**: 支持了`USER`, `PASS`, `STAT`, `LIST`, `UIDL`, `RETR`, `TOP`, `DELE`, `QUIT`, `NOOP`等指令
- **IMAP**: 支持了文件夹、邮件等操作的指令。
  - 通用：`CAPABILITY`, `LOGIN`, `LOGOUT`, `LIST`, `LSUB`, `UID`, `SEARCH`
  - 文件夹：`SELECT`, `STATUS`, `CREATE`, `RENAME`, `DELETE`, `CLOSE`
  - 邮件：`FETCH`, `COPY`, `EXPUNGE`, `APPEND`, `STORE`
  - 邮件属性：`Seen`, `Answered`, `Deleted`, `Flagged`, `Draft`, `Recent`
  - `FETCH`支持：`BODYSTRUCTURE`, `FLAGS`, `ENVELOPE`, `RFC822.SIZE`, `INTERNALDATE`, `BODY.PEEK[]`, `BODY[]`等的解析
- **SMTP**: 支持了`AUTH`, `MAIL FROM`, `RCPT TO`, `DATA`, `HELO`, `EHLO`, `QUIT`等指令

对MIME的支持：
- 支持`multipart/mixed`, `multipart/related`, `mulitipart/alternative`等复合格式
- 支持`Content-Type`, `Content-ID`, `Content-Disposition`, `Date`等头信息的解析
- 支持**base64**, **quoted-printable**, **utf7 IMAP**等格式的编解码

对MSG的支持：
- 支持**CFB**格式的读取
- 支持**MSG**格式常用字段信息的读取
- 支持**RTF**格式转成html

本SDK还定义了一套`MailEngine`, `IFoler`, `IMail`, `IStore`, `ITransport`等接口，为开发者提供方便易用的API接口，同时也屏蔽协议底层细节，扩展私有协议支持可以不影响上层应用。具体使用请查看[开发文档](https://gitee.com/openharmony-sig/mail_base/blob/master/lib/README.md)

## 安装使用

### 引用 ohos_mail_base SDK

1. ohpm 引用

```bash
ohpm install @coremail/mail_base
```

2. 源码引用

开发者可执行 clone 源码，将 **mail_base** 目录下的代码导入自己工程中引用，开发平台推荐 Dev Eco


## 更新日志（RleaseNote&ChangeLog）

点击查看更新日志：[更新日志](https://gitee.com/openharmony-sig/mail_base/blob/master/lib/CHANGELOG.md)


## 约束与限制

```
DevEco Studio：4.1 Canary2(4.1.3.401)

SDK：API11 Canary2(4.1.0.36)

OpenHarmony系统版本：2.1.3.5（Canary）
```


## 贡献代码

使用过程中发现任何问题都可以提[Issue](https://gitee.com/openharmony-sig/mail_base/issues)，当然，也非常欢迎发[PR](https://gitee.com/openharmony-sig/mail_base/pulls) 

### 二次开发
本项目只包括了SDK的代码和DevEco的instrumentTest的测试代码，本仓库不是一个完整的DevEco项目，无法在DevEco中打开。如果要对本仓库代码进行修改，请参考如下步骤：
1. git clone 本项目
2. 在DevEco中新建一个空项目，会自动生成一个entry类型的项目。
3. 将空项目中的.hvigor, AppScope, hvigor, build-profile.json5, hvigorfile.js, hvigorw, hvigorw.bat, oh-package.json5文件，复制到本项目的目录下。这样就可以使用DevEco打开。
4. 在DevEco中删除自动生成的那个entry类型的项目。修改build-profile.json5文件，将lib和test加上
然后就可以正常编译运行。

### 使用本SDK的项目

1. [mail-client](https://gitee.com/mouqx/mail-client/)

## 兼容测试的邮箱

邮箱服务商 | IMAP | POP3 | SMTP
--- | --- | --- | ---
139.com | ✅ | ✅ | ✅ 
189.com | ✅ | ✅ | ✅ 
wo.cn | ✅ | ✅ | ✅  
tom.com | ✅ | ✅ | ✅ 
aliyun.com | ✅ | ✅ | ✅ 
qq.com | ✅ | ✅ | ✅ 
foxmail.com | ✅ | ✅ | ✅ 
163.com | ✅ | ✅ | ✅ 
vip.163.com | ✅ | ✅ | ✅ 
126.com | ✅ | ✅ | ✅ 
vip.126.com | ✅ | ✅ | ✅ 
yeah.net | ✅ | ✅ | ✅ 
188.com | ✅ | ✅ | ✅ 
sina.com | ✅ | ✅ | ✅ 
sina.cn | ✅ | ✅ | ✅ 
sohu.com | ✅ | ✅ | ✅ 

## 开源协议

```
Copyright 2023 Coremail论客

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
