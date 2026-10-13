import { Email } from '../models/Email';
import { FilterRule, FilterCondition, FilterAction, FilterConditionType, FilterActionType } from '../models/FilterRule';
import { StorageService } from './StorageService';
import { Folder } from '../models/Folder';
import { FilterRuleRecord } from '../models/RecordTypes';

export class FilterService {
  private static instance: FilterService;
  private storageService: StorageService;

  private constructor(storageService: StorageService) {
    this.storageService = storageService;
  }

  static getInstance(storageService: StorageService): FilterService {
    if (!FilterService.instance) {
      FilterService.instance = new FilterService(storageService);
    }
    return FilterService.instance;
  }

  async getRules(accountId: string): Promise<FilterRule[]> {
    const raw = await this.storageService.getFilterRules(accountId);
    const result: FilterRule[] = [];
    for (const r of raw) {
      const rule: FilterRule = {
        id: r.id,
        accountId: r.accountId,
        name: r.name,
        enabled: r.enabled,
        conditions: JSON.parse(r.conditions) as FilterCondition[],
        action: JSON.parse(r.action) as FilterAction,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt
      };
      result.push(rule);
    }
    return result;
  }

  async saveRule(rule: FilterRule): Promise<void> {
    const record: FilterRuleRecord = {
      id: rule.id,
      accountId: rule.accountId,
      name: rule.name,
      enabled: rule.enabled,
      conditions: JSON.stringify(rule.conditions),
      action: JSON.stringify(rule.action),
      createdAt: rule.createdAt,
      updatedAt: rule.updatedAt
    };
    await this.storageService.saveFilterRule(record);
  }

  async deleteRule(ruleId: string): Promise<void> {
    await this.storageService.deleteFilterRule(ruleId);
  }

  async applyRules(email: Email, rules: FilterRule[], folders: Folder[]): Promise<FilterAction | null> {
    for (const rule of rules) {
      if (!rule.enabled) continue;
      if (this.matches(email, rule.conditions)) {
        return rule.action;
      }
    }
    return null;
  }

  private matches(email: Email, conditions: FilterCondition[]): boolean {
    if (conditions.length === 0) return false;
    for (const cond of conditions) {
      const keyword = cond.keyword.toLowerCase();
      let value = '';
      if (cond.type === FilterConditionType.FROM) {
        value = (email.from.name + ' ' + email.from.address).toLowerCase();
      } else if (cond.type === FilterConditionType.TO) {
        const toList = email.to || [];
        const parts: string[] = [];
        for (const a of toList) {
          parts.push(a.name + ' ' + a.address);
        }
        value = parts.join(' ').toLowerCase();
      } else if (cond.type === FilterConditionType.SUBJECT) {
        value = (email.subject || '').toLowerCase();
      } else if (cond.type === FilterConditionType.BODY) {
        value = ((email.bodyText || '') + ' ' + (email.bodyHtml || '')).toLowerCase();
      }
      if (value.indexOf(keyword) < 0) return false;
    }
    return true;
  }

  async processIncomingEmail(email: Email, rules: FilterRule[], folders: Folder[]): Promise<string | null> {
    const action = await this.applyRules(email, rules, folders);
    if (!action) return null;
    if (action.type === FilterActionType.DELETE) {
      return null;
    }
    if (action.type === FilterActionType.MARK_READ) {
      email.isRead = true;
    }
    if (action.type === FilterActionType.MARK_STARRED) {
      email.isStarred = true;
    }
    if (action.type === FilterActionType.ARCHIVE) {
      const archive = folders.find(f => f.type === 5);
      if (archive) email.folderId = archive.id;
    }
    if (action.type === FilterActionType.MOVE_TO_FOLDER && action.targetFolderId) {
      email.folderId = action.targetFolderId;
    }
    return action.type;
  }
}
