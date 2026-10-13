/**
 * Folder data model
 * Represents an email folder
 */
export interface Folder {
  id: string;
  accountId: string;
  
  // Folder information
  name: string;
  fullName: string;
  type: FolderType;
  icon?: string;
  
  // Folder statistics
  totalCount: number;
  unreadCount: number;
  
  // Sync status
  lastSyncTime?: number;
  isSynced: boolean;
  
  // Metadata
  selectable: boolean;
  createdAt: number;
  updatedAt: number;
}

export enum FolderType {
  INBOX = 0,
  SENT = 1,
  DRAFTS = 2,
  TRASH = 3,
  SPAM = 4,
  ARCHIVE = 5,
  CUSTOM = 6
}

export const STANDARD_FOLDERS: FolderType[] = [
  FolderType.INBOX,
  FolderType.SENT,
  FolderType.DRAFTS,
  FolderType.TRASH,
  FolderType.SPAM,
  FolderType.ARCHIVE
];
