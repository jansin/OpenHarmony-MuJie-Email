import { preferences } from '@kit.ArkData';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Constants } from '../common/Constants';
import { util } from '@kit.ArkTS';
import { Account } from '../models/Account';
import { Email, EmailAddress } from '../models/Email';
import { Folder, FolderType } from '../models/Folder';
import { Attachment } from '../models/Attachment';
import { LogUtil } from '../common/LogUtil';
import { FilterRuleRecord, ContactRecord } from '../models/RecordTypes';

export class StorageService {
  private static instance: StorageService;
  private context: common.Context;
  private preferencesStore: preferences.Preferences | null = null;
  private rdbStore: relationalStore.RdbStore | null = null;
  private logger: LogUtil = new LogUtil('StorageService');

  private constructor(context: common.Context) {
    this.context = context;
  }

  static getInstance(context: common.Context): StorageService {
    if (!StorageService.instance) {
      StorageService.instance = new StorageService(context);
    }
    return StorageService.instance;
  }

  async initialize(): Promise<void> {
    await this.initPreferences();
    await this.initRdbStore();
  }

  private async initPreferences(): Promise<void> {
    try {
      this.preferencesStore = await preferences.getPreferences(this.context, 'MailPreferences');
    } catch (error) {
      this.logger.e('Failed to initialize preferences: ' + JSON.stringify(error));
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  private async initRdbStore(): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: Constants.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };

    try {
      this.rdbStore = await relationalStore.getRdbStore(this.context, config);
      await this.createTables();
    } catch (error) {
      this.logger.e('Failed to initialize RdbStore: ' + JSON.stringify(error));
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  private async createTables(): Promise<void> {
    if (!this.rdbStore) return;

    await this.rdbStore.executeSql(`
      CREATE TABLE IF NOT EXISTS ${Constants.TABLE_ACCOUNTS} (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        displayName TEXT,
        protocol TEXT NOT NULL,
        smtpEnabled INTEGER DEFAULT 1,
        incomingServer TEXT,
        incomingPort INTEGER,
        incomingSecurity TEXT,
        incomingUsername TEXT,
        outgoingServer TEXT,
        outgoingPort INTEGER,
        outgoingSecurity TEXT,
        outgoingUsername TEXT,
        password TEXT NOT NULL,
        isConnected INTEGER DEFAULT 0,
        isDefault INTEGER DEFAULT 0,
        lastSyncTime INTEGER,
        createdAt INTEGER,
        updatedAt INTEGER
      )
    `);

    await this.rdbStore.executeSql(`
      CREATE TABLE IF NOT EXISTS ${Constants.TABLE_FOLDERS} (
        id TEXT PRIMARY KEY,
        accountId TEXT NOT NULL,
        name TEXT NOT NULL,
        fullName TEXT NOT NULL,
        type TEXT NOT NULL,
        totalCount INTEGER DEFAULT 0,
        unreadCount INTEGER DEFAULT 0,
        lastSyncTime INTEGER,
        isSynced INTEGER DEFAULT 0,
        selectable INTEGER DEFAULT 1,
        createdAt INTEGER,
        updatedAt INTEGER
      )
    `);

    await this.rdbStore.executeSql(`
      CREATE TABLE IF NOT EXISTS ${Constants.TABLE_EMAILS} (
        id TEXT PRIMARY KEY,
        accountId TEXT NOT NULL,
        folderId TEXT NOT NULL,
        messageId TEXT,
        subject TEXT,
        fromName TEXT,
        fromAddress TEXT,
        toAddresses TEXT,
        ccAddresses TEXT,
        bccAddresses TEXT,
        replyToName TEXT,
        replyToAddress TEXT,
        date INTEGER,
        bodyText TEXT,
        bodyHtml TEXT,
        preview TEXT,
        isRead INTEGER DEFAULT 0,
        isStarred INTEGER DEFAULT 0,
        isDeleted INTEGER DEFAULT 0,
        isDraft INTEGER DEFAULT 0,
        isAnswered INTEGER DEFAULT 0,
        isForwarded INTEGER DEFAULT 0,
        hasAttachments INTEGER DEFAULT 0,
        isSynced INTEGER DEFAULT 0,
        syncError TEXT,
        size INTEGER DEFAULT 0,
        uid INTEGER,
        createdAt INTEGER,
        updatedAt INTEGER
      )
    `);

    await this.rdbStore.executeSql(`
      CREATE TABLE IF NOT EXISTS ${Constants.TABLE_ATTACHMENTS} (
        id TEXT PRIMARY KEY,
        emailId TEXT NOT NULL,
        filename TEXT NOT NULL,
        contentType TEXT,
        size INTEGER,
        contentId TEXT,
        disposition TEXT,
        localPath TEXT,
        isDownloaded INTEGER DEFAULT 0,
        downloadProgress INTEGER DEFAULT 0,
        createdAt INTEGER
      )
    `);

    await this.rdbStore.executeSql(`
      CREATE TABLE IF NOT EXISTS ${Constants.TABLE_CONTACTS} (
        id TEXT PRIMARY KEY,
        accountId TEXT NOT NULL,
        name TEXT,
        email TEXT NOT NULL,
        lastContactTime INTEGER,
        contactCount INTEGER DEFAULT 1,
        createdAt INTEGER
      )
    `);

    await this.rdbStore.executeSql(`
      CREATE TABLE IF NOT EXISTS ${Constants.TABLE_FILTER_RULES} (
        id TEXT PRIMARY KEY,
        accountId TEXT NOT NULL,
        name TEXT NOT NULL,
        enabled INTEGER DEFAULT 1,
        conditions TEXT,
        action TEXT,
        createdAt INTEGER,
        updatedAt INTEGER
      )
    `);

    await this.rdbStore.executeSql(`CREATE INDEX IF NOT EXISTS idx_contacts_account ON ${Constants.TABLE_CONTACTS}(accountId)`);
    await this.rdbStore.executeSql(`CREATE INDEX IF NOT EXISTS idx_contacts_email ON ${Constants.TABLE_CONTACTS}(email)`);
    await this.rdbStore.executeSql(`CREATE INDEX IF NOT EXISTS idx_emails_account_folder ON ${Constants.TABLE_EMAILS}(accountId, folderId)`);
    await this.rdbStore.executeSql(`CREATE INDEX IF NOT EXISTS idx_emails_date ON ${Constants.TABLE_EMAILS}(date DESC)`);
    await this.rdbStore.executeSql(`CREATE INDEX IF NOT EXISTS idx_folders_account ON ${Constants.TABLE_FOLDERS}(accountId)`);
  }

  private encodePassword(pwd: string): string {
    if (!pwd) return '';
    try {
      const encoder = new util.Base64();
      const encoded = encoder.encodeToStringSync(new util.TextEncoder().encode(pwd));
      const xored = this.xorObfuscate(encoded);
      return encoder.encodeToStringSync(new util.TextEncoder().encode(xored));
    } catch (e) {
      this.logger.w('Password encoding failed, returning original', e);
      return pwd;
    }
  }

  private decodePassword(encoded: string): string {
    if (!encoded) return '';
    try {
      const decoder = new util.Base64();
      const xored = new util.TextDecoder('utf-8', { ignoreBOM: true }).decode(decoder.decodeSync(encoded));
      const unxored = this.xorObfuscate(xored);
      return new util.TextDecoder('utf-8', { ignoreBOM: true }).decode(decoder.decodeSync(unxored));
    } catch (e) {
      this.logger.w('Password decoding failed, returning encoded', e);
      return encoded;
    }
  }

  private xorObfuscate(data: string): string {
    const key = 'MuJieEmail_2024_K';
    let result = '';
    for (let i = 0; i < data.length; i++) {
      result += String.fromCharCode(data.charCodeAt(i) ^ key.charCodeAt(i % key.length));
    }
    return result;
  }

  async saveAccount(account: Account): Promise<void> {
    if (!this.preferencesStore) return;

    try {
      const accounts = await this.getAccounts();
      const index = accounts.findIndex(a => a.id === account.id);
      if (index >= 0) {
        // Preserve encoded password from existing account if password field is empty update
        if (!account.password && accounts[index].password) {
          account.password = accounts[index].password;
        } else if (account.password && !account.password.startsWith('==')) {
          account.password = '==' + this.encodePassword(account.password);
        }
        accounts[index] = account;
      } else {
        if (account.password && !account.password.startsWith('==')) {
          account.password = '==' + this.encodePassword(account.password);
        }
        accounts.push(account);
      }
      const json = JSON.stringify(accounts);
      await this.preferencesStore.put(Constants.ACCOUNTS_KEY, json);
      await this.preferencesStore.flush();
    } catch (error) {
      this.logger.e('Failed to save account: ' + JSON.stringify(error));
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  async getAccounts(): Promise<Account[]> {
    if (!this.preferencesStore) return [];
    try {
      const accountsJson = await this.preferencesStore.get(Constants.ACCOUNTS_KEY, '[]');
      const accounts: Account[] = JSON.parse(accountsJson as string) as Account[];
      for (const a of accounts) {
        if (a.password && a.password.startsWith('==')) {
          a.password = this.decodePassword(a.password.substring(2));
        }
      }
      return accounts;
    } catch (error) {
      this.logger.e('Failed to get accounts: ' + JSON.stringify(error));
      return [];
    }
  }

  async deleteAccount(accountId: string): Promise<void> {
    if (!this.preferencesStore) return;

    try {
      const accounts = await this.getAccounts();
      const filtered = accounts.filter(a => a.id !== accountId);
      await this.preferencesStore.put(Constants.ACCOUNTS_KEY, JSON.stringify(filtered));
      await this.preferencesStore.flush();

      if (this.rdbStore) {
        const emailPred = new relationalStore.RdbPredicates(Constants.TABLE_EMAILS);
        emailPred.equalTo('accountId', accountId);
        await this.rdbStore.delete(emailPred);

        const folderPred = new relationalStore.RdbPredicates(Constants.TABLE_FOLDERS);
        folderPred.equalTo('accountId', accountId);
        await this.rdbStore.delete(folderPred);
      }
    } catch (error) {
      this.logger.e('Failed to delete account: ' + JSON.stringify(error));
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  async getCurrentAccountId(): Promise<string | null> {
    if (!this.preferencesStore) return null;
    try {
      const accountId = await this.preferencesStore.get(Constants.CURRENT_ACCOUNT_KEY, '');
      return (accountId as string) || null;
    } catch (error) {
      this.logger.e('Failed to get current account ID: ' + JSON.stringify(error));
      return null;
    }
  }

  async setCurrentAccountId(accountId: string): Promise<void> {
    if (!this.preferencesStore) return;
    try {
      await this.preferencesStore.put(Constants.CURRENT_ACCOUNT_KEY, accountId);
      await this.preferencesStore.flush();
    } catch (error) {
      this.logger.e('Failed to set current account ID: ' + JSON.stringify(error));
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  async saveFolder(folder: Folder): Promise<void> {
    if (!this.rdbStore) return;

    try {
      const valueBucket: relationalStore.ValuesBucket = {
        'id': folder.id,
        'accountId': folder.accountId,
        'name': folder.name,
        'fullName': folder.fullName,
        'type': folder.type,
        'totalCount': folder.totalCount,
        'unreadCount': folder.unreadCount,
        'lastSyncTime': folder.lastSyncTime ? folder.lastSyncTime : null,
        'isSynced': folder.isSynced ? 1 : 0,
        'selectable': folder.selectable ? 1 : 0,
        'createdAt': folder.createdAt,
        'updatedAt': folder.updatedAt
      };

      try {
        await this.rdbStore.insert(Constants.TABLE_FOLDERS, valueBucket);
      } catch (insertError) {
        const predicates = new relationalStore.RdbPredicates(Constants.TABLE_FOLDERS);
        predicates.equalTo('id', folder.id);
        await this.rdbStore.update(valueBucket, predicates);
      }
    } catch (error) {
      this.logger.e('Failed to save folder: ' + JSON.stringify(error));
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  async getFoldersByAccountId(accountId: string): Promise<Folder[]> {
    if (!this.rdbStore) return [];

    try {
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_FOLDERS);
      predicates.equalTo('accountId', accountId);

      const resultSet = await this.rdbStore.query(predicates);
      const folders: Folder[] = [];

      while (resultSet.goToNextRow()) {
        folders.push({
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          accountId: resultSet.getString(resultSet.getColumnIndex('accountId')),
          name: resultSet.getString(resultSet.getColumnIndex('name')),
          fullName: resultSet.getString(resultSet.getColumnIndex('fullName')),
          type: resultSet.getLong(resultSet.getColumnIndex('type')) as FolderType,
          totalCount: resultSet.getLong(resultSet.getColumnIndex('totalCount')),
          unreadCount: resultSet.getLong(resultSet.getColumnIndex('unreadCount')),
          lastSyncTime: resultSet.getLong(resultSet.getColumnIndex('lastSyncTime')),
          isSynced: resultSet.getLong(resultSet.getColumnIndex('isSynced')) === 1,
          selectable: resultSet.getLong(resultSet.getColumnIndex('selectable')) === 1,
          createdAt: resultSet.getLong(resultSet.getColumnIndex('createdAt')),
          updatedAt: resultSet.getLong(resultSet.getColumnIndex('updatedAt'))
        });
      }

      resultSet.close();
      return folders;
    } catch (error) {
      this.logger.e('Failed to get folders: ' + JSON.stringify(error));
      return [];
    }
  }

  async getEmailByMessageId(messageId: string, accountId: string): Promise<Email | null> {
    if (!this.rdbStore) return null;
    try {
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_EMAILS);
      predicates.equalTo('messageId', messageId);
      predicates.equalTo('accountId', accountId);
      const resultSet = await this.rdbStore.query(predicates);
      let email: Email | null = null;
      if (resultSet.goToNextRow()) {
        email = this.parseEmailFromResultSet(resultSet);
      }
      resultSet.close();
      return email;
    } catch (e) {
      this.logger.e('getEmailByMessageId error: ' + JSON.stringify(e));
      return null;
    }
  }

  async getEmailById(emailId: string): Promise<Email | null> {
    if (!this.rdbStore) return null;

    try {
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_EMAILS);
      predicates.equalTo('id', emailId);

      const resultSet = await this.rdbStore.query(predicates);
      let email: Email | null = null;

      if (resultSet.goToNextRow()) {
        email = this.parseEmailFromResultSet(resultSet);
      }

      resultSet.close();
      return email;
    } catch (error) {
      this.logger.e('Failed to get email by ID: ' + JSON.stringify(error));
      return null;
    }
  }

  /** 兼容历史 JSON 使用 email 字段、或 SDK 形状 */
  private normalizeAddressObject(raw: EmailAddress): EmailAddress {
    const a = raw.address !== undefined && raw.address !== null ? raw.address.trim() : '';
    const e = raw.email !== undefined && raw.email !== null ? raw.email.trim() : '';
    const addr = a.length > 0 ? a : e;
    const name = raw.name !== undefined && raw.name !== null ? raw.name.trim() : '';
    return { address: addr, name: name };
  }

  private parseAddressJsonColumn(json: string | null | undefined): EmailAddress[] {
    if (!json || json.length === 0) {
      return [];
    }
    try {
      const arr = JSON.parse(json) as EmailAddress[];
      if (!Array.isArray(arr)) {
        return [];
      }
      return arr.map((x: EmailAddress) => this.normalizeAddressObject(x));
    } catch (e) {
      return [];
    }
  }

  private parseEmailFromResultSet(resultSet: relationalStore.ResultSet): Email {
    const fromName = resultSet.getString(resultSet.getColumnIndex('fromName'));
    const fromAddress = resultSet.getString(resultSet.getColumnIndex('fromAddress'));
    const toStr = resultSet.getString(resultSet.getColumnIndex('toAddresses'));
    const ccStr = resultSet.getString(resultSet.getColumnIndex('ccAddresses'));
    const bccStr = resultSet.getString(resultSet.getColumnIndex('bccAddresses'));
    const replyToName = resultSet.getString(resultSet.getColumnIndex('replyToName'));
    const replyToAddress = resultSet.getString(resultSet.getColumnIndex('replyToAddress'));

    const fromAddr: EmailAddress = this.normalizeAddressObject(
      { name: (fromName ?? '').toString(), address: (fromAddress ?? '').toString() } as EmailAddress);
    const toList: EmailAddress[] = this.parseAddressJsonColumn(toStr);
    let ccList: EmailAddress[] | undefined = undefined;
    if (ccStr) {
      const parsed = this.parseAddressJsonColumn(ccStr);
      ccList = parsed.length > 0 ? parsed : undefined;
    }
    let bccList: EmailAddress[] | undefined = undefined;
    if (bccStr) {
      const parsedB = this.parseAddressJsonColumn(bccStr);
      bccList = parsedB.length > 0 ? parsedB : undefined;
    }
    let replyToList: EmailAddress[] | undefined = undefined;
    if (replyToName) {
      const addr: EmailAddress = { name: replyToName, address: replyToAddress };
      replyToList = [addr];
    }

    const email: Email = {
      id: resultSet.getString(resultSet.getColumnIndex('id')),
      accountId: resultSet.getString(resultSet.getColumnIndex('accountId')),
      folderId: resultSet.getString(resultSet.getColumnIndex('folderId')),
      messageId: resultSet.getString(resultSet.getColumnIndex('messageId')),
      subject: resultSet.getString(resultSet.getColumnIndex('subject')),
      from: fromAddr,
      to: toList,
      cc: ccList,
      bcc: bccList,
      replyTo: replyToList,
      date: resultSet.getLong(resultSet.getColumnIndex('date')),
      bodyText: resultSet.getString(resultSet.getColumnIndex('bodyText')),
      bodyHtml: resultSet.getString(resultSet.getColumnIndex('bodyHtml')),
      preview: resultSet.getString(resultSet.getColumnIndex('preview')),
      isRead: resultSet.getLong(resultSet.getColumnIndex('isRead')) === 1,
      isStarred: resultSet.getLong(resultSet.getColumnIndex('isStarred')) === 1,
      isDeleted: resultSet.getLong(resultSet.getColumnIndex('isDeleted')) === 1,
      isDraft: resultSet.getLong(resultSet.getColumnIndex('isDraft')) === 1,
      isAnswered: resultSet.getLong(resultSet.getColumnIndex('isAnswered')) === 1,
      isForwarded: resultSet.getLong(resultSet.getColumnIndex('isForwarded')) === 1,
      hasAttachments: resultSet.getLong(resultSet.getColumnIndex('hasAttachments')) === 1,
      isSynced: resultSet.getLong(resultSet.getColumnIndex('isSynced')) === 1,
      syncError: resultSet.getString(resultSet.getColumnIndex('syncError')),
      size: resultSet.getLong(resultSet.getColumnIndex('size')),
      uid: resultSet.getLong(resultSet.getColumnIndex('uid')),
      attachments: [],
      createdAt: resultSet.getLong(resultSet.getColumnIndex('createdAt')),
      updatedAt: resultSet.getLong(resultSet.getColumnIndex('updatedAt'))
    };
    return email;
  }

  async getEmailsByFolderId(folderId: string, offset: number, limit: number): Promise<Email[]> {
    if (!this.rdbStore) return [];

    try {
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_EMAILS);
      predicates.equalTo('folderId', folderId);
      predicates.equalTo('isDeleted', 0);
      predicates.orderByDesc('date');
      predicates.limitAs(limit);
      predicates.offsetAs(offset);

      const resultSet = await this.rdbStore.query(predicates);
      const emails: Email[] = [];

      while (resultSet.goToNextRow()) {
        emails.push(this.parseEmailFromResultSet(resultSet));
      }

      resultSet.close();
      return emails;
    } catch (error) {
      this.logger.e('Failed to get emails: ' + JSON.stringify(error));
      return [];
    }
  }

  async saveEmail(email: Email): Promise<void> {
    if (!this.rdbStore) return;

    try {
      const fromNameVal: string | null = email.from.name !== undefined && email.from.name !== null ? email.from.name : null;
      const replyToNameVal: string | null = email.replyTo && email.replyTo.length > 0 && email.replyTo[0].name !== undefined ? email.replyTo[0].name : null;
      const replyToAddrVal: string | null = email.replyTo && email.replyTo.length > 0 && email.replyTo[0].address !== undefined ? email.replyTo[0].address : null;
      const bodyTextVal: string | null = email.bodyText !== undefined && email.bodyText !== null ? email.bodyText : null;
      const bodyHtmlVal: string | null = email.bodyHtml !== undefined && email.bodyHtml !== null ? email.bodyHtml : null;
      const syncErrorVal: string | null = email.syncError !== undefined && email.syncError !== null ? email.syncError : null;
      const uidVal: number | null = email.uid !== undefined && email.uid !== null ? email.uid : null;

      const valueBucket: relationalStore.ValuesBucket = {
        'id': email.id,
        'accountId': email.accountId,
        'folderId': email.folderId,
        'messageId': email.messageId,
        'subject': email.subject,
        'fromName': fromNameVal,
        'fromAddress': email.from.address,
        'toAddresses': JSON.stringify(email.to),
        'ccAddresses': email.cc !== undefined ? JSON.stringify(email.cc) : null,
        'bccAddresses': email.bcc !== undefined ? JSON.stringify(email.bcc) : null,
        'replyToName': replyToNameVal,
        'replyToAddress': replyToAddrVal,
        'date': email.date,
        'bodyText': bodyTextVal,
        'bodyHtml': bodyHtmlVal,
        'preview': email.preview,
        'isRead': email.isRead ? 1 : 0,
        'isStarred': email.isStarred ? 1 : 0,
        'isDeleted': email.isDeleted ? 1 : 0,
        'isDraft': email.isDraft ? 1 : 0,
        'isAnswered': email.isAnswered ? 1 : 0,
        'isForwarded': email.isForwarded ? 1 : 0,
        'hasAttachments': email.hasAttachments ? 1 : 0,
        'isSynced': email.isSynced ? 1 : 0,
        'syncError': syncErrorVal,
        'size': email.size,
        'uid': uidVal,
        'createdAt': email.createdAt,
        'updatedAt': email.updatedAt
      };

      let existingByMessageId: string | null = null;
      if (email.messageId && email.messageId.length > 0) {
        const msgIdPredicates = new relationalStore.RdbPredicates(Constants.TABLE_EMAILS);
        msgIdPredicates.equalTo('messageId', email.messageId);
        msgIdPredicates.equalTo('accountId', email.accountId);
        const msgIdResult = await this.rdbStore.query(msgIdPredicates, ['id']);
        if (msgIdResult.goToFirstRow()) {
          existingByMessageId = msgIdResult.getString(msgIdResult.getColumnIndex('id'));
        }
        msgIdResult.close();
      }

      if (existingByMessageId && existingByMessageId !== email.id) {
        const updatePredicates = new relationalStore.RdbPredicates(Constants.TABLE_EMAILS);
        updatePredicates.equalTo('id', existingByMessageId);
        await this.rdbStore.update(valueBucket, updatePredicates);
        return;
      }

      try {
        await this.rdbStore.insert(Constants.TABLE_EMAILS, valueBucket);
      } catch (insertError) {
        const predicates = new relationalStore.RdbPredicates(Constants.TABLE_EMAILS);
        predicates.equalTo('id', email.id);
        await this.rdbStore.update(valueBucket, predicates);
      }
    } catch (error) {
      this.logger.e('Failed to save email: ' + JSON.stringify(error));
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  async updateEmailFlags(emailId: string, flags: Record<string, number>): Promise<void> {
    if (!this.rdbStore) return;

    try {
      const valueBucket: relationalStore.ValuesBucket = {};
      const keys = Object.keys(flags);
      for (const key of keys) {
        valueBucket[key] = flags[key];
      }

      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_EMAILS);
      predicates.equalTo('id', emailId);
      await this.rdbStore.update(valueBucket, predicates);
    } catch (error) {
      this.logger.e('Failed to update email flags: ' + JSON.stringify(error));
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  async deleteEmail(emailId: string): Promise<void> {
    if (!this.rdbStore) return;

    try {
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_EMAILS);
      predicates.equalTo('id', emailId);
      await this.rdbStore.delete(predicates);
    } catch (error) {
      this.logger.e('Failed to delete email: ' + JSON.stringify(error));
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  async deleteFolder(folderId: string): Promise<void> {
    if (!this.rdbStore) return;
    try {
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_FOLDERS);
      predicates.equalTo('id', folderId);
      await this.rdbStore.delete(predicates);
    } catch (error) {
      this.logger.e('Failed to delete folder: ' + JSON.stringify(error));
    }
  }

  async renameFolder(folderId: string, newName: string): Promise<void> {
    if (!this.rdbStore) return;
    try {
      const valueBucket: relationalStore.ValuesBucket = {
        'name': newName,
        'updatedAt': Date.now()
      };
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_FOLDERS);
      predicates.equalTo('id', folderId);
      await this.rdbStore.update(valueBucket, predicates);
    } catch (error) {
      this.logger.e('Failed to rename folder: ' + JSON.stringify(error));
    }
  }

  async updateFolderStats(folderId: string, totalCount: number, unreadCount: number): Promise<void> {
    if (!this.rdbStore) return;
    try {
      const valueBucket: relationalStore.ValuesBucket = {
        'totalCount': totalCount,
        'unreadCount': unreadCount,
        'updatedAt': Date.now()
      };
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_FOLDERS);
      predicates.equalTo('id', folderId);
      await this.rdbStore.update(valueBucket, predicates);
    } catch (error) {
      this.logger.e('Failed to update folder stats: ' + JSON.stringify(error));
    }
  }

  async saveFilterRule(rule: FilterRuleRecord): Promise<void> {
    if (!this.rdbStore) return;
    try {
      const bucket: relationalStore.ValuesBucket = {
        'id': rule.id,
        'accountId': rule.accountId,
        'name': rule.name,
        'enabled': rule.enabled ? 1 : 0,
        'conditions': rule.conditions,
        'action': rule.action,
        'createdAt': rule.createdAt,
        'updatedAt': rule.updatedAt
      };
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_FILTER_RULES);
      predicates.equalTo('id', rule.id);
      const existing = await this.rdbStore.query(predicates, ['id']);
      if (existing.rowCount > 0) {
        const up = new relationalStore.RdbPredicates(Constants.TABLE_FILTER_RULES);
        up.equalTo('id', rule.id);
        await this.rdbStore.update(bucket, up);
      } else {
        await this.rdbStore.insert(Constants.TABLE_FILTER_RULES, bucket);
      }
      existing.close();
    } catch (error) {
      this.logger.e('Failed to save filter rule: ' + JSON.stringify(error));
    }
  }

  async getFilterRules(accountId: string): Promise<FilterRuleRecord[]> {
    if (!this.rdbStore) return [];
    try {
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_FILTER_RULES);
      predicates.equalTo('accountId', accountId);
      predicates.orderByDesc('createdAt');
      const result = await this.rdbStore.query(predicates);
      const rules: FilterRuleRecord[] = [];
      while (result.goToNextRow()) {
        const item: FilterRuleRecord = {
          id: result.getString(result.getColumnIndex('id')),
          accountId: result.getString(result.getColumnIndex('accountId')),
          name: result.getString(result.getColumnIndex('name')),
          enabled: result.getLong(result.getColumnIndex('enabled')) === 1,
          conditions: result.getString(result.getColumnIndex('conditions')),
          action: result.getString(result.getColumnIndex('action')),
          createdAt: result.getLong(result.getColumnIndex('createdAt')),
          updatedAt: result.getLong(result.getColumnIndex('updatedAt'))
        };
        rules.push(item);
      }
      result.close();
      return rules;
    } catch (error) {
      this.logger.e('Failed to get filter rules: ' + JSON.stringify(error));
      return [];
    }
  }

  async deleteFilterRule(ruleId: string): Promise<void> {
    if (!this.rdbStore) return;
    try {
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_FILTER_RULES);
      predicates.equalTo('id', ruleId);
      await this.rdbStore.delete(predicates);
    } catch (error) {
      this.logger.e('Failed to delete filter rule: ' + JSON.stringify(error));
    }
  }

  async saveContact(contact: ContactRecord): Promise<void> {
    if (!this.rdbStore) return;
    try {
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_CONTACTS);
      predicates.equalTo('accountId', contact.accountId);
      predicates.equalTo('email', contact.email);
      const existing = await this.rdbStore.query(predicates, ['id', 'contactCount', 'lastContactTime']);
      if (existing.rowCount > 0) {
        existing.goToFirstRow();
        const id = existing.getString(existing.getColumnIndex('id'));
        const count = existing.getLong(existing.getColumnIndex('contactCount'));
        const valueBucket: relationalStore.ValuesBucket = {
          'name': contact.name,
          'lastContactTime': contact.lastContactTime,
          'contactCount': count + 1
        };
        const up = new relationalStore.RdbPredicates(Constants.TABLE_CONTACTS);
        up.equalTo('id', id);
        await this.rdbStore.update(valueBucket, up);
      } else {
        const bucket: relationalStore.ValuesBucket = {
          'id': contact.id,
          'accountId': contact.accountId,
          'name': contact.name,
          'email': contact.email,
          'lastContactTime': contact.lastContactTime,
          'contactCount': contact.contactCount,
          'createdAt': contact.createdAt
        };
        await this.rdbStore.insert(Constants.TABLE_CONTACTS, bucket);
      }
      existing.close();
    } catch (error) {
      this.logger.e('Failed to save contact: ' + JSON.stringify(error));
    }
  }

  async getContacts(accountId: string, keyword?: string): Promise<ContactRecord[]> {
    if (!this.rdbStore) return [];
    try {
      const predicates = new relationalStore.RdbPredicates(Constants.TABLE_CONTACTS);
      predicates.equalTo('accountId', accountId);
      if (keyword && keyword.length > 0) {
        predicates.like('email', `%${keyword}%`);
        predicates.or();
        predicates.like('name', `%${keyword}%`);
      }
      predicates.orderByDesc('contactCount');
      predicates.limitAs(50);
      const result = await this.rdbStore.query(predicates);
      const contacts: ContactRecord[] = [];
      while (result.goToNextRow()) {
        const item: ContactRecord = {
          id: result.getString(result.getColumnIndex('id')),
          accountId: result.getString(result.getColumnIndex('accountId')),
          name: result.getString(result.getColumnIndex('name')),
          email: result.getString(result.getColumnIndex('email')),
          lastContactTime: result.getLong(result.getColumnIndex('lastContactTime')),
          contactCount: result.getLong(result.getColumnIndex('contactCount')),
          createdAt: 0
        };
        contacts.push(item);
      }
      result.close();
      return contacts;
    } catch (error) {
      this.logger.e('Failed to get contacts: ' + JSON.stringify(error));
      return [];
    }
  }

  async close(): Promise<void> {
    if (this.rdbStore) {
      await this.rdbStore.close();
      this.rdbStore = null;
    }
  }

  async cleanDuplicateEmails(): Promise<number> {
    if (!this.rdbStore) return 0;
    let cleaned = 0;
    try {
      const accounts = await this.getAccounts();
      for (const account of accounts) {
        const folders = await this.getFoldersByAccountId(account.id);
        for (const folder of folders) {
          const emails = await this.getEmailsByFolderId(folder.id, 0, 1000);
          const seenMessageIds = new Set<string>();
          const toDelete: string[] = [];
          for (const email of emails) {
            if (email.messageId && email.messageId.length > 0) {
              if (seenMessageIds.has(email.messageId)) {
                toDelete.push(email.id);
              } else {
                seenMessageIds.add(email.messageId);
              }
            }
          }
          for (const id of toDelete) {
            await this.deleteEmail(id);
            cleaned++;
          }
        }
      }
      this.logger.i('Cleaned ' + cleaned + ' duplicate emails');
    } catch (error) {
      this.logger.e('Failed to clean duplicate emails: ' + JSON.stringify(error));
    }
    return cleaned;
  }
}


