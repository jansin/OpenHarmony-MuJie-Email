# SDK develop document
Chinese document：[中文文档](https://gitee.com/openharmony-sig/mail_base/blob/master/lib/README.md)

## Design concept

This SDK is developed to facilitate the development of email clients. It provides functions related to email clients such as parsing standard email protocols, MIME format parsing, and MSG format parsing.

Generally, developers only need to use the interfaces of `MailEngine`, `IFolder`, and `IMail` to complete the basic development of an email client.。

For more granular control, developers can directly utilize the `ImapStore` and `Pop3Store` objects, both of which implement the `IStore` interface. This interface provides a simplified encapsulation of email protocols, allowing access to email content such as the body, attachments, properties, and more through the interface.

At a lower level, objects such as `ImapProtocol`, `Pop3Protocol`, and `SmtpProtocol` encapsulate the **IMAP**, **POP3**, and **SMTP** protocols, respectively. The interfaces provided are based on the command names found in the respective protocols, such as `retr`, `select`, and others. These are intended for users who need to extend the protocols or require more flexible control.

## Extensible Design

Generally, developers only need to use the `MailEngine`, `IFolder`, and `IMail` interfaces for development, making email protocols and network connections transparent to them. By registering `IStore` objects, the application can freely switch between different protocols or network connections.

## Directory Structure Diagram

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

## Installation and Usage

Installation using `ohpm`：

```bash
ohpm install @coremail/mail_base
```

Reference in the code.：

```typescript
import type { IFolder, IMail, Properties, IStore } from "@coremail/mail_base";
import { MailEngine, ImapStore } from "@coremail/mail_base";
```

## `MailEngine` useage

When using, first create a 'MailEngine' object and set the corresponding properties. Usually, you need to set:

- `imap`: Information for the IMAP server, including `host`, `port`, `secure` fields, where `secure` is a boolean indicating whether to use SSL.
- `pop3`: Information for the POP3 server.
- `smtp`: Information for the SMTP server.

Only one of `pop3` and `imap` is required.

- `userInfo`: Information required for logging into the server, currently consisting of `username` and `password`.

Then, retrieve folder objects through the `MailEngine` object, and subsequently, retrieve emails through the folder objects. The root folder is merely a conceptual entity used for convenient folder management; it cannot store emails directly beneath it.

You can refer to the following code example for details..

### Initialization and login verification

```typescript
const engine = new MailEngine();
engine.setProperties({
  imap: { host: host, port: 993, secure: true },
  smtp: { host: host, port: 25, secure: false },
  userInfo: { username: user, password: pass },
});
const store = engine.getStore();
const transport = engine.getTransport();
// Check if the login is successful
const success = await Promise.all([store.check(), transport.check()])
  .then(v => true)
  .catch(e => false);
```

### Retrieve emails and perform email operations

```typescript
const engine = new MailEngine();
engine.setProperties({
  imap: { host: host, port: 993, secure: true },
  smtp: { host: host, port: 25, secure: false },
  userInfo: { username: user, password: pass },
});

// Get the inbox object
const inbox = await engine.getInbox();

// Get the first 10 emails
const mails = await inbox.getMailList(10, "", {
  by: "date",
  desc: true,
});

// Print the content of the email
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

// Mark as important email
mail.setFlagged(true);

// Mark read emails as unread
if (mail.isSeen()) {
  mail.setSeen(false);
}

// attachments
const attachments = await mail.getAttachmentInfoList();
for (let i = 0; i < attachments.length; i++) {
  // attachment name：
  const name = getMimePartName(attachment[i]);

  // attachments content：
  const content = await mail.getAttachment(i);
}

// Move the email to another folder
const otherFolder = await engine.getFolder("文件夹名称").catch(e => null);
if (otherFolder) {
  mail.moveTo(otherFolder);
}

// Delete the email
mail.delete();
```

### Folder

```typescript
const engine = new MailEngine();
engine.setProperties({
  imap: { host: host, port: 993, secure: true },
  smtp: { host: host, port: 25, secure: false },
  userInfo: { username: user, password: pass },
});

// Get the root folder object, which contains no emails
const root = await engine.getRootFolder();

// Get the list of subfolders
const folders = await root.getSubFolders();

// Sent folder
const sent = folders.find(f => f.getType() == FolderType.sent);

// Inbox folder
const inbox = folders.find(f => f.getType() == FolderType.inbox);

// Inbox information: number of emails
console.log(await inbox.getMailCount());

// Inbox information: number of unread emails
console.log(await inbox.getUnreadMailCount());

// Create a subfolder
const folder = await inbox.createSubFolder("Subfolder Name");
// Rename
folder.renameFolder("New Name");
// Delete the subfolder
inbox.deleteSubFolder(folder.getName());
```

### Send Email

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
  { name: "Sender Name", email: user }, // Sender
  [{ name: "Recipient Name", email: "recipient@example.com" }], // Recipient list
  [], // CC list
  [], // BCC list
  "test -- test", // Email subject
  `<p>hello world <img src="cid:abcdefgh" /></p>`, // HTML body
  "hello world", // Plain text body
  [{ fileName: "./tests/a.jpg", content: s, contentId: "abcdefgh" }], // Inline images
  [{ fileName: "./tests/owl.jpg", content: s }] // Attachments
);
```

## Using `IStore` Directly

```typescript
const store = new ImapStore();
store.setProperties({
  imap: { host: host, port: 993, secure: true },
  userInfo: { username: user, password: pass },
});
// Get the IDs of the first 10 emails
const mailIdList = await store.getFolderMailIdList("INBOX", 1, 10, {
  by: "index",
  desc: false,
});
const mailBasic = await store.getMailBasic("INBOX", mailIdList[0]);
console.log(mailBasic.envelope);
```

### Check Server Connection and Account Information

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
    logger.info("Connection timeout or connection failed.")
  } else if (err.code == ErrorCode.LOGIN_FAILED) {
    logger.info("Login failed. Server response:", err.message);
  }
};
```
## Using Callback

The SDK provides interfaces based on `Promise`. For developers who prefer to use the callback style, there are two methods:

- Use the `util.callbackWrapper` method provided by standard lib.
- Use the `wrapCallback` method provided by this SDK.

```typescript
import util from "@ohos.util";
// ... Engine creation, parameter setting, etc., are omitted
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
            logger.info("Sender:", address);
          }
        );
      }
    );
  }
);
```

```typescript
import { wrapCallback } from "@coremail/utils/common";
// ... Engine creation, parameter setting, etc., are omitted
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
            logger.info("Sender:", address);
          },
          (err: unknown) => {
            // Failed to get sender
          }
        );
      },
      (err: unknown) => {
        // Failed to get emails
      }
    );
  },
  (err: unknown) => {
    // Failed to get inbox
  }
);
```

Using callbacks can make the code less intuitive. It's recommended to use `Promise` with `async` and `await` as much as possible for better code readability.

## API

Sure, here's the translation of the provided text into English without any contextual associations:

---

## Data Structures

### `EmailAddress`

Recipient, sender, CC, BCC, and other email addresses.

| Attribute | Type   | Meaning     | Required |
| ------    | ------ | ----------- | -------- |
| name      | string | Name        | ✅       |
| email     | string | Email Address | ✅      |

### `MailEnvelope`

Envelope data, corresponding to the BODYSTRUCTURE returned by the IMAP protocol, needs to be parsed from the MIME format for the POP3 protocol.

| Attribute | Type           | Meaning          | Required |
| --------- | -------------- | ---------------- | -------- |
| date      | Date           | Sending time     | ✅       |
| subject   | string         | Subject          | ✅       |
| from      | EmailAddress   | Sender           | ✅       |
| to        | EmailAddress[] | Recipient list   | ✅       |
| cc        | EmailAddress[] | CC list          | ✅       |
| bcc       | EmailAddress[] | BCC list         | ✅       |

### `MimeParams`

Parameters of a MIME header, such as Content-Type and Content-Disposition, usually come with parameters.

| Attribute | Type   | Meaning                            | Required |
| --------- | ------ | ---------------------------------- | -------- |
| charset   | string | Character set                      | ❌       |
| name      | string | Attachment name                    | ❌       |
| filename  | string | Attachment name                    | ❌       |
| boundary  | string | String for multipart type splitting| ❌       |

### `MimeDisposition`

Content-Disposition header information in MIME format.

| Attribute | Type        | Meaning   | Required |
| --------- | ----------- | --------- | -------- |
| type      | string      | Type      | ✅       |
| params    | MimeParams  | Parameters| ✅       |

### `ContentType`

Content-Type header information in MIME format.

| Attribute | Type        | Meaning   | Required |
| --------- | ----------- | --------- | -------- |
| type      | string      | Type      | ✅       |
| subType   | string      | Subtype   | ✅       |
| params    | MimeParams  | Parameters| ✅       |

### `MailStructure`

Email structure, usually in the following MIME format:

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

| Attribute   | Type            | Meaning                 | Required |
| ----------- | --------------- | ------------------------| -------- |
| contentType | ContentType     | Content-Type            | ✅       |
| disposition | MimeDisposition | Content-Disposition     | ❌       |
| encoding    | string          | Transmission encoding   | ❌       |
| contentId   | string          | Inline image ID         | ❌       |
| partId      | string          | Current part number     | ✅       |
| size        | number          | Eml size                | ✅       |
| children    | MailStructure[] | Child nodes             | ✅       |

### `MailBasic`

Basic email information, including envelope, structure, and attributes.

| Attribute   | Type            | Meaning          | Required |
| ----------- | --------------- | -----------------| -------- |
| envelope    | MailEnvelope    | Envelope data    | ✅       |
| structure   | MailStructure   | Structure        | ✅       |
| attributes  | MailAttribute[] | Attributes       | ✅       |



### Some Constants

#### `MailAttribute`<sup>1.0<sup>+</sup></sup>

Mail attributes

| Attribute | Meaning |
| --------- | ------- |
| Seen      | Read    |
| Flagged   | Important |
| Unknown   | Unknown |

#### `ErrorCode`<sup>1.0<sup>+</sup></sup>

Error codes

| Attribute             | Meaning                           |
| --------------------- | --------------------------------- |
| UNKNOWN_ERROR         | Unknown error                     |
| PROTOCOL_ERROR        | Protocol parsing error, usually format issue |
| CONNECT_TIMEOUT       | Connection to server timed out    |
| CONNECT_FAILED        | Connection to server failed       |
| LOGIN_FAILED          | Login failed                      |
| PARAMETER_ERROR       | Parameter error                   |
| PARAMETER_MISSED      | Parameter missing                 |
| SERVER_NOT_SUPPORT    | Server connection abnormal        |
| SERVER_UN_REACHABLE   | Server connection abnormal        |
| NO_AVAILABLE_NETWORK  | Network not available             |
| FOLDER_NOT_FOUND      | Folder not found                  |
| FOLDER_EXISTS         | Folder already exists             |
| CREATE_FOLDER_FAILED  | Failed to create folder           |
| PARSE_MIME_FAILED     | Parsing MIME format error         |
| IMAP_PARSER_FAILED    | IMAP parsing failed               |
| IMAP_UNEXPECTED_END_OF_LINE | IMAP parsing failed        |
| RTF_PARSER_FAILED     | RTF parsing failed, usually unsupported parameter |
| RTF_ARGMENT_OUT_OF_RANGE | RTF parsing parameter out of range |
| PARSE_RTF_FAILED      | Parsing RTF format error          |
| MAIL_ATTRIBUTE_NOT_WRITABLE | Unknown exception            |
| MAIL_ATTRIBUTE_NOT_SUPPORT  | Unknown exception            |
| MAIL_ATTRIBUTE_NOT_FOUND    | Unknown exception            |
| MAIL_PART_NOT_FOUND        | Failed to parse email        |
| PARSE_MAIL_FAILED          | Error parsing email content  |
| MAIL_NOT_FOUND             | Email not found              |
| ATTACHMENT_NOT_FOUND       | Attachment not found         |
| INLINE_IMAGE_NOT_FOUND     | Inline image not found       |
| SENT_MAIL_FAILED           | Failed to send email         |
| DELETE_MAIL_FAILED         | Failed to delete email       |
| NOT_IMPLEMENTED            | Method not implemented       |
| NOT_SUPPORTED              | Method or attribute not supported |


### `MailEngine` <sup>1.0<sup>+</sup></sup>

Encapsulation of an email account, primarily providing interfaces for registering `IStore`, `ITransport` objects, and methods for reading `IFolder`, `IMail`, etc.

