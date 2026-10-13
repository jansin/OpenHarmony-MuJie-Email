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

import { getLogger } from "./log";
import { CMError, ErrorCode } from "../api";
import type { MimeParams, IBuffer } from "../api";
import { decodeCharset, decodeRFC2047, decodeUtf7 } from "./encodings";
import { createBuffer } from './file_stream';

const logger = getLogger("common")

export function delay(timeout: number): Promise<void> {
  return new Promise((resolve, reject) => {
    setTimeout(() => resolve(), timeout);
  });
}

export function assert(
  condition: boolean,
  message: string = "assert failed!"
): asserts condition {
  if (!condition) {
    throw new CMError(message, ErrorCode.Error);
  }
}

export function isDigit(s: string): boolean {
  const n = s.charCodeAt(0);
  return n >= 0x30 && n <= 0x39;
}

export function imapListToMap(list: string[]): MimeParams {
  const map: MimeParams = {};
  for (let i = 0; i < list.length; i += 2) {
    const name = list[i].toLowerCase();
    const value = name == 'charset' ? list[i + 1].toLowerCase() : decodeRFC2047(list[i + 1]);
    map[name] = value;
  }
  return map;
}

export class EventHandler {
  handlers: Map<string, Function[]> = new Map();
  on(event: string, callback: Function): void {
    if (!this.handlers.has(event)) {
      this.handlers.set(event, []);
    }
    this.handlers.get(event)?.push(callback);
  }
  emit(event: string, ...args: unknown[]): void {
    this.handlers.get(event)?.forEach(callback => {
      callback(...args);
    });
  }
  once(event: string, callback: Function): void {
    const func = (...args: unknown[]): void => {
      callback(...args);
      this.off(event, func);
    };
    this.on(event, func);
  }
  off(event: string, callback: Function): void {
    const callbacks = this.handlers.get(event);
    if (callbacks) {
      const idx = callbacks.findIndex(cb => cb === callback);
      if (idx >= 0) {
        callbacks.splice(idx, 1);
      }
    }
  }
}

/*
* 简单的LRU缓存
 */
export class LRUCache<T> {
  _cache: T[] = [];
  _maxSize: number;
  _clearTimer?: number;
  _clearTimeout: number;
  _keyFunc: (v: T) => string;

  constructor(keyFunc: (v: T) => string, maxSize: number = 10, clearTimeout: number = 10 * 1000) {
    this._keyFunc = keyFunc;
    this._maxSize = maxSize;
    this._clearTimeout = clearTimeout;
  }

  clean(): void {
    if (!this._clearTimer) {
      this._clearTimer = setInterval(() => {
        if (this._cache.length > 0) {
          this._cache.pop();
        } else {
          clearInterval(this._clearTimer);
          this._clearTimer = undefined;
        }
      }, this._clearTimeout)
    }
  }

  has(key: string): boolean {
    for (const value of this._cache) {
      if (this._keyFunc(value) == key) {
        return true;
      }
    }
    return false;
  }

  remove(key: string): boolean {
    let i = 0;
    for (const value of this._cache) {
      if (this._keyFunc(value) == key) {
        // 找到则将元素移除
        this._cache.splice(i, 1);
        return true;
      }
      i += 1;
    }
    return false;
  }

  get(key: string): T | undefined {
    let i = 0;
    for (const value of this._cache) {
      if (this._keyFunc(value) == key) {
        // 找到了，将节点放到列表前面
        this._cache.splice(i, 1);
        this._cache.unshift(value);
        return value;
      }
      i += 1;
    }
  }

  add(value: T): void {
    this._cache.unshift(value);
    if (this._cache.length > this._maxSize) {
      this._cache.pop();
    }
    this.clean();
  }
}

export const CRLF = new Uint8Array([13, 10]);
export const SP = new Uint8Array([32]);

export function wrapCallback<T>(
  p: Promise<T>,
  callback?: (data: T) => void,
  onError?: (err: CMError) => void
): Promise<T> | void {
  if (!callback) {
    return p;
  } else {
    p.then((data: T) => callback(data)).catch((err: CMError) => onError?.(err));
  }
}

export function parseDateString(rd: string): Date {
  if (rd && rd.length > 0) {
    //Thu,  1 Feb 2024 17:48:33 +0800 (CST)
    //Wed, 31 Jan 2024 18:19:03 +0800 (CST)
    // 部分时间格式，有2个空格以上，统一处理为一个空格分隔
    rd = rd.replace("  ", " ");
    let ms = 0;
    if (rd.search("CST") != -1) {
      //中美洲标准时间
      //CST时间解析不出来.
      let rd2 = rd.replace("CST", "UTC");
      let date = new Date(Date.parse(rd2));
      let arr = rd2.split(" ");
      ms = date.getTime();
      // 6个: 22 Nov 2023 00:28:53 +0800 (UTC)
      // 7个: wed 22 Nov 2023 00:28:53 +0800 (UTC)
      // 获取时区字符串 类似:+0800
      if (arr.length == 7 || arr.length == 6) {
        let timeZoneOffsetStr = arr[arr.length - 2];
        let timeZoneOffset = Number.parseInt(timeZoneOffsetStr);
        let offsetMs = (timeZoneOffset / 100) * 3600 * 1000;
        let fixedMs = ms - offsetMs;
        return new Date(fixedMs);
      }
    } else if (rd.search("CDT") != -1) {
      //
      let rd2 = rd.replace("CDT", "UTC");
      let date = new Date(Date.parse(rd2));
      let arr = rd2.split(" ");
      ms = date.getTime();
      if (arr.length == 7 || arr.length == 6) {
        let timeZoneOffsetStr = arr[arr.length - 2];
        let timeZoneOffset = Number.parseInt(timeZoneOffsetStr);
        let offsetMs = (timeZoneOffset / 100) * 3600 * 1000;
        let fixedMs = ms - offsetMs;
        return new Date(fixedMs);
      }
    } else {
      //utc时间直接解析
      let date = new Date(Date.parse(rd));
      return date;
      ms = date.getTime();
      if (ms == null || ms == 0) {
      }
    }
    //毫秒数
    // hilog.debug(0x0,"MAIL",`msgNo: ${msgNo},date: ${rd} -> ${entity.receivedDate}`)
  }
  //TODO
  return new Date("1970-01-01");
}

export async function* stream2lines(
  stream: AsyncIterable<string>
): AsyncIterable<string> {
  logger.trace("stream2lines")
  let s = "";
  for await (const chunk of stream) {
    let start = 0;
    let i = chunk.indexOf("\r\n");
    while (i >= 0) {
      const res = s + chunk.substring(start, i);
      start = i + 2;
      s = "";
      yield res;
      i = chunk.indexOf("\r\n", start);
    }
    s = s + chunk.substring(start);
  }
  if (s.length > 0) {
    yield s;
  }
}

export function stream2buffer(
  stream: AsyncIterable<string | Uint8Array>
): IBuffer {
  let b = createBuffer({});
  (async function (): Promise<void> {
    for await (const chunk of stream) {
      b.feed(chunk);
    }
    b.end();
  })();
  return b;
}

export async function* transformStream<T, U>(
  stream: AsyncIterable<U>,
  transformer: (current: U) => Promise<[T | undefined, U | undefined]>,
  join?: (a: U, b: U) => U
): AsyncIterable<T> {
  let buff: U | undefined = undefined;
  for await (const chunk of stream) {
    if (buff !== undefined && join !== undefined) {
      buff = join(buff, chunk);
    } else {
      buff = chunk;
    }
    while (buff !== undefined) {
      const [result, remain] = await transformer(buff);
      if (!result) {
        break;
      }
      yield result;
      buff = remain;
    }
  }
}
