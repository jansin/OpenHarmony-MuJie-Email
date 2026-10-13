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
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect, DEFAULT } from '@ohos/hypium'
import buffer from '@ohos.buffer'
import { getFileName, guessContentType, MemBuffer } from '@coremail/mail_base'

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
`

export default function file_streamTest() {
  describe('file_streamTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
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
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    })

    it("guessContentType", DEFAULT, () => {
      expect(guessContentType("online.exe")).assertEqual("application/x-msdownload");
      expect(guessContentType("麦当劳第4季度营销优惠.xls")).assertEqual("application/vnd.ms-excel");
      expect(guessContentType("just on last dance.mp3")).assertEqual("audio/mpeg");
      expect(guessContentType("idnotknow.rtf")).assertEqual("application/octet-stream");
    })

    it("getFileName", DEFAULT, () => {
      expect(getFileName("/data/app/el2/100/base/cn.coremail.mailclient/files/mails/1702869956/attachment/-737352427.xlsx")).assertEqual("-737352427.xlsx");
      expect(getFileName("file:///data/app/el2/100/base/cn.coremail.mailclient/files/mails/1702869956/attachment/执行文件")).assertEqual("执行文件");
      expect(getFileName("人员名单")).assertEqual("人员名单");
    })

    // 一次性写入数据
    it("MemBuffer_OneTime_Write", DEFAULT, async () => {
      const membuffer = new MemBuffer();
      await membuffer.feed(eml);
      await membuffer.end(null);
      const s = await membuffer.readAll();
      expect(await membuffer.getSize()).assertEqual(eml.length);
      expect(s).assertEqual(eml);

      const raw = await membuffer.readAllRaw();
      expect(buffer.from(raw.buffer).toString()).assertEqual(eml);
    })

  })
}