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

import { Connection, NetworkState } from "./network";
import { getLogger } from "../utils/log";
import type { IBufferCreator } from "../api";
import { CMError, ErrorCode } from "../api";
import { memBufferCreator } from '../utils/file_stream';
import { delay } from '../utils/common';

const logger = getLogger("protocol");

export type RawResult = {
  ok: boolean;
  data: string[];
};

export interface ICommand<T> {
  do(conn: Connection): Promise<T>;
}

export class ProtocolBase {
  conn: Connection;
  nextPromise?: Promise<unknown>;
  _hasError: boolean = false;
  _idle: boolean = true;
  _bufferCreator: IBufferCreator = memBufferCreator;
  constructor(host: string, port: number, isSSL: boolean, ca: string[] = []) {
    this.conn = new Connection(host, port, isSSL, ca);
  }

  async connect() : Promise<void> {
    logger.debug('connect')
    await this.conn.connect();
    await this.onConnected();
  }

  setBufferCreator(creator: IBufferCreator): void {
    this._bufferCreator = creator;
  }

  async onConnected(): Promise<void> {
    logger.debug("onConnected");
  }

  hasError(): boolean {
    return this._hasError;
  }

  isReady(): boolean {
    return this.conn.state == NetworkState.CONNECTED;
  }

  async doCommand<T>(command: ICommand<T>): Promise<T> {
    logger.trace("do command", command, this.conn.state)
    if (!this.isReady()) {
      const text = "do command when connection failed";
      logger.error("doCommand no connection", command)
      return Promise.reject(new CMError(text))
    }
    logger.trace("promise  ")
    const np = this.nextPromise ? this.nextPromise : Promise.resolve();
    this.nextPromise = new Promise<T>((resolve, reject) => {
      logger.trace("promise next")
      np.catch(e => { logger.trace("promise catch", e); }).then(() => {
        logger.trace("promise then")
        let success = false;
        this._idle = false;
        if (!this.isReady()) {
          reject(new CMError(
            "connection error",
            ErrorCode.CONNECT_FAILED
          ))
        }
        command.do(this.conn)
          .then((value: T) => {
            success = true;
            resolve(value);
            this._idle = true;
          })
          .catch((err: unknown) => {
            this._idle = true;
            this._hasError = true;
            this.conn.getData(0);
            const text = `command failed ${JSON.stringify(command)}`;
            logger.trace(text, err);
            logger.error('command failed');
            reject(new CMError(
              text,
              ErrorCode.PROTOCOL_ERROR,
              err as Object));
          });

        /*
        delay(60 * 1000).then(() => {
          if (success) {
            return;
          }
          const text = `command timeout ${JSON.stringify(command)}`;
          logger.trace(text);
          logger.error('command timeout');
          this._idle = true;
          reject(new CMError(
            text,
            ErrorCode.CONNECT_TIMEOUT));
        });
        */
      });
    });
    return this.nextPromise as Promise<T>;
  }

  stop(): void {
    this.conn.close();
  }
}
