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

export class StringBuilder {
  _string:string = "";
  tag:number|null = null;
  constructor(charcode:number | null = null) {
    if(charcode) {
      this._string = String.fromCharCode(charcode);
    }
  }
  append(charcode:number) {
    let str = String.fromCharCode(charcode);
    this.appendString(str);
  }
  appendString(str:string) {
    this._string += str;
  }
  toString() {
    return this._string;
  }
}