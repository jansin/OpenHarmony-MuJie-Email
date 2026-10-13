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

import { Encoding } from './encoding';


export class FontTable extends Array {
  _mixedEncodings: boolean | null = null;

  public get MixedEncodings(): boolean {

    if (this._mixedEncodings != null)
      return this._mixedEncodings;

    let currentEncoding: Encoding = null;
    this._mixedEncodings = false;

    for (let font of this) {
      if (font.Encoding != null && currentEncoding == null)
        currentEncoding = font.Encoding;
      else if (currentEncoding != null && font.Encoding != null && currentEncoding.codePage != font.Encoding.codePage) {
        this._mixedEncodings = true;
        break;
      }
    }
    return this._mixedEncodings;
  }

  clear() {
    this.splice(0,this.length);
  }
}