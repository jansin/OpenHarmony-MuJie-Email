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
import { isPOP3ResponseOK } from "../utils/pop3_utils";
import { base64Encode, decodeCharset } from "../utils/encodings";
import { wrapCallback, assert, delay } from "../utils/common";
import type { ICommand } from "./protocol_base";
import { ProtocolBase } from "./protocol_base";
import type { RawResult } from "./protocol_base";
import type { CMError } from "../api";
import { Tokenizer } from "./tokenizer";

const logger = getLogger("protocol:smtp");

const CRLF = "\r\n";

export enum SMTP_CODE {
  SERVICE_READY = 220,
  SERVICE_CLOSE = 221,
  AUTH_SUCCESS = 235,
  OK = 250,
  START_MAIL_INPUT = 354,
  AUTH_LOGIN = 334,
  AUTH_CANCEL = 501,
  AUTH_ERROR = 535,
  COMMAND_ERROR = 500,
  COMMAND_PARAM_ERROR = 501,
  COMMAND_SEQ_ERROR = 503,
  MAILBOX_ERROR = 550,
  TRANSACTION_FAILED = 554,
}
type RawResultWithCode = RawResult & { code: SMTP_CODE };
type SmtpResponse = {
  code: SMTP_CODE;
  message: string[];
};

async function getResponse(conn: Connection): Promise<SmtpResponse> {
  const tokenizer = new Tokenizer(conn);
  await tokenizer.feed();
  const code = tokenizer.getNumber();
  const content: string[] = [];
  let ch = tokenizer.peekNextChar();
  while (ch == "-") {
    tokenizer.expect("-");
    let line = tokenizer.getUntil(CRLF);
    content.push(line);
    await tokenizer.feed();
    const code2 = tokenizer.getNumber();
    assert(code2 == code);
    ch = tokenizer.peekNextChar();
  }
  let line = tokenizer.getUntil(CRLF);
  content.push(line);
  return { code, message: content };
}

const MAX_SIZE_TO_SEND = 1024 * 100;
class SMTPCommand implements ICommand<SmtpResponse> {
  data: string[] = [];
  ok: boolean = true;
  command: string = "";
  constructor(command: string) {
    this.command = command;
  }
  async do(conn: Connection): Promise<SmtpResponse> {
    if (this.command.length < MAX_SIZE_TO_SEND) {
      conn.send(this.command + "\r\n");
    } else {
      for (let i = 0; i < this.command.length; i += MAX_SIZE_TO_SEND) {
        await conn.send(this.command.substring(i, i + MAX_SIZE_TO_SEND));
      }
      conn.send("\r\n");
    }
    const resp = await getResponse(conn);

    return resp;
  }
}

export type SMTP_Extention = {
  name: string;
};

export class SmtpProtocol extends ProtocolBase {
  constructor(host: string, port: number, isSSL: boolean, ca: string[] = []) {
    super(host, port, isSSL, ca);
  }

  async onConnected(): Promise<void> {
    const resp = await getResponse(this.conn);
    logger.debug("onConnected", resp);
  }

  auth(user: string, pass: string): Promise<SmtpResponse>;
  auth(
    user: string,
    pass: string,
    callback: (data: SmtpResponse) => void,
    onError: (err: CMError) => void
  ): void;
  auth(
    user: string,
    pass: string,
    callback?: (data: SmtpResponse) => void,
    onError?: (err: CMError) => void
  ): Promise<SmtpResponse> | void {
    return wrapCallback(
      (async (): Promise<SmtpResponse> => {
        let res = await this.doCommand(new SMTPCommand("AUTH LOGIN"));
        if (res.code != SMTP_CODE.AUTH_LOGIN) {
          return res;
        }
        res = await this.doCommand(new SMTPCommand(base64Encode(user)));
        if (res.code != SMTP_CODE.AUTH_LOGIN) {
          return res;
        }
        res = await this.doCommand(new SMTPCommand(base64Encode(pass)));
        if (res.code != SMTP_CODE.AUTH_LOGIN) {
          return res;
        }
        return res;
      })(),
      callback,
      onError
    );
  }

  mail(email: string): Promise<SmtpResponse>;
  mail(
    email: string,
    callback: (data: SmtpResponse) => void,
    onError: (err: CMError) => void
  ): void;
  mail(
    email: string,
    callback?: (data: SmtpResponse) => void,
    onError?: (err: CMError) => void
  ): Promise<SmtpResponse> | void {
    return wrapCallback(
      this.doCommand(new SMTPCommand(`MAIL FROM: <${email}>`)),
      callback,
      onError
    );
  }

  rcpt(email: string): Promise<SmtpResponse>;
  rcpt(
    email: string,
    callback: (data: SmtpResponse) => void,
    onError?: (err: CMError) => void
  ): void;
  rcpt(
    email: string,
    callback?: (data: SmtpResponse) => void,
    onError?: (err: CMError) => void
  ): Promise<SmtpResponse> | void {
    return wrapCallback(
      this.doCommand(new SMTPCommand(`RCPT TO: <${email}>`)),
      callback
    );
  }

  data(data: string): Promise<SmtpResponse>;
  data(
    data: string,
    callback: (data: SmtpResponse) => void,
    onError: (err: CMError) => void
  ): void;
  data(
    data: string,
    callback?: (data: SmtpResponse) => void,
    onError?: (err: CMError) => void
  ): Promise<SmtpResponse> | void {
    return wrapCallback(
      (async (): Promise<SmtpResponse> => {
        let res = await this.doCommand(new SMTPCommand(`DATA`));
        logger.log("data", res);
        if (res.code == SMTP_CODE.START_MAIL_INPUT) {
          res = await this.doCommand(
            new SMTPCommand(data.replace(/\r\n\./g, "\r\n..") + "\r\n.")
          );
        }
        return res;
      })(),
      callback
    );
  }

  helo(host: string): Promise<SmtpResponse>;
  helo(
    host: string,
    callback: (data: SmtpResponse) => void,
    onError: (err: CMError) => void
  ): void;
  helo(
    host: string,
    callback?: (data: SmtpResponse) => void,
    onError?: (err: CMError) => void
  ): Promise<SmtpResponse> | void {
    return wrapCallback(
      this.doCommand(new SMTPCommand(`HELO ${host}`)),
      callback
    );
  }

  ehlo(host: string): Promise<SmtpResponse>;
  ehlo(
    host: string,
    callback: (data: SmtpResponse) => void,
    onError: (err: CMError) => void
  ): void;
  ehlo(
    host: string,
    callback?: (data: SmtpResponse) => void,
    onError?: (err: CMError) => void
  ): Promise<SmtpResponse> | void {
    return wrapCallback(
      this.doCommand(new SMTPCommand(`EHLO ${host}`)),
      callback
    );
  }

  quit(): Promise<SmtpResponse>;
  quit(
    callback: (data: SmtpResponse) => void,
    onError: (err: CMError) => void
  ): void;
  quit(
    callback?: (data: SmtpResponse) => void,
    onError?: (err: CMError) => void
  ): Promise<SmtpResponse> | void {
    return wrapCallback(this.doCommand(new SMTPCommand(`QUIT`)), callback);
  }

  noop(): void {
  }
}
