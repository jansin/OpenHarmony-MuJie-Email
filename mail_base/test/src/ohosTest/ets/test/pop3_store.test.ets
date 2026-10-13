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
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect, beforeItSpecified } from '@ohos/hypium'
import {
  EmailAddress,
  FolderType,
  IStore,
  MailAttribute,
  Properties,
  MailEngine,
  Pop3Store
} from '@coremail/mail_base';
import fs from '@ohos.file.fs'
import { createBufferCreator, FileBuffer } from './FileBuffer';

export default function pop3_storeTest() {
  const engine = new MailEngine();
  const username: string = "hma@jmtest.cn";
  const _toemail: string = "admin@jmtest.cn";

  describe('pop3_storeTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      const host: string = "172.16.10.30";
      const popport: number = 110;
      const smtpport: number = 25;
      const password: string = "admin123";

      const property:Properties = {pop3: {host: host, port: popport, secure: false},
        smtp: {host: host, port: smtpport, secure: false},
        userInfo: {username: username, password: password}};

      engine.setProperties(property);

      let store:IStore = new Pop3Store();
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

    it('remote_login_success', 0, async () => {
      const store = engine.getStore()
      let p = store.check()
      await p
      expect(p).assertPromiseIsResolved()
    })

    it('get_folders', 0, async () => {
      const root = await engine.getRootFolder()
      const subFolders = await root.getSubFolders()
      expect(subFolders.length).assertEqual(1);

      const inbox = subFolders[0]
      expect(inbox.getName()).assertEqual("INBOX")
    })


    it('get_inbox_mails', 0, async () => {
      const store = engine.getStore()
      await store.openFolder("INBOX")
      await store.closeFolder("INBOX")
      expect(store.supportedFeatures().length).assertEqual(0)

      const inbox = await engine.getFolder("INBOX")
      const mails = await inbox.getMailList(10, null, {
        by: 'date', desc: true
      })
      expect(mails.length <= 10).assertTrue()

      const mid = mails[4].getId()
      const sencond_page_mails = await inbox.getMailList(5, mid, {
        by: 'date', desc: true
      })
      expect(sencond_page_mails.length <= 5).assertTrue()
      for (let i = 0; i < sencond_page_mails.length; i++) {
        expect(sencond_page_mails[i].getId()).assertEqual(mails[5 + i].getId())
      }
      const m = mails[0]
      const f_name = m.getFolder().getName()
      const f_fullname = m.getFolder().getFullName()
      expect(f_name).assertEqual(inbox.getName())
      expect(f_fullname).assertEqual(inbox.getFullName())
      expect(f_fullname).assertContain(f_name)

      const mailIndex = await inbox.getMailIndex(m.getId(), {
        by: 'date', desc: true
      })
      expect(mailIndex).assertEqual(1)

      const m_buffer = await engine.getStore().getMail("INBOX", m.getId())
      expect(m_buffer).not().assertNull()

      const mail = m

      const mailFrom = await mail.getFrom()
      expect(mailFrom.email).not().assertNull()
      const mailTo = await mail.getTo()
      expect(mailTo.length).assertEqual(1)
      expect(mailTo[0].email).not().assertNull()
      const mailSubjct = await mail.getSubject()
      expect(mailSubjct).not().assertNull()
      const mailContent = await mail.getHtml()
      expect(mailContent).not().assertNull()
      const plainText = await mail.getPlain()
      expect(plainText).assertEqual("")
      const date = await mail.getDate()
      expect(date).not().assertNull()
      const size = await mail.getSize()
      expect(size).assertLarger(0)
      const summary = await mail.getDigest(10)
      expect(summary).not().assertNull()
    })

    it('send_attachment_mail', 0, async () => {
      try {
        engine.on('new-mail', (folderFullName, mails) => {
          expect(mails.length).assertEqual(1)
        })
      } catch (e) {
      }

      const imgBase64 = "iVBORw0KGgoAAAANSUhEUgAAACwAAAAiCAYAAAAkjjtxAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAJkSURBVHgB7ZhLTBNRGIXPFLApQlPFYKA1YYFKDOJC0K2PlSw00S1G3ZBA0OJGXZiIiRvdKGokkYUaWRk1caM7deHGCBt1QxQfUd6PNDThTYZ7LrmkpQOdCXNLm8y3mLm3c6c9c+b8fydjQFDd0nMDMFvFMITsJGYYxtNvDw5eNvZf7LlrmlJsDmDe9Amx5zlsOFKK8u1bkG1Q06nDJQgG8sTMiPrENnSsJoSrZ3bh5bV98mC2QBOp6VZDBWp3F/OjUF7poca2scl57AgWoKZiKyg+XOJH9484ZhdMbAbFws3Wk2E015fDX+DDm8/jePFpFHNCj1Hd0m0mXhEX8YSBiTlcaO+V+0yyNxzA/cZKGYX49AI63g3h+YfhleNJggkXPonuEXu/nD96OyBOGkQmoGGMJuntn8Klx30phqUIVtDpphNlcvz+awy3X/3T5jZNYk7rlnOKro8j0qj49GLKWplhqy/5IjJMgVWRgMh2EY4f2Cbnv4dn4Ca1lUUyAlWRQhmBpo6fK3m1Yk2HFauv3s2IXDkdwdmjO+WYBl3v+pP2LqYVrEiMyEYLkibQVRYYufP6f1JhuSJY/ZAqSOaLuWbLcUJyJ5oVrv6V7tplzQxbQZEswGBhvuOebdVbo519jmvCkcOJOOnZ6XprRgQTOz3bTm/NmGCFVc8mdnurE1wRTPjQ1FxfJt1WDqoIRDt/OSqs9XBNMFnds+32Vie4KljB7sFb75arieRDA8yxLnzIMTzBuvEE68YTrBtPsG48wbqhYH1//O4TE4LNduQOzwxuxSPmPbE7hyx+oU1jvz+sa1sC/ZI2edXLe2YAAAAASUVORK5CYII="
      const file = await fs.open("/data/storage/el2/base/files/sina.png", fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, imgBase64)

      const subject = "测试发送带附件的邮件"
      const inlingImgId = `${username}15426947`
      const content = `测试发送带附件的邮件的内容内容内容内容<img src="cid:${inlingImgId}">`
      const fromemail = username
      const toemail = _toemail
      const transport = engine.getTransport();
      const sendMailPromise = transport.sendMail(
        {
          name: '发件人', email: fromemail
        },
        [{
          name: '收件人', email: toemail
        }],
        [],
        [],
        subject,
        content,
        "",
        [{
          fileName: "sina.png", content: new FileBuffer("/data/storage/el2/base/files/sina.png"), contentId: inlingImgId
        }],
        [{
          fileName: "sina.png", content: new FileBuffer("/data/storage/el2/base/files/sina.png")
        }]
      )
      await sendMailPromise
      expect(sendMailPromise).assertPromiseIsResolved()
    })

    it('pop3_unspport_function', 0, async () => {
      const inbox = await engine.getInbox()
      const mails = await inbox.getMailList(1, null, {
        by: 'date', desc: true
      })
      const m = mails[0]

      try {
        await m.isSeen()
      } catch (e) {
        expect(e).not().assertNull()
      }
      try {
        await m.isFlagged()
      } catch (e) {
        expect(e).not().assertNull()
      }
      try {
        await m.setSeen(true)
      } catch (e) {
        expect(e).not().assertNull()
      }
      try {
        await m.setFlagged(true)
      } catch (e) {
        expect(e).not().assertNull()
      }
      const root = await engine.getRootFolder()
      try {
        await root.createSubFolder("newFolderName")
      } catch (e) {
        expect(e).not().assertNull()
      }
      try {
        await root.renameFolder("newFolderName")
      } catch (e) {
        expect(e).not().assertNull()
      }
      try {
        await root.deleteSubFolder("INBOX")
      } catch (e) {
        expect(e).not().assertNull()
      }
      const mid = m.getId()
      const store = engine.getStore()
      try {
        await store.moveMail("INBOX", mid, "newFolderName")
      } catch (e) {
        expect(e).not().assertNull()
      }
      try {
        await store.copyMail("INBOX", mid, "newFolderName")
      } catch (e) {
        expect(e).not().assertNull()
      }
      try {
        await store.addMail(mid, "INBOX")
      } catch (e) {
        expect(e).not().assertNull()
      }
      try {
        await store.searchMail({
          fields: {
            from: "keyword",
            to: null,
            subject: null,
            attachment: null
          },
          folder: "INBOX"
        })
      } catch (e) {
        expect(e).not().assertNull()
      }
      try {
        await store.filterMail({isFlagged: true})
      } catch (e) {
        expect(e).not().assertNull()
      }
    })

    it('delete_mail', 0, async () => {
      const inbox = await engine.getFolder("INBOX")
      const count = await inbox.getMailCount()
      const mails = await inbox.getMailList(count, null, {
        by: 'date', desc: true
      })
      const m = mails[count - 1]
      const deletePromise = engine.getStore().deleteMail("INBOX", m.getId())
      await deletePromise
      expect(deletePromise).assertPromiseIsResolved()
    })
  })
}