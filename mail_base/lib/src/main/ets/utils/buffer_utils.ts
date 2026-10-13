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

export function joinBuffers(buffers: Uint8Array[]): Uint8Array {
  const size = buffers.reduce((acc, cur) => acc + cur.byteLength, 0);
  const r = new Uint8Array(size);
  buffers.reduce((acc, cur) => {
    r.set(cur, acc);
    return acc + cur.byteLength;
  }, 0);
  return r;
}

/*
 * 删除srcBuffer中，toRemove的数据， * 直接修改srcBuffer的内容，
 * 返回一个新的Uint8Array对象，长度为去掉了toRemove后的数据的长度
 */
export function removeBufferData(
  srcBuffer: Uint8Array,
  toRemove: Uint8Array,
): Uint8Array {
  let start = 0;
  let end = 0;
  let offset = srcBuffer.byteLength;
  start = findBuffer(srcBuffer, toRemove);
  offset = start;
  while (start >= 0 && start < srcBuffer.byteLength) {
    end = findBuffer(srcBuffer, toRemove, start + toRemove.byteLength);
    if (end < 0) {
      end = srcBuffer.byteLength;
    }
    const toMove = srcBuffer.subarray(start + toRemove.byteLength, end);
    srcBuffer.set(toMove, offset);
    offset += toMove.byteLength;
    start = end;
  }
  return srcBuffer.subarray(0, offset);
}

/*
 * 将srcBuffer中，toRemove的内容替换成toReplace，直接修改srcBuffer的内容
 * 要求toRemove的长度必须小于toReplace。
 * 因为这样实现简单，不需要处理重新申请内存
 * 返回一个新的Uint8Array对象，长度为替换后的数据的长度
 */
export function replaceBufferData(
  srcBuffer: Uint8Array,
  toRemove: Uint8Array,
  toReplace: Uint8Array
): Uint8Array {
  if (toReplace.byteLength > toRemove.byteLength) {
    throw new CMError("parameter error", ErrorCode.PARAMETER_ERROR);
  }
  let start = 0;
  let end = 0;
  let offset = srcBuffer.byteLength;
  start = findBuffer(srcBuffer, toRemove);
  if (start >= 0) {
    offset = start;
  }
  while (start >= 0 && start < srcBuffer.byteLength) {
    end = findBuffer(srcBuffer, toRemove, start + toRemove.byteLength);
    if (end < 0) {
      end = srcBuffer.byteLength;
    }
    const toMove = srcBuffer.subarray(start + toRemove.byteLength, end);
    srcBuffer.set(toReplace, offset);
    offset += toReplace.byteLength;
    srcBuffer.set(toMove, offset);
    offset += toMove.byteLength;

    start = end;
  }
  return srcBuffer.subarray(0, offset);
}

export function findBuffer(
  srcBuffer: Uint8Array,
  target: Uint8Array,
  offset: number = 0
): number {
  const firstNumber = target[0];
  let idx = offset - 1;
  let found = false;
  while (true) {
    idx = srcBuffer.indexOf(firstNumber, idx + 1);
    if (idx < 0) {
      break;
    }
    found = true;
    for (let i = 1; i < target.length; i++) {
      if (target[i] != srcBuffer[idx + i]) {
        found = false;
        break;
      }
    }
    if (found) {
      break;
    }
  }
  return idx;
}
