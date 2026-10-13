import { router } from '@kit.ArkUI';
import { Account } from '../models/Account';
import { AccountService } from '../services/AccountService';
import { StorageService } from '../services/StorageService';
import { common } from '@kit.AbilityKit';
import { EmailTheme, DARK_THEME, LIGHT_THEME } from '../common/Theme';
import { Utils } from '../common/Utils';
import { useBasicServices } from '../common/ServiceLocator';
import { LogUtil } from '../common/LogUtil';
import { ToastUtil } from '../common/ToastUtil';

@Entry
@Component
struct AccountList {
  private context = getContext(this) as common.UIAbilityContext;
  private logger: LogUtil = new LogUtil('AccountList');
  @State accounts: Account[] = [];
  @State isLoading: boolean = true;
  @State themeVersion: number = 0;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;

  private accountService: AccountService | null = null;
  private storageService: StorageService | null = null;
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
    if (this.accountService) {
      this.loadAccounts();
    }
  }

  onPageHide(): void {
  }

  async initializeServices(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const services = await useBasicServices(context);
      this.storageService = services.storageService;
      this.accountService = services.accountService;
      await this.loadAccounts();
    } catch (error) {
      this.logger.e('Failed to initialize services:', error);
    } finally {
      this.isLoading = false;
    }
  }

  async loadAccounts(): Promise<void> {
    if (!this.accountService) return;
    try {
      this.accounts = await this.accountService.getAllAccounts();
    } catch (error) {
      this.logger.e('Failed to load accounts:', error);
    }
  }

  navigateToAddAccount(): void {
    router.pushUrl({ url: 'pages/AccountConfig' });
  }

  navigateToEditAccount(account: Account): void {
    router.pushUrl({ url: 'pages/AccountConfig', params: { accountId: account.id } });
  }

  async deleteAccount(account: Account): Promise<void> {
    if (!this.accountService) return;
    AlertDialog.show({
      title: Utils.resourceToString(this.context, $r('app.string.msg_confirm_delete_title')),
      message: Utils.resourceToString(this.context, $r('app.string.msg_confirm_delete_account')).replace('$1', account.displayName || account.email),
      autoCancel: true,
      primaryButton: {
        value: Utils.resourceToString(this.context, $r('app.string.btn_cancel')),
        action: () => {}
      },
      secondaryButton: {
        value: Utils.resourceToString(this.context, $r('app.string.btn_delete')),
        fontColor: '#D93025',
        action: async () => {
          try {
            await this.accountService!.deleteAccount(account.id);
            await this.loadAccounts();
            ToastUtil.showSuccess(Utils.resourceToString(this.context, $r('app.string.msg_account_deleted')) || '账户已删除');
          } catch (error) {
            this.logger.e('Failed to delete account:', error);
            ToastUtil.showError(Utils.resourceToString(this.context, $r('app.string.msg_delete_failed')) || '删除失败');
          }
        }
      }
    });
  }

  async setAsDefault(account: Account): Promise<void> {
    if (!this.accountService) return;
    try {
      await this.accountService.setDefaultAccount(account.id);
      await this.loadAccounts();
    } catch (error) {
      this.logger.e('Failed to set default account:', error);
    }
  }

  goBack(): void {
    router.back();
  }

  getAvatarChar(account: Account): string {
    return account.displayName.charAt(0).toUpperCase();
  }

  build() {
    Column() {
      Row() {
        Button() {
          Image($r('app.media.icon_arrow_left')).width(20).height(20)
        }
          .width(48).height(48).backgroundColor('transparent')
          .onClick(() => this.goBack())

        Text($r('app.string.title_accounts'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().textPrimary)
          .layoutWeight(1)

        Button($r('app.string.btn_add'))
          .fontSize(15)
          .fontColor(this.theme().primary)
          .backgroundColor('transparent')
          .onClick(() => this.navigateToAddAccount())
      }
      .width('100%')
      .height(56)
      .padding({ left: 4, right: 12 })
      .backgroundColor(this.theme().surface)

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.theme().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.accounts.length === 0) {
        Column({ space: 16 }) {
          Image($r('app.media.icon_mail'))
            .width(64).height(64)
          Text($r('app.string.no_accounts'))
            .fontSize(16)
            .fontColor(this.theme().textSecondary)
          Text($r('app.string.add_account_hint'))
            .fontSize(14)
            .fontColor(this.theme().textHint)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.accounts, (account: Account) => {
            ListItem() {
              this.AccountItem(account)
            }
          }, (account: Account) => account.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding(16)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().background)
  }

  @Builder
  AccountItem(account: Account) {
    Row() {
      Text(this.getAvatarChar(account))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor(this.avatarColor(account.email))
        .textAlign(TextAlign.Center)

      Column() {
        Row() {
          Text(account.displayName || account.email)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme().textPrimary)

          if (account.isDefault) {
            Text($r('app.string.btn_default'))
              .fontSize(11)
              .fontColor('#FFFFFF')
              .backgroundColor(this.theme().primary)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(4)
              .margin({ left: 8 })
          }
        }
        .width('100%')

        Text(account.email)
          .fontSize(14)
          .fontColor(this.theme().textSecondary)
          .margin({ top: 2 })

        Row() {
          Text(account.protocol)
            .fontSize(12)
            .fontColor(this.theme().textHint)

          if (account.isConnected) {
            Row({ space: 4 }) {
              Image($r('app.media.icon_circle')).width(12).height(12).fillColor(this.theme().success)
              Text(Utils.resourceToString(this.context, $r('app.string.label_connected')))
                .fontSize(12)
                .fontColor(this.theme().success)
            }
              .margin({ left: 8 })
          } else {
            Row({ space: 4 }) {
              Image($r('app.media.icon_circle_off')).width(12).height(12).fillColor(this.theme().warning)
              Text(Utils.resourceToString(this.context, $r('app.string.label_disconnected')))
                .fontSize(12)
                .fontColor(this.theme().warning)
            }
              .margin({ left: 8 })
          }
        }
        .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      Column({ space: 6 }) {
        if (!account.isDefault) {
          Button($r('app.string.btn_default'))
            .fontSize(12)
            .backgroundColor(this.theme().primary)
            .fontColor(this.theme().onPrimary)
            .height(32)
            .borderRadius(16)
            .onClick(() => this.setAsDefault(account))
        }

        Button($r('app.string.btn_edit'))
          .fontSize(13)
          .backgroundColor(this.theme().background)
          .fontColor(this.theme().primary)
          .height(32)
          .borderRadius(16)
          .onClick(() => this.navigateToEditAccount(account))

        Button($r('app.string.btn_delete'))
          .fontSize(12)
          .backgroundColor(this.theme().background)
          .fontColor(this.theme().error)
          .height(28)
          .borderRadius(16)
          .onClick(() => this.deleteAccount(account))
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.theme().surface)
    .borderRadius(12)
  }
}
