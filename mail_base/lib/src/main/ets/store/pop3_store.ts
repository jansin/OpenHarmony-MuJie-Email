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


import { CMError, ErrorCode, FolderType } from "../api";
import type {
  IBuffer,
  IStore,
  Properties,
  StoreFeature,
  MailAttribute,
  FolderData,
  Query,
  Order,
  MailBasic,
  Filter,
  Mime
, IBufferCreator } from "../api";
import { Pop3Protocol } from "../protocols/pop3_protocol";
import { getLogger } from "../utils/log";
import { getMimeParts, MimeMail, parseMime2 } from "../utils/mime";
import { memBufferCreator } from '../utils/file_stream';

const logger = getLogger("pop3_store");

export class Pop3Store implements IStore {
  _properties?: Properties;
  _protocolPromise?: Promise<Pop3Protocol>;
  _mailId2Index = new Map<string, number>();
  _bufferCreator: IBufferCreator = memBufferCreator;

  constructor() {}

  setBufferCreator(creator: IBufferCreator): void {
    this._bufferCreator = creator;
  }

  async createProtocol(): Promise<Pop3Protocol> {
    logger.trace("===create pop3 protocol")
    const { pop3, userInfo, ca } = this._properties;
    const protocol = new Pop3Protocol(pop3.host, pop3.port, pop3.secure, ca);
    await protocol.connect();
    let success = await protocol.user(userInfo.username);
    if (!success) {
      throw new CMError("pop3 login user failed", ErrorCode.LOGIN_FAILED);
    }
    success = await protocol.pass(userInfo.password);
    if (!success) {
      throw new CMError("pop3 login pass failed", ErrorCode.LOGIN_FAILED);
    }
    protocol.setBufferCreator(this._bufferCreator);
    return protocol;
  }

  async getProtocol(): Promise<Pop3Protocol> {
    const prop = this._properties;
    if (!prop) {
      throw new CMError("properties not set", ErrorCode.PARAMETER_ERROR);
    }
    const { pop3, userInfo, ca } = prop;
    if (!pop3) {
      throw new CMError("pop3 properties not set", ErrorCode.PARAMETER_ERROR);
    }
    if (this._protocolPromise) {
      const protocol = await this._protocolPromise;
      if (protocol.isReady() && !protocol.hasError()) {
        return protocol;
      }
      try {
        protocol.quit();
        protocol.stop();
      } catch (e: unknown) {}
      logger.warn("connection issue, recreate connection")
    }
    this._protocolPromise = this.createProtocol();
    return this._protocolPromise;
  }

  async release(): Promise<void> {
    logger.trace("release")
    const protocol = await this._protocolPromise;
    protocol.quit();
    protocol.stop();
    this._protocolPromise = undefined;
  }

  async syncMailIdList(protocol: Pop3Protocol): Promise<void> {
    const resp = await protocol.uidl();
    for (const [id, uid] of resp.list) {
      this._mailId2Index.set(uid, id);
    }
  }

  setProperties(properties: Properties): void {
    this._properties = properties;
  }

  async check(): Promise<void> {
    logger.trace("check")
    await this.getProtocol();
  }
  supportedFeatures(): StoreFeature[] {
    return [];
  }
  hasFeature(feature: StoreFeature): boolean {
    return false;
  }

  async getMail(folderFullName: string, mailId: string): Promise<IBuffer> {
    let index = this._mailId2Index.get(mailId);
    if (!index) {
      throw new CMError("mail not found", ErrorCode.MAIL_NOT_FOUND);
    }
    const protocol = await this.getProtocol();
    const resp = await protocol.retr(index);
    return resp.data;
  }

  // 为保持api兼容而实现，一般不要直接调用，性能较差
  async getMailPartContent(
    folderFullName: string,
    mailId: string,
    partId: string
  ): Promise<IBuffer> {
    logger.debug("getMailPartContent", mailId, partId);
    const s = await this.getMail("inbox", mailId);
    const mime = await parseMime2(s, this._bufferCreator);
    let m = getMimeParts(mime, (mime) => mime.partId == partId)[0];
    return (m as Mime).body;
  }

  async getMailBasic(
    folderFullName: string,
    mailId: string
  ): Promise<MailBasic> {
    const s = await this.getMail("inbox", mailId);
    const mime = await parseMime2(s, this._bufferCreator);
    const mail = new MimeMail(mime);
    const mailBasic: MailBasic = {
      id: mailId,
      envelope: mail.getEnvelope(),
      structure: mail.getStructure(),
      attributes: [],
      size: await s.getSize(),
    };
    return mailBasic;
  }

  async getMailIndex(
    folderFullName: string,
    mailId: string,
    order: Order
  ): Promise<number> {
    if (this._mailId2Index.size === 0) {
      await this.syncMailIdList(await this.getProtocol());
    }
    let index = this._mailId2Index.get(mailId);
    if (!index) {
      throw new CMError("mail not found", ErrorCode.MAIL_NOT_FOUND);
    }
    return index;
  }

  getMailAttributes(mailId: string): Promise<MailAttribute[]> {
    return Promise.resolve([] as MailAttribute[]);
  }

  setMailAttributes(
    folderFullName: string,
    mailId: string,
    attributes: MailAttribute[],
    modifyType: "+" | "-" | ""
  ): Promise<MailAttribute[]> {
    throw new CMError("method setMailAttributes not implemented", ErrorCode.NOT_IMPLEMENTED);
  }

  createSubFolder(folderName: string, parent: string): Promise<void> {
    throw new CMError("method createSubFolder not supported", ErrorCode.NOT_SUPPORTED);
  }

  deleteFolder(folderName: string): Promise<void> {
    throw new CMError("method deleteFolder not supported", ErrorCode.NOT_SUPPORTED);
  }

  renameFolder(folderName: string, newName: string): Promise<void> {
    throw new CMError("method createSubFolder not implemented", ErrorCode.NOT_SUPPORTED);
  }

  getAllFolderList(): Promise<FolderData[]> {
    return Promise.resolve([
      {
        parent: "",
        name: "INBOX",
        fullName: "INBOX",
        type: FolderType.inbox,
      },
    ]);
  }

  getFolderList(parent: string): Promise<FolderData[]> {
    if (parent == "") {
      return this.getAllFolderList();
    }
    return Promise.resolve([] as FolderData[]);
  }

  async getFolderInfo(folderName: string): Promise<FolderData> {
    const protocol = await this.getProtocol();
    await this.syncMailIdList(protocol);
    const n = this._mailId2Index.size;
    return {
      parent: "",
      name: "INBOX",
      fullName: "INBOX",
      type: FolderType.inbox,
      mailCount: n,
      unreadCount: n,
      recent: n,
    };
  }

  openFolder(folderName: string): Promise<FolderData> {
    if (folderName.toLowerCase() !== "inbox") {
      logger.warn("only inbox supported");
    }
    return this.getFolderInfo("INBOX");
  }

  closeFolder(folderName: string): Promise<void> {
    return Promise.resolve();
  }

  isFolderOpen(folderName: string): boolean {
    return folderName.toLowerCase() === "inbox";
  }

  async getFolderMailIdList(
    folderName: string,
    start: number,
    size: number,
    order: Order
  ): Promise<string[]> {
    if (this._mailId2Index.size === 0) {
      await this.syncMailIdList(await this.getProtocol());
    }
    // debug: 只返回一个，方便调试
    // return [this._mailId2Index.keys().next().value]
    const idList = new Array<string>(size);
    this._mailId2Index.forEach((v, k) => {
      if (v >= start && v < start + size) {
        idList[v - 1] = k;
      }
    });
    return idList.filter(v => !!v);
  }

  moveMail(mailId: string, folderName: string): Promise<string> {
    throw new CMError("method moveMail not implemented", ErrorCode.NOT_IMPLEMENTED);
  }
  copyMail(mailId: string, folderName: string): Promise<string> {
    throw new CMError("method copyMail not implemented", ErrorCode.NOT_IMPLEMENTED);
  }
  addMail(mail: string, folderName: string): Promise<string> {
    throw new CMError("method addMail not implemented", ErrorCode.NOT_IMPLEMENTED);
  }

  async deleteMail(folderName:string, mailId: string): Promise<void> {
    const protocol = await this.getProtocol();
    const success = await protocol.dele(
      await this.getMailIndex("inbox", mailId, { by: "date", desc: true })
    );
    await protocol.quit();
    protocol.stop();
    if (!success) {
      throw new CMError("delete mail failed", ErrorCode.DELETE_MAIL_FAILED);
    }
  }

  searchMail(query: Query): Promise<string[]> {
    throw new CMError("method searchMail not supported", ErrorCode.NOT_SUPPORTED);
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
    throw new CMError("method on not supported", ErrorCode.NOT_SUPPORTED);
  }
}
