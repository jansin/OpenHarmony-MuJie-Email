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

import { TokenType } from './token_type';

/**
 * Token代表的是一段有意义的字符序列,长度不定.
 */
export class Token {
  /// <summary>
  ///     Type
  /// </summary>
  public type: TokenType;

  /// <summary>
  ///     Key
  /// </summary>
  public key: string;

  /// <summary>
  ///     True when the token has a param
  public hasParam: boolean;

  /// <summary>
  ///     Param value
  /// </summary>
  public param: number

  /// <summary>
  ///     True when the token contains text
  /// </summary>
  isTextToken(): boolean {
    return this.type == TokenType.Text;
  }

  public constructor() {
    this.type = TokenType.None;
    this.param = 0;
  }
}