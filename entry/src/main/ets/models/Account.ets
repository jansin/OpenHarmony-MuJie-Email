/**
 * Account data model
 * Represents an email account configuration
 */
export interface Account {
  id: string;
  email: string;
  displayName: string;
  protocol: 'IMAP' | 'POP3';
  smtpEnabled: boolean;
  
  // IMAP/POP3 settings
  incomingServer: string;
  incomingPort: number;
  incomingSecurity: 'NONE' | 'SSL' | 'TLS';
  incomingUsername?: string;
  
  // SMTP settings
  outgoingServer: string;
  outgoingPort: number;
  outgoingSecurity: 'NONE' | 'SSL' | 'TLS';
  outgoingUsername?: string;
  
  // Authentication
  password: string; // Should be encrypted in storage
  /** true: 客户端授权码 / 应用专用密码；false: 邮箱登录密码。未写入的旧数据在界面中按域名推断。 */
  useClientAuthCode?: boolean;
  signature?: string;

  // OAuth2
  authType?: 'password' | 'oauth2';
  accessToken?: string;
  refreshToken?: string;
  tokenExpiry?: number;

  // Account status
  isConnected: boolean;
  isDefault: boolean;
  lastSyncTime?: number;
  
  // Metadata
  createdAt: number;
  updatedAt: number;
}

export enum AccountProtocol {
  IMAP = 'IMAP',
  POP3 = 'POP3'
}

export enum SecurityType {
  NONE = 'NONE',
  SSL = 'SSL',
  TLS = 'TLS'
}
