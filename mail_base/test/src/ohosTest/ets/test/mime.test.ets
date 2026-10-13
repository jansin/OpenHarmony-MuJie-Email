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
import { afterAll, afterEach, beforeAll, beforeEach, DEFAULT, describe, expect, it } from '@ohos/hypium'

import buffer from '@ohos.buffer'
import {
  getMimePartName,
  getMimeParts,
  MimeMail,
  parseMime2,
  base64Decode
} from '@coremail/mail_base'

import type {
  MailStructure
} from '@coremail/mail_base'

const eml1 = `Received: from aaa$607.net ( [192.168.200.90] ) by
 ajax-webmail-localhost.localdomain (Coremail) ; Fri, 1 Sep 2023 13:41:19
 +0800 (GMT+08:00)
Date: Fri, 1 Sep 2023 13:41:19 +0800 (GMT+08:00)
Subject: 123
From: =?UTF-8?B?55So5oi3QQ==?= <aaa@607.net>
To: =?UTF-8?B?55So5oi3RA==?= <ddd@607.net>,
        =?UTF-8?B?6YOo6Zeo566h55CG5ZGYMDE=?= <dep01@607.net>,
        =?UTF-8?B?6YOo6Zeo566h55CG5ZGYMDI=?= <dep02@607.net>,
        =?UTF-8?B?55So5oi3RQ==?= <eee@607.net>,
        =?UTF-8?B?55So5oi3Rg==?= <fff@607.net>
Cc: =?UTF-8?B?55So5oi3Rw==?= <ggg@607.net>,
        =?UTF-8?B?6Z2Z5oCB5YiX6KGoMDHnlKjmiLfkuIA=?= <j01@607.net>,
        =?UTF-8?B?6Z2Z5oCB5YiX6KGoMDHnlKjmiLfkuow=?= <j02@607.net>
Message-ID: <1d1f2d9a.2d.18a4f4299a3.Coremail.aaa@607.net>
X-Mailer: Coremail Webmail Server Version 2023.2-cmXT6 build
 20230714(eb2b3919)
 mispb-7133344e-eee8-4549-8aa8-a20724ae1ca2-12.com
X-CMClient-Version: Coremail cmclient(4.0.2.721 win64.exe)
MIME-Version: 1.0
X-Priority: 3
X-Coremail-Locale: zh_CN
X-CM-HeaderCharset: UTF-8
References: <64f179c8.2.ikb0HgDJtPijkb0H@aaa>
        <64f1798b.1.Djb0HgDJtPiEjb0H@aaa>
x-cm-smime: signed,cmsm
x-cm-smime-version: cmsm openssl OpenSSL 3.1.1 30 May 2023 v1
Content-Type: text/plain
X-Originating-IP: [192.168.200.90]
X-CM-TRANSID:AQAAfwBXy5WAefFktRkAAA--.551W
X-CM-SenderInfo: hdddqlqqxo0vbw/1tbiAQABBmTwaSoAGgAAsL
X-Coremail-Antispam: 1Ur529EdanIXcx71UUUUU7IcSsGvfJ3GIAIbVAYFVCjjxCrMI
        AIbVAFxVCF77xC64kEw24lV2xY67C26IkvcIIF6IxKo4kEV4DvcSsGvfC2KfnxnUU==

This is a multipart message in MIME format.`.replace(new RegExp('\\r?\\n', 'g'), '\r\n')

const eml2 = `Received: from aaa$607.net ( [192.168.200.90] ) by
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

const eml3 = `Received: from emailgateway.icoremail.net (unknown [10.11.150.9])
	by mailtech_rd (Coremail) with SMTP id AgIMCgC3jNbaHLNlAR0AAA--.669S2;
	Fri, 26 Jan 2024 10:45:46 +0800 (CST)
Received: from mailtech.cn (unknown [61.144.145.228])
	by gateway (Coremail) with SMTP id AAAAAADHfjCxHLNlwakFAA--.8581S3;
	Fri, 26 Jan 2024 10:45:05 +0800 (CST)
Received: from mtpeng$coremail.cn ( [61.144.145.228] ) by
 ajax-webmail-mailtech (Coremail) ; Fri, 26 Jan 2024 10:45:05 +0800 (CST)
