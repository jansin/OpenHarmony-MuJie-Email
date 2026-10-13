import { router, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { Account, AccountProtocol } from '../models/Account';
import { Folder, FolderType } from '../models/Folder';
import { AccountService } from '../services/AccountService';
import { EmailService } from '../services/EmailService';
import { StorageService } from '../services/StorageService';
import { common } from '@kit.AbilityKit';
import { EmailTheme, DARK_THEME, LIGHT_THEME, setEmailDarkMode } from '../common/Theme';
import { Utils } from '../common/Utils';
import { useServices } from '../common/ServiceLocator';
import { LogUtil } from '../common/LogUtil';

enum TabIndex {
  INBOX = 0,
  FOLDERS = 1,
  PROFILE = 2
}

@Entry
@Component
struct MainLayout {
  private context = getContext(this) as common.UIAbilityContext;
  private logger: LogUtil = new LogUtil('MainLayout');
  @State currentAccount: Account | null = null;
  @State accounts: Account[] = [];
  @State folders: Folder[] = [];
  @State searchQuery: string = '';
  @State showSearch: boolean = false;
  @State themeVersion: number = 0;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @State isLoading: boolean = true;
  @State loadError: string = '';
  @State activeTab: TabIndex = TabIndex.INBOX;

  private storageService: StorageService | null = null;
  private accountService: AccountService | null = null;
  private emailService: EmailService | null = null;
  private folderSyncGen: number = 0;
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
    this.loadThemePreference();
    this.initializeServices();
    this.updateStatusBarStyle();
  }

  onThemeChange = (isDark: boolean): void => {
    this.isDarkMode = isDark;
    this.themeVersion++;
    this.updateStatusBarStyle();
  }

  onPageHide(): void {
  }

  onPageShow(): void {
    this.themeVersion++;
    this.updateStatusBarStyle();
    if (!this.storageService) {
      this.initializeServices();
    } else {
      this.refreshData();
    }
  }

  private async loadThemePreference(): Promise<void> {
    try {
      const prefStore = await preferences.getPreferences(this.context, 'AppSettings');
      const darkVal = await prefStore.get('isDarkMode', this.isDarkMode);
      const isDark = darkVal as boolean;
      setEmailDarkMode(isDark);
      this.isDarkMode = isDark;
      this.themeVersion++;
      this.updateStatusBarStyle();
    } catch (error) {
      this.logger.w('Failed to load theme preference:', error);
    }
  }

  private updateStatusBarStyle(): void {
    try {
      const mainWindow = window.findWindow('main');
      mainWindow.setWindowSystemBarProperties({
        statusBarContentColor: this.isDarkMode ? '#F5F5F5' : '#1C1C1E'
      });
    } catch (error) {
      this.logger.w('Failed to update status bar style:', error);
    }
  }

  async refreshData(): Promise<void> {
    if (!this.accountService) return;
    try {
      this.currentAccount = await this.accountService.getDefaultAccount();
      this.accounts = await this.accountService.getAllAccounts();
      if (this.currentAccount && this.storageService) {
        this.folders = await this.deduplicateFolders(await this.storageService.getFoldersByAccountId(this.currentAccount.id));
        if (this.folders.length === 0) {
          await this.createDefaultFolders();
        }
      }
      this.loadError = '';
    } catch (error) {
      this.logger.e('Failed to refresh data:', error);
    }
  }

  private deduplicateFolders(list: Folder[]): Folder[] {
    const seenId = new Set<string>();
    const result: Folder[] = [];
    for (const f of list) {
      if (!seenId.has(f.id)) {
        seenId.add(f.id);
        result.push(f);
      }
    }
    return result;
  }

  async initializeServices(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const services = await useServices(context);
      this.storageService = services.storageService;
      this.accountService = services.accountService;
      this.emailService = services.emailService;
      await this.loadData();
    } catch (error) {
      this.logger.e('Failed to initialize:', error);
      this.loadError = Utils.resourceToString(this.context, $r('app.string.msg_sync_failed'));
      this.isLoading = false;
    }
  }

  async loadData(): Promise<void> {
    if (!this.accountService) return;
    this.currentAccount = await this.accountService.getDefaultAccount();
    this.accounts = await this.accountService.getAllAccounts();
    if (this.currentAccount && this.storageService) {
      this.folders = this.deduplicateFolders(await this.storageService.getFoldersByAccountId(this.currentAccount.id));
      if (this.folders.length === 0) {
        await this.createDefaultFolders();
      }
      if (this.currentAccount.protocol === AccountProtocol.IMAP && this.emailService) {
        this.scheduleImapFolderRefresh(this.currentAccount);
      }
    }
    this.isLoading = false;
  }

  private scheduleImapFolderRefresh(account: Account): void {
    if (account.protocol !== AccountProtocol.IMAP || !this.emailService) {
      return;
    }
    const emailService = this.emailService;
    const expectId = account.id;
    const gen = ++this.folderSyncGen;
    setTimeout(async () => {
      if (gen !== this.folderSyncGen || !this.currentAccount || this.currentAccount.id !== expectId) {
        return;
      }
      try {
        const sdkFolders = await emailService.fetchFolders(account);
        if (gen !== this.folderSyncGen || !this.currentAccount || this.currentAccount.id !== expectId) {
          return;
        }
        const localFolders = await this.storageService?.getFoldersByAccountId(account.id) || [];
        const typeMap = new Map<FolderType, Folder>();
        for (const lf of localFolders) {
          typeMap.set(lf.type, lf);
        }
        for (const sf of sdkFolders) {
          if (typeMap.has(sf.type)) {
            const existing = typeMap.get(sf.type)!;
            existing.unreadCount = sf.unreadCount;
            if (existing.id !== sf.id) {
              existing.id = sf.id;
              existing.fullName = sf.fullName;
              if (this.storageService) {
                this.storageService.saveFolder(existing);
              }
            }
          } else {
            localFolders.push(sf);
          }
        }
        this.folders = this.deduplicateFolders(localFolders);
      } catch (e) {
        this.logger.e('Background IMAP folder refresh failed:', e);
      }
    }, 300);
  }

  async createDefaultFolders(): Promise<void> {
    if (!this.storageService || !this.currentAccount) return;
    const types: FolderType[] = [FolderType.INBOX, FolderType.SENT, FolderType.DRAFTS, FolderType.TRASH, FolderType.SPAM, FolderType.ARCHIVE];
    const names: string[] = [Utils.resourceToString(this.context, $r('app.string.folder_inbox')), Utils.resourceToString(this.context, $r('app.string.folder_sent')), Utils.resourceToString(this.context, $r('app.string.folder_drafts')), Utils.resourceToString(this.context, $r('app.string.folder_trash')), Utils.resourceToString(this.context, $r('app.string.folder_spam')), Utils.resourceToString(this.context, $r('app.string.folder_archive'))];
    const fullNames: string[] = ['INBOX', 'Sent', 'Drafts', 'Trash', 'Spam', 'Archive'];

    for (let i = 0; i < types.length; i++) {
      const folder: Folder = {
        id: this.currentAccount.id + '_' + fullNames[i],
        accountId: this.currentAccount.id,
        name: names[i],
        fullName: fullNames[i],
        type: types[i],
        icon: '',
        totalCount: 0,
        unreadCount: 0,
        isSynced: false,
        selectable: true,
        createdAt: Date.now(),
        updatedAt: Date.now()
      };
      await this.storageService.saveFolder(folder);
    }
    this.folders = this.deduplicateFolders(await this.storageService.getFoldersByAccountId(this.currentAccount.id));
  }

  async switchAccount(account: Account): Promise<void> {
    if (this.accountService) {
      this.folderSyncGen++;
      await this.accountService.setDefaultAccount(account.id);
      this.currentAccount = account;
      if (this.storageService) {
        this.folders = this.deduplicateFolders(await this.storageService.getFoldersByAccountId(account.id));
        if (this.folders.length === 0) {
          await this.createDefaultFolders();
        }
        if (account.protocol === AccountProtocol.IMAP && this.emailService) {
          this.scheduleImapFolderRefresh(account);
        }
      }
    }
  }

  navigateToFolder(folder: Folder): void {
    router.pushUrl({ url: 'pages/EmailList', params: { folderId: folder.id, folderName: folder.name, folderType: folder.type } });
  }

  navigateToInbox(): void {
    const list = this.folders;
    const inbox = list ? list.find(f => f.type === FolderType.INBOX) : undefined;
    if (inbox) {
      this.navigateToFolder(inbox);
    } else if (this.currentAccount) {
      router.pushUrl({ url: 'pages/EmailList', params: { folderId: this.currentAccount.id + '_INBOX', folderName: Utils.resourceToString(this.context, $r('app.string.folder_inbox')), folderType: FolderType.INBOX } });
    } else {
      router.pushUrl({ url: 'pages/AccountList' });
    }
  }

  navigateToCompose(): void {
    if (!this.currentAccount) {
      router.pushUrl({ url: 'pages/AccountList' });
      return;
    }
    router.pushUrl({ url: 'pages/ComposeEmail' });
  }

  navigateToAccounts(): void {
    router.pushUrl({ url: 'pages/AccountList' });
  }

  navigateToSettings(): void {
    router.pushUrl({ url: 'pages/Settings' });
  }

  navigateToFilterRules(): void {
    router.pushUrl({ url: 'pages/FilterRules' });
  }

  doSearch(): void {
    if (this.searchQuery.trim()) {
      router.pushUrl({ url: 'pages/EmailList', params: { searchQuery: this.searchQuery.trim(), folderName: Utils.resourceToString(this.context, $r('app.string.label_search_prefix')) + this.searchQuery.trim() } });
      this.searchQuery = '';
      this.showSearch = false;
    }
  }

  getInitial(name: string): string {
    if (!name || name.length === 0) return '?';
    return name.charAt(0).toUpperCase();
  }

  get inboxUnread(): number {
    let count = 0;
    const list = this.folders;
    if (list) {
      for (const f of list) {
        if (f.type === FolderType.INBOX) {
          count = (f.unreadCount ?? 0);
        }
      }
    }
    return count;
  }

  get totalUnread(): number {
    let count = 0;
    const list = this.folders;
    if (list) {
      for (const f of list) {
        count += (f.unreadCount ?? 0);
      }
    }
    return count;
  }

  build() {
    Column() {
      if (this.showSearch) {
        this.SearchBar()
      } else {
        this.TopBar()
      }

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme().primary)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.loadError) {
        this.buildErrorView()
      } else if (!this.currentAccount || this.accounts.length === 0) {
        this.buildWelcomeView()
      } else if (this.activeTab === TabIndex.INBOX) {
        this.buildInboxTab()
      } else if (this.activeTab === TabIndex.FOLDERS) {
        this.buildFoldersTab()
      } else if (this.activeTab === TabIndex.PROFILE) {
        this.buildProfileTab()
      }

      this.buildTabBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().background)
  }

  @Builder
  buildErrorView(): void {
    Column({ space: 12 }) {
      Image($r('app.media.icon_warning'))
        .width(56).height(56)
        .fillColor(this.theme().error)

      Text(this.loadError)
        .fontSize(14)
        .fontColor(this.theme().error)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })

      Button($r('app.string.btn_refresh'))
        .fontSize(14)
        .backgroundColor(this.theme().primary)
        .fontColor(this.theme().onPrimary)
        .height(40)
        .width(160)
        .borderRadius(20)
        .onClick(() => {
          this.loadError = '';
          this.isLoading = true;
          this.initializeServices();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildWelcomeView(): void {
    Column({ space: 16 }) {
      Image($r('app.media.icon_mail'))
        .width(72).height(72)
        .fillColor(this.theme().textHint)

      Text($r('app.string.title_welcome'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().textPrimary)

      Text($r('app.string.hint_add_account'))
        .fontSize(14)
        .fontColor(this.theme().textSecondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })

      Button($r('app.string.btn_add_account'))
        .fontSize(16)
        .backgroundColor(this.theme().primary)
        .fontColor(this.theme().onPrimary)
        .height(48)
        .width(200)
        .borderRadius(24)
        .onClick(() => { router.pushUrl({ url: 'pages/AccountList' }); })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildInboxTab(): void {
    Column() {
      Scroll() {
        Column({ space: 0 }) {
          this.buildInboxHeaderCard()

          if (this.folders && this.folders.length > 1) {
            Column({ space: 0 }) {
              Row() {
                Text($r('app.string.label_folders'))
                  .fontSize(14)
                  .fontColor(this.theme().textSecondary)
                  .fontWeight(FontWeight.Medium)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 20, bottom: 4 })

              ForEach(this.folders, (folder: Folder) => {
                this.buildFolderRow(folder)
              }, (folder: Folder) => folder.id)

              if (this.accounts.length > 1) {
                this.buildUnifiedRow()
              }
            }
            .width('100%')
            .backgroundColor(this.theme().surface)
            .borderRadius(12)
            .margin({ left: 16, right: 16, top: 12 })
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({ bottom: 72 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor(this.theme().background)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildInboxHeaderCard(): void {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text(Utils.resourceToString(this.context, $r('app.string.folder_inbox')))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().textPrimary)

          if (this.inboxUnread > 0) {
            Text(this.inboxUnread.toString())
              .fontSize(13)
              .fontColor(this.theme().textHint)
          }
        }

        Blank()

        if ((this.inboxUnread ?? 0) > 0) {
          Text((this.inboxUnread ?? 0).toString())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().primary)
        }

        Image($r('app.media.icon_arrow_right'))
          .width(18).height(18)
          .fillColor(this.theme().textHint)
          .margin({ left: 6 })
      }
      .width('100%')
      .padding(16)

      Row() {
        Button($r('app.string.btn_compose'))
          .fontSize(14)
          .fontColor(this.theme().onPrimary)
          .backgroundColor(this.theme().primary)
          .height(36)
          .borderRadius(18)
          .onClick(() => this.navigateToCompose())

        Blank()

        Button($r('app.string.btn_add_account'))
          .fontSize(14)
          .fontColor(this.theme().primary)
          .backgroundColor('transparent')
          .height(36)
          .borderRadius(18)
          .onClick(() => { router.pushUrl({ url: 'pages/AccountList' }); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
    .backgroundColor(this.theme().surface)
    .borderRadius(12)
    .margin({ left: 16, right: 16, top: 16 })
    .onClick(() => this.navigateToInbox())
  }

  @Builder
  buildFolderRow(folder: Folder): void {
    Row() {
      Image(this.getFolderIcon(folder.type))
        .width(22).height(22)
        .fillColor(this.theme().primary)

      Text(folder.name)
        .fontSize(15)
        .fontColor(this.theme().textPrimary)
        .layoutWeight(1)
        .margin({ left: 12 })

      if (folder.unreadCount > 0) {
        Text(folder.unreadCount.toString())
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor(this.theme().primary)
          .width(22).height(22).borderRadius(11)
          .textAlign(TextAlign.Center)
      }

      Image($r('app.media.icon_arrow_right'))
        .width(14).height(14)
        .fillColor(this.theme().textHint)
        .margin({ left: 4 })
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .onClick(() => this.navigateToFolder(folder))
  }

  @Builder
  buildUnifiedRow(): void {
    Row() {
      Text('@')
        .fontSize(18)
        .fontColor(this.theme().primary)
        .fontWeight(FontWeight.Bold)

      Text($r('app.string.label_unified_inbox'))
        .fontSize(15)
        .fontColor(this.theme().textPrimary)
        .layoutWeight(1)
        .margin({ left: 12 })

      Image($r('app.media.icon_arrow_right'))
        .width(14).height(14)
        .fillColor(this.theme().textHint)
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .onClick(() => {
      router.pushUrl({ url: 'pages/EmailList', params: {
        folderId: '__unified__',
        folderName: Utils.resourceToString(this.context, $r('app.string.label_unified_inbox')),
        folderType: 'CUSTOM'
      }});
    })
  }

  @Builder
  buildFoldersTab(): void {
    Column() {
      Column() {
        Row() {
          Text($r('app.string.label_folders'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme().textPrimary)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      }
      .backgroundColor(this.theme().surface)

      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.folders, (folder: Folder) => {
            this.buildFolderRow(folder)
          }, (folder: Folder) => folder.id)

          if (this.accounts.length > 1) {
            this.buildUnifiedRow()
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().surface)
  }

  @Builder
  buildProfileTab(): void {
    Column() {
      Scroll() {
        Column({ space: 0 }) {
          if (this.currentAccount) {
            Row() {
              Text(this.getInitial(this.currentAccount.displayName || this.currentAccount.email))
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .width(56).height(56).borderRadius(28)
                .backgroundColor(this.avatarColor(this.currentAccount.email))
                .textAlign(TextAlign.Center)

              Column({ space: 4 }) {
                Text(this.currentAccount.displayName || this.currentAccount.email)
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme().textPrimary)

                Text(this.currentAccount.email)
                  .fontSize(14)
                  .fontColor(this.theme().textHint)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 12 })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.theme().surface)
          }

          if (this.accounts.length > 1) {
            Column({ space: 0 }) {
              Text($r('app.string.label_account_switch'))
                .fontSize(12)
                .fontColor(this.theme().textHint)
                .width('100%')
                .padding({ left: 16, top: 20, bottom: 4 })

              Column() {
                ForEach(this.accounts, (account: Account) => {
                  Row() {
                    Text(this.getInitial(account.displayName || account.email))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#FFFFFF')
                      .width(36).height(36).borderRadius(18)
                      .backgroundColor(this.avatarColor(account.email))
                      .textAlign(TextAlign.Center)

                    Column({ space: 2 }) {
                      Text(account.displayName || account.email)
                        .fontSize(14)
                        .fontColor(account.id === this.currentAccount?.id ? this.theme().primary : this.theme().textPrimary)
                        .fontWeight(account.id === this.currentAccount?.id ? FontWeight.Bold : FontWeight.Normal)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(account.email)
                        .fontSize(11)
                        .fontColor(this.theme().textHint)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .layoutWeight(1)
                    .margin({ left: 10 })

                    if (account.id === this.currentAccount?.id) {
                      Image($r('app.media.icon_check'))
                        .width(16).height(16)
                    }
                  }
                  .width('100%').height(48).padding({ left: 16, right: 16 })
                  .backgroundColor(account.id === this.currentAccount?.id ? this.theme().selectedItem : 'transparent')
                  .onClick(() => this.switchAccount(account))
                }, (account: Account) => account.id)
              }
              .backgroundColor(this.theme().surface)
              .borderRadius(12)
              .margin({ left: 16, right: 16 })
            }
            .width('100%')
          }

          Column({ space: 0 }) {
            Text($r('app.string.label_settings'))
              .fontSize(12)
              .fontColor(this.theme().textHint)
              .width('100%')
              .padding({ left: 16, top: 20, bottom: 4 })

            Column() {
              this.buildProfileRow($r('app.media.icon_settings'), $r('app.string.label_settings'), () => this.navigateToSettings())
              this.buildProfileRow($r('app.media.icon_circle'), $r('app.string.label_manage_accounts'), () => this.navigateToAccounts())
              this.buildProfileRow($r('app.media.icon_edit'), $r('app.string.btn_filter_rules'), () => this.navigateToFilterRules())
            }
            .backgroundColor(this.theme().surface)
            .borderRadius(12)
            .margin({ left: 16, right: 16 })
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({ bottom: 72 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().background)
  }

  @Builder
  buildProfileRow(icon: Resource, label: Resource, onClick: () => void): void {
    Row() {
      Image(icon).width(22).height(22).fillColor(this.theme().primary)
      Text(label)
        .fontSize(16)
        .fontColor(this.theme().textPrimary)
        .layoutWeight(1)
        .margin({ left: 12 })
      Image($r('app.media.icon_arrow_right'))
        .width(14).height(14)
        .fillColor(this.theme().textHint)
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(onClick)
  }

  @Builder
  buildTabBar(): void {
    Row() {
      this.buildTabItem(TabIndex.INBOX, $r('app.media.tab_inbox'), $r('app.media.tab_inbox_active'), $r('app.string.folder_inbox'))
      this.buildTabItem(TabIndex.FOLDERS, $r('app.media.tab_folder'), $r('app.media.tab_folder_active'), $r('app.string.label_folders'))
      this.buildTabItem(TabIndex.PROFILE, $r('app.media.icon_circle'), $r('app.media.icon_circle'), $r('app.string.label_me'))
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.theme().surface)
    .border({ width: { top: 1 }, color: this.theme().divider })
  }

  @Builder
  buildTabItem(index: TabIndex, icon: Resource, activeIcon: Resource, label: Resource): void {
    Column({ space: 2 }) {
      Image(index === this.activeTab ? activeIcon : icon)
        .width(24).height(24)
        .fillColor(index === this.activeTab ? this.theme().primary : this.theme().textHint)

      Text(label)
        .fontSize(10)
        .fontColor(index === this.activeTab ? this.theme().primary : this.theme().textHint)
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => { this.activeTab = index; })
  }

  getFolderIcon(type: FolderType): Resource {
    if (type === FolderType.INBOX) return $r('app.media.tab_inbox');
    if (type === FolderType.SENT) return $r('app.media.ic_forward');
    if (type === FolderType.DRAFTS) return $r('app.media.icon_edit');
    if (type === FolderType.TRASH) return $r('app.media.icon_delete');
    if (type === FolderType.SPAM) return $r('app.media.icon_warning');
    if (type === FolderType.ARCHIVE) return $r('app.media.ic_save');
    return $r('app.media.icon_circle');
  }

  @Builder
  TopBar() {
    Row() {
      Text($r('app.string.app_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().textPrimary)
        .layoutWeight(1)

      Button() {
        Image($r('app.media.icon_settings')).width(20).height(20)
          .fillColor(this.theme().textPrimary)
      }
        .width(40).height(40).backgroundColor('transparent')
        .onClick(() => { this.navigateToSettings(); })

      Button() {
        Text(this.getInitial(this.currentAccount?.displayName || this.currentAccount?.email || 'U'))
          .fontSize(16).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
      }
        .width(36).height(36).borderRadius(18)
        .backgroundColor(this.avatarColor(this.currentAccount?.email || 'U'))
        .onClick(() => { router.pushUrl({ url: 'pages/AccountList' }); })
        .margin({ left: 2 })
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 12 })
    .backgroundColor(this.theme().surface)
    .border({ width: { bottom: 1 }, color: this.theme().divider })
  }

  @Builder
  SearchBar() {
    Row() {
      Button() {
        Image($r('app.media.icon_arrow_left')).width(20).height(20)
      }
        .width(48).height(48).backgroundColor('transparent')
        .onClick(() => { this.showSearch = false; this.searchQuery = ''; })

      TextInput({ placeholder: Utils.resourceToString(this.context, $r('app.string.placeholder_search')), text: this.searchQuery })
        .fontSize(16).fontColor(this.theme().textPrimary)
        .layoutWeight(1).backgroundColor('transparent')
        .placeholderColor(this.theme().textHint)
        .onChange((value: string) => { this.searchQuery = value; })
        .onSubmit(() => { this.doSearch(); })

      Button() {
        Image($r('app.media.icon_search')).width(20).height(20)
      }
        .width(48).height(48).backgroundColor('transparent')
        .onClick(() => this.doSearch())
    }
    .width('100%').height(56).padding({ left: 4, right: 4 })
    .backgroundColor(this.theme().surface)
    .border({ width: { bottom: 1 }, color: this.theme().divider })
  }
}
