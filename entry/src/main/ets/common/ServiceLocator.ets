import { common } from '@kit.AbilityKit';
import { StorageService } from '../services/StorageService';
import { AccountService } from '../services/AccountService';
import { EmailService } from '../services/EmailService';
import { LogUtil } from './LogUtil';

const logger = new LogUtil('ServiceLocator');

let instance: ServiceLocator | null = null;

export interface Services {
  storageService: StorageService;
  accountService: AccountService;
  emailService: EmailService;
}

export interface BasicServices {
  storageService: StorageService;
  accountService: AccountService;
}

export class ServiceLocator {
  private storageService: StorageService | null = null;
  private accountService: AccountService | null = null;
  private emailService: EmailService | null = null;
  private context: common.Context | null = null;
  private isInitialized: boolean = false;

  private constructor() {}

  static getInstance(): ServiceLocator {
    if (!instance) {
      instance = new ServiceLocator();
    }
    return instance;
  }

  async initialize(context: common.Context): Promise<void> {
    if (this.isInitialized) {
      logger.d('Services already initialized');
      return;
    }

    try {
      logger.i('Initializing services...');
      this.context = context;
      this.storageService = StorageService.getInstance(context);
      await this.storageService.initialize();

      const cleaned = await this.storageService.cleanDuplicateEmails();
      if (cleaned > 0) {
        logger.i('Cleaned duplicate emails on startup: ' + cleaned);
      }

      this.accountService = AccountService.getInstance(this.storageService);
      this.emailService = EmailService.getInstance(this.storageService);
      this.isInitialized = true;
      logger.i('Services initialized successfully');
    } catch (error) {
      logger.e('Failed to initialize services:', error as string);
      throw new Error(`Service initialization failed: ${error}`);
    }
  }

  getStorageService(): StorageService | null {
    return this.storageService;
  }

  getAccountService(): AccountService | null {
    return this.accountService;
  }

  getEmailService(): EmailService | null {
    return this.emailService;
  }

  getContext(): common.Context | null {
    return this.context;
  }

  isServiceInitialized(): boolean {
    return this.isInitialized;
  }

  reset(): void {
    this.storageService = null;
    this.accountService = null;
    this.emailService = null;
    this.context = null;
    this.isInitialized = false;
    logger.i('Services reset');
  }
}

export async function useServices(context: common.Context): Promise<Services> {
  const locator = ServiceLocator.getInstance();
  await locator.initialize(context);

  const storageService = locator.getStorageService();
  const accountService = locator.getAccountService();
  const emailService = locator.getEmailService();

  if (!storageService || !accountService || !emailService) {
    throw new Error('Failed to get services');
  }

  const result: Services = {
    storageService: storageService,
    accountService: accountService,
    emailService: emailService
  };
  return result;
}

export async function useBasicServices(context: common.Context): Promise<BasicServices> {
  const locator = ServiceLocator.getInstance();
  await locator.initialize(context);

  const storageService = locator.getStorageService();
  const accountService = locator.getAccountService();

  if (!storageService || !accountService) {
    throw new Error('Failed to get basic services');
  }

  const result: BasicServices = {
    storageService: storageService,
    accountService: accountService
  };
  return result;
}