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

import { Consts } from './consts';
import { LayerInfo } from './layer_info';
import { Lex } from './lex';
import { Stack } from './stack';
import { TextReader } from './text_reader';
import { Token } from './token';
import { TokenType } from './token_type';

export class Reader {
  _layerStack: Stack<LayerInfo> = new Stack();
  lastToken: Token | null = null;
  currentToken: Token | null = null;
  _lex: Lex;
  innerReader: TextReader;
  parsingHighLowSurrogate: boolean;
  highSurrogateValue: number | null = null;
  ;
  constructor(reader: TextReader) {
    this._lex = new Lex(reader)
    this.innerReader = reader;
  }

  public readToken(): Token {
    this.lastToken = this.currentToken;
    this.currentToken = this._lex.nextToken();
    if (this.currentToken == null || this.currentToken.type == TokenType.Eof) {
      this.currentToken = null;
      return null;
    }

    switch (this.currentToken.type) {
      case TokenType.GroupStart: {
        if (this._layerStack.count() == 0) {
          this._layerStack.push(new LayerInfo());
        }
        else {
          var info = this._layerStack.peek();
          this._layerStack.push(info.clone());
        }
        break;
      }

      case TokenType.GroupEnd: {
        if (this._layerStack.count() > 0)
          this._layerStack.pop();
        break;
      }
    }

    switch (this.currentToken.key) {
      case Consts.Uc:
        let value = this.currentToken?.param ?? 0;
        this.CurrentLayerInfo.UcValue = value;
        break;

      case Consts.U:
        if (this.innerReader.peek() == '?'.charCodeAt(0))
          this.innerReader.read();
        break;
    }
    return this.currentToken;
  }

  get CurrentLayerInfo(): LayerInfo {
    if (this._layerStack.count() == 0) {
      this._layerStack.push(new LayerInfo())
    }
    return this._layerStack.peek();
  }

  get TokenType(): TokenType {
    return this.currentToken?.type ?? TokenType.None;
  }

  get Keyword(): string {
    return this.currentToken?.key;
  }

  get Parameter(): number {
    return this.currentToken?.param ?? 0;
  }

  readToEndOfGroup() {
    var level = 0;

    while (true) {
      var c = this.InnerReader.peek();
      if (c == -1)
        break;

      if (c == '{'.charCodeAt(0)) {
        level++;
      }

      else if (c == '}'.charCodeAt(0)) {
        level--;
        if (level < 0) break;
      }

      this.InnerReader.read();
    }
  }

  get HasParam(): boolean {
    return this.currentToken?.hasParam ?? false;
  }

  get InnerReader(): TextReader {
    return this.innerReader;
  }

  peekTokenType(): TokenType {
    return this._lex.peekTokenType();
  }
}