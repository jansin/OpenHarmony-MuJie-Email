import { router } from '@kit.ArkUI';
import { Email } from '../models/Email';
import { Folder, FolderType } from '../models/Folder';
import { Account, AccountProtocol } from '../models/Account';
import { StorageService } from '../services/StorageService';
import { AccountService } from '../services/AccountService';
import { EmailService } from '../services/EmailService';
import { common } from '@kit.AbilityKit';
import { Utils } from '../common/Utils';
import { EmailTheme, DARK_THEME, LIGHT_THEME } from '../common/Theme';
import { EmailItem } from '../components/EmailItem';
import { ToastUtil } from '../common/ToastUtil';
import { LogUtil } from '../common/LogUtil';

@Entry
@Component
struct EmailList {
  private context = getContext(this) as common.UIAbilityContext;
  @State emails: Email[] = [];
  @State folderId: string = '';
  @State folderName: string = Utils.resourceToString(this.context, $r('app.string.folder_inbox'));
  @State folderType: FolderType = FolderType.INBOX;
  @State searchQuery: string = '';
  @State currentAccount: Account | null = null;
  @State isLoading: boolean = true;
  @State syncError: string = '';
  @State isSyncing: boolean = false;
  @State selectedEmails: string[] = [];
  @State isSelectionMode: boolean = false;
  private selectedEmailSet: Set<string> = new Set();
  @State showSearch: boolean = false;
  @State showThreading: boolean = false;
  @State expandedThreads: Set<string> = new Set();
  @State themeVersion: number = 0;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @State emailOffset: number = 0;
  @State hasMore: boolean = true;
  @State isRefreshing: boolean = false;
  @State showUnreadOnly: boolean = false;
  private readonly pageSize: number = 50;
  private logger: LogUtil = new LogUtil('EmailList');
  private storageService: StorageService | null = null;
  private accountService: AccountService | null = null;
  private emailService: EmailService | null = null;
  /** 防止连续 void 触发多次完整 IMAP 拉取 */
  private imapMailboxSyncBusy: boolean = false;
  private theme(): EmailTheme {
    return this.isDarkMode ? DARK_THEME : LIGHT_THEME;
  }
  private avatarColor(name: string): string {
    const colors = this.theme().avatarColors;
    if (!name || name.length === 0 || colors.length === 0) {
      return this.theme().primary;
    }
    return colors[name.charCodeAt(0) % colors.length];
  }





  aboutToAppear(): void {
    this.initializeServices();
  }

  onThemeChange = (isDark: boolean): void => {
    this.themeVersion++;
  }

onPageShow(): void {
    this.themeVersion++;
    if (!this.storageService || !this.folderId) {
      return;
    }
    if (this.folderId === '__unified__') {
      void this.loadUnifiedEmails();
      return;
    }
    void this.refreshListFromDatabaseOnly();
  }

  onPageHide(): void {
  }

  async initializeServices(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.storageService = StorageService.getInstance(context);
      await this.storageService.initialize();
      this.accountService = AccountService.getInstance(this.storageService);
      this.emailService = EmailService.getInstance(this.storageService);
      await this.loadPageData();
    } catch (error) { this.logger.e('Failed to initialize: ' + JSON.stringify(error)); } finally {
      this.isLoading = false;
    }
  }

  async loadPageData(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      this.folderId = (params['folderId'] as string) || '';
      this.folderName = (params['folderName'] as string) || Utils.resourceToString(this.context, $r('app.string.folder_inbox'));
      this.folderType = (params['folderType'] as FolderType) || FolderType.INBOX;
      this.searchQuery = (params['searchQuery'] as string) || '';
    }
    await this.loadCurrentAccount();
    if (!this.searchQuery && this.folderId !== '__unified__' && this.storageService && this.currentAccount &&
      (!this.folderId || this.folderId.length === 0)) {
      const fs = await this.storageService.getFoldersByAccountId(this.currentAccount.id);
      const resolved = this.resolveFolderForList(fs, '', this.folderType);
      if (resolved) {
        this.folderId = resolved.id;
      }
    }
    if (this.searchQuery) {
      await this.searchEmails();
    } else {
      await this.loadEmails();
    }
  }

  async loadCurrentAccount(): Promise<void> {
    if (!this.accountService) return;
    try {
      this.currentAccount = await this.accountService.getDefaultAccount();
    } catch (error) { this.logger.e('Failed to load account: ' + JSON.stringify(error)); }
  }

  /**
   * 路由或旧数据�?folderId 可能�?IMAP 同步后的 id（账号_INBOX）不一致，�?id �?类型 �?INBOX 全名 回退解析�?
   */
  private resolveFolderForList(folders: Folder[], preferId: string, folderType: FolderType): Folder | null {
    if (preferId && preferId.length > 0) {
      const byId = folders.find(f => f.id === preferId);
      if (byId) {
        return byId;
      }
    }
    if (folderType === FolderType.INBOX) {
      const canonicalInbox = folders.find(f => f.type === FolderType.INBOX && f.fullName.toUpperCase() === 'INBOX');
      if (canonicalInbox) {
        return canonicalInbox;
      }
    }
    const byType = folders.find(f => f.type === folderType);
    return byType ?? null;
  }

  private formatImapSyncError(e: Error): string {
    const base = Utils.resourceToString(this.context, $r('app.string.msg_sync_failed'));
    let detail = '';
    if (e instanceof Error) {
      detail = e.message;
    } else {
      detail = String(e);
    }
    const lower = detail.toLowerCase();
    const neteaseUnsafe = lower.includes('unsafe login') || detail.includes('kefu@188') || detail.includes('kefu@163');
    const hint = neteaseUnsafe
      ? Utils.resourceToString(this.context, $r('app.string.msg_sync_163_unsafe'))
      : '';
    if (detail.length > 0) {
      return base + '\n' + detail + (hint.length > 0 ? '\n' + hint : '');
    }
    return base;
  }

  private deduplicateEmails(list: Email[]): Email[] {
    const seen = new Set<string>();
    const result: Email[] = [];
    for (const e of list) {
      if (!seen.has(e.id)) {
        seen.add(e.id);
        result.push(e);
      }
    }
    return result;
  }

  private isLocalFolder(): boolean {
    return this.folderType === FolderType.DRAFTS ||
           this.folderType === FolderType.TRASH ||
           this.folderType === FolderType.SPAM ||
           this.folderType === FolderType.ARCHIVE ||
           this.folderId === '__unified__';
  }

  async loadEmails(): Promise<void> {
    if (!this.storageService) return;
    this.syncError = '';
    this.emailOffset = 0;
    this.hasMore = true;
    try {
      if (this.folderId === '__unified__') {
        await this.loadUnifiedEmails();
        return;
      }
      this.emails = this.deduplicateEmails(await this.storageService.getEmailsByFolderId(this.folderId, 0, this.pageSize));
      this.hasMore = this.emails.length >= this.pageSize;
      this.isLoading = false;

      if (this.isLocalFolder() || this.imapMailboxSyncBusy) {
        return;
      }
      this.imapMailboxSyncBusy = true;
      void this.syncImapEmailsAfterIdle();
    } catch (error) {
      this.logger.e('Failed to load emails: ' + JSON.stringify(error));
      this.syncError = Utils.resourceToString(this.context, $r('app.string.msg_sync_failed'));
    }
  }

  private async syncImapEmailsAfterIdle(): Promise<void> {
    await new Promise<void>((resolve: (v?: void) => void) => {
      setTimeout((): void => {
        resolve();
      }, 0);
    });
    await new Promise<void>((resolve: (v?: void) => void) => {
      setTimeout((): void => {
        resolve();
      }, 120);
    });
    if (this.isLocalFolder()) {
      this.imapMailboxSyncBusy = false;
      return;
    }
    this.isSyncing = true;
    try {
      if (!this.storageService || !this.currentAccount || !this.emailService) {
        return;
      }
      if (this.currentAccount.protocol === AccountProtocol.IMAP) {
        const foldersBefore = await this.storageService.getFoldersByAccountId(this.currentAccount.id);
        if (foldersBefore.length === 0) {
          await this.emailService.fetchFolders(this.currentAccount);
        }
      }
      let folders = await this.storageService.getFoldersByAccountId(this.currentAccount.id);
      let folder = this.resolveFolderForList(folders, this.folderId, this.folderType);
      if (!folder && this.currentAccount.protocol === AccountProtocol.IMAP) {
        await this.emailService.fetchFolders(this.currentAccount);
        folders = await this.storageService.getFoldersByAccountId(this.currentAccount.id);
        folder = this.resolveFolderForList(folders, this.folderId, this.folderType);
      }
      if (folder) {
        if (folder.id !== this.folderId) {
          this.folderId = folder.id;
        }
        await this.emailService.fetchEmails(this.currentAccount, folder, this.pageSize);
      }
      const updated = this.deduplicateEmails(await this.storageService.getEmailsByFolderId(this.folderId, 0, this.pageSize));
      if (updated.length > 0) {
        this.emails = updated;
        this.hasMore = updated.length >= this.pageSize;
      }
      this.syncError = '';
    } catch (error) {
      this.logger.e('Failed to load emails: ' + JSON.stringify(error));
      this.syncError = this.formatImapSyncError(error);
    } finally {
      this.isSyncing = false;
      this.imapMailboxSyncBusy = false;
    }
  }

  /** 子页返回时轻量刷新列表，不建 IMAP 连接 */
  private async refreshListFromDatabaseOnly(): Promise<void> {
    if (!this.storageService || !this.folderId) {
      return;
    }
    try {
      this.emails = this.deduplicateEmails(await this.storageService.getEmailsByFolderId(this.folderId, 0, this.pageSize));
      this.hasMore = this.emails.length >= this.pageSize;
      this.emailOffset = 0;
    } catch (e) {
      this.logger.e('refreshListFromDatabaseOnly: ' + JSON.stringify(e));
    }
  }

  async loadUnifiedEmails(): Promise<void> {
    if (!this.storageService) return;
    try {
      const allAccounts = await this.storageService.getAccounts();
      const seenMessageIds = new Set<string>();
      const result: Email[] = [];
      for (const acc of allAccounts) {
        const folders = await this.storageService.getFoldersByAccountId(acc.id);
        const inbox = folders.find(f => f.type === FolderType.INBOX);
        if (inbox) {
          const emails = await this.storageService.getEmailsByFolderId(inbox.id, 0, this.pageSize * 2);
          for (const email of emails) {
            const msgId = email.messageId || email.id;
            if (!seenMessageIds.has(msgId)) {
              seenMessageIds.add(msgId);
              result.push(email);
            }
          }
        }
      }
      result.sort((a, b) => b.date - a.date);
      this.emails = result.slice(0, this.pageSize);
      this.hasMore = result.length >= this.pageSize;
      this.isLoading = false;
    } catch (e) {
      this.logger.e('Failed to load unified emails: ' + JSON.stringify(e));
    }
  }

  async loadFromCache(): Promise<void> {
    if (!this.storageService) return;
    this.emails = await this.storageService.getEmailsByFolderId(this.folderId, 0, this.pageSize);
    this.hasMore = this.emails.length >= this.pageSize;
    this.isLoading = false;
  }

  async loadMoreEmails(): Promise<void> {
    if (!this.storageService || !this.hasMore) return;
    const newOffset = this.emailOffset + this.pageSize;
    try {
      const more = await this.storageService.getEmailsByFolderId(this.folderId, newOffset, this.pageSize);
      if (more.length > 0) {
        const existingIds = new Set<string>();
        for (const e of this.emails) existingIds.add(e.id);
        const deduped: Email[] = [];
        for (const e of more) {
          if (!existingIds.has(e.id)) {
            deduped.push(e);
            existingIds.add(e.id);
          }
        }
        this.emails = this.emails.concat(deduped);
        this.emailOffset = newOffset;
        this.hasMore = more.length >= this.pageSize;
      } else {
        this.hasMore = false;
      }
    } catch (error) {
      this.logger.e('Failed to load more: ' + JSON.stringify(error));
    }
  }

  private deduplicateEmailsInPlace(list: Email[]): void {
    const seen = new Set<string>();
    const result: Email[] = [];
    for (const e of list) {
      if (!seen.has(e.id)) {
        seen.add(e.id);
        result.push(e);
      }
    }
    if (result.length < list.length) {
      list.length = 0;
      for (const e of result) {
        list.push(e);
      }
    }
  }

  async searchEmails(): Promise<void> {
    if (!this.emailService || !this.currentAccount) return;
    try {
      const q = this.searchQuery.trim();
      if (!q) return;
      this.isSyncing = true;
      await new Promise<void>((resolve: () => void) => {
        setTimeout((): void => {
          resolve();
        }, 0);
      });
      this.emails = await this.emailService.searchEmails(this.currentAccount, q);
    } catch (error) {
      this.logger.e('Failed to search emails: ' + JSON.stringify(error));
    } finally {
      this.isSyncing = false;
    }
  }

  async refreshEmails(): Promise<void> {
    this.syncError = '';
    this.isSyncing = true;
    try {
      if (!this.isLocalFolder() && this.currentAccount && this.emailService) {
        await new Promise<void>((resolve: () => void) => {
          setTimeout((): void => {
            resolve();
          }, 0);
        });
        if (this.currentAccount.protocol === AccountProtocol.IMAP) {
          await this.emailService.fetchFolders(this.currentAccount);
        }
        let folders = await this.storageService?.getFoldersByAccountId(this.currentAccount.id) || [];
        let folder = this.resolveFolderForList(folders, this.folderId, this.folderType);
        if (!folder && this.currentAccount.protocol === AccountProtocol.IMAP) {
          await this.emailService.fetchFolders(this.currentAccount);
          folders = await this.storageService?.getFoldersByAccountId(this.currentAccount.id) || [];
          folder = this.resolveFolderForList(folders, this.folderId, this.folderType);
        }
        if (folder) {
          if (folder.id !== this.folderId) {
            this.folderId = folder.id;
          }
          await this.emailService.fetchEmails(this.currentAccount, folder, 50);
        }
      }
      const refreshed = this.deduplicateEmails(await this.storageService?.getEmailsByFolderId(this.folderId, 0, this.pageSize) || []);
      if (refreshed.length > 0 || !this.isLocalFolder()) {
        this.emails = refreshed;
        this.hasMore = refreshed.length >= this.pageSize;
      }
      this.syncError = '';
    } catch (error) {
      this.logger.e('Failed to refresh: ' + JSON.stringify(error));
      this.syncError = this.formatImapSyncError(error);
    } finally {
      this.isSyncing = false;
    }
  }

  navigateToEmailDetail(email: Email): void {
    if (this.isSelectionMode) {
      this.toggleEmailSelection(email.id);
    } else {
      if (!email.isRead) {
        this.markAsRead(email.id);
      }
      router.pushUrl({ url: 'pages/EmailDetail', params: { emailId: email.id, folderId: this.folderId } });
    }
  }

  navigateToCompose(): void {
    router.pushUrl({ url: 'pages/ComposeEmail' });
  }

  goBack(): void {
    router.back();
  }

  toggleEmailSelection(emailId: string): void {
    if (this.selectedEmailSet.has(emailId)) {
      this.selectedEmailSet.delete(emailId);
      this.selectedEmails = this.selectedEmails.filter(id => id !== emailId);
    } else {
      this.selectedEmailSet.add(emailId);
      this.selectedEmails = this.selectedEmails.concat([emailId]);
    }
    this.isSelectionMode = this.selectedEmails.length > 0;
  }

  clearSelection(): void {
    this.selectedEmails = [];
    this.selectedEmailSet.clear();
    this.isSelectionMode = false;
  }

  async deleteSelectedEmails(): Promise<void> {
    if (!this.storageService) return;
    try {
      for (const emailId of this.selectedEmails) {
        await this.storageService.deleteEmail(emailId);
      }
      this.clearSelection();
      await this.loadEmails();
      ToastUtil.showSuccess(Utils.resourceToString(this.context, $r('app.string.msg_delete_success')));
    } catch (error) {
      this.logger.e('Failed to delete: ' + JSON.stringify(error));
      ToastUtil.showError(Utils.resourceToString(this.context, $r('app.string.msg_delete_failed')));
    }
  }

  async markAsRead(emailId: string): Promise<void> {
    if (!this.storageService) return;
    try {
      await this.storageService.updateEmailFlags(emailId, { 'isRead': 1 });
    } catch (error) {
      this.logger.e('Failed to mark as read: ' + JSON.stringify(error));
    }
  }

  async toggleStar(emailId: string, isStarred: boolean): Promise<void> {
    if (!this.storageService) return;
    try {
      await this.storageService.updateEmailFlags(emailId, { 'isStarred': isStarred ? 0 : 1 });
    } catch (error) {
      this.logger.e('Failed to toggle star: ' + JSON.stringify(error));
    }
  }

  async archiveEmail(emailId: string): Promise<void> {
    if (!this.storageService) return;
    try {
      const email = this.emails.find(e => e.id === emailId);
      if (email) {
        // Find Archive folder
        const folders = await this.storageService.getFoldersByAccountId(email.accountId);
        const archiveFolder = folders.find(f => f.type === FolderType.ARCHIVE);
        if (archiveFolder) {
          // Move email to Archive folder locally
          email.folderId = archiveFolder.id;
          await this.storageService.saveEmail(email);
          // Try to sync with IMAP server
          if (this.emailService && this.currentAccount) {
            const uid = parseInt(email.messageId);
            if (uid > 0 && this.currentAccount.protocol === AccountProtocol.IMAP) {
              await this.emailService.archiveEmail(this.currentAccount, email, archiveFolder.fullName);
            }
          }
        } else {
          await this.storageService.deleteEmail(emailId);
        }
      }
      const filtered: Email[] = [];
      for (const e of this.emails) {
        if (e.id !== emailId) filtered.push(e);
      }
      this.emails = filtered;
      ToastUtil.showSuccess(Utils.resourceToString(this.context, $r('app.string.msg_archived')));
    } catch (error) {
      this.logger.e('Failed to archive: ' + JSON.stringify(error));
      ToastUtil.showError(Utils.resourceToString(this.context, $r('app.string.msg_archive_failed')));
    }
  }

  isEmailSelected(emailId: string): boolean {
    return this.selectedEmailSet.has(emailId);
  }

  getInitial(): string {
    if (!this.currentAccount) return 'U';
    return (this.currentAccount.displayName || this.currentAccount.email).charAt(0).toUpperCase();
  }

  getDisplayEmails(): Email[] {
    if (this.showUnreadOnly) {
      const result: Email[] = [];
      for (const e of this.emails) {
        if (!e.isRead) {
          result.push(e);
        }
      }
      return result;
    }
    return this.emails;
  }

  @Builder
  TopBar() {
    Column() {
      Row() {
        Button() {
          Image($r('app.media.icon_arrow_left')).width(20).height(20)
        }
          .width(48).height(48).backgroundColor('transparent')
          .onClick(() => this.goBack())
        Text(this.folderName)
          .fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(this.theme().textPrimary)
          .layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button() {
          Image($r('app.media.icon_search')).width(20).height(20)
        }
          .width(48).height(48).backgroundColor('transparent')
          .onClick(() => { this.showSearch = !this.showSearch; })
        Button() {
          Text(this.getInitial())
            .fontSize(16).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        }
          .width(36).height(36).borderRadius(18)
          .backgroundColor(this.avatarColor(this.currentAccount?.email || 'U'))
          .onClick(() => { router.pushUrl({ url: 'pages/AccountList' }); })
          .margin({ left: 4 })
      }
      .width('100%').height(56).padding({ left: 4, right: 12 })
      .backgroundColor(this.theme().surface)

      Row({ space: 0 }) {
        Button() {
          Text($r('app.string.label_all'))
            .fontSize(14)
            .fontColor(!this.showUnreadOnly ? this.theme().primary : this.theme().textHint)
            .fontWeight(!this.showUnreadOnly ? FontWeight.Medium : FontWeight.Normal)
        }
        .height(36)
        .backgroundColor('transparent')
        .padding({ left: 16, right: 16 })
        .borderRadius(18)
        .onClick(() => { this.showUnreadOnly = false; })

        Button() {
          Text($r('app.string.label_unread'))
            .fontSize(14)
            .fontColor(this.showUnreadOnly ? this.theme().primary : this.theme().textHint)
            .fontWeight(this.showUnreadOnly ? FontWeight.Medium : FontWeight.Normal)
        }
        .height(36)
        .backgroundColor('transparent')
        .padding({ left: 16, right: 16 })
        .borderRadius(18)
        .onClick(() => { this.showUnreadOnly = true; })

        Blank()

        Button() {
          Text(this.showThreading ? '\u2261' : '\u22EE')
            .fontSize(18)
            .fontColor(this.showThreading ? this.theme().primary : this.theme().textHint)
        }
        .width(36).height(36).backgroundColor('transparent')
        .onClick(() => { this.showThreading = !this.showThreading; })
        .margin({ right: 8 })
      }
      .width('100%').height(40)
      .padding({ left: 8 })
      .backgroundColor(this.theme().surface)
      .border({ width: { bottom: 1 }, color: this.theme().divider })
    }
    .width('100%')
    .backgroundColor(this.theme().surface)
  }

  @Builder
  SearchBar() {
    Row() {
      Button() {
        Image($r('app.media.icon_arrow_left')).width(20).height(20)
      }
        .width(48).height(48).backgroundColor('transparent')
        .onClick(() => { this.showSearch = false; this.searchQuery = ''; })
      TextInput({ placeholder: Utils.resourceToString(this.context, $r('app.string.placeholder_search_in')) + this.folderName + ' ', text: this.searchQuery })
        .fontSize(16).fontColor(this.theme().textPrimary)
        .layoutWeight(1).backgroundColor('transparent')
        .placeholderColor(this.theme().textHint)
        .onChange((value: string) => { this.searchQuery = value; })
        .onSubmit(() => { if (this.searchQuery.trim()) { void this.searchEmails(); } })
    }
    .width('100%').height(56).padding({ left: 4, right: 12 })
    .backgroundColor(this.theme().surface)
  }

  @Builder
  SelectionBar() {
    Row() {
      Button() {
        Image($r('app.media.icon_close')).width(18).height(18)
      }
        .width(48).height(48).backgroundColor('transparent')
        .onClick(() => this.clearSelection())
      Text(this.selectedEmails.length.toString() + Utils.resourceToString(this.context, $r('app.string.unit_items')))
        .fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(this.theme().textPrimary).layoutWeight(1)
      Button($r('app.string.btn_delete'))
        .fontSize(14).fontColor(this.theme().error).backgroundColor('transparent')
        .onClick(() => this.deleteSelectedEmails())
    }
    .width('100%').height(48).padding({ left: 8, right: 8 })
    .backgroundColor(this.theme().surface)
    .border({ width: { bottom: 1 }, color: this.theme().divider })
  }

  @Builder
  SwipeActions(email: Email) {
    Row() {
      if (this.folderType === FolderType.TRASH) {
        Button($r('app.string.btn_restore'))
          .fontSize(14).fontColor('#FFFFFF')
          .width(64).height('100%').backgroundColor('#4285F4').borderRadius(0)
          .onClick(() => { this.restoreEmail(email.id); })
        Button($r('app.string.btn_delete'))
          .fontSize(14).fontColor('#FFFFFF')
          .width(64).height('100%').backgroundColor('#EA4335').borderRadius(0)
          .onClick(() => {
            if (this.storageService) {
              this.storageService.deleteEmail(email.id);
              const filtered: Email[] = [];
              for (const e of this.emails) {
                if (e.id !== email.id) filtered.push(e);
              }
              this.emails = filtered;
            }
          })
      } else {
        Button($r('app.string.btn_archive'))
          .fontSize(14).fontColor('#FFFFFF')
          .width(64).height('100%').backgroundColor('#34A853').borderRadius(0)
          .onClick(() => { this.archiveEmail(email.id); })
        Button($r('app.string.btn_delete'))
          .fontSize(14).fontColor('#FFFFFF')
          .width(64).height('100%').backgroundColor('#EA4335').borderRadius(0)
          .onClick(() => { this.moveToTrash(email.id); })
      }
    }
    .height('100%')
  }

  async moveToTrash(emailId: string): Promise<void> {
    if (!this.storageService) return;
    try {
      const email = this.emails.find(e => e.id === emailId);
      if (email) {
        const folders = await this.storageService.getFoldersByAccountId(email.accountId);
        const trashFolder = folders.find(f => f.type === FolderType.TRASH);
        if (trashFolder) {
          email.folderId = trashFolder.id;
          await this.storageService.saveEmail(email);
        } else {
          await this.storageService.deleteEmail(emailId);
        }
      }
      const filtered: Email[] = [];
      for (const e of this.emails) {
        if (e.id !== emailId) filtered.push(e);
      }
      this.emails = filtered;
    } catch (error) {
      this.logger.e('Failed to move to trash: ' + JSON.stringify(error));
    }
  }

  async restoreEmail(emailId: string): Promise<void> {
    if (!this.storageService) return;
    try {
      const email = this.emails.find(e => e.id === emailId);
      if (email) {
        const folders = await this.storageService.getFoldersByAccountId(email.accountId);
        const inboxFolder = folders.find(f => f.type === FolderType.INBOX);
        if (inboxFolder) {
          email.folderId = inboxFolder.id;
          await this.storageService.saveEmail(email);
        }
      }
      const filtered: Email[] = [];
      for (const e of this.emails) {
        if (e.id !== emailId) filtered.push(e);
      }
      this.emails = filtered;
      ToastUtil.showSuccess(Utils.resourceToString(this.context, $r('app.string.msg_restored')));
    } catch (error) {
      this.logger.e('Failed to restore email: ' + JSON.stringify(error));
      ToastUtil.showError(Utils.resourceToString(this.context, $r('app.string.msg_restore_failed')));
    }
  }

  threadSubjectLine(em: Email): string {
    const s = Utils.coerceUiString(em.subject );
    if (s.length > 0) {
      return s;
    }
    return Utils.resourceToString(this.context, $r('app.string.msg_no_subject'));
  }

  buildThreads(): Email[][] {
    const groups = new Map<string, Email[]>();
    for (const email of this.emails) {
      const key = Utils.normalizeSubject(email.subject);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key)!.push(email);
    }
    const result: Email[][] = [];
    groups.forEach((group: Email[]) => {
      group.sort((a, b) => b.date - a.date);
      result.push(group);
    });
    result.sort((a, b) => b[0].date - a[0].date);
    return result;
  }

  @Builder
  ThreadHeader(thread: Email[], isExpanded: boolean, onToggle: () => void) {
    Row() {
      Text(this.getThreadInitial(thread))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width(36).height(36).borderRadius(18)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.avatarColor(
          Utils.coerceUiString(thread[0].from.name ) ||
          Utils.coerceUiString(thread[0].from.address )))
        .margin({ right: 10 })
      Column() {
        Text(this.threadSubjectLine(thread[0]))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(Utils.resourceToString(this.context, $r('app.string.label_thread_count')).replace('$1', thread.length.toString()))
          .fontSize(12)
          .fontColor(this.theme().textHint)
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)

      Text(isExpanded ? '\u25B2' : '\u25BC')
        .fontSize(12)
        .fontColor(this.theme().textHint)
        .margin({ left: 8 })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.theme().surface)
    .onClick(() => onToggle())
  }

  getThreadInitial(thread: Email[]): string {
    const participants: string[] = [];
    for (const e of thread) {
      const n = Utils.coerceUiString(e.from.name );
      const a = Utils.coerceUiString(e.from.address );
      const name = n.length > 0 ? n : a;
      if (name.length === 0) {
        continue;
      }
      if (participants.indexOf(name) < 0) {
        participants.push(name);
      }
    }
    if (participants.length === 0) {
      return '?';
    }
    if (participants.length > 1) {
      return participants.length.toString();
    }
    return participants[0].charAt(0).toUpperCase();
  }

  build() {
    Column() {
      if (this.showSearch) { this.SearchBar() } else { this.TopBar() }
      if (this.isSelectionMode) { this.SelectionBar() }
      if (this.isSyncing && !this.isRefreshing) {
        Row({ space: 6 }) {
          LoadingProgress().width(14).height(14).color(this.theme().primary)
          Text($r('app.string.msg_syncing')).fontSize(12).fontColor(this.theme().primary)
          Blank()
        }
        .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .backgroundColor(this.theme().infoBackground)
      } else if (this.syncError && !this.isRefreshing) {
        Row() {
          Text(this.syncError).fontSize(12).fontColor(this.theme().textHint)
          Blank()
        }
        .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .backgroundColor(this.theme().warningBackground)
      }
      Stack() {
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(40).height(40).color(this.theme().primary)
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else if (!this.searchQuery && this.getDisplayEmails().length === 0 && !this.isSyncing) {
          Column({ space: 16 }) {
            Image($r('app.media.icon_mail'))
              .width(80).height(80)
              .fillColor(this.theme().textHint)
            Text($r('app.string.no_emails'))
              .fontSize(18).fontColor(this.theme().textSecondary)
              .fontWeight(FontWeight.Medium)
            Text($r('app.string.pull_refresh_hint'))
              .fontSize(14).fontColor(this.theme().textHint).textAlign(TextAlign.Center)
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else if (this.searchQuery && this.getDisplayEmails().length === 0) {
          Column({ space: 16 }) {
            Image($r('app.media.icon_warning'))
              .width(64).height(64)
              .fillColor(this.theme().textHint)
            Text($r('app.string.search_no_result'))
              .fontSize(18).fontColor(this.theme().textSecondary)
              .fontWeight(FontWeight.Medium)
            Text($r('app.string.search_no_result_hint'))
              .fontSize(14).fontColor(this.theme().textHint).textAlign(TextAlign.Center)
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          Refresh({ refreshing: this.isRefreshing }) {
            List() {
              if (this.showThreading) {
                // Threaded view
                ForEach(this.buildThreads(), (thread: Email[], index: number | undefined) => {
                  if (thread.length === 1) {
                    ListItem() {
                      EmailItem({
                        email: thread[0],
                        isSelected: this.isEmailSelected(thread[0].id),
                        isSelectionMode: this.isSelectionMode,
                        onEmailSelect: (id: string): void => { this.toggleEmailSelection(id); },
                        onEmailClick: (e: Email): void => { this.navigateToEmailDetail(e); },
                        onEmailStarToggle: (id: string, starred: boolean): void => { this.toggleStar(id, starred); }
                      })
                    }
                    .swipeAction({ end: (): void => { this.SwipeActions(thread[0]); } })
                  } else {
                    // Thread header
                    ListItem() {
                      this.ThreadHeader(thread,
                        this.expandedThreads.has(Utils.normalizeSubject(thread[0].subject)),
                        () => {
                          const key = Utils.normalizeSubject(thread[0].subject);
                          if (this.expandedThreads.has(key)) {
                            const s = new Set<string>(this.expandedThreads);
                            s.delete(key);
                            this.expandedThreads = s;
                          } else {
                            const s = new Set<string>(this.expandedThreads);
                            s.add(key);
                            this.expandedThreads = s;
                          }
                        })
                    }
                    // Expanded thread emails
                    if (this.expandedThreads.has(Utils.normalizeSubject(thread[0].subject))) {
                      ForEach(thread, (subEmail: Email) => {
                        ListItem() {
                          EmailItem({
                            email: subEmail,
                            isSelected: this.isEmailSelected(subEmail.id),
                            isSelectionMode: this.isSelectionMode,
                            onEmailSelect: (id: string): void => { this.toggleEmailSelection(id); },
                            onEmailClick: (e: Email): void => { this.navigateToEmailDetail(e); },
                            onEmailStarToggle: (id: string, starred: boolean): void => { this.toggleStar(id, starred); }
                          })
                        }
                        .swipeAction({ end: (): void => { this.SwipeActions(subEmail); } })
                        .padding({ left: 24 })
                      }, (subEmail: Email) => subEmail.id)
                    }
                  }
                }, (thread: Email[], idx: number | undefined) => 'thread_' + (idx ?? 0))
              } else {
                // Flat view
                ForEach(this.getDisplayEmails(), (email: Email) => {
                  ListItem() {
                    EmailItem({
                      email: email,
                      isSelected: this.isEmailSelected(email.id),
                      isSelectionMode: this.isSelectionMode,
                      onEmailSelect: (id: string): void => { this.toggleEmailSelection(id); },
                      onEmailClick: (e: Email): void => { this.navigateToEmailDetail(e); },
                      onEmailStarToggle: (id: string, starred: boolean): void => { this.toggleStar(id, starred); }
                    })
                  }
                  .swipeAction({ end: (): void => { this.SwipeActions(email); } })
                }, (email: Email) => email.id)
              }
              if (this.hasMore) {
                ListItem() {
                  Row() {
                    LoadingProgress().width(20).height(20).color(this.theme().primary)
                    Text($r('app.string.load_more')).fontSize(14).fontColor(this.theme().primary).margin({ left: 8 })
                  }
                  .width('100%').height(52).justifyContent(FlexAlign.Center)
                  .backgroundColor(this.theme().surface)
                  .onClick(() => { void this.loadMoreEmails(); })
                }
              }
            }
            .width('100%').height('100%').divider({ strokeWidth: 0 })
          }
          .onRefreshing(() => {
            this.isRefreshing = true;
            void this.refreshEmails().finally(() => {
              this.isRefreshing = false;
            });
          })
        }
        Button() {
          Text('+').fontSize(28).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        }
        .width(56).height(56).borderRadius(28)
        .backgroundColor(this.theme().primary)
        .shadow({ radius: 6, color: '#1a73e844', offsetY: 3 })
        .position({ bottom: 24, right: 24 })
        .onClick(() => this.navigateToCompose())
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(this.theme().background)
  }
}

