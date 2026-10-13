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

import type {
  IEmlParser,
  MailData,
  MailEnvelope,
  InlineImage,
  Attachment,
  Mime,
  IBuffer,
} from "../api";
import { parseMime2, serializeMail } from "../utils/mime";

export class EmlParser implements IEmlParser {
  async mimeParse(
    content: string | IBuffer
  ): Promise<Mime> {
    const mime = await parseMime2(content);
    return mime;
  }
}

