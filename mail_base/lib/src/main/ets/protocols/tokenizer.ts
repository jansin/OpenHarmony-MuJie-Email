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

import type { Connection } from "./network";
import { base64Encode, decodeCharset, decodeUtf7 } from "../utils/encodings";
import { CRLF, isDigit } from "../utils/common";
import { createBuffer, memBufferCreator } from "../utils/file_stream";
import { CMError, ErrorCode } from "../api";
import type { IBuffer , IBufferCreator } from "../api";

export enum Atoms {
  NIL,
  UID,
  FLAGS,
  RFC822_SIZE,
  BODY,
  BODYSTRUCTURE,
  ENVELOPE,
  INTERNALDATE,
  OK,
  NO,
  BAD,
  BYE,
  PREAUTH,

  EXISTS,

  MESSAGES,
  RECENT,
  UIDNEXT,
  UIDVALIDITY,
  UNSEEN,

  // commands
  LIST,
  LSUB,
  STATUS,
  FETCH,
  SEARCH,

  // response code
  ALERT,
  BADCHARSET,
  CAPABILITY,
  PARSE,
  PERMANENTFLAGS,
  READ_ONLY,
  READ_WRITE,
  TRYCREATE,

  // flags
  ANSWERED,
  FLAGGED,
  DELETED,
  SEEN,
  DRAFT,

  IMPORTANT,

  UNKNOWN,
}

export type UnknownAtom = string;
export type Atom = Atoms | UnknownAtom;

export type ServerStatusResponse =
  | Atoms.OK
  | Atoms.NO
  | Atoms.BAD
  | Atoms.BYE
  | Atoms.PREAUTH;
export type StatusItem =
  | Atoms.MESSAGES
  | Atoms.RECENT
  | Atoms.UIDNEXT
  | Atoms.UIDVALIDITY
  | Atoms.UNSEEN;
export type ResponseCode =
  | Atoms.ALERT
  | Atoms.BADCHARSET
  | Atoms.CAPABILITY
  | Atoms.PARSE
  | Atoms.PERMANENTFLAGS
  | Atoms.READ_ONLY
  | Atoms.READ_WRITE
  | Atoms.TRYCREATE
  | Atoms.UIDNEXT
  | Atoms.UIDVALIDITY
  | Atoms.UNSEEN;

export type ImapList = Array<Atom | string | number | ImapList>;

export class Tokenizer {
  s: string;
  i: number;
  conn: Connection;
  _bufferCreator: IBufferCreator = memBufferCreator;
  constructor(conn: Connection) {
    this.s = "";
    this.i = 0;
    this.conn = conn;
  }

  setBufferCreator(creator: IBufferCreator): void {
    this._bufferCreator = creator;
  }

  getInfo(): {
    s: string,
    i: number
  } {
    return {
      s: this.s,
      i: this.i,
    };
  }

  async feed(): Promise<void> {
    let line = decodeCharset(await this.conn.getData(CRLF));
    this.s = line;
    this.i = 0;
  }

  expect(c: string) : void {
    this.skipSpace();
    for (let i = 0; i < c.length; i++) {
      if (this.s[this.i + i] != c[i])
        throw new CMError(`Expect ${c} but got ${this.s[this.i]}`, ErrorCode.IMAP_PARSER_FAILED);
    }
    this.i += c.length;
  }

  getUntil(c: string): string {
    this.skipSpace();
    let i = this.i;
    while (i < this.s.length && this.s[i] != c) {
      i += 1;
    }
    const s = this.s.substring(this.i, i);
    this.i = i;
    return s;
  }

  getNumber(): number {
    this.skipSpace();
    let i = this.i;
    while (i < this.s.length) {
      const c = this.s.charCodeAt(i);
      if (c < 0x30 || c > 0x39) {
        break;
      }
      i += 1;
    }
    const res = parseInt(this.s.substring(this.i, i));
    this.i = i;
    return res;
  }

  getString(): string | undefined | number {
    this.skipSpace();
    const ch = this.s[this.i];
    if (ch == '"') {
      let i = this.i + 1;
      while (i < this.s.length) {
        const ch = this.s[i];
        if (ch == "\\") {
          i += 1;
        } else if (ch == '"') {
          break;
        }
        i += 1;
      }
      const res = this.s.substring(this.i + 1, i);
      this.i = i + 1;
      return res;
    } else if (ch == "{") {
      this.i += 1;
      const n = this.getNumber();
      this.expect("}");
      return n;
    } else if (ch == "N") {
      this.expect("NIL");
    } else {
      return this.getUntil(' ');
    }
  }

  async getString2(): Promise<string | undefined> {
    const s = this.getString();
    if (typeof s == "number") {
      const res = decodeCharset(await this.conn.getData(s));
      await this.feed();
      return res;
    } else {
      return s;
    }
  }

  async getStringStream(): Promise<IBuffer | undefined> {
    const s = this.getString();
    const MAX_CHUNK_SIZE = 1024 * 10;
    if (typeof s == "number") {
      let stream = this._bufferCreator.createBuffer({size: s});
      if (s > MAX_CHUNK_SIZE) {
        let n = 0;
        while (n < s) {
          const m = Math.min(s - n, MAX_CHUNK_SIZE);
          const data = await this.conn.getData(m);
          // TODO: charset
          // TODO: decode error
          await stream.feed(data);
          n += m;
        }
        await stream.end();
      } else {
        await stream.end(await this.conn.getData(s));
      }
      // const res = decodeCharset(await this.conn.getData(s));
      await this.feed();
      return stream;
    } else {
      let stream = this._bufferCreator.createBuffer({size: s.length});
      await stream.end(s);
      return stream;
    }
  }

  getAtom(): Atom {
    this.skipSpace();
    let i = this.i;
    while (i < this.s.length && !"() []".includes(this.s[i])) {
      i += 1;
    }
    const res = this.s.substring(this.i, i);
    const atom = res.replace(".", "_").replace("-", "_").toUpperCase();
    this.i = i;
    return Atoms[atom as keyof typeof Atoms] ?? res;
  }

  peekNextChar(): string {
    this.skipSpace();
    if (this.isEndOfLine()) {
      throw new CMError("Unexpected end of line", ErrorCode.IMAP_UNEXPECTED_END_OF_LINE);
    }
    return this.s[this.i];
  }

  isEndOfLine(): boolean {
    return this.i >= this.s.length;
  }

  skipSpace() : void {
    // according to rfc, there should be only one space between tokens
    // but some servers may send more than one space
    while (this.i < this.s.length && this.s[this.i] == " ") {
      this.i += 1;
    }
  }

  async getList(hasParenthesis: boolean = true): Promise<ImapList> {
    if (hasParenthesis) {
      this.expect("(");
    }
    const arr: ImapList = [];
    while (true) {
      this.skipSpace();
      if (this.isEndOfLine()) {
        break;
      }
      const ch = this.peekNextChar();
      if (ch == "\r") {
        break;
      }
      if (hasParenthesis && ch == ")") {
        this.expect(")");
        break;
      } else if (ch == "(") {
        arr.push(await this.getList());
      } else if (ch == '"' || ch == "{") {
        arr.push(await this.getString2());
      } else if (ch == "\\") {
        this.expect("\\");
        arr.push(this.getAtom());
      } else if (isDigit(ch)) {
        arr.push(this.getNumber());
      } else {
        arr.push(this.getAtom());
      }
    }
    return arr;
  }
}
