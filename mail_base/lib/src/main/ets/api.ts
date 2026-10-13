/* Copyright © 2023 - 2024 Coremail论客
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


export type EmailAddress = {
  name: string;
  email: string;
};

/*
 * 一个支持流式读取的buffer，用于存储邮件正文、附件、内联附件等的内容
 * 默认实现是使用内存，对于大文件，会有内存占用问题。
 * 一般的实现是一个文件，但是也可以是一个数据库表，这个需要根据具体的情况来实现
 * 通过MailEngine的bufferCreator参数，可以使用自定义的IBuffer对象
 * 支持一边读取一边写入，支持随机读取
 */
export interface IBuffer {
  feed(data: string | Uint8Array): Promise<void>;
  end(data?: string | Uint8Array): Promise<void>;
  [Symbol.asyncIterator](): AsyncIterableIterator<string>;
  read(): AsyncIterableIterator<string>;
  readAll(): Promise<string>;
  getSize(): Promise<number>;

  readRaw(): AsyncIterableIterator<Uint8Array>;
  readAllRaw(): Promise<Uint8Array>;
  getSizeRaw(): Promise<number>;
}

export type BufferHint = {
  // 存放eml原文
  isEml?: boolean;
  // 存放附件
  isAttachment?: boolean;
  // 存放内联附件
  isInlineImage?: boolean;
  // 存放邮件正文
  isBody?: boolean;
  // 大小
  size?: number;
  // 使用文件存储
  useFile?: boolean;
  // Mime对象
  mime?: Mime;

  [key: string]: string | number | boolean | Mime;
};
export interface IBufferCreator {
  createBuffer(hint?: BufferHint): IBuffer;
}

export type InlineImage = {
  name: string;
  body: IBuffer;
  contentId: string;
  contentType: string;
  type: string;
  subType: string;
  size: number;
};
export type Attachment = {
  name: string;
  body: IBuffer;
  contentType: string;
  type: string;
  subType: string;
  size: number;
};

export interface IMail {
  getId(): string;

  getFrom(): Promise<EmailAddress>;
  getTo(): Promise<EmailAddress[]>;
  getCc(): Promise<EmailAddress[]>;
  getBcc(): Promise<EmailAddress[]>;
  getSubject(): Promise<string>;
  getDate(): Promise<Date>;
  getSize(): Promise<number>;

  getAttachmentInfoList(): Promise<MailStructure[]>;
  getInlineImageInfoList(): Promise<MailStructure[]>;

  getAttachment(index: number): Promise<IBuffer>;
  getInlineImage(index: number): Promise<IBuffer>;

  getHtml(): Promise<string>;
  getPlain(): Promise<string>;
  getDigest(num: number): Promise<string>;

  isSeen(): Promise<boolean>;
  setSeen(isSeen: boolean): Promise<void>;

  isFlagged(): Promise<boolean>;
  setFlagged(isFlagged: boolean): Promise<void>;

  isAnswered(): Promise<boolean>;
  setAnswered(isAnswered: boolean): Promise<void>;

  getAttributes(): Promise<MailAttribute[]>;
  setAttributes(attrs: MailAttribute[]): Promise<void>;

  getFolder(): IFolder; // 所属文件夹

  on(event: "flagged-changed", handler: (hasAttr: boolean) => void): void;
  on(event: "seen-changed", handler: (hasAttr: boolean) => void): void;
  on(
    event: "attr-changed",
    handler: (attr: MailAttribute, hasAttr: boolean) => void
  ): void;

  delete(): Promise<void>;
  moveTo(folder: IFolder): Promise<string>;
}

export type Order = {
  by: "date" | "size"; // 按照日期、大小排序
  desc: boolean; // 是否降序
};

export interface IFolder {
  getName(): string;
  getFullName(): string;
  getType(): FolderType;
  // 获取邮件列表
  /*
   * 获取邮件列表
   * @param size: 获取邮件的数量
   * @param startMailId: 开始的邮件id，如果不指定，则从最新的邮件开始
   * @param order: 排序规则，如果不指定，则按照日期倒序
   */
  getMailList(
    size: number,
    startMailId?: string,
    order?: Order
  ): Promise<IMail[]>;

  getMailCount(): Promise<number>;
  getUnreadMailCount(): Promise<number>;
  refresh(): Promise<void>;
  getRecentCount(): Promise<number>;
  getSubFolders(): Promise<IFolder[]>;
  getSubFolder(name: string): Promise<IFolder>;
  createSubFolder(name: string): Promise<IFolder>;
  renameFolder(name: string): Promise<void>;
  deleteSubFolder(name: string): Promise<void>;

  getMail(mailId: string): Promise<IMail>;
  getMail(mailIndex: number, order: Order): Promise<IMail>;
  getMailIndex(mailId: string, order: Order): Promise<number>;

  addMail(mime: string): Promise<string>;

  // 搜索当前文件夹及其子文件夹的邮件
  searchMail(query: Omit<Query, "folder">): Promise<string[]>; // 返回邮件id列表

  open(): Promise<string>;
  close(): Promise<void>;
  isOpen(): boolean;

  on(event: "new-mails", handler: (mail: IMail[]) => void): void;
  on(event: "mail-deleted", handler: (mailId: string) => void): void;
}

export enum MailAttribute {
  Seen,
  Flagged,
  Answered,
  Deleted,
  Draft,
  Recent
}

export interface MailEnvelope {
  date: Date;
  subject: string;
  from: EmailAddress;
  // sender: EmailAddress[],
  // reply_to: EmailAddress[],
  to: EmailAddress[];
  cc: EmailAddress[];
  bcc: EmailAddress[];
  // in_reply_to: EmailAddress[],
  messageId: string;
}

export type MimeParams = {
  charset?: string;
  name?: string;
  filename?: string;
  boundary?: string;
  [key: string]: string | undefined;
};

export type MimeDisposition = {
  type: string;
  params: MimeParams;
};

/*
 * 邮件结构，参考RFC 3501
 * https://tools.ietf.org/html/rfc3501#section-7.4.2
 * todo:
 * 本结构是根据RFC 3501定义的，还没有处理MESSAGE类型的数据
 */
export type MailStructure = {
  contentType: ContentType;
  disposition?: MimeDisposition;
  encoding?: string;
  contentId?: string;
  children: MailStructure[];
  partId: string;
  size: number;
};

export type Mime = Omit<MailStructure, 'children'> & {
  headers: Map<string, string>;
  body: IBuffer;
  children: Mime[];
}

export type ContentType = {
  type: string;
  subType: string;
  params: MimeParams;
};

export type MailDataAny = {
  id: string;
  envelope?: MailEnvelope;
  structure?: MailStructure;
  attributes?: MailAttribute[];
  size?: number;
  index?: number;
};

export type MailData = {
  envelope: MailEnvelope;
  structure: MailStructure;
  html: IBuffer;
  plain: IBuffer;
  inlineImages: InlineImage[];
  attachments: Attachment[];
};

export type MailBasic = {
  envelope: MailEnvelope;
  structure: MailStructure;
  attributes: MailAttribute[];
  id: string;
  // 邮件大小，单位是字节，由于MIME是纯ASCII文本，所以实际上也是字符数
  // 包括头部和正文
  size: number;
};

export interface IEmlParser {
  /*
   * 解析邮件
   * @param mime: 邮件的MIME格式字符串
   * @return: 返回解析后的邮件内容，参考MailData的定义
   */
  mimeParse(
    content: string | IBuffer
  ): Promise<Mime>;
}

export enum FolderType {
  root = 0,
  inbox = 1,
  draft,
  sent,
  trash,
  spam,
  archive,
  virus,
  other,

  virtual, // 这个之后的是虚拟文件夹
  important,
}

export type FolderData = {
  name: string;
  fullName: string;
  type?: FolderType;
  parent?: string;
  mailCount?: number;
  unreadCount?: number;
  recent?: number;
  mode?: "rw" | "ro";
  status?: "open" | "close";
};

