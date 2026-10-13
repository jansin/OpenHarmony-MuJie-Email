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


import { getLogger } from "../utils/log";
import { CMError, ErrorCode } from "../api";
import type {
  IMail,
  ITransport,
  Properties,
  EmailAddress,
  InlineImage,
  Attachment,
  IBuffer,
} from "../api";
import { SMTP_CODE, SmtpProtocol } from "../protocols/smtp_protocol";
import { serializeMail } from "../utils/mime";
import { guessContentType, openFile, getFileName } from "../utils/file_stream";

const logger = getLogger("transport");

export class SmtpTransport implements ITransport {
  properties?: Properties;
  constructor() {}

  setProperties(properties: Properties): void {
    this.properties = properties;
  }

  async getProtocol(): Promise<SmtpProtocol> {
    if (!this.properties) {
      throw new CMError("Properties not set", ErrorCode.PARARMETER_MISSED);
    }
    let { smtp, userInfo, ca} = this.properties;
    let sp = new SmtpProtocol(smtp.host, smtp.port, smtp.secure, ca);
    await sp.connect();
    await sp.ehlo(smtp.host);
    const res = await sp.auth(userInfo.username, userInfo.password);
    if (res.code != SMTP_CODE.AUTH_SUCCESS) {
      sp.quit();
      throw new CMError(res.message.join(""), ErrorCode.LOGIN_FAILED, res.code);
    }
    return sp;
  }

  async check(): Promise<void> {
    const sp = await this.getProtocol();
    sp.quit();
    sp.stop()
  }

  async sendMail(
    from: EmailAddress,
    toList: EmailAddress[],
    ccList: EmailAddress[],
    bccList: EmailAddress[],
    subject: string,
    richText: string,
    plainText: string,
    inlineImages: { content: IBuffer; fileName: string; contentId: string }[],
    attachments: { fileName: string; content: IBuffer}[]
  ): Promise<void> {
    logger.trace("start send mail");
    const images: InlineImage[] = inlineImages.map(image => {
      return {
        name: image.fileName,
        body: image.content,
        contentId: image.contentId,
        contentType: guessContentType(image.fileName),
        type: "",
        subType: "",
        size: 0,
      };
    });
    const attachs: Attachment[] = attachments.map(attachment => {
      return {
        name: attachment.fileName,
        body: attachment.content,
        contentType: guessContentType(attachment.fileName),
        type: "",
        subType: "",
        size: 0,
      };
    });
    logger.trace("start serialize mail");
    let mail = await serializeMail(
      { from, to: toList, cc: ccList, bcc: bccList, subject },
      new Map([
        ["date", { value: (new Date()).toUTCString() }]
      ]),
      richText,
      plainText,
      images,
      attachs
    );
    logger.debug("send mail", mail);
    let sp = await this.getProtocol();
    let res = await sp.mail(from.email);
    if (res.code >= 300) {
      const text = res.message.join("");
      logger.error("send mail from", res.code, text);
      throw new CMError(text, ErrorCode.SENT_MAIL_FAILED, res.code);
    }

    const emailList = toList.concat(ccList).concat(bccList);
    for (const to of emailList) {
      res = await sp.rcpt(to.email);
      if (res.code >= 300) {
        const text = res.message.join("");
        logger.error("send mail from", res.code, text);
        throw new CMError(text, ErrorCode.SENT_MAIL_FAILED, res.code);
      }
    }
    let response = await sp.data(mail);
    await sp.quit();
    sp.stop();
    if (response.code >= 300) {
      const text = res.message.join("");
      logger.error("send mail from", res.code, text);
      throw new CMError(text, ErrorCode.SENT_MAIL_FAILED, response.code);
    }
  }
}
