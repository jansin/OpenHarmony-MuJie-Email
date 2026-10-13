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

import { getMimeDecodedBody, getMimeParts,
} from "../utils/mime";
import type {
  IFolder,
  IMail,
  IStore,
  EmailAddress,
  MailStructure,
  IBuffer,
  Mime
} from "../api";
import { CMError, ErrorCode, MailAttribute, } from "../api";
import { base64Decode, decodeCharset, qpDecode } from "../utils/encodings";
import { EventHandler } from "../utils/common";
import { getLogger } from "../utils/log";
import { createBuffer } from "../utils/file_stream";

const logger = getLogger("mail");

type ValueKeys = Pick<
  Mail,
  | "_from"
  | "_to"
  | "_cc"
  | "_bcc"
  | "_subject"
  | "_date"
  | "_struct"
  | "_size"
  | "_attributes"
>;
export class Mail implements IMail {
  folder: IFolder;
  id: string;
  store: IStore;
  _events: EventHandler = new EventHandler();

  _from?: EmailAddress;
  _to?: EmailAddress[];
  _cc?: EmailAddress[];
  _bcc?: EmailAddress[];
  _subject?: string;
  _date?: Date;

  _struct?: MailStructure;
  _html?: string;
  _plain?: string;

  _attributes?: MailAttribute[];
  _size?: number;
  _inited: boolean = false;

  constructor(id: string, folder: IFolder, store: IStore) {
    this.id = id;
    this.folder = folder;
    this.store = store;
  }

  getId(): string {
    return this.id;
  }

  on(
    event: "attr-changed" | "seen-changed" | "flagged-changed",
    handler: Function
  ): void {
    this._events.on(event, handler);
  }

  async init(): Promise<void> {
    if (this._inited) {
      return;
    }
    try {
      const mailBasic = await this.store.getMailBasic(
        this.folder.getFullName(),
        this.id
      );
      logger.trace(`[__draft] [mail] [get mail basic ${this.id}]`)
      const envelope = mailBasic.envelope;
      this._struct = mailBasic.structure;
      this._from = envelope.from;
      this._to = envelope.to;
      this._bcc = envelope.bcc;
      this._cc = envelope.cc;
      this._subject = envelope.subject;
      this._date = envelope.date;
      this._size = mailBasic.size;
      this._attributes = mailBasic.attributes;
    } catch (e) {
      logger.error("get mail basic failed", e);
      throw new CMError(`parse mail failed ${this.id}`, ErrorCode.PARSE_MAIL_FAILED)
    } finally {
      this._inited = true;
    }
  }

  async getValue(key: keyof ValueKeys): Promise<Mail[keyof ValueKeys]> {
    if (this[key] === undefined || this[key] === null) {
      await this.init();
      if (!this[key]) {
        this._inited = false;
        logger.error("init data failed", key, this.id);
        throw new CMError(`${key} not found ${this.id}`, ErrorCode.UNKNOWN_ERROR)
        // return Promise.reject(`${key} not found ${this.id}`);
      }
    }
    return this[key];
  }

  async getFrom(): Promise<EmailAddress> {
    return this.getValue("_from") as Promise<EmailAddress>;
  }

  getTo(): Promise<EmailAddress[]> {
    return this.getValue("_to") as Promise<EmailAddress[]>;
  }

  getCc(): Promise<EmailAddress[]> {
    return this.getValue("_cc") as Promise<EmailAddress[]>;
  }

  getBcc(): Promise<EmailAddress[]> {
    return this.getValue("_bcc") as Promise<EmailAddress[]>;
  }

  getSubject(): Promise<string> {
    return this.getValue("_subject") as Promise<string>;
  }

  getDate(): Promise<Date> {
    return this.getValue("_date") as Promise<Date>;
  }

  getSize(): Promise<number> {
    return this.getValue("_size") as Promise<number>;
  }

  async getAttachmentInfoList(): Promise<MailStructure[]> {
    const struct = (await this.getValue("_struct")) as MailStructure;
    if (!struct) {
      return [];
    }
    return getMimeParts(struct,
      (mime) => !!mime.disposition?.type.startsWith("attachment"))
  }

  async getInlineImageInfoList(): Promise<MailStructure[]> {
    const struct = (await this.getValue("_struct")) as MailStructure;
    if (!struct) {
      return [];
    }
    return getMimeParts(struct, (mime) => {
      let isInline = !!(mime.disposition?.type == "inline");
      if (!isInline && mime.contentType.type == 'image' && mime.contentId) {
        isInline = true;
      }
      return isInline;
    })
  }

  async getAttachment(index: number): Promise<IBuffer> {
    const structs = await this.getAttachmentInfoList();
    if (structs.length == 0 || structs.length <= index) {
      throw new CMError("attachment not found", ErrorCode.ATTACHMENT_NOT_FOUND);
    }
    const struct = structs[index];
    return this._getAttachment(struct);
  }

  async getInlineImage(index: number): Promise<IBuffer> {
    const structs = await this.getInlineImageInfoList();
    if (structs.length == 0 || structs.length <= index) {
      throw new CMError("inline image not found", ErrorCode.INLINE_IMAGE_NOT_FOUND);
    }
    const struct = structs[index];
    return this._getAttachment(struct);
  }

  async _getAttachment(struct: MailStructure): Promise<IBuffer> {
    const buff = await this.store.getMailPartContent(
      this.folder.getFullName(),
      this.id,
      struct.partId
    );
    const mime: Mime = {
      ...struct, body: buff, headers: new Map(), children: []
    }
    const res = getMimeDecodedBody(mime);
    return res;
  }

  async getText(textType: "html" | "plain"): Promise<string> {
    const struct = (await this.getValue("_struct")) as MailStructure;
    // logger.debug(JSON.stringify(struct, null, 2));
    if (!struct) {
      // todo: 重新获取整份邮件进行解析
      return "";
    }
    if (textType == "html" && this._html) {
      return this._html;
    } else if (textType == "plain" && this._plain) {
      return this._plain;
    }
    const parts = getMimeParts(struct, (struct: MailStructure) => {
      const ms = struct;
      if (ms.disposition?.type == "attachment") {
        return false;
      }
      const t = (ms.contentType.type || "").toLowerCase();
      const sub = (ms.contentType.subType || "").toLowerCase();
      if (textType == "plain") {
        return t == "text" && sub == "plain";
      }
      if (t == "text" && (sub == "html" || sub == "xhtml+xml")) {
        return true;
      }
      return t == "application" && sub == "xhtml+xml";
    });
    if (parts.length === 0) {
      const s = `text/${textType} not found`;
      logger.error(s);
      return Promise.reject(s);
    }
    const part = parts[0];
    const partId = part.partId;
    const stream = await this.store.getMailPartContent(
      this.folder.getFullName(),
      this.id,
      partId
    );
    const mime: Mime = {
      ...part, body: stream, headers: new Map(), children: []
    }
    const res = getMimeDecodedBody(mime);
    const s = await res.readAll();
    return s;
  }

  getHtml(): Promise<string> {
    return this.getText("html").catch(e => {
      logger.error("get html failed", e);
      return "";
    });
  }

  getPlain(): Promise<string> {
    return this.getText("plain").catch(e => {
      logger.error("get plain failed", e);
      return "";
    });
  }

  async getDigest(n: number): Promise<string> {
    const plain = await this.getPlain();
    return plain.substring(0, n);
  }

  async hasAttribute(attr: MailAttribute): Promise<boolean> {
    const attributes = (await this.getValue("_attributes")) as MailAttribute[];
    if (!attributes) {
      return false;
    }
    return attributes.includes(attr);
  }

  async setAttributes(
    attrs: MailAttribute[],
    modifyType: "+" | "-" | "" = ""
  ): Promise<void> {
    logger.trace(`[__imap] [syncstore set attr]`)
    const attributes = await this.store.setMailAttributes(
      this.folder.getFullName(), this.id, attrs, modifyType)
    logger.trace(`[__imap] [cache set attr]`)
    this._attributes = attributes;
  }

  async isSeen(): Promise<boolean> {
    return this.hasAttribute(MailAttribute.Seen);
  }

  setSeen(isSeen: boolean): Promise<void> {
    return this.setAttributes([MailAttribute.Seen], isSeen ? "+" : "-");
  }

  isFlagged(): Promise<boolean> {
    return this.hasAttribute(MailAttribute.Flagged);
  }

  setFlagged(isFlagged: boolean): Promise<void> {
    return this.setAttributes([MailAttribute.Flagged], isFlagged ? "+" : "-");
  }

  isAnswered(): Promise<boolean> {
    return this.hasAttribute(MailAttribute.Answered);
  }

  setAnswered(isAnswered: boolean): Promise<void> {
    return this.setAttributes([MailAttribute.Answered], isAnswered ? "+" : "-");
  }

  async getAttributes(): Promise<MailAttribute[]> {
    const attributes = (await this.getValue("_attributes")) as MailAttribute[];
    if (!attributes) {
      return [];
    }
    return [...attributes];
  }

  getFolder(): IFolder {
    return this.folder;
  }

  async delete(): Promise<void> {
    await this.store.deleteMail(this.folder.getFullName(), this.id);
    await this.folder.refresh();
    return
  }

  copyTo(folder: IFolder): Promise<string> {
    return this.store.copyMail(
      this.folder.getFullName(),
      this.id,
      folder.getFullName()
    );
  }

  async moveTo(folder: IFolder): Promise<string> {
    let mid = await this.store.moveMail(
      this.folder.getFullName(),
      this.id,
      folder.getFullName()
    )
    let isNew = this.isSeen();
    if(isNew) {
      await this.folder.refresh();
      await folder.refresh();
    }
    return mid;
  }
}
