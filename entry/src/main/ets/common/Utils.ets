/**
 * Utility functions
 */
import { util } from '@kit.ArkTS';
import common from '@ohos.app.ability.common';
import { EmailAddress } from '../models/Email';

export class Utils {
  /**
   * Generate unique ID
   */
  static generateId(): string {
    return util.generateRandomUUID();
  }
  
  /**
   * Format file size
   */
  static formatFileSize(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
  }
  
  /**
   * Format date
   */
  static formatDate(context: common.UIAbilityContext, timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    if (days === 0) {
      const hours = Math.floor(diff / (1000 * 60 * 60));
      if (hours === 0) {
        const minutes = Math.floor(diff / (1000 * 60));
        const justNow = Utils.resourceToString(context, $r('app.string.time_just_now'));
        const minutesAgo = Utils.resourceToString(context, $r('app.string.time_minutes_ago'));
        return minutes === 0 ? justNow : minutesAgo.replace('$1', minutes.toString());
      }
      const hoursAgo = Utils.resourceToString(context, $r('app.string.time_hours_ago'));
      return hoursAgo.replace('$1', hours.toString());
    } else if (days === 1) {
      return Utils.resourceToString(context, $r('app.string.time_yesterday'));
    } else if (days < 7) {
      const daysAgo = Utils.resourceToString(context, $r('app.string.time_days_ago'));
      return daysAgo.replace('$1', days.toString());
    } else {
      return `${date.getMonth() + 1}/${date.getDate()}`;
    }
  }
  
  /**
   * Format date full
   */
  static formatDateFull(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = date.getMonth() + 1;
    const day = date.getDate();
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return year + '/' + month + '/' + day + ' ' + hours + ':' + minutes;
  }

  /** Format single email address as "Name <addr>" or plain address */
  private static safeString(v: string | object | number | boolean | undefined | null): string {
    if (v === undefined || v === null) {
      return '';
    }
    if (typeof v === 'string') {
      return v.trim();
    }
    return '';
  }

  static formatOneAddress(a: EmailAddress): string {
    const addr = Utils.safeString(a.address);
    const email = Utils.safeString(a.email);
    const address = addr.length > 0 ? addr : email;
    const name = Utils.safeString(a.name);
    if (!address && !name) {
      return '';
    }
    if (!address) {
      return name;
    }
    if (!name || name === address) {
      return address;
    }
    return name + ' <' + address + '>';
  }

  /** 多收件人/抄送逗号分隔 */
  static formatAddressList(addrs: EmailAddress[]): string {
    const parts: string[] = [];
    for (const x of addrs) {
      const line = Utils.formatOneAddress(x);
      if (line.length > 0) {
        parts.push(line);
      }
    }
    return parts.join(', ');
  }
  
  /**
   * Extract email domain
   */
  static extractDomain(email: string): string {
    const match = email.match(/@(.+)/);
    return match ? match[1] : '';
  }
  
  /**
   * Detect email provider
   */
  static detectProvider(email: string): string {
    const domain = Utils.extractDomain(email).toLowerCase();
    if (domain.includes('gmail.com')) return 'gmail';
    if (domain.includes('outlook.com') || domain.includes('hotmail.com') || domain.includes('live.com')) return 'outlook';
    if (domain.includes('qq.com') || domain.includes('foxmail.com') || domain.includes('vip.qq.com')) return 'qq';
    if (domain.includes('163.com') || domain.includes('yeah.net')) return '163';
    if (domain.includes('126.com')) return '126';
    if (domain.includes('188.com')) return '188';
    if (domain.includes('sina.com')) return 'sina';
    if (domain.includes('139.com')) return '139';
    if (domain.includes('sohu.com')) return 'sohu';
    if (domain.includes('aliyun.com')) return 'aliyun';
    if (domain.includes('tom.com')) return 'tom';
    return 'custom';
  }
  
