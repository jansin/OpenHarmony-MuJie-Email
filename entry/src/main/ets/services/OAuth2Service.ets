import { http } from '@kit.NetworkKit';
import { Account } from '../models/Account';
import { StorageService } from './StorageService';

interface OAuthTokenJson {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
}

export interface OAuth2Provider {
  name: string;
  authUrl: string;
  tokenUrl: string;
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  scopes: string[];
}

export interface OAuth2TokenResult {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export interface OAuth2RefreshResult {
  accessToken: string;
  expiresIn: number;
}

export class OAuth2Service {
  private static instance: OAuth2Service;
  private storageService: StorageService;

  private constructor(storageService: StorageService) {
    this.storageService = storageService;
  }

  static getInstance(storageService: StorageService): OAuth2Service {
    if (!OAuth2Service.instance) {
      OAuth2Service.instance = new OAuth2Service(storageService);
    }
    return OAuth2Service.instance;
  }

  private static createGmailProvider(): OAuth2Provider {
    const p: OAuth2Provider = {
      name: 'Gmail',
      authUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
      tokenUrl: 'https://oauth2.googleapis.com/token',
      clientId: '',
      clientSecret: '',
      redirectUri: 'com.jason.email:/oauth2redirect',
      scopes: ['https://mail.google.com/']
    };
    return p;
  }

  private static createOutlookProvider(): OAuth2Provider {
    const p: OAuth2Provider = {
      name: 'Outlook',
      authUrl: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
      tokenUrl: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
      clientId: '',
      clientSecret: '',
      redirectUri: 'com.jason.email:/oauth2redirect',
      scopes: ['https://outlook.office.com/IMAP.AccessAsUser.All',
        'https://outlook.office.com/SMTP.Send', 'offline_access']
    };
    return p;
  }

  getProvider(account: Account): OAuth2Provider | undefined {
    const domain = account.email.split('@')[1]?.toLowerCase() || '';
    if (domain.includes('gmail.com')) return OAuth2Service.createGmailProvider();
    if (domain.includes('outlook.com') || domain.includes('hotmail.com') || domain.includes('live.com')) {
      return OAuth2Service.createOutlookProvider();
    }
    return undefined;
  }

  supportsOAuth2(account: Account): boolean {
    return this.getProvider(account) !== undefined;
  }

  getAuthUrl(provider: OAuth2Provider): string {
    return provider.authUrl +
      '?client_id=' + encodeURIComponent(provider.clientId) +
      '&redirect_uri=' + encodeURIComponent(provider.redirectUri) +
      '&response_type=code' +
      '&scope=' + encodeURIComponent(provider.scopes.join(' ')) +
      '&access_type=offline' +
      '&prompt=consent';
  }

  async exchangeCode(provider: OAuth2Provider, code: string): Promise<OAuth2TokenResult | null> {
    const bodyStr = 'grant_type=authorization_code' +
      '&code=' + encodeURIComponent(code) +
      '&client_id=' + encodeURIComponent(provider.clientId) +
      '&client_secret=' + encodeURIComponent(provider.clientSecret) +
      '&redirect_uri=' + encodeURIComponent(provider.redirectUri);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/x-www-form-urlencoded' },
      extraData: bodyStr
    };
    const client = http.createHttp();
    try {
      const resp: http.HttpResponse = await client.request(provider.tokenUrl, options);
      if (resp.responseCode !== 200) return null;
      const text = resp.result as string;
      const data = JSON.parse(text) as OAuthTokenJson;
      if (!data.access_token || !data.refresh_token || data.expires_in === undefined) return null;
      const r: OAuth2TokenResult = {
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
        expiresIn: data.expires_in
      };
      return r;
    } catch (e) {
      return null;
    } finally {
      client.destroy();
    }
  }

  async refreshAccessToken(provider: OAuth2Provider, refreshToken: string): Promise<OAuth2RefreshResult | null> {
    const bodyStr = 'grant_type=refresh_token' +
      '&refresh_token=' + encodeURIComponent(refreshToken) +
      '&client_id=' + encodeURIComponent(provider.clientId) +
      '&client_secret=' + encodeURIComponent(provider.clientSecret);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/x-www-form-urlencoded' },
      extraData: bodyStr
    };
    const client = http.createHttp();
    try {
      const resp: http.HttpResponse = await client.request(provider.tokenUrl, options);
      if (resp.responseCode !== 200) return null;
      const text = resp.result as string;
      const data = JSON.parse(text) as OAuthTokenJson;
      if (!data.access_token || data.expires_in === undefined) return null;
      const r: OAuth2RefreshResult = {
        accessToken: data.access_token,
        expiresIn: data.expires_in
      };
      return r;
    } catch (e) {
      return null;
    } finally {
      client.destroy();
    }
  }

  async ensureValidToken(account: Account): Promise<string | null> {
    if (account.authType !== 'oauth2') return account.password;
    if (!account.accessToken) return null;
    if (account.tokenExpiry && Date.now() < account.tokenExpiry - 60000) {
      return account.accessToken;
    }
    if (!account.refreshToken) return null;
    const provider = this.getProvider(account);
    if (!provider) return null;
    const result = await this.refreshAccessToken(provider, account.refreshToken);
    if (!result) return null;
    account.accessToken = result.accessToken;
    account.tokenExpiry = Date.now() + result.expiresIn * 1000;
    await this.storageService.saveAccount(account);
    return result.accessToken;
  }
}

