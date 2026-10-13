import { router } from '@kit.ArkUI';
import { Email, EmailAddress } from '../models/Email';
import { Account } from '../models/Account';
import { AccountService } from '../services/AccountService';
import { StorageService } from '../services/StorageService';
import { EmailService } from '../services/EmailService';
import { common } from '@kit.AbilityKit';
import { Utils } from '../common/Utils';
import { EmailTheme, DARK_THEME, LIGHT_THEME } from '../common/Theme';
import { Attachment } from '../models/Attachment';
import { fileIo } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { buildEmailBodyHtmlFragment, escapeHtmlText } from '../common/EmailWebDocument';
import { LogUtil } from '../common/LogUtil';
import { ToastUtil } from '../common/ToastUtil';
import { ContactSuggestion, ContactRecord } from '../models/RecordTypes';

@Entry
@Component
struct ComposeEmail {
  private context = getContext(this) as common.UIAbilityContext;
  private logger: LogUtil = new LogUtil('ComposeEmail');
  @State mode: string = 'new';
  @State fromAccount: Account | null = null;
  @State accounts: Account[] = [];
  @State showAccountPicker: boolean = false;
  @State to: string = '';
  @State cc: string = '';
  @State bcc: string = '';
  @State subject: string = '';
  /** 用户编辑区（不含底部引用卡片） */
  @State composeBody: string = '';
  /** 回复/转发时只读展示的引用块，发送时拼回正文 */
  @State quotedBlock: string = '';
  @State quotedRichHtml: string = '';
  @State isSending: boolean = false;
  @State showCc: boolean = false;
  @State showBcc: boolean = false;
  @State originalEmail: Email | null = null;
  @State errorMessage: string = '';
  @State attachments: Attachment[] = [];
  @State themeVersion: number = 0;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @State contactSuggestions: ContactSuggestion[] = [];
  @State showContactDropdown: boolean = false;
  @State activeField: string = 'to';
  private storageService: StorageService | null = null;

  private accountService: AccountService | null = null;
  private emailService: EmailService | null = null;
  private theme(): EmailTheme {
    return this.isDarkMode ? DARK_THEME : LIGHT_THEME;
  }



  aboutToAppear(): void {
    void this.initializeServices();
  }

  onThemeChange = (_isDark: boolean): void => {
    this.themeVersion++;
  }

  onPageShow(): void {
    this.themeVersion++;
  }

  onPageHide(): void {
  }

  private originalBodyPlain(): string {
    if (!this.originalEmail) {
      return '';
    }
    const t = this.originalEmail.bodyText?.trim();
    if (t !== undefined && t !== null && t.length > 0) {
      return t;
    }
    const h = this.originalEmail.bodyHtml;
    if (h !== undefined && h !== null && h.length > 0) {
      return Utils.stripHtml(h);
    }
    return '';
  }

  private buildQuotedPreviewHtml(header: string): string {
    if (!this.originalEmail) {
      return '';
    }
    const body = buildEmailBodyHtmlFragment(this.originalEmail.bodyHtml, this.originalEmail.bodyText);
    const safeHeader = escapeHtmlText(header).replace(/\n/g, '<br/>');
    return '<div style="border-left:3px solid #1a73e8;padding-left:10px;color:#5f6368;">' +
      '<div style="font-size:12px;margin-bottom:8px;">' + safeHeader + '</div>' +
      '<div>' + body + '</div>' +
      '</div>';
  }

  async initializeServices(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.storageService = StorageService.getInstance(context);
      await this.storageService.initialize();

      this.accountService = AccountService.getInstance(this.storageService);
      this.emailService = EmailService.getInstance(this.storageService);

      this.fromAccount = await this.accountService.getDefaultAccount();
      this.accounts = await this.storageService.getAccounts();
      this.loadComposeData();
      if (this.mode === 'new' && this.fromAccount?.signature && this.quotedBlock.length === 0 &&
        !this.originalEmail && this.composeBody.length === 0) {
        this.composeBody = '\n\n--\n' + this.fromAccount.signature;
      }
      if (this.fromAccount) {
        void this.loadContacts('');
      }
    } catch (error) {
      this.logger.e('Failed to initialize:', error);
    }
  }

  private async loadContacts(keyword: string): Promise<void> {
    if (!this.storageService || !this.fromAccount) return;
    const raw = await this.storageService.getContacts(this.fromAccount.id, keyword);
    const list: ContactSuggestion[] = [];
    for (const c of raw) {
      if (list.findIndex(item => item.email === c.email) < 0) {
        const item: ContactSuggestion = { name: c.name, email: c.email };
        list.push(item);
      }
    }
    this.contactSuggestions = list;
    this.showContactDropdown = list.length > 0 && keyword.length > 0;
  }

  private selectContact(contact: ContactSuggestion): void {
    const addr = contact.email;
    if (this.activeField === 'cc') {
      this.cc = this.cc ? this.cc + ', ' + addr : addr;
    } else if (this.activeField === 'bcc') {
      this.bcc = this.bcc ? this.bcc + ', ' + addr : addr;
    } else {
      this.to = this.to ? this.to + ', ' + addr : addr;
    }
    this.showContactDropdown = false;
    this.contactSuggestions = [];
  }

  private saveContactsFromEmail(email: Email): void {
    if (!this.storageService || !this.fromAccount) return;
    const now = Date.now();
    const seen = new Set<string>();
    const all: EmailAddress[] = [];
    if (email.to) for (const a of email.to) all.push(a);
    if (email.cc) for (const a of email.cc) all.push(a);
    if (email.bcc) for (const a of email.bcc) all.push(a);
    for (const addr of all) {
      if (!addr.address || seen.has(addr.address)) continue;
      seen.add(addr.address);
      const record: ContactRecord = {
        id: Utils.generateId(),
        accountId: this.fromAccount.id,
        name: addr.name || addr.address.split('@')[0],
        email: addr.address,
        lastContactTime: now,
        contactCount: 1,
        createdAt: now
      };
      this.storageService.saveContact(record);
    }
  }

  loadComposeData(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      this.mode = (params['mode'] as string) || 'new';
      this.originalEmail = (params['originalEmail'] as Email) || null;

      if (this.originalEmail) {
        this.setupReplyForwardFields();
      } else {
        this.quotedBlock = '';
        this.quotedRichHtml = '';
      }
    }
  }

  setupReplyForwardFields(): void {
    if (!this.originalEmail) {
      return;
    }

    const raw = this.originalBodyPlain();
    if (this.mode === 'reply') {
      this.to = this.originalEmail.from.address;
      this.subject = 'Re: ' + this.originalEmail.subject;
      const who = this.originalEmail.from.name || this.originalEmail.from.address;
      const wrote = Utils.resourceToString(this.context, $r('app.string.reply_wrote'));
      this.quotedBlock = who + ' ' + wrote + '\n' + raw.split('\n').map((line: string) => '> ' + line).join('\n');
      this.quotedRichHtml = this.buildQuotedPreviewHtml(who + ' ' + wrote);
      this.composeBody = '\n';
    } else if (this.mode === 'replyAll') {
      this.to = this.originalEmail.from.address;
      const filteredTo: string[] = [];
      for (const addr of this.originalEmail.to) {
        if (addr.address !== this.fromAccount?.email) {
          filteredTo.push(addr.address);
        }
      }
      this.cc = filteredTo.join(', ');
      if (this.originalEmail.cc) {
        const ccFiltered: string[] = [];
        for (const addr of this.originalEmail.cc) {
          if (addr.address !== this.fromAccount?.email) {
            ccFiltered.push(addr.address);
          }
        }
        if (ccFiltered.length > 0) {
          this.cc = this.cc ? this.cc + ', ' + ccFiltered.join(', ') : ccFiltered.join(', ');
        }
      }
      this.subject = 'Re: ' + this.originalEmail.subject;
      const who = this.originalEmail.from.name || this.originalEmail.from.address;
      const wrote = Utils.resourceToString(this.context, $r('app.string.reply_wrote'));
      this.quotedBlock = who + ' ' + wrote + '\n' + raw.split('\n').map((line: string) => '> ' + line).join('\n');
      this.quotedRichHtml = this.buildQuotedPreviewHtml(who + ' ' + wrote);
      this.composeBody = '\n';
    } else if (this.mode === 'forward') {
      this.subject = 'Fwd: ' + this.originalEmail.subject;
      const hdr = Utils.resourceToString(this.context, $r('app.string.msg_forward_header'));
      const sub = Utils.resourceToString(this.context, $r('app.string.label_subject'));
      const fromL = Utils.resourceToString(this.context, $r('app.string.label_from'));
      const dateL = Utils.resourceToString(this.context, $r('app.string.label_date'));
      const toL = Utils.resourceToString(this.context, $r('app.string.label_to'));
      this.quotedBlock = hdr + '\n' + sub + this.originalEmail.subject + '\n' + fromL +
        (this.originalEmail.from.name || this.originalEmail.from.address) + '\n' + dateL +
        Utils.formatDate(this.context, this.originalEmail.date) + '\n' + toL +
        this.originalEmail.to.map(addr => addr.address).join(', ') + '\n\n' + raw;
      this.quotedRichHtml = this.buildQuotedPreviewHtml(hdr + '\n' + sub + this.originalEmail.subject + '\n' +
        fromL + (this.originalEmail.from.name || this.originalEmail.from.address) + '\n' +
        dateL + Utils.formatDate(this.context, this.originalEmail.date) + '\n' +
        toL + this.originalEmail.to.map(addr => addr.address).join(', '));
      this.composeBody = '';
    }
  }

  private buildMergedBody(): string {
    const top = this.composeBody;
    if (this.quotedBlock.length === 0) {
      return top;
    }
    return top.replace(/\s+$/, '') + '\n\n' + this.quotedBlock;
  }

  goBack(): void {
    if (this.hasUnsavedContent()) {
      AlertDialog.show({
        title: Utils.resourceToString(this.context, $r('app.string.msg_discard_title')),
        message: Utils.resourceToString(this.context, $r('app.string.msg_discard_body')),
        autoCancel: true,
        primaryButton: {
          value: Utils.resourceToString(this.context, $r('app.string.btn_save_draft')),
          action: () => { void this.saveDraft(); }
        },
        secondaryButton: {
          value: Utils.resourceToString(this.context, $r('app.string.btn_discard')),
          fontColor: '#D93025',
          action: () => { router.back(); }
        }
      });
    } else {
      router.back();
    }
  }

  private hasUnsavedContent(): boolean {
    if (this.isSending) return false;
    return this.to.trim().length > 0 || this.subject.trim().length > 0 || this.composeBody.trim().length > 0;
  }

  async sendEmail(): Promise<void> {
    this.errorMessage = '';

    if (!this.to) {
      this.errorMessage = Utils.resourceToString(this.context, $r('app.string.msg_recipient_required'));
      return;
    }

    if (!this.fromAccount) {
      this.errorMessage = Utils.resourceToString(this.context, $r('app.string.msg_no_account'));
      return;
    }

    this.isSending = true;
    const mergedBody = this.buildMergedBody();

    try {
      const toList: EmailAddress[] = this.parseAddressList(this.to);
      const ccList: EmailAddress[] = this.cc ? this.parseAddressList(this.cc) : [];
      const bccList: EmailAddress[] = this.bcc ? this.parseAddressList(this.bcc) : [];

      const account = this.fromAccount;
      if (!account) {
        this.errorMessage = Utils.resourceToString(this.context, $r('app.string.msg_account_error'));
        return;
      }

      const emailSvc = this.emailService;
      if (!emailSvc) {
        this.errorMessage = Utils.resourceToString(this.context, $r('app.string.msg_service_error'));
        return;
      }

      const attachmentFiles: Attachment[] = [];
      for (const a of this.attachments) {
        try {
          const file = fileIo.openSync(a.localPath!, fileIo.OpenMode.READ_ONLY);
          const stat = fileIo.statSync(a.localPath!);
          const buf = new ArrayBuffer(stat.size);
          fileIo.readSync(file.fd, buf);
          fileIo.closeSync(file);
          const attach: Attachment = {
            id: a.id, emailId: '',
            filename: a.filename, contentType: a.contentType,
            size: stat.size, disposition: 'attachment',
            isDownloaded: true, localPath: a.localPath,
            createdAt: a.createdAt
          };
          attachmentFiles.push(attach);
        } catch (e) {
          this.logger.e('Read attachment failed:', e);
        }
      }
      const success = await emailSvc.sendEmail(
        account, toList, ccList, bccList,
        this.subject, mergedBody, attachmentFiles
      );

      if (success) {
        ToastUtil.showSuccess(Utils.resourceToString(this.context, $r('app.string.msg_send_success')) || '发送成功');
        this.saveContactsFromEmail({
          to: toList, cc: ccList, bcc: bccList
        } as Email);
        const sentFolderId = account.id + '_Sent';
        const sentEmail: Email = {
          id: Utils.generateId(),
          accountId: this.fromAccount.id,
          folderId: sentFolderId,
          messageId: Utils.generateId(),
          subject: this.subject,
          from: { name: this.fromAccount.displayName, address: this.fromAccount.email },
          to: toList,
          cc: ccList.length > 0 ? ccList : undefined,
          bcc: bccList.length > 0 ? bccList : undefined,
          date: Date.now(),
          bodyText: mergedBody,
          preview: mergedBody.substring(0, 100),
          isRead: true,
          isStarred: false,
          isDeleted: false,
          isDraft: false,
          isAnswered: false,
          isForwarded: false,
          attachments: [],
          hasAttachments: false,
          isSynced: true,
          size: mergedBody.length,
          createdAt: Date.now(),
          updatedAt: Date.now()
        };
        if (this.storageService) {
          await this.storageService.saveEmail(sentEmail);
        }
        router.back();
      } else {
        this.errorMessage = Utils.resourceToString(this.context, $r('app.string.msg_send_fail'));
      }
    } catch {
      this.errorMessage = Utils.resourceToString(this.context, $r('app.string.msg_send_fail'));
    } finally {
      this.isSending = false;
    }
  }

  async saveDraft(): Promise<void> {
    if (!this.fromAccount || !this.storageService) return;

    const mergedBody = this.buildMergedBody();
    try {
      const draftFolderId = this.fromAccount.id + '_Drafts';
      const draftEmail: Email = {
        id: Utils.generateId(),
        accountId: this.fromAccount.id,
        folderId: draftFolderId,
        messageId: Utils.generateId(),
        subject: this.subject || Utils.resourceToString(this.context, $r('app.string.msg_no_subject')),
        from: { name: this.fromAccount.displayName, address: this.fromAccount.email },
        to: this.to ? [{ address: this.to, name: this.to.split('@')[0] }] : [],
        date: Date.now(),
        bodyText: mergedBody,
        preview: mergedBody.substring(0, 100),
        isRead: true,
        isStarred: false,
        isDeleted: false,
        isDraft: true,
        isAnswered: false,
        isForwarded: false,
        attachments: [],
        hasAttachments: false,
        isSynced: false,
        size: mergedBody.length,
        createdAt: Date.now(),
        updatedAt: Date.now()
      };
      await this.storageService.saveEmail(draftEmail);
      router.back();
    } catch (error) {
      this.logger.e('Failed to save draft:', error);
    }
  }

  async addAttachment(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const uris: string[] = await documentPicker.select();
      if (!uris || uris.length === 0) return;
      for (const uri of uris) {
        if (!uri) continue;
        const name = uri.substring(uri.lastIndexOf('/') + 1) || 'file';
        const size = 0;
        const attach: Attachment = {
          id: Utils.generateId(),
          emailId: '',
          filename: name,
          contentType: 'application/octet-stream',
          size: size,
          disposition: 'attachment',
          isDownloaded: false,
          localPath: uri,
          createdAt: Date.now()
        };
        const existing = this.attachments.find(a => a.filename === name);
        if (!existing) this.attachments.push(attach);
      }
    } catch (error) {
      this.logger.e('Add attachment error:', error);
    }
  }

  removeAttachment(index: number): void {
    const filtered: Attachment[] = [];
    for (let i = 0; i < this.attachments.length; i++) {
      if (i !== index) filtered.push(this.attachments[i]);
    }
    this.attachments = filtered;
  }

  build() {
    Column() {
      Blank().height(0).margin({ top: this.themeVersion * 0 })
      Row() {
        Button($r('app.string.btn_cancel'))
          .fontSize(16)
          .fontColor(this.theme().textPrimary)
          .backgroundColor('transparent')
          .onClick(() => this.goBack())

        Text(this.getModeTitle())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button() {
          if (this.isSending) {
            Row({ space: 6 }) {
              LoadingProgress().width(16).height(16).color(this.theme().primary)
              Text($r('app.string.btn_sending')).fontSize(15).fontColor(this.theme().textHint)
            }
          } else {
            Text($r('app.string.btn_send')).fontSize(15).fontColor(this.theme().primary)
          }
        }
          .backgroundColor('transparent')
          .enabled(!this.isSending)
          .onClick(() => { void this.sendEmail(); })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .backgroundColor(this.theme().surface)

      Column({ space: 0 }) {
        Row() {
          Text($r('app.string.label_from'))
            .fontSize(14)
            .fontColor(this.theme().textSecondary)
            .width(60)
          if (this.fromAccount) {
            Text(this.fromAccount.displayName || this.fromAccount.email)
              .fontSize(14)
              .fontColor(this.theme().textPrimary)
              .layoutWeight(1)
            if (this.accounts.length > 1) {
              Text('▼')
                .fontSize(10)
                .fontColor(this.theme().textHint)
                .margin({ left: 4 })
            }
          }
        }
        .width('100%')
        .padding(12)
        .border({ width: { bottom: 1 }, color: this.theme().divider })
        .onClick(() => {
          if (this.accounts.length > 1) this.showAccountPicker = !this.showAccountPicker;
        })

        if (this.showAccountPicker) {
          Column() {
            ForEach(this.accounts, (acc: Account) => {
              Row() {
                Text(this.getInitial(acc))
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .width(28).height(28).borderRadius(14)
                  .textAlign(TextAlign.Center)
                  .backgroundColor(acc.id === this.fromAccount?.id ? this.theme().primary : this.theme().textHint)
                Text(acc.displayName || acc.email)
                  .fontSize(14)
                  .fontColor(acc.id === this.fromAccount?.id ? this.theme().primary : this.theme().textPrimary)
                  .layoutWeight(1)
                  .margin({ left: 8 })
                if (acc.id === this.fromAccount?.id) {
                  Text('✓').fontSize(14).fontColor(this.theme().primary)
                }
              }
              .width('100%')
              .height(40)
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                this.fromAccount = acc;
                this.showAccountPicker = false;
                if (this.mode === 'new' && acc.signature) {
                  this.composeBody = '\n\n--\n' + acc.signature;
                }
              })
            }, (acc: Account) => acc.id)
          }
          .backgroundColor(this.theme().surface)
          .border({ width: { bottom: 1 }, color: this.theme().divider })
        }

        Row({ space: 8 }) {
          Text($r('app.string.label_to'))
            .fontSize(14)
            .fontColor(this.theme().textSecondary)
            .width(60)

          Column() {
            TextInput({ placeholder: Utils.resourceToString(this.context, $r('app.string.placeholder_recipient')), text: this.to })
              .fontSize(14)
              .fontColor(this.theme().textPrimary)
              .width('100%')
              .backgroundColor('transparent')
              .placeholderColor(this.theme().textHint)
              .onChange((value: string) => {
                this.to = value;
                this.activeField = 'to';
                void this.loadContacts(this.getLastAddress(value));
              })
              .onBlur(() => {
                setTimeout(() => { this.showContactDropdown = false; }, 200);
              })

            if (this.showContactDropdown && this.activeField === 'to') {
              this.ContactDropdown()
            }
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding(12)
        .border({ width: { bottom: 1 }, color: this.theme().divider })

        if (this.showCc) {
          Row({ space: 8 }) {
            Text($r('app.string.label_cc'))
              .fontSize(14)
              .fontColor(this.theme().textSecondary)
              .width(60)

            Column() {
              TextInput({ placeholder: Utils.resourceToString(this.context, $r('app.string.placeholder_cc')), text: this.cc })
                .fontSize(14)
                .width('100%')
                .backgroundColor('transparent')
                .placeholderColor(this.theme().textHint)
                .onChange((value: string) => {
                  this.cc = value;
                  this.activeField = 'cc';
                  void this.loadContacts(this.getLastAddress(value));
                })
                .onBlur(() => {
                  setTimeout(() => { this.showContactDropdown = false; }, 200);
                })

              if (this.showContactDropdown && this.activeField === 'cc') {
                this.ContactDropdown()
              }
            }
            .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .border({ width: { bottom: 1 }, color: this.theme().divider })
        }

        if (this.showBcc) {
          Row({ space: 8 }) {
            Text($r('app.string.label_bcc'))
              .fontSize(14)
              .fontColor(this.theme().textSecondary)
              .width(60)

            Column() {
              TextInput({ placeholder: Utils.resourceToString(this.context, $r('app.string.placeholder_bcc')), text: this.bcc })
                .fontSize(14)
                .width('100%')
                .backgroundColor('transparent')
                .placeholderColor(this.theme().textHint)
                .onChange((value: string) => {
                  this.bcc = value;
                  this.activeField = 'bcc';
                  void this.loadContacts(this.getLastAddress(value));
                })
                .onBlur(() => {
                  setTimeout(() => { this.showContactDropdown = false; }, 200);
                })

              if (this.showContactDropdown && this.activeField === 'bcc') {
                this.ContactDropdown()
              }
            }
            .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .border({ width: { bottom: 1 }, color: this.theme().divider })
        }

        if (!this.showCc || !this.showBcc) {
          Row({ space: 16 }) {
            if (!this.showCc) {
              Text($r('app.string.label_add_cc'))
                .fontSize(14)
                .fontColor(this.theme().primary)
                .onClick(() => this.showCc = true)
            }
            if (!this.showBcc) {
              Text($r('app.string.label_add_bcc'))
                .fontSize(14)
                .fontColor(this.theme().primary)
                .onClick(() => this.showBcc = true)
            }
          }
          .width('100%')
          .padding({ left: 72, top: 8, bottom: 8 })
          .border({ width: { bottom: 1 }, color: this.theme().divider })
        }

        TextInput({ placeholder: Utils.resourceToString(this.context, $r('app.string.placeholder_subject')), text: this.subject })
          .fontSize(16)
          .fontColor(this.theme().textPrimary)
          .placeholderColor(this.theme().textHint)
          .padding(12)
          .backgroundColor('transparent')
          .width('100%')
          .border({ width: { bottom: 1 }, color: this.theme().divider })
          .onChange((value: string) => this.subject = value)

        Column() {
          TextArea({
            placeholder: Utils.resourceToString(this.context, $r('app.string.placeholder_body')),
            text: this.composeBody
          })
            .width('100%')
            .layoutWeight(1)
            .constraintSize({ minHeight: 160 })
            .padding(12)
            .borderRadius(10)
            .backgroundColor(this.theme().background)
            .fontSize(16)
            .fontColor(this.theme().textPrimary)
            .placeholderColor(this.theme().textHint)
            .lineHeight(24)
            .copyOption(CopyOptions.LocalDevice)
            .wordBreak(WordBreak.BREAK_ALL)
            .onChange((value: string) => {
              this.composeBody = value;
            })

          if (this.quotedBlock.length > 0) {
            Column({ space: 6 }) {
              Text($r('app.string.compose_quoted_title'))
                .fontSize(12)
                .fontColor(this.theme().textHint)
                .width('100%')
                .padding({ left: 4, top: 8 })
              Scroll() {
                RichText(this.quotedRichHtml.length > 0 ? this.quotedRichHtml : buildEmailBodyHtmlFragment(undefined, this.quotedBlock))
                  .width('100%')
                  .padding(12)
                  .backgroundColor(this.theme().background)
                  .borderRadius(8)
                  .border({ width: { left: 3 }, color: this.theme().primary })
              }
              .width('100%')
              .constraintSize({ maxHeight: 220 })
              .scrollBar(BarState.Auto)
            }
            .width('100%')
            .padding({ left: 8, right: 8, bottom: 8 })
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .layoutWeight(1)
      .backgroundColor(this.theme().surface)

      if (this.attachments.length > 0) {
        Column() {
          ForEach(this.attachments, (att: Attachment, index: number | undefined) => {
            Row() {
              Image($r('app.media.icon_file'))
                .width(20).height(20)
                .fillColor(this.theme().primary)
              Text(att.filename)
                .fontSize(13)
                .fontColor(this.theme().textPrimary)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ left: 8 })
              Text(Utils.formatFileSize(att.size))
                .fontSize(11)
                .fontColor(this.theme().textHint)
                .margin({ left: 8 })
              Button() {
                Image($r('app.media.icon_close')).width(16).height(16)
              }
                .width(28).height(28)
                .backgroundColor('transparent')
                .onClick(() => this.removeAttachment(index!))
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(this.theme().cardBackground)
            .borderRadius(8)
            .margin({ bottom: 4 })
          }, (att: Attachment) => att.id)
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }

      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor(this.theme().error)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }

      Row() {
        Button() {
          Row({ space: 6 }) {
            Image($r('app.media.ic_attach')).width(18).height(18).fillColor(this.theme().textSecondary)
            Text($r('app.string.btn_attachment'))
              .fontSize(14)
              .fontColor(this.theme().textSecondary)
          }
        }
          .backgroundColor('transparent')
          .onClick(() => { void this.addAttachment(); })

        Blank()

        Button() {
          Row({ space: 6 }) {
            Image($r('app.media.ic_save')).width(18).height(18).fillColor(this.theme().textSecondary)
            Text($r('app.string.btn_save_draft'))
              .fontSize(14)
              .fontColor(this.theme().textSecondary)
          }
        }
          .backgroundColor('transparent')
          .onClick(() => { void this.saveDraft(); })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.theme().surface)
      .border({ width: { top: 1 }, color: this.theme().divider })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().background)
  }

  private getLastAddress(value: string): string {
    const parts = value.split(',');
    const last = parts[parts.length - 1].trim();
    return last.split('@')[0];
  }

  @Builder
  ContactDropdown() {
    Column() {
      ForEach(this.contactSuggestions, (contact: ContactSuggestion) => {
        Row() {
          Text(contact.name)
            .fontSize(14).fontColor(this.theme().textPrimary)
            .maxLines(1).layoutWeight(1)
          Text(contact.email)
            .fontSize(12).fontColor(this.theme().textHint)
            .maxLines(1)
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.theme().surface)
        .onClick(() => this.selectContact(contact))
      }, (c: ContactSuggestion) => c.email)
    }
    .width('100%')
    .backgroundColor(this.theme().background)
    .border({ width: 1, color: this.theme().divider })
    .borderRadius(6)
  }

  parseAddressList(input: string): EmailAddress[] {
    const parts: string[] = input.split(',');
    const result: EmailAddress[] = [];
    for (let i = 0; i < parts.length; i++) {
      const trimmed = parts[i].trim();
      if (trimmed) {
        const addr: EmailAddress = { address: trimmed, name: trimmed.split('@')[0] };
        result.push(addr);
      }
    }
    return result;
  }

  getInitial(acc: Account): string {
    return (acc.displayName || acc.email).charAt(0).toUpperCase();
  }

  getModeTitle(): string {
    if (this.mode === 'reply') return Utils.resourceToString(this.context, $r('app.string.title_reply'));
    if (this.mode === 'replyAll') return Utils.resourceToString(this.context, $r('app.string.title_reply_all'));
    if (this.mode === 'forward') return Utils.resourceToString(this.context, $r('app.string.title_forward'));
    return Utils.resourceToString(this.context, $r('app.string.title_new_email'));
  }
}
