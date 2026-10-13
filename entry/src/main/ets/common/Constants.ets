export class ServerConfig {
  server: string = '';
  port: number = 0;
  security: string = '';
}

export class ProviderConfig {
  imap: ServerConfig = new ServerConfig();
  pop3: ServerConfig = new ServerConfig();
  smtp: ServerConfig = new ServerConfig();
}

export class Constants {
  static readonly ACCOUNTS_KEY: string = 'accounts';
  static readonly SETTINGS_KEY: string = 'settings';
  static readonly CURRENT_ACCOUNT_KEY: string = 'current_account';
  static readonly DB_NAME: string = 'MailClientDB';
  static readonly DB_VERSION: number = 2;
  static readonly TABLE_ACCOUNTS: string = 'accounts';
  static readonly TABLE_EMAILS: string = 'emails';
  static readonly TABLE_FOLDERS: string = 'folders';
  static readonly TABLE_ATTACHMENTS: string = 'attachments';
  static readonly TABLE_CONTACTS: string = 'contacts';
  static readonly TABLE_FILTER_RULES: string = 'filter_rules';
  static readonly SYNC_INTERVAL_MINUTES: number = 15;
  static readonly MAX_CACHE_SIZE_MB: number = 500;
  static readonly MAX_ATTACHMENT_SIZE_MB: number = 25;
  static readonly EMAIL_LIST_PAGE_SIZE: number = 50;
  static readonly MAX_ATTACHMENT_DOWNLOAD_CONCURRENT: number = 3;
  private static providerCache: Record<string, ProviderConfig> | null = null;

  static getProvider(key: string): ProviderConfig | undefined {
    const map = Constants.initProviders();
    return map[key];
  }

  static get COMMON_PROVIDERS(): Record<string, ProviderConfig> {
    return Constants.initProviders();
  }

  private static initProviders(): Record<string, ProviderConfig> {
    if (Constants.providerCache) {
      return Constants.providerCache;
    }
    const map: Record<string, ProviderConfig> = {};
    map['gmail'] = Constants.createGmailConfig();
    map['outlook'] = Constants.createOutlookConfig();
    map['qq'] = Constants.createQQConfig();
    map['163'] = Constants.create163Config();
    map['sina'] = Constants.createSinaConfig();
    map['126'] = Constants.create126Config();
    map['188'] = Constants.create188Config();
    map['foxmail'] = Constants.createFoxmailConfig();
    map['139'] = Constants.create139Config();
    map['sohu'] = Constants.createSohuConfig();
    map['aliyun'] = Constants.createAliyunConfig();
    map['tom'] = Constants.createTomConfig();
    Constants.providerCache = map;
    return map;
  }

  private static createServerConfig(server: string, port: number, security: string): ServerConfig {
    const config = new ServerConfig();
    config.server = server;
    config.port = port;
    config.security = security;
    return config;
  }

  private static createProviderConfig(imap: ServerConfig, pop3: ServerConfig, smtp: ServerConfig): ProviderConfig {
    const config = new ProviderConfig();
    config.imap = imap;
    config.pop3 = pop3;
    config.smtp = smtp;
    return config;
  }

  private static createGmailConfig(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.gmail.com', 993, 'SSL'),
      Constants.createServerConfig('pop.gmail.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.gmail.com', 587, 'TLS')
    );
  }

  private static createOutlookConfig(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('outlook.office365.com', 993, 'SSL'),
      Constants.createServerConfig('outlook.office365.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.office365.com', 587, 'TLS')
    );
  }

  private static createQQConfig(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.qq.com', 993, 'SSL'),
      Constants.createServerConfig('pop.qq.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.qq.com', 587, 'TLS')
    );
  }

  private static create163Config(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.163.com', 993, 'SSL'),
      Constants.createServerConfig('pop.163.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.163.com', 465, 'SSL')
    );
  }

  private static createSinaConfig(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.sina.com', 993, 'SSL'),
      Constants.createServerConfig('pop.sina.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.sina.com', 465, 'SSL')
    );
  }

  private static create126Config(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.126.com', 993, 'SSL'),
      Constants.createServerConfig('pop.126.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.126.com', 465, 'SSL')
    );
  }

  private static create188Config(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.188.com', 993, 'SSL'),
      Constants.createServerConfig('pop.188.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.188.com', 465, 'SSL')
    );
  }

  private static createFoxmailConfig(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.foxmail.com', 993, 'SSL'),
      Constants.createServerConfig('pop.foxmail.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.foxmail.com', 587, 'TLS')
    );
  }

  private static create139Config(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.139.com', 993, 'SSL'),
      Constants.createServerConfig('pop.139.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.139.com', 465, 'SSL')
    );
  }

  private static createSohuConfig(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.sohu.com', 993, 'SSL'),
      Constants.createServerConfig('pop.sohu.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.sohu.com', 465, 'SSL')
    );
  }

  private static createAliyunConfig(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.aliyun.com', 993, 'SSL'),
      Constants.createServerConfig('pop.aliyun.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.aliyun.com', 465, 'SSL')
    );
  }

  private static createTomConfig(): ProviderConfig {
    return Constants.createProviderConfig(
      Constants.createServerConfig('imap.tom.com', 993, 'SSL'),
      Constants.createServerConfig('pop.tom.com', 995, 'SSL'),
      Constants.createServerConfig('smtp.tom.com', 465, 'SSL')
    );
  }
}
