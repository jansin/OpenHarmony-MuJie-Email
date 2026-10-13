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
import {
  afterAll,
  afterEach,
  ArgumentMatchers,
  beforeAll,
  beforeEach,
  beforeItSpecified,
  describe,
  expect,
  it,
  MockKit,
  when
} from '@ohos/hypium';
import {
  EmailAddress,
  FolderType,
  IStore,
  MailAttribute,
  Properties,
  MailEngine,
  ImapStore,
  serializeMail,
} from '@coremail/mail_base';
import { createBufferCreator, FileBuffer } from './FileBuffer';

export default function imap_mailAttrTest() {
  describe('imap_mailAttrTest', () => {

    const engine = new MailEngine();
    const username: string = "hma@jmtest.cn";
    const _toemail: string = "admin@jmtest.cn";

    beforeAll(() => {
      const host: string = "172.16.10.30";
      const imapport: number = 143;
      const smtpport: number = 25;
      const password: string = "admin123";

      const property: Properties = {
        imap: {
          host: host, port: imapport, secure: false
        },
        smtp: {
          host: host, port: smtpport, secure: false
        },
        userInfo: {
          username: username, password: password
        }
      };

      engine.setProperties(property);

      let store: IStore = new ImapStore();
      store.setProperties(property);
      try {
        store.setBufferCreator(createBufferCreator("/data/storage/el2/base/files/", username))
      } catch (e) {
      }

      engine.registerStore(store);
      engine.setProperties(property);
      engine.setSyncInterval(60 * 60);
      engine.showDebugLog(false);
      engine.sync();
    })
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    })
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    })
    afterAll(() => {
      engine.getStore()!.release!()
    })
    beforeItSpecified(['send_attachment_mail'], async () => {
      const transport = engine.getTransport()
      const checkPromise = transport.check()
      await checkPromise
      expect(checkPromise).assertPromiseIsResolved()
    })

    it('get_mail_attrs_seen', 0, async () => {
      const inbox = await engine.getInbox()
      const mailCount = await inbox.getMailCount()
      const mails = await inbox.getMailList(mailCount, null, {
        by: 'date', desc: true
      })
      const mail = mails[mailCount - 1]
      // 已读属性
      const seen = await mail.isSeen();
      const isBoolean = typeof seen == 'boolean';
      expect(isBoolean).assertTrue();
      await mail.setSeen(!seen);
      const newSeen = await mail.isSeen();
      expect(newSeen).assertEqual(!seen);
    })
    it('get_mail_attrs_answered', 0, async () => {
      const inbox = await engine.getInbox()
      const mailCount = await inbox.getMailCount()
      const mails = await inbox.getMailList(mailCount, null, {
        by: 'date', desc: true
      })
      const mail = mails[mailCount - 1]
      // 已回复属性
      const answered = await mail.isAnswered();
      const isBoolean = typeof answered == 'boolean';
      expect(isBoolean).assertTrue();
      await mail.setAnswered(!answered);
      const newAnswered = await mail.isAnswered();
      expect(newAnswered).assertEqual(!answered);
    })
    it('get_mail_attrs_flagged', 0, async () => {
      const inbox = await engine.getInbox()
      const mailCount = await inbox.getMailCount()
      const mails = await inbox.getMailList(mailCount, null, {
        by: 'date', desc: true
      })
      const mail = mails[mailCount - 1]
      // 重要属性
      const flagged = await mail.isFlagged();
      const isBoolean = typeof flagged == 'boolean';
      expect(isBoolean).assertTrue();
      await mail.setFlagged(!flagged);
      const newFlagged = await mail.isFlagged();
      expect(newFlagged).assertEqual(!flagged);
    })

  })
}