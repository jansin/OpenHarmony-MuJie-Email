import { router } from '@kit.ArkUI';
import { Email, EmailAddress } from '../models/Email';
import { Attachment } from '../models/Attachment';
import { StorageService } from '../services/StorageService';
import { AccountService } from '../services/AccountService';
import { EmailService } from '../services/EmailService';
import { common } from '@kit.AbilityKit';
import { Utils } from '../common/Utils';
import { EmailTheme, DARK_THEME, LIGHT_THEME } from '../common/Theme';
import { buildEmailBodyHtmlFragment } from '../common/EmailWebDocument';
import { fileIo } from '@kit.CoreFileKit';
import { LogUtil } from '../common/LogUtil';
import { ToastUtil } from '../common/ToastUtil';

/** loadData 过大可能导致卡顿或失败；超出则仅�?Text 回退 */
const MAIL_WEB_DOC_MAX_CHARS = 8000000;

@Entry
@Component
struct EmailDetail {
  private context = getContext(this) as common.UIAbilityContext;
  private logger: LogUtil = new LogUtil('EmailDetail');
  @State email: Email | null = null;
  @State isLoading: boolean = true;
  @State isLoadingBody: boolean = false;
  /** 正文从服务器拉取失败时的说明（如网络、UID 不匹配等�?*/
  @State bodyLoadError: string = '';
  @State showDetails: boolean = false;
  @State themeVersion: number = 0;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  /** �?HTML Web 或超大正文时的纯文本回退 */
  @State bodyDisplayPlain: string = '';
  @State mailBodyRichHtml: string = '';
  /** 使用 ArkWeb loadData 渲染邮件（主流：内嵌 WebView + 本地 HTML 串，避免 data: URL�?*/
  @State mailBodyUseWeb: boolean = false;
  @State downloadingAttachments: Set<string> = new Set();
  

  private storageService: StorageService | null = null;
  private accountService: AccountService | null = null;
  private emailService: EmailService | null = null;
  /** 待注�?Web 的完�?HTML；与 @State 解耦以减小状态体�?*/
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

  onThemeChange = (): void => {
    this.themeVersion++;
    this.refreshMailBodyView();
  }

  onPageShow(): void {
    this.themeVersion++;
    this.refreshMailBodyView();
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
      await this.loadEmailData();
    } catch (error) {
      this.logger.e('Failed to initialize: ' + JSON.stringify(error));
    } finally {
      this.isLoading = false;
    }
  }

  async loadEmailData(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (!params) {
      return;
    }
    const emailId = params['emailId'] as string;
    if (!this.storageService || !emailId) {
      return;
    }
    const email = await this.storageService.getEmailById(emailId);
    if (!email) {
      return;
    }
    this.email = email;
    const hasStoredBody =
      ((email.bodyText ?? '').trim().length > 0) || ((email.bodyHtml ?? '').trim().length > 0);
    this.bodyLoadError = hasStoredBody ? '' : (email.syncError ?? '').trim();
    if (!email.isRead) {
      await this.storageService.updateEmailFlags(emailId, { 'isRead': 1 });
      this.email.isRead = true;
    }
    this.refreshMailBodyView();
    const hasHtmlBody = ((email.bodyHtml ?? '').trim().length > 0);
    const hasTextBody = ((email.bodyText ?? '').trim().length > 0);
    const needFetch = !hasHtmlBody && !hasTextBody;
    if (needFetch && this.emailService) {
      this.isLoadingBody = true;
      void this.fetchBodyAfterIdle(email);
    }
  }

  updateBodyDisplayPlain(): void {
    const e = this.email;
    if (!e) {
      this.bodyDisplayPlain = '';
      return;
    }
    const tx = (e.bodyText ?? '').trim();
    const ht = (e.bodyHtml ?? '').trim();
    if (tx.length > 0) {
      this.bodyDisplayPlain = tx;
      return;
    }
    if (ht.length > 0) {
      this.bodyDisplayPlain = Utils.stripHtml(ht);
      return;
    }
    this.bodyDisplayPlain = '';
  }

  /** 生成阅读�?HTML，并决定是否�?Web loadData */
  refreshMailBodyView(): void {
    const e = this.email;
    this.updateBodyDisplayPlain();
    if (!e) {
      this.mailBodyUseWeb = false;
      this.mailBodyRichHtml = '';
      return;
    }
    const tx = (e.bodyText ?? '').trim();
    const ht = (e.bodyHtml ?? '').trim();
    if (tx.length === 0 && ht.length === 0) {
      this.mailBodyUseWeb = false;
      this.mailBodyRichHtml = '';
      return;
    }
    const html = buildEmailBodyHtmlFragment(e.bodyHtml, e.bodyText);
    if (html.length === 0) {
      this.mailBodyUseWeb = false;
      this.mailBodyRichHtml = '';
      return;
    }
    if (html.length > MAIL_WEB_DOC_MAX_CHARS) {
      this.bodyLoadError = 'Email body too large to render fully.';
      this.mailBodyUseWeb = false;
      this.mailBodyRichHtml = '';
      return;
    }
    this.mailBodyRichHtml = html;
    this.mailBodyUseWeb = true;
  }

  private async fetchBodyAfterIdle(seed: Email): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), 0);
    });
    try {
      let account = await this.accountService?.getAccountById(seed.accountId);
      if (!account) {
        account = await this.accountService?.getDefaultAccount();
      }
      if (!account || !this.emailService) {
        return;
      }
      const updated = await this.emailService.fetchEmailContent(account, seed);
      if (updated && this.email?.id === seed.id) {
        this.bodyLoadError = (updated.syncError ?? '').trim();
        this.email = null;
        this.email = updated;
      }
    } catch (e) {
      this.logger.e('fetchBodyAfterIdle: ' + JSON.stringify(e));
      this.bodyLoadError = e instanceof Error ? e.message : String(e);
    } finally {
      if (this.email?.id === seed.id) {
        this.isLoadingBody = false;
        this.refreshMailBodyView();
      }
    }
  }

  retryLoadBody(): void {
    if (!this.email || !this.emailService) return;
    this.isLoadingBody = true;
    this.bodyLoadError = '';
    void this.fetchBodyAfterIdle(this.email);
  }

  goBack(): void { router.back(); }

  navigateToCompose(mode: string): void {
    if (!this.email) return;
    router.pushUrl({ url: 'pages/ComposeEmail', params: { mode: mode, originalEmail: this.email } });
  }

  async deleteEmail(): Promise<void> {
    if (!this.storageService || !this.email) return;
    try {
      await this.storageService.deleteEmail(this.email.id);
      router.back();
    } catch (e) {
      this.logger.e('Failed to delete email:', e);
    }
  }

  async toggleStar(): Promise<void> {
    if (!this.storageService || !this.email) return;
    try {
      await this.storageService.updateEmailFlags(this.email.id, { 'isStarred': this.email.isStarred ? 0 : 1 });
      if (this.email) this.email.isStarred = !this.email.isStarred;
    } catch (e) {
      this.logger.e('Failed to toggle star:', e);
    }
  }

  async downloadAttachment(attachment: Attachment): Promise<void> {
    if (!this.storageService || !this.email) return;
    const s = new Set<string>(this.downloadingAttachments);
    s.add(attachment.id);
    this.downloadingAttachments = s;
    try {
      const dir = this.context.filesDir + '/downloads/';
      try {
        fileIo.mkdirSync(dir);
      } catch (e) {
        this.logger.d('Download directory already exists or cannot be created:', e);
      }
      const path = dir + attachment.filename;
      let exists = false;
      try {
        const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        fileIo.writeSync(file.fd, attachment.filename + '\nsize: ' + attachment.size + '\nemail: ' + this.email.id);
        fileIo.closeSync(file);
        exists = true;
      } catch (e) {
        this.logger.e('Failed to save attachment:', e);
        exists = false;
      }
      if (exists) {
        attachment.localPath = path;
        attachment.isDownloaded = true;
        const e = this.email;
        this.email = null;
        this.email = e;
        ToastUtil.showSuccess(Utils.resourceToString(this.context, $r('app.string.msg_download_success')));
      } else {
        ToastUtil.showError(Utils.resourceToString(this.context, $r('app.string.msg_download_failed')));
      }
    } catch (e) {
      this.logger.e('Download attachment error:', e);
      ToastUtil.showError(Utils.resourceToString(this.context, $r('app.string.msg_download_failed')));
    } finally {
      const s2 = new Set<string>(this.downloadingAttachments);
      s2.delete(attachment.id);
      this.downloadingAttachments = s2;
    }
  }

  getInitial(): string {
    if (!this.email || !this.email.from) {
      return '?';
    }
    const n = Utils.coerceUiString(this.email.from.name );
    const a = Utils.coerceUiString(this.email.from.address );
    const pick = n.length > 0 ? n : a;
    if (!pick) {
      return '?';
    }
    return pick.charAt(0).toUpperCase();
  }

  private formatRecipientDisplay(list: EmailAddress[]): string {
    const s = Utils.formatAddressList(list);
    if (s.length > 0) {
      return s;
    }
    return Utils.resourceToString(this.context, $r('app.string.detail_recipients_none'));
  }

  private displaySubjectLine(): string {
    if (!this.email) {
      return '';
    }
    const s = Utils.coerceUiString(this.email.subject );
    if (s.length > 0) {
      return s;
    }
    return Utils.resourceToString(this.context, $r('app.string.msg_no_subject'));
  }

  build() {
    Column() {
      Row() {
        Button() {
          Image($r('app.media.icon_arrow_left')).width(20).height(20)
        }
          .width(48).height(48).backgroundColor('transparent')
          .onClick(() => this.goBack())

        Text(this.displaySubjectLine())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 4 })

        Button() {
          Text(this.email?.isStarred ? '\u2605' : '\u2606')
            .fontSize(22)
            .fontColor(this.email?.isStarred ? '#FF9500' : this.theme().textHint)
        }
        .width(48).height(48).backgroundColor('transparent')
        .onClick(() => { void this.toggleStar(); })

        Button() {
          Image($r('app.media.icon_delete')).width(20).height(20)
        }
          .width(48).height(48).backgroundColor('transparent')
          .onClick(() => { void this.deleteEmail(); })
      }
      .width('100%')
      .height(56)
      .padding({ left: 4, right: 4 })
      .backgroundColor(this.theme().surface)
      .border({ width: { bottom: 1 }, color: this.theme().divider })

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme().primary)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.email) {
        Scroll() {
          Column() {
            Row() {
              Text(this.getInitial())
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .width(48)
                .height(48)
                .borderRadius(24)
                .backgroundColor(this.avatarColor(
                  Utils.coerceUiString(this.email.from.name) ||
                  Utils.coerceUiString(this.email.from.address)))
                .textAlign(TextAlign.Center)

              Column({ space: 2 }) {
                Text(Utils.coerceUiString(this.email.from.name) ||
                  Utils.coerceUiString(this.email.from.address))
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme().textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Row({ space: 8 }) {
                  Text(Utils.coerceUiString(this.email.from.address))
                    .fontSize(13)
                    .fontColor(this.theme().textHint)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(Utils.formatDateFull(this.email.date))
                    .fontSize(13)
                    .fontColor(this.theme().textHint)
                    .flexShrink(0)
                }
                .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 12 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16 })

            Row() {
              Button($r('app.string.btn_view_details'))
                .fontSize(12)
                .fontColor(this.theme().textHint)
                .backgroundColor('transparent')
                .onClick(() => this.showDetails = !this.showDetails)
            }
            .width('100%')
            .padding({ left: 12, right: 16 })

            if (this.showDetails) {
              Column({ space: 4 }) {
                Text($r('app.string.label_to') + this.formatRecipientDisplay(this.email.to ?? []))
                  .fontSize(13).fontColor(this.theme().textHint).width('100%')
                if (this.email.cc && this.email.cc.length > 0) {
                  Text($r('app.string.label_cc') + this.formatRecipientDisplay(this.email.cc))
                    .fontSize(13).fontColor(this.theme().textHint).width('100%')
                }
                if (this.email.bcc && this.email.bcc.length > 0) {
                  Text($r('app.string.label_bcc') + this.formatRecipientDisplay(this.email.bcc))
                    .fontSize(13).fontColor(this.theme().textHint).width('100%')
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 8 })
            }

            Divider().height(1).color(this.theme().divider).margin({ left: 16, right: 16 })

            Column() {
              if (this.isLoadingBody) {
                Row({ space: 8 }) {
                  LoadingProgress().width(16).height(16).color(this.theme().primary)
                  Text($r('app.string.msg_loading'))
                    .fontSize(14).fontColor(this.theme().textHint)
                }
                .width('100%').justifyContent(FlexAlign.Center)
                .padding({ top: 24, bottom: 24 })
              } else if (this.mailBodyUseWeb && this.mailBodyRichHtml.length > 0) {
                RichText(this.mailBodyRichHtml)
                  .key((this.email?.id ?? '') + '_mw_' + this.themeVersion.toString())
                  .width('100%')
                  .backgroundColor(this.theme().surface)
              } else if (this.bodyLoadError.length > 0) {
                Column({ space: 8 }) {
                  Text($r('app.string.msg_detail_body_failed'))
                    .fontSize(14)
                    .fontColor(this.theme().error)
                    .width('100%')
                  Text(this.bodyLoadError)
                    .fontSize(13)
                    .fontColor(this.theme().textSecondary)
                    .width('100%')
                    .wordBreak(WordBreak.BREAK_WORD)
                  Button($r('app.string.btn_refresh'))
                    .fontSize(13)
                    .fontColor(this.theme().onPrimary)
                    .backgroundColor(this.theme().primary)
                    .height(36)
                    .borderRadius(18)
                    .onClick(() => this.retryLoadBody())
                }
                .width('100%')
                .padding({ top: 16, bottom: 16 })
              } else {
                Text($r('app.string.msg_no_body'))
                  .fontSize(14)
                  .fontColor(this.theme().textHint)
                  .width('100%')
                  .textAlign(TextAlign.Center)
              }
            }
            .width('100%')
            .padding(16)

            if (this.email.attachments && this.email.attachments.length > 0) {
              Divider().height(1).color(this.theme().divider).margin({ left: 16, right: 16 })
              Column() {
                Text(Utils.resourceToString(this.context, $r('app.string.label_attachments')) + this.email.attachments.length + ')')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme().textPrimary)
                  .width('100%')
                  .margin({ bottom: 12 })

                ForEach(this.email.attachments, (attachment: Attachment) => {
                  Row() {
                    Row({ space: 10 }) {
                      Image($r('app.media.icon_file'))
                        .width(24).height(24)
                        .fillColor(this.theme().primary)
                      Column({ space: 2 }) {
                        Text(attachment.filename)
                          .fontSize(14)
                          .fontColor(this.theme().textPrimary)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(Utils.formatFileSize(attachment.size))
                          .fontSize(12)
                          .fontColor(this.theme().textHint)
                      }
                      .layoutWeight(1)
                      .margin({ left: 8 })
                    }

                    if (attachment.isDownloaded) {
                      Image($r('app.media.ic_check'))
                        .width(20).height(20)
                        .fillColor(this.theme().success)
                    } else if (this.downloadingAttachments.has(attachment.id)) {
                      LoadingProgress().width(20).height(20).color(this.theme().primary)
                    } else {
                      Button($r('app.string.btn_download'))
                        .fontSize(13)
                        .fontColor(this.theme().onPrimary)
                        .backgroundColor(this.theme().primary)
                        .height(32)
                        .borderRadius(16)
                        .onClick(() => this.downloadAttachment(attachment))
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(this.theme().cardBackground)
                  .borderRadius(12)
                  .margin({ bottom: 8 })
                }, (attachment: Attachment) => attachment.id)
              }
              .width('100%')
              .padding(16)
            }
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .padding({ bottom: 80 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .height('100%')
        .backgroundColor(this.theme().surface)

        Row() {
          Button() {
            Row({ space: 6 }) {
              Image($r('app.media.ic_reply')).width(18).height(18).fillColor(this.theme().primary)
              Text($r('app.string.btn_reply'))
                .fontSize(13)
                .fontColor(this.theme().primary)
            }
          }
          .backgroundColor(this.theme().background)
          .height(44)
          .borderRadius(22)
          .layoutWeight(1)
          .margin({ right: 8 })
          .onClick(() => this.navigateToCompose('reply'))

          Button() {
            Row({ space: 6 }) {
              Image($r('app.media.ic_reply_all')).width(18).height(18).fillColor(this.theme().primary)
              Text($r('app.string.btn_reply_all'))
                .fontSize(13)
                .fontColor(this.theme().primary)
            }
          }
          .backgroundColor(this.theme().background)
          .height(44)
          .borderRadius(22)
          .layoutWeight(1)
          .margin({ right: 8 })
          .onClick(() => this.navigateToCompose('replyAll'))

          Button() {
            Row({ space: 6 }) {
              Image($r('app.media.ic_forward')).width(18).height(18).fillColor(this.theme().primary)
              Text($r('app.string.btn_forward'))
                .fontSize(13)
                .fontColor(this.theme().primary)
            }
          }
          .backgroundColor(this.theme().background)
          .height(44)
          .borderRadius(22)
          .layoutWeight(1)
          .onClick(() => this.navigateToCompose('forward'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
        .backgroundColor(this.theme().surface)
        .border({ width: { top: 1 }, color: this.theme().divider })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().background)
  }
}
