/* Copyright © 2023 - 2024 Coremail论客
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


import hilog from "@ohos.hilog";

function toString(args: unknown[], maxLength?: number): string {
  let s = args.map(v => {
    if (typeof v == "string") {
      return v;
    } else {
      try {
        const s = JSON.stringify(v);
        return s;
      } catch (e: unknown) {
        return v as string;
      }
    }
  }).join(" ");
  if (maxLength && maxLength > 0 && s.length > maxLength) {
    s = s.substring(0, maxLength);
  }
  return s;
}

let _logLevel: hilog.LogLevel = hilog.LogLevel.INFO;
export function setLogLevel(level: hilog.LogLevel): void {
  _logLevel = level;
}

export function showDebugLog(show: boolean): void {
  if (show) {
    _logLevel = hilog.LogLevel.DEBUG;
  } else if (_logLevel == hilog.LogLevel.DEBUG) {
    _logLevel = hilog.LogLevel.INFO;
  }
}

const _disabledLogNameList: string[] = [];

export function disableLogName(name: string): void {
  if (!_disabledLogNameList.includes(name)) {
    _disabledLogNameList.push(name);
  }
}

export function enableLogName(name: string): void {
  const index = _disabledLogNameList.indexOf(name);
  if (index >= 0) {
    _disabledLogNameList.splice(index, 1);
  }
}

function canLog(name: string, level: hilog.LogLevel): boolean {
  return level >= _logLevel && !_disabledLogNameList.includes(name);
}

export class Logger {
  prefix: string = "[mccm]";
  name: string;
  maxLength: number = 2000

  constructor(name: string) {
    this.prefix += name;
    this.name = name;
  }

  addPrefix(prefix: string): void {
    this.prefix += prefix;
  }

  setLineLimit(max: number): void {
    this.maxLength = max;
  }

  trace(...args: unknown[]): void {
    if (canLog(this.name, hilog.LogLevel.DEBUG)) {
      hilog.debug(2, this.prefix, toString(args));
    }
  }

  debug(...args: unknown[]): void {
    if (canLog(this.name, hilog.LogLevel.DEBUG)) {
      hilog.debug(1, this.prefix, toString(args, this.maxLength));
    }
  }

  info(...args: unknown[]): void {
    if (canLog(this.name, hilog.LogLevel.INFO)) {
      hilog.info(1, this.prefix, toString(args, this.maxLength));
    }
  }

  warn(...args: unknown[]): void {
    if (canLog(this.name, hilog.LogLevel.WARN)) {
      hilog.warn(1, this.prefix, toString(args, this.maxLength));
    }
  }

  error(...args: unknown[]): void {
    if (canLog(this.name, hilog.LogLevel.ERROR)) {
      hilog.error(1, this.prefix, toString(args));
    }
  }

  fatal(...args: unknown[]): void {
    if (canLog(this.name, hilog.LogLevel.FATAL)) {
      hilog.fatal(1, this.prefix, toString(args));
    }
  }

  log(...args: unknown[]): void {
    this.info(...args);
  }
}

export function getLogger(name: string): Logger {
  return new Logger(name);
}
