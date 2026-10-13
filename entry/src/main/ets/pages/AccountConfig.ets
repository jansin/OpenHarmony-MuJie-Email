import { router } from '@kit.ArkUI';
import { Account, AccountProtocol, SecurityType } from '../models/Account';
import { AccountService } from '../services/AccountService';
import { StorageService } from '../services/StorageService';
import { EmailService } from '../services/EmailService';
import { common } from '@kit.AbilityKit';
import { Utils } from '../common/Utils';
import { EmailTheme, DARK_THEME, LIGHT_THEME } from '../common/Theme';
import { useServices } from '../common/ServiceLocator';
import { LogUtil } from '../common/LogUtil';

interface ProviderInfo {
  label: string;
  domain: string;
  color: string;
  icon: string;
}

@Entry
@Component
struct AccountConfig {
  private context = getContext(this) as common.UIAbilityContext;
  private logger: LogUtil = new LogUtil('AccountConfig');

  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @State themeVersion: number = 0;
  @State accountId: string = '';
  @State email: string = '';
  @State password: string = '';
  @State displayName: string = '';
  @State protocol: AccountProtocol = AccountProtocol.IMAP;
  @State incomingServer: string = '';
  @State incomingPort: number = 993;
  @State incomingSecurity: SecurityType = SecurityType.SSL;
  @State outgoingServer: string = '';
  @State outgoingPort: number = 587;
  @State outgoingSecurity: SecurityType = SecurityType.TLS;
  @State isManualConfig: boolean = false;
  @State useAuthCode: boolean = false;
  @State showProviders: boolean = true;
  @State isLoading: boolean = false;
  @State isTesting: boolean = false;
  @State testResult: string = '';
  @State testSuccess: boolean = false;
  @State emailFocused: boolean = false;
  @State passwordFocused: boolean = false;
  @State animatingProvider: boolean = false;
  @State emailError: string = '';
  @State passwordError: string = '';
  @State isExpandedAuth: boolean = false;

  private accountService: AccountService | null = null;
  private storageService: StorageService | null = null;
  private emailService: EmailService | null = null;

  private providers: ProviderInfo[] = [];
  private theme(): EmailTheme {
    return this.isDarkMode ? DARK_THEME : LIGHT_THEME;
  }



  aboutToAppear(): void {
    this.providers = [
      { label: Utils.resourceToString(this.context, $r('app.string.label_qq_mail')), domain: '@qq.com', color: '#1CB1E3', icon: 'Q' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_163_mail')), domain: '@163.com', color: '#DE1A2B', icon: '1' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_126_mail')), domain: '@126.com', color: '#DE5B2B', icon: '1' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_sina_mail')), domain: '@sina.com', color: '#E81E2B', icon: 'S' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_outlook')), domain: '@outlook.com', color: '#0078D4', icon: 'O' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_gmail')), domain: '@gmail.com', color: '#EA4335', icon: 'G' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_foxmail')), domain: '@foxmail.com', color: '#29A71F', icon: 'F' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_139_mail')), domain: '@139.com', color: '#C62828', icon: '1' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_sohu_mail')), domain: '@sohu.com', color: '#FFAA00', icon: 'S' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_aliyun')), domain: '@aliyun.com', color: '#FF6A00', icon: 'A' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_tom_mail')), domain: '@tom.com', color: '#1E88E5', icon: 'T' },
      { label: Utils.resourceToString(this.context, $r('app.string.label_other')), domain: '', color: '#757575', icon: '...' },
    ];
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
    try {
      const services = await useServices(this.context);
      this.storageService = services.storageService;
      this.accountService = services.accountService;
      this.emailService = services.emailService;
      await this.loadAccount();
    } catch (error) {
      this.logger.e('Failed to initialize:', error as Error);
    }
  }

  async loadAccount(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (!params || !params['accountId']) {
      return;
    }
    this.accountId = params['accountId'] as string;
    if (!this.accountService) {
      return;
    }
    const account = await this.accountService.getAccountById(this.accountId);
    if (!account) {
      return;
    }
    this.email = account.email;
    this.displayName = account.displayName;
    this.protocol = account.protocol as AccountProtocol;
    this.incomingServer = account.incomingServer;
    this.incomingPort = account.incomingPort;
    this.incomingSecurity = account.incomingSecurity as SecurityType;
    this.outgoingServer = account.outgoingServer;
    this.outgoingPort = account.outgoingPort;
    this.outgoingSecurity = account.outgoingSecurity as SecurityType;
    this.password = account.password;
    this.isManualConfig = true;
    this.useAuthCode = account.useClientAuthCode !== false;
    this.showProviders = false;
  }

  onEmailChange(email: string): void {
    this.email = email;
    this.emailError = '';
    
    if (this.isManualConfig || !Utils.isValidEmail(email)) {
      return;
    }
    const settings = this.accountService?.autoDetectSettings(email);
    if (settings) {
      this.incomingServer = settings.incomingServer || '';
      this.incomingPort = settings.incomingPort || 993;
      this.incomingSecurity = (settings.incomingSecurity as SecurityType) || SecurityType.SSL;
      this.outgoingServer = settings.outgoingServer || '';
      this.outgoingPort = settings.outgoingPort || 587;
      this.outgoingSecurity = (settings.outgoingSecurity as SecurityType) || SecurityType.TLS;
    }
    this.displayName = email.split('@')[0];
  }

  validateEmail(): boolean {
    const email = this.email.trim();
    if (!email) {
      this.emailError = Utils.resourceToString(this.context, $r('app.string.placeholder_email'));
      return false;
    }
    if (!Utils.isValidEmail(email)) {
      this.emailError = Utils.resourceToString(this.context, $r('app.string.msg_valid_email_required'));
      return false;
    }
    this.emailError = '';
    return true;
  }

  validatePassword(): boolean {
    const password = this.password.trim();
    if (!password) {
      this.passwordError = Utils.resourceToString(this.context, this.useAuthCode ? $r('app.string.placeholder_auth_code_on_login') : $r('app.string.placeholder_password_on_login'));
      return false;
    }
    this.passwordError = '';
    return true;
  }

  async testConnection(): Promise<void> {
    if (!this.validateEmail() || !this.validatePassword()) {
      return;
    }
    
    const email = this.email.trim();
    const password = this.password.trim();
    
    this.isTesting = true;
    this.testResult = '';
    this.testSuccess = false;
    
    try {
      const account: Account = this.buildAccount(email, password);
      const success = await this.emailService!.connect(account);
      
      if (success) {
        this.testSuccess = true;
        this.testResult = Utils.resourceToString(this.context, $r('app.string.msg_test_success'));
        return;
      }
      
      const parts = email.split('@');
      const isCn = parts.length > 1 && (
        parts[1].includes('163.com') ||
        parts[1].includes('126.com') ||
        parts[1].includes('qq.com') ||
        parts[1].includes('sina.com') ||
        parts[1].includes('139.com') ||
        parts[1].includes('sohu.com') ||
        parts[1].includes('foxmail.com')
      );
      
      this.testResult = isCn
        ? Utils.resourceToString(this.context, $r('app.string.msg_test_fail_auth_cn'))
        : Utils.resourceToString(this.context, $r('app.string.msg_test_fail'));
        
    } catch (error) {
      this.testResult = Utils.resourceToString(this.context, $r('app.string.msg_connection_failed_prefix')) + String(error);
    } finally {
      this.isTesting = false;
    }
  }

  async saveAccount(): Promise<void> {
    if (!this.validateEmail() || !this.validatePassword()) {
      return;
    }
    
    const email = this.email.trim();
    const password = this.password.trim();
    
    this.isLoading = true;
    
    try {
      let existing: Account | null = null;
      if (this.accountId) {
        existing = await this.accountService!.getAccountById(this.accountId);
      }
      
      const account: Account = this.buildAccount(email, password);
      account.id = existing?.id || this.accountId || Utils.generateId();
      account.isDefault = existing?.isDefault || false;
      account.createdAt = existing?.createdAt || Date.now();

      const isConnected = await this.emailService!.connect(account);
      account.isConnected = isConnected;
      account.lastSyncTime = isConnected ? Date.now() : undefined;

      await this.accountService!.updateAccount(account);
      router.back();
      
    } catch (error) {
      this.testResult = Utils.resourceToString(this.context, $r('app.string.msg_save_fail_prefix')) + String(error);
      this.testSuccess = false;
    } finally {
      this.isLoading = false;
    }
  }

  private buildAccount(email: string, password: string): Account {
    return {
      id: Utils.generateId(),
      email: email,
      displayName: (this.displayName || email.split('@')[0]).trim(),
      protocol: this.protocol,
      smtpEnabled: true,
      incomingServer: this.incomingServer.trim(),
      incomingPort: this.incomingPort,
      incomingSecurity: this.incomingSecurity,
      incomingUsername: email,
      outgoingServer: this.outgoingServer.trim(),
      outgoingPort: this.outgoingPort,
      outgoingSecurity: this.outgoingSecurity,
      outgoingUsername: email,
      password: password,
      useClientAuthCode: this.useAuthCode,
      isConnected: false,
      isDefault: false,
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
  }

  goBack(): void {
    router.back();
  }

  quickPick(provider: ProviderInfo): void {
    const prefix = this.email.split('@')[0] || '';
    this.email = prefix + provider.domain;
    this.useAuthCode = true;
  }

  build() {
    Column() {
      this.buildHeader();

      Scroll() {
        Column({ space: 20 }) {
          this.buildEmailInput();
          this.buildProviderSection();
          this.buildDisplayNameInput();
          this.buildAuthSection();
          this.buildProtocolSection();
          this.buildManualToggle();
          this.buildManualConfigSection();
          this.buildTestButton();
          this.buildResultMessage();
          this.buildSaveButton();

        }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }.layoutWeight(1)
      .scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(this.theme().background)
  }

  @Builder
  buildHeader(): void {
    Row() {
      Button() {
        Image($r('app.media.icon_arrow_left'))
          .width(22)
          .height(22)
          .fillColor(this.theme().textPrimary)
      }
        .width(48)
        .height(48)
        .backgroundColor('transparent')
        .onClick(() => this.goBack())

      Text(this.accountId ? $r('app.string.title_edit_account') : $r('app.string.title_add_account'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().textPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Blank().width(48)
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4 })
    .backgroundColor(this.theme().surface)
    .border({ width: { bottom: 0.5 }, color: this.theme().divider })
  }

  @Builder
  buildEmailInput(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image($r('app.media.icon_mail'))
          .width(18)
          .height(18)
          .fillColor(this.emailFocused ? this.theme().primary : this.theme().textHint)
        Text($r('app.string.label_email_address'))
          .fontSize(14)
          .fontColor(this.theme().textSecondary)
          .fontWeight(FontWeight.Medium)
        Blank()
        if (this.email && Utils.isValidEmail(this.email)) {
          Text('✓')
            .fontSize(14)
            .fontColor('#34A853')
        }
      }.width('100%')

      TextInput({ placeholder: $r('app.string.placeholder_email'), text: this.email })
        .type(InputType.Normal)
        .fontSize(16)
        .fontColor(this.theme().textPrimary)
        .backgroundColor(this.theme().background)
        .borderRadius(10)
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .caretColor(this.theme().primary)
        .focusOnTouch(true)
        .onFocus(() => this.emailFocused = true)
        .onBlur(() => {
          this.emailFocused = false;
          this.validateEmail();
        })
        .onChange((email: string) => this.onEmailChange(email))

      if (this.emailError) {
        Text(this.emailError)
          .fontSize(12)
          .fontColor(this.theme().error)
          .margin({ left: 26 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.theme().surface)
    .borderRadius(16)
    .border({
      width: this.emailFocused ? 1.5 : 0.5,
      color: this.emailFocused ? this.theme().primary : this.theme().divider
    })
  }

  @Builder
  buildProviderSection(): void {
    if (this.showProviders && !this.accountId && !this.isManualConfig && !Utils.isValidEmail(this.email)) {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Image($r('app.media.icon_circle'))
            .width(16)
            .height(16)
            .fillColor(this.theme().primary)
          Text($r('app.string.label_quick_select'))
            .fontSize(14)
            .fontColor(this.theme().textSecondary)
            .fontWeight(FontWeight.Medium)
        }.width('100%')

        ForEach(
          this.chunkArray(this.providers, 3),
          (row: ProviderInfo[], index: number) => {
            Row({ space: 10 }) {
              ForEach(row, (provider: ProviderInfo, idx: number) => {
                this.buildProviderButton(provider, index * 3 + idx);
              })
            }.width('100%').margin({ bottom: 10 })
          }
        )

        Text($r('app.string.hint_provider_desc'))
          .fontSize(12)
          .fontColor(this.theme().textHint)
          .width('100%')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.theme().surface)
      .borderRadius(16)
    }
  }

  @Builder
  buildProviderButton(provider: ProviderInfo, index: number): void {
    Column({ space: 4 }) {
      Text(provider.icon)
        .fontSize(20)
        .fontColor('#FFFFFF')
        .fontWeight(FontWeight.Bold)
      Text(provider.label)
        .fontSize(10)
        .fontColor('#FFFFFF')
        .margin({ top: 2 })
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .height(60)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(provider.color)
    .borderRadius(12)
    .shadow({
      radius: 4,
      color: provider.color + '40',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => this.quickPick(provider))
  }

  @Builder
  buildDisplayNameInput(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image($r('app.media.icon_mail'))
          .width(18)
          .height(18)
          .fillColor(this.theme().textHint)
        Text($r('app.string.label_display_name'))
          .fontSize(14)
          .fontColor(this.theme().textSecondary)
          .fontWeight(FontWeight.Medium)
      }.width('100%')

      TextInput({ placeholder: $r('app.string.placeholder_name'), text: this.displayName })
        .fontSize(16)
        .fontColor(this.theme().textPrimary)
        .backgroundColor(this.theme().background)
        .borderRadius(10)
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .caretColor(this.theme().primary)
        .onChange((name: string) => this.displayName = name)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.theme().surface)
    .borderRadius(16)
    .border({ width: 0.5, color: this.theme().divider })
  }

  @Builder
  buildAuthSection(): void {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Image(this.useAuthCode ? $r('app.media.icon_settings') : $r('app.media.icon_edit'))
          .width(18)
          .height(18)
          .fillColor(this.theme().primary)
        Text($r('app.string.label_login_method'))
          .fontSize(14)
          .fontColor(this.theme().textSecondary)
          .fontWeight(FontWeight.Medium)
      }.width('100%')

      Row({ space: 24 }) {
        this.buildAuthOption('password', Utils.resourceToString(this.context, $r('app.string.label_password_login_option')), !this.useAuthCode, () => { this.useAuthCode = false; })
        this.buildAuthOption('authcode', Utils.resourceToString(this.context, $r('app.string.label_auth_code_login_option')), this.useAuthCode, () => { this.useAuthCode = true; })
      }.width('100%')

      TextInput({
        placeholder: this.useAuthCode ? $r('app.string.placeholder_auth_code_on_login') : $r('app.string.placeholder_password_on_login'),
        text: this.password
      })
        .type(InputType.Password)
        .fontSize(16)
        .fontColor(this.theme().textPrimary)
        .backgroundColor(this.theme().background)
        .borderRadius(10)
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .caretColor(this.theme().primary)
        .focusOnTouch(true)
        .onFocus(() => this.passwordFocused = true)
        .onBlur(() => {
          this.passwordFocused = false;
          this.validatePassword();
        })
        .onChange((pwd: string) => {
          this.password = pwd;
          this.passwordError = '';
        })

      if (this.passwordError) {
        Text(this.passwordError)
          .fontSize(12)
          .fontColor(this.theme().error)
          .margin({ left: 26 })
      }

      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Image($r('app.media.ic_info'))
            .width(14)
            .height(14)
            .fillColor(this.theme().primary)
          Text(this.useAuthCode ? $r('app.string.label_how_to_get_auth_code') : $r('app.string.hint_password_desc'))
            .fontSize(12)
            .fontColor(this.theme().primary)
            .fontWeight(FontWeight.Medium)
        }

        if (this.useAuthCode) {
          Text($r('app.string.label_auth_code_description'))
            .fontSize(11)
            .fontColor(this.theme().textHint)
            .margin({ left: 20 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.theme().surface)
    .borderRadius(16)
    .border({ width: 0.5, color: this.passwordFocused ? this.theme().primary : this.theme().divider })
  }

  @Builder
  buildAuthOption(value: string, label: string, checked: boolean, onChange: (checked: boolean) => void): void {
    Row() {
      Radio({ value: value, group: 'auth' })
        .checked(checked)
        .onChange(onChange)
      
      Text(label)
        .fontSize(14)
        .fontColor(checked ? this.theme().primary : this.theme().textPrimary)
        .margin({ left: 6 })
        .fontWeight(checked ? FontWeight.Medium : FontWeight.Normal)
    }
    .scale(checked ? { x: 1.02, y: 1.02 } : { x: 1, y: 1 })
  }

  @Builder
  buildProtocolSection(): void {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_sync'))
          .width(18)
          .height(18)
          .fillColor(this.theme().textHint)
        Text($r('app.string.label_receive_protocol'))
          .fontSize(14)
          .fontColor(this.theme().textSecondary)
          .fontWeight(FontWeight.Medium)
      }.width('100%')

      Row({ space: 32 }) {
        this.buildProtocolOption(AccountProtocol.IMAP, 'IMAP')
        this.buildProtocolOption(AccountProtocol.POP3, 'POP3')
      }

      Text($r('app.string.hint_recommend_imap'))
        .fontSize(12)
        .fontColor(this.theme().textHint)
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.theme().surface)
    .borderRadius(16)
  }

  @Builder
  buildProtocolOption(protocol: AccountProtocol, label: string): void {
    Row() {
      Radio({ value: protocol.toString(), group: 'p' })
        .checked(this.protocol === protocol)
        .onChange(() => this.protocol = protocol)
      
      Text(label)
        .fontSize(16)
        .fontColor(this.protocol === protocol ? this.theme().primary : this.theme().textPrimary)
        .margin({ left: 8 })
        .fontWeight(this.protocol === protocol ? FontWeight.Medium : FontWeight.Normal)
    }
  }

  @Builder
  buildManualToggle(): void {
    Row() {
      Row({ space: 12 }) {
        Image($r('app.media.icon_settings'))
          .width(20)
          .height(20)
          .fillColor(this.theme().primary)
        Column({ space: 2 }) {
          Text($r('app.string.label_manual_config'))
            .fontSize(16)
            .fontColor(this.theme().textPrimary)
            .fontWeight(FontWeight.Medium)
          Text($r('app.string.hint_manual_config'))
            .fontSize(12)
            .fontColor(this.theme().textHint)
        }
        .alignItems(HorizontalAlign.Start)
      }

      Blank()

      Toggle({ type: ToggleType.Switch, isOn: this.isManualConfig })
        .selectedColor(this.theme().primary)
        .switchPointColor('#FFFFFF')
        .onChange((enabled: boolean) => { this.isManualConfig = enabled; })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.theme().surface)
    .borderRadius(16)
    .onClick(() => { this.isManualConfig = !this.isManualConfig; })
  }

  @Builder
  buildManualConfigSection(): void {
    if (this.isManualConfig) {
      Column({ space: 16 }) {
        Column({ space: 16 }) {
          Text($r('app.string.label_incoming_server'))
            .fontSize(14)
            .fontColor(this.theme().textPrimary)
            .fontWeight(FontWeight.Medium)
          
          this.buildServerInput(Utils.resourceToString(this.context, $r('app.string.label_server_address')), this.incomingServer, (v: string) => this.incomingServer = v)
          this.buildPortInput(Utils.resourceToString(this.context, $r('app.string.label_port')), this.incomingPort, (v: number) => this.incomingPort = v)
          this.buildSecuritySection('in', Utils.resourceToString(this.context, $r('app.string.label_security_type')))
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.theme().surface)
        .borderRadius(12)

        Column({ space: 16 }) {
          Text($r('app.string.label_outgoing_server'))
            .fontSize(14)
            .fontColor(this.theme().textPrimary)
            .fontWeight(FontWeight.Medium)
          
          this.buildServerInput(Utils.resourceToString(this.context, $r('app.string.label_server_address')), this.outgoingServer, (v: string) => this.outgoingServer = v)
          this.buildPortInput(Utils.resourceToString(this.context, $r('app.string.label_port')), this.outgoingPort, (v: number) => this.outgoingPort = v)
          this.buildSecuritySection('out', Utils.resourceToString(this.context, $r('app.string.label_security_type')))
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.theme().surface)
        .borderRadius(12)
      }
    }
  }

  @Builder
  buildServerInput(label: string, value: string, onChange: (v: string) => void): void {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme().textHint)
        .width('100%')
      
      TextInput({ text: value })
        .fontSize(15)
        .fontColor(this.theme().textPrimary)
        .backgroundColor(this.theme().background)
        .borderRadius(6)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .onChange(onChange)
    }
  }

  @Builder
  buildPortInput(label: string, value: number, onChange: (v: number) => void): void {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme().textHint)
        .width('100%')
      
      TextInput({ text: value.toString() })
        .fontSize(15)
        .fontColor(this.theme().textPrimary)
        .backgroundColor(this.theme().background)
        .borderRadius(6)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .type(InputType.Number)
        .onChange((v: string) => onChange(parseInt(v) || 993))
    }
  }

  @Builder
  buildSecuritySection(group: string, label: string): void {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme().textHint)
        .width('100%')
      
      Row({ space: 20 }) {
        this.buildSecurityOption(group, SecurityType.NONE, Utils.resourceToString(this.context, $r('app.string.label_none')))
        this.buildSecurityOption(group, SecurityType.SSL, 'SSL')
        this.buildSecurityOption(group, SecurityType.TLS, 'TLS')
      }
    }
  }

  @Builder
  buildSecurityOption(group: string, type: SecurityType, label: string): void {
    Row() {
      Radio({ value: type.toString(), group: group })
        .checked(group === 'in' ? this.incomingSecurity === type : this.outgoingSecurity === type)
        .onChange(() => {
          if (group === 'in') {
            this.incomingSecurity = type;
          } else {
            this.outgoingSecurity = type;
          }
        })
      
      Text(label)
        .fontSize(13)
        .fontColor(this.theme().textPrimary)
        .margin({ left: 4 })
    }
  }

  @Builder
  buildTestButton(): void {
    Button() {
      Row({ space: 10 }) {
        if (this.isTesting) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color('#FFFFFF')
        } else {
          Image($r('app.media.icon_circle'))
            .width(20)
            .height(20)
            .fillColor('#FFFFFF')
        }
        Text(this.isTesting ? $r('app.string.btn_testing') : $r('app.string.btn_test_connection'))
          .fontSize(16)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Medium)
      }
    }
    .width('100%')
    .height(52)
    .backgroundColor('#FF9800')
    .borderRadius(14)
    .enabled(!this.isTesting)
    .onClick(() => { void this.testConnection(); })
  }

  @Builder
  buildResultMessage(): void {
    if (this.testResult) {
      Row({ space: 10 }) {
        if (this.testSuccess) {
          Image($r('app.media.icon_check'))
            .width(20)
            .height(20)
            .fillColor('#34A853')
        } else {
          Image($r('app.media.icon_warning'))
            .width(20)
            .height(20)
            .fillColor(this.theme().error)
        }
        Text(this.testResult)
          .fontSize(14)
          .fontColor(this.testSuccess ? '#34A853' : this.theme().error)
          .maxLines(3)
          .layoutWeight(1)
      }
      .width('100%')
      .padding(14)
      .backgroundColor(this.testSuccess ? 'rgba(52,168,83,0.1)' : 'rgba(211,47,47,0.1)')
      .borderRadius(12)
      .border({ width: 1, color: this.testSuccess ? '#34A85340' : this.theme().error + '40' })
    }
  }

  @Builder
  buildSaveButton(): void {
    Button() {
      Row({ space: 10 }) {
        if (this.isLoading) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color('#FFFFFF')
        } else {
          Image($r('app.media.icon_check'))
            .width(20)
            .height(20)
            .fillColor('#FFFFFF')
        }
        Text(this.isLoading ? $r('app.string.btn_saving') : $r('app.string.btn_save'))
          .fontSize(17)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .height(56)
    .backgroundColor(this.theme().primary)
    .borderRadius(14)
    .enabled(!this.isLoading)
    .shadow({
      radius: 8,
      color: this.theme().primary + '40',
      offsetX: 0,
      offsetY: 4
    })
    .onClick(() => { void this.saveAccount(); })
  }


  private chunkArray<T>(array: T[], size: number): T[][] {
    const chunks: T[][] = [];
    for (let i = 0; i < array.length; i += size) {
      chunks.push(array.slice(i, i + size));
    }
    return chunks;
  }
}
