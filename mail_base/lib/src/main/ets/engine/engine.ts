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
  ITransport,
  IFolder,
  IMail,
  Properties,
  MailEnvelope,
  InlineImage,
  Attachment,
  MailData,
  IEmlParser,
  EmailAddress,

  IBufferCreator,
  BufferHint,
  IBuffer,

  Mime,
} from "../api";
import { CMError, ErrorCode, FolderType, StoreFeature, } from "../api";
import { Folder } from "./folder";
import { Mail } from "./mail";
import { ImapStore } from "../store/store";
import { SmtpTransport } from "../transport/transport";
import { EmlParser } from "../format/eml";
import { getLogger } from "../utils/log";
import { Pop3Store } from "../store/pop3_store";
import { setBufferCreator } from "../utils/file_stream";
import { MemMailStorage } from '../store/mem_storage';

const logger = getLogger("engine");

function getDefaultStore(prop: Properties): IStore {
  let store: IStore;
  if (prop.imap) {
    store = new ImapStore();
    store.setProperties(prop);
  } else if (prop.pop3) {
    store = new Pop3Store();
    store.setProperties(prop);
  } else {
    throw new CMError("need `pop3' or `imap'", ErrorCode.PARAMETER_ERROR);
  }
  return store;
}
export class MailEngine implements IEmlParser {
  name: string = "mailengine";
  _transport?: ITransport;
  _store?: IStore;

  _rootFolder?: IFolder;
  _inbox?: IFolder;
  _draft?: IFolder;
  _sent?: IFolder;
  _properties?: Properties;
  _syncTimer?: number;

  _emlParser: IEmlParser = new EmlParser();

  constructor(bufferCreator?: IBufferCreator) {
    if (bufferCreator) {
      setBufferCreator(bufferCreator);
    }
  }

  async getRootFolder(): Promise<IFolder> {
    if (!this._rootFolder) {
      this._rootFolder = new Folder(
        { name: "", fullName: "", type: FolderType.root },
        this.getStore(),
        this
      );
    }
    return this._rootFolder;
  }

  async getInbox(): Promise<IFolder> {
    if (!this._inbox) {
      const root = await this.getRootFolder();
      const folders = await root.getSubFolders();
      this._inbox = folders.filter(
        folder => folder.getType() === FolderType.inbox
      )[0];
    }
    return this._inbox;
  }

  async getFolder(folderFullName: string): Promise<IFolder> {
    if (!folderFullName || folderFullName.length == 0) {
      return this.getRootFolder();
    }
    const parts = folderFullName.split('/');
    let folder = await this.getRootFolder();
    for (const part of parts) {
      folder = await folder.getSubFolder(part);
    }
    return folder;
  }

  async getDraft(): Promise<IFolder> {
    if (!this._draft) {
      const root = await this.getRootFolder();
      const folders = await root.getSubFolders();
      this._draft = folders.filter(
        folder => folder.getType() === FolderType.draft
      )[0];
    }
    return this._draft;
  }

  async getSent(): Promise<IFolder> {
    if (!this._sent) {
      const root = await this.getRootFolder();
      const folders = await root.getSubFolders();
      this._sent = folders.filter(
        folder => folder.getType() === FolderType.sent
      )[0];
    }
    return this._sent;
  }

  getTransport(): ITransport {
    if (!this._transport) {
      this._transport = new SmtpTransport();
    }
    return this._transport;
  }

  setProperties(prop: Properties): void {
    this._properties = prop;
    if (!this._store) {
      this._store = getDefaultStore(prop);
    }
    this.getStore().setProperties(prop);
    this.getTransport().setProperties(prop);
  }

  getStore(): IStore {
    if (!this._store) {
      // this._store = new ImapStore();
      // this._store = new MemCacheImapStore();
      throw new CMError("no store", ErrorCode.PARARMETER_MISSED);
    }
    return this._store;
  }

  setSyncInterval(interval: number): void {
    if (this._syncTimer) {
      clearInterval(this._syncTimer);
    }
    const store = this.getStore();
    if (store.hasFeature(StoreFeature.NeedToSync)) {
      this._syncTimer = setInterval(() => store.sync && store.sync(), interval);
    }
  }

  sync(): void {
    const store = this.getStore();
    logger.debug("sync", store.hasFeature(StoreFeature.NeedToSync), store.sync);
    if (store.hasFeature(StoreFeature.NeedToSync) && store.sync) {
      store.sync();
    }
  }

  registerStore(store: IStore): void {
    this._store = store;
  }

  async mimeParse(
    content: string | IBuffer
  ): Promise<Mime> {
    return this._emlParser.mimeParse(content);
  }

  async search(keyword: string, types: ('subject' | 'attachment' | 'from' | 'to')[], start: number, size: number): Promise<IMail[]> {
    const rootFolder = await this.getRootFolder();
    let mails: IMail[] = [];
    try {
      mails = await this._search(keyword, rootFolder, types);
    }
    catch(e: unknown) {
      logger.error("search failed", e);
      return [];
    }
    return mails.splice(start, size)
  }

  private async _search(keyword: string, folder: IFolder, types: ('subject' | 'attachment' | 'from' | 'to')[]): Promise<IMail[]> {
    if (folder.getType() > FolderType.virtual) {
      return [];
    }
    const mids = await this._store.searchMail({
      folder: folder.getFullName(),
      fields: {
        from: types.find(value => value == 'from') ? keyword : null,
        to: types.find(value => value == 'to') ? keyword : null,
        subject: types.find(value => value == 'subject') ? keyword : null,
        attachment: types.find(value => value == 'attachment') ? keyword : null
      }
    })
    let mails = await Promise.all(mids.map(async id => {
      return folder.getMail(id)
    }))
    const subFolders = await folder.getSubFolders()
    for (const f of subFolders) {
      const subMails = await this._search(keyword, f, types)
      mails = mails.concat(subMails)
    }
    return mails
  }

  showDebugLog(show: boolean): void {}

  on(
    event: "new-mail",
    handler: (folderFullName: IFolder, mails: IMail[]) => void
  ): void;
  on(event: string, handler: Function): void;
  on(event: string, handler: Function): void {
    if (!this._store) {
      logger.error("no store", event);
      return;
    }
    if (event == "new-mail") {
      this._store.on(
        event,
        async (folderFullName: string, mailIdList: string[]) => {
          const folderParts = folderFullName.split("/");
          let folder = await this.getRootFolder();
          for (const part of folderParts) {
            folder = await folder.getSubFolder(part);
          }
          const mails = await Promise.all(
            mailIdList.map(mailId => folder.getMail(mailId))
          );
          handler(folder, mails);
        }
      );
    } else {
      this._store.on(event, handler);
    }
  }
}
