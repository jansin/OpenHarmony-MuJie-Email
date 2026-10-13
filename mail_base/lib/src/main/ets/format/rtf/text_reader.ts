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

export class TextReader {
  text:string = "";
  length:number = 0;
  position:number = -1;
  constructor(rtf:string) {
    this.text = rtf;
    this.length = this.text.length;
  }

  /**
   *
   *
   * Returns the next available character but does not consume it.
   * An integer representing the next character to be read
   * or -1 if no more characters are available or the stream does not support seeking.
   * @returns
   */
  peek():number {
    let nextPosition = this.position + 1;
    return this.getCharCodeAtIndex(nextPosition);
  }

  getCharCodeAtIndex(index:number) {
    if(index < this.length) {
      return this.text.charCodeAt(index);
    }
    else {
      return -1;
    }
  }

  /**
   * Reads the next character from the input string and advances the character position by one character.
   * 需要对数组长度进行检查,charCodeAt()超出长度,返回一个NaN.
   * @returns
   */
  read():number {
    let nextPosition = ++ this.position;
    return this.getCharCodeAtIndex(nextPosition);
  }
}