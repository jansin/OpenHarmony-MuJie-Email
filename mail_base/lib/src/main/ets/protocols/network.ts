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

import socket from '@ohos.net.socket';
import wifiManager from '@ohos.wifiManager';

import { joinBuffers } from '../utils/buffer_utils';
import { getLogger } from '../utils/log';
import type { Logger } from '../utils/log';
import { delay, EventHandler } from '../utils/common';
import { decodeCharset } from '../utils/encodings';
import connection from '@ohos.net.connection';
import { CMError, ErrorCode } from '../api';

export enum NetworkState {
  CONNECTING = 0,
  CONNECTED = 1,
  DISCONNECTED = 2,
  ERROR = 3,
}

type ConnectionOption = {
  timeout: number;
};

function int2ip(n: number): string {
  return `${(n & 0xff000000) >>> 24}.${(n & 0x00ff0000) >>> 16}.${
  (n & 0x0000ff00) >>> 8
  }.${n & 0xff}`;
}

function isIP(str: string): boolean {
  if (str.length < 7 || str.length > 15) {
    return false;
  }

  var arr: string[] = str.split(".");
  if (arr.length != 4) {
    return false;
  }

  for (let i = 0; i < 4; i++) {
    var s = arr[i];
    for (let j = 0; j < s.length; j++) {
      if (s.charAt(j) < "0" || s.charAt(j) > "9") {
        return false;
      }
    }
  }

  for (let i = 0; i < 4; i++) {
    var temp = parseInt(arr[i]);
    if (temp < 0 || temp > 255) {
      return false;
    }
  }
  return true;
}

function getLocalIp(): string {
  const ipInfo = wifiManager.getIpInfo();
  const localHost = int2ip(ipInfo.ipAddress);
  return localHost;
}

export class Connection extends EventHandler {
  host: string;
  port: number;
  isSSL: boolean;
  sock?: socket.TCPSocket | socket.TLSSocket;
  ca: string[] = []

  option: ConnectionOption = {
    timeout: 10000,
  };
  buffer = new Uint8Array(0);
  buffs: Uint8Array[] = [];
  state = NetworkState.DISCONNECTED;
  connectedPromise: Promise<boolean> = Promise.resolve(false);
  logger: Logger;

  constructor(
    host: string,
    port: number,
    isSSL: boolean,
    ca?: string[],
    option?: ConnectionOption
  ) {
    super();
    this.logger = getLogger("protocol");
    this.logger.addPrefix(host + ":" + port.toString());
    this.host = host;
    this.port = port;
    this.isSSL = isSSL;
    if (option) {
      this.option = option;
    }
    if (ca) {
      this.ca = ca;
    }
  }

  isConnected(): boolean {
    return this.state == NetworkState.CONNECTED;
  }

  initHandler(sock: socket.TCPSocket | socket.TLSSocket): void {
    const logger = this.logger;
    logger.log("initHandler");
    sock.on("message", ({ message }) => {
      this.processData(message);
    });
    sock.on("close", () => {
      logger.log("onclose");
      this.state = NetworkState.DISCONNECTED;
      this.emit("end");
    });
    this.connectedPromise = new Promise<boolean>((resolve, reject) => {
      let success = false;
      sock.on("connect", () => {
        logger.log("connected");
        this.state = NetworkState.CONNECTED;
        success = true;
        resolve(true);
      });
      sock.on("error", (err: Error) => {
        logger.error("onerror", err);
        this.state = NetworkState.DISCONNECTED;
        reject(err);
        this.emit("end");
      });
      delay(this.option.timeout).then(() => {
        if (success) {
          return;
        }
        logger.error("connect timeout", this.state);
        reject(
          new CMError("connect timeout", ErrorCode.CONNECT_TIMEOUT, {
            host: this.host,
            port: this.port,
            isSSL: this.isSSL,
          })
        );
      });
    });
  }

  async connect(): Promise<boolean> {
    const logger = this.logger;
    logger.log("connect", this.host, this.port, this.isSSL);
    try {
      const handler = await connection.getDefaultNet();
      let netAddress = await handler.getAddressesByName(this.host);
      let ip: string = null;
      for (let i = 0; i < netAddress.length; i++) {
        if (isIP(netAddress[i].address)) {
          ip = netAddress[i].address;
          break;
        }
      }
      if (!!!ip) {
        //TODO:
        //ip处理错误.
        throw new CMError("not available ip", ErrorCode.PARAMETER_ERROR);
      }
      if (this.isSSL) {
        const sock = socket.constructTLSSocketInstance();
        await sock.bind({
          address: getLocalIp(),
          family: 1,
          port: 0 })
        this.initHandler(sock)
        await sock.connect({
          address: {
            address: ip,
            port: this.port
          },
          secureOptions: {
            ca: this.ca,
            cert: '',
            key: '',
            protocols: [socket.Protocol.TLSv12],
            useRemoteCipherPrefer: true,
            signatureAlgorithms: '',
            cipherSuite: ''
          },
        })
        this.sock = sock;
      } else {
        const sock = socket.constructTCPSocketInstance();
        await sock.bind({
          address: getLocalIp(),
          family: 1,
        });
        this.initHandler(sock);
        await sock.connect({
          address: {
            address: ip,
            port: this.port,
          },
          timeout: 6000,
        });
        this.sock = sock;
      }
    } catch (e: unknown) {
      this.logger.log(JSON.stringify(e));
      this.connectedPromise = Promise.reject(new CMError("connect failed", ErrorCode.CONNECT_FAILED, e));
      return this.connectedPromise;
    }
    return this.waitForConnected();
  }

  startTLS(): void {
    if (this.isSSL) {
      return;
    }
  }

  waitForConnected(): Promise<boolean> {
    return this.connectedPromise;
  }

  processData(data: ArrayBuffer): void {
    // log('processData', data, this.waitingResponses.length);
    const logger = this.logger;
    logger.debug(
      "processData",
      data.byteLength,
      this.buffer.byteLength,
      // decodeCharset(new Uint8Array(data)).replace(/\r\n/g, "\\r\\n"),
    );
    const buffer = new Uint8Array(this.buffer.byteLength + data.byteLength);
    buffer.set(this.buffer);
    buffer.set(new Uint8Array(data), this.buffer.byteLength);
    this.buffer = buffer;
    this.emit("data");
  }

  send(data: string): Promise<void> {
    const logger = this.logger;
    logger.debug("send", data.replace(/\r\n/g, "\\r\\n"));
    if (!this.sock) {
      return;
    }
    try {
      if (this.isSSL) {
        return (this.sock as socket.TLSSocket).send(data);
      } else {
        return (this.sock as socket.TCPSocket).send({ data });
      }
    } catch (e: unknown) {
      logger.error('send data', JSON.stringify(e));
      throw new CMError("send data failed", ErrorCode.SEND_DATA_FAILED, e as Object);
    }
  }

  _getData(bytes: number, discard: number = 0): Uint8Array {
    const buffer = this.buffer.subarray(0, bytes);
    this.buffer = this.buffer.subarray(bytes + discard);
    return buffer;
  }

  getMaxData(max: number): Promise<Uint8Array> {
    if (this.buffer.byteLength < max) {
      max = this.buffer.byteLength;
    }
    return Promise.resolve(this._getData(max));
  }

  getData(bytesOrEnd: number | Uint8Array): Promise<Uint8Array> {
    // this.logger.debug(`[__pop3] [enter get data]`);
    if(!this.isConnected()) {
      this.logger.debug(`[__pop3] [disconnected when get data]`);
      return Promise.reject();
    }

    if (typeof bytesOrEnd == "number") {
      if (bytesOrEnd <= 0) {
        bytesOrEnd = this.buffer.byteLength;
      }
      if (this.buffer.byteLength >= bytesOrEnd) {
        return Promise.resolve(this._getData(bytesOrEnd));
      }
      return new Promise<Uint8Array>((resolve, reject) => {
        let endHandler = (): void => {
          this.logger.error(`[__pop3] [onend]`, bytesOrEnd);
          reject();
        }
        this.once('end', endHandler);
        this.once("data", (): void => {
          this.off('end',endHandler);
          resolve(this.getData(bytesOrEnd))
        });
      });
    } else {
      for (let i = 0; i < this.buffer.byteLength; i++) {
        let found = true;
        for (let j = 0; j < bytesOrEnd.byteLength; j++) {
          if (this.buffer[i + j] != bytesOrEnd[j]) {
            found = false;
            break;
          }
        }
        if (found) {;
          return Promise.resolve(this._getData(i, bytesOrEnd.byteLength));
        }
      }
      const buffer = this._getData(this.buffer.byteLength);
      return new Promise<Uint8Array>((resolve, reject) => {
        let endHandler = (): void => {
          this.logger.error(`[__pop3] [onend]`, bytesOrEnd);
          reject();
        }
        this.once('end', endHandler);
        this.once("data", () => {
          this.getData(bytesOrEnd).then(data => {
            resolve(joinBuffers([buffer, data]));
          });
        });
      });
    }
  }

  close(): void {
    this.state = NetworkState.DISCONNECTED;
    this.sock?.close();
  }
}
