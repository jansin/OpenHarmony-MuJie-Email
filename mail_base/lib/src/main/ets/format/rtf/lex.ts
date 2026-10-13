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
import { Consts } from './consts';
import { StringBuilder } from './string_builder';
import { TextReader } from './text_reader';
import { Token } from './token';
import { TokenType } from './token_type';

const Eof: number = -1;

export class Lex {
  _reader: TextReader;

  constructor(reader: TextReader) {
    this._reader = reader;
  }

  /**
   * 查看下一个token的TokenType.
   */
  public peekTokenType(): TokenType {
    var c = this._reader.peek();

    while (c == '\r'.charCodeAt(0) || c == '\n'.charCodeAt(0) || c == '\t'.charCodeAt(0) || c == '\0'.charCodeAt(0)) {
      this._reader.read();
      c = this._reader.peek();
    }

    if (c == Eof)
      return TokenType.Eof;

    switch (c) {
      case '{'.charCodeAt(0):
        return TokenType.GroupStart;

      case '}'.charCodeAt(0):
        return TokenType.GroupEnd;

      case '\\'.charCodeAt(0):
        return TokenType.Keyword;

      default:
        return TokenType.Text;
    }
  }


  public nextToken(): Token {
    var token = new Token();

    //获取下一个有效字符.
    var c = this._reader.read();
    while (c == '\r'.charCodeAt(0) || c == '\n'.charCodeAt(0) || c == '\t'.charCodeAt(0) || c == '\0'.charCodeAt(0))
      c = this._reader.read();

    if (c != Eof) {
      switch (c) {
        case '{'.charCodeAt(0):
          token.type = TokenType.GroupStart;
          break;

        case '}'.charCodeAt(0):
          token.type = TokenType.GroupEnd;
          break;

        case '\\'.charCodeAt(0):
          this.parseKeyword(token);
          break;

        default: {
          token.type = TokenType.Text;
          this.parseText(c, token);
          break;
        }
      }
    }
    else {
      token.type = TokenType.Eof;
    }
    return token;
  }

  private parseKeyword(token: Token) {
    var c = this._reader.peek();
    if (!StringUtil.isLetter(c)) {
      this._reader.read();
      if (c == '*'.charCodeAt(0)) {
        // Expand keyword
        token.type = TokenType.Extension;
        this._reader.read();
      }
      else {
        if (c == '\\'.charCodeAt(0) || c == '{'.charCodeAt(0) || c == '}'.charCodeAt(0)) {
          // Special character
          token.type = TokenType.Text;
          // token.Key = ((char)c).ToString(CultureInfo.InvariantCulture);
          token.key = String.fromCharCode(c);
        }
        else {
          token.type = TokenType.EncodedChar;
          // token.Key = ((char)c).ToString(CultureInfo.InvariantCulture);
          token.key = String.fromCharCode(c);
          if (token.key == Consts.Apostrophe) {
            // Read 2 hex characters  /'eb  最终param应该为0xeb
            var text = new StringBuilder();
            text.append(this._reader.read());
            text.append(this._reader.read());
            token.hasParam = true;
            // token.param = Convert.ToInt32(text.ToString().ToLower(), 16);
            token.param = Number.parseInt(text.toString().toLowerCase(), 16);
          }
        }

        return;
      }
    }
    else if (c == 'u'.charCodeAt(0))
      token.type = TokenType.EncodedChar;
    else
      token.type = TokenType.Keyword;

    // Read keyword
    var keyword = new StringBuilder();
    c = this._reader.peek();

    while (StringUtil.isLetter(c)) {
      this._reader.read();
      keyword.append(c);
      c = this._reader.peek();
    }

    token.key = keyword.toString();

    // Read an integer
    if (StringUtil.isDigit(c) || c == '-'.charCodeAt(0)) {
      token.hasParam = true;
      var negative = false;

      if (c == '-'.charCodeAt(0)) {
        negative = true;
        this._reader.read();
      }
      c = this._reader.peek();
      var text = new StringBuilder();

      while (StringUtil.isDigit(c)) {
        this._reader.read();
        text.append(c);
        c = this._reader.peek();
      }

      var param = Number.parseInt(text.toString());
      if (negative)
        param = -param;
      token.param = param;
    }
    if (c == ' '.charCodeAt(0))
      this._reader.read();
  }

  private parseText(c: number, token: Token) {
    var stringBuilder = new StringBuilder(c);
    c = this.clearWhiteSpace();
    while (c != '\\'.charCodeAt(0) && c != '}'.charCodeAt(0) && c != '{'.charCodeAt(0) && c != Eof) {
      this._reader.read();
      stringBuilder.append(c);
      c = this.clearWhiteSpace();
    }
    token.key = stringBuilder.toString();
  }

  private clearWhiteSpace(): number {
    var c = this._reader.peek();
    while (c == '\r'.charCodeAt(0) || c == '\n'.charCodeAt(0) || c == '\t'.charCodeAt(0) || c == '\0'.charCodeAt(0)) {
      this._reader.read();
      c = this._reader.peek();
    }
    return c;
  }
}


