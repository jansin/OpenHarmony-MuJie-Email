import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { EmailTheme, DARK_THEME, LIGHT_THEME } from '../common/Theme';
import { Utils } from '../common/Utils';
import { StorageService } from '../services/StorageService';
import { AccountService } from '../services/AccountService';
import { FilterService } from '../services/FilterService';
import { FilterRule, FilterCondition, FilterAction, FilterConditionType, FilterActionType } from '../models/FilterRule';
import { ToastUtil } from '../common/ToastUtil';
import { Folder } from '../models/Folder';

@Entry
@Component
struct FilterRules {
  private context = getContext(this) as common.UIAbilityContext;
  @State rules: FilterRule[] = [];
  @State themeVersion: number = 0;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @State folders: Folder[] = [];
  @State isLoading: boolean = true;
  @State showAddDialog: boolean = false;
  @State editRule: FilterRule | null = null;
  private storageService: StorageService | null = null;
  private filterService: FilterService | null = null;
  private theme(): EmailTheme {
    return this.isDarkMode ? DARK_THEME : LIGHT_THEME;
  }



  aboutToAppear(): void {
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
      const ctx = getContext(this) as common.UIAbilityContext;
      this.storageService = StorageService.getInstance(ctx);
      await this.storageService.initialize();
      this.filterService = FilterService.getInstance(this.storageService);
      await this.loadRules();
    } catch (e) {
    } finally {
      this.isLoading = false;
    }
  }

  async loadRules(): Promise<void> {
    if (!this.storageService || !this.filterService) return;
    const accounts = await this.storageService.getAccounts();
    if (accounts.length === 0) return;
    const defaultAccount = accounts[0];
    this.rules = await this.filterService.getRules(defaultAccount.id);
    this.folders = await this.storageService.getFoldersByAccountId(defaultAccount.id);
  }

  toggleRule(rule: FilterRule): void {
    if (!this.filterService) return;
    rule.enabled = !rule.enabled;
    rule.updatedAt = Date.now();
    this.filterService.saveRule(rule);
    const r = this.rules;
    this.rules = [];
    this.rules = r;
  }

  deleteRule(ruleId: string): void {
    if (!this.filterService) return;
    AlertDialog.show({
      title: Utils.resourceToString(this.context, $r('app.string.filter_delete_title')),
      message: Utils.resourceToString(this.context, $r('app.string.filter_delete_msg')),
      autoCancel: true,
      primaryButton: {
        value: Utils.resourceToString(this.context, $r('app.string.btn_cancel')),
        action: () => {}
      },
      secondaryButton: {
        value: Utils.resourceToString(this.context, $r('app.string.btn_delete')),
        fontColor: '#D93025',
        action: async () => {
          await this.filterService!.deleteRule(ruleId);
          await this.loadRules();
          ToastUtil.showSuccess(Utils.resourceToString(this.context, $r('app.string.filter_deleted')));
        }
      }
    });
  }

  build() {
    Column() {
      Row() {
        Button() {
          Image($r('app.media.icon_arrow_left')).width(20).height(20)
        }.width(48).height(48).backgroundColor('transparent').onClick(() => router.back())
        Text($r('app.string.filter_page_title')).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(this.theme().textPrimary).layoutWeight(1).textAlign(TextAlign.Center)
        Button('+').fontSize(24).fontColor(this.theme().primary)
          .backgroundColor('transparent').width(48).height(48)
          .onClick(() => { this.editRule = null; this.showAddDialog = true; })
      }
      .width('100%').height(56).padding({ left: 4, right: 4 })
      .backgroundColor(this.theme().surface)
      .border({ width: { bottom: 1 }, color: this.theme().divider })

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme().primary)
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.rules.length === 0) {
        Column({ space: 12 }) {
          Text($r('app.string.filter_no_rules')).fontSize(16).fontColor(this.theme().textSecondary)
          Text($r('app.string.filter_add_hint')).fontSize(14).fontColor(this.theme().textHint)
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.rules, (rule: FilterRule) => {
            ListItem() {
              Row() {
                Column({ space: 4 }) {
                  Text(rule.name).fontSize(15).fontWeight(FontWeight.Medium)
                    .fontColor(this.theme().textPrimary).maxLines(1)
                  Text(this.ruleSummary(rule)).fontSize(12)
                    .fontColor(this.theme().textHint).maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
                  .selectedColor(this.theme().primary)
                  .onChange(() => this.toggleRule(rule))

                Button($r('app.string.btn_delete')).fontSize(14).fontColor(this.theme().error)
                  .backgroundColor('transparent').width(36).height(36)
                  .onClick(() => this.deleteRule(rule.id))
              }
              .width('100%').padding(16)
              .backgroundColor(this.theme().surface)
              .borderRadius(12)
            }
          }, (r: FilterRule) => r.id)
        }
        .width('100%').layoutWeight(1).padding(16)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.theme().background)
  }

  ruleSummary(rule: FilterRule): string {
    const parts = rule.conditions.map(c => {
      const label = c.type === 'from' ? Utils.resourceToString(this.context, $r('app.string.filter_cond_from')) : c.type === 'to' ? Utils.resourceToString(this.context, $r('app.string.filter_cond_to')) : c.type === 'subject' ? Utils.resourceToString(this.context, $r('app.string.filter_cond_subject')) : Utils.resourceToString(this.context, $r('app.string.filter_cond_body'));
      return label + ':' + c.keyword;
    });
    return parts.join(Utils.resourceToString(this.context, $r('app.string.filter_and'))) + Utils.resourceToString(this.context, $r('app.string.filter_arrow')) + this.actionLabel(rule.action);
  }

  actionLabel(action: FilterAction): string {
    if (action.type === 'delete') return Utils.resourceToString(this.context, $r('app.string.filter_action_delete'));
    if (action.type === 'mark_read') return Utils.resourceToString(this.context, $r('app.string.filter_action_mark_read'));
    if (action.type === 'mark_starred') return Utils.resourceToString(this.context, $r('app.string.filter_action_mark_starred'));
    if (action.type === 'archive') return Utils.resourceToString(this.context, $r('app.string.filter_action_archive'));
    if (action.type === 'move_to_folder') return Utils.resourceToString(this.context, $r('app.string.filter_action_move'));
    return action.type;
  }
}
