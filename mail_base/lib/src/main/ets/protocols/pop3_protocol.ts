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
import { isPOP3ResponseERR, isPOP3ResponseOK } from "../utils/pop3_utils";
import { CRLF, delay, wrapCallback } from "../utils/common";
import { ProtocolBase } from "./protocol_base";
import type { ICommand } from "./protocol_base";
import { decodeCharset } from "../utils/encodings";
import { getLogger } from "../utils/log";
import type { IBuffer, IBufferCreator } from "../api";
import { createBuffer, memBufferCreator } from "../utils/file_stream";
import { findBuffer, replaceBufferData } from '../utils/buffer_utils';

const logger = getLogger("protocol:pop3");

const POP3_EndLine = new Uint8Array([13, 10]);
const POP3_EndBlock = new Uint8Array([13, 10, 0x2e, 13, 10]);
const POP3_Pattern = new Uint8Array([13, 10, 0x2e, 0x2e]);
const POP3_Replace = new Uint8Array([13, 10, 0x2e]);

export enum Pop3ResponseType {
  LIST,
  UIDL,
  RETR,
  USER,
  PASS,
  UNKNOWN,
}

export enum Pop3ResponseStatus {
  OK,
  ERR,
}

export type Pop3ListResponse = {
  type: Pop3ResponseType.LIST;
  status: Pop3ResponseStatus;
  list: [number, number][];
};
export type Pop3UidlResponse = {
  type: Pop3ResponseType.UIDL;
  status: Pop3ResponseStatus;
  list: [number, string][];
};
export type Pop3RetrResponse = {
  type: Pop3ResponseType.RETR;
  status: Pop3ResponseStatus;
  data: IBuffer;
};

export type Pop3Response = {
  type: Pop3ResponseType;
  status: Pop3ResponseStatus;
  data?: unknown;
};

function parseUIDL(ok: boolean, data: string[]): Pop3UidlResponse {
  const list: [number, string][] = [];
  if (ok) {
    for (const d of data) {
      try {
        const [index, uid] = d.trim().split(/\s+/, 2);
        list.push([parseInt(index), uid]);
      } catch (e) {
        logger.error("parse list failed", d, e);
      }
    }
  }
  return {
    type: Pop3ResponseType.UIDL,
    status: ok ? Pop3ResponseStatus.OK : Pop3ResponseStatus.ERR,
    list,
  };
}

function parseLIST(ok: boolean, data: string[]): Pop3ListResponse {
  const list: [number, number][] = [];
  if (ok) {
    for (const d of data) {
      try {
        const [index, size] = d.trim().split(/\s+/, 2);
        list.push([parseInt(index), parseInt(size)]);
      } catch (e) {
        logger.error("parse list failed", d, e);
      }
    }
  }
  return {
    type: Pop3ResponseType.LIST,
    status: ok ? Pop3ResponseStatus.OK : Pop3ResponseStatus.ERR,
    list,
  };
}
class POP3Command implements ICommand<Pop3Response> {
  isBlock: boolean = false;
  command: string = "";
  _bufferCreator: IBufferCreator = memBufferCreator;

  constructor(command: string, isBlock: boolean, useStream: boolean = false) {
    this.isBlock = isBlock;
    this.command = command;
  }

  setBufferCreator(creator: IBufferCreator): void {
    this._bufferCreator = creator;
  }

