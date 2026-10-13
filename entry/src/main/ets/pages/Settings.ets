import { router, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { EmailTheme, DARK_THEME, LIGHT_THEME, setEmailDarkMode } from '../common/Theme';
import { Utils } from '../common/Utils';
import { fileIo } from '@kit.CoreFileKit';
import { LogUtil } from '../common/LogUtil';

@Entry
@Component
struct Settings {
  private context = getContext(this) as common.UIAbilityContext;
  private logger: LogUtil = new LogUtil('Settings');
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @State syncInterval: number = 15;
  @State notificationEnabled: boolean = true;
  @State themeVersion: number = 0;
  private prefStore: preferences.Preferences | null = null;
  private theme(): EmailTheme {
    return this.isDarkMode ? DARK_THEME : LIGHT_THEME;
  }



  aboutToAppear(): void {
    this.loadSettings();
  }

  themeChangeHandler = (isDark: boolean): void => {
    this.isDarkMode = isDark;
    this.themeVersion++;
    this.updateStatusBarStyle();
  }

  onPageShow(): void {
    this.themeVersion++;
    this.updateStatusBarStyle();
  }

  onPageHide(): void {
  }

  async loadSettings(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.prefStore = await preferences.getPreferences(context, 'AppSettings');
      const darkVal = await this.prefStore.get('isDarkMode', false);
      const isDark = darkVal as boolean;
      setEmailDarkMode(isDark);
      this.isDarkMode = isDark;
      this.updateStatusBarStyle();
      const syncVal = await this.prefStore.get('syncInterval', 15);
      this.syncInterval = syncVal as number;
      const notifVal = await this.prefStore.get('notificationEnabled', true);
      this.notificationEnabled = notifVal as boolean;
    } catch (e) {
      this.logger.e('Failed to load settings:', e);
    }
  }

  async saveSetting(key: string, value: number | boolean | string): Promise<void> {
    if (!this.prefStore) return;
    try {
      await this.prefStore.put(key, value);
      await this.prefStore.flush();
    } catch (e) {
      this.logger.e('Failed to save setting:', e);
    }
  }

  goBack(): void { router.back(); }

  async clearCache(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const filesDir = context.filesDir;
      const cacheDir = context.cacheDir;
      try {
        const dir = filesDir + '/downloads/';
        const files = fileIo.listFileSync(dir);
        for (const f of files) {
          fileIo.unlinkSync(dir + f);
        }
        this.logger.i('Download cache cleared successfully');
      } catch (e) {
        this.logger.w('Download cache not found or cannot be cleared:', e);
      }
      try {
        const cacheFiles = fileIo.listFileSync(cacheDir);
        for (const f of cacheFiles) {
          fileIo.unlinkSync(cacheDir + '/' + f);
        }
        this.logger.i('App cache cleared successfully');
      } catch (e) {
        this.logger.w('App cache not found or cannot be cleared:', e);
      }
    } catch (error) {
      this.logger.e('Failed to clear cache:', error);
    }
  }

  onThemeChange(isOn: boolean): void {
    setEmailDarkMode(isOn);
    this.isDarkMode = isOn;
    this.updateStatusBarStyle();
    this.saveSetting('isDarkMode', isOn);
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

  onSyncChange(value: number): void {
    this.syncInterval = value;
    this.saveSetting('syncInterval', value);
  }

  onNotifyChange(isOn: boolean): void {
    this.notificationEnabled = isOn;
    this.saveSetting('notificationEnabled', isOn);
  }

  build() {
    Column() {
      Row() {
        Button() {
          Image($r('app.media.icon_arrow_left')).width(20).height(20)
        }
          .width(48).height(48).backgroundColor('transparent')
          .onClick(() => this.goBack())
        Text($r('app.string.title_settings'))
          .fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(this.theme().textPrimary).layoutWeight(1)
      }
      .width('100%').height(56).padding({ left: 4, right: 4 })
      .backgroundColor(this.theme().surface)
      .border({ width: { bottom: 1 }, color: this.theme().divider })

      Scroll() {
        Column({ space: 0 }) {
          Text($r('app.string.theme_title'))
            .fontSize(13).fontColor(this.theme().textHint)
            .width('100%').padding({ left: 16, top: 24, bottom: 8 })

          Column() {
            Row() {
              Row({ space: 12 }) {
                Image($r('app.media.ic_palette'))
                  .width(22).height(22)
                  .fillColor(this.theme().primary)
                Text($r('app.string.theme_dark_mode'))
                  .fontSize(16).fontColor(this.theme().textPrimary)
              }
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.isDarkMode })
                .selectedColor(this.theme().primary)
                .onChange((isOn: boolean) => this.onThemeChange(isOn))
            }
            .width('100%').height(56).padding({ left: 16, right: 16 })
          }
          .backgroundColor(this.theme().surface)
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          Text($r('app.string.sync_title'))
            .fontSize(13).fontColor(this.theme().textHint)
            .width('100%').padding({ left: 16, top: 24, bottom: 8 })

          Column() {
            Row() {
              Row({ space: 12 }) {
                Image($r('app.media.ic_sync'))
                  .width(22).height(22)
                  .fillColor(this.theme().primary)
                Text($r('app.string.sync_interval'))
                  .fontSize(16).fontColor(this.theme().textPrimary)
              }
              .layoutWeight(1)

              Text(this.syncInterval.toString() + Utils.resourceToString(this.context, $r('app.string.unit_minutes')))
                .fontSize(14).fontColor(this.theme().textSecondary)
            }
            .width('100%').height(52).padding({ left: 16, right: 16 })

            Row() {
              Slider({ value: this.syncInterval, min: 5, max: 60, step: 5 })
                .width('100%')
                .blockColor(this.theme().primary)
                .trackColor(this.theme().divider)
                .selectedColor(this.theme().primary)
                .onChange((val: number) => this.onSyncChange(val))
            }
            .width('100%').padding({ left: 16, right: 16, bottom: 12 })
          }
          .backgroundColor(this.theme().surface)
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          Text($r('app.string.notif_title'))
            .fontSize(13).fontColor(this.theme().textHint)
            .width('100%').padding({ left: 16, top: 24, bottom: 8 })

          Column() {
            Row() {
              Row({ space: 12 }) {
                Image($r('app.media.ic_notifications'))
                  .width(22).height(22)
                  .fillColor(this.theme().primary)
                Text($r('app.string.notif_new_email'))
                  .fontSize(16).fontColor(this.theme().textPrimary)
              }
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.notificationEnabled })
                .selectedColor(this.theme().primary)
                .onChange((isOn: boolean) => this.onNotifyChange(isOn))
            }
            .width('100%').height(56).padding({ left: 16, right: 16 })
          }
          .backgroundColor(this.theme().surface)
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          Text($r('app.string.about_title'))
            .fontSize(13).fontColor(this.theme().textHint)
            .width('100%').padding({ left: 16, top: 24, bottom: 8 })

          Column() {
            Row() {
              Row({ space: 12 }) {
                Image($r('app.media.ic_info'))
                  .width(22).height(22)
                  .fillColor(this.theme().primary)
                Text($r('app.string.about_version'))
                  .fontSize(16).fontColor(this.theme().textPrimary)
              }
              .layoutWeight(1)

              Text('1.0.0').fontSize(14).fontColor(this.theme().textSecondary)
            }
            .width('100%').height(56).padding({ left: 16, right: 16 })
          }
          .backgroundColor(this.theme().surface)
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          Button($r('app.string.btn_clear_cache'))
            .width('calc(100% - 32)')
            .height(48).fontSize(16)
            .fontColor(this.theme().error)
            .backgroundColor(this.theme().surface)
            .borderRadius(12)
            .margin({ left: 16, right: 16, top: 24, bottom: 32 })
            .onClick(() => { void this.clearCache(); })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(this.theme().background)
    }
    .width('100%').height('100%').backgroundColor(this.theme().background)
  }
}
