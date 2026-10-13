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

export class ByteBuffer {
  buffer:Array<number> = new Array();

  /**
   * 通过创建一个空的来清空.
   */
  clear() {
    this.buffer.splice(0,this.buffer.length);
  }

  length() {
    return this.buffer.length;
  }
  byteAt(index:number):number {
    return this.buffer[index];
  }
  /**
   * 增加一个byte,数据应该在0-255之间.
   * @param byte
   */
  add(byte:number) {
    this.buffer.push(byte);
  }
}