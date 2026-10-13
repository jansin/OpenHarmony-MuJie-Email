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

import { StringUtil } from '../string_util';
import { ByteBuffer } from './byte_buffer';
import { Consts } from './consts';
import { Encoding } from './encoding';
import { Reader } from './reader';
import { StringBuilder } from './string_builder';
import { StringCodec } from './string_codec';
import { Token } from './token';
import { TokenType } from './token_type';

export class TextContainer {
  _byteBuffer: ByteBuffer = new ByteBuffer();
  _stringBuilder: StringBuilder = new StringBuilder()
  _encoding: Encoding
  #endregion



  get Text(): string {
    return this._stringBuilder.toString();
  }


  public constructor(encoding: Encoding) {
    this._encoding = encoding;
  }


  /// <summary>
  ///     Append text content
  /// </summary>
  /// <param name="text"></param>
  public append(text: string): void {
    if (!StringUtil.isNullOrEmpty(text)) {
      this._stringBuilder.appendString(text);
    }
  }


  /// <summary>
  ///     Accept rtf token
  /// </summary>
  /// <param name="token">RTF token</param>
  /// <param name="reader"></param>
  public accept(token: Token, reader: Reader): void {
    if (token == null) return;
    if (this._byteBuffer.length() > 0 && reader.TokenType.valueOf() != TokenType.EncodedChar.valueOf()) {
      let str = StringCodec.getString(this._byteBuffer, this._encoding);
      this._stringBuilder.appendString(str);
      this._byteBuffer.clear();
    }

    switch (token.type) {
      case TokenType.Text:
        this._stringBuilder.appendString(token.key);
        break;

      case TokenType.EncodedChar:
        if (token.hasParam) {
          switch (token.key) {
            case Consts.U:
              this._stringBuilder.append(token.param);
              reader.CurrentLayerInfo.UcValueCount = reader.CurrentLayerInfo.UcValue;
              return;

            case Consts.Apostrophe:
              this._byteBuffer.add(token.param);
              return;
          }
        }
        break;
    }

    if (token.key == Consts.Tab) {
      this._stringBuilder.appendString("\t");
      return;
    }

    if (token.key == Consts.Emdash) {
      this._stringBuilder.appendString('-');
      return;
    }

    if (token.key == "")
      this._stringBuilder.appendString('-');
  }
}