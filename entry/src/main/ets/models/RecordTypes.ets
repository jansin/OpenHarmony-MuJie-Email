export interface FilterRuleRecord {
  id: string;
  accountId: string;
  name: string;
  enabled: boolean;
  conditions: string;
  action: string;
  createdAt: number;
  updatedAt: number;
}

export interface ContactRecord {
  id: string;
  accountId: string;
  name: string;
  email: string;
  lastContactTime: number;
  contactCount: number;
  createdAt: number;
}

export interface ContactSuggestion {
  name: string;
  email: string;
}
