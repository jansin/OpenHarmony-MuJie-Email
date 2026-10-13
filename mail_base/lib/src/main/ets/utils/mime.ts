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
import {
  base64Decode,
  qpDecode,
  decodeRFC2047,
  qpEncode,
  base64Encode,
  encodeRFC2047,
  getEncodeMethod,
  decodeCharset,
  base64DecodeStream,
  qpDecodeStream,
} from "./encodings";
import { CMError, ErrorCode } from "../api";
import type {
  EmailAddress,
  MailEnvelope,
  InlineImage,
  Attachment,
  MailStructure,
  MimeDisposition,
  MimeParams,
  IBuffer,
  ContentType,
  Mime,
  IBufferCreator,
} from "../api";
import { parseDateString, stream2buffer, stream2lines } from "./common";
import { createBuffer, memBufferCreator } from "./file_stream";
import { findBuffer } from "./buffer_utils"
import util from '@ohos.util';

const logger = getLogger("mime");

type MIMEHeadEncode = Map<string, { value: string; encoder?: "Q" | "B" }>;

export type EncodeOption = {
  qpThreshold?: number;
  isRichText?: boolean;
  needEncode?: boolean;
  boundaryIndex?: number;
};

/*
+--------------------- multipart/mixed ---------------------------------+
| +--------- multipart/relative ----------------------+  +------------+ |
| | +------ multipart/alternative --+  +-----------+  |  | image/jpeg | |
| | | +------------+ +-----------+  |  | image/png |  |  | image/png  | |
| | | | text/plain | | text/html |  |  | image/gif |  |  | image/gif  | |
| | | +------------+ +-----------+  |  | other/mime|  |  | other/mime | |
| | +-------------------------------+  +-----------+  |  +------------+ |
| +---------------------------------------------------+                 |
+-----------------------------------+-----------------+-----------------+
*/

let _boundaryPrefix = "----=_Part_";
let _pattern = base64Encode(
  "coremail-boundary-" + Math.random().toString(36).substring(2)
);
export function setBoundaryPattern(pattern: string): void {
  _pattern = pattern;
}

function getBoundaryPart(index: number): string {
  return `${_boundaryPrefix}${index}.${_pattern}`;
}

export async function serializeRichText(
  rich: string,
  plain: string,
  boundary: string
): Promise<string> {
  if (plain.length > 0) {
    plain = await serializeMIME(
      [
        ["Content-Type", "text/plain; charset=utf-8"],
        ["Content-Transfer-Encoding", "base64"],
      ],
      base64Encode(plain.replace(/<[^>]*>/g, ""), 76, "utf-8")
    );
  }
  if (rich.length > 0) {
    rich = await serializeMIME(
      [
        ["Content-Type", "text/html; charset=utf-8"],
        ["Content-Transfer-Encoding", "quoted-printable"],
      ],
      qpEncode(rich, 76, "utf-8")
    );
  }
  if (rich.length > 0 && plain.length > 0) {
    return serializeMIME(
      [["Content-Type", `multipart/alternative;\r\n\tboundary="${boundary}"`]],
      `--${boundary}\r\n${plain}\r\n--${boundary}\r\n${rich}\r\n--${boundary}--`,
      {}
    );
  } else if (rich.length > 0) {
    return rich;
  } else if (plain.length > 0) {
    return plain;
  }
  return "";
}

function serializeInnerImages(images: InlineImage[]): Promise<string[]> {
  return Promise.all(
    images.map(async image => {
      const buff = await image.body.readAllRaw();
      const body = base64Encode(buff, 76);
      const content = await serializeMIME(
        [
          ["Content-Type", `${image.contentType}; name="${image.name}"`],
          ["Content-Disposition", `inline; filename="${image.name}"`],
          ["Content-Transfer-Encoding", "base64"],
          ["Content-ID", `<${image.contentId}>`],
        ],
        body,
        { needEncode: false }
      );
      return content;
    })
  );
}

function serializeAttachments(attachments: Attachment[]): Promise<string[]> {
  return Promise.all(
    attachments.map(async attachment => {
      const buff = await attachment.body.readAllRaw();
      const body = base64Encode(buff, 76);
      const content = await serializeMIME(
        [
          [
            "Content-Type",
            `${attachment.contentType}; name="${attachment.name}"`,
          ],
          ["Content-Disposition", `attachment; filename="${attachment.name}"`],
          ["Content-Transfer-Encoding", "base64"],
        ],
        body,
        { needEncode: false }
      );
      return content;
    })
  );
}

function encodeAddress(address: EmailAddress, qpThreshold = 0.9): string {
  if (!address.name) {
    return address.email;
  }
  const s = address.name;
  return `${encodeRFC2047(address.name)} <${address.email}>`;
}

export async function serializeMail(
  mailHead: Omit<MailEnvelope, "date" | "messageId">,
  extra: MIMEHeadEncode,
  body: string,
  plainBody: string,
  innerImages: InlineImage[],
  attachments: Attachment[],
  option: EncodeOption = {}
): Promise<string> {
  const headers: Array<[string, string]> = [];
  headers.push(["from", encodeAddress(mailHead.from)]);
  if (mailHead.to.length > 0) {
    headers.push([
      "to",
      mailHead.to.map(a => encodeAddress(a)).join(",\r\n\t"),
    ]);
  }
  if (mailHead.cc.length > 0) {
    headers.push([
      "cc",
      mailHead.cc.map(a => encodeAddress(a)).join(",\r\n\t"),
    ]);
  }
  if (mailHead.bcc.length > 0) {
    headers.push([
      "bcc",
      mailHead.bcc.map(a => encodeAddress(a)).join(",\r\n\t"),
    ]);
  }
  if (mailHead.subject.length > 0) {
    headers.push(["subject", encodeRFC2047(mailHead.subject)]);
  }
  for (const [k, { value, encoder }] of extra) {
    let encodedValue = value;
    if (encoder == "Q") {
      encodedValue = qpEncode(value, 50).replace(/\r\n/g, "\r\n\t");
    } else if (encoder == "B") {
      encodedValue = base64Encode(value, 50).replace(/\r\n/g, "\r\n\t");
    }
    headers.push([k, encodedValue]);
  }
  option.needEncode = true;
  let boundaryIndex = option.boundaryIndex ?? 1;
  if (attachments.length > 0) {
    option.needEncode = false;
    const boundary = getBoundaryPart(boundaryIndex);
    headers.push([
      "Content-Type",
      `multipart/mixed;\r\n\tboundary="${boundary}"`,
    ]);

    const textBoundaryIndex =
      innerImages.length > 0 ? boundaryIndex + 2 : boundaryIndex + 1;
    const textBoundary = getBoundaryPart(textBoundaryIndex);
    const textBody = await serializeRichText(body, plainBody, textBoundary);
    if (innerImages.length > 0) {
      const innerBoundary = getBoundaryPart(boundaryIndex + 1);
      const parts = await serializeInnerImages(innerImages);
      parts.unshift(textBody);
      const imageBody = parts.join(`\r\n--${innerBoundary}\r\n`);
      body = await serializeMIME(
        [
          [
            "Content-Type",
            `multipart/related;\r\n\tboundary="${innerBoundary}"`,
          ],
        ],
        `--${innerBoundary}\r\n${imageBody}\r\n--${innerBoundary}--`,
        { needEncode: false }
      );
    } else {
      body = textBody;
    }
    const parts = await serializeAttachments(attachments);
    parts.unshift(body);
    const attachmentBody = parts.join(`\r\n--${boundary}\r\n`);
    body = `--${boundary}\r\n${attachmentBody}\r\n--${boundary}--`;
  } else if (innerImages.length > 0) {
    option.needEncode = false;
    const boundary = getBoundaryPart(boundaryIndex);
    headers.push([
      "Content-Type",
      `multipart/related;\r\n\tboundary="${boundary}"`,
    ]);

    boundaryIndex += 1;
    const textBoundary = getBoundaryPart(boundaryIndex);
    const textBody = await serializeRichText(body, plainBody, textBoundary);
    const parts = await serializeInnerImages(innerImages);
    parts.unshift(textBody);
    const imageBody = parts.join(`\r\n--${boundary}\r\n`);
    body = `--${boundary}\r\n${imageBody}\r\n--${boundary}--`;
  } else if (plainBody.length > 0 && body.length > 0) {
    option.needEncode = false;
    const boundary = getBoundaryPart(boundaryIndex);
    headers.push([
      "Content-Type",
      `multipart/alternative;\r\n\tboundary="${boundary}"`,
    ]);
    const text1 = await serializeRichText("", plainBody, "");
    const text2 = await serializeRichText(body, "", "");
    body = `--${boundary}\r\n${text1}\r\n--${boundary}\r\n${text2}\r\n--${boundary}--`;
  } else if (body.length > 0){
    headers.push(['Content-Type', 'text/html; charset="utf-8"'])
    body = body;
  } else if (plainBody.length > 0) {
    headers.push(['Content-Type', 'text/plain; charset="utf-8"'])
    body = plainBody;
  }
  return serializeMIME(headers, body, option);
}

