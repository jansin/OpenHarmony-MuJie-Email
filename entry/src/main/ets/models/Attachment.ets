/**
 * Attachment data model
 * Represents an email attachment
 */
export interface Attachment {
  id: string;
  emailId: string;
  
  // Attachment information
  filename: string;
  contentType: string;
  size: number;
  
  // Attachment data
  contentId?: string; // For inline images
  disposition: 'attachment' | 'inline';
  
  // Storage
  localPath?: string;
  isDownloaded: boolean;
  downloadProgress?: number;
  
  // Metadata
  createdAt: number;
}

export interface AttachmentDownloadProgress {
  attachmentId: string;
  progress: number;
  status: 'pending' | 'downloading' | 'completed' | 'failed';
  error?: string;
}
