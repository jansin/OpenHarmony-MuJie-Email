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
import { CMError, ErrorCode } from '../api';

import { joinBuffers } from "../utils/buffer_utils";
import { getLogger } from "../utils/log";

const logger = getLogger("msg");

export class BufferView {
  _buffer: ArrayBuffer;
  _view: DataView;
  _offset: number = 0;
  constructor(buffer: ArrayBuffer) {
    this._buffer = buffer;
    this._view = new DataView(buffer, 0);
  }

  getUint8(): number {
    return this._view.getUint8(this._offset++);
  }

  getUint16(): number {
    const v = this._view.getUint16(this._offset, true);
    this._offset += 2;
    return v;
  }
  getUint16Array(n: number): number[] {
    const arr: number[] = [];
    for (let i = 0; i < n; i++) {
      arr.push(this.getUint16());
    }
    return arr;
  }
  getUint32(): number {
    const v = this._view.getUint32(this._offset, true);
    this._offset += 4;
    return v;
  }
  getBytes(n: number): Uint8Array {
    const bytes = new Uint8Array(this._view.buffer, this._offset, n);
    this._offset += n;
    return bytes;
  }

  skip(n: number): void {
    this._offset += n;
  }
  seek(n: number): void {
    this._offset = n;
  }
  offset(): number {
    return this._offset;
  }
}

enum NextSector {
  DIFAT = 0xfffffffc,
  FATSect = 0xfffffffd,
  EndOfChain = 0xfffffffe,
  FreeSector = 0xffffffff,
}

export enum DirectoryObjectType {
  Unknown = 0,
  Storage = 1,
  Stream = 2,
  RootStorage = 5,
}

export type DirectoryEntry = {
  name: string;
  objectType: DirectoryObjectType;
  colorFlag: number;
  leftSiblingId: number;
  rightSiblingId: number;
  childId: number;
  clsId: string;
  stateBits: string;
  creationTime: string;
  modifiedTime: string;
  startSectorLocation: number;
  streamSize: number;
};

export type DirectoryEntryTreeItem = {
  name: string;
  type: number;
  children: DirectoryEntryTreeItem[];
  startSectorLocation: number;
  streamSize: number;
};

export class CFBReader {
  _ds: BufferView;
  _miniFat: number[] = [];
  _fat: number[] = [];
  _miniStreamStartSector: number = 0;
  _sectorShift: number = 0;
  _miniStreamCutoffSize: number = 4096;
  _directoryEntries: DirectoryEntry[] = [];

  constructor(buffer: ArrayBuffer) {
    this._ds = new BufferView(buffer);
    logger.log("MsgReader", buffer);
    this.parse();
  }

  getDirectoryEntries(): DirectoryEntry[] {
    return this._directoryEntries;
  }

  parse(): DirectoryEntry[] {
    logger.log("getHeader", this.isValid());
    const ds = this._ds;
    ds.seek(24);
    const minorVersion = ds.getUint16();
    const majorVersion = ds.getUint16();
    const byteOrder = ds.getUint16(); // must be 0xfffe
    // 如果majorVersion是3，必须是0x09，如果majorVersion是4，必须是0x0c
    // 0x09 512字节扇区
    // 0x0c 4096字节扇区
    const sectorShift = ds.getUint16() == 0x09 ? 512 : 4096;
    this._sectorShift = sectorShift;
    const miniSectorShift = ds.getUint16(); // 必须是0x06
    logger.log(`
    majorVersion: ${majorVersion}
    minorVersion: ${minorVersion}
    byteOrder: ${byteOrder}
    sectorShift: ${sectorShift}
    miniSectorShift: ${miniSectorShift}`);
    const reserved = ds.getBytes(6);
    const directorySectorCount = ds.getUint32();
    const fatSectorCount = ds.getUint32();
    logger.log("offset", ds.offset().toString(16));
    const firstDirectorySectorLocation = ds.getUint32();
    const transactionSignatureNumber = ds.getUint32();
    const miniStreamCutoffSize = ds.getUint32(); // must be 4096
    const firstMiniFATSectorLocation = ds.getUint32();
    const miniFATSectorCount = ds.getUint32();
    const firstDIFATSectorLocation = ds.getUint32();
    const difatSectorCount = ds.getUint32();
    const difat = [];
    logger.log(`
    reserved: ${reserved}
    directorySectorCount: ${directorySectorCount}
    fatSectorCount: ${fatSectorCount}
    firstDirectorySectorLocation: ${firstDirectorySectorLocation}
    transactionSignatureNumber: ${transactionSignatureNumber}
    miniStreamCutoffSize: ${miniStreamCutoffSize}
    firstMiniFATSectorLocation: ${firstMiniFATSectorLocation}
    miniFATSectorCount: ${miniFATSectorCount}
    firstDIFATSectorLocation: ${firstDIFATSectorLocation}
    difatSectorCount: ${difatSectorCount}
    ${ds.offset().toString(16)}
    `);

    // 头部还可以最多存放109个DIFAT项
    for (let i = 0; i < 109; i++) {
      const v = ds.getUint32();
      if (v != 0xffffffff) {
        difat.push(v);
      }
    }
    // logger.log("difat", difat);

    // 构造FAT表
    const entryNumberPerSector = sectorShift / 4;
    let fatSect: number[] = [];
    for (const df of difat) {
      ds.seek((df + 1) * sectorShift);
      for (let i = 0; i < entryNumberPerSector; i++) {
        fatSect.push(ds.getUint32());
      }
    }
    // logger.log("difat", fatSect.map(v => v.toString(10)).join(" "));
    this._fat = fatSect;
    logger.debug("fat", this._fat);

    // 构造miniFAT表
    let miniFatIndex: number = firstMiniFATSectorLocation;
    let miniFatSect: number[] = [];
    for (let n = 0; n < miniFATSectorCount; n++) {
      ds.seek((miniFatIndex + 1) * sectorShift);
      for (let i = 0; i < entryNumberPerSector; i++) {
        miniFatSect.push(ds.getUint32());
      }
      /*
      logger.log(
        "miniFatSect",
        miniFatIndex,
        miniFatSect.map(v => v.toString(10)).join(" ")
      );
      */
      miniFatIndex = fatSect[miniFatIndex];
    }
    this._miniFat = miniFatSect;

    // 读取directory
    let sectorIndex = firstDirectorySectorLocation;
    let nodes: DirectoryEntry[] = [];
    const directoryEntrySize = 128;
    while (true) {
      // logger.log("sectorIndex", sectorIndex);
      let directoryOffset = (sectorIndex + 1) * sectorShift;
      let sz = 0;
      let arr: DirectoryEntry[] = [];
      while (sz < sectorShift) {
        const node = this.readDirectory(directoryOffset + sz);
        if (node) {
          arr.push(node);
        }
        sz += directoryEntrySize;
      }
      // console.log(arr);
      nodes = nodes.concat(arr);
      const nextSector = fatSect[sectorIndex];
      if (nextSector == NextSector.EndOfChain) {
        break;
      }
      sectorIndex = nextSector;
    }
    this._miniStreamStartSector = nodes[0].startSectorLocation;
    this._directoryEntries = nodes;
    // logger.log("nodes", nodes, nodes.length);
    // const root = this.buildDirectoryTree(nodes);
    // logger.log("root", JSON.stringify(root, null, 2));
    return nodes;
  }

  /*
   * 根据startSectorLocation和streamSize从miniStream流中读取数据
   */
  readDirectoryData(entry: DirectoryEntry): Uint8Array {
    // logger.debug("entry", entry);
    // logger.debug("minifat", JSON.stringify(this._miniFat));
    // logger.debug("fat", JSON.stringify(this._fat));
    return this.readStream(entry);
  }

  /*
   * 读取一个目录项的数据，entry.objectType必须是DirectoryObjectType.Storage
   * 在cfb格式里面，storage是类似于文件夹的概念
   */
  readStorage(entry: DirectoryEntry): DirectoryEntry[] {
    if (entry.objectType != DirectoryObjectType.Storage) {
      throw new CMError("not a storage", ErrorCode.PARAMETER_ERROR);
    }
    if (entry.childId == 0xffffffff) {
      return [];
    }
    const cidList = [entry.childId];
    const children: DirectoryEntry[] = [];
    while (cidList.length > 0) {
      const cid = cidList.shift()!;
      const entry = this._directoryEntries[cid];
      children.push(entry);
      if (entry.leftSiblingId != 0xffffffff) {
        cidList.push(entry.leftSiblingId);
      }
      if (entry.rightSiblingId != 0xffffffff) {
        cidList.push(entry.rightSiblingId);
      }
    }
    return children;
  }

  /*
   * 读取一个目录项的数据，entry.objectType必须是DirectoryObjectType.Stream
   * 在cfb格式里面，stream是类似于文件的概念
   */
  readStream(entry: DirectoryEntry): Uint8Array {
    if (entry.objectType != DirectoryObjectType.Stream) {
      throw new CMError("not a stream", ErrorCode.PARAMETER_ERROR);
    }
    const data: Uint8Array[] = [];
    if (entry.streamSize >= this._miniStreamCutoffSize) {
      let sector = entry.startSectorLocation;
      while (sector != NextSector.EndOfChain) {
        data.push(this.getSector(sector));
        sector = this._fat[sector];
      }
    } else {
      let block = entry.startSectorLocation;
      while (block != NextSector.EndOfChain) {
        // logger.debug("block", block);
        data.push(this.getMinStreamSector(block));
        block = this._miniFat[block];
      }
    }
    const buff = joinBuffers(data).subarray(0, entry.streamSize);

    return buff;
  }

  getMinStreamSector(sector: number): Uint8Array {
    const miniStreamOffset = sector * 64;
    let n = Math.floor(miniStreamOffset / this._sectorShift);
    let o = miniStreamOffset % this._sectorShift;
    let startSector = this._miniStreamStartSector;
    while (n > 0) {
      startSector = this._fat[startSector];
      n -= 1;
    }
    const fileOffset = (startSector + 1) * this._sectorShift + o;
    // logger.debug("getSector", sector, startSector, fileOffset.toString(16));
    this._ds.seek(fileOffset);
    return this._ds.getBytes(64);
  }

  getSector(sector: number): Uint8Array {
    const offset = (sector + 1) * this._sectorShift;
    this._ds.seek(offset);
    return this._ds.getBytes(this._sectorShift);
  }

  // https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/60fe8611-66c3-496b-b70d-a504c94c9ace
  readDirectory(offset: number): DirectoryEntry | undefined {
    const ds = this._ds;
    ds.seek(offset + 0x40);
    const directoryEntryNameLen = this._ds.getUint16();
    const objectType = this._ds.getUint8();
    if (objectType == DirectoryObjectType.Unknown) {
      return;
    }
    const colorFlag = this._ds.getUint8();
    const leftSiblingId = this._ds.getUint32();
    const rightSiblingId = this._ds.getUint32();
    const childId = this._ds.getUint32();
    const clsId = this._ds.getBytes(16);
    const stateBits = this._ds.getBytes(4);
    const creationTime = this._ds.getBytes(8);
    const modifiedTime = this._ds.getBytes(8);
    const startSectorLocation = this._ds.getUint32();
    const streamSize = this._ds.getUint32(); // 实际是8字节，但是一般文件没那么大。小端序存储，所以只需要拿低地址的32位即可
    ds.seek(offset);
    const directoryEntryName = this._ds
      .getUint16Array(directoryEntryNameLen / 2 - 1)
      .map(v => String.fromCharCode(v))
      .join("");
    return {
      name: directoryEntryName,
      objectType,
      colorFlag,
      leftSiblingId,
      rightSiblingId,
      childId,
      clsId: Array.from(clsId)
        .map(v => String.fromCharCode(v))
        .join(""),
      stateBits: Array.from(stateBits)
        .map(v => v.toString(16))
        .join(""),
      creationTime: Array.from(creationTime)
        .map(v => v.toString(16))
        .join(""),
      modifiedTime: Array.from(modifiedTime)
        .map(v => v.toString(16))
        .join(""),
      startSectorLocation,
      streamSize,
    };
  }

  isValid(): boolean {
    const fileHeader = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
    const bytes = this._ds.getBytes(8);
    return fileHeader
      .map((v, i) => bytes[i] == v)
      .reduce((a, b) => a && b, true);
  }
}