X-Originating-IP: [61.144.145.228]
Date: Fri, 26 Jan 2024 10:45:05 +0800 (CST)
X-CM-HeaderCharset: UTF-8
From: =?UTF-8?B?5b2t576O5am3?= <mtpeng@coremail.cn>
To: =?UTF-8?B?5ZOI5ZOI?= <mtpeng@coremail.cn>
Subject: =?UTF-8?B?5rWL6K+V6ZmE5Lu26YKu5Lu2?=
X-Priority: 3
X-Mailer: Coremail Webmail Server Version 2023.4-cmXT6 build
 20231205(37e20f0e) Coremail_cmclient(4.0.3.864_win64.exe) Copyright (c)
 2002-2024 www.mailtech.cn
 mispb-8dfce572-2f24-404d-b59d-0dd2e304114c-icoremail.cn
X-CM-CTRLMSGS: c0wWUg==
Message-ID: <65b31cb1.2.5c9CbYDPhTi6c9Cb@coremail.cn>
Content-Type: multipart/mixed;
	boundary="----=_Part_331_683877808.1706237105027"
MIME-Version: 1.0
X-Coremail-Locale: zh_CN
X-CM-DELIVERINFO: =?B?aI6ekr5oA/JzIL8gKj09+4xbMBEgbvGlvkS/Frf6cyLj/XxgFjO6WKPvoboIS6sKSe
	EP49CkQyr5OYunWocpKsOnZUH92oOujP/yZDoOjiJUKi9vNctIvQElvLQlP6wU9zz9YBMw
	JgSOdSm908R3ySvY1NKDq2sBld64qXBWzvM51e8b
X-CM-TRANSID:AgIMCgC3jNbaHLNlAR0AAA--.669S2
Authentication-Results: mailtech_rd; spf=neutral smtp.mail=mtpeng@core
	mail.cn;
X-CM-SenderInfo: ppwsv0nj6f02phpdxzgofq/1tbiAQcJEGWyZGQDygAFsE
X-Coremail-Antispam: 1UD129KBjDUn29KB7ZKAUJUUUUU529EdanIXcx71UUUUU7v73
	VFW2AGmfu7bjvjm3AaLaJ3UjIYCTnIWjp_UUUog7kC6x804xWl1xkIjI8I6I8E6xAIw20E
	Y4v20xvaj40_Wr0E3s1l8cAvFVAK0II2c7xJM28CjxkF64kEwVA0rcxSw2x7M28EF7xvwV
	C0I7IYx2IY67AKxVWDJVCq3wA2z4x0Y4vE2Ix0cI8IcVCY1x0267AKxVWxJr0_GcWl84AC
	jcxK6I8E87Iv67AKxVW0oVCq3wA2z4x0Y4vEx4A2jsIEc7CjxVAFwI0_GcCE3s1le2I262
	IYc4CY6c8Ij28IcVAaY2xG8wASzI0EjI02j7AqF2xKxwAqjxCEc2xF0cIa020Ex4CE44I2
	7wAq07x20xvEnxkEFVAI27IIrVCY07AIYIkIcwAq07x20xvEIxAIcVA0r40Er4AFj41l5I
	8CrVACY4xI64kE6c02F40Ex7xfMcIj64x0Y40En7xvr7AKxVWUJVW8JwAv7VCjz48v1sIE
	Y20_XF4lYx0Ec7CjxVAajcxG14v26r4j6F4UMcvjeVCFs4IE7xkEbVWUJVW8JwACjcxG0x
	vY0x0EwIxGrwACjI8F5VA0II8E6IAqYI8I648v4I1lFcxC0VAYjxAxZF0Ew4CEw7xC0wAC
	Y4xI67k04243AVC20s07MxkIecxEwVCm-wCF04k20xvY0x0EwIxGrwCF04k20xvE0xIIj4
	0Ec7CjxwCF04k20xvE74AGY7Cv6cx26ryxMxC20s026xCaFVCjc4AY6r1j6r4UMI8I3I0E
	5I8CrVAFwI0_Jr0_Jr4lx2IqxVCjr7xvwVAFwI0_JrI_JrWlx4CE17CEb7AF67AKxVWUJV
	WUXwCIc40Y0x0EwIxGrwCI42IY6xIIjxv20xvE14v26r1j6r1xMIIF0xvE2Ix0cI8IcVCY
	1x0267AKxVWUJVW8JwCI42IY6xAIw20EY4v20xvaj40_Jr0_JF4lIxAIcVC2z280aVAFwI
	0_Jr0_Gr1lIxAIcVC2z280aVCY1x0267AKxVWUJVW8JbIYCTnIWIevJa73UjIFyTuYvjxU
	2hiSUUUUU

------=_Part_331_683877808.1706237105027
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: base64

57qv5paH5pys6YKu5Lu25YaF5a65
------=_Part_331_683877808.1706237105027
Content-Type: text/plain;
	x-cm-attr="attId:_CMClient@65b31c96.1.3c9CbYDPhTi4c9Cb";
	name="=?UTF-8?Q?=E6=96=87=E6=9C=AC.txt?=";
 x-cm-securityLevel=0
Content-Transfer-Encoding: base64
Content-Disposition: attachment;
 filename="=?UTF-8?Q?=E6=96=87=E6=9C=AC.txt?="

5paH5pys
------=_Part_331_683877808.1706237105027--
`.replace(new RegExp('\\r?\\n', 'g'), '\r\n')


export default function mimeTest() {
  describe('parseMime2_test', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // setBoundaryPattern("1234567890");
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
    it("mime_parse_header", 0, async () => {
      const mime = await parseMime2(eml1);
      expect(mime.headers.size).assertEqual(21);
    });
    it("mime_headers_from", 0, async () => {
      const mime = await parseMime2(eml1);
      expect(mime.headers.get("from")).assertEqual("用户A <aaa@607.net>");
    });
    it("mime_headers_to", 0, async () => {
      const mime = await parseMime2(eml1);
      expect(mime.headers.get("to")).assertEqual(
        "用户D <ddd@607.net>,       部门管理员01 <dep01@607.net>,       部门管理员02 <dep02@607.net>,       用户E <eee@607.net>,       用户F <fff@607.net>"
      );
    });
    // it("mime_headers_body", 0, async () => {
    //   const mime = await parseMime2(eml1);
    //   let data = await mime.body.readAll()
    //   expect(data).assertEqual("This is a multipart message in MIME format.");
    // });
    it("mime_headers_subject", 0, async () => {
      const mime = await parseMime2(eml2);
      expect(mime.headers.get("subject")).assertEqual("群发单显");
    });
  })

  describe('mime_mail_test', () => {
    let mimeMail: MimeMail;
    beforeAll(async () => {
      let mime = await parseMime2(eml3);
      mimeMail = new MimeMail(mime);
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

    })
    it("mime_mail_plain", DEFAULT, async () => {
      const plain = mimeMail.getPlain()
      let text = await plain?.readAll()
      expect(buffer.from(base64Decode(text)).toString()).assertEqual('纯文本邮件内容')
    })
    it("mime_mail_PartId", DEFAULT, () => {
      let id = mimeMail.getPlainPartId()
      expect(id).assertEqual('1')
    })
    it("mime_mail_HtmlPartId", DEFAULT, () => {
      let id = mimeMail.getHtmlPartId()
      expect(id).assertUndefined()
    })
    it("mime_mail_html", DEFAULT, async () => {
      let htmlBuffer = mimeMail.getHtml()
      if (htmlBuffer) {
        let text = await htmlBuffer.readAll()
        expect(text).assertEqual("")
      }
    })
    it("mime_mail_envelope", DEFAULT, () => {
      let data = mimeMail.getEnvelope()
      expect(data.to[0].email).assertContain('mtpeng@coremail.cn')
    })
    it("mime_mail_attachment", DEFAULT, () => {
      let data = mimeMail.getAttachments()
      expect(data.length).assertEqual(1)
    })
    it("mime_mail_inlineImg", DEFAULT, () => {
      let data = mimeMail.getInlineImages()
      expect(data.length).assertEqual(0)
    })
  })

  describe('mime_part_test', () => {
    let mime: MailStructure;
    beforeAll(() => {
      mime = {
        contentType: {
          type: "application", subType: "vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          params: {
            "name": "项目管理跟进表.xlsx"
          }
        },
        children: [],
        partId: "2",
        size: 506378
      }
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

    it("mime_part_name_content", 0, () => {
      let name = getMimePartName(mime)
      expect(name).assertEqual("项目管理跟进表.xlsx")
    })

    it("mime_part_name", 0, () => {
      mime.disposition = {
        type: "attachment",
        params: {
          "filename": "移动端-项目管理跟进表.xlsx"
        }
      }
      let name = getMimePartName(mime)
      expect(name).assertEqual("移动端-项目管理跟进表.xlsx")
    })

    it("mime_get_parts_filter", 0, () => {
      let result = getMimeParts(mime, (mime) => {
        return mime.children.length > 0
      })
      expect(result.length).assertEqual(0)
    })
  })
}
