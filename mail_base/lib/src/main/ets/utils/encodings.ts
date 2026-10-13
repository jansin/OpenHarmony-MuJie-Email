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

import buffer from '@ohos.buffer';
import util from '@ohos.util';
import { getLogger } from './log';
import { CRLF, transformStream } from "./common";
import { IBuffer } from '../api';
import { findBuffer, joinBuffers, removeBufferData } from './buffer_utils';

export function decodeCharset(
  buff: Uint8Array,
  charset: string = "utf-8"
): string {
  if (buff.byteLength == 0) {
    return "";
  }
  try {
    let res = util.TextDecoder.create(charset).decodeWithStream(buff, {stream: false})
    if (res === undefined || res === null) {
      getLogger('encoding').error('deocde charset', res, charset, buff)
      res = "";
    }
    return res;
  }
  catch(e) {
    getLogger('encoding').error('deocde charset', charset, e)
    return ''
  }
}

export function encodeUtf8(s: string): Uint8Array {
  return new util.TextEncoder().encodeInto(s);
}

export function base64Encode(
  str: string | Uint8Array,
  maxPerline = 76,
  charset: buffer.BufferEncoding = "utf-8"
): string {
  let buff =
    typeof str == "string" ? buffer.from(str, charset) : buffer.from(str);
  let text = buff.toString("base64");
  if (maxPerline > 0 && maxPerline % 4 != 0) {
    maxPerline -= maxPerline % 4;
  }
  if (maxPerline > 0 && text.length > maxPerline) {
    const ss = [];
    let s = 0;
    let e = s + maxPerline;
    while (e < text.length) {
      ss.push(text.substring(s, e));
      s = e;
      e = s + maxPerline;
    }
    ss.push(text.substring(s));
    text = ss.join("\r\n");
  }
  return text;
}

export function base64Decode(
  str: string,
  charset: buffer.BufferEncoding = "utf-8"
): Uint8Array {
  const buff = buffer.from(str, 'base64');
  return new Uint8Array(buff.buffer)
}

// quoted-printable
export function qpEncode(
  str: string | Uint8Array,
  maxPerLine = 76,
  charset: buffer.BufferEncoding = "utf-8"
): string {
  let buff =
    typeof str == "string" ? buffer.from(str, charset) : buffer.from(str);
  const d = Array.from(buff.values());
  let s = d
    .map(v => {
      if (v == 0x3d || v <= 0x20 || v >= 0x7e) {
        return "=" + ("0" + v.toString(16).toUpperCase()).slice(-2);
      } else {
        return String.fromCharCode(v);
      }
    })
    .join("");
  if (maxPerLine > 0 && s.length > maxPerLine) {
    const ss = [];
    let i = 0;
    let e = i + 76;
    while (e < s.length) {
      if (s[e - 1] == "=") {
        e -= 1;
      } else if (s[e - 2] == "=") {
        e -= 2;
      }
      ss.push(s.substring(i, e) + "=\r\n");
      i = e;
      e = i + 76;
    }
    ss.push(s.substring(i));
    s = ss.join("");
  }
  return s;
}

export function qpDecode(str: string): Uint8Array {
  const buff = new Uint8Array(str.length);
  let index = 0;
  for (let i = 0; i < str.length; ) {
    if (str[i] != "=") {
      buff[index] = str.charCodeAt(i);
      index += 1;
      i += 1;
    } else if (i <= str.length - 3) {
      const s = str.substring(i, i + 3);
      if (s != "=\r\n") {
        buff[index] = parseInt(s.substring(1), 16);
        index += 1;
      }
      i += 3;
    } else {
      // error
    }
  }
  const v = new Uint8Array(buff.buffer, 0, index);
  return v;
}

export function getEncodeMethod(s: string, qpThreshold = 0.7): "B" | "Q" | "" {
  const noEncodeNumber = s.split("").filter(c => {
    const cc = c.charCodeAt(0);
    return 0x20 <= cc && cc <= 0x7e && cc != 0x3d;
  }).length;
  if (noEncodeNumber == s.length) {
    return "";
  }
  if (noEncodeNumber > s.length * qpThreshold) {
    return "Q";
  } else {
    return "B";
  }
}

export function encodeRFC2047(s: string, qpThreshold = 0.7): string {
  const m = getEncodeMethod(s, qpThreshold);
  if (m == "") {
    return s;
  }
  const useQP = m == "Q";
  const prefix = useQP ? "=?UTF-8?Q?" : "=?UTF-8?B?";
  let r = useQP ? qpEncode(s, -1) : base64Encode(s, -1);
  if (r.length <= 50) {
    r = prefix + r + "?=";
  } else {
    const res = [];
    let len = 0;
    let b = 0;
    for (let i = 0; i < s.length; i++) {
      const v = s.charCodeAt(i);
      if (v == 0x3d || v <= 0x20 || v >= 0x7e) {
        len += useQP ? 9 : 4; // chinese char
      } else {
        len += 1.3;
      }
      if (len >= 50 || i == s.length - 1) {
        if (i == s.length - 1) {
          i += 1;
        }
        const subStr = s.substring(b, i);
        res.push(
          prefix +
            (useQP ? qpEncode(subStr, -1) : base64Encode(subStr, -1)) +
            "?="
        );
        b = i;
        len = 0;
      }
    }
    r = res.join("\r\n\t");
  }
  return r;
}

export function decodeRFC2047(s: string): string {
  return s.replace(/=\?[^\s]+\?=/g, (s) => {
    const i = s.indexOf("?", 2);
    const j = s.indexOf("?", i + 1);
    const charset = s.substring(2, i).toLowerCase();
    const encoding = s.substring(i + 1, j).toUpperCase();
    if (encoding == "B") {
      const b = base64Decode(s.substring(j + 1, s.length - 2));
      const r = decodeCharset(b, charset);
      return r;
    } else if (encoding == "Q") {
      const b = qpDecode(s.substring(j + 1, s.length - 2));
      const r = decodeCharset(b, charset);
      return r;
    }
  })
}

export function decodeUtf7(s: string): string {
  return s.replace(/&([^-]*)-/g, (m: string, p1: string) => {
    if (p1 == "") {
      return "&";
    } else {
      const s = p1.replace(/,/g, "/").replace(/&-/g, "&");
      const b = base64Decode(s);
      const ss = [];
      for (let i = 0; i < b.byteLength; i += 2) {
        ss.push(String.fromCharCode((b[i] << 8) | b[i + 1]));
      }
      return ss.join("");
    }
  });
}

export function encodeUtf7(s: string): string {
  return s.replace(/&/g, "&-").replace(/[^\x20-\x7e]+/g, m => {
    const b = new Uint8Array(m.length * 2);
    for (let i = 0; i < m.length; i++) {
      const v = m.charCodeAt(i);
      b[i * 2] = v >> 8;
      b[i * 2 + 1] = v & 0xff;
    }
    return "&" + base64Encode(b).replace(/\//g, ",").replace(/=+$/, "") + "-";
  });
}

export function base64EncodeStream(
  inputStream: AsyncIterable<string | Uint8Array>,
  numPerLine = 76
): AsyncIterable<string> {
  const encoder = new util.TextEncoder();
  const u8aStream = transformStream(
    inputStream,
    async (current: string | Uint8Array) => {
      let b = typeof current == "string" ? encoder.encodeInto(current) : current;
      return [b, undefined];
    }
  );
  const base64 = new util.Base64Helper();
  const stringStream = transformStream<string, Uint8Array>(
    u8aStream,
    async (current: Uint8Array) => {
      const r = await base64.encodeToString(current); // buffer.from(current).toString("base64");
      return [r, undefined];
    }
  );
  return transformStream<string, string>(
    stringStream,
    async (current: string) => {
      if (current.length >= numPerLine) {
        return [
          current.substring(0, numPerLine) + "\r\n",
          current.substring(numPerLine),
        ];
      } else {
        return [undefined, current];
      }
    },
    (a, b) => a + b
  );
}

export function base64DecodeStream(
  inputStream: IBuffer,
  charset: buffer.BufferEncoding = "utf-8",
): AsyncIterable<Uint8Array> {
  const base64 = new util.Base64Helper();
  let buff = new Uint8Array(0);
  const result = (async function*(){
    for await (let chunk of inputStream.readRaw()) {
      if (buff.byteLength > 0) {
        buff = joinBuffers([buff, chunk]);
      } else {
        buff = chunk;
      }
      buff = removeBufferData(buff, CRLF);
      // buff = removeBufferData(buff, new Uint8Array([10]));
      // buff = removeBufferData(buff, new Uint8Array([13]));
      const remain = buff.byteLength % 4;
      let remainBuff = new Uint8Array(0);
      if (remain > 0) {
        remainBuff = buff.subarray(buff.byteLength - remain);
        buff = buff.subarray(0, buff.byteLength - remain);
      }
      const u8a = await base64.decode(buff, util.Type.BASIC);
      yield u8a;
      buff = remainBuff;
    }
    if (buff.length > 0) {
      const u8a = await base64.decode(buff, util.Type.BASIC);
      yield u8a;
    }
  })();
  return result;
}

export function qpDecodeStream(
  inputStream: AsyncIterable<string>,
  charset: buffer.BufferEncoding = "utf-8",
): AsyncIterable<Uint8Array> {
  const t: (current: string) => Promise<[Uint8Array | undefined, string]> = async (
    current: string
  ) => {
    const str = current;
    if (str.length < 3) {
      return [undefined, str];
    }
    const buff = new Uint8Array(str.length);
    let index = 0;
    let i = 0;
    for (; i < str.length; ) {
      if (str[i] != "=") {
        buff[index] = str.charCodeAt(i);
        index += 1;
        i += 1;
      } else if (i <= str.length - 3) {
        const s = str.substring(i, i + 3);
        if (s != "=\r\n") {
          buff[index] = parseInt(s.substring(1), 16);
          index += 1;
        }
        i += 3;
      } else {
        break;
      }
    }
    const v = new Uint8Array(buff.buffer, 0, index);
    return [v, str.substring(i)];
  };
  return transformStream<Uint8Array, string>(inputStream, t, (a, b) => a + b);
}
