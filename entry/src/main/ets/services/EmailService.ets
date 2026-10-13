import { Account } from '../models/Account';
import { Email, EmailAddress } from '../models/Email';
import { Folder, FolderType } from '../models/Folder';
import { Attachment } from '../models/Attachment';
import { StorageService } from './StorageService';
import { MailSdkService } from './MailSdkService';
import { FilterService } from './FilterService';
import { FilterRule } from '../models/FilterRule';

export class EmailService {
  private static instance: EmailService;
  private storageService: StorageService;
  private sdk: MailSdkService;

  private constructor(storageService: StorageService) {
    this.storageService = storageService;
    this.sdk = MailSdkService.getInstance(storageService);
  }

  static getInstance(storageService: StorageService): EmailService {
    if (!EmailService.instance) {
      EmailService.instance = new EmailService(storageService);
    }
    return EmailService.instance;
  }

  async connect(account: Account): Promise<boolean> {
    return await this.sdk.testConnect(account);
  }

  async disconnect(): Promise<void> {
  }

  async fetchFolders(account: Account): Promise<Folder[]> {
    const local = await this.storageService.getFoldersByAccountId(account.id);
    const sdkFolders = await this.sdk.fetchFolders(account);
    if (sdkFolders.length > 0) {
      const typeMap = new Map<FolderType, Folder>();
      for (const lf of local) {
        typeMap.set(lf.type, lf);
      }
      const merged: Folder[] = local.slice();
      for (const sf of sdkFolders) {
        if (typeMap.has(sf.type)) {
          const existing = typeMap.get(sf.type)!;
          existing.unreadCount = sf.unreadCount;
        } else {
          merged.push(sf);
        }
      }
      return merged;
    }
    return local;
  }

  async fetchEmails(account: Account, folder: Folder, limit: number): Promise<Email[]> {
    const cached = await this.storageService.getEmailsByFolderId(folder.id, 0, limit * 2);
    try {
      const mails = await this.sdk.fetchEmails(account, folder, limit);
      if (mails.length > 0) {
        const seenMessageIds = new Set<string>();
        const seenIds = new Set<string>();
        for (const old of cached) {
          if (old.messageId) seenMessageIds.add(old.messageId);
          seenIds.add(old.id);
        }
        const dedupedMails: Email[] = [];
        for (const mail of mails) {
          const msgId = mail.messageId || mail.id;
          if (seenMessageIds.has(msgId)) {
            continue;
          }
          seenMessageIds.add(msgId);
          seenIds.add(mail.id);
          dedupedMails.push(mail);
        }
        const filterService = FilterService.getInstance(this.storageService);
        const rules = await filterService.getRules(account.id);
        const folders = await this.storageService.getFoldersByAccountId(account.id);
        for (const email of dedupedMails) {
          if (rules.length > 0) {
            const resultAction: string | null = await filterService.processIncomingEmail(email, rules, folders);
            if (resultAction === null) continue;
          }
          await this.storageService.saveEmail(email);
        }
        const allEmails = await this.storageService.getEmailsByFolderId(folder.id, 0, limit);
        return allEmails.slice(0, limit);
      }
    } catch (e) {
      const detail = e instanceof Error ? e.message : String(e);
      throw new Error(detail);
    }
    return cached;
  }

  async fetchEmailContent(account: Account, email: Email): Promise<Email | null> {
    try {
      const updated = await this.sdk.fetchEmailBody(account, email);
      const hasText = ((updated.bodyText ?? '').trim().length > 0);
      const hasHtml = ((updated.bodyHtml ?? '').trim().length > 0);
      if (!hasText && !hasHtml && (email.preview ?? '').trim().length > 0) {
        updated.bodyText = (email.preview ?? '').trim();
        updated.syncError = undefined;
      }
      await this.storageService.saveEmail(updated);
      return updated;
    } catch (e) {
      // fetch content error logged in SDK layer
      email.syncError = e instanceof Error ? e.message : String(e);
      return email;
    }
  }

  async sendEmail(
    account: Account, to: EmailAddress[], cc: EmailAddress[], bcc: EmailAddress[],
    subject: string, body: string, attachments: Attachment[]
  ): Promise<boolean> {
    return await this.sdk.sendEmail(account, to, cc, bcc, subject, body);
  }

  async markAsRead(account: Account, email: Email): Promise<boolean> {
    return await this.sdk.markAsRead(account, email);
  }

  async starEmail(account: Account, email: Email, isStarred: boolean): Promise<boolean> {
    return await this.sdk.starEmail(account, email, isStarred);
  }

  async deleteEmail(account: Account, email: Email): Promise<boolean> {
    return await this.sdk.deleteEmail(account, email);
  }

  async archiveEmail(account: Account, email: Email, archiveFolderName: string): Promise<boolean> {
    return await this.sdk.moveEmail(account, email, archiveFolderName);
  }

  async downloadAttachment(attachment: Attachment): Promise<string | null> {
    if (attachment.localPath) return attachment.localPath;
    if (attachment.isDownloaded) return attachment.localPath || null;
    return null;
  }

  async syncEmails(account: Account, folder: Folder): Promise<number> {
    try {
      const mails = await this.sdk.fetchEmails(account, folder, 50);
      return mails.length;
    } catch (e) {
      return 0;
    }
  }

  async searchEmails(account: Account, query: string, folderId?: string): Promise<Email[]> {
    try {
      const results = await this.sdk.searchEmails(account, query);
      if (folderId) {
        return results.filter(e => e.folderId === folderId);
      }
      return results;
    } catch (e) {
      return [];
    }
  }
}