/* 设置相关属性 */
export type Properties = {
  // 发信相关属性
  // 服务器相关的属性，imap/pop3 只需要填一个，smtp必填
  imap?: {
    host: string;
    port: number;
    secure: boolean,
  };
  pop3?: {
    host: string;
    port: number;
    secure: boolean,
  };
  smtp: {
    host: string;
    port: number;
    secure: boolean,
  };
  // 用户账号信息
  userInfo: {
    username: string;
    password: string
  };
  // 其他属性
  extra?: {
    [prop: string]: string | boolean | number;
  };
  ca?: string[]
};

export interface ITransport {
  // 设置属性
  setProperties(properties: Properties): void;
  // 检查配置是否正确
  check(): Promise<void>;
  // 发送邮件
  sendMail(
    from: EmailAddress,
    toList: EmailAddress[],
    ccList: EmailAddress[],
    bccList: EmailAddress[],
    subject: string,
    richText: string,
    plainText: string,
    inlineImages: { content: IBuffer; fileName: string; contentId: string }[],
    attachments: { fileName: string; content: IBuffer}[]
  ): Promise<void>;
}

type QueryFieldKey =
  | "from"
  | "to"
  | "subject"
  | "cc"
  | "bcc"
  | "attachment"
  | "body";
type QueryField = {
  [key in QueryFieldKey]?: string;
};
export type Query = {
  fields: QueryField;
  folder: string;
  attrs?: MailAttribute[];
  text?: string;
};

export enum StoreFeature {
  Folder, // 支持文件夹增删改操作
  VirtualFolder, // 支持虚拟文件夹，比如重要、未读等
  MailPart, // 支持分块下载邮件内容
  MailAttribute, // 支持设置邮件属性：已读、已标记等
  NeedToSync, // 需要同步，需要调用sync方法
}

export type Filter = {
  isFlagged?: boolean,
  isSeen?: boolean,
  folderFullName?: string,
}

export interface IMailStorage {
  /*
  * 同步文件夹数据
   */
  setFolderList(folderList: FolderData[]): Promise<void>;
  /*
  * 拿出文件夹数据
   */
  getFolderList(): Promise<FolderData[]>;


  getFolderInfo(fullName: string): Promise<FolderData>;
  setFolderInfo(folderData:FolderData): Promise<void>;

  getFolderMailIdList(
    folderName: string,
    start: number,
    size: number,
    order: Order
  ): Promise<string[]>;

  addMail(folderFullName: string, mailId: string, mail: IBuffer): Promise<void>;
  addMailBasicList(folderFullName: string, mailList: MailBasic[]);
  getMailPartContent(
    folderFullName: string,
    mailId: string,
    partId: string
  ): Promise<IBuffer>;

  hasMail(folderFullName: string, mailId: string): Promise<boolean>;
  checkMailExist(mailIdList: string[]): Promise<{basic: boolean, full: boolean}[]>;

  copyMail(srcFolderFullName: string, srcMailId: string, dstFolderFullName: string, dstMailId: string): Promise<void>;

  moveMail(srcFolderFullName: string, srcMailId: string, dstFolderFullName: string, dstMailId: string): Promise<void>;

  deleteMail(folderFullName: string, mailId: string): Promise<void>;

  getMailIndex(
    folderFullName: string,
    mailId: string,
    order: Order
  ): Promise<number>;
  getMailBasic(
    folderFullName: string,
    mailId: string
  ): Promise<MailBasic>;
  searchMail(query: Query): Promise<string[]>;

  /*
  * 根据参数过滤选择出邮件，用于实现虚拟文件夹功能，比如重要邮件、未读邮件等
   */
  filterMail(filter: Filter): Promise<Map<string, string[]>>;

  //设置邮件属性,返回设置后具备的属性.
  setMailAttributes(mailId: string,folderFullName:string,  attributes: MailAttribute[], modifyType: '' | '+' | '-'): Promise<MailAttribute[]>;

  /**
   * 释放资源.
   */
  release(): Promise<void>;
}

export interface IStore {
  // 设置属性
  setProperties(properties: Properties): void;
  // 检查配置是否正确
  check(): Promise<void>;
  // 获取支持的功能，参考StoreFeature的定义。目前主要是区分IMAP和POP3协议的功能
  supportedFeatures(): StoreFeature[];
  // 是否支持某个功能
  hasFeature(feature: StoreFeature): boolean;

  /*
   * 触发同步操作，同步操作会更新文件夹的邮件列表，更新邮件的属性等
   * 需要支持StoreFeature.NeedToSync才会被调用
   */
  sync?(): void;

  /*
   * 新邮件通知，当有新邮件到达时，会触发该事件
   * 对于IMAP协议，可以通过IDLE命令来实现，对于POP3协议，需要定时轮询
   * 对于IMAP协议，新邮件是指新加入到文件夹的邮件，有可能是已读的，也有可能是未读的
   * 回调函数的参数是文件夹夹名称和新邮件id列表
   */
  on(
    event: "new-mail",
    handler: (folderFullName: string, mailIdList: string[]) => void
  ): void;

  /*
   * 其他事件，看具体Store对象的实现
   */
  on(event: string, handler: Function): void;

  /* 获取邮件全部内容，包括头部、正文、附件等，是一个MIME格式的字符串
   * @param folderFullName: 文件夹名称
   * @param mailId: 邮件id
   * @return: 邮件内容，是一个MIME格式的字符串，使用IBuffer存储
   */
  getMail(folderFullName: string, mailId: string): Promise<IBuffer>;

  /* 获取邮件部分内容，对于multipart的邮件，可以指定获取某个部分的内容
   * partId是一个字符串，格式是 1.2.3，表示获取第1个子部分的第2个子部分的第3个子部分的内容
   * @param folderFullName: 文件夹名称
   * @param mailId: 邮件id
   * @param partId: 邮件的部分id
   * @return: 返回对应的part的内容，不包括头部，未解码。使用时需要根据MailStructure来解码
   */
  getMailPartContent(
    folderFullName: string,
    mailId: string,
    partId: string
  ): Promise<IBuffer>;

  /* 获取邮件的基本信息，包括信封、结构、属性等，参考MailBasic的定义
   * @param folderFullName: 文件夹名称
   * @param mailId: 邮件id
   */
  getMailBasic(folderFullName: string, mailId: string): Promise<MailBasic>;

  /*
   * 获取邮件的序号，序号是一个数字，从1开始
   * 如果mailId不是合法，或者找不到邮件，reject
   */
  getMailIndex(
    folderFullName: string,
    mailId: string,
    order: Order
  ): Promise<number>;

  /* 设置邮件的属性，返回设置后的属性列表
   * @param folderFullName: 文件夹名称
   * @param mailId: 邮件id
   * @param attributes: 邮件属性列表
   * @param modifyType: "+"表示添加属性，"-"表示删除属性，""表示替换属性
   */
  setMailAttributes(
    folderFullName: string,
    mailId: string,
    attributes: MailAttribute[],
    modifyType: "+" | "-" | ""
  ): Promise<MailAttribute[]>;

  // 文件夹相关操作，需要支持StoreFeature.Folder才可以使用。
  // 标准协议里面，IMAP支持，POP3不支持

  // 创建子文件夹
  createSubFolder(folderName: string, parent: string): Promise<void>;
  // 重命名文件夹
  renameFolder(folderName: string, newName: string): Promise<void>;
  // 删除文件夹，
  deleteFolder(folderName: string): Promise<void>;
  // 获取全部文件夹列表
  getAllFolderList(): Promise<FolderData[]>;
  // 获取文件夹列表
  getFolderList(parent: string): Promise<FolderData[]>;
  // 获取文件夹信息，参考FolderData的定义
  getFolderInfo(folderName: string): Promise<FolderData>;
  // 打开文件夹，文件夹需要打开之后才可以读取邮件
  // 对应IMAP的select指令，POP3不需要打开
  openFolder(folderName: string): Promise<FolderData>;
  // 关闭文件夹，关闭之后就不能读取邮件了
  // 对应IMAP的close指令，POP3不需要关闭
  closeFolder(folderName: string): Promise<void>;
  // 判断文件夹是否打开
  isFolderOpen(folderName: string): boolean;

  /*
   * 获取文件夹指定范围的邮件id列表
   * @param folderName: 文件夹名称
   * @param start: 开始的邮件序号，从1开始
   * @param size: 获取邮件的数量
   * @param order: 排序规则，参看Order的定义
   * return: 邮件id列表
   */
  getFolderMailIdList(
    folderName: string,
    start: number,
    size: number,
    order: Order
  ): Promise<string[]>;

  /*
  * 移动一封邮件到目标文件夹
  * 返回邮件在新文件夹的id
   */
  moveMail(
    fromFolderFullName: string,
    mailId: string,
    toFolderFullName: string
  ): Promise<string>;
  /*
  * 复制一封邮件到目标文件夹
  * 返回邮件在新文件夹的id
   */
  copyMail(
    fromFolderFullName: string,
    mailId: string,
    toFolderFullName: string
  ): Promise<string>;
  /*
  * 往文件夹里添加邮件
  * 返回邮件id
   */
  addMail(mail: string, folderName: string): Promise<string>;
  /*
  * 删除邮件
   */
  deleteMail(fromFolder: string, mailId: string): Promise<void>;

  filterMail(filter: Filter): Promise<Map<string, string[]>>;
  searchMail(query: Query): Promise<string[]>;

  /*
  * 断开连接，释放资源
   */
  release(): Promise<void>;
  /*
   * 设置缓存生成器。协议内部需要的IBuffer对象，由这个生成器来构造。如果没传，则使用内存对象。
   */
  setBufferCreator(creator: IBufferCreator): void;
}

export enum ErrorCode {
  Error = 1,
  // 未知错误
  UNKNOWN_ERROR = 1,
  // 协议解析出错，一般是格式问题
  PROTOCOL_ERROR,
  // 连接服务器超时
  CONNECT_TIMEOUT,
  // 登录失败
  LOGIN_FAILED,
  // 连接不到服务器
  CONNECT_FAILED,
  // 发送数据失败
  SEND_DATA_FAILED,

  // 参数错误
  PARAMETER_ERROR,
  // 参数缺失
  PARARMETER_MISSED,
  // 找不到文件夹
  FOLDER_NOT_FOUND,
  FOLDER_EXISTS,
  // 解析邮件内容出错
  PARSE_MAIL_FAILED,
  // 解析MIME格式出错
  PARSE_MIME_FAILED,
  // 解析RTF出错
  PARSE_RTF_FAILED,
  // 不支持
  NOT_SUPPORTED,
  // 方法未实现
  NOT_IMPLEMENTED,
  // 找不到附件
  ATTACHMENT_NOT_FOUND,
  // 找不到内联图片
  INLINE_IMAGE_NOT_FOUND,

  DELETE_MAIL_FAILED,

  SENT_MAIL_FAILED,

  MAIL_NOT_FOUND,

  NO_AVAILABLE_NETWORK,

  SERVER_UN_REACHABLE,
  SERVER_NOT_SUPPORT,
  CREATE_FOLDER_FAILED,
  MAIL_PART_NOT_FOUND,
  MAIL_ATTRIBUTE_NOT_FOUND,
  MAIL_ATTRIBUTE_NOT_SUPPORT,
  MAIL_ATTRIBUTE_NOT_WRITABLE,

  // RTF解析参数超出限制
  RTF_ARGMENT_OUT_OF_RANGE,
  // RTF解析失败（一般是未能支持的参数）
  RTF_PARSER_FAILED,

  IMAP_UNEXPECTED_END_OF_LINE,
  IMAP_PARSER_FAILED,
}
export class CMError extends Error {
  code: ErrorCode;
  extra?: Object;
  constructor(message: string, code: ErrorCode = ErrorCode.Error, extra?: Object) {
    super(message);
    this.code = code;
    this.extra = extra;
  }
}
