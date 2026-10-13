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

import type { BufferHint, IBuffer, IBufferCreator } from "../api";
import { joinBuffers } from "./buffer_utils";
import { encodeUtf8, decodeCharset } from "./encodings";
import { getLogger } from "./log";
import fs from "@ohos.file.fs"
import { delay } from './common';

const logger = getLogger("file_stream");

const contentTypeMap = new Map<string, string>([
  ["txt", "text/plain"],
  ["html", "text/html"],
  ["jpg", "image/jpeg"],
  ["jpeg", "image/jpeg"],
  ["png", "image/png"],
  ["gif", "image/gif"],
  ["bmp", "image/bmp"],
  ["doc", "application/msword"],
  [
    "docx",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ],
  ["xls", "application/vnd.ms-excel"],
  ["xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"],
  ["ppt", "application/vnd.ms-powerpoint"],
  [
    "pptx",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  ],
  ["pdf", "application/pdf"],
  ["zip", "application/zip"],
  ["rar", "application/x-rar-compressed"],
  ["tar", "application/x-tar"],
  ["gz", "application/gzip"],
  ["7z", "application/x-7z-compressed"],
  ["exe", "application/x-msdownload"],
  ["msi", "application/x-msdownload"],
  ["cab", "application/vnd.ms-cab-compressed"],
  ["mp3", "audio/mpeg"],
  ["ogg", "audio/ogg"],
  ["wav", "audio/wav"],
  ["wma", "audio/x-ms-wma"],
  ["wmv", "video/x-ms-wmv"],
  ["swf", "application/x-shockwave-flash"],
  ["avi", "video/x-msvideo"],
  ["mp4", "video/mp4"],
  ["mpg", "video/mpeg"],
  ["rm", "application/vnd.rn-realmedia"],
  ["rmvb", "application/vnd.rn-realmedia-vbr"],
  ["mov", "video/quicktime"],
  ["mkv", "video/x-matroska"],
  ["flv", "video/x-flv"],
  ["f4v", "video/mp4"],
  ["m4v", "video/mp4"],
  ["m4a", "audio/mp4"],
  ["m4b", "audio/mp4"],
  ["m4p", "audio/mp4"],
  ["m4r", "audio/mp4"],
  ["3gp", "video/3gpp"],
  ["3g2", "video/3gpp2"],
  ["ts", "video/mp2t"],
  ["m2ts", "video/mp2t"],
  ["ipa", "application/vnd.iphone"],
  ["deb", "application/vnd.debian.binary-package"],
  ["iso", "application/x-iso9660-image"],
  ["img", "application/x-iso9660-image"],
  ["dmg", "application/x-apple-diskimage"],
  ["vhd", "application/x-virtualbox-vhd"],
  ["vmdk", "application/x-virtualbox-vmdk"],
  ["ova", "application/x-virtualbox-ova"],
  ["ovf", "application/x-virtualbox-ovf"],
  ["torrent", "application/x-bittorrent"],
]);

export function guessContentType(fileName: string): string {
  const ext = fileName.split(".").pop()?.toLowerCase() || "";
  return contentTypeMap.get(ext) || "application/octet-stream";
}

export function getFileName(filePath: string): string {
  return filePath.split(/\/|\\/).pop() || "";
}

export function openFile(path: string, mode: string): IBuffer {
  const stream = createBuffer({});
  (async function read(): Promise<void> {
    const buffer = new ArrayBuffer(1024 * 20);
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    let offset = 0;
    while (true) {
      const bytesRead = await fs.read(file.fd,
        buffer,
        {
          offset,
          length: buffer.byteLength
        }
      );
      logger.debug("read", path, bytesRead);
      if (bytesRead > 0) {
        const b = new Uint8Array(bytesRead)
        b.set(new Uint8Array(buffer, 0, bytesRead))
        stream.feed(b);
        offset += bytesRead;
      } else {
        stream.end();
        break;
      }
    }
  })();
  return stream;
}

