import { Account, AccountProtocol } from '../models/Account';
import { Email, EmailAddress } from '../models/Email';
import { Folder, FolderType } from '../models/Folder';
import { Attachment } from '../models/Attachment';
import { StorageService } from './StorageService';
import { Utils } from '../common/Utils';
import { LogUtil } from '../common/LogUtil';
import type { IFolder, IMail, IBuffer, Properties, IStore, ITransport } from '@coremail/mail_base';
import { MailEngine } from '@coremail/mail_base';
import { util } from '@kit.ArkTS';
import { FolderType as SdkFolderType } from '@coremail/mail_base';

interface SdkAddr {
  name: string;
  email: string;
}

function buildProperties(acct: Account): Properties {
  const username = (acct.incomingUsername || acct.email).trim();
  const password = (acct.password ?? '').trim();
  const prop: Properties = {
    userInfo: { username, password },
    smtp: {
      host: (acct.outgoingServer ?? '').trim(),
      port: acct.outgoingPort,
      secure: acct.outgoingSecurity !== 'NONE'
    },
  };
  if (acct.protocol === AccountProtocol.IMAP) {
    prop.imap = {
      host: (acct.incomingServer ?? '').trim(),
      port: acct.incomingPort,
      secure: acct.incomingSecurity !== 'NONE'
    };
  } else {
    prop.pop3 = {
      host: (acct.incomingServer ?? '').trim(),
      port: acct.incomingPort,
      secure: acct.incomingSecurity !== 'NONE'
    };
  }
  return prop;
}

function normalizeInlineContentId(cid: string): string {
  let c = (cid ?? '').trim();
  if (c.startsWith('<') && c.endsWith('>')) {
    c = c.substring(1, c.length - 1).trim();
  }
  return c;
}

function decodeCidToken(raw: string): string {
  const t = (raw ?? '').trim();
  try {
    return decodeURIComponent(t);
  } catch (e) {
    return t;
  }
}

interface CidInlineEntry {
  keyNorm: string;
  dataUrl: string;
}

function resolveCidToDataUrl(token: string, entries: CidInlineEntry[]): string | null {
  const t = normalizeInlineContentId(decodeCidToken(token)).toLowerCase();
  if (!t) {
    return null;
  }
  for (const e of entries) {
    const k = e.keyNorm.toLowerCase();
    if (t === k) {
      return e.dataUrl;
    }
  }
  for (const e of entries) {
    const k = e.keyNorm.toLowerCase();
    if (t.length >= 8 && k.length >= 8 && (t.endsWith(k) || k.endsWith(t) || t.includes(k) || k.includes(t))) {
      return e.dataUrl;
    }
  }
  return null;
}

/** �?HTML 中的 cid: 引用替换�?data: URL，便�?WebView 显示内嵌�?表格背景图等 */
async function embedCidInlineImages(sm: IMail, html: string): Promise<string> {
  if (!html || html.indexOf('cid:') < 0) {
    return html;
  }
  let out = html;
  try {
    const list = await sm.getInlineImageInfoList();
    const encoder = new util.Base64();
    const entries: CidInlineEntry[] = [];
    for (let i = 0; i < list.length; i++) {
      const st = list[i];
      const rawCid = st.contentId;
      if (!rawCid || typeof rawCid !== 'string') {
        continue;
      }
      const cid = normalizeInlineContentId(rawCid);
      if (!cid) {
        continue;
      }
      let buf: IBuffer;
      try {
        buf = await sm.getInlineImage(i);
      } catch (e) {
        continue;
      }
      const u8 = await buf.readAllRaw();
      const mimeType = `${st.contentType.type}/${st.contentType.subType}`;
      const b64 = encoder.encodeToStringSync(u8);
      const dataUrl = `data:${mimeType};base64,${b64}`;
      const row: CidInlineEntry = { keyNorm: cid, dataUrl: dataUrl };
      entries.push(row);
    }
    out = out.replace(/\bcid:([^"'\s>]+)/gi, (full: string, g1: string) => {
      const hit = resolveCidToDataUrl(g1, entries);
      return hit !== null ? hit : full;
    });
  } catch (e) {
    // embedCidInlineImages error (standalone function, no logger context)
  }
  return out;
}

export class MailSdkService {
  private static instance: MailSdkService;
  private storageService: StorageService;
  private engineCache: Record<string, MailEngine | null> = {};
  private logger: LogUtil = new LogUtil('MailSdkService');

  private constructor(storageService: StorageService) {
    this.storageService = storageService;
  }

  static getInstance(storageService: StorageService): MailSdkService {
    if (!MailSdkService.instance) {
      MailSdkService.instance = new MailSdkService(storageService);
    }
    return MailSdkService.instance;
  }

  private async sdkMailHasAttachments(mail: IMail): Promise<boolean> {
    const list = await mail.getAttachmentInfoList();
    return list.length > 0;
  }

  async testConnect(acct: Account): Promise<boolean> {
    let store: IStore | null = null;
    try {
      // 测试连接必须使用当前表单凭证；勿复用 getEngine 缓存，否则会沿用旧密�?�?TCP 会话导致「授权码已改仍失败�?
      const engine = new MailEngine();
      engine.setProperties(buildProperties(acct));
      store = engine.getStore();
      await store.check();
      return true;
    } catch (e) {
      this.logger.e('SDK testConnect error: ' + JSON.stringify(e));
      return false;
    } finally {
      if (store) {
        try {
          await store.release();
        } catch (e) {
          /* 忽略断开时的清理错误 */
        }
      }
    }
  }

  async fetchFolders(acct: Account): Promise<Folder[]> {
    try {
      await this.ensureConnected(acct);
      const engR = await this.getEngine(acct);
const root = await engR.getRootFolder();
      const sdkFolders = await root.getSubFolders();
      const result: Folder[] = [];
      for (const sf of sdkFolders) {
        const ft = this.toLocalFolderType(sf.getType());
        const f: Folder = {
          id: acct.id + '_' + sf.getFullName(),
          accountId: acct.id,
          name: sf.getName(),
          fullName: sf.getFullName(),
          type: ft,
          totalCount: 0,
          unreadCount: await sf.getUnreadMailCount().catch(() => 0),
          isSynced: false,
          selectable: true,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        };
        result.push(f);
        if (ft === FolderType.CUSTOM) {
          await this.storageService.saveFolder(f);
        }
      }
      return result;
    } catch (e) {
      this.logger.e('SDK fetchFolders error: ' + JSON.stringify(e));
      return [];
    }
  }

  async fetchEmails(acct: Account, folder: Folder, limit: number): Promise<Email[]> {
    try {
      this.logger.i('SDK fetchEmails: ' + acct.email + ' folder: ' + folder.fullName + ' limit: ' + limit);
      await this.ensureConnected(acct);
      const engM = await this.getEngine(acct);
      let sdkFolder: IFolder;
      try {
        sdkFolder = await engM.getFolder(folder.fullName);
      } catch (e) {
        this.logger.w('SDK getFolder failed, trying getInbox');
        sdkFolder = await engM.getInbox();
      }
      const sdkMails: IMail[] = await sdkFolder.getMailList(limit);
      this.logger.i('SDK fetchEmails got ' + sdkMails.length + ' mails');
      const result: Email[] = [];
      const msgIdSet = new Set<string>();
      const existingEmails = await this.storageService.getEmailsByFolderId(folder.id, 0, 9999);
      for (const old of existingEmails) {
        if (old.messageId && old.messageId.length > 0) {
          msgIdSet.add(old.messageId);
        }
      }
      for (const sm of sdkMails) {
        const msgId = sm.getId();
        const existing = existingEmails.find(e => e.messageId === msgId);
        const e: Email = {
          id: existing ? existing.id : Utils.generateId(),
          accountId: acct.id,
          folderId: folder.id,
          messageId: msgId,
          subject: await sm.getSubject(),
          from: await this.toEmailAddress(sm.getFrom()),
          to: await this.toEmailAddressList(sm.getTo()),
          date: (await sm.getDate()).getTime(),
          bodyText: '',
          bodyHtml: '',
          preview: await sm.getDigest(80),
          isRead: await sm.isSeen(),
          isStarred: await sm.isFlagged(),
          isDeleted: false, isDraft: false, isAnswered: false, isForwarded: false,
          hasAttachments: await this.sdkMailHasAttachments(sm),
          attachments: [],
          isSynced: true,
          size: await sm.getSize(),
          createdAt: existing ? existing.createdAt : Date.now(),
          updatedAt: Date.now(),
        };
        result.push(e);
        await this.storageService.saveEmail(e);
      }
      return result;
    } catch (e) {
      this.logger.e('SDK fetchEmails error: ' + JSON.stringify(e));
      const detail = e instanceof Error ? e.message : String(e);
      throw new Error(detail);
    }
  }

  async fetchEmailBody(acct: Account, email: Email): Promise<Email> {
    try {
      await this.ensureConnected(acct);
      const folderName = this.getSdkFolderName(acct, email.folderId);
      const engF = await this.getEngine(acct);
      let sdkFolder: IFolder;
      try {
        sdkFolder = await engF.getFolder(folderName);
      } catch (firstErr) {
        const up = folderName.toUpperCase();
        if (up === 'INBOX' || up.endsWith('/INBOX')) {
          sdkFolder = await engF.getInbox();
        } else {
          const rethrowMsg = firstErr instanceof Error ? firstErr.message : String(firstErr);
          throw new Error(rethrowMsg);
        }
      }
      const sm: IMail = await sdkFolder.getMail(email.messageId);
      email.from = await this.toEmailAddress(sm.getFrom());
      email.to = await this.toEmailAddressList(sm.getTo());
      email.cc = await this.toEmailAddressList(sm.getCc());
      const bccList = await this.toEmailAddressList(sm.getBcc());
      email.bcc = bccList.length > 0 ? bccList : undefined;
      email.bodyText = await sm.getPlain();
      email.bodyHtml = await embedCidInlineImages(sm, await sm.getHtml());
      email.preview = await sm.getDigest(100);
      email.syncError = undefined;
      return email;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.logger.e('SDK fetchEmailBody error: ' + JSON.stringify(e));
      email.syncError = msg;
      return email;
    }
  }

  async markAsRead(acct: Account, email: Email): Promise<boolean> {
    return this.setMailAttribute(acct, email, 'seen', true);
  }

  async starEmail(acct: Account, email: Email, starred: boolean): Promise<boolean> {
    return this.setMailAttribute(acct, email, 'flagged', starred);
  }

  async deleteEmail(acct: Account, email: Email): Promise<boolean> {
    return this.setMailAttribute(acct, email, 'deleted', true);
  }

  async moveEmail(acct: Account, email: Email, destFolderFullName: string): Promise<boolean> {
    try {
      await this.ensureConnected(acct);
      const engine = await this.getEngine(acct);
      const sdkFolder: IFolder = await engine.getFolder(this.getSdkFolderName(acct, email.folderId));
      const sm: IMail = await sdkFolder.getMail(email.messageId);
      const dest: IFolder = await engine.getFolder(destFolderFullName);
      await sm.moveTo(dest);
      return true;
    } catch (e) {
      this.logger.e('SDK moveEmail error: ' + JSON.stringify(e));
      return false;
    }
  }

  async sendEmail(acct: Account, to: EmailAddress[], cc: EmailAddress[], bcc: EmailAddress[],
    subject: string, body: string): Promise<boolean> {
    try {
      const transport: ITransport = (await this.getEngine(acct)).getTransport();
      const from: SdkAddr = { name: acct.displayName, email: acct.email };
      const toSDK: SdkAddr[] = this.toSdkAddrList(to);
      const ccSDK: SdkAddr[] = this.toSdkAddrList(cc);
      const bccSDK: SdkAddr[] = this.toSdkAddrList(bcc);
      await transport.sendMail(from, toSDK, ccSDK, bccSDK, subject, '', body, [], []);
      return true;
    } catch (e) {
      this.logger.e('SDK send error: ' + JSON.stringify(e));
      return false;
    }
  }

  async searchEmails(acct: Account, query: string): Promise<Email[]> {
    try {
      await this.ensureConnected(acct);
      const searchTypes: ('subject' | 'attachment' | 'from' | 'to')[] = ['subject', 'from', 'to'];
      const engS = await this.getEngine(acct);
      const sdkMails: IMail[] = await engS.search(query, searchTypes, 0, 50);
      const result: Email[] = [];
      for (const sm of sdkMails) {
        const folder: IFolder = sm.getFolder();
        const e: Email = {
          id: Utils.generateId(),
          accountId: acct.id,
          folderId: acct.id + '_' + folder.getFullName(),
          messageId: sm.getId(),
          subject: await sm.getSubject(),
          from: await this.toEmailAddress(sm.getFrom()),
          to: await this.toEmailAddressList(sm.getTo()),
          date: (await sm.getDate()).getTime(),
          bodyText: '', bodyHtml: '',
          preview: await sm.getDigest(80),
          isRead: await sm.isSeen(),
          isStarred: await sm.isFlagged(),
          isDeleted: false, isDraft: false, isAnswered: false, isForwarded: false,
          hasAttachments: await this.sdkMailHasAttachments(sm),
          attachments: [],
          isSynced: true,
          size: await sm.getSize(),
          createdAt: Date.now(),
          updatedAt: Date.now(),
        };
        result.push(e);
      }
      return result;
    } catch (e) {
      this.logger.e('SDK search error: ' + JSON.stringify(e));
      return [];
    }
  }

  async clearEngineCache(acctId?: string): Promise<void> {
    if (acctId) {
      this.engineCache[acctId] = null;
    } else {
      this.engineCache = {};
    }
  }

  private async ensureConnected(acct: Account): Promise<void> {
    const eng = await this.getEngine(acct);
    const store: IStore = eng.getStore();
    await store.check();
  }

  private async getEngine(acct: Account): Promise<MailEngine> {
    const key = acct.id;
    const cached = this.engineCache[key];
    if (cached) return cached;
    const engine = new MailEngine();
    engine.setProperties(buildProperties(acct));
    this.engineCache[key] = engine;
    this.logger.i('SDK engine created for ' + acct.email + ' ' + acct.incomingServer + ':' + acct.incomingPort);
    return engine;
  }

  private async setMailAttribute(acct: Account, email: Email, attr: string, value: boolean): Promise<boolean> {
    try {
      await this.ensureConnected(acct);
      const engine = await this.getEngine(acct);
      const sdkFolder: IFolder = await engine.getFolder(this.getSdkFolderName(acct, email.folderId));
      const sm: IMail = await sdkFolder.getMail(email.messageId);
      if (attr === 'seen') { await sm.setSeen(value); return true; }
      if (attr === 'flagged') { await sm.setFlagged(value); return true; }
      if (attr === 'deleted') { await sm.delete(); return true; }
      return false;
    } catch (e) {
      this.logger.e('SDK setMailAttribute error: ' + JSON.stringify(e));
      return false;
    }
  }

  private getSdkFolderName(acct: Account, folderId: string): string {
    const prefix = acct.id + '_';
    if (folderId.startsWith(prefix)) {
      return folderId.substring(prefix.length);
    }
    return folderId;
  }

  private toSdkAddrList(list: EmailAddress[]): SdkAddr[] {
    const result: SdkAddr[] = [];
    for (const a of list) {
      result.push({ name: a.name || a.address, email: a.address });
    }
    return result;
  }

  private async toEmailAddress(p: Promise<SdkAddr>): Promise<EmailAddress> {
    try {
      const a = await p;
      if (!a) return { address: '', name: '' };
      return { address: a.email, name: a.name };
    } catch (e) { return { address: '', name: '' }; }
  }

  private async toEmailAddressList(p: Promise<SdkAddr[]>): Promise<EmailAddress[]> {
    try {
      const list = await p;
      if (!list) return [];
      const result: EmailAddress[] = [];
      for (const a of list) {
        result.push({ address: a.email, name: a.name });
      }
      return result;
    } catch (e) { return []; }
  }

  private toLocalFolderType(sdkType: number): FolderType {
    if (sdkType === SdkFolderType.inbox) return FolderType.INBOX;
    if (sdkType === SdkFolderType.sent) return FolderType.SENT;
    if (sdkType === SdkFolderType.draft) return FolderType.DRAFTS;
    if (sdkType === SdkFolderType.trash) return FolderType.TRASH;
    if (sdkType === SdkFolderType.spam) return FolderType.SPAM;
    if (sdkType === SdkFolderType.archive) return FolderType.ARCHIVE;
    return FolderType.CUSTOM;
  }
}