  async do(conn: Connection): Promise<Pop3Response> {
    conn.send(this.command + "\r\n");

    const isRetr = this.command.startsWith("RETR");
    let buffer: IBuffer | undefined;
    if (isRetr) {
      buffer = this._bufferCreator.createBuffer({useFile: true});
    }
    let res = decodeCharset(await conn.getData(POP3_EndLine));
    let data: string[] = [];
    let ok = isPOP3ResponseOK(res);
    if (ok) {
      if (!this.isBlock) {
        data.push(res.substring(res.indexOf(" ") + 1));
      } else {
        if (buffer) {
          let remain = new Uint8Array(0);
          let finished = false;
          while (!finished && conn.isConnected()) {
            let buff = await conn.getMaxData(100 * 1024);
            if (buff.byteLength == 0) {
              await delay(10);
              continue;
            }
            if (remain.byteLength > 0) {
              const newBuff = new Uint8Array(buff.byteLength + remain.byteLength);
              newBuff.set(remain);
              newBuff.set(buff, remain.byteLength);
              buff = newBuff;
              remain = new Uint8Array(0);
            }
            const endIndex = findBuffer(buff, POP3_EndBlock);
            if (endIndex > 0) {
              finished = true;
              buff = buff.subarray(0, endIndex + 2); // 加上换行回车
            } else {
              const ch = buff[buff.byteLength - 1];
              if (ch == 13 || ch == 10 || ch == 0x2e) {
                remain = buff.subarray(buff.byteLength - 4);
                buff = buff.subarray(0, buff.byteLength - 4);
              }
              buff = replaceBufferData(buff, POP3_Pattern, POP3_Replace);
            }
            await buffer.feed(buff);
          }
        } else {
          let buff = await conn.getData(POP3_EndBlock);
          const s = decodeCharset(buff).replace(/\r\n\.\./g, '\r\n.');
          data = s.split('\r\n');
        }
      }
      if (buffer) {
        await buffer.end();
      }
    }
    if (this.command.startsWith("LIST")) {
      return parseLIST(ok, data);
    } else if (this.command.startsWith("UIDL")) {
      return parseUIDL(ok, data);
    } else if (isRetr) {
      const resp: Pop3RetrResponse = {
        status: ok ? Pop3ResponseStatus.OK : Pop3ResponseStatus.ERR,
        type: Pop3ResponseType.RETR,
        data: buffer!,
      };
      return resp;
    } else {
      let type =
        Pop3ResponseType[
          this.command.split(" ")[0] as keyof typeof Pop3ResponseType
        ];
      if (!type) {
        type = Pop3ResponseType.UNKNOWN;
      }

      return {
        status: ok ? Pop3ResponseStatus.OK : Pop3ResponseStatus.ERR,
        type,
        data,
      };
    }
  }
}
export class Pop3Protocol extends ProtocolBase {
  _bufferCreator: IBufferCreator = memBufferCreator;

  constructor(host: string, port: number, isSSL: boolean, ca: string[] = []) {
    super(host, port, isSSL, ca);
  }

  setBufferCreator(creator: IBufferCreator): void {
    this._bufferCreator = creator;
  }

  async onConnected(): Promise<void> {
    await this.conn.getData(POP3_EndLine);
  }

  user(username: string): Promise<boolean>;
  user(username: string, callback: (data: boolean) => void): void;
  user(
    username: string,
    callback?: (data: boolean) => void
  ): Promise<boolean> | void {
    return wrapCallback(
      this.doCommand<Pop3Response>(
        new POP3Command(`USER ${username}`, false)
      ).then(res => {
        return res.status == Pop3ResponseStatus.OK;
      }),
      callback
    );
  }

  apop(username: string, digest: string): Promise<boolean>;
  apop(
    username: string,
    digest: string,
    callback: (data: boolean) => void
  ): void;
  apop(
    username: string,
    digest: string,
    callback?: (data: boolean) => void
  ): Promise<boolean> | void {
    return wrapCallback(
      this.doCommand<Pop3Response>(
        new POP3Command(`APOP ${username} ${digest}`, false)
      ).then((res: Pop3Response) => {
        return res.status == Pop3ResponseStatus.OK;
      }),
      callback
    );
  }

  pass(password: string): Promise<boolean>;
  pass(password: string, callback: (data: boolean) => void): void;
  pass(
    password: string,
    callback?: (data: boolean) => void
  ): Promise<boolean> | void {
    return wrapCallback(
      this.doCommand<Pop3Response>(
        new POP3Command(`PASS ${password}`, false)
      ).then((res: Pop3Response) => {
        return res.status == Pop3ResponseStatus.OK;
      }),
      callback
    );
  }

  stat(): Promise<boolean>;
  stat(callback: (data: boolean) => void): void;
  stat(callback?: (data: boolean) => void): Promise<boolean> | void {
    return wrapCallback(
      this.doCommand<Pop3Response>(new POP3Command(`STAT`, false)).then(
        (res: Pop3Response) => {
          return res.status == Pop3ResponseStatus.OK;
        }
      ),
      callback
    );
  }

  uidl(mailId: number | void): Promise<Pop3UidlResponse>;
  uidl(mailId: number | void, callback: (data: Pop3UidlResponse) => void): void;
  uidl(
    mailId: number | void,
    callback?: (data: Pop3UidlResponse) => void
  ): Promise<Pop3UidlResponse> | void {
    let para = "";
    if (mailId) {
      para = ` ${mailId.toString()}`;
    }
    const isBlock = mailId ? false : true;
    return wrapCallback(
      this.doCommand<Pop3Response>(
        new POP3Command(`UIDL${para}`, isBlock)
      ) as Promise<Pop3UidlResponse>,
      callback
    );
  }

  list(): Promise<Pop3ListResponse>;
  list(callback: (data: Pop3ListResponse) => void, onError?: () => void): void;
  list(
    callback?: (data: Pop3ListResponse) => void,
    _onError?: () => void
  ): Promise<Pop3ListResponse> | void {
    return wrapCallback(
      this.doCommand(
        new POP3Command(`LIST`, true)
      ) as Promise<Pop3ListResponse>,
      callback
    );
  }

  retr(mailId: number): Promise<Pop3RetrResponse>;
  retr(mailId: number, callback: (data: Pop3RetrResponse) => void): void;
  retr(
    mailId: number,
    callback?: (data: Pop3RetrResponse) => void
  ): Promise<Pop3RetrResponse> | void {
    const command = new POP3Command(`RETR ${mailId.toString()}`, true);
    command.setBufferCreator(this._bufferCreator);
    return wrapCallback(
      this.doCommand<Pop3Response>(
        command
      ) as Promise<Pop3RetrResponse>,
      callback
    );
  }

  top(mailId: number, lineNumber: number): Promise<string[]>;
  top(
    mailId: number,
    lineNumber: number,
    callback: (data: string[]) => void
  ): void;
  top(
    mailId: number,
    lineNumber: number,
    callback?: (data: string[]) => void
  ): Promise<string[]> | void {
    return wrapCallback(
      this.doCommand<Pop3Response>(
        new POP3Command(`TOP ${mailId.toString()}`, true)
      ).then((res: Pop3Response) => {
        return [""];
      }),
      callback
    );
  }

  dele(mailId: number): Promise<boolean>;
  dele(mailId: number, callback: (data: boolean) => void): void;
  dele(
    mailId: number,
    callback?: (data: boolean) => void
  ): Promise<boolean> | void {
    return wrapCallback(
      this.doCommand<Pop3Response>(new POP3Command(`DELE ${mailId}`, false)).then(
        (res: Pop3Response) => {
          return res.status == Pop3ResponseStatus.OK;
        }
      ),
      callback
    );
  }
  rest(): Promise<boolean>;
  rest(callback: (data: boolean) => void): void;
  rest(callback?: (data: boolean) => void): Promise<boolean> | void {
    return wrapCallback(
      this.doCommand<Pop3Response>(new POP3Command(`REST`, false)).then(
        (res: Pop3Response) => {
          return res.status == Pop3ResponseStatus.OK;
        }
      ),
      callback
    );
  }

  quit(): Promise<boolean>;
  quit(callback: (data: boolean) => void): void;
  quit(callback?: (data: boolean) => void): Promise<boolean> | void {
    return wrapCallback(
      this.doCommand<Pop3Response>(new POP3Command(`QUIT`, false)).then(
        (res: Pop3Response) => {
          return res.status == Pop3ResponseStatus.OK;
        }
      ),
      callback
    );
  }

  noop(): Promise<boolean>;
  noop(callback: (data: boolean) => void): void;
  noop(callback?: (data: boolean) => void): Promise<boolean> | void {
    return wrapCallback(
      this.doCommand<Pop3Response>(new POP3Command(`NOOP`, false)).then(
        (res: Pop3Response) => {
          return res.status == Pop3ResponseStatus.OK;
        }
      ),
      callback
    );
  }

  stls(): Promise<void>;
  stls(callback: () => void): void;
  stls(callback?: () => void): Promise<void> | void {
    return wrapCallback(
      this.doCommand<Pop3Response>(new POP3Command("STLS", false)).then(
        (res: Pop3Response) => {
          if (res.status == Pop3ResponseStatus.OK) {
            this.conn.startTLS();
          }
        }
      ),
      callback
    );
  }
}
