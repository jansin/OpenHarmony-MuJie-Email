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
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { BufferHint, IBuffer, IBufferCreator } from '@coremail/mail_base';
import { ExtVsMimeDict } from './MimeExtMap';

export function createBufferCreator(basePath: string, account: string): IBufferCreator {
  const base64 = new util.Base64Helper();
  const b = new Uint8Array(account.split('').map(v => v.charCodeAt(0)));
  const path = `${basePath}/${base64.encodeToStringSync(b)}`
  if (!fs.accessSync(path)) {
    fs.mkdirSync(path);
  }
  let index = 0;
  const bufferCreator: IBufferCreator = {
    createBuffer() {
      index += 1;
      const filePath = `${path}/${index}`;
      return new FileBuffer(filePath);
    }
  }
  return bufferCreator;
}

export async function createFile(filePath: string, data: string) {
  const file = await fs.open(filePath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  await fs.write(file.fd, data)
}

export class FileBufferCreator implements IBufferCreator {
  _path: string;
  _index: number = 1;
  _account: string;
  _fileTitle: string;
  constructor(path: string,fileTitle:string = null) {
    this._path = path;
    this._fileTitle = fileTitle;
  }

  createBuffer(hint?: BufferHint): IBuffer {
    let title = this._fileTitle? this._fileTitle : this._index;
    let truePath = this._path + "/" + title + ".buf";
    if (hint["type"] == "image") {
      const subType = hint["subType"] as string
      const mime = hint["type"] + "/" + subType
      const ext = Object.entries(ExtVsMimeDict).find(item => item[1] == mime)
      if (ext) {
        truePath = this._path + "/" + title + "." + ext[0];
      }
    }
    const buffer = new FileBuffer(truePath);
    this._index += 1; // TODO: 做个递增验证效果先
    return buffer;
  }
}

export class FileBuffer implements IBuffer {

  filePath: string;
  file:fs.File = null;
  _debugCache: (string | Uint8Array)[] = [];

  constructor(filePath: string) {
    this.filePath = filePath;
    fs.access(filePath)
      .then(existed => {
        if (!existed) {
          this.detectAndCreateDir(filePath);
        }
      })
  }

  detectAndCreateDir(filePath: string): void {
    let pathComponents = filePath.split('/');
    pathComponents.pop();
    let dir = pathComponents[0];
    for(let i = 0; i < pathComponents.length; i ++) {
      let component = pathComponents[i];
      dir += `/${component}`;
      if(fs.accessSync(dir)){
        continue
      }
      else {
        fs.mkdirSync(dir);
      }
    }
  }

  async feed(data: string | Uint8Array): Promise<void> {
    this._debugCache.push(data);
    if (!this.file) {
      this.file = await fs.open(this.filePath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    }
    try {
      if (typeof data == "string") {
        const content = data as string
        await fs.write(this.file.fd, content)
      } else {
        const u8a = data as Uint8Array;
        const u = new Uint8Array(u8a.byteLength)
        u.set(u8a);
        await fs.write(this.file.fd, u.buffer);
      }
    } catch (error) {
      // console.log(error)
    }
  }

  async end(data?: string | Uint8Array): Promise<void> {
    if (data) {
      await this.feed(data);
    }
    await fs.close(this.file);
    this.file = null;
  }

  [Symbol.asyncIterator](): AsyncIterableIterator<string> {
    return this.read();
  }

  read(): AsyncIterableIterator<string> {
    if (!this.file) {
      this.file = fs.openSync(this.filePath, fs.OpenMode.READ_ONLY)
    }

    let count = 0;
    let offset = 0;
    let buffer = new ArrayBuffer(1024);
    return {
      next: async (): Promise<IteratorResult<string>> => {
        try {
          count = await fs.read(this.file.fd, buffer, {
            offset: offset,
            length: 1024
          })

          if (count > 0) {
            offset += count;
            const u8a = new Uint8Array(buffer, 0, count);
            const decoder = util.TextDecoder.create('utf-8');
            const str = decoder.decodeWithStream(u8a);
            return { value: str, done: false };
          }
          else {
            await fs.close(this.file);
            return { value: undefined, done: true };
          }
        } catch(e) {
          return {done: true, value: undefined}
        }
      },
      [Symbol.asyncIterator](): AsyncIterableIterator<string> {
        return this;
      },
    };
  }

  async readAll(): Promise<string> {
    const iterator = this.read()
    let result: string = ""
    for await (const chunk of iterator) {
      result = result + chunk
    }
    return result
  }

  async getSize(): Promise<number> {
    let stat = await fs.stat(this.filePath) as fs.Stat;
    return stat.size
  }

  readRaw(): AsyncIterableIterator<Uint8Array> {
    if (!this.file) {
      this.file = fs.openSync(this.filePath, fs.OpenMode.READ_ONLY)
    }

    let count = 0;
    let offset = 0;
    let buffer = new ArrayBuffer(1024);
    return {
      next: async (): Promise<IteratorResult<Uint8Array>> => {
        count = await fs.read(this.file.fd, buffer, { offset: offset, length: 1024 })
        if (count > 0) {
          offset += count;
          const u8a = new Uint8Array(buffer, 0, count);
          return { value: u8a, done: false };
        } else {
          fs.closeSync(this.file);
          return { value: undefined, done: true };
        }
      },
      [Symbol.asyncIterator](): AsyncIterableIterator<Uint8Array> {
        return this;
      },
    };
  }

  async readAllRaw(): Promise<Uint8Array> {
    const iterator = this.readRaw()
    let result: Uint8Array = new Uint8Array()
    for await (const chunk of iterator) {
      let mergeArr = new Uint8Array(result.length + chunk.length);
      mergeArr.set(result);
      mergeArr.set(chunk, result.length);
      result = mergeArr;
    }
    return result
  }

  getSizeRaw(): Promise<number> {
    return this.getSize() // TODO：暂时
  }

}