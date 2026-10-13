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
  IFolder,
  IMail,
  IStore,
  Order,
  Query,
  IBuffer,
} from "../api";
import { FolderType, CMError, ErrorCode,  StoreFeature } from "../api";
import { Mail } from "./mail";
import { Atoms } from "../protocols/imap_protocol";
import { EventHandler, LRUCache } from "../utils/common";
import type { FolderData } from "../api";
import { getLogger } from "../utils/log";
import type { MailEngine } from './engine';

const logger = getLogger("folder");


type ValueKeys = Pick<Folder, "_mailCount" | "_recentCount" | "_unreadCount">;
export class Folder implements IFolder {
  private store: IStore;
  _engine: MailEngine;
  _name: string;
  _fullName: string;
  _type: FolderType;

  _mailCount?: number;
  _recentCount?: number;
  _unreadCount?: number;
  _subFolders: Folder[] = [];

  //暂时修改为0,同步时修改邮件标志需要同步缓存.
  _mailCache = new LRUCache<IMail>((mail: IMail) => mail.getId(), 0, 60 * 1000);

  _events: EventHandler = new EventHandler();

  constructor(folderData: FolderData, store: IStore, engine: MailEngine) {
    this._engine = engine;
    this.store = store;
    this._name = folderData.name;
    this._fullName = folderData.fullName;
    const folderType = folderData.type!;
    this._type = folderType;
  }

  getName(): string {
    return this._name;
  }

  getFullName(): string {
    return this._fullName;
  }

  getType(): FolderType {
    return this._type;
  }

  async open(): Promise<string> {
    const fd = await this.store.openFolder(this._fullName);
    this._mailCount = fd.mailCount;
    this._unreadCount = fd.unreadCount;
    this._recentCount = fd.recent;
    return "";
  }

  close(): Promise<void> {
    return this.store.closeFolder(this._fullName);
  }

  isOpen(): boolean {
    return this.store.isFolderOpen(this._fullName);
  }
  addMail(mime: string): Promise<string> {
    return this.store.addMail(mime, this._fullName);
  }

  async getSubFolders(): Promise<IFolder[]> {
    if (this._subFolders.length == 0) {
      const folderDataList = await this.store.getFolderList(this._fullName);
      this._subFolders = folderDataList.map(folderData => new Folder(folderData, this.store, this._engine));
    }
    return this._subFolders;
  }

  async getSubFolder(name: string): Promise<IFolder> {
    const folders = await this.getSubFolders();
    const folder = folders.filter(f => f.getName() == name)[0];
    if (!folder) {
      throw new CMError(`folder ${this._fullName} ${name} not found`,
        ErrorCode.FOLDER_NOT_FOUND);
    }
    return folder;
  }

  async createSubFolder(name: string): Promise<IFolder> {
    let folder: Folder = await this.getSubFolder(name).catch((e): IFolder => null) as Folder;
    if (folder) {
      throw new CMError(`folder ${name} already exists`, ErrorCode.FOLDER_EXISTS);
    }
    await this.store.createSubFolder(name, this._fullName);
    //WARN: fullName确保不要以/开头.
    let fullName = this._fullName.length > 0 ? `${this._fullName}/${name}` : `${name}`
    folder = new Folder(
      {
        name: name,
        fullName: fullName,
        type: FolderType.other,
      },
      this.store,
      this._engine
    );
    this._subFolders.push(folder);
    return folder;
  }

  async deleteSubFolder(name: string): Promise<void> {
    this._subFolders = this._subFolders.filter(f => f.getName() != name);
    await this.store.deleteFolder(
      this._fullName.length ? `${this._fullName}/${name}` : name
    );
  }

  async renameFolder(name: string): Promise<void> {
    await this.store.renameFolder(this._fullName, name);
    this._fullName = name;
    this._name = name.split('/').pop()!;
  }

  async getMails(range: [number, number], order?: Order): Promise<IMail[]> {
    logger.error("deprecated");
    if (!this.isOpen()) {
      await this.open();
    }
    if (!order) {
      order = { by: "date", desc: true };
    }
    const mailIdList = await this.store.getFolderMailIdList(
      this._fullName,
      range[0],
      range[1] - range[0] + 1,
      order
    );
    return mailIdList.map(mailId => {
      const m = new Mail(mailId, this, this.store);
      return m;
    });
  }

  async getMailList(
    size: number,
    startMailId?: string,
    order?: Order
  ): Promise<IMail[]> {
    if (this._type > FolderType.virtual) { // 虚拟文件夹，特殊处理
      if (!this.store.hasFeature(StoreFeature.VirtualFolder)) {
        throw new CMError("not supported", ErrorCode.NOT_SUPPORTED);
      }
      if (this._type == FolderType.important) {
        if (startMailId) { // 每次都全部返回，不会有下一页的情况。 TODO: 分页优化
          return [];
        }
        const res = await this.store.filterMail({isFlagged: true});
        const mails: IMail[] = [];
        for (const [folderFullName, mailIdList] of res.entries()) {
          const folder: IFolder = await this._engine.getFolder(folderFullName).catch((e):IFolder => {
            logger.error("get folder failed", folderFullName);
            return null;
          });
          if (!folder) {
            continue;
          }
          for (const mailId of mailIdList) {
            const mail:IMail = await folder.getMail(mailId).catch((e):IMail => {
              logger.error("get mail failed", folderFullName, mailId);
              return null;
            })
            if (mail) {
              mails.push(mail);
            }
          }
        }
        return mails;
      }
    }
    let start = 1;
    if (!order) {
      order = {
        by: "date",
        desc: true,
      };
    }
    if (startMailId) {
      start = await this.store.getMailIndex(this._fullName, startMailId, order)
        .catch(err => {
          logger.error("get mail index failed", err);
          throw new CMError("get mail list failed because mailId not found", ErrorCode.MAIL_NOT_FOUND);
        });
      start += 1;
    }
    const mailIdList = await this.store.getFolderMailIdList(
      this._fullName,
      start,
      size,
      order
    );
    return mailIdList.map(mailId => this._getMail(mailId));
  }

  /**
   * pop3会从db获取数据刷新
   * imap会从server那里获取刷新
   * @returns
   */
  async refresh(): Promise<void> {
    const data = await this.store.getFolderInfo(this._fullName);
    logger.debug(`[__pop3] [unread count is: ${data.unreadCount} ]`);
    this._mailCount = data.mailCount;
    this._recentCount = data.recent;
    this._unreadCount = data.unreadCount;
  }

  async getValue(key: keyof ValueKeys): Promise<number> {
    if (!this[key]) {
      const data = await this.store.getFolderInfo(this._fullName);
      logger.debug(`[folder][__folder][get folder info] [${JSON.stringify(data)}]`)
      this._mailCount = data.mailCount;
      this._recentCount = data.recent;
      this._unreadCount = data.unreadCount;
    }
    return this[key]!;
  }

  async getMailCount(): Promise<number> {
    return this.getValue("_mailCount");
  }

  async getUnreadMailCount(): Promise<number> {
    return this.getValue("_unreadCount");
  }

  async getRecentCount(): Promise<number> {
    return this.getValue("_unreadCount");
  }

  _getMail(mailId: string): IMail {
    let mail = this._mailCache.get(mailId);
    if (!mail) {
      mail = new Mail(mailId, this, this.store);
      this._mailCache.add(mail);
    }
    return mail;
  }

  getMail(mailId: string): Promise<IMail>;
  getMail(mailIndex: number, order: Order): Promise<IMail>;
  async getMail(mailId: string | number, order?: Order): Promise<IMail> {
    if (!order) {
      order = { by: "date", desc: true };
    }
    if (typeof mailId == "number") {
      const mails = await this.store.getFolderMailIdList(
        this._fullName,
        mailId,
        1,
        order
      );
      mailId = mails[0];
    }
    return this._getMail(mailId);
  }

  async searchMail(query: Omit<Query, "folder">): Promise<string[]> {
    let res: string[] = [];
    if (this._type != FolderType.root) {
      res = await this.store.searchMail({
        ...query,
        folder: this._fullName,
      });
    }
    const subFolders = await this.getSubFolders();
    const subRes = await Promise.all(
      subFolders.map(folder => folder.searchMail(query))
    );
    subRes.reduce((a, b) => a.concat(b), res);
    return res;
  }

  async getMailIndex(mailId: string, order: Order): Promise<number> {
    if (!this.isOpen()) {
      await this.open();
    }
    const index = await this.store.getMailIndex(this._fullName, mailId, order);
    return index;
  }

  on(
    event: "new-mails" | "mail-deleted",
    handler: Function
  ): void {
    this._events.on(event, handler);
  }
}
