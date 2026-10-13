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

// a outlook msg reader
import { CFBReader, DirectoryObjectType } from './cfb';
import type { DirectoryEntry } from './cfb';
import propertyTags from './msg_property_tag';
import { FieldType } from './msg_def';
import { getLogger } from '../utils/log';
import { decodeCharset } from '../utils/encodings';
import util from '@ohos.util';
import { CompressedRtfDecoder } from './compressed_rtf_decoder';
import { Document } from './rtf/document';

const logger = getLogger("msg");

export { CFBReader, DirectoryObjectType, DirectoryEntryTreeItem, DirectoryEntry } from "./cfb";

enum FieldName {
  senderEmail = "5D02",
  extension = "3703",
  addressType = "3002",
  email = "3003",
  RecipientType = "0C15",
  RecipientDisplayName = "5FF6",
  SmtpAddress = "39Fe",
  DisplayName = "3001",
  AddressType = "3002",
  EmailAddress = "3003",
  NormalizedSubject = "0e1d",
  subject = "0037",
  OriginalSubject = "0049",
  ClientSubmitTime = "0039",
  ProviderSubmitTime = "0048",
  CreationTime = "3007",
  LastModificationTime = "3008",
  MessageDeliverTime = "0E06",
  SenderEmailAddress = "0C1F",
  SenderName = "0C1A",
  SenderSmtpAddress = "5D01",
  SenderAddressType = "0C1E",
  PlaintextBody = "1000",
  htmlBody = "1013",
  TransportMessageHeaders = "007D",
  RtfCompressed = "1009",
  AttachFilename = "3704",
  AttachLongFilename = "3707",
  AttachDataBinary = "3701",
  AttachMimeTag = "370E",
  AttachContentId = "3712",
  InternetCodepage = "3FDE",
  DisplayTo = "0E04",
  DisplayCc = "0E03",
  DisplayBcc = "0E02",
}

export type DirectoryItem = {
  name: string;
  value: string | Uint8Array;
  nameCode: number;
  typeCode: number;
};

type MsgMailAddress = {
  name: string;
  email: string;
}

type MsgMailAttach = {
  name?: string;
  value: Uint8Array;
  mime: string;
  attachContentId: string;
}

type MsgMailEntry = {
  from: MsgMailAddress;
  to: MsgMailAddress[];
  cc: MsgMailAddress[];
  bcc: MsgMailAddress[];
  subject: string;
  body: string;
  htmlBody: string;
  attachments: MsgMailAttach[];
  inlineImages: MsgMailAttach[];
}

// type Temp = {
//   [key: string]: any;
// };

export class MsgReader {
  // _temp: Temp = {};
  _cfb: CFBReader;


  fromEmail: string;
  fromName: string;
  displayCc: string;
  displayTo: string;
  displayBcc: string;
  subject: string;
  body: string;
  htmlBody: string;

  receiverList: MsgMailAddress [] = [];
  attachList: MsgMailAttach [] = [];

  constructor(buffer: ArrayBuffer) {
    this._cfb = new CFBReader(buffer);
  }

  // getData(): Temp {
  //   return this._temp;
  // }

  parse(): MsgMailEntry {
    const directoryEntries = this._cfb.parse();
    logger.trace("===============================");
    for (const entry of directoryEntries) {
      this.dispatch(entry);
    }
    console.info("msg debug:" + this.attachList.length);

    let inlinesMaybe = this.attachList.filter(item => (item.attachContentId != ""));
    let attach = this.attachList.filter(item => (item.attachContentId == ""));

    //进一步检查内联附件,如果html中没有用到此contentid,则也为外部附件.
    let inlines:MsgMailAttach[] = [];
    inlinesMaybe .forEach((item)=>{
      if(this.htmlBody && this.htmlBody.indexOf(item.attachContentId) == -1) {
        attach.push(item)
      }
      else {
        inlines.push(item);
      }
    });

    let tempTo: MsgMailAddress[] = [];
    let tempCc: MsgMailAddress[] = [];
    let tempBcc: MsgMailAddress[] = [];

    if (this.displayTo) {
      let obj = {};
      this.displayTo.split(";").map((value) => {
        obj[value.trim()] = true;
      });
      tempTo = this.receiverList.filter((item) => {
        return obj[item.name] || obj[item.email]
      });
    }

    if (this.displayCc) {
      let obj = {};
      this.displayCc.split(";").map((value) => {
        obj[value.trim()] = true;
      });
      tempCc = this.receiverList.filter((item) => {
        return obj[item.name] || obj[item.email]
      });
    }

    if (this.displayBcc) {
      let obj = {};
      this.displayBcc.split(";").map((value) => {
        obj[value.trim()] = true;
      });
      tempBcc = this.receiverList.filter((item) => {
        return obj[item.name] || obj[item.email]
      });
    }

    let mailEntry: MsgMailEntry = {
      from: { name: this.fromName, email: this.fromEmail },
      to: tempTo,
      cc: tempCc,
      bcc: tempBcc,
      htmlBody: this.htmlBody,
      body: this.body,
      attachments: attach,
      inlineImages:inlines,
      subject: this.subject
    };
    return mailEntry;
  }

  parseDirectory(entry: DirectoryEntry): DirectoryItem {
    const nameCode = parseInt(entry.name.substring(12, 16), 16);
    const typeCode = parseInt(entry.name.substring(16), 16);
    const name = propertyTags.get(nameCode)?.[0] || entry.name;
    const buff = this._cfb.readDirectoryData(entry);
    let value: string | Uint8Array = buff;
    if (typeCode == FieldType.UNICODE) {
      // utf-16le/be
      value = decodeCharset(buff, 'utf-16le')
    } else if (typeCode == FieldType.STRING) {
      value = decodeCharset(buff, "utf-8");
    }
    return { name: name, value: value, nameCode: nameCode, typeCode: typeCode }
  }

  setAttach(di: DirectoryItem, attach: MsgMailAttach): void {
    switch (di.name) {
      case "ATTACH_DATA_BIN":
        attach.value = di.value as Uint8Array;
        break;
      case "ATTACH_MIME_TAG":
        attach.mime = di.value as string;
        break;
      case "ATTACH_FILENAME":
        if(!attach.name) {
          attach.name = di.value as string;
        }
        break;
      case "ATTACH_CONTENT_ID":
        attach.attachContentId = di.value as string;
        break;
      case "ATTACH_LONG_FILENAME":
      //优先使用ATTACH_LONG_FILENAME吧.
        attach.name = di.value as string;
        break;
    }
  }

  setReceiver(di: DirectoryItem, mailAddress: MsgMailAddress): void {
    switch (di.name) {
      case "DISPLAY_NAME":
        mailAddress.name = di.value?.toString();
        break;
      case "EMAIL_ADDRESS":
        mailAddress.email = di.value?.toString();
        break;
    }
  }

  setValue(di: DirectoryItem): void {
    switch (di.name) {
      case "SENT_REPRESENTING_EMAIL_ADDRESS":
        this.fromEmail = di.value as string;
        break;
      case "SENDER_NAME":
        this.fromName = di.value as string;
        break;
      case "DISPLAY_TO":
        this.displayTo = di.value as string;
        break
      case "DISPLAY_CC":
        this.displayCc = di.value as string;
        break;
      case "DISPLAY_BCC":
        this.displayBcc = di.value as string;
        break;
      case "EMAIL_ADDRESS": // 添加到 address

        break;
      case "SUBJECT":
        this.subject = di.value.toString();
        break;
      case "BODY":
        this.body = di.value.toString();
        break;
      case "HTML_BODY":
        let u8a = di.value as Uint8Array;
      //TODO:需要获取对应编码
        if(!this.htmlBody) {
          this.htmlBody = this.decodeUint8Array(u8a, "utf-8");
        }
        break;
      default:
        break;
    }
  }

  /**
   * 将序作为utf8序列进行转换.
   * @param u8a
   * @returns
   */
  decodeUint8Array(u8a:Uint8Array,encoding:string):string {
    let decoder:util.TextDecoder = util.TextDecoder.create(encoding);
    let str:string = decoder.decodeWithStream(u8a);
    return str;
  }

  /**
   * 适用于latin1字符集的编码.
   * @param u8a
   * @returns
   */
  uint8ArrayToString(u8a: Uint8Array): string {
    let dataStr: string = "";
    for (var i = 0; i < u8a.length; i++) {
      dataStr += String.fromCharCode(u8a[i])
    }
    return dataStr;
  }

  dispatch(entry: DirectoryEntry): void {
    switch (entry.objectType) {
      case DirectoryObjectType.Stream:
        if (entry.name.startsWith("__substg1.0_")) {
          let di: DirectoryItem = this.parseDirectory(entry);
          this.setValue(di);
          if (di.name == "RTF_COMPRESSED") {
            let src = di.value as Uint8Array;
            let dst:Uint8Array|null = CompressedRtfDecoder.decompress(src);
            if(dst) {
              // let verifyData = dst.subarray(0,100);
              let bodyRtf = this.decodeUint8Array(dst, "utf-8");
              var rtfDomDocument = new Document();
              rtfDomDocument.DeEncapsulateHtmlFromRtf(bodyRtf);
              let html = rtfDomDocument.htmlContent;
              this.htmlBody = html;
            }
          }
          logger.trace("entry1",
            di.name,
            "value:" + di.value,
            "typeCode:" + di.typeCode.toString(16),
            "Location:" + entry.startSectorLocation,
            "streamSize:" + entry.streamSize
          );
        } else {
          logger.trace(
            "entry2",
            ` name:${entry.name}`,
            ` entry.startSectorLocation:${entry.startSectorLocation}`,
            ` entry.streamSize:${entry.streamSize}`
          );
        }
        break;
      case DirectoryObjectType.Storage:
        if (entry.name.startsWith("__attach_version1.0")) {
          const buff = this._cfb.readStorage(entry);
          let attItem: MsgMailAttach = { name: "", value: new Uint8Array(), mime: "", attachContentId: "" }
          for (const subEntry of buff) {
            logger.trace("__attach0", `__attach_ name:${entry.name}`);
            if (subEntry.name.startsWith("__substg1.0_")) {
              let di: DirectoryItem = this.parseDirectory(subEntry);
              this.setAttach(di, attItem);
              logger.trace("__attach1",
                di.name,
                di.value,
                di.typeCode.toString(16),
                entry.startSectorLocation,
                entry.streamSize
              );
            } else {
              logger.trace("__attach2", `__attach_ name:${entry.name}`);
              if (subEntry.name.startsWith("__properties_version")) {
                this.attachList.push(attItem);
                // attItem = { name: "", value: new Uint8Array(), mime: "", attachContentId:"" }
              }
            }
          }
        } else if (entry.name.startsWith("__recip_version")) {
          const buff = this._cfb.readStorage(entry);
          let mailAddress: MsgMailAddress = { name: "", email: "" }
          for (const entry of buff) {
            logger.trace("__recip0", `__recip name:${entry.name}`);
            if (entry.name.startsWith("__substg1.0_")) {
              let di: DirectoryItem = this.parseDirectory(entry);
              this.setReceiver(di, mailAddress);
              logger.trace("__recip1",
                di.name,
                di.value,
                di.typeCode.toString(16),
                entry.startSectorLocation,
                entry.streamSize
              );
            } else {
              if (entry.name.startsWith("__properties_version")) {
                this.receiverList.push(mailAddress);
                mailAddress = { name: "", email: "" }
              }
            }
          }
        } else if (entry.name.startsWith("__nameid_version1.0")) {
          // const buff = this._cfb.readStorage(entry);
          // for (const entry of buff) {
          //   logger.trace("__nameid_0", `__nameid name:${entry.name}`);
          //   if (entry.name.startsWith("__substg1.0_")) {
          //     let pa: DirectoryItem = this.parseDirectory(entry);
          //     logger.trace("__nameid_1",
          //       pa.name,
          //       pa.value,
          //       pa.typeCode.toString(16),
          //       entry.startSectorLocation,
          //       entry.streamSize
          //     );
          //   }
          // }
        }
        break;
      case DirectoryObjectType.RootStorage:
        logger.trace(
          "__root_storage",
          ` name:${entry.name}`,
          ` entry.startSectorLocation:${entry.startSectorLocation}`,
          ` entry.streamSize:${entry.streamSize}`
        );
        break
    }
  }
}