export class MemBuffer implements IBuffer {
  data: (string | Uint8Array)[] = [];
  size: number = 0;
  _end: boolean = false;
  constructor() {}
  async feed(d: string | Uint8Array): Promise<void> {
    this.size += d.length;
    this.data.push(d);
  }
  async end(d?: string | Uint8Array): Promise<void> {
    if (d) {
      this.feed(d);
    }
    this._end = true;
  }
  [Symbol.asyncIterator](): AsyncIterableIterator<string> {
    return this.read();
  }
  _readIndex(i: number, type: "raw" | "string"): string | Uint8Array {
    let d = this.data[i];
    if (type == "string" && typeof d !== "string") {
      if(d.length == 0) return "";
      d = decodeCharset(d, "utf-8");
    }
    if (type == "raw" && typeof d === "string") {
      if(d.length == 0) return new Uint8Array([]);
      d = encodeUtf8(d);
    }
    return d;
  }

  read(): AsyncIterableIterator<string> {
    let i = 0;
    const it: AsyncIterableIterator<string> = {
      next: async (): Promise<IteratorResult<string>> => {
        if (i < this.data.length) {
          const value = this._readIndex(i, "string") as string;
          i += 1;
          return { value, done: false };
        } else {
          let value: string | undefined;
          let done = true;
          while (!this._end && i >= this.data.length) {
            await delay(500);
          }
          if (i < this.data.length) {
            value = this._readIndex(i, "string") as string;
            i += 1;
            done = false;
          }
          return { value, done };
        }
      },
      [Symbol.asyncIterator](): AsyncIterableIterator<string> {
        return this as AsyncIterableIterator<string>;
      },
    };
    return it;
  }
  async readAll(): Promise<string> {
    while (!this._end) {
      await delay(500);
    }
    return this.data
      .map(d => {
        if (typeof d === "string") {
          return d;
        } else {
          return decodeCharset(d, "utf-8");
        }
      })
      .join("");
  }
  getSize(): Promise<number> {
    return Promise.resolve(this.size);
  }
  readRaw(): AsyncIterableIterator<Uint8Array> {
    let i = 0;
    const it: AsyncIterableIterator<Uint8Array> = {
      next: async (): Promise<IteratorResult<Uint8Array>> => {
        if (i < this.data.length) {
          const value = this._readIndex(i, "raw") as Uint8Array;
          i += 1;
          return { value, done: false };
        } else {
          let value: Uint8Array | undefined;
          let done = true;
          while (!this._end && i >= this.data.length) {
            await delay(500);
          }
          if (i < this.data.length) {
            value = this._readIndex(i, "raw") as Uint8Array;
            i += 1;
            done = false;
          }
          return { value, done };
        }
      },
      [Symbol.asyncIterator](): AsyncIterableIterator<Uint8Array> {
        return this as AsyncIterableIterator<Uint8Array>;
      },
    };
    return it;
  }
  async readAllRaw(): Promise<Uint8Array> {
    while (!this._end) {
      await delay(500);
    }
    const data = this.data.map(d => {
      if (typeof d !== "string") {
        return d;
      } else {
        return encodeUtf8(d);
      }
    });
    return joinBuffers(data);
  }
  getSizeRaw(): Promise<number> {
    return Promise.resolve(this.size);
  }
}

export const memBufferCreator: IBufferCreator = {
  createBuffer: (hint: BufferHint) => {
    return new MemBuffer();
  },
};

let bufferCreator: IBufferCreator;

export function setBufferCreator(creator: IBufferCreator): void {
  bufferCreator = creator;
}

export function createBuffer(hint: BufferHint): IBuffer {
  // return memBufferCreator.createBuffer(hint)
  if (!bufferCreator) {
    bufferCreator = memBufferCreator;
  }
  return bufferCreator.createBuffer(hint);
}
