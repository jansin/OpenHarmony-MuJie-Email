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

import type {
  IStore,
  Properties,
  MailEnvelope,
  MailStructure,
  FolderData,
  EmailAddress,
  Query,
  Order,
  IBuffer,
  MailBasic,
  Filter,
  IBufferCreator,
} from "../api";
import { MailAttribute, CMError, ErrorCode, StoreFeature, FolderType } from "../api";
import type {
  ResultResponse,
  FetchResponse,
  ListResponse,
  ImapResponse,
  StatusResponse,
} from "../protocols/imap_protocol";
import { Atoms, IMAPProtocol, ImapResponseType } from "../protocols/imap_protocol";
import { decodeRFC2047, encodeUtf8 } from "../utils/encodings";
import { imapListToMap, delay, parseDateString } from "../utils/common";
import { getLogger } from "../utils/log";
import { memBufferCreator } from '../utils/file_stream';
import type { Atom, ImapList } from '../protocols/tokenizer';

type Timer = number;

type _FolderData = FolderData & {flags:Atom[]}

const logger = getLogger("imap_store");

function parseStructure(structure: ImapList, index: number[]): MailStructure {
  let isMultipart = structure[0] instanceof Array;
  if (isMultipart) {
    const subParts: MailStructure[] = [];
    let i = 0;
    for (; i < structure.length; i++) {
      const item = structure[i];
      if (item instanceof Array) {
        subParts.push(parseStructure(item, [...index, i + 1]));
      } else {
        break;
      }
    }
    return {
      contentType: {
        type: 'multipart',
        subType: (structure[i] as string).toLowerCase(),
        params: imapListToMap((structure[i + 1] || []) as string[])
      },
      children: subParts,
      partId: "",
      size: 0,
    };
  } else {
    const struct: MailStructure = {
      contentType: {
        type: (structure[0] as string).toLowerCase(),
        subType: (structure[1] as string).toLowerCase(),
        params: imapListToMap((structure[2] || []) as string[]),
      },
      contentId: (structure[3] || undefined) as (string | undefined),
      // description: structure[4] || "",
      encoding: ((structure[5] || "") as string).toLowerCase(),
      size: structure[6] as number,
      partId: index.join(".") || "1",
      children: [],
    };
    const isMessage = struct.contentType.type.toUpperCase() == "MESSAGE";
    if (isMessage) {
    } else if (structure[8]) {
      struct.disposition = {
        type: (structure[8][0] as string).toLowerCase(),
        params: imapListToMap((structure[8][1] || []) as string[]),
      };
    }
    return struct;
  }
}

function parseDate(dateStr: string): Date {
  let date: Date;
  if (dateStr) {
    date = parseDateString(dateStr);
  } else {
    date = new Date("1970-01-01");
  }
  return date;
}

function isNilToken(v: unknown): boolean {
  if (v === undefined || v === null) {
    return true;
  }
  if (typeof v === 'string' && v.toUpperCase() === 'NIL') {
    return true;
  }
  return false;
}

/** 解析 IMAP ENVELOPE 中的单个 (name adl mailbox host) 地址 */
function parseOneEnvelopeAddress(addr: unknown): EmailAddress | null {
  if (!addr || !Array.isArray(addr) || addr.length < 4) {
    return null;
  }
  const nameRaw = addr[0];
  const mailbox = addr[2];
  const host = addr[3];
  const name = isNilToken(nameRaw) ? '' : decodeRFC2047(String(nameRaw));
  const mb = isNilToken(mailbox) ? '' : String(mailbox);
  const ho = isNilToken(host) ? '' : String(host);
  let email = '';
  if (mb && ho) {
    email = `${mb}@${ho}`;
  } else if (mb) {
    email = mb;
  }
  if (!email && !name) {
    return null;
  }
  return { name, email };
}

/**
 * 解析 ENVELOPE 的 from/to/cc/bcc 字段。
 * 注意：NIL 在 tokenizer 中为原子 "NIL"；若误把 "NIL" 当数组 map，会把字符当成地址产生乱码。
 */
function parseMailList(field: unknown): EmailAddress[] {
  if (field === undefined || field === null || isNilToken(field)) {
    return [];
  }
  if (typeof field === 'string') {
    return [];
  }
  if (!Array.isArray(field) || field.length === 0) {
    return [];
  }
  const first = field[0];
  if (Array.isArray(first)) {
    const out: EmailAddress[] = [];
    for (const item of field) {
      const one = parseOneEnvelopeAddress(item);
      if (one && (one.email.length > 0 || one.name.length > 0)) {
        out.push(one);
      }
    }
    return out;
  }
  const single = parseOneEnvelopeAddress(field);
  return single ? [single] : [];
}

function parseEnvelope(envelope: ImapList): MailEnvelope {
  const fromList = parseMailList(envelope[2]);
  const mailEnvelope: MailEnvelope = {
    date: parseDate(envelope[0] as string),
    subject: decodeRFC2047((envelope[1] || "") as string),
    from: fromList.length > 0 ? fromList[0] : { name: '', email: '' },
    to: parseMailList(envelope[5]),
    cc: parseMailList(envelope[6]),
    bcc: parseMailList(envelope[7]),
    messageId: (envelope[9] || "") as string,
  };
  return mailEnvelope;
}

function parseMailFlags(flags: Atom[]): MailAttribute[] {
  if (!flags) {
    return [];
  }
  const attrs = flags.map(flag => {
    switch (flag) {
      case Atoms.SEEN:
        return MailAttribute.Seen;
      case Atoms.FLAGGED:
        return MailAttribute.Flagged;
      case Atoms.ANSWERED:
        return MailAttribute.Answered;
      case Atoms.DRAFT:
        return MailAttribute.Draft;
      case Atoms.RECENT:
        return MailAttribute.Recent;
      case Atoms.DELETED:
        return MailAttribute.Deleted;
    }
    return null;
  }).filter(v => v !== null);
  return attrs;
}

function parseMailBasicInfo(resp: FetchResponse): MailBasic {
  const uid = resp.uid!.toString();
  const envelope = parseEnvelope(resp.envelope!);
  if (resp.internalDate && !(resp.envelope && resp.envelope[0])) {
    const d = parseDateString(resp.internalDate);
    envelope.date = d;
  }
  const data: MailBasic = {
    id: uid,
    envelope,
    structure: parseStructure(resp.bodyStructure!, []),
    attributes: parseMailFlags(resp.flags),
    size: resp.rfc822_size!,
  };
  return data;
}

export class ImapStore implements IStore {
  name: string = "imap";
  properties?: Properties;
  currentFolder: string = "";
  _capabilities: string[] = [];
  _delayCloseTime: number = 60 * 1000;
  _protocolTimeout: number = 5000;
  _protocolPromise?: Promise<IMAPProtocol>;
  _bufferCreator: IBufferCreator = memBufferCreator;

  constructor() {}

  setBufferCreator(creator: IBufferCreator): void {
    this._bufferCreator = creator;
  }

  async getProtocol(): Promise<IMAPProtocol> {
    logger.trace("get protocol")
    if (!this.properties || !this.properties.imap) {
      logger.error("get protocol before properties are set", this.properties)
      throw new CMError("properties not set", ErrorCode.PARARMETER_MISSED);
    }

    if (this._protocolPromise) {
      const protocol = await this._protocolPromise.catch((err: unknown) => {
        logger.error("protocol failed", err);
      });
      if (protocol && protocol.isReady() && !protocol.hasError()) {
        return protocol;
      } else if (protocol) {
        logger.trace("===close error connection")
        protocol.logout();
        protocol.stop();
      }
      logger.warn("connection issue, recreate connection")
    }
    this._protocolPromise = this.createProtocol();
    const protocol = await this._protocolPromise.catch((err: unknown) => {
      logger.error("connect failed", this.properties.imap);
      throw err;
    });
    return protocol;
  }

  async release(): Promise<void> {
    logger.trace("===release")
    this.currentFolder = "";
    const protocol = await this._protocolPromise;
    protocol.logout();
    protocol.stop();
    this._protocolPromise = undefined;
  }

  releaseProtocol(protocol: IMAPProtocol): void {
    logger.trace("===release protocole")
    protocol.logout();
    protocol.stop();
  }

  async createProtocol(): Promise<IMAPProtocol> {
    logger.trace("===create imap protocol")
    this.currentFolder = "";
    const { imap, userInfo, ca } = this.properties;
    const protocol = new IMAPProtocol(imap.host, imap.port, imap.secure, ca);
    if (this.properties.extra?.imapPrefix) {
      protocol.setIdPrefix(this.properties.extra.imapPrefix as string);
    }
    await protocol.connect();
    // 系统问题，连接成功后不能马上发送消息，否则会导致收不到数据
    await delay(100);
    let respList = await protocol.capability();
    logger.debug("capability", respList);
    const resp = respList.filter(
      resp => resp.type === ImapResponseType.capability
    )[0];
    const capabilities = (resp as (ImapResponse & {capabilities: string[]})).capabilities;
    this._capabilities = capabilities;

    respList = await protocol.login(userInfo.username, userInfo.password);
    let success = false;
    let message = "";
    for (const resp of respList) {
      if (resp.type === ImapResponseType.result) {
        if ((resp as ResultResponse).status === Atoms.OK) {
          success = true;
          break;
        } else {
          message = (resp as ResultResponse).text;
        }
      }
    }
    if (!success) {
      return Promise.reject(new CMError(message, ErrorCode.LOGIN_FAILED));
    }
    // 网易 163/126/188 等：LOGIN 成功后若不发 ID，后续 SELECT 会报 "Unsafe Login"
    if (capabilities.includes("ID")) {
      const customId = this.properties.extra?.["imap.id"] as string | undefined;
      const idParams = (customId && customId.length > 0)
        ? customId
        : '"name" "mail_base" "version" "1.0.0" "vendor" "OpenHarmony"';
      await protocol.id(idParams);
    }
    protocol.setBufferCreator(this._bufferCreator);
    return protocol;
  }

  setProperties(properties: Properties): void {
    this.properties = properties;
    const timeout = properties.extra?.["imap.timeout"];
    if (timeout) {
      this._protocolTimeout = timeout as number;
    }
    const delay = properties.extra?.["imap.delay-close"];
    if (delay) {
      this._delayCloseTime = delay as number;
    }
  }

  async check(): Promise<void> {
    logger.trace("check")
    await this.getProtocol();
  }

  supportedFeatures(): StoreFeature[] {
    return [
      StoreFeature.Folder,
      StoreFeature.MailPart,
      StoreFeature.MailAttribute,
    ];
  }

  hasFeature(feature: StoreFeature): boolean {
    return this.supportedFeatures().includes(feature);
  }

  async getMail(folderFullName: string, mailId: string): Promise<IBuffer> {
    logger.debug("getMail", folderFullName, mailId);
    if (folderFullName !== this.currentFolder) {
      logger.debug("getMail", folderFullName, this.currentFolder);
      await this.openFolder(folderFullName);
    }
    const protocol = await this.getProtocol();
    const respList = await protocol.uidFetch(mailId, "BODY.PEEK[]");
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      return Promise.reject("mail not found");
    }
    const resp = respList.filter(
      resp => resp.type === ImapResponseType.fetch
    )[0];
    if (!resp || !(resp as FetchResponse).body) {
      return Promise.reject("mail not found");
    }
    return (resp as FetchResponse).body!;
  }

  async getMailBasic(
    folderFullName: string,
    mailId: string
  ): Promise<MailBasic> {
    if (folderFullName !== this.currentFolder) {
      await this.openFolder(folderFullName);
    }
    const protocol = await this.getProtocol();
    let respList = await protocol.uidFetch(
      mailId,
      "BODYSTRUCTURE FLAGS ENVELOPE RFC822.SIZE INTERNALDATE"
    );
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      return Promise.reject("mail not found");
    }
    respList = respList.filter(resp => resp.type === ImapResponseType.fetch);
    if (respList.length === 0) {
      logger.error("fetch mail failed", respList);
      return Promise.reject("fetch mail failed");
    }
    const resp = respList[0] as FetchResponse;
    try {
      const data = parseMailBasicInfo(resp);
      return data;
    } catch (e: unknown) {
      logger.error(`parseMailBasic ${mailId} ${folderFullName}`, resp, e);
      return Promise.reject(
        new CMError(
          `parseMailBasic ${mailId} ${folderFullName}`,
          ErrorCode.PARAMETER_ERROR,
          e
        )
      );
    }
  }

  async getMailPartContent(
    folderFullName: string,
    mailId: string,
    partId: string
  ): Promise<IBuffer> {
    if (folderFullName !== this.currentFolder) {
      await this.openFolder(folderFullName);
    }
    const protocol = await this.getProtocol();
    const respList = await protocol.uidFetch(mailId, `BODY[${partId}]`);
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      return Promise.reject("mail not found");
    }
    const resp = respList.filter(
      resp => resp.type === ImapResponseType.fetch
    )[0] as FetchResponse;
    return resp.body!;
  }

  async getMailIndex(
    folderFullName: string,
    mailId: string,
    order: Order
  ): Promise<number> {
    if (folderFullName !== this.currentFolder) {
      await this.openFolder(folderFullName);
    }
    const protocol = await this.getProtocol();
    let respList = await protocol.uidFetch(
      mailId,
      "BODYSTRUCTURE FLAGS ENVELOPE RFC822.SIZE"
    );
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      return Promise.reject("mail not found");
    }
    respList = respList.filter(resp => resp.type === ImapResponseType.fetch);
    if (respList.length === 0) {
      logger.error("fetch mail failed", respList);
      return Promise.reject("fetch mail failed");
    }
    const resp = respList[0] as FetchResponse;
    return resp.index;
  }

  async setMailAttributes(
    folderFullName: string,
    mailId: string,
    attributes: MailAttribute[],
    modifyType: "+" | "-" | ""
  ): Promise<MailAttribute[]> {
    logger.debug('setMailAttributes', folderFullName, mailId, attributes)
    if (folderFullName !== this.currentFolder) {
      await this.openFolder(folderFullName);
    }
    const protocol = await this.getProtocol();
    const mailAttrs = attributes.map(attr => `\\${MailAttribute[attr]}`).join("");
    const respList = await protocol.uidStore(
      mailId,
      `${modifyType}FLAGS (${mailAttrs})`
    );
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      logger.info("set mail attr failed", folderFullName, mailId, result.status);
      return Promise.reject("set mail attributes failed");
    }
    const resp = respList.filter(
      resp => resp.type === ImapResponseType.fetch
    )[0] as FetchResponse;
    const flags = parseMailFlags(resp.flags);
    logger.debug("set mail success", folderFullName, mailId, flags);
    return flags;
  }

  async createSubFolder(folderName: string, parent: string): Promise<void> {
    logger.debug("createSubFolder")
    const protocol = await this.getProtocol();
    const name = parent.length > 0 ? `${parent}/${folderName}` : folderName;
    const respList = await protocol.create(name, "/");
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      const text = "create folder failed " + result.text;
      logger.info("createSubFolder ", text);
      return Promise.reject(text);
    }
    logger.debug("createSubFolder success")
  }

  async deleteFolder(folderName: string): Promise<void> {
    logger.debug("deleteFolder")
    const protocol = await this.getProtocol();
    const respList = await protocol.delete(folderName);
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      const text = "delete folder failed " + result.text;
      logger.info("deleteFolder", text);
      return Promise.reject(text);
    }
    logger.debug("deleteFolder success");
  }

  async renameFolder(folderName: string, newName: string): Promise<void> {
    logger.debug("renameFolder");
    const protocol = await this.getProtocol();
    const respList = await protocol.rename(folderName, newName);
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      const text = "rename folder failed " + result.text;
      logger.info("renameFolder", text);
      return Promise.reject(text);
    }
    logger.debug("renameFolder success")
  }

  // 获取全部文件夹列表
  async getAllFolderList(): Promise<FolderData[]> {
    logger.debug("getAllFolderList");
    const protocol = await this.getProtocol();
    const respList = await protocol.list("", "*");
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      const text = "list folder failed " + result.text;
      logger.log("getAllFolderList", text);
      return Promise.reject(text);
    }
    const res:_FolderData[] = respList
      .filter(resp => resp.type == ImapResponseType.list)
      .map(r => {
        const resp = r as ListResponse;
        const fullName = resp.name;
        let name = fullName;
        let parentPart = "";
        if (resp.delimiter) {
          const i = fullName.lastIndexOf(resp.delimiter);
          if (i > 0) {
            name = fullName.substring(i + 1);
            parentPart = fullName.substring(0, i);
          }
        }
        const fd: _FolderData = {
          name,
          fullName,
          parent: parentPart,
          type: FolderType.other,
          flags:resp.flags
        };
        return fd;
      });
    let recognizedMap:Map<FolderType,boolean> = new Map([
      [FolderType.root,false],
      [FolderType.inbox,false],
      [FolderType.draft,false],
      [FolderType.sent,false],
      [FolderType.trash,false],
      [FolderType.spam,false],
      [FolderType.archive,false],
      [FolderType.virus,false],
    ]);
    let recognizedFds = this.judgeFolderListType(res,recognizedMap);
    logger.debug("getAllFolderList success");
    return recognizedFds;
  }



  /**
   * 判断文件夹的type类型
   */
  judgeFolderListType(fds:_FolderData[],recognizedMap:Map<FolderType,boolean>):FolderData[] {
    this.judgeFolderTypeByServerFlag(fds,recognizedMap);
    this.judgeFolderTypeByName(fds,recognizedMap);
    fds.forEach((item)=>{
      delete item.flags;
    })
    return fds;
  }

  // const FolderNameMap: Map<string, string> = new Map([
  //   ["INBOX", "收件箱"],
  //   ["draft", "草稿箱"],
  //   ["Draft", "草稿箱"],
  //   ["Drafts", "草稿箱"],
  //   ["sent", "已发送"],
  //   ["Sent", "已发送"],
  //   ["Sent Items", "已发送"],
  //   ["Sent Messages", "已发送"],
  //   ["trash", "已删除"],
  //   ["Trash", "已删除"],
  //   ["Deleted", "已删除"],
  //   ["Deleted Items", "已删除"],
  //   ["Deleted Messages", "已删除"],
  //   ["Virus", "病毒邮件"],
  //   ["Virus Items", "病毒邮件"],
  //   ["Spam", "垃圾邮件"],
  //   ["Junk", "垃圾邮件"],
  //   ["Junk E-mail", "垃圾邮件"]
  // ])

  judgeFolderTypeByServerFlag(fds:_FolderData[],recognizedMap:Map<FolderType,boolean>) {
    fds.forEach((item)=>{
      if (item.flags.includes("Sent")) {
        item.type = FolderType.sent;
        recognizedMap.set(FolderType.sent,true);
      } else if (item.flags.includes("Trash")) {
        item.type = FolderType.trash;
        recognizedMap.set(FolderType.trash,true);
      } else if (item.flags.includes("Junk") || item.flags.includes("Spam")) {
        item.type = FolderType.spam;
        recognizedMap.set(FolderType.spam,true);
      } else if (item.flags.includes("Drafts")) {
        item.type = FolderType.draft;
        recognizedMap.set(FolderType.draft,true);
      } else if (item.flags.includes("Archive")) {
        item.type = FolderType.archive;
        recognizedMap.set(FolderType.archive,true);
      } else if (item.flags.includes("Virus")) {
        item.type = FolderType.virus;
        recognizedMap.set(FolderType.virus,true);
      }
    });
  }
  hasRecognizedFolderType(type:FolderType,recognizedMap:Map<FolderType,boolean>):boolean {
    return recognizedMap.get(type) == true;
  }
  setHasRecognizedFolderType(type:FolderType,recognizedMap:Map<FolderType,boolean>){
    recognizedMap.set(type,true);
  }
  judgeFolderTypeByName(fds:_FolderData[],recognizedMap:Map<FolderType,boolean>) {
    fds.forEach((item) => {
      switch (item.fullName) {
        case "INBOX":
        case "收件箱": {
          if (!this.hasRecognizedFolderType(FolderType.inbox,recognizedMap)) {
            item.type = FolderType.inbox;
            this.setHasRecognizedFolderType(FolderType.inbox,recognizedMap)
          }
          break;
        }
        case "Draft":
        case "Drafts":
        case "草稿箱": {
          if (!this.hasRecognizedFolderType(FolderType.draft,recognizedMap)) {
            item.type = FolderType.draft;
            this.setHasRecognizedFolderType(FolderType.draft,recognizedMap)
          }
          break;
        }
        case "Sent":
        case "Sent Items":
        case "Sent Messages":
        case "已发送": {
          if (!this.hasRecognizedFolderType(FolderType.sent,recognizedMap)) {
            item.type = FolderType.sent;
            this.setHasRecognizedFolderType(FolderType.sent,recognizedMap)
          }
          break;
        }
        case "Trash":
        case "Deleted":
        case "Deleted Items":
        case "Deleted Messages":
        case "已删除": {
          if (!this.hasRecognizedFolderType(FolderType.trash,recognizedMap)) {
            item.type = FolderType.trash;
            this.setHasRecognizedFolderType(FolderType.trash,recognizedMap)
          }
          break;
        }
        case "Virus":
        case "Virus Items":
        case "病毒邮件": {
          if (!this.hasRecognizedFolderType(FolderType.virus,recognizedMap)) {
            item.type = FolderType.virus;
            this.setHasRecognizedFolderType(FolderType.virus,recognizedMap)
          }
          break;
        }
        case "Spam":
        case "Junk":
        case "Junk E-mail":
        case "垃圾邮件": {
          if (!this.hasRecognizedFolderType(FolderType.spam,recognizedMap)) {
            item.type = FolderType.spam;
            this.setHasRecognizedFolderType(FolderType.spam,recognizedMap)
          }
          break;
        }
        default:
        //保持other不变.
          break;
      }
    });
  }


  async getFolderList(parent: string): Promise<FolderData[]> {
    const allFolders = await this.getAllFolderList();
    return allFolders.filter(fd => fd.parent == parent);
  }

  _parseFolderDataResponse(
    respList: ImapResponse[],
    folderData: FolderData
  ): void {
    logger.debug("folder data", folderData, respList);
    for (const resp of respList) {
      if (resp.type === ImapResponseType.exists) {
        folderData.mailCount = (resp as (ImapResponse & {exists: number})).exists;
      } else if (resp.type === ImapResponseType.recent) {
        folderData.recent = (resp as (ImapResponse & {recent: number})).recent;
      } else if (resp.type === ImapResponseType.status) {
        const status = resp as StatusResponse;
        if (status.name === folderData.name) {
          if (status.attributes.has(Atoms.MESSAGES)) {
            folderData.mailCount = status.attributes.get(Atoms.MESSAGES);
          }
          if (status.attributes.has(Atoms.RECENT)) {
            folderData.recent = status.attributes.get(Atoms.RECENT);
          }
          if (status.attributes.has(Atoms.UNSEEN)) {
            folderData.unreadCount = status.attributes.get(Atoms.UNSEEN);
          }
        }
      }
    }
    logger.debug("folder data", folderData);
  }

  async getFolderInfo(folderName: string): Promise<FolderData> {
    logger.debug("getFolderInfo", folderName);
    const protocol = await this.getProtocol();
    // const protocol = await this.createProtocol();
    const respList = await protocol.status(folderName, [
      Atoms.MESSAGES,
      Atoms.UNSEEN,
      Atoms.RECENT,
    ]);
    const result = respList[respList.length - 1] as ResultResponse;
    const folderData: FolderData = {
      name: folderName,
      fullName: folderName,
      mailCount: 0,
      unreadCount: 0,
      recent: 0,
    };
    if (result.status === Atoms.OK) {
      this._parseFolderDataResponse(respList, folderData);
    } else {
      const text = "get folder info failed" + result;
      logger.error("getFolderInfo failed", text);
      throw new CMError(text, ErrorCode.PROTOCOL_ERROR);
    }
    logger.debug("getFolderInfo success", folderName, folderData);
    // protocol.logout()
    // protocol.stop();
    return folderData;
  }

  async openFolder(folderName: string): Promise<FolderData> {
    const protocol = await this.getProtocol();
    const respList = await protocol.select(folderName);
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      return Promise.reject("select folder failed " + result.text);
    }
    const folderData: FolderData = {
      name: folderName,
      fullName: folderName,
      mailCount: 0,
      unreadCount: 0,
      recent: 0,
    };
    this._parseFolderDataResponse(respList, folderData);
    this.currentFolder = folderName;
    return folderData;
  }

  async closeFolder(folderName: string): Promise<void> {
    if (folderName == this.currentFolder) {
      const protocol = await this.getProtocol();
      await protocol.close();
    }
  }

  isFolderOpen(folderName: string): boolean {
    return this.currentFolder === folderName;
  }

  async getFolderMailIdList(
    folderName: string,
    start: number,
    size: number,
    order: Order // 忽略此参数，只能按照服务器的顺序获取
  ): Promise<string[]> {
    logger.debug("getFolderMailIdList", folderName, start, size);
    if (folderName != this.currentFolder) {
      logger.info("getFolderMailIdList", folderName, this.currentFolder);
      await this.openFolder(folderName);
    }
    const protocol = await this.getProtocol();
    const respList = await protocol.fetch([start, start + size - 1], "UID");
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      const text = "fetch failed " + result.text;
      logger.info("getFolderMailIdList", text, folderName, start, size);
      return Promise.reject(text);
    }
    const res = respList
      .filter(resp => resp.type === ImapResponseType.fetch)
      .map(resp => {
        try {
          return (resp as FetchResponse).uid!.toString();
        } catch (e) {
          logger.error("parse uid failed", resp, e);
          return "";
        }
      })
      .filter(id => id.length > 0);
    logger.debug("getFolderMailIdList success", folderName, start, size);
    return res;
  }

  async copyMail(
    fromFolderFullName: string,
    mailId: string,
    toFolderFullName: string
  ): Promise<string> {
    if (fromFolderFullName !== this.currentFolder) {
      await this.openFolder(fromFolderFullName);
    }
    const protocol = await this.getProtocol();
    const respList = await protocol.uidCopy(mailId, toFolderFullName);
    const result = respList[respList.length - 1] as ResultResponse;
    if (result.status !== Atoms.OK) {
      return Promise.reject("copy mail failed" + result.text);
    }
    // 打开目标文件夹，拿到最新的邮件id
    let fd = await this.openFolder(toFolderFullName);
    fd = await this.getFolderInfo(toFolderFullName);
    logger.debug(`[__imap][CopyMail][__move][get folder info totalCount: ${fd.mailCount}]`)
    const idList = await this.getFolderMailIdList(toFolderFullName, fd.mailCount!, 1, {by: "date", desc: true});
    return idList[0];
  }

  async moveMail(fromFolderFullName: string, mailId: string, folderName: string): Promise<string> {
    if (fromFolderFullName !== this.currentFolder) {
      await this.openFolder(fromFolderFullName);
    }
    logger.debug(`[__imap][copy mail ${fromFolderFullName}/${mailId} ==> ${folderName}]`);
    const newMailId = await this.copyMail(fromFolderFullName, mailId, folderName);
    logger.debug(`[__imap][copy mail new mid: ${newMailId}]`);
    logger.debug(`[__imap][delete mail ${fromFolderFullName}/${mailId}]`);
    await this.deleteMail(fromFolderFullName, mailId);
    return newMailId;
  }

  async addMail(mail: string, folderName: string): Promise<string> {
    if (folderName !== this.currentFolder) {
      await this.openFolder(folderName);
    }
    const protocol = await this.getProtocol();
    const respList = await protocol.append(folderName, mail);
    const fd = await this.openFolder(folderName);
    const idList = await this.getFolderMailIdList(folderName, fd.mailCount!, 1, {by: "date", desc: true});
    return idList[0];
  }

  async deleteMail(fromFolderFullName: string, mailId: string): Promise<void> {
    if (fromFolderFullName !== this.currentFolder) {
      await this.openFolder(fromFolderFullName);
    }
    const protocol = await this.getProtocol();
    const respList = await protocol.uidStore(mailId, "+FLAGS.SILENT \\Deleted");
    await protocol.expunge();
  }

  async searchMail(query: Query): Promise<string[]> {
    logger.debug("search", query);
    let fields = query.fields;
    const criteria = ["CHARSET UTF-8"];
    if (fields.from) {
      criteria.push(`FROM "${fields.from}"`);
    }
    if (fields.to) {
      criteria.push(`TO "${fields.to}"`);
    }
    if (fields.cc) {
      criteria.push(`CC "${fields.cc}"`);
    }
    if (fields.bcc) {
      criteria.push(`BCC "${fields.bcc}"`);
    }
    if (fields.subject) {
      criteria.push(`SUBJECT ${processSearchCriterion(fields.subject)}`);
    }
    if (fields.body) {
      criteria.push(`TEXT ${processSearchCriterion(fields.body)}`);
    }

    const protocol = await this.getProtocol();
    await protocol.select(query.folder);
    const respList = await protocol.search(criteria.join(" "));
    if (this.currentFolder) {
      await protocol.select(this.currentFolder);
    } else {
      await protocol.close();
    }
    const resp = respList.find(resp => resp.type === ImapResponseType.search);
    if (!resp) {
      return [];
    }
    return (resp as ImapResponse & {ids: string[]}).ids;
  }

  filterMail(filter: Filter): Promise<Map<string, string[]>> {
    throw new CMError("not implemented", ErrorCode.NOT_IMPLEMENTED);
  }

  on(event: "init", handler: () => void): void;
  on(
    event: "new-mail",
    handler: (folderFullName: string, mailIdList: string[]) => void
  ): void;
  on(event: "mail-deleted", handler: (mailId: string) => void): void;
  on(event: string, handler: Function): void {
    throw new CMError("Method not implemented.", ErrorCode.NOT_IMPLEMENTED);
  }
}

function processSearchCriterion(text: string): string {
  const b = encodeUtf8(text);
  if (b.length > text.length) {
    text = `{${b.length}}\r\n${text}`;
  } else {
    text = `"${text}"`;
  }
  return text;
}
