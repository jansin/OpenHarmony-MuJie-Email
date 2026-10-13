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
import { DocumentInfo } from './document_info';
import { Encoding } from './encoding';
import { Environments } from './environments';
import { Font } from './font';
import { FontTable } from './font_table';
import { Reader } from './reader';
import { StringBuilder } from './string_builder';
import { StringCodec } from './string_codec';
import { TextContainer } from './text_container';
import { TextReader } from './text_reader';
import { Token } from './token';
import { TokenType } from './token_type';
import { CMError, ErrorCode } from '../../api';

//
const LangCodepageMap:Map<number,number> = new Map([[0x804,0x3a8]])


export class Document {
  fontTable: FontTable
  private _runtimeEncoding: Encoding | null;
  private _defaultEncoding: Encoding = Encoding.Default;
  _defaultFont?: number
  _defaultLanguage?: number
  info: DocumentInfo = new DocumentInfo();
  htmlContent: string | null = null;

  constructor() {
    this.fontTable = new FontTable();
  }

  get RuntimeEncoding(): Encoding {
    return this._runtimeEncoding ?? this._defaultEncoding;
  }

  public DeEncapsulateHtmlFromRtf(rtf: string): void {
    var stringBuilder = new StringBuilder();
    var rtfContainsEmbeddedHtml = false;
    let byteBuffer = new ByteBuffer();
    var ignore = true;

    let textReader = new TextReader(rtf);
    let reader = new Reader(textReader);

    while (reader.readToken() != null) {
      if (byteBuffer.length() > 0 && reader.TokenType != TokenType.EncodedChar) {
        if (this.fontTable.MixedEncodings && this._runtimeEncoding.IsSingleByte && byteBuffer.length() > 1 && byteBuffer.byteAt(0) >= 0x80) {
          let str = this.tryDecode(byteBuffer);
          stringBuilder.appendString(str);
        }
        else {
          let str = StringCodec.getString(byteBuffer, this._runtimeEncoding)
          stringBuilder.appendString(str);
        }
        byteBuffer.clear();
      }

      switch (reader.TokenType) {
        case TokenType.Keyword:
          switch (reader.Keyword) {
            case Consts.Ansicpg:
              this._defaultEncoding = Font.encodingFromCodePage(reader.Parameter);
              break;
            case Consts.Deff:
              this._defaultFont = reader.Parameter;
              break;

            case Consts.DefLang:
              this._defaultLanguage = reader.Parameter;
              break;

            case Consts.Info:
              this.readDocumentInfo(reader);
              return;

            case Consts.FromHtml:
              rtfContainsEmbeddedHtml = true;
              break;

            case Consts.Fonttbl:
              this.readFontTable(reader);
              break;

            case Consts.F:
            case Consts.Af: {
              var font = this.fontTable[reader.Parameter];
              this._runtimeEncoding = font?.Encoding ?? this._defaultEncoding;

              break;
            }

            case Consts.Lang: {
              try {
                var lang = reader.Parameter;
                let codepage = LangCodepageMap.get(lang);
                if(codepage) {
                  let codePageName = Font.codePages.get(codepage);
                  this._runtimeEncoding = Encoding.getEncoding(codePageName);
                }
              }
              catch {
                // Ignore
              }
              break;
            }

            case Consts.Plain:
              try {
                if (this._defaultLanguage != undefined) {
                  this._runtimeEncoding = Encoding.Default;
                }
              }
              catch {
                // Ignore
              }

              try {
                if (this._defaultFont != undefined) {
                  var font = this.fontTable[this._defaultFont];
                  this._runtimeEncoding = font?.Encoding ?? this._defaultEncoding;
                }
              }
              catch {
                // Ignore
              }

              break;

            case Consts.Pntxtb:
            case Consts.Pntext:
              if (ignore) continue;
              reader.readToEndOfGroup();
              break;

            case Consts.HtmlRtf:
              if (reader.HasParam && reader.Parameter == 0)
                ignore = false;
              else
                ignore = true;

              break;

            case Consts.Tab:
              stringBuilder.appendString("\t");
              break;

            case Consts.Lquote:
              stringBuilder.appendString("&lsquo;");
              break;

            case Consts.Rquote:
              stringBuilder.appendString("&rsquo;");
              break;

            case Consts.LdblQuote:
              stringBuilder.appendString("&ldquo;");
              break;

            case Consts.RdblQuote:
              stringBuilder.appendString("&rdquo;");
              break;

            case Consts.Bullet:
              stringBuilder.appendString("&bull;");
              break;

            case Consts.Endash:
              stringBuilder.appendString("&ndash;");
              break;

            case Consts.Emdash:
              stringBuilder.appendString("&mdash;");
              break;

            case Consts.Tilde:
              stringBuilder.appendString("&nbsp;");
              break;

            case Consts.Underscore:
              stringBuilder.appendString("&shy;");
              break;
          }
          break;

        case TokenType.Extension:

          switch (reader.Keyword) {
            case Consts.HtmlTag: {
              ignore = false;

              if (reader.InnerReader.peek() == ' '.charCodeAt(0))
                reader.InnerReader.read();

              var text = this.readInnerText2(reader, null, true, true, this.RuntimeEncoding);

              if (!StringUtil.isNullOrEmpty(text))
                stringBuilder.appendString(text);
              break;
            }
          }

          break;

        case TokenType.EncodedChar:

          if (ignore) continue;

          switch (reader.Keyword) {
            case Consts.Apostrophe:

              byteBuffer.add(reader.Parameter);
              break;

            case Consts.U:

              if (reader.Parameter.toString().startsWith("c") || reader.Parameter.toString().startsWith("C"))
                throw new CMError("\\uc parameter not yet supported", ErrorCode.RTF_PARSER_FAILED);

              if (reader.Parameter.toString().startsWith("-")) {

                let value: number = 65536 + parseInt(reader.Parameter.toString());

                if (value >= 0xD800 && value <= 0xDFFF) {
                  if (!reader.parsingHighLowSurrogate) {
                    reader.parsingHighLowSurrogate = true;
                    reader.highSurrogateValue = value;
                  }
                  else {
                    var combined = ((reader.highSurrogateValue - 0xD800) << 10) + (value - 0xDC00) + 0x10000;
                    // TODO:
                    stringBuilder.appendString(`&#${combined};`);
                    reader.parsingHighLowSurrogate = false;
                    reader.highSurrogateValue = null;
                  }
                }
                else {
                  reader.parsingHighLowSurrogate = false;
                  stringBuilder.appendString(`"&#${value};`);
                }
              }
              else
                stringBuilder.appendString(`&#${reader.Parameter};`);
              break;
          }

          break;


        case TokenType.Text:
          if (!ignore)
            stringBuilder.appendString(reader.Keyword);
          break;

        case
        TokenType.None:
        case
        TokenType.GroupStart:
        case
        TokenType.GroupEnd:
        case
        TokenType.Eof:
          break;

        default:
          throw new CMError("ArgumentOutOfRangeException", ErrorCode.RTF_ARGMENT_OUT_OF_RANGE)
      }
    }

    if (rtfContainsEmbeddedHtml) {
      this.htmlContent = stringBuilder.toString();
    }
  }

  /**
   * 根据字节探测编码,然后再解码得到字符串(unicode序列).
   * @param byteBuffer
   * @returns
   */
  private tryDecode(byteBuffer: ByteBuffer): string {
    return StringCodec.getString(byteBuffer, this._defaultEncoding);
  }

  readDocumentInfo(reader: Reader) {
    this.info.clear();
    var level = 0;

    while (reader.readToken() != null)
      if (reader.TokenType == TokenType.GroupStart) {
        level++;
      }
      else if (reader.TokenType == TokenType.GroupEnd) {
        level--;
        if (level < 0)
          break;
      }
      else {
        switch (reader.Keyword) {
          case "creatim":
            this.info.creationTime = this.readDateTime(reader);
            level--;
            break;

          case "revtim":
            this.info.revisionTime = this.readDateTime(reader);
            level--;
            break;

          case "printim":
            this.info.printTime = this.readDateTime(reader);
            level--;
            break;

          case "buptim":
            this.info.backupTime = this.readDateTime(reader);
            level--;
            break;

          default:
            if (reader.Keyword != null) {
              let value: string = reader.HasParam ? reader.Parameter.toString() : this.readInnerText(reader, true);
              this.info.setInfo(reader.Keyword, value);
              break;
            }
        }
      }
  }


  private readDateTime(reader: Reader): number {
    var year = 1900;
    var month = 1;
    var day = 1;
    var hour = 0;
    var min = 0;
    var sec = 0;

    while (reader.readToken() != null) {
      if (reader.TokenType == TokenType.GroupEnd)
        break;

      switch (reader.Keyword) {
        case "yr":
          year = reader.Parameter;
          break;

        case "mo":
          month = reader.Parameter;
          break;

        case "dy":
          day = reader.Parameter;
          break;

        case "hr":
          hour = reader.Parameter;
          break;

        case "min":
          min = reader.Parameter;
          break;

        case "sec":
          sec = reader.Parameter;
          break;
      }
    }

    let date = new Date(year, month, day, hour, min, sec);
    return date.getTime();
  }

  readFontTable(reader: Reader) {
    this.fontTable.clear();
    while (reader.readToken() != null) {
      if (reader.TokenType == TokenType.GroupEnd)
        break;

      if (reader.TokenType != TokenType.GroupStart) continue;

      var font = new Font();

      while (reader.readToken() != null) {
        if (reader.TokenType.valueOf() == TokenType.GroupEnd.valueOf())
          break;

        if (reader.TokenType == TokenType.GroupStart) {
          // If we meet nested levels, then ignore
          reader.readToken();
          reader.readToEndOfGroup();
          reader.readToken();
        }
        else {
          switch (reader.Keyword) {
          // case Consts.F when reader.HasParam:
            case Consts.F: {
              if (reader.HasParam) {
                font._index = reader.Parameter;
              }
            }
              break;

            case Consts.Fnil:

              font.name = "Arial";

              break;

            case Consts.Fcharset:
              font.charset = reader.Parameter;
              break;

            default:

              if (reader.currentToken.isTextToken())
                font.name = this.readInnerText2(reader, reader.currentToken, false, false, font.encoding ?? this.RuntimeEncoding);

              break;
          }
        }
      }


      // font.name = font.name.TrimEnd(';').Trim('\"');
      font.name = StringUtil.trimEnd(font.name, ";");
      font.name = StringUtil.trim(font.name, "\"");
      if (StringUtil.isNullOrEmpty(font.name)) {
        font.name = "Arial";
      }
      this.fontTable.push(font);
    }
  }

  private readInnerText(reader: Reader, deeply: boolean): string {
    return this.readInnerText2(reader, null, deeply, false, this.RuntimeEncoding);
  }

  private readInnerText2(
    reader: Reader,
    firstToken: Token,
    deeply: boolean,
    htmlExtraction: boolean,
    encoding: Encoding): string {
    var level = 0;
    var container = new TextContainer(encoding);
    container.accept(firstToken, reader);

    while (true) {
      var type = reader.peekTokenType();

      if (type == TokenType.Eof)
        break;

      if (type == TokenType.GroupStart) {
        level++;
      }
      else if (type == TokenType.GroupEnd) {
        level--;
        if (level < 0)
          break;
      }

      reader.readToken();

      if (!deeply && level != 0)
        continue;

      if (htmlExtraction && reader.Keyword == Consts.Par) {
        container.append(Environments.NewLine);
        continue;
      }

      container.accept(reader.currentToken, reader);
    }

    return container.Text;
  }
}




