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

import buffer from '@ohos.buffer';
import util from '@ohos.util';



export class StringUtil {
  /**
   * 字符是否是一个字母
   * A-Z
   * a-z
   * @param c
   * @returns
   */
  static isLetter(charcode:number) {
    return (charcode >= 'A'.charCodeAt(0) && charcode <= 'Z'.charCodeAt(0)) || (charcode >= 'a'.charCodeAt(0) && charcode <= 'z'.charCodeAt(0))

  }

  /**
   * 字符是否是一个数字
   * @param c
   */
  static isDigit(charcode:number) {
    return charcode >= '0'.charCodeAt(0) && charcode <= '9'.charCodeAt(0)
  }

  static isNullOrEmpty(str:string|null) {
     return !(str && str.length > 0);
  }

  /**
   * 移除首端和末尾的c.
   * @param str
   * @param c
   */
  static trim(str:string,c:string):string {
    if(str[0] == c) {
      str = str.slice(1);
    }
    let lastIndex = str.length - 1;
    if(str[lastIndex] == c) {
      str = str.substring(0,lastIndex -1);
    }
    return str;
  }
  static trimEnd(str:string,c:string):string {
    let lastIndex = str.length - 1;
    if(str[lastIndex] == c) {
      str = str.substring(0,lastIndex -1);
    }
    return str;
  }
}