export async function serializeMIME(
  headers: Array<[string, string]>,
  body: string,
  option: EncodeOption = {}
): Promise<string> {
  if (option.needEncode) {
    const m = getEncodeMethod(body);
    if (m != "") {
      body = m == "Q" ? qpEncode(body, 76) : base64Encode(body, 76);
      headers.push([
        "Content-Transfer-Encoding",
        m == "Q" ? "quoted-printable" : "base64",
      ]);
    }
  }
  const lines: string[] = [];
  for (const [name, value] of headers) {
    lines.push(
      `${name
        .split("-")
        .map(s => s[0].toUpperCase() + s.substring(1))
        .join("-")}: ${value}`
    );
  }
  lines.push("");
  lines.push(body);
  return lines.join("\r\n");
}

/*
简单解析邮件地址
CAVEAT: 当名字里面有特殊字符<,;时会出错
*/
function parseAddress(s: string): EmailAddress[] {
  try {
    return s.split(/[,;]/).map(s => {
      s = s.trim();
      const i = s.indexOf("<");
      if (i == -1) {
        return { name: "", email: s };
      } else {
        return {
          name: s.substring(0, i).trim(),
          email: s.substring(i + 1, s.length - 1).trim(),
        };
      }
    });
  } catch (e) {
    logger.error("parseAddress error", s, e);
    return [];
  }
}

function parseParams(params: string[]): MimeParams {
  const map: MimeParams = {};
  for (const p of params) {
    const i = p.indexOf("=");
    const name = p.substring(0, i).trim().toLowerCase();
    let value = p.substring(i + 1).trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    value = decodeRFC2047(value);
    if (name == 'charset'){
      value = value.toLowerCase();
    }
    map[name] = value;
  }
  return map;
}

function parseContentType(s: string): ContentType | undefined {
  try {
    const [part1, ...params] = s.split(";");
    const [type, subType] = part1.split("/");
    return {
      type: type.toLowerCase(),
      subType: subType.toLowerCase(),
      params: parseParams(params)
    };
  } catch (e) {
    logger.error("parse content failed", s)
    return;
  }
}

function parseDisposition(s: string): MimeDisposition | undefined {
  try {
    const [type, ...params] = s.split(";");
    return { type, params: parseParams(params) };
  } catch (e) {
    logger.error("parse disposition failed", s)
    return;
  }
}

function toBuffer(s: AsyncIterable<Uint8Array>): IBuffer {
  const b = createBuffer({});
  (async function (): Promise<void> {
    for await (const chunk of s) {
      b.feed(chunk);
    }
  })();
  return b;
}

interface IReader {
  /*
   * 读取内容，直到遇到`end`的值。
   * 返回的Promise，成功的话resolve一个字符串，不包括`end`的值。失败则reject错误
   * 移动当前位置到`end`的后一个位置
   */
  readUntil(end: string): Promise<string>;
  /*
   * 读取内容，直到遇到`end`的值。
   * 返回的Promise，成功的话resolve一个IBuffer对象，不包括`end`的值。失败则reject错误
   * 用于读取附件、内联附件内容这类大数据的内容
   * 移动当前位置到`end`的后一个位置
   */
  readBlockUntil(end: string | Uint8Array): Promise<IBuffer>;
  readToEnd(): Promise<IBuffer>;
  /*
   * 获取当前`n`个字符串，不移动当前位置。
   */
  peek(n: number): Promise<string>;
  /*
   * 跳过空白字符，空白字符是指空格，制表符，换行，回车这四个字符
   * 移动当前位置到空白字符的后一个位置
   */
  skipSpace(): Promise<void>;
  /*
   * 跳过`n`个字符
   * 移动当前位置到跳过的字符的后一个位置
   */
  skip(n: number): Promise<void>;
  /*
   * 判断是否结束
   */
  end(): boolean;
}

export class StringReader implements IReader {
  _data: string;
  _offset: number = 0;
  constructor(s: string) {
    this._data = s;
  }
  readUntil(end: string): Promise<string> {
    if (!end) {
      return Promise.reject("parameter error");
    }
    const idx = this._data.indexOf(end, this._offset);
    if (idx < 0) {
      return Promise.reject("not found");
    }
    const result = this._data.substring(this._offset, idx);
    this._offset = idx + end.length;
    return Promise.resolve(result);
  }
  async readBlockUntil(end: string | Uint8Array): Promise<IBuffer> {
    if (typeof end != 'string') {
      end = util.TextDecoder.create('utf-8').decodeWithStream(end);
    }
    const buff = memBufferCreator.createBuffer({});
    buff.end(await this.readUntil(end));
    return buff;
  }
  readToEnd(): Promise<IBuffer> {
    const buff = memBufferCreator.createBuffer({});
    buff.end(this._data.substring(this._offset));
    this._offset = this._data.length;
    return Promise.resolve(buff);
  }

  peek(n: number): Promise<string> {
    return Promise.resolve(this._data.substring(this._offset, this._offset + n));
  }

  skipSpace(): Promise<void> {
    let i = this._offset;
    for (; i < this._data.length; i++) {
      const ch = this._data[i];
      if (!(ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n')) {
        break;
      }
    }
    this._offset = i;
    return Promise.resolve()
  }

  skip(n: number): Promise<void> {
    this._offset += n;
    return Promise.resolve()
  }
  end(): boolean {
    return this._offset >= this._data.length;
  }
}

export class BufferReader implements IReader {
  _bufferCreator: IBufferCreator;
  _currentBuffer: Uint8Array = new Uint8Array;
  _offset: number = 0;
  _buffer: AsyncIterator<Uint8Array>;
  constructor(buffer: IBuffer, bufferCreator?: IBufferCreator) {
    this._bufferCreator = bufferCreator || memBufferCreator;
    this._buffer = buffer.readRaw();
  }

  async init() {
    await this.getData();
  }

  /*
  尝试去拿数据，返回是否有新数据
   */
  async getData(): Promise<boolean> {
    logger.debug('get data start')
    const result = await this._buffer.next();
    if (result.done) {
      return false;
    }
    const newBuffer: Uint8Array = result.value;
    if (this._offset < this._currentBuffer.byteLength) {
      const remain = this._currentBuffer.byteLength - this._offset;
      const buff = new Uint8Array(remain + newBuffer.byteLength);
      buff.set(this._currentBuffer.subarray(this._offset));
      buff.set(newBuffer, remain);
      this._currentBuffer = buff;
    } else {
      const buff = new Uint8Array(newBuffer.byteLength);
      buff.set(newBuffer);
      this._currentBuffer = buff;
    }
    this._offset = 0;
    logger.debug('get data end', this._currentBuffer.byteLength);
    return true;
  }

  /*
   读取内容，直到遇到`end`的值。如果`end`为空，则读到Buffer的末尾
   返回的Promise，成功的话resolve一个字符串，不包括`end`的值。失败则reject错误
   底层是二进制，默认按照**UTF-8**解码
  */
  async readUntil(end: string): Promise<string> {
    let target: Uint8Array = (new util.TextEncoder()).encodeInto(end);
    let idx = findBuffer(this._currentBuffer, target, this._offset);
    while (idx < 0) {
      const hasNew = await this.getData();
      if (!hasNew) {
        throw new CMError('not found');
      }
      idx = findBuffer(this._currentBuffer, target, this._offset);
    }
    const buffer = this._currentBuffer.subarray(this._offset, idx);
    let result = '';
    if (buffer.byteLength > 0) {
      const decoder = util.TextDecoder.create('utf-8');
      result = decoder.decodeWithStream(buffer);
    }

    this._offset = idx + target.byteLength;
    if (this._offset >= this._currentBuffer.byteLength) {
      await this.getData();
    }
    return result;
  }

  /*
   读取内容，直到遇到`end`的值，或者读到`Buffer`的末尾。
   返回的Promise，成功的话是一个IBuffer对象，不包括`end`的值。
   */
  async readBlockUntil(end: string | Uint8Array): Promise<IBuffer> {
    if (typeof end == 'string') {
      end = (new util.TextEncoder()).encodeInto(end);
    }
    const buff = this._bufferCreator.createBuffer({useFile: false});
    this._currentBuffer = this._currentBuffer.subarray(this._offset);
    this._offset = 0;
    let idx = -1;
    while (true) {
      idx = findBuffer(this._currentBuffer, end);
      if (idx < 0) {
        if (this._currentBuffer.byteLength > end.byteLength) { // 只放入部分数据，因为需要判断交叉的部分。
          buff.feed(this._currentBuffer.subarray(0, this._currentBuffer.byteLength - end.byteLength));
          this._currentBuffer = this._currentBuffer.subarray(this._currentBuffer.byteLength - end.byteLength);
          this._offset = 0;
        }
        const hasNew = await this.getData();
        if (!hasNew) {
          throw new CMError('not found');
        }
      } else {
        const b = this._currentBuffer.subarray(0, idx);
        buff.end(b)
        this._currentBuffer = this._currentBuffer.subarray(idx + end.byteLength);
        this._offset = 0;
        break;
      }
    }
    await this.getData();
    return buff;
  }

  async readToEnd(): Promise<IBuffer> {
    const buff = this._bufferCreator.createBuffer({useFile: false});
    let buffer = this._currentBuffer.subarray(this._offset);
    if (buffer.byteLength > 0) {
      buff.feed(buffer)
    }
    while (await this.getData()) {
      buff.feed(this._currentBuffer);
    }
    buff.end();
    return buff;
  }

  async peek(n: number = 1): Promise<string> { // 只处理 ascii 字符
    if (this._offset + n >= this._currentBuffer.byteLength) {
      await this.getData();
    }
    const b = this._currentBuffer.subarray(this._offset, this._offset + n);
    const s = Array.from(b).map(n => String.fromCharCode(n)).join('');
    return s;
  }
  /*
    跳过空白字符，包括空格' '，制表符'\t'，换行'\n'，回车'\r'等
   */
  async skipSpace(): Promise<void> {
    let i = 0;
    while (true) {
      if (this._offset >= this._currentBuffer.byteLength) {
        const hasNew = await this.getData();
        if (!hasNew) {
          break;
        }
      }
      const ch = this._currentBuffer[this._offset];
      if (!(ch == 32 || ch == 9 || ch == 13 || ch == 10)) {
        break;
      }
      this._offset += 1;
    }
  }

  async skip(n: number = 1): Promise<void> {
    this._offset += n;
    if (this._offset >= this._currentBuffer.byteLength) {
      await this.getData();
    }
  }

  end(): boolean {
    return this._offset >= this._currentBuffer.byteLength;
  }
}

export async function parseMime(s: string | IBuffer, bufferCreator?: IBufferCreator): Promise<Mime> {
  logger.trace('start parse mime')
  if (!bufferCreator) {
    bufferCreator = memBufferCreator;
  }
  const reader = await (async () => {
    if (typeof s == 'string') {
      return new StringReader(s);
    }
    else {
      const reader = new BufferReader(s);
      await reader.init();
      return reader;
    }
  })();
  const mime = await _parseMime(reader, '', bufferCreator);
  modifyMimePartId(mime);
  return mime;
}

export async function _parseMime(
  reader: IReader,
  boundary: string,
  bufferCreator: IBufferCreator
): Promise<Mime> {
  logger.trace('start parse')
  const mime: Mime = {
    contentType: { type: "", subType: "", params: {} },
    headers: new Map(),
    children: [],
    body: bufferCreator.createBuffer({useFile: false}),
    size: 0,
    partId: "",
  };
  const CRLF = "\r\n";
  await reader.skipSpace();
  while (!reader.end()) {
    while (!reader.end()) { // header
      const field = (await reader.readUntil(':')).toLowerCase();
      await reader.skipSpace();
      const valueParts = [await reader.readUntil(CRLF)];
      let nextChar = await reader.peek(2);
      while (nextChar.startsWith(' ') || nextChar.startsWith('\t')) {
        await reader.skip(1);
        const v = await reader.readUntil(CRLF);
        valueParts.push(v);
        nextChar = await reader.peek(2);
      }
      const value = valueParts.map(decodeRFC2047).join('');
      mime.headers.set(field, value);
      processHeadValue(mime, field, value);
      if (nextChar == CRLF) {
        await reader.skip(2);
        break;
      }
    }
    logger.trace('parse body', mime.contentType.type)
    if (mime.contentType.type == 'multipart') {
      await reader.skipSpace();
      const selfBoundary = mime.contentType.params.boundary;
      if (!selfBoundary) {
        logger.error("no boundary");
      }
      const content = await reader.readUntil('--' + selfBoundary);
      if (content.length > 0) {
        mime.body.feed(content);
      }

      while (!reader.end()) {
        let chars = await reader.peek(2);
        if (chars == '--') {
          reader.skip(2);
          if (boundary) {
            await reader.readUntil('--' + boundary);
          }
          return mime;
        } else if (chars == CRLF) {
          reader.skip(2);
          const m = await _parseMime(reader, selfBoundary, bufferCreator);
          m.size = await m.body.getSizeRaw();
          mime.children.push(m);
        } else {
          logger.error('error');
          throw new CMError('parse error');
        }
      }
    } else {
      const content = boundary ?
        await reader.readBlockUntil('--' + boundary) :
        await reader.readToEnd();
      mime.body = content;
      break;
    }
    await reader.skipSpace();
  }
  logger.trace('end parse')
  return mime;
}
function processHeadValue(mime: Mime, field: string, value: string) {
  switch (field) {
    case 'content-type':
      mime.contentType = parseContentType(value);
      break;
    case 'content-disposition':
      mime.disposition = parseDisposition(value);
      break;
    case 'content-id':
      mime.contentId = value;
      break;
    case 'content-transfer-encoding':
      mime.encoding = value.toLowerCase();
      break;
  }
}


export const parseMime2 = parseMime;
export async function parseMime_old(s: IBuffer | string, bufferCreator?: IBufferCreator): Promise<Mime> {
  if (!bufferCreator) {
    bufferCreator = memBufferCreator;
  }
  logger.trace("start parse mime====")
  const mime: Mime = {
    contentType: { type: "", subType: "", params: {} },
    headers: new Map(),
    children: [],
    body: bufferCreator.createBuffer({useFile: false}),
    size: 0,
    partId: "",
  };
  const CRLF = "\r\n";
  const mimeStack: Mime[] = [mime];
  let isHead = true;
  // let currentMime = mime;
  let currentHeadField = "";
  let currentHeadValues: string[] = [];
  let boundary = "";
  let lines: AsyncIterable<string> | Iterable<string>;
  if (typeof s == "string") {
    lines = s.split(/\r?\n/);
  } else {
    lines = stream2lines(s);
  }

  const processHead = (): Promise<never> => {
    logger.trace("processHead", currentHeadField)
    const currentMime: Mime = mimeStack[mimeStack.length - 1];
    let vs: string[] = currentHeadValues.map(decodeRFC2047);
    let value: string = vs.join("");
    currentHeadValues = [];
    currentMime.headers.set(currentHeadField, value);
    if (currentHeadField == "content-type") {
      const contentType = parseContentType(value);
      if (!contentType) {
        const text = "invalid mime header bad content type";
        logger.error(text);
        return Promise.reject(new CMError(text, ErrorCode.PARSE_MIME_FAILED));
      }
      currentMime.contentType = contentType;
      if (contentType.type == "multipart") {
        if (!contentType.params.boundary) {
          const text = "invalid mime header no boundary"
          logger.error(text);
          return Promise.reject(new CMError(text, ErrorCode.PARSE_MIME_FAILED));
        }
        boundary = contentType.params.boundary;
      } else if (contentType.type != "text") {
        currentMime.body = bufferCreator.createBuffer({mime: currentMime})
      }
    } else if (currentHeadField == 'content-transfer-encoding') {
      currentMime.encoding = value.toLowerCase();
    } else if (currentHeadField == 'content-disposition') {
      currentMime.disposition = parseDisposition(value)
    } else if (currentHeadField == 'content-id') {
      currentMime.contentId = value;
    }
    logger.trace("processHead end", currentHeadField)
  };

  for await (const line of lines) {
    if (isHead) {
      if (line === "") {
        isHead = false;
        processHead();
        currentHeadField = "";
        logger.trace('end head')
        continue;
      }
      if (line.startsWith(" ") || line.startsWith("\t")) {
        currentHeadValues.push(line.trim());
        continue;
      }
      if (currentHeadField.length > 0) {
        processHead();
      }
      const i = line.indexOf(":");
      if (i < 0) {
        logger.info("invalid mime header", line)
        continue;
      }
      currentHeadField = line.substring(0, i).toLowerCase();
      // logger.trace(currentHeadField, line);
      currentHeadValues.push(line.substring(i + 1).trim());
    } else {
      if (boundary && boundary.length > 0 && line == `--${boundary}--`) {
        logger.trace('end part')
        const m = mimeStack.pop();
        if (m && (m.contentType.type != 'multipart' || m.contentType.params.boundary != boundary)) {
          mimeStack.pop();
        }
        boundary =
          mimeStack[mimeStack.length - 1]?.contentType.params.boundary || "";
        continue;
      }
      else if (boundary && boundary.length > 0 && line.startsWith(`--${boundary}`)) {
        logger.trace('new part')
        const newMime = {
          contentType: { type: "", subType: "", params: {} },
          headers: new Map(),
          children: [],
          body: bufferCreator.createBuffer({useFile: false}),
          size: 0,
          partId: "",
        };
        let currentMime = mimeStack[mimeStack.length - 1];
        if (currentMime.contentType.params.boundary != boundary) {
          mimeStack.pop();
        }
        currentMime = mimeStack[mimeStack.length - 1];
        currentMime.children.push(newMime);
        mimeStack.push(newMime);
        isHead = true;
      } else {
        const currentMime = mimeStack[mimeStack.length - 1];
        if (currentMime && currentMime.contentType.type != "multipart") {
          await currentMime.body.feed(line);
          await currentMime.body.feed(CRLF);
          currentMime.size += line.length + 2
        }
      }
    }
  }
  getMimeParts(mime, mime => (mime as Mime).body.end() && false);
  modifyMimePartId(mime);
  logger.trace("finish parse mime====")
  return mime;
}

export class MimeMail {
  _mime: Mime;
  constructor(mime: Mime) {
    this._mime = mime;
  }

  getPlainPart(): MailStructure | undefined {
    const part = getMimeParts(this._mime, (mime) => {
      return mime.disposition?.type != 'attachment' &&
        mime.contentType.type == "text" &&
        mime.contentType.subType == 'plain';
    })[0];
    return part;
  }
  getPlain(): IBuffer | undefined {
    const part = this.getPlainPart();
    if (!part) {
      return;
    }
    return (part as Mime).body;
  }
  getPlainPartId(): string|undefined {
    return this.getPlainPart()?.partId;
  }

  getHtmlPart(): MailStructure | undefined {
    const part = getMimeParts(this._mime, (mime) => {
      if (mime.disposition?.type == 'attachment') {
        return false;
      }
      const t = (mime.contentType.type || '').toLowerCase();
      const sub = (mime.contentType.subType || '').toLowerCase();
      return (t == "text" && (sub == "html" || sub == "xhtml+xml")) ||
        (t == "application" && sub == "xhtml+xml");
    })[0];
    return part;
  }

  getHtmlPartId(): string | undefined {
    return this.getHtmlPart()?.partId;
  }

  getHtml(): IBuffer | undefined {
    const part = this.getHtmlPart();
    if (!part) {
      return;
    }
    return (part as Mime).body;
  }

  getEnvelope(): MailEnvelope {
    const mime = this._mime;
    let dateStr = mime.headers.get("date");
    if (!dateStr) {
      dateStr = mime.headers.get("received").split(';').pop();
    }
    return {
      from: parseAddress(mime.headers.get("from") || "")[0],
      to: parseAddress(mime.headers.get("to") || ""),
      cc: parseAddress(mime.headers.get("cc") || ""),
      bcc: parseAddress(mime.headers.get("bcc") || ""),
      subject: mime.headers.get("subject") || "",
      date: parseDateString(dateStr || ""),
      messageId: "",
    }
  }

  getStructure(): MailStructure {
    return getStructure2(this._mime);
  }

  getAttachments(): MailStructure[] {
    return getMimeParts(this._mime,
      (mime) => !!mime.disposition?.type.startsWith("attachment"))
  }

  getInlineImages(): MailStructure[] {
    return getMimeParts(this._mime, (mime) => {
      let isInline = !!(mime.disposition?.type == "inline" && mime.contentId);
      if (!isInline && mime.contentType.type == 'image' && mime.contentId) {
        isInline = true;
      }
      return isInline;
    })
  }
}

function decodeCharsetStream(input: IBuffer, charset?: string): IBuffer {
  const buff = createBuffer({});
  (async function(): Promise<void> {
    const buf = await input.readAllRaw()
    const str = decodeCharset(buf, charset);
    buff.end(str);
  })();
  return buff;
}

export function getMimeDecodedBody(mime: Mime): IBuffer {
  if (mime.encoding == 'base64') {
    const r = base64DecodeStream(mime.body);
    let res = stream2buffer(r);
    if (mime.contentType.params.charset) {
      return decodeCharsetStream(res, mime.contentType.params.charset);
    } else {
      return res;
    }
  } else if (mime.encoding == 'quoted-printable') {
    const r = qpDecodeStream(mime.body);
    let res = stream2buffer(r);
    if (mime.contentType.params.charset) {
      return decodeCharsetStream(res, mime.contentType.params.charset);
    } else {
      return res;
    }
  } else {
    return mime.body;
  }
}

export function getMimePartName(mime: MailStructure): string {
  const name = mime.disposition?.params.filename || mime.contentType.params.name;
  return name || mime.partId;
}

export function getMimeParts(mime: MailStructure, filter: (mime: MailStructure) => boolean): MailStructure[] {
  let parts: MailStructure[] = [];
  if (filter(mime)) {
    parts.push(mime);
  }
  if (mime.children.length > 0) {
    parts = mime.children.reduce(
      (prev, m) => prev.concat(getMimeParts(m, filter)),
      parts
    );
  }
  return parts;
}

function getStructure2(mime: Mime): MailStructure {
  return {
    contentType: mime.contentType,
    disposition: mime.disposition,
    contentId: mime.contentId,
    encoding: mime.encoding,
    children: mime.children.map(getStructure2),
    partId: mime.partId,
    size: mime.size,
  }
}

function modifyMimePartId(mime: Mime): void {
  _modifyMimePartId(mime, []);
}

function _modifyMimePartId(mime: Mime, partIds: number[]): void {
  if (mime.contentType.type == "multipart") {
    mime.children.forEach((m, i) => {
      _modifyMimePartId(m, [...partIds, i + 1]);
    });
  } else {
    mime.partId = partIds.join(".") || "1";
  }
}
