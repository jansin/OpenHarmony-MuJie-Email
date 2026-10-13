import { Attachment } from './Attachment';

export interface Email {
  id: string;
  accountId: string;
  folderId: string;
  messageId: string;
  subject: string;
  from: EmailAddress;
  to: EmailAddress[];
  cc?: EmailAddress[];
  bcc?: EmailAddress[];
  replyTo?: EmailAddress[];
  date: number;
  bodyText?: string;
  bodyHtml?: string;
  preview: string;
  isRead: boolean;
  isStarred: boolean;
  isDeleted: boolean;
  isDraft: boolean;
  isAnswered: boolean;
  isForwarded: boolean;
  attachments: Attachment[];
  hasAttachments: boolean;
  isSynced: boolean;
  syncError?: string;
  size: number;
  uid?: number;
  createdAt: number;
  updatedAt: number;
}

export interface EmailAddress {
  name?: string;
  /** 主邮箱地址（展示、发信） */
  address: string;
  /** 历史 JSON / SDK 可能仅存此字段，读库后由 normalize 合并到 address */
  email?: string;
}

export enum EmailFlag {
  SEEN = 'SEEN',
  ANSWERED = 'ANSWERED',
  FLAGGED = 'FLAGGED',
  DELETED = 'DELETED',
  DRAFT = 'DRAFT',
  RECENT = 'RECENT'
}
