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

import { getLogger } from "../utils/log";
import type { Connection } from "./network";
import {
  base64Encode,
  decodeCharset,
  decodeUtf7,
  encodeUtf7,
} from "../utils/encodings";
import { isDigit, wrapCallback } from "../utils/common";
import { ProtocolBase } from "./protocol_base";
import type { ICommand } from "./protocol_base";
import type {
  ServerStatusResponse,
  StatusItem,
  ResponseCode,
  ImapList,
} from "./tokenizer";
import type { Atom } from "./tokenizer";
import { Atoms, Tokenizer, } from "./tokenizer";
import type { IBuffer, IBufferCreator } from "../api";
import { MemBuffer, memBufferCreator } from "../utils/file_stream";

export { Atoms } from "./tokenizer";

const logger = getLogger("protocol:imap");
const CRLF = "\r\n";

function idString(id: number): string {
  const zeros = id < 10 ? "00" : id < 100 ? "0" : "";
  return zeros + id.toString();
}

export type ImapResponse = {
  type: ImapResponseType;
  [key: string]: unknown;
};

export enum ImapResponseType {
  raw,
  result,
  capability,
  list,
  lsub,
  status,
  fetch,
  search,
  continue,
  flags,
  recent,
  exists,
}

export type ResultResponse = {
  status: ServerStatusResponse;
  text: string;
  type: ImapResponseType.result;
  responseCode?: ResponseCode;
  uidValidity?: number;
  flags?: Atom[];
};

export type ListResponse = {
  flags: Atom[];
  delimiter: string;
  name: string;
  type: ImapResponseType.list;
};

export type StatusResponse = {
  type: ImapResponseType.status;
  name: string;
  attributes: Map<StatusItem, number>;
};

type Address = {
  a: string;
  b: string;
  c: string;
  d: string;
};

type Envelope = {
  date?: string;
  subject?: string;
  from: Address[];
  sender: Address[];
  reply_to: Address[];
  to?: Address[];
  cc?: Address[];
  bcc?: Address[];
  in_reply_to?: Address[];
  message_id?: string;
};

export type FetchResponse = {
  type: ImapResponseType.fetch;
  index: number;
  flags?: Atom[];
  uid?: number;
  rfc822_size?: number;
  // rfc3501 envelope data: date, subject, from, sender, reply-to,
  // to, cc, bcc, in-reply-to, and message-id
  envelope?: ImapList;
  body?: IBuffer;
  part?: string;
  offset?: number;
  bodyStructure?: ImapList;
  internalDate?: string;
  rfc822?: string;
  rfc822_header?: string;
  rfc822_text?: string;
  rfc822_header_fields?: string;
};

async function parseResult(
  status: ServerStatusResponse,
  tokenizer: Tokenizer
): Promise<ResultResponse> {
  // const status = tokenizer.getAtom();
  const ch = tokenizer.peekNextChar();
  const resp: ResultResponse = {
    status: status,
    text: "",
    type: ImapResponseType.result,
  };
  if (ch == "[") {
    tokenizer.expect("[");
    const code = tokenizer.getAtom();
    resp.responseCode = code as ResponseCode;
    if (code == Atoms.PERMANENTFLAGS) {
      resp.flags = await tokenizer.getList() as Atoms[];
    } else if (code == Atoms.UIDVALIDITY) {
      resp.uidValidity = tokenizer.getNumber();
    }
    tokenizer.getUntil("]");
    tokenizer.expect("]");
  }
  resp.text = tokenizer.getUntil(CRLF);
  return resp;
}

function parseRaw(tokenizer: Tokenizer): ImapResponse {
  return {
    name: "",
    text: tokenizer.getUntil(CRLF),
    type: ImapResponseType.raw,
  };
}

async function parseLIST(tokenizer: Tokenizer): Promise<ListResponse> {
  const attrs = await tokenizer.getList();
  let delimiter = (await tokenizer.getString2()) as string;
  const name = decodeUtf7((await tokenizer.getString2()) as string);
  return {
    flags: attrs as Atoms[],
    delimiter,
    name,
    type: ImapResponseType.list,
  };
}

async function parseSTATUS(tokenizer: Tokenizer): Promise<StatusResponse> {
  const ch = tokenizer.peekNextChar();
  let _name: string;
  if (ch == '"' || ch == "{") {
    _name = (await tokenizer.getString2()) as string;
  } else {
    _name = tokenizer.getUntil(" ");
  }
  const name = decodeUtf7(_name);
  tokenizer.expect("(");
  const attrs: Map<StatusItem, number> = new Map();
  while (true) {
    const ch = tokenizer.peekNextChar();
    if (ch == ")") {
      tokenizer.expect(")");
      break;
    }
    const item = tokenizer.getAtom() as StatusItem;
    const value = tokenizer.getNumber();
    attrs.set(item, value);
  }

  return {
    type: ImapResponseType.status,
    name,
    attributes: attrs,
  };
}

async function parseFETCH(
  index: number,
  tokenizer: Tokenizer
): Promise<FetchResponse> {
  tokenizer.expect("(");
  let resp: FetchResponse = {
    index,
    type: ImapResponseType.fetch,
  };
  while (true) {
    const c = tokenizer.peekNextChar();
    if (c == ")") {
      tokenizer.expect(")");
      break;
    }
    const token = tokenizer.getAtom();
    if (!token) {
      break;
    }
    if (token == Atoms.UID) {
      resp.uid = tokenizer.getNumber();
    } else if (token == Atoms.FLAGS) {
      resp.flags = await tokenizer.getList() as Atoms[];
    } else if (token == Atoms.RFC822_SIZE) {
      resp.rfc822_size = tokenizer.getNumber();
    } else if (token == Atoms.BODY) {
      const ch = tokenizer.peekNextChar();
      if (ch == "[") {
        tokenizer.expect("[");
        resp.part = tokenizer.getUntil("]");
        tokenizer.expect("]");
        const ch = tokenizer.peekNextChar();
        if (ch == "<") {
          tokenizer.expect("<");
          resp.offset = tokenizer.getNumber();
          tokenizer.expect(">");
        }
        resp.body = await tokenizer.getStringStream();
      } else if (ch == "(") {
        resp.bodyStructure = await tokenizer.getList();
      }
    } else if (token == Atoms.BODYSTRUCTURE) {
      resp.bodyStructure = await tokenizer.getList();
    } else if (token == Atoms.ENVELOPE) {
      resp.envelope = await tokenizer.getList();
    } else if (token == Atoms.INTERNALDATE) {
      resp.internalDate = await tokenizer.getString2()
    }
  }
  return resp;
}

type parser = (tokenizer: Tokenizer) => ImapResponse | Promise<ImapResponse>;

const parserMap = new Map<Atoms, parser>([
  [Atoms.OK, (t: Tokenizer): Promise<ResultResponse> => parseResult(Atoms.OK, t)],
  [Atoms.NO, (t: Tokenizer): Promise<ResultResponse> => parseResult(Atoms.NO, t)],
  [Atoms.BAD, (t: Tokenizer): Promise<ResultResponse> => parseResult(Atoms.BAD, t)],
  [Atoms.BYE, (t: Tokenizer): Promise<ResultResponse> => parseResult(Atoms.BYE, t)],
  [Atoms.PREAUTH, (t: Tokenizer): Promise<ResultResponse> => parseResult(Atoms.PREAUTH, t)],
  [Atoms.LIST, parseLIST],
  [Atoms.LSUB, parseLIST],
  [Atoms.STATUS, parseSTATUS],
  [
    Atoms.FLAGS,
    async (tokenizer: Tokenizer): Promise<ImapResponse> => ({
      type: ImapResponseType.flags,
      flags: await tokenizer.getList(),
    }),
  ],
  [
    Atoms.SEARCH,
    async (tokenizer: Tokenizer): Promise<ImapResponse> => {
      return {
        type: ImapResponseType.search,
        ids: await tokenizer.getList(false),
      };
    },
  ],
  [
    Atoms.CAPABILITY,
    async (tokenizer: Tokenizer): Promise<ImapResponse> => {
      return {
        type: ImapResponseType.capability,
        capabilities: await tokenizer.getList(false),
      };
    },
  ],
]);

function parseResponse(
  tokenizer: Tokenizer
): ImapResponse | Promise<ImapResponse> {
  const ch = tokenizer.peekNextChar();
  if (isDigit(ch)) {
    const num = tokenizer.getNumber();
    const command = tokenizer.getAtom();
    if (command == Atoms.FETCH) return parseFETCH(num, tokenizer);
    else if (command == Atoms.RECENT) {
      return {
        type: ImapResponseType.recent,
        recent: num,
      };
    } else if (command == Atoms.EXISTS) {
      return {
        type: ImapResponseType.exists,
        exists: num,
      };
    } else return parseRaw(tokenizer);
  } else {
    const command = tokenizer.getAtom();
    if (typeof command == "string") {
      const resp = parseRaw(tokenizer);
      resp.name = command;
      return resp;
    }
    const parser = parserMap.get(command);
    if (parser) {
      return parser(tokenizer);
    }
  }
  return parseRaw(tokenizer);
}
class IMAPCommand implements ICommand<ImapResponse[]> {
  command: string;
  tag: string;
  extra?: IBuffer;
  _bufferCreator: IBufferCreator = memBufferCreator;
  constructor(command: string, tag: string, extra?: IBuffer) {
    this.command = command;
    this.tag = tag;
    this.extra = extra;
  }

  setBufferCreator(creator: IBufferCreator): void {
    this._bufferCreator = creator;
  }

  async do(conn: Connection): Promise<ImapResponse[]> {
    conn.send(`${this.tag} ${this.command}${CRLF}`);
    const tokenizer = new Tokenizer(conn);
    tokenizer.setBufferCreator(this._bufferCreator);
    await tokenizer.feed();
    let respList: ImapResponse[] = [];
    while (true) {
      const ch = tokenizer.peekNextChar();
      if (ch == "*") {
        tokenizer.expect("*");
        const resp = await parseResponse(tokenizer);
        respList.push(resp);
        await tokenizer.feed();
      } else if (ch == "+") {
        respList.push({ type: ImapResponseType.continue });
        tokenizer.getUntil(CRLF);
        if (this.extra) {
          for await (const buf of this.extra) {
            conn.send(buf);
            conn.send(CRLF);
            await tokenizer.feed();
            // await delay(100);
          }
        } else {
          break;
        }
      } else {
        tokenizer.expect(this.tag);
        const resp = await parseResponse(tokenizer);
        respList.push(resp);
        break;
      }
    }
    return respList;
  }
}

export class IMAPProtocol extends ProtocolBase {
  _id: number = 1;
  _idPrefix: string = "MCCM";
  _close: boolean = false;
  constructor(host: string, port: number, isSSL: boolean, ca: string[] = []) {
    super(host, port, isSSL, ca);
    logger.log("new IMAPProtocol");
  }

  setIdPrefix(prefix: string): void {
    this._idPrefix = prefix;
  }

  async onConnected(): Promise<void> {
    logger.debug("ignore the first line")
    await this.conn.getData(new Uint8Array([13, 10]));
  }

  getCommandId(): string {
    this._id += 1;
    return `${this._idPrefix}${idString(this._id)}`;
  }

  execCommand(
    command: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    logger.debug('execute command', command);
    const commandObj = new IMAPCommand(command, this.getCommandId());
    commandObj.setBufferCreator(this._bufferCreator);
    return wrapCallback(
      this.doCommand(commandObj).catch((err: Error) => {
        logger.debug("error", command, err);
        logger.error("execCommand failed");
        const r: ResultResponse = {
          type: ImapResponseType.result,
          status: Atoms.BAD,
          text: err.message,
        };
        return [r];
      }),
      callback
    );
  }

  capability(): Promise<ImapResponse[]>;
  capability(callback: (data: ImapResponse[]) => void): void;
  capability(
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand("CAPABILITY", callback);
  }

  select(folder: string): Promise<ImapResponse[]>;
  select(folder: string, callback: (data: ImapResponse[]) => void): void;
  select(
    folder: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand(`SELECT "${encodeUtf7(folder)}"`, callback);
  }

  fetch(sequence: [number, number], param: string): Promise<ImapResponse[]>;
  fetch(
    sequence: [number, number],
    param: string,
    callback: (data: ImapResponse[]) => void
  ): void;
  fetch(
    sequence: [number, number],
    param: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    const itemStr = param;
    return this.execCommand(
      `FETCH ${sequence[0]}:${sequence[1]} (${itemStr})`,
      callback
    );
  }

  uidFetch(uid: string, param: string): Promise<ImapResponse[]>;
  uidFetch(
    uid: string,
    param: string,
    callback: (data: ImapResponse[]) => void
  ): void;
  uidFetch(
    uid: string,
    param: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    const itemStr = param;
    return this.execCommand(`UID FETCH ${uid} (${itemStr})`, callback);
  }

  uidStore(uid: string, param: string): Promise<ImapResponse[]>;
  uidStore(
    uid: string,
    param: string,
    callback: (data: ImapResponse[]) => void
  ): void;
  uidStore(
    uid: string,
    param: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    const itemStr = param;
    return this.execCommand(`UID STORE ${uid} ${itemStr}`, callback);
  }

  status(mailbox: string, statusItems: StatusItem[]): Promise<ImapResponse[]>;
  status(
    mailbox: string,
    statusItems: StatusItem[],
    callback: (data: ImapResponse[]) => void
  ): void;
  status(
    mailbox: string,
    statusItems: StatusItem[],
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    const s = statusItems.map(item => Atoms[item]);
    return this.execCommand(
      `STATUS "${encodeUtf7(mailbox)}" (${s.join(" ")})`,
      callback
    );
  }

  list(base: string, template: string): Promise<ImapResponse[]>;
  list(
    base: string,
    template: string,
    callback: (data: ImapResponse[]) => void
  ): void;
  list(
    base: string,
    template: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand(`LIST "${base}" "${template}"`, callback);
  }

  lsub(base: string, template: string): Promise<ImapResponse[]>;
  lsub(
    base: string,
    template: string,
    callback: (data: ImapResponse[]) => void
  ): void;
  lsub(
    base: string,
    template: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand(`LSUB "${base}" "${template}"`, callback);
  }

  login(user: string, pass: string): Promise<ImapResponse[]>;
  login(
    user: string,
    pass: string,
    callback: (data: ImapResponse[]) => void
  ): void;
  login(
    user: string,
    pass: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand(`LOGIN ${user} ${pass}`, callback);
  }

  logout(): Promise<ImapResponse[]>;
  logout(callback: (data: ImapResponse[]) => void): void;
  logout(
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand("LOGOUT", callback);
  }

  id(params: string): Promise<ImapResponse[]>;
  id(params: string, callback: (data: ImapResponse[]) => void): void;
  id(
    params: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand(`ID (${params})`, callback);
  }

  search(criteria: string): Promise<ImapResponse[]>;
  search(criteria: string, callback: (data: ImapResponse[]) => void): void;
  search(
    criteria: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    const s = new MemBuffer();
    const ss = criteria.split("\r\n");
    logger.debug("search", ss, criteria.replace(/\r\n/g, "\\r\\n"));
    for (let i = 1; i < ss.length; i++) {
      s.feed(ss[i]);
    }
    s.end();
    const command = `UID SEARCH ${ss[0]}`;
    return wrapCallback(
      this.doCommand(new IMAPCommand(command, this.getCommandId(), s))
        .catch((err: Error) => {
          const r: ResultResponse = {
            type: ImapResponseType.result,
            status: Atoms.BAD,
            text: err.message,
          };
          return [r];
        }
      ),
      callback
    );
  }

  create(folder: string, delimiter: string): Promise<ImapResponse[]>;
  create(
    folder: string,
    delimiter: string,
    callback: (data: ImapResponse[]) => void
  ): void;
  create(
    folder: string,
    delimiter: string = "",
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    let folderName = folder;
    if (delimiter.length) {
      folderName = folder.split(delimiter).map(encodeUtf7).join(delimiter);
    }
    return this.execCommand(`CREATE "${folderName}"`, callback);
  }

  rename(folder: string, newName: string): Promise<ImapResponse[]>;
  rename(
    folder: string,
    newName: string,
    callback: (data: ImapResponse[]) => void
  ): void;
  rename(
    folder: string,
    newName: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand(
      `RENAME "${encodeUtf7(folder)}" "${encodeUtf7(newName)}"`,
      callback
    );
  }

  delete(folder: string): Promise<ImapResponse[]>;
  delete(folder: string, callback: (data: ImapResponse[]) => void): void;
  delete(
    folder: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand(`DELETE "${encodeUtf7(folder)}"`, callback);
  }

  close(): Promise<ImapResponse[]>;
  close(callback: (data: ImapResponse[]) => void): void;
  close(
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand("CLOSE", callback);
  }

  noop(): Promise<ImapResponse[]>;
  noop(callback: (data: ImapResponse[]) => void): void;
  noop(
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand("NOOP", callback);
  }

  expunge(): Promise<ImapResponse[]>;
  expunge(callback: (data: ImapResponse[]) => void): void;
  expunge(
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand("EXPUNGE", callback);
  }

  uidCopy(mailId: string, folder: string): Promise<ImapResponse[]>;
  uidCopy(
    mailId: string,
    folder: string,
    callback: (data: ImapResponse[]) => void
  ): void;
  uidCopy(
    mailId: string,
    folder: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    return this.execCommand(
      `UID COPY ${mailId} "${encodeUtf7(folder)}"`,
      callback
    );
  }

  append(folder: string, mail: string): Promise<ImapResponse[]>;
  append(
    folder: string,
    mail: string,
    callback: (data: ImapResponse[]) => void
  ): void;
  append(
    folder: string,
    mail: string,
    callback?: (data: ImapResponse[]) => void
  ): Promise<ImapResponse[]> | void {
    const command = `APPEND "${encodeUtf7(folder)}" {${mail.length}}`;
    const extra = new MemBuffer();
    extra.end(mail);
    return wrapCallback(
      this.doCommand(new IMAPCommand(command, this.getCommandId(), extra)),
      callback
    );
  }
}
