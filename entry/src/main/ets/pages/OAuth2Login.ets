import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Account } from '../models/Account';
import { StorageService } from '../services/StorageService';
import { OAuth2Service } from '../services/OAuth2Service';
import { EmailTheme, DARK_THEME, LIGHT_THEME } from '../common/Theme';
import { ToastUtil } from '../common/ToastUtil';
import { Utils } from '../common/Utils';

@Entry
@Component
struct OAuth2Login {
  private context = getContext(this) as common.UIAbilityContext;
  @State account: Account | null = null;
  @State themeVersion: number = 0;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @State authUrl: string = '';
  @State authCode: string = '';
  @State isExchanging: boolean = false;
  @State statusText: string = '';

  private storageService: StorageService | null = null;
  private oauth2Service: OAuth2Service | null = null;
  private theme(): EmailTheme {
    return this.isDarkMode ? DARK_THEME : LIGHT_THEME;
  }



  aboutToAppear(): void {
    this.statusText = Utils.resourceToString(this.context, $r('app.string.oauth_status_init'));
    this.init();
  }

  onThemeChange = (): void => {
    this.themeVersion++;
  }

  onPageShow(): void {
    this.themeVersion++;
  }

  onPageHide(): void {
  }

  async init(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['accountId']) {
      const context = getContext(this) as common.UIAbilityContext;
      this.storageService = StorageService.getInstance(context);
      await this.storageService.initialize();
      this.oauth2Service = OAuth2Service.getInstance(this.storageService);
      const accounts = await this.storageService.getAccounts();
      const acc = accounts.find(a => a.id === params['accountId']);
      if (acc) {
        this.account = acc;
        const provider = this.oauth2Service.getProvider(acc);
        if (provider) {
          this.authUrl = this.oauth2Service.getAuthUrl(provider);
          this.statusText = Utils.resourceToString(this.context, $r('app.string.oauth_status_instruction'));
        } else {
          this.statusText = Utils.resourceToString(this.context, $r('app.string.oauth_status_unsupported'));
        }
        return;
      }
    }
    this.statusText = Utils.resourceToString(this.context, $r('app.string.oauth_status_param_error'));
  }

  async completeAuth(): Promise<void> {
    if (!this.authCode.trim() || !this.account || !this.oauth2Service) {
      ToastUtil.showError(Utils.resourceToString(this.context, $r('app.string.oauth_code_required')));
      return;
    }
    const provider = this.oauth2Service.getProvider(this.account);
    if (!provider) {
      ToastUtil.showError(Utils.resourceToString(this.context, $r('app.string.oauth_status_unsupported')));
      return;
    }
    this.isExchanging = true;
    this.statusText = Utils.resourceToString(this.context, $r('app.string.oauth_status_exchanging'));
    try {
      const result = await this.oauth2Service.exchangeCode(provider, this.authCode.trim());
      if (!result) {
        this.statusText = Utils.resourceToString(this.context, $r('app.string.oauth_status_exchange_fail'));
        ToastUtil.showError(Utils.resourceToString(this.context, $r('app.string.oauth_failed')));
        return;
      }
      this.account.accessToken = result.accessToken;
      this.account.refreshToken = result.refreshToken;
      this.account.tokenExpiry = Date.now() + result.expiresIn * 1000;
      this.account.authType = 'oauth2';
      if (this.storageService) {
        await this.storageService.saveAccount(this.account);
      }
      ToastUtil.showSuccess(Utils.resourceToString(this.context, $r('app.string.oauth_success')));
      router.back();
    } catch (e) {
      this.statusText = Utils.resourceToString(this.context, $r('app.string.oauth_network_error'));
      ToastUtil.showError(Utils.resourceToString(this.context, $r('app.string.oauth_failed')));
    } finally {
      this.isExchanging = false;
    }
  }

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.oauth_title'))
        .fontSize(20).fontWeight(FontWeight.Bold)
        .margin({ top: 32 })

      Text(this.statusText)
        .fontSize(14)
        .fontColor(this.theme().textSecondary)
        .padding(16)
        .lineHeight(22)
        .width('100%')

      if (this.authUrl) {
        Button($r('app.string.oauth_btn_browser'))
          .width('80%').height(48)
          .backgroundColor(this.theme().primary)
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            try {
              this.context.openLink(this.authUrl);
            } catch (e) {
              // opened via openLink
            }
          })

        TextInput({ placeholder: Utils.resourceToString(this.context, $r('app.string.oauth_placeholder_code')), text: this.authCode })
          .width('80%').height(48)
          .fontSize(14)
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .onChange((v: string) => this.authCode = v)

        Button() {
          if (this.isExchanging) {
            Row({ space: 6 }) {
              LoadingProgress().width(16).height(16).color('#FFFFFF')
              Text($r('app.string.oauth_exchanging')).fontSize(15).fontColor('#FFFFFF')
            }
          } else {
            Text($r('app.string.oauth_btn_confirm')).fontSize(15).fontColor('#FFFFFF')
          }
        }
          .width('80%').height(48)
          .backgroundColor(this.isExchanging ? this.theme().textHint : this.theme().primary)
          .borderRadius(8)
          .enabled(!this.isExchanging)
          .onClick(() => { void this.completeAuth(); })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.theme().background)
  }
}
