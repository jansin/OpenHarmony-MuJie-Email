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

/*
* 实现 IMailStorage接口，但是使用内存做存储，只是演示IMailStorage的用法
 */

import type {
  MailStructure,
  FolderData,
  IBuffer,
  MailDataAny,
  FolderType,
  Query,
  Order,
  MailBasic,
  IMailStorage,
  Filter,
  Mime,
} from "../api";
import { CMError, MailAttribute, ErrorCode } from "../api";
import { getLogger } from "../utils/log";
import { parseMime2 } from '../utils/mime';

const logger = getLogger('mem-storage');

export class MemMailStorage implements IMailStorage {
  _folderDataList?: FolderData[];
  _allMail: Map<string, MailBasic> = new Map();
  _mailFull: [string, Mime][] = [];
  _folderSortedBySizeMailList: Map<string, MailBasic[]> = new Map();
  _folderSortedByDateMailList: Map<string, MailBasic[]> = new Map();
  constructor() {
  }

  async release(): Promise<void> {
    throw new CMError('Method not implemented.', ErrorCode.NOT_IMPLEMENTED);
  }

  setFolderInfo(folderData: FolderData): Promise<void> {
    throw new CMError('Method not implemented.', ErrorCode.NOT_IMPLEMENTED);
  }

  getFolderInfo(fullName: string): Promise<FolderData> {
    throw new CMError('Method not implemented.', ErrorCode.NOT_IMPLEMENTED);
  }


  setMailAttributes(mailId: string, folderFullName: string, attributes: MailAttribute[], modifyType: '' | '+' | '-'): Promise<MailAttribute[]> {
    throw new CMError('Method not implemented.', ErrorCode.NOT_IMPLEMENTED);
  }

  copyMail(srcFolderFullName: string, srcMailId: string, dstFolderFullName: string, dstMailId: string): Promise<void> {
    throw new CMError('Method not implemented.', ErrorCode.NOT_IMPLEMENTED);
  }

  moveMail(srcFolderFullName: string, srcMailId: string, dstFolderFullName: string, dstMailId: string): Promise<void> {
    throw new CMError('Method not implemented.', ErrorCode.NOT_IMPLEMENTED);
  }

  deleteMail(folderFullName: string, mailId: string): Promise<void> {
    throw new CMError('Method not implemented.', ErrorCode.NOT_IMPLEMENTED);
  }

  setFolderList(folderList: FolderData[]): Promise<void> {
    this._folderDataList = folderList;
    return Promise.resolve();
  }
  getFolderList(): Promise<FolderData[]> {
    return Promise.resolve(this._folderDataList || []);
  }
  getFolderMailIdList(
    folderName: string,
    start: number,
    size: number,
    order: Order
  ): Promise<string[]> {
    let mailList: MailDataAny[];
    if (order.by == "size") {
      mailList = this._folderSortedBySizeMailList.get(folderName) || [];
    } else {
      mailList = this._folderSortedByDateMailList.get(folderName) || [];
    }
    if (order.desc) {
      mailList = [...mailList].reverse();
    }
    const result = mailList.slice(start - 1, start + size - 1);
    return Promise.resolve(result.map(mail => mail.id));
  }

  async addMail(folderFullName: string, mailId: string, mail: IBuffer): Promise<void> {
    const MAX_CACHE_SIZE = 20;
    const mime = await parseMime2(mail)
    this._mailFull.push([mailId, mime]);
    if (this._mailFull.length >= MAX_CACHE_SIZE) {
      this._mailFull.shift();
    }
    return Promise.resolve();
  }

  checkMailExist(mailIdList: string[]): Promise<{basic: boolean, full: boolean}[]> {
    return Promise.resolve(mailIdList.map(mailId => ({
      basic: this._allMail.has(mailId),
      full: false
    })));
  }

  hasMail(folderFullName: string, mailId: string): Promise<boolean> {
    const mailList = this._folderSortedBySizeMailList.get(folderFullName);
    let exist = false;
    if (mailList) {
      const r = mailList.filter(m => m.id == mailId);
      exist = r.length > 0;
    }
    return Promise.resolve(exist)
  }
  getMailIndex(
    folderFullName: string,
    mailId: string,
    order: Order
  ): Promise<number> {
    let mailList: MailBasic[];
    if (order.by == "date") {
      mailList = this._folderSortedByDateMailList.get(folderFullName);
    } else if (order.by == "size") {
      mailList = this._folderSortedBySizeMailList.get(folderFullName);
    } else {
      return Promise.reject(new CMError(`not supported order ${order.by}`, ErrorCode.NOT_SUPPORTED))
    }
    if (mailList) {
      let index = mailList.findIndex(mail => mail.id == mailId);
      if (index >= 0) {
        if (order.desc) {
          index = mailList.length - index;
        }
        return Promise.resolve(index);
      }
    }
    return Promise.reject(new CMError(`mail not found ${mailId}`, ErrorCode.MAIL_NOT_FOUND));
  }

  addMailBasicList(folderFullName: string, newMailList: MailBasic[]): void {
    // 过滤已有的
    newMailList = newMailList.filter(mail => {
      if (!this._allMail.has(mail.id)) {
        this._allMail.set(mail.id, mail);
        return true;
      }
      return false;
    });
    let mailList = this._folderSortedBySizeMailList.get(folderFullName);
    if (!mailList) {
      mailList = newMailList;
    } else {
      mailList = mailList.concat(newMailList);
    }
    mailList.sort((a, b) => a.size - b.size)
    this._folderSortedBySizeMailList.set(folderFullName, mailList);

    mailList = this._folderSortedByDateMailList.get(folderFullName);
    if (!mailList) {
      mailList = newMailList;
    } else {
      mailList = mailList.concat(newMailList);
    }
    mailList.sort((a, b) => {
      let ad = a.envelope?.date;
      let bd = b.envelope?.date;
      if (!ad) {
        return 1;
      } else if (!bd) {
        return -1;
      } else {
        return ad.getTime() - bd.getTime();
      }
    })
    this._folderSortedByDateMailList.set(folderFullName, mailList);
  }

  getMailPartContent(
    folderFullName: string,
    mailId: string,
    partId: string
  ): Promise<IBuffer> {
    const d = this._mailFull.filter(m => m[0] == mailId)[0];
    if (!d) {
      return Promise.reject(new CMError('mail not found', ErrorCode.MAIL_NOT_FOUND));
    }
    const mime = d[1];
    const parts = partId.split('.').map(p => parseInt(p));
    let m = mime;
    for (const part of parts) {
      if (!m.children[part - 1]) {
        break;
      }
      m = m.children[part - 1];
    }
    return Promise.resolve(m.body);
  }

  getMailBasic(
    folderFullName: string,
    mailId: string
  ): Promise<MailBasic> {
    const mailList = this._folderSortedBySizeMailList.get(folderFullName) || [];
    for (const mail of mailList) {
      if (mail.id == mailId) {
        return Promise.resolve(mail);
      }
    }
    return Promise.reject(new CMError("no mail", ErrorCode.MAIL_NOT_FOUND))
  }
  searchMail(query: Query): Promise<string[]> {
    if (!query.folder || query.folder.length == 0) {
      return new Promise(resolve => resolve(new Array<string>()));
    }
    let mails = this._folderSortedByDateMailList.get(query.folder);
    if (!mails) {
      return Promise.resolve(new Array<string>());
    }
    const matches = mails.filter(m => {
      if (query.fields.from) {
        const queryFrom = query.fields.from;
        if (m.envelope!.from.name.search(queryFrom) != -1) {
          return m;
        }
        if (m.envelope!.from.email.search(queryFrom) != -1) {
          return m;
        }
      }
      if (query.fields.to) {
        const queryTo = query.fields.to;
        const index = m.envelope!.to.findIndex(item => {
          if (item.name.search(queryTo) != -1) {
            return item;
          }
          if (item.email.search(queryTo) != -1) {
            return item;
          }
        });
        if (index != -1) {
          return m;
        }
      }
      if (query.fields.subject) {
        const querySubject = query.fields.subject;
        if (m.envelope!.subject.search(querySubject) != -1) {
          return m;
        }
      }
      if (query.fields.attachment) {
        const queryFileName = query.fields.attachment;
        const fileMatch = this.searchAttachment(m.structure!, queryFileName);
        if (fileMatch) {
          return m;
        }
      }
    });

    return Promise.resolve(matches.map(m => m.id));
  }

  searchAttachment(struct: MailStructure | null, keyword: string): boolean {
    return false;
    /*
    if (!struct) {
      return false;
    }
    let result: boolean = false;
    const ms = struct as MailTextStructure;
    if (!!(ms.disposition?.type == "attachment")) {
      result = (ms.disposition?.params.filename != undefined) ? (ms.disposition?.params.filename.search(keyword) != -1) : false;
      result = result || ((ms.params.name != undefined) ? ms.params.name.search(keyword) != -1 : false);
    }
    const st = struct as MailMultipartStructure;
    if (st.subParts) {
      for (const sub of st.subParts) {
        result = result || this.searchAttachment(sub, keyword);
      }
    }
    return result;
    * */
  }

  filterMail(filter: Filter): Promise<Map<string, string[]>> {
    const res: Map<string, string[]> = new Map();
    for (const [k, mails] of this._folderSortedByDateMailList) {
      const ms: string[] = [];
      for (const v of mails) {
        if (v.attributes.includes(MailAttribute.Flagged)) {
          ms.push(v.id);
        }
      }
      if (ms.length > 0) {
        res.set(k, ms);
      }
    }
    return Promise.resolve(res);
  }
}