  /**
   * Simple base64 encoding
   */
  static encode(data: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    let i = 0;
    while (i < data.length) {
      const b1 = data.charCodeAt(i++);
      const b2 = i < data.length ? data.charCodeAt(i++) : NaN;
      const b3 = i < data.length ? data.charCodeAt(i++) : NaN;
      const triplet = (b1 << 16) | (b2 << 8) | b3;
      result += chars.charAt((triplet >> 18) & 0x3F);
      result += chars.charAt((triplet >> 12) & 0x3F);
      result += isNaN(b2) ? '=' : chars.charAt((triplet >> 6) & 0x3F);
      result += isNaN(b3) ? '=' : chars.charAt(triplet & 0x3F);
    }
    return result;
  }
  
  /**
   * Simple base64 decoding
   */
  static decode(encodedData: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    let i = 0;
    encodedData = encodedData.replace(/[^A-Za-z0-9+/=]/g, '');
    while (i < encodedData.length) {
      const b1 = chars.indexOf(encodedData.charAt(i++));
      const b2 = chars.indexOf(encodedData.charAt(i++));
      const b3 = chars.indexOf(encodedData.charAt(i++));
      const b4 = chars.indexOf(encodedData.charAt(i++));
      const triplet = (b1 << 18) | (b2 << 12) | ((b3 & 0x3F) << 6) | (b4 & 0x3F);
      result += String.fromCharCode((triplet >> 16) & 0xFF);
      if (b3 !== 64) result += String.fromCharCode((triplet >> 8) & 0xFF);
      if (b4 !== 64) result += String.fromCharCode(triplet & 0xFF);
    }
    return result;
  }
  
  /**
   * Validate email format
   */
  static isValidEmail(email: string): boolean {
    const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return regex.test(email);
  }
  
  /**
   * Truncate text
   */
  static truncateText(text: string, maxLength: number): string {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength) + '...';
  }

  /**
   * Convert Resource to string
   */
  static resourceToString(context: common.UIAbilityContext, res: Resource): string {
    try {
      return context.resourceManager.getStringSync(res.id);
    } catch (error) {
      return '';
    }
  }

  static normalizeSubject(subject: string | object | undefined | null): string {
    const s0 = Utils.coerceUiString(subject);
    if (!s0) {
      return '';
    }
    let s = s0.trim();
    s = s.replace(/^(Re|Fwd|回复|转发|�?|RE|FWD)\s*:\s*/g, '');
    s = s.replace(/^(Re|Fwd|回复|转发|�?|RE|FWD)\s*:\s*/g, '');
    s = s.replace(/\[.*?\]/g, '').trim();
    if (s.length === 0) return s0.trim();
    return s;
  }

  /**
   * 将可能误入的 Object/非字符串转为界面安全文本，避免出�?[object Object]�?
   */
  static coerceUiString(v: string | object | number | boolean | undefined | null): string {
    if (v === undefined || v === null) {
      return '';
    }
    if (typeof v === 'string') {
      return v;
    }
    if (typeof v === 'number' || typeof v === 'boolean') {
      return String(v);
    }
    return '';
  }

  static stripHtml(html: string): string {
    let text = html;
    text = text.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '');
    text = text.replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '');
    text = text.replace(/<br\s*\/?>/gi, '\n');
    text = text.replace(/<p[^>]*>/gi, '\n');
    text = text.replace(/<\/p>/gi, '\n');
    text = text.replace(/<div[^>]*>/gi, '\n');
    text = text.replace(/<\/div>/gi, '');
    text = text.replace(/<tr[^>]*>/gi, '\n');
    text = text.replace(/<\/tr>/gi, '');
    text = text.replace(/<td[^>]*>/gi, ' ');
    text = text.replace(/<\/td>/gi, '');
    text = text.replace(/<li[^>]*>/gi, '\n- ');
    text = text.replace(/<\/li>/gi, '');
    text = text.replace(/<[^>]+>/g, '');
    text = text.replace(/&amp;/g, '&');
    text = text.replace(/&lt;/g, '<');
    text = text.replace(/&gt;/g, '>');
    text = text.replace(/&quot;/g, '"');
    text = text.replace(/&#39;/g, "'");
    text = text.replace(/&nbsp;/g, ' ');
    text = text.replace(/&[a-zA-Z]+;/g, '');
    text = text.replace(/\n{3,}/g, '\n\n');
    text = text.replace(/^\s+|\s+$/gm, '');
    text = text.trim();
    return text;
  }
}


