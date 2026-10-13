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

import { ByteBuffer } from './byte_buffer';
import { Encoding } from './encoding';
import util from '@ohos.util';

export class StringCodec {

  /**
   * 将一个二进制序列,解码为特定编码的字符串.
   * @param u8a
   * @param encoding
   */
  static getString(bytebuffer:ByteBuffer,encoding:Encoding):string {
    let decoder = util.TextDecoder.create(encoding.codePageName);
    let u8a = new Uint8Array(bytebuffer.buffer);
    let str = decoder.decodeWithStream(u8a);
    return str;
  }
}