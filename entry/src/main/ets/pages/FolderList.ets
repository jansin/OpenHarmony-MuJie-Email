import { router } from '@kit.ArkUI';
import { Folder, FolderType } from '../models/Folder';
import { Account, AccountProtocol } from '../models/Account';
import { StorageService } from '../services/StorageService';
import { AccountService } from '../services/AccountService';
import { EmailService } from '../services/EmailService';
import { common } from '@kit.AbilityKit';
import { EmailTheme, DARK_THEME, LIGHT_THEME } from '../common/Theme';
import { Utils } from '../common/Utils';
import { LogUtil } from '../common/LogUtil';

@Entry
@Component
struct FolderList {
  private context = getContext(this) as common.UIAbilityContext;
  @State folders: Folder[] = [];
  @State currentAccount: Account | null = null;
  @State isLoading: boolean = true;
  @State themeVersion: number = 0;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;

  private storageService: StorageService | null = null;
  private accountService: AccountService | null = null;
  private emailService: EmailService | null = null;
  private folderSyncGen: number = 0;
  private logger: LogUtil = new LogUtil('FolderList');
  private theme(): EmailTheme {
    return this.isDarkMode ? DARK_THEME : LIGHT_THEME;
  }



  aboutToAppear(): void {
    this.initializeServices();
  }

  onThemeChange = (isDark: boolean): void => {
    this.themeVersion++;
  }

  onPageShow(): void {
    this.themeVersion++;
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
      await this.loadCurrentAccount();
      await this.loadFolders();
    } catch (error) {
      this.logger.e('Failed to initialize: ' + JSON.stringify(error));
    } finally {
      this.isLoading = false;
    }
  }

  async loadCurrentAccount(): Promise<void> {
    if (!this.accountService) return;
    try {
      this.currentAccount = await this.accountService.getDefaultAccount();
      if (!this.currentAccount) {
        router.replaceUrl({ url: 'pages/AccountList' });
      }
    } catch (error) {
      this.logger.e('Failed to load account: ' + JSON.stringify(error));
    }
  }

  async loadFolders(): Promise<void> {
    if (!this.storageService || !this.currentAccount) return;
    try {
      this.folders = await this.storageService.getFoldersByAccountId(this.currentAccount.id);
      if (this.folders.length === 0) {
        await this.createDefaultFolders();
      } else if (this.currentAccount.protocol === AccountProtocol.IMAP && this.emailService) {
        this.scheduleImapFolderRefresh(this.currentAccount);
      }
    } catch (error) {
      this.logger.e('Failed to load folders: ' + JSON.stringify(error));
    }
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
        const list = await emailService.fetchFolders(account);
        if (gen !== this.folderSyncGen || !this.currentAccount || this.currentAccount.id !== expectId) {
          return;
        }
        this.folders = list;
      } catch (e) {
        this.logger.e('Background IMAP folder refresh failed: ' + JSON.stringify(e));
      }
    }, 300);
  }

  async createDefaultFolders(): Promise<void> {
    if (!this.storageService || !this.currentAccount) return;
    const types: FolderType[] = [FolderType.INBOX, FolderType.SENT, FolderType.DRAFTS, FolderType.TRASH, FolderType.SPAM, FolderType.ARCHIVE];
    const names: string[] = [Utils.resourceToString(this.context, $r('app.string.folder_inbox')), Utils.resourceToString(this.context, $r('app.string.folder_sent')), Utils.resourceToString(this.context, $r('app.string.folder_drafts')), Utils.resourceToString(this.context, $r('app.string.folder_trash')), Utils.resourceToString(this.context, $r('app.string.folder_spam')), Utils.resourceToString(this.context, $r('app.string.folder_archive'))];
    const icons: string[] = [Utils.resourceToString(this.context, $r('app.string.icon_arrow_down')), Utils.resourceToString(this.context, $r('app.string.icon_arrow_up')), Utils.resourceToString(this.context, $r('app.string.icon_edit')), Utils.resourceToString(this.context, $r('app.string.icon_delete')), Utils.resourceToString(this.context, $r('app.string.icon_warning')), Utils.resourceToString(this.context, $r('app.string.icon_circle'))];

    for (let i = 0; i < types.length; i++) {
      const ft = types[i];
      const folder: Folder = {
        id: this.currentAccount.id + '_' + names[i],
        accountId: this.currentAccount.id,
        name: names[i],
        fullName: names[i],
        type: ft,
        icon: icons[i],
        totalCount: 0,
        unreadCount: 0,
        isSynced: false,
        selectable: true,
        createdAt: Date.now(),
        updatedAt: Date.now()
      };
      await this.storageService.saveFolder(folder);
    }
    await this.loadFolders();
  }

  getFolderIcon(type: FolderType): string {
    if (type === FolderType.INBOX) return Utils.resourceToString(this.context, $r('app.string.label_inbox_short'));
    if (type === FolderType.SENT) return Utils.resourceToString(this.context, $r('app.string.label_sent_short'));
    if (type === FolderType.DRAFTS) return Utils.resourceToString(this.context, $r('app.string.label_drafts_short'));
    if (type === FolderType.TRASH) return Utils.resourceToString(this.context, $r('app.string.label_trash_short'));
    if (type === FolderType.SPAM) return Utils.resourceToString(this.context, $r('app.string.label_spam_short'));
    if (type === FolderType.ARCHIVE) return Utils.resourceToString(this.context, $r('app.string.label_archive_short'));
    return '+';
  }

  navigateToEmailList(folder: Folder): void {
    router.pushUrl({ url: 'pages/EmailList', params: { folderId: folder.id, folderName: folder.name, folderType: folder.type } });
  }

  navigateToAccountList(): void {
    router.pushUrl({ url: 'pages/AccountList' });
  }

  navigateToCompose(): void {
    router.pushUrl({ url: 'pages/ComposeEmail' });
  }

  build() {
    Column() {
      Row() {
        Button() {
          Image($r('app.media.icon_menu')).width(20).height(20)
        }
          .backgroundColor('transparent')
          .onClick(() => this.navigateToAccountList())

        Text(this.currentAccount?.displayName || this.currentAccount?.email || Utils.resourceToString(this.context, $r('app.string.label_email')))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Blank()
      }
      .width('100%')
      .height(56)
      .padding({ left: 4, right: 16 })
      .backgroundColor(this.theme().surface)

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.theme().primary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.folders.length === 0) {
        Column({ space: 12 }) {
          Text($r('app.string.no_emails')).fontSize(16).fontColor(this.theme().textSecondary)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.folders, (folder: Folder) => {
            ListItem() {
              Row() {
                Text(this.getFolderIcon(folder.type) + '  ')
                  .fontSize(16).fontColor(this.theme().link).fontWeight(FontWeight.Bold)

                Text(folder.name)
                  .fontSize(16)
                  .fontColor(this.theme().textPrimary)
                  .layoutWeight(1)
                  .margin({ left: 12 })

                if (folder.unreadCount > 0) {
                  Text(folder.unreadCount.toString())
                    .fontSize(12)
                    .fontColor(this.theme().onPrimary)
                    .backgroundColor(this.theme().primary)
                    .width(22)
                    .height(22)
                    .borderRadius(11)
                    .textAlign(TextAlign.Center)
                }

                Image($r('app.media.icon_arrow_right'))
                  .width(22).height(22)
                  .margin({ left: 8 })
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.theme().surface)
              .onClick(() => this.navigateToEmailList(folder))
            }
          }, (folder: Folder) => folder.id)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(this.theme().surface)
      }

      Stack() {
        Button() {
          Text('+')
            .fontSize(28)
            .fontColor(this.theme().onPrimary)
            .fontWeight(FontWeight.Bold)
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor(this.theme().primary)
        .shadow({ radius: 6, color: this.theme().primary + '44', offsetY: 3 })
        .position({ bottom: 16, right: 16 })
        .onClick(() => this.navigateToCompose())
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().background)
  }
}