#### `setProperties(properties: Properties): void` <sup>1.0<sup>+</sup></sup>

Sets the parameters required by the engine. Refer to the definition of `Properties` for details.

#### `getStore(): IStore` <sup>1.0<sup>+</sup></sup>

Gets the current `IStore` object, throwing an exception if it doesn't exist.

#### `registerStore(store: IStore): void` <sup>1.0<sup>+</sup></sup>

Registers an `IStore` object.

#### `getTransport(): ITransport` <sup>1.0<sup>+</sup></sup>

Gets the current `ITransport` object, throwing an exception if it doesn't exist.

#### `registerTransport(store: ITransport): void` <sup>1.0<sup>+</sup></sup>

Registers an `ITransport` object.

#### `search(keyword: string, types: ('subject' | 'attachment' | 'from' | 'to')[], start: number, size: number): Promise<IMail[]>` <sup>1.0<sup>+</sup></sup>

Global search for emails.

#### `getRootFolder(): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

Obtains the root folder.

#### `getInbox(): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

Obtains the inbox folder.

#### `getDraft(): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

Obtains the drafts folder.

#### `getFolder(folderFullName: string): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

Gets a folder object based on the folder path.

### `IFolder` <sup>1.0<sup>+</sup></sup>

Folder object.

#### `getName(): string` <sup>1.0<sup>+</sup></sup>

Gets the folder's name. This name is the last part of the folder path, i.e., the part after the last "/".

Note: According to the standard protocol, there is no requirement for folder paths to be delimited by "/", but most implementations use "/" as the delimiter, which has become a de facto standard.

#### `getFullName(): string` <sup>1.0<sup>+</sup></sup>

Gets the full name of the folder, including the entire path.

#### `getType(): FolderType` <sup>1.0<sup>+</sup></sup>

Gets the folder type, as defined by `FolderType`.

#### `getMailCount(): Promise<number>` <sup>1.0<sup>+</sup></sup>

Gets the total number of emails in the folder.

#### `getUnreadMailCount(): Promise<number>` <sup>1.0<sup>+</sup></sup>

Gets the total number of unread emails in the folder.

#### `getMailList(size: number, startMailId?: string, order?: Order): Promise<IMail[]>` <sup>1.0<sup>+</sup></sup>

Gets a list of emails.

Gets a specified number of emails, starting after the `startMailId`, according to the specified `order`.

Standard protocols do not specify the order of emails by time or size, so sorting is not supported for `ImapStore` and `Pop3Store`. However, the sorting feature is fundamental for email clients, so the SDK internally provides a simple `SyncStore` to support sorting, but it requires the use of `IMailStorage` to sort based on local cache.

#### `getSubFolders(): Promise<IFolder[]>` <sup>1.0<sup>+</sup></sup>

Fetches a list of subfolders under the current folder.

#### `getSubFolder(name: string): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

Fetches the subfolder specified by `name` under the current folder. Returns a rejection if the folder does not exist.

#### `createSubFolder(name: string): Promise<IFolder>` <sup>1.0<sup>+</sup></sup>

Creates a subfolder with the specified `name`.

#### `renameFolder(name: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

Renames the folder.

#### `deleteSubFolder(name: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

Deletes the specified subfolder.

#### `getMail(mailId: string): Promise<IMail>`<sup>1.0<sup>+</sup></sup>

Gets the email object based on the `mailId`.

#### `getMail(mailIndex: number, order: Order): Promise<IMail>`<sup>1.0<sup>+</sup></sup>

Gets the email object at the specified `mailIndex` position according to the specified `order`.

#### `addMail(mime: string): Promise<string>`<sup>1.0<sup>+</sup></sup>

Adds an email to the folder.

#### `searchMail(query: Omit<Query, "folder">): Promise<string[]>`<sup>1.0<sup>+</sup></sup>

Searches for emails in the current folder based on the provided query.

### `IMail`

An abstraction for representing an email message.

#### `getId(): string`<sup>1.0<sup>+</sup></sup>

Gets the ID of the email.

#### `getFrom(): Promise<EmailAddress>`<sup>1.0<sup>+</sup></sup>

Gets the sender's information.

#### `getTo(): Promise<EmailAddress[]>`<sup>1.0<sup>+</sup></sup>

Gets the list of recipients. May return an empty array.

#### `getCc(): Promise<EmailAddress[]>`<sup>1.0<sup>+</sup></sup>

Gets the list of CC recipients. May return an empty array.

#### `getBcc(): Promise<EmailAddress[]>`<sup>1.0<sup>+</sup></sup>

Gets the list of BCC recipients. Typically an empty array.

#### `getSubject(): Promise<string>`<sup>1.0<sup>+</sup></sup>

Gets the email subject. May return an empty string.

#### `getDate(): Promise<Date>`<sup>1.0<sup>+</sup></sup>

Gets the date the email was sent. Returns a `Date` object. This date might not be accurate.

#### `getSize(): Promise<number>`<sup>1.0<sup>+</sup></sup>

Gets the size of the email. This size refers to the original email size.

#### `getAttachmentInfoList(): Promise<MailStructure[]>`<sup>1.0<sup>+</sup></sup>

Gets the list of attachment information.

#### `getInlineImageInfoList(): Promise<MailStructure[]>`<sup>1.0<sup>+</sup></sup>

Gets the list of inline image information.

#### `getAttachment(index: number): Promise<IBuffer>`<sup>1.0<sup>+</sup></sup>

Gets the attachment specified by its index in the attachment information list.

#### `getInlineImage(index: number): Promise<IBuffer>`<sup>1.0<sup>+</sup></sup>

Gets the inline image specified by its index in the inline image information list.

#### `getHtml(): Promise<string>`<sup>1.0<sup>+</sup></sup>

Gets the HTML content of the email. May return an empty string.

#### `getPlain(): Promise<string>`<sup>1.0<sup>+</sup></sup>

Gets the plain text content of the email. May return an empty string.

#### `getDigest(num: number): Promise<string>`<sup>1.0<sup>+</sup></sup>

Gets a digest of the email. Returns a maximum of `num` characters. May return an empty string.

#### `isSeen(): Promise<boolean>`<sup>1.0<sup>+</sup></sup>

Checks if the email has been read. Returns `true` if it has been read. For **IMAP** protocol, based on the *\Seen* attribute; for **POP3**, this attribute is not available and needs to be simulated.

#### `setSeen(isSeen: boolean): Promise<void>`<sup>1.0<sup>+</sup></sup>

Sets the "seen" attribute of the email. Set `isSeen` to `true` to mark it as read.

#### `isFlagged(): Promise<boolean>`<sup>1.0<sup>+</sup></sup>

Checks if the email is flagged as important. Returns `true` if it is flagged. For **IMAP** protocol, based on the *\Flagged* attribute; **POP3** does not have this attribute and needs to be simulated.

#### `setFlagged(isFlagged: boolean): Promise<void>`<sup>1.0<sup>+</sup></sup>

Sets the "flagged" attribute of the email. Set `isFlagged` to `true` to mark it as important.

#### `getFolder(): IFolder`<sup>1.0<sup>+</sup></sup>

Gets the folder to which the email belongs.

### `IStore`

Interface for reading and manipulating emails.

#### `setProperties(properties: Properties): void`<sup>1.0<sup>+</sup></sup>

Sets properties for the store.

#### `check(): Promise<void>`<sup>1.0<sup>+</sup></sup>

Checks if the configuration is correct, including server connectivity and credentials.

#### `supportedFeatures(): StoreFeature[]`<sup>1.0<sup>+</sup></sup>

Gets the supported features, based on `StoreFeature` definition. Mainly distinguishes between IMAP and POP3 protocol features.

#### `hasFeature(feature: StoreFeature): boolean`<sup>1.0<sup>+</sup></sup>

Checks if a feature is supported.

#### `sync?(): void`<sup>1.0<sup>+</sup></sup>

Triggers synchronization, updating the email list in folders and updating email attributes. This is called if `StoreFeature.NeedToSync` is supported.

#### `on(event: "new-mail", handler: (folderFullName: string, mailIdList: string[]) => void): void`<sup>1.0<sup>+</sup></sup>

- New email notification. Triggered when new emails arrive.
- Callback parameters: folder name and list of new email IDs.

#### `on(event: string, handler: Function): void`<sup>1.0<sup>+</sup></sup>

