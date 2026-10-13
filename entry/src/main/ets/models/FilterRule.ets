export enum FilterConditionType {
  FROM = 'from',
  TO = 'to',
  SUBJECT = 'subject',
  BODY = 'body'
}

export enum FilterActionType {
  MOVE_TO_FOLDER = 'move_to_folder',
  MARK_READ = 'mark_read',
  MARK_STARRED = 'mark_starred',
  DELETE = 'delete',
  ARCHIVE = 'archive'
}

export interface FilterCondition {
  type: FilterConditionType;
  keyword: string;
}

export interface FilterAction {
  type: FilterActionType;
  targetFolderId?: string;
}

export interface FilterRule {
  id: string;
  accountId: string;
  name: string;
  enabled: boolean;
  conditions: FilterCondition[];
  action: FilterAction;
  createdAt: number;
  updatedAt: number;
}
