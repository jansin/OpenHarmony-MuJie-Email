# SDK开发手册
英文文档：[English](https://gitee.com/openharmony-sig/mail_base/blob/master/lib/README.en.md)

## 设计理念

本**SDK**为方便开发邮件客户端而开发。提供了标准邮件协议解析，MIME格式解析，MSG格式解析等邮件客户端相关的功能。

一般开发者只需要使用`MailEngine`, `IFolder`, `IMail`的接口，就可以完成基本的邮件客户端开发。

如果需要更细致的控制，可以直接使用`ImapStore`和`Pop3Store`这两个对象，都实现了`IStore`的接口，对邮件协议的进行简单的封装。可以通过该接口获取邮件正文、附件、属性等内容。

更底层的是`ImapProtocol`, `Pop3Protocol`, `SmtpProtocol`这些对象，分别对**IMAP**, **POP3**, **SMTP**协议进行封装，提供的接口也是根据协议中命令的名字，比如`retr`, `select`等。为需要对协议进行扩展，或者需要更灵活的控制的用户使用。

## 扩展设计

一般只需要使用`MailEngine`, `IFolder`, `IMail`接口来开发，这样邮件协议和网络连接等对开发者来说是透明的。可以通过注册`IStore`对象，让应用程序自由切换不同的协议或者网络连接。

## 目录结构图

```
代码根目录
 |
 +--- api.ts  // 接口定义
 |
 +--- engine
 |    |
 |    +--- engine.ts
 |    |
 |    +--- folder.ts
 |    |
 |    +--- mail.ts
 |
 +--- format
 |    |
 |    +--- cfb.ts
 |    |
 |    +--- eml.ts
 |    |
 |    +--- msg.ts
 |    |
 |    +--- msg_def.ts
 |    |
 |    +--- msg_property_tag.ts
 |    |
 |    +--- rtf
 |    |     |
 |    |     +--- byte_buffer.ts
 |    |     |
 |    |     +--- consts.ts
 |    |     |
 |    |     +--- documents.ts
 |    |     |
 |    |     +--- document_info.ts
 |    |     |
 |    |     +--- encoding.ts
 |    |     |
 |    |     +--- environments.ts
 |    |     |
 |    |     +--- fonts.ts
 |    |     |
 |    |     +--- font_table.ts
 |    |     |
 |    |     +--- layer_info.ts
 |    |     |
 |    |     +--- lex.ts
 |    |     |
 |    |     +--- reader.ts
 |    |     |
 |    |     +--- stack.ts
 |    |     |
 |    |     +--- string_builder.ts
 |    |     |
 |    |     +--- string_codec.ts
 |    |     |
 |    |     +--- text_container.ts
 |    |     |
 |    |     +--- text_reader.ts
 |    |     |
 |    |     +--- token.ts
 |    |     |
 |    |     +--- token_type.ts
 |
 +--- protocols
 |    |
 |    +--- protocol_base.ts
 |    |
 |    +--- imap_protocol.ts
 |    |
 |    +--- pop3_protocol.ts
 |    |
 |    +--- smtp_protocol.ts
 |    |
 |    +--- network.ts
 |    |
 |    +--- tokenizer.ts
 |
 +--- store
 |    |
 |    +--- store.ts
 |    |
 |    +--- imap_store.ts
 |    |
 |    +--- pop3_store.ts
 |    |
 |    +--- mem_store.ts
 |    |
 |    +--- mem_storage.ts
 |
 +--- transport
 |    |
 |    +--- transport.ts
 |
 +--- utils
 |    |
 |    +--- buffer_utils.ts
 |    |
 |    +--- common.ts
 |    |
 |    +--- encodings.ts
 |    |
 |    +--- file_stream.ts
 |    |
 |    +--- log.ts
 |    |
 |    +--- mime.ts
 |    |
 |    +--- pop3_utils.ts
 |
```

## 安装和使用

使用`ohpm`安装：

```bash
ohpm install @coremail/mail_base
```

在代码中引入：

```typescript
import type { IFolder, IMail, Properties, IStore } from "@coremail/mail_base";
import { MailEngine, ImapStore } from "@coremail/mail_base";
```

## `MailEngine`使用方法

使用时，首先需要创建一个`MailEngine`对象，设置相应的属性。一般需要设置

- `imap`： **IMAP**服务器的信息，包括`host`, `port`, `secure`字段，`secure`是布尔值，表示是否使用 SSL。
- `pop3`： **POP3**服务器的信息
- `smtp`： **SMTP**服务器的信息

`pop3`和`imap`只需要有一个就可以。

- `userInfo`: 登录服务器所需要的信息，目前就是`username`和`password`

然后通过`MailEngine`对象获取文件夹对象，再通过文件夹对象获取邮件。根文件夹只是概念上存在，用于方便文件夹管理，它下面不能存放邮件。

具体请看下面示例代码和注释。

### 初始化和登录检查

```typescript
const engine = new MailEngine();
engine.setProperties({
  imap: { host: host, port: 993, secure: true },
  smtp: { host: host, port: 25, secure: false },
  userInfo: { username: user, password: pass },
});
const store = engine.getStore();
const transport = engine.getTransport();
// 是否登录成功
const success = await Promise.all([store.check(), transport.check()])
  .then(v => true)
  .catch(e => false);
```

### 收取邮件以及邮件操作

```typescript
const engine = new MailEngine();
engine.setProperties({
  imap: { host: host, port: 993, secure: true },
  smtp: { host: host, port: 25, secure: false },
  userInfo: { username: user, password: pass },
});

// 得到收件箱对象
const inbox = await engine.getInbox();

// 得到前10封邮件
const mails = await inbox.getMailList(10, "", {
  by: "date",
  desc: true,
});

// 打印邮件内容
for (const mail of mails) {
  console.log(
    "==mail",
    mail.getId(),
    await mail.getSubject(),
    await mail.getFrom(),
    await mail.getTo(),
    await mail.getSize(),
    await mail.getDate()
  );
}

const mail = mails[0];

// 标记为重要邮件
mail.setFlagged(true);

// 将已读邮件设置成未读
if (mail.isSeen()) {
  mail.setSeen(false);
}

// 附件
const attachments = await mail.getAttachmentInfoList();
for (let i = 0; i < attachments.length; i++) {
  // 附件文件名：
  const name = getMimePartName(attachment[i]);

  // 附件内容：
  const content = await mail.getAttachment(i);
}

// 将邮件移动到另一个文件夹
const otherFolder = await engine.getFolder("文件夹名称").catch(e => null);
if (otherFolder) {
  mail.moveTo(otherFolder);
}

// 删除邮件
mail.delete();
```

### 文件夹

```typescript
const engine = new MailEngine();
engine.setProperties({
  imap: { host: host, port: 993, secure: true },
  smtp: { host: host, port: 25, secure: false },
  userInfo: { username: user, password: pass },
});

// 得到根目录对象，此目录下没有邮件
const root = await engine.getRootFolder();

// 得到子文件夹列表
const folders = await root.getSubFolders();

// 发件箱
const sent = folders.find(f => f.getType() == FolderType.sent);

// 收件箱
const inbox = folders.find(f => f.getType() == FolderType.inbox);

// 收件箱信息：邮件数
console.log(await inbox.getMailCount());

// 收件箱信息：未读邮件数
console.log(await inbox.getUnreadMailCount());

// 创建子文件夹
const folder = await inbox.createSubFolder("子文件夹名字");
// 重命名
folder.renameFolder("换个名字");
// 删除子文件夹
inbox.deleteSubFolder(folder.getName());
```

### 发送邮件

```typescript
const engine = new MailEngine();
engine.setProperties({
  imap: { host: host, port: 993, secure: true },
  smtp: { host: host, port: 25, secure: false },
  userInfo: { username: user, password: pass },
});
const transport = engine.getTransport();
const s = createBuffer({});
await transport.sendMail(
  { name: "fff", email: user }, // 发件人
  [{ name: "ggg", email: "ggg@607.net" }], // 收件人列表
  [], // 抄送列表
  [], // 暗送列表
  "test -- test", // 邮件标题
  `<p>hello world <img src="cid:abcdefgh" /></p>`, // 富文本正文
  "hello world", // 纯文本正文
  [{ fileName: "./tests/a.jpg", content: s, contentId: "abcdefgh" }], // 内联图片
  [{ fileName: "./tests/owl.jpg", content: s }] // 附件
);
```

## 直接使用`IStore`

```typescript
const store = new ImapStore();
store.setProperties({
  imap: { host: host, port: 993, secure: true },
  userInfo: { username: user, password: pass },
});
// 获取前10封邮件的id
const mailIdList = await store.getFolderMailIdList("INBOX", 1, 10, {
  by: "index",
  desc: false,
});
const mailBasic = await store.getMailBasic("INBOX", mailIdList[0]);
console.log(mailBasic.envelope);
```

### 检查服务器连接和账号信息

```typescript
const store = new ImapStore();
store.setProperties({
  imap: { host: host, port: 993, secure: true },
  userInfo: { username: user, password: pass },
});
store.check().then(() => {
  logger.info("success");
}).catch((err: CMError) => {
  if (err.code == ErrorCode.CONNECT_FAILED || err.code == ErrorCode.CONNECT_TIMEOUT) {
    logger.info("连接服务器超时或连接失败")
  } else if (err.code == ErrorCode.LOGIN_FAILED) {
    logger.info("登录失败，服务器返回:", err.message);
  }
};
```

## 使用**Callback**

**SDK**提供的都是基于`Promise`的接口。对于需要使用**Callback**风格的开发者，有两种方法：

- 使用系统标准库提供的`util.callbackWrapper`方法
- 使用**SDK**提供的`wrapCallback`方法

```typescript
import util from "@ohos.util";
// ... 创建engine，设置参数等省略
util.callbackWrapper(engine.getInbox.bind(engine))(
  (err: unknown, inbox: IFolder) => {
    util.callbackWrapper(inbox.getMailList.bind(inbox))(
      10,
      "",
      {
        by: "date",
        desc: true,
      },
      (err: unknown, mails: IMail[]) => {
        const mail = mails[0];
        util.callbackWrapper(mail.getFrom.bind(mail))(
          (err: unknown, address: EmailAddress) => {
            logger.info("发件人：", address);
          }
        );
      }
    );
  }
);
```

```typescript
import { wrapCallback } from "@coremail/utils/common";
// ... 创建engine，设置参数等省略
wrapCallback(
  engine.getInbox(),
  (inbox: IFolder) => {
    wrapCallback(
      inbox.getMailList(10, "", { by: "date", desc: true }),
      (mails: IMail[]) => {
        const mail = mails[0];
        wrapCallback(
          mail.getFrom(),
          (address: EmailAddress) => {
            logger.info("发件人：", address);
          },
          (err: unknown) => {
            // 获取收件人失败
          }
        );
      },
      (err: unknown) => {
        // 获取邮件失败
      }
    );
  },
  (err: unknown) => {
    // 获取收件箱失败
  }
);
```

**Callback**的使用比较不直观，推荐尽量使用`Promise`结合`async`和`await`，代码可读性更好。

## API

### 数据结构

#### `EmailAddress`<sup>1.0<sup>+</sup></sup>

收件人、发件人、抄送、暗送等邮件地址

| 属性名 | 类型   | 意义       | 必不为 undefined |
| ------ | ------ | ---------- | ---------------- |
| name   | string | 名称       | ✅               |
| email  | string | email 地址 | ✅               |

#### `MailEnvelope`<sup>1.0<sup>+</sup></sup>

信封数据，对应**IMAP**协议 _BODYSTRUCTURE_ 的返回数据，**POP3**协议需要从邮件**MIME**格式中解析出来

| 属性名  | 类型           | 意义       | 必不为 undefined |
| ------- | -------------- | ---------- | ---------------- |
| date    | Date           | 发送时间   | ✅               |
| subject | string         | 标题       | ✅               |
| from    | EmailAddress   | 发件人     | ✅               |
| to      | EmailAddress[] | 收件人列表 | ✅               |
| cc      | EmailAddress[] | 抄送列表   | ✅               |
| bcc     | EmailAddress[] | 暗送列表   | ✅               |

#### `MimeParams`<sup>1.0<sup>+</sup></sup>

**MIME**一个头信息的一些参数，比如 _Content-Type_ 和 _Content-Disposition_ 一般都会带有参数

| 属性名   | 类型   | 意义                             | 必不为 undefined |
| -------- | ------ | -------------------------------- | ---------------- |
| charset  | string | 字符集                           | ❌               |
| name     | string | 附件名字                         | ❌               |
| filename | string | 附件名字                         | ❌               |
| boundary | string | _multipart_ 类型的块分隔的字符串 | ❌               |

#### `MimeDisposition`<sup>1.0<sup>+</sup></sup>

**MIME**的*Content-Disposition*头信息

| 属性名 | 类型       | 意义 | 必不为 undefined |
| ------ | ---------- | ---- | ---------------- |
| type   | string     | 类型 | ✅               |
| params | MimeParams | 参数 | ✅               |

#### `ConentType`<sup>1.0<sup>+</sup></sup>

**MIME**的*Content-Type*头信息

| 属性名  | 类型       | 意义   | 必不为 undefined |
| ------- | ---------- | ------ | ---------------- |
| type    | string     | 类型   | ✅               |
| subType | string     | 子类型 | ✅               |
| params  | MimeParams | 参数   | ✅               |

#### `MailStructure`<sup>1.0<sup>+</sup></sup>

邮件结构。**MIME**的结构一般如下图：

```
+--------------------- multipart/mixed ---------------------------------+
| +--------- multipart/relative ----------------------+  +------------+ |
| | +------ multipart/alternative --+  +-----------+  |  | image/jpeg | |
| | | +------------+ +-----------+  |  | image/png |  |  | image/png  | |
| | | | text/plain | | text/html |  |  | image/gif |  |  | image/gif  | |
| | | +------------+ +-----------+  |  | other/mime|  |  | other/mime | |
| | +-------------------------------+  +-----------+  |  +------------+ |
| +---------------------------------------------------+                 |
+-----------------------------------+-----------------+-----------------+
```

| 属性名      | 类型            | 意义                                  | 必不为 undefined |
| ----------- | --------------- | ------------------------------------- | ---------------- |
| contentType | ContentType     | _Content-Type_                        | ✅               |
| disposition | MimeDisposition | _Content-Disposition_                 | ❌               |
| encoding    | string          | 传输编码，_Content-Transfer-Encoding_ | ❌               |
| contentId   | string          | 内联图片的 id _Content-ID_            | ❌               |
| partId      | string          | 当前 part 的编号，格式如：_1.2_, _2_  | ✅               |
| size        | number          | 邮件 Eml 的大小                       | ✅               |
| children    | MailStructure[] | 子节点                                | ✅               |

#### `MailBasic`<sup>1.0<sup>+</sup></sup>

邮件基本信息，包括邮件信封、结构、属性等

| 属性名     | 类型            | 意义 | 必不为 undefined |
| ---------- | --------------- | ---- | ---------------- |
| envelope   | MailEnvelope    | 信封 | ✅               |
| structure  | MailStructure   | 结构 | ✅               |
| attributes | MailAttribute[] | 属性 | ✅               |

### 一些常量

#### `MailAttribute`<sup>1.0<sup>+</sup></sup>

邮件属性

| 属性    | 意义 |
| ------- | ---- |
| Seen    | 已读 |
| Flagged | 重要 |
| Unknown | 未知 |

#### `ErrorCode`<sup>1.0<sup>+</sup></sup>

错误码

| 属性              | 意义                         |
| ----------------- | ---------------------------- |
| UNKNOWN_ERROR     | 未知错误				|
| PROTOCOL_ERROR    | 协议解析出错，一般是格式问题 |
| CONNECT_TIMEOUT   | 连接服务器超时		|
| CONNECT_FAILED    | 连接服务器失败		|
| LOGIN_FAILED      | 登录失败				|
| PARAMETER_ERROR   | 参数错误				|
| PARARMETER_MISSED | 参数缺失				 |
| SERVER_NOT_SUPPORT | 服务器连接异常		|
| SERVER_UN_REACHABLE | 服务器连接异常		|
| NO_AVAILABLE_NETWORK	| 网络不可用		|
| FOLDER_NOT_FOUND  | 找不到文件夹			|
| FOLDER_EXISTS		| 文件夹已存在			 |
| CREATE_FOLDER_FAILED | 创建文件夹失败	|
| PARSE_MIME_FAILED | 解析 MIME 格式出错	|
| IMAP_PARSER_FAILED | IMAP 解析失败		|
| IMAP_UNEXPECTED_END_OF_LINE	| IMAP 解析失败  |
| RTF_PARSER_FAILED	| RTF 解析失败，一般是未能支持的参数 |
| RTF_ARGMENT_OUT_OF_RANGE	| RTF 解析参数超出限制  |
| PARSE_RTF_FAILED	| 解析 RTF 格式出错	|
| MAIL_ATTRIBUTE_NOT_WRITABLE	| 未知异常	|
| MAIL_ATTRIBUTE_NOT_SUPPORT	| 未知异常	|
| MAIL_ATTRIBUTE_NOT_FOUND	| 未知异常		|
| MAIL_PART_NOT_FOUND	| 解析邮件失败		|
| PARSE_MAIL_FAILED	| 解析邮件内容出错	|
| MAIL_NOT_FOUND		| 找不到邮件		|
| ATTACHMENT_NOT_FOUND	| 找不到附件	|
| INLINE_IMAGE_NOT_FOUND | 找不到内联图片	|
| SENT_MAIL_FAILED	| 发送邮件失败		|
| DELETE_MAIL_FAILED | 删除邮件失败		|
| NOT_IMPLEMENTED	| 方法未实现		|
| NOT_SUPPORTED		| 方法或属性不支持	|

### `MailEngine` <sup>1.0<sup>+</sup></sup>

一个邮箱账号的封装，主要提供注册`IStore`, `ITransport`对象的接口，读取`IFolder`, `IMail`的接口等方法。

#### `setProperties(properties: Properties): void` <sup>1.0<sup>+</sup></sup>

设置引擎需要的参数。具体参考`Properties`的定义。

#### `getStore(): IStore` <sup>1.0<sup>+</sup></sup>

获取当前的`IStore`对象，如果不存在，则会抛出异常

#### `registerStore(store: IStore): void` <sup>1.0<sup>+</sup></sup>

注册`IStore`对象

#### `getTransport(): ITransport` <sup>1.0<sup>+</sup></sup>

获取当前的`ITransport`对象，如果不存在，则会抛出异常

#### `registerTransport(store: ITransport): void` <sup>1.0<sup>+</sup></sup>

注册`ITransport`对象

#### `search(keyword: string, types: ('subject' | 'attachment' | 'from' | 'to')[], start: number, size: number): Promise<IMail[]>` <sup>1.0<sup>+</sup></sup>

全局搜索邮件

#### `getRootFolder(): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

获取根文件夹

#### `getInbox(): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

获取收件箱

#### `getDraft(): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

获取草稿箱

#### `getFolder(folderFullName: string): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

根据文件夹路径获取文件夹对象

### `IFolder` <sup>1.0<sup>+</sup></sup>

文件夹对象

#### `getName(): string` <sup>1.0<sup>+</sup></sup>

获取文件夹的名字。这个名字是文件夹路径末尾的部分，既是末尾"/"后面的部分。

注：根据标准协议，并没有要求文件夹路径一定是以"/"进行分割，但是一般的实现都是以"/"进行分割，已经是一种事实上的标准

#### `getFullName(): string` <sup>1.0<sup>+</sup></sup>

获取文件夹全路径的名字

#### `getType(): FolderType` <sup>1.0<sup>+</sup></sup>

获取文件夹类型，具体看`FolderType`定义

#### `getMailCount(): Promise<number>` <sup>1.0<sup>+</sup></sup>

获取文件夹下面邮件总数

#### `getUnreadMailCount(): Promise<number>` <sup>1.0<sup>+</sup></sup>

获取文件夹下面未读邮件总数

#### `getMailList(size: number, startMailId?: string, order?: Order): Promise<IMail[]>` <sup>1.0<sup>+</sup></sup>

获取邮件列表

按照`order`指定的排序方式，获取`startMailId`后面，`size`指定数量的邮件列表。

标准协议没有按照时间排序或邮件大小排序的规定，所以对于`ImapStore`和`Pop3Store`，不支持排序。但是这个排序功能又是邮箱客户端的基础功能，所以 SDK 内部带了一个简单的`SyncStore`支持排序，但是需要使用`IMailStorage`，根据本地缓存来进行排序

#### `getSubFolders(): Promise<IFolder[]>` <sup>1.0<sup>+</sup></sup>

获取文件夹下面子文件夹列表

#### `getSubFolder(name: string): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

获取文件夹下面由`name`指定的子文件夹，不存在则返回 reject

#### `createSubFolder(name: string): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

创建子文件夹

#### `renameFolder(name: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

重命名文件夹

#### `deleteSubFolder(name: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

删除子文件夹

#### `getMail(mailId: string): Promise<IMail>`<sup>1.0<sup>+</sup></sup>

根据`mailId`获取邮件对象

#### `getMail(mailIndex: number, order: Order): Promise<IMail>`<sup>1.0<sup>+</sup></sup>

根据`order`指定的排序方式，获取`mailIndex`指定位置的邮件对象

#### `addMail(mime: string): Promise<string>`<sup>1.0<sup>+</sup></sup>

添加邮件到文件夹中

#### `searchMail(query: Omit<Query, "folder">): Promise<string[]>`<sup>1.0<sup>+</sup></sup>

搜索当前文件夹下的邮件

### `IMail`

一封邮件的抽象封装

#### `getId(): string`<sup>1.0<sup>+</sup></sup>

获取邮件 id

#### `getFrom(): Promise<EmailAddress>`<sup>1.0<sup>+</sup></sup>

获取发件人信息

#### `getTo(): Promise<EmailAddress[]>`<sup>1.0<sup>+</sup></sup>

获取收件人信息列表，可能为空数组

#### `getCc(): Promise<EmailAddress[]>`<sup>1.0<sup>+</sup></sup>

获取抄送信息列表，可能为空数组

#### `getBcc(): Promise<EmailAddress[]>`<sup>1.0<sup>+</sup></sup>

获取密送信息列表，一般为空数组

#### `getSubject(): Promise<string>`<sup>1.0<sup>+</sup></sup>

获取邮件标题，可能为空字符串。

#### `getDate(): Promise<Date>`<sup>1.0<sup>+</sup></sup>

获取邮件发送日期。返回`Date`对象。这个时间可能不准确

#### `getSize(): Promise<number>`<sup>1.0<sup>+</sup></sup>

获取邮件大小。此大小为邮件原始大小。

#### `getAttachmentInfoList(): Promise<MailStructure[]>`<sup>1.0<sup>+</sup></sup>

获取附件信息列表

#### `getInlineImageInfoList(): Promise<MailStructure[]>`<sup>1.0<sup>+</sup></sup>

获取内联图片信息列表

#### `getAttachment(index: number): Promise<IBuffer>`<sup>1.0<sup>+</sup></sup>

获取附件，参数为附件在附件信息列表里面的序号

#### `getInlineImage(index: number): Promise<IBuffer>`<sup>1.0<sup>+</sup></sup>

获取内联图片，参数为内联图片在内联图片列表里面的序号

#### `getHtml(): Promise<string>`<sup>1.0<sup>+</sup></sup>

获取邮件 html 正文，可能为空字符串

#### `getPlain(): Promise<string>`<sup>1.0<sup>+</sup></sup>

获取邮件纯文本正，可能为空字符串

#### `getDigest(num: number): Promise<string>`<sup>1.0<sup>+</sup></sup>

获取邮件摘要。至多`num`个字符。可能为空字符串

#### `isSeen(): Promise<boolean>`<sup>1.0<sup>+</sup></sup>

是否已读，返回`ture`表示已读，对于**IMAP**协议的*\Seen*属性，**POP3**邮件无此属性，需要模拟实现

#### `setSeen(isSeen: boolean): Promise<void>`<sup>1.0<sup>+</sup></sup>

设置已读属性，`isSeen`为`true`表示设置成已读

#### `isFlagged(): Promise<boolean>`<sup>1.0<sup>+</sup></sup>

是否设置为重要邮件，返回`true`表示是重要邮件。对应**IMAP**协议的*\Flagged*属性，**POP3**无此属性。需要模拟实现

#### `setFlagged(isFlagged: boolean): Promise<void>`<sup>1.0<sup>+</sup></sup>

设置重要属性，`isFlagged`为`true`表示设置成重要邮件

#### `getFolder(): IFolder; // 所属文件`<sup>1.0<sup>+</sup></sup>

获取邮件所在文件夹对象

### `IStore`

邮件读取、操作的接口

#### `setProperties(properties: Properties): void`<sup>1.0<sup>+</sup></sup>

设置属性

#### `check(): Promise<void>`<sup>1.0<sup>+</sup></sup>

检查配置是否正确，包括服务器连接是否正常，账号密码是否正确。

#### `supportedFeatures(): StoreFeature[]`<sup>1.0<sup>+</sup></sup>

获取支持的功能，参考 StoreFeature 的定义。目前主要是区分 IMAP 和 POP3 协议的功能

#### `hasFeature(feature: StoreFeature): boolean`<sup>1.0<sup>+</sup></sup>

是否支持某个功能

#### `sync?(): void`<sup>1.0<sup>+</sup></sup>

触发同步操作，同步操作会更新文件夹的邮件列表，更新邮件的属性等。 需要支持 StoreFeature.NeedToSync 才会被调用

#### `on( event: "new-mail", handler: (folderFullName: string, mailIdList: string[]) => void): void`<sup>1.0<sup>+</sup></sup>

- 新邮件通知，当有新邮件到达时，会触发该事件
- 回调函数的参数是文件夹夹名称和新邮件 id 列表

#### `on(event: string, handler: Function): void`<sup>1.0<sup>+</sup></sup>

- 其它事件，看具体 Store 对象的实现

#### `getMail(folderFullName: string, mailId: string): Promise<IBuffer>`<sup>1.0<sup>+</sup></sup>

获取邮件全部内容，包括头部、正文、附件等，是一个 MIME 格式的字符串

- @param folderFullName: 文件夹名称
- @param mailId: 邮件 id
- @return: 邮件内容，是一个 MIME 格式的字符串，使用 IBuffer 存储

#### `getMailPartContent( folderFullName: string, mailId: string, partId: string): Promise<IBuffer>`<sup>1.0<sup>+</sup></sup>

获取邮件部分内容，对于 multipart 的邮件，可以指定获取某个部分的内容

- partId 是一个字符串，格式是 1.2.3，表示获取第 1 个子部分的第 2 个子部分的第 3 个子部分的内容
- @param folderFullName: 文件夹名称
- @param mailId: 邮件 id
- @param partId: 邮件的部分 id
- @return: 返回对应的 part 的内容，不包括头部，未解码。使用时需要根据 MailStructure 来解码

#### `getMailBasic(folderFullName: string, mailId: string): Promise<MailBasic>`<sup>1.0<sup>+</sup></sup>

获取邮件的基本信息，包括信封、结构、属性等，参考 MailBasic 的定义

- @param folderFullName: 文件夹名称
- @param mailId: 邮件 id

#### `getMailIndex( folderFullName: string, mailId: string, order: Order): Promise<number>`<sup>1.0<sup>+</sup></sup>

- 获取邮件的序号，序号是一个数字，从 1 开始
- 如果 mailId 不是合法，或者找不到邮件，reject

#### `setMailAttributes( folderFullName: string, mailId: string, attributes: MailAttribute[], modifyType: "+" | "-" | ""): Promise<MailAttribute[]>`<sup>1.0<sup>+</sup></sup>

设置邮件的属性，返回设置后的属性列表

- @param folderFullName: 文件夹名称
- @param mailId: 邮件 id
- @param attributes: 邮件属性列表
- @param modifyType: "+"表示添加属性，"-"表示删除属性，""表示替换属性

#### `createSubFolder(folderName: string, parent: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

文件夹相关操作，需要支持 StoreFeature.Folder 才可以使用。 标准协议里面，IMAP 支持，POP3 不支持。

创建子文件夹

#### `renameFolder(folderName: string, newName: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

重命名文件夹

#### `deleteFolder(folderName: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

删除文件夹

#### `getAllFolderList(): Promise<FolderData[]>`<sup>1.0<sup>+</sup></sup>

获取全部文件夹列表

#### `getFolderList(parent: string): Promise<FolderData[]>`<sup>1.0<sup>+</sup></sup>

获取文件夹列表

#### `getFolderInfo(folderName: string): Promise<FolderData>`<sup>1.0<sup>+</sup></sup>

获取文件夹信息，参考 FolderData 的定义

#### `getFolderMailIdList( folderName: string, start: number, size: number, order: Order): Promise<string[]>`<sup>1.0<sup>+</sup></sup>

获取文件夹指定范围的邮件 id 列表

- @param folderName: 文件夹名称
- @param start: 开始的邮件序号，从 1 开始
- @param size: 获取邮件的数量
- @param order: 排序规则，参看 Order 的定义
- return: 邮件 id 列表

#### `moveMail( fromFolderFullName: string, mailId: string, toFolderFullName: string): Promise<string>`<sup>1.0<sup>+</sup></sup>

移动一封邮件到目标文件夹，返回邮件在新文件夹的 id

#### `addMail(mail: string, folderName: string): Promise<string>`<sup>1.0<sup>+</sup></sup>

往文件夹里添加邮件，返回邮件 id

#### `deleteMail(fromFolder: string, mailId: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

删除邮件

#### `filterMail(filter: Filter): Promise<Map<string, string[]>>`<sup>1.0<sup>+</sup></sup>

根据`filter`过滤邮件。用来实现**重要文件夹**等虚拟的文件夹

#### `searchMail(query: Query): Promise<string[]>`<sup>1.0<sup>+</sup></sup>

搜索邮件。目前只支持搜索标题、发件人、收件人、附件名字等。不支持正文搜索

### `ITransport`

发送邮件的接口

#### `setProperties(properties: Properties): void`<sup>1.0<sup>+</sup></sup>

设置属性

#### `check(): Promise<void>`<sup>1.0<sup>+</sup></sup>

检查配置是否正确

#### `sendMail( from: EmailAddress, toList: EmailAddress[], ccList: EmailAddress[], bccList: EmailAddress[], subject: string, richText: string, plainText: string, inlineImages: { content: IBuffer; fileName: string; contentId: string }[], attachments: { fileName: string; content: IBuffer}[]): Promise<void>`<sup>1.0<sup>+</sup></sup>

发送邮件

### 工具函数

#### `getLogger(name: string): Logger`<sup>1.0<sup>+</sup></sup>

获取一个`Logger`对象

#### `showDebugLog(show: boolean): void`<sup>1.0<sup>+</sup></sup>

设置是否输出调试日志

#### `setLogLevel(level: hilog.LogLevel): void`<sup>1.0<sup>+</sup></sup>

设置日志输出等级