- Other events, depending on the specific Store implementation.

#### `getMail(folderFullName: string, mailId: string): Promise<IBuffer>`<sup>1.0<sup>+</sup></sup>

Gets the entire content of an email, including headers, body, and attachments, in MIME format.

#### `getMailPartContent( folderFullName: string, mailId: string, partId: string): Promise<IBuffer>`<sup>1.0<sup>+</sup></sup>

Gets a part of the email content specified by `partId`. For multipart emails, this allows retrieval of specific parts.

#### `getMailBasic(folderFullName: string, mailId: string): Promise<MailBasic>`<sup>1.0<sup>+</sup></sup>

Gets basic information about the email, including envelope, structure, and attributes.

#### `getMailIndex( folderFullName: string, mailId: string, order: Order): Promise<number>`<sup>1.0<sup>+</sup></sup>

Gets the index of the email, starting from 1.

#### `setMailAttributes( folderFullName: string, mailId: string, attributes: MailAttribute[], modifyType: "+" | "-" | ""): Promise<MailAttribute[]>`<sup>1.0<sup>+</sup></sup>

Sets attributes for the email, returning the updated attribute list.

#### `createSubFolder(folderName: string, parent: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

Creates a subfolder.

#### `renameFolder(folderName: string, newName: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

Renames a folder.

#### `deleteFolder(folderName: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

Deletes Folder

#### `getAllFolderList(): Promise<FolderData[]>`<sup>1.0<sup>+</sup></sup>

Gets a list of all folders.

#### `getFolderList(parent: string): Promise<FolderData[]>`<sup>1.0<sup>+</sup></sup>

Gets a list of folders.

#### `getFolderInfo(folderName: string): Promise<FolderData>`<sup>1.0<sup>+</sup></sup>

Gets information about a specific folder, referring to the definition of `FolderData`.

#### `getFolderMailIdList( folderName: string, start: number, size: number, order: Order): Promise<string[]>`<sup>1.0<sup>+</sup></sup>

Gets the list of mail IDs in a folder within the specified range.

- `folderName`: The name of the folder.
- `start`: The starting mail index, starting from 1.
- `size`: The number of mails to retrieve.
- `order`: The sorting order, as defined by `Order`.
- Returns: A list of mail IDs.

#### `moveMail( fromFolderFullName: string, mailId: string, toFolderFullName: string): Promise<string>`<sup>1.0<sup>+</sup></sup>

Moves an email to a target folder, returning the email ID in the new folder.

#### `addMail(mail: string, folderName: string): Promise<string>`<sup>1.0<sup>+</sup></sup>

Adds an email to a folder, returning the email ID.

#### `deleteMail(fromFolder: string, mailId: string): Promise<void>`<sup>1.0<sup>+</sup></sup>

Deletes an email.

#### `filterMail(filter: Filter): Promise<Map<string, string[]>>`<sup>1.0<sup>+</sup></sup>

Filters emails based on the specified filter, such as implementing virtual folders like "Important".

#### `searchMail(query: Query): Promise<string[]>`<sup>1.0<sup>+</sup></sup>

Searches for emails. Currently supports searching by subject, sender, recipient, and attachment names. Does not support searching the email body.

### `ITransport`

Interface for sending emails.

#### `setProperties(properties: Properties): void`<sup>1.0<sup>+</sup></sup>

Sets properties for the transport.

#### `check(): Promise<void>`<sup>1.0<sup>+</sup></sup>

Checks if the configuration is correct.

#### `sendMail( from: EmailAddress, toList: EmailAddress[], ccList: EmailAddress[], bccList: EmailAddress[], subject: string, richText: string, plainText: string, inlineImages: { content: IBuffer; fileName: string; contentId: string }[], attachments: { fileName: string; content: IBuffer}[]): Promise<void>`<sup>1.0<sup>+</sup></sup>

Sends an email.

### Utility Functions

#### `getLogger(name: string): Logger`<sup>1.0<sup>+</sup></sup>

Gets a `Logger` object.

#### `showDebugLog(show: boolean): void`<sup>1.0<sup>+</sup></sup>

Sets whether to display debug logs.

#### `setLogLevel(level: hilog.LogLevel): void`<sup>1.0<sup>+</sup></sup>

Sets the log output level.
