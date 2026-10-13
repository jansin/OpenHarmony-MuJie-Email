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
  Mail,
  getFileName,
  openFile
} from '@coremail/mail_base';
import fs from '@ohos.file.fs';
import { createBufferCreator, FileBuffer } from './FileBuffer';

export default function imap_storeTest() {
  describe('imap_storeTest', () => {

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

    it('remote_login_success', 0, async () => {
      const store = engine.getStore()
      let p = store.check()
      await p
      expect(p).assertPromiseIsResolved()
    })

    it("search_mail", 0, async () => {
      const store = engine.getStore()
      let p = store.check()
      await p
      expect(p).assertPromiseIsResolved()

      let keyword = username

      // 文件夹搜索
      const inbox = await engine.getFolder("INBOX")
      if (inbox) {
        let inboxIds = await inbox.searchMail({
          fields: {
            from: keyword,
            to: null,
            subject: null,
            attachment: null
          }
        })
        expect(inboxIds.length).assertLargerOrEqual(0)
      }

      let mails = await engine.search(keyword, ['from', 'subject'], 0, 10)
      expect(mails.length).assertLargerOrEqual(0)

      let closeAction = inbox.close()
      await closeAction
      expect(closeAction).assertPromiseIsResolved()
    })

    it('get_folders', 0, async () => {
      const root = await engine.getRootFolder()
      const subFolders = await root.getSubFolders()
      expect(subFolders.length).assertLarger(1);

      const inbox = subFolders.find(f => f.getType() == FolderType.inbox)
      expect(inbox).not().assertNull()

      const sent = subFolders.find(f => f.getType() == FolderType.sent)
      expect(sent).not().assertNull()

      const important = subFolders.find(f => f.getType() == FolderType.important)
      expect(important).not().assertNull()

      const draft = await engine.getDraft()
      expect(draft).not().assertNull()
    })

    it('get_inbox_mails', 0, async () => {
      const inbox = await engine.getFolder("INBOX")
      await inbox.open()
      expect(inbox.isOpen()).assertTrue()

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
    })

    it('change_mail_flags', 0, async () => {
      const inbox = await engine.getInbox()
      const mails = await inbox.getMailList(1, null, {
        by: 'date', desc: true
      })
      const m = mails[0]

      const isSeen = await m.isSeen()
      const isFlaged = await m.isFlagged()
      expect(isSeen).not().assertNull()
      expect(isFlaged).not().assertNull

      m.on("attr-changed", (attr, hasAttr) => {
        if (attr == MailAttribute.Seen) {
          expect(hasAttr).assertEqual(!isSeen)
        } else if (attr == MailAttribute.Flagged) {
          expect(hasAttr).assertEqual(!isFlaged)
        }
      })

      const setSeen = m.setSeen(!isSeen)
      await setSeen
      expect(setSeen).assertPromiseIsResolved()
      const newIsSeen = await m.isSeen()
      expect(newIsSeen).assertEqual(!isSeen)

      const setFlag = m.setFlagged(!isFlaged)
      await setFlag
      expect(setFlag).assertPromiseIsResolved()
      const newIsFlagged = await m.isFlagged()
      expect(newIsFlagged).assertEqual(!isFlaged)
    })

    it('folder_action', 0, async () => {
      const newFolderName = "测试用例的文件夹"
      const root = await engine.getRootFolder()
      // 创建
      await root.createSubFolder(newFolderName)
      let customFolder = await root.getSubFolder(newFolderName)
      expect(customFolder).not().assertNull()
      // 重命名
      const rename = "改了名字的测试用例文件夹"
      await customFolder.renameFolder(rename)
      customFolder = await root.getSubFolder(rename)
      expect(customFolder).not().assertNull()
      try {
        await root.getSubFolder(newFolderName)
      } catch (e) {
        expect(e).not().assertNull()
      }
      // 删除
      await root.deleteSubFolder(rename)
      try {
        await root.getSubFolder(rename)
      } catch (e) {
        expect(e).not().assertNull()
      }
    })

    it('mail_move_and_delete', 0, async () => {
      const root = await engine.getRootFolder()
      const subFolders = await root.getSubFolders()
      const trash = subFolders.find(f => f.getType() == FolderType.trash)
      expect(trash).not().assertNull()
      if (!trash) {
        return
      }
      // Move
      const sent = await engine.getSent()
      let mailCount = await sent.getMailCount()
      let mails = await sent.getMailList(mailCount, null, {
        by: 'date', desc: true
      })
      let mail = mails[mailCount - 1]
      let mid = mail.getId()

      const subject = await mail.getSubject()
      const content = await mail.getHtml()
      const fromemail = (await mail.getFrom()).email
      const toemail = (await mail.getTo())[0].email

      const movePromise = mail.moveTo(trash)
      try {
        await movePromise
      } catch (e) {
        console.log(e)
      }

      expect(movePromise).assertPromiseIsResolved()
      try {
        await sent.getMail(mid)
      } catch (e) {
        expect(e).not().assertNull()
      }

      mailCount = await trash.getMailCount()
      mails = await trash.getMailList(mailCount, null, {
        by: 'date', desc: true
      })
      mail = mails[mailCount - 1]
      mid = mail.getId()
      const mFrom = await mail.getFrom()
      expect(mFrom.email).assertEqual(fromemail)
      const mTo = await mail.getTo()
      expect(mTo.length).assertEqual(1)
      expect(mTo[0].email).assertEqual(toemail)
      const mSubject = await mail.getSubject()
      expect(mSubject).assertEqual(subject)
      const mContent = await mail.getHtml()
      expect(mContent).assertEqual(content)
      // Delete
      await mail.delete()
      try {
        await trash.getMail(mid)
      } catch (e) {
        expect(e).not().assertNull()
      }
    })

    it('send_attachment_mail', 0, async () => {
      try {
        engine.on('new-mail', (folderFullName, mails) => {
          expect(mails.length).assertEqual(1)
        })
      } catch (e) {
      }

      const imgBase64 = "iVBORw0KGgoAAAANSUhEUgAAACwAAAAiCAYAAAAkjjtxAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAJkSURBVHgB7ZhLTBNRGIXPFLApQlPFYKA1YYFKDOJC0K2PlSw00S1G3ZBA0OJGXZiIiRvdKGokkYUaWRk1caM7deHGCBt1QxQfUd6PNDThTYZ7LrmkpQOdCXNLm8y3mLm3c6c9c+b8fydjQFDd0nMDMFvFMITsJGYYxtNvDw5eNvZf7LlrmlJsDmDe9Amx5zlsOFKK8u1bkG1Q06nDJQgG8sTMiPrENnSsJoSrZ3bh5bV98mC2QBOp6VZDBWp3F/OjUF7poca2scl57AgWoKZiKyg+XOJH9484ZhdMbAbFws3Wk2E015fDX+DDm8/jePFpFHNCj1Hd0m0mXhEX8YSBiTlcaO+V+0yyNxzA/cZKGYX49AI63g3h+YfhleNJggkXPonuEXu/nD96OyBOGkQmoGGMJuntn8Klx30phqUIVtDpphNlcvz+awy3X/3T5jZNYk7rlnOKro8j0qj49GLKWplhqy/5IjJMgVWRgMh2EY4f2Cbnv4dn4Ca1lUUyAlWRQhmBpo6fK3m1Yk2HFauv3s2IXDkdwdmjO+WYBl3v+pP2LqYVrEiMyEYLkibQVRYYufP6f1JhuSJY/ZAqSOaLuWbLcUJyJ5oVrv6V7tplzQxbQZEswGBhvuOebdVbo519jmvCkcOJOOnZ6XprRgQTOz3bTm/NmGCFVc8mdnurE1wRTPjQ1FxfJt1WDqoIRDt/OSqs9XBNMFnds+32Vie4KljB7sFb75arieRDA8yxLnzIMTzBuvEE68YTrBtPsG48wbqhYH1//O4TE4LNduQOzwxuxSPmPbE7hyx+oU1jvz+sa1sC/ZI2edXLe2YAAAAASUVORK5CYII="
      const filePath = "/data/storage/el2/base/files/sina.png"
      expect(getFileName(filePath)).assertEqual("sina.png")
      openFile(filePath, "")
      const file = await fs.open(filePath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
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

      await new Promise<void>((resolve) => {
        setTimeout(() => {
          resolve()
        }, 3000)
      })

      const sent = await engine.getSent()
      const mailCount = await sent.getMailCount()
      const mails = await sent.getMailList(mailCount, null, {
        by: 'date', desc: true
      })
      const mail = mails[mailCount - 1]

      const mailFrom = await mail.getFrom()
      expect(mailFrom.email).assertEqual(fromemail)
      const mailTo = await mail.getTo()
      expect(mailTo.length).assertEqual(1)
      expect(mailTo[0].email).assertEqual(toemail)
      const mailCc = await mail.getCc()
      expect(mailCc.length).assertEqual(0)
      const mailBcc = await mail.getBcc()
      expect(mailBcc.length).assertEqual(0)
      const mailSubjct = await mail.getSubject()
      expect(mailSubjct).assertEqual(subject)
      const mailContent = await mail.getHtml()
      expect(mailContent).assertContain(content)
      const plainText = await mail.getPlain()
      expect(plainText).assertEqual("")
      const date = await mail.getDate()
      expect(date).not().assertNull()
      const size = await mail.getSize()
      expect(size).assertLarger(0)
      const summary = await mail.getDigest(10)
      expect(summary).not().assertNull()

      const inlineImgs = await mail.getInlineImageInfoList()
      expect(inlineImgs.length).assertEqual(1)
      const attachments = await mail.getAttachmentInfoList()
      expect(attachments.length).assertEqual(1)

      const getAttachmentPromise = mail.getAttachment(0)
      await getAttachmentPromise
      expect(getAttachmentPromise).assertPromiseIsResolved()

      const getInlieImgPromise = mail.getInlineImage(0)
      await getInlieImgPromise
      expect(getInlieImgPromise).assertPromiseIsResolved()

      const m = mail as Mail
      const inbox = await engine.getInbox()
      const copyPromise = m.copyTo(inbox)
      await copyPromise
      expect(copyPromise).assertPromiseIsResolved()
    })

    it("get_folder_count", 0, async () => {
      const store = engine.getStore()
      let p = store.check()
      await p
      expect(p).assertPromiseIsResolved()

      const inbox = await engine.getFolder("INBOX")
      const mails = await inbox.getMailList(1)
      const mail = mails[0]
      await mail.setSeen(false)
      let unReadCount = await inbox.getUnreadMailCount()
      expect(unReadCount).assertLargerOrEqual(1)
      let recentCount = await inbox.getRecentCount()
      expect(recentCount).assertLargerOrEqual(1)

      try {
        await inbox.getMailList(1, "test")
      } catch (e) {
        expect(e).not().assertNull()
      }


      let mocker: MockKit = new MockKit();
      let mockFunc: Function = mocker.mockFunc(inbox, inbox.isOpen);
      when(mockFunc)().afterReturn(false);
      inbox.getMailIndex(mail.getId(), {
        by: 'date', desc: true
      }).then((value) => {
        expect(value).assertEqual(0)
      })
      mocker.clearAll()
    })

    it('eml_parser', 0, async () => {
      const eml = `Received: from aaa$607.net ( [192.168.200.90] ) by
 ajax-webmail-localhost.localdomain (Coremail) ; Fri, 1 Sep 2023 15:01:18
 +0800 (GMT+08:00)
X-Originating-IP: [192.168.200.90]
Date: Fri, 1 Sep 2023 15:01:18 +0800 (GMT+08:00)
X-CM-HeaderCharset: UTF-8
From: =?UTF-8?B?55So5oi3QQ==?= <aaa@607.net>
To: =?UTF-8?B?55So5oi3Rw==?= <ggg@607.net>
Subject: =?UTF-8?B?576k5Y+R5Y2V5pi+?=
X-Priority: 3
X-Mailer: Coremail Webmail Server Version 2023.2-cmXT6 build
 20230714(eb2b3919) Coremail_cmclient(4.0.2.721_win64.exe) Copyright (c)
 2002-2023 www.mailtech.cn mispb-7133344e-eee8-4549-8aa8-a20724ae1ca2-12.com
X-CM-CTRLMSGS: jWzZKg==
Content-Type: multipart/alternative;
       boundary="----=_Part_222_1714646033.1693551678428"
MIME-Version: 1.0
Message-ID: <4c6de7ef.41.18a4f8bd3dc.Coremail.aaa@607.net>
X-Coremail-Locale: zh_CN
X-CM-TRANSID:AQAAfwDnWpU+jPFk_BkAAA--.4W
X-CM-SenderInfo: hdddqlqqxo0vbw/1tbiAQABBmTwaSoAKQAEs8
X-Coremail-Antispam: 1Ur529EdanIXcx71UUUUU7IcSsGvfJ3GIAIbVAYFVCjjxCrMI
       AIbVAFxVCF77xC64kEw24lV2xY67C26IkvcIIF6IxKo4kEV4DvcSsGvfC2KfnxnUU==

------=_Part_222_1714646033.1693551678428
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: base64

CgoKCgoK576k5Y+R5Y2V5pi+
------=_Part_222_1714646033.1693551678428
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: base64

PHN0eWxlIGNsYXNzPSJrZS1zdHlsZSI+CltsaXN0LXN0eWxlLXR5cGVdIHtwYWRkaW5nLWxlZnQ6
MjBweDtsaXN0LXN0eWxlLXBvc2l0aW9uOmluc2lkZX0KW2xpc3Qtc3R5bGUtdHlwZV0gbGkge21h
cmdpbjowfQpbbGlzdC1zdHlsZS10eXBlXSBsaTpiZWZvcmUsIHNwYW4ua2UtbGlzdC1pdGVtLW1h
dHRlciB7Zm9udC1mYW1pbHk6InNhbnMgc2VyaWYiLHRhaG9tYSx2ZXJkYW5hLGhlbHZldGljYX0K
W2xpc3Qtc3R5bGUtdHlwZV0gbGkgcCxbbGlzdC1zdHlsZS10eXBlXSBsaSBoMSxbbGlzdC1zdHls
ZS10eXBlXSBsaSBoMixbbGlzdC1zdHlsZS10eXBlXSBsaSBoMyxbbGlzdC1zdHlsZS10eXBlXSBs
aSBoNCxbbGlzdC1zdHlsZS10eXBlXSBsaSBoNSxbbGlzdC1zdHlsZS10eXBlXSBsaSBkaXYsW2xp
c3Qtc3R5bGUtdHlwZV0gbGkgYmxvY2txdW90ZXtkaXNwbGF5OmlubGluZTt3b3JkLWJyZWFrOmJy
ZWFrLWFsbH0KW2xpc3Qtc3R5bGUtdHlwZV0gbGkgdGFibGUge2Rpc3BsYXk6aW5saW5lLWJsb2Nr
O3ZlcnRpY2FsLWFsaWduOnRvcH0KcHttYXJnaW46MH0KdGQge3dvcmQtYnJlYWs6IGJyZWFrLXdv
cmR9Ci5kZWZhdWx0LWZvbnQtMTY5MzU1MTc0MTQzOHsKZm9udC1zaXplOjEycHQ7CmZvbnQtZmFt
aWx5OiJNaWNyb3NvZnQgWWFIZWkgVUkiOwpjb2xvcjpyZ2IoMCwgMCwgMCk7CnRleHQtYWxpZ246
bGVmdDsKbGluZS1oZWlnaHQ6MS41Owp9Cjwvc3R5bGU+PGRpdiBjbGFzcz0iZGVmYXVsdC1mb250
LTE2OTM1NTE3NDE0MzgiPjxwPjxicj48L3A+PHA+PGJyPjwvcD48cD7nvqTlj5HljZXmmL48L3A+
PC9kaXY+
------=_Part_222_1714646033.1693551678428--
`.replace(new RegExp('\\r?\\n', 'g'), '\r\n')
      const mime = await engine.mimeParse(eml)
      expect(mime).not().assertNull()
    })

    it("save_draft", 0, async () => {
      const subject = "这是主题"
      const content = "来着测试用例的简单邮件内容"
      const fromemail = username
      const toemail = _toemail
      let _from: EmailAddress = {
        name: "", email: fromemail
      };
      let toList: EmailAddress[] = [{
        name: "", email: toemail
      }]
      let mail = await serializeMail(
        {
          from: _from,
          to: toList,
          cc: [],
          bcc: [],
          subject
        },
        new Map(),
        content,
        "",
        [],
        []
      );
      let folder = await engine.getDraft();
      let id = await folder.addMail(mail);
      expect(id).not().assertUndefined()
    })

    it("check_folder_exit", 0, async () => {
      let normalFolders: string[] = ['INBOX', 'Draft', 'Sent']
      const root = await engine.getRootFolder()
      normalFolders.map(async (itemFolder) => {
        try {
          await root.createSubFolder(itemFolder)
        } catch (e) {
          expect(e).not().assertNull()
        }
      })
    })

    it("important_folder_test", 0, async () => {
      let folderName = "$$important$$"
      const root = await engine.getRootFolder()
      try {
        await root.createSubFolder(folderName)
      } catch (e) {

      }
      let customFolder = await root.getSubFolder(folderName)
      expect(customFolder).not().assertNull()

      try {
        let mails = await customFolder.getMailList(1, null, {
          by: 'date', desc: true
        })
        expect(mails.length).assertEqual(0)
      } catch (e) {
      }

      let mocker: MockKit = new MockKit();
      let mockFunc: Function = mocker.mockFunc(engine.getStore(), engine.getStore().hasFeature);
      when(mockFunc)(ArgumentMatchers.any).afterReturn(true);

      try {
        let mails = await customFolder.getMailList(1, "test", {
          by: 'date', desc: true
        })
        expect(mails.length).assertEqual(0)
      } catch (e) {
      }
      mocker.clearAll()
    })
  })
}