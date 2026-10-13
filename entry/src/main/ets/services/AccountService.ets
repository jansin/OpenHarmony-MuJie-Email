import { Account, AccountProtocol, SecurityType } from '../models/Account';
import { StorageService } from './StorageService';
import { MailSdkService } from './MailSdkService';
import { Constants, ProviderConfig } from '../common/Constants';
import { Utils } from '../common/Utils';
import { LogUtil } from '../common/LogUtil';

export class AccountService {
  private static instance: AccountService;
  private storageService: StorageService;
  private logger: LogUtil = new LogUtil('AccountService');

  private constructor(storageService: StorageService) {
    this.storageService = storageService;
  }

  static getInstance(storageService: StorageService): AccountService {
    if (!AccountService.instance) {
      AccountService.instance = new AccountService(storageService);
    }
    return AccountService.instance;
  }

  async createAccount(email: string, password: string, protocol: AccountProtocol = AccountProtocol.IMAP,
    useClientAuthCode: boolean = true): Promise<Account> {
    const em = email.trim();
    const pw = password.trim();
    if (!Utils.isValidEmail(em)) {
      throw new Error('Invalid email format');
    }

    const provider = Utils.detectProvider(em);
    const providerConfig = Constants.getProvider(provider);

    const account: Account = {
      id: Utils.generateId(),
      email: em,
      displayName: em.split('@')[0],
      protocol: protocol,
      smtpEnabled: true,
      incomingServer: providerConfig?.imap.server || '',
      incomingPort: providerConfig?.imap.port || 993,
      incomingSecurity: (providerConfig?.imap.security as SecurityType) || SecurityType.SSL,
      incomingUsername: em,
      outgoingServer: providerConfig?.smtp.server || '',
      outgoingPort: providerConfig?.smtp.port || 587,
      outgoingSecurity: (providerConfig?.smtp.security as SecurityType) || SecurityType.TLS,
      outgoingUsername: em,
      password: pw,
      useClientAuthCode: useClientAuthCode,
      isConnected: false,
      isDefault: false,
      createdAt: Date.now(),
      updatedAt: Date.now()
    };

    await this.storageService.saveAccount(account);
    return account;
  }

  async updateAccount(account: Account): Promise<void> {
    account.updatedAt = Date.now();
    await this.storageService.saveAccount(account);
    MailSdkService.getInstance(this.storageService).clearEngineCache(account.id);
  }

  async deleteAccount(accountId: string): Promise<void> {
    await this.storageService.deleteAccount(accountId);
  }

  async getAllAccounts(): Promise<Account[]> {
    return await this.storageService.getAccounts();
  }

  async getAccountById(accountId: string): Promise<Account | null> {
    const accounts = await this.getAllAccounts();
    for (const a of accounts) {
      if (a.id === accountId) return a;
    }
    return null;
  }

  async setDefaultAccount(accountId: string): Promise<void> {
    const accounts = await this.getAllAccounts();
    for (const a of accounts) {
      a.isDefault = (a.id === accountId);
      await this.storageService.saveAccount(a);
    }
    await this.storageService.setCurrentAccountId(accountId);
  }

  async getDefaultAccount(): Promise<Account | null> {
    const accounts = await this.getAllAccounts();
    for (const a of accounts) {
      if (a.isDefault) return a;
    }
    if (accounts.length > 0) {
      return accounts[0];
    }
    return null;
  }

  async testConnection(account: Account): Promise<boolean> {
    try {
      await new Promise<void>((resolve) => setTimeout(resolve, 1000));
      return true;
    } catch (error) {
      this.logger.e('Connection test failed: ' + JSON.stringify(error));
      return false;
    }
  }

  async updateConnectionStatus(accountId: string, isConnected: boolean): Promise<void> {
    const account = await this.getAccountById(accountId);
    if (account) {
      account.isConnected = isConnected;
      account.lastSyncTime = isConnected ? Date.now() : undefined;
      await this.updateAccount(account);
    }
  }

  autoDetectSettings(email: string): Partial<Account> {
    const provider = Utils.detectProvider(email);
    const providerConfig = Constants.getProvider(provider);

    if (providerConfig) {
      return {
        incomingServer: providerConfig.imap.server,
        incomingPort: providerConfig.imap.port,
        incomingSecurity: providerConfig.imap.security as SecurityType,
        outgoingServer: providerConfig.smtp.server,
        outgoingPort: providerConfig.smtp.port,
        outgoingSecurity: providerConfig.smtp.security as SecurityType
      };
    }

    return {};
  }
}

