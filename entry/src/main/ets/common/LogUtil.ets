import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG_PREFIX = 'MuJieEmail';

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3
}

let currentLogLevel: LogLevel = LogLevel.DEBUG;

export function setLogLevel(level: LogLevel): void {
  currentLogLevel = level;
}

export function getLogLevel(): LogLevel {
  return currentLogLevel;
}

export type LogArg = string | number | boolean | null | Error;

export class LogUtil {
  private tag: string;

  constructor(tag: string) {
    this.tag = `${TAG_PREFIX}_${tag}`;
  }

  d(message: string, ...args: LogArg[]): void {
    if (currentLogLevel > LogLevel.DEBUG) return;
    hilog.debug(DOMAIN, this.tag, this.formatMessage(message, args));
  }

  i(message: string, ...args: LogArg[]): void {
    if (currentLogLevel > LogLevel.INFO) return;
    hilog.info(DOMAIN, this.tag, this.formatMessage(message, args));
  }

  w(message: string, ...args: LogArg[]): void {
    if (currentLogLevel > LogLevel.WARN) return;
    hilog.warn(DOMAIN, this.tag, this.formatMessage(message, args));
  }

  e(message: string, ...args: LogArg[]): void {
    if (currentLogLevel > LogLevel.ERROR) return;
    hilog.error(DOMAIN, this.tag, this.formatMessage(message, args));
  }

  private formatMessage(message: string, args: LogArg[]): string {
    if (args.length === 0) {
      return message;
    }
    const mutableArgs: LogArg[] = [];
    for (let i = 0; i < args.length; i++) {
      mutableArgs.push(args[i]);
    }
    try {
      return message.replace(/%\{public\}s/g, () => {
        if (mutableArgs.length === 0) {
          return '';
        }
        const arg = mutableArgs[0];
        for (let j = 1; j < mutableArgs.length; j++) {
          mutableArgs[j - 1] = mutableArgs[j];
        }
        mutableArgs.pop();
        if (arg === null || arg === undefined) {
          return 'null';
        }
        if (arg instanceof Error) {
          return arg.message;
        }
        return String(arg);
      });
    } catch {
      return message;
    }
  }

  static getLogger(tag: string): LogUtil {
    return new LogUtil(tag);
  }
}

export const logger = new LogUtil('Main');