import { Email } from '../models/Email';
import { Utils } from '../common/Utils';
import { EmailTheme, DARK_THEME, LIGHT_THEME } from '../common/Theme';
import common from '@ohos.app.ability.common';

@Component
export struct EmailItem {
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  private context = getContext(this) as common.UIAbilityContext;
  @Prop email: Email = { id: '', accountId: '', folderId: '', messageId: '', subject: '', from: { address: '' }, to: [], date: 0, preview: '', isRead: false, isStarred: false, isDeleted: false, isDraft: false, isAnswered: false, isForwarded: false, attachments: [], hasAttachments: false, isSynced: false, size: 0, createdAt: 0, updatedAt: 0 };
  @Prop isSelected: boolean = false;
  @Prop isSelectionMode: boolean = false;
  onEmailSelect?: (emailId: string) => void;
  onEmailClick?: (email: Email) => void;
  onEmailStarToggle?: (emailId: string, isStarred: boolean) => void;

  private displayFromPrimary(): string {
    const n = Utils.coerceUiString(this.email.from.name);
    const a = Utils.coerceUiString(this.email.from.address);
    return n.length > 0 ? n : a;
  }

  private displayFromSecondary(): string {
    return Utils.coerceUiString(this.email.from.address);
  }

  private displaySubject(): string {
    const s = Utils.coerceUiString(this.email.subject);
    return s.length > 0 ? s : Utils.resourceToString(this.context, $r('app.string.msg_no_subject'));
  }

  private displayPreview(): string {
    return Utils.coerceUiString(this.email.preview);
  }
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





  build() {
    Row() {
      if (this.isSelectionMode) {
        Checkbox()
          .select(this.isSelected)
          .onChange(() => {
            if (this.onEmailSelect) {
              this.onEmailSelect(this.email.id);
            }
          })
          .margin({ right: 8, left: 4 })
      } else {
        Text(this.getInitial())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.avatarColor(this.displayFromPrimary()))
          .textAlign(TextAlign.Center)
          .margin({ right: 12 })
          .flexShrink(0)
      }

      Column() {
        Row() {
          Text(this.displayFromPrimary())
            .fontSize(15)
            .fontWeight(this.email.isRead ? FontWeight.Normal : FontWeight.Bold)
            .fontColor(this.theme().textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(Utils.formatDate(this.context, this.email.date))
            .fontSize(12)
            .fontColor(this.theme().textHint)
            .flexShrink(0)
            .margin({ left: 8 })
        }
        .width('100%')

        Row() {
          Text(this.displaySubject())
            .fontSize(14)
            .fontWeight(this.email.isRead ? FontWeight.Normal : FontWeight.Bold)
            .fontColor(this.email.isRead ? this.theme().textSecondary : this.theme().textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Row({ space: 2 }) {
            if (this.email.isAnswered) {
              Image($r('app.media.ic_reply'))
                .width(12).height(12)
                .fillColor(this.theme().textHint)
            }
            if (this.email.isForwarded) {
              Image($r('app.media.ic_forward'))
                .width(12).height(12)
                .fillColor(this.theme().textHint)
            }
            if (this.email.hasAttachments) {
              Image($r('app.media.ic_attach'))
                .width(12).height(12)
                .fillColor(this.theme().textHint)
            }

            Button() {
              Text(this.email.isStarred ? '\u2605' : '\u2606')
                .fontSize(16)
                .fontColor(this.email.isStarred ? '#FF9500' : this.theme().textHint)
            }
            .width(28).height(28).backgroundColor('transparent')
            .enabled(!this.isSelectionMode)
            .onClick(() => {
              if (this.onEmailStarToggle) {
                this.onEmailStarToggle(this.email.id, this.email.isStarred);
              }
            })
          }
          .flexShrink(0)
        }
        .width('100%')
        .margin({ top: 2 })

        Row({ space: 6 }) {
          Text(this.displayPreview())
            .fontSize(13)
            .fontColor(this.theme().textHint)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .border({ width: { bottom: 1 }, color: this.theme().divider })
    .backgroundColor(this.getBackgroundColor())
    .onClick(() => {
      if (this.onEmailClick) {
        this.onEmailClick(this.email);
      }
    })
  }

  getInitial(): string {
    const name = this.displayFromPrimary();
    if (!name || name.length === 0) {
      return '?';
    }
    return name.charAt(0).toUpperCase();
  }

  getBackgroundColor(): string {
    if (this.isSelected) {
      return this.theme().selectedItem;
    }
    if (!this.email.isRead) {
      return this.theme().unreadBackground;
    }
    return 'transparent';
  }
}
