import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import { EmailTheme, DARK_THEME, LIGHT_THEME } from '../common/Theme';
import { Utils } from '../common/Utils';

@Entry
@Component
struct WebAuthHelp {
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  private context = getContext(this) as common.UIAbilityContext;
  private controller: webview.WebviewController = new webview.WebviewController();
  @State pageUrl: string = 'about:blank';
  @State barTitle: string = '';
  @State webLoading: boolean = true;
  private theme(): EmailTheme {
    return this.isDarkMode ? DARK_THEME : LIGHT_THEME;
  }



  aboutToAppear(): void {
    const p = router.getParams() as Record<string, Object>;
    if (p) {
      const u = p['url'] as string;
      if (u) {
        this.pageUrl = u;
      }
      const t = p['title'] as string;
      if (t) {
        this.barTitle = t;
      }
    }
    if (!this.barTitle) {
      this.barTitle = Utils.resourceToString(this.context, $r('app.string.title_auth_guide'));
    }
  }

  refreshPage(): void {
    this.webLoading = true;
    this.controller.refresh();
  }

  openInSystemBrowser(): void {
    if (!this.pageUrl || this.pageUrl === 'about:blank') {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    try {
      const want: Want = { uri: this.pageUrl, action: 'ohos.want.action.viewData' };
      ctx.startAbility(want);
    } catch (e) {}
  }

  build() {
    Column() {
      Row() {
        Button() {
          Image($r('app.media.icon_arrow_left')).width(20).height(20)
        }
          .width(48).height(48).backgroundColor('transparent')
          .onClick(() => router.back())
        Text(this.barTitle)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme().textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button($r('app.string.btn_refresh'))
          .fontSize(14)
          .fontColor(this.theme().primary)
          .backgroundColor('transparent')
          .height(48)
          .padding({ left: 8, right: 8 })
          .onClick(() => this.refreshPage())
      }
      .width('100%').height(56)
      .padding({ left: 4, right: 4 })
      .backgroundColor(this.theme().surface)
      .border({ width: { bottom: 1 }, color: this.theme().divider })

      Row() {
        Button($r('app.string.btn_open_browser'))
          .fontSize(13)
          .fontColor(this.theme().primary)
          .backgroundColor(this.theme().background)
          .layoutWeight(1)
          .height(40)
          .borderRadius(0)
          .enabled(this.pageUrl !== 'about:blank')
          .onClick(() => this.openInSystemBrowser())
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 4 })
      .backgroundColor(this.theme().surface)

      Stack() {
        Web({ src: this.pageUrl, controller: this.controller })
          .width('100%')
          .height('100%')
          .backgroundColor(this.theme().background)
          .onPageBegin(() => {
            this.webLoading = true;
          })
          .onPageEnd(() => {
            this.webLoading = false;
          })

        if (this.webLoading) {
          Column() {
            LoadingProgress().width(40).height(40).color(this.theme().primary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('#22000000')
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(this.theme().background)
  }
}
