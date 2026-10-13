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

export class Encoding {

  codePage:number;
  codePageName:string;
  private static defaultEncoding:Encoding|null;

  //默认创建utf-8 encoding.
  static get Default() {
    if(!Encoding.defaultEncoding) {
      Encoding.defaultEncoding = new Encoding("utf-8");
    }
    return Encoding.defaultEncoding;
  }

  constructor(codePageName:string) {
    this.codePageName = codePageName;
  }


  /**
   * 返回和codePage名称相关的Encoding.
   * @returns
   */
  static getEncoding(codePageName:string):Encoding {
    return new Encoding(codePageName);
  }
  get IsSingleByte() {
    return false;
  }
}