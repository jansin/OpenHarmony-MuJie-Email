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
/* istanbul ignore next */
import {
  describe,
  beforeAll,
  beforeEach,
  afterEach,
  afterAll,
  it,
  expect
} from '@ohos/hypium'
import buffer from '@ohos.buffer'
import {   base64Decode,
  base64DecodeStream,
  base64Encode,
  decodeCharset,
  decodeRFC2047,
  decodeUtf7,
  encodeRFC2047,
  encodeUtf7,
  getEncodeMethod,
  qpDecode,
  qpEncode } from '@coremail/mail_base'


const poet1 = `Whose woods these are I think I know.
His house is in the village though;
He will not see me stopping here
To watch his woods fill up with snow.

My little horse must think it queer
To stop without a farmhouse near
Between the woods and frozen lake
The darkest evening of the year.

He gives his harness bells a shake
To ask if there is some mistake.
The only other sound’s the sweep
Of easy wind and downy flake.

The woods are lovely, dark and deep,
But I have promises to keep,
And miles to go before I sleep,
And miles to go before I sleep.`

const poet1base64 = `V2hvc2Ugd29vZHMgdGhlc2UgYXJlIEkgdGhpbmsgSSBrbm93LiAgIApIaXMgaG91c2UgaXMgaW4g
dGhlIHZpbGxhZ2UgdGhvdWdoOyAgIApIZSB3aWxsIG5vdCBzZWUgbWUgc3RvcHBpbmcgaGVyZSAg
IApUbyB3YXRjaCBoaXMgd29vZHMgZmlsbCB1cCB3aXRoIHNub3cuICAgCgpNeSBsaXR0bGUgaG9y
c2UgbXVzdCB0aGluayBpdCBxdWVlciAgIApUbyBzdG9wIHdpdGhvdXQgYSBmYXJtaG91c2UgbmVh
ciAgIApCZXR3ZWVuIHRoZSB3b29kcyBhbmQgZnJvemVuIGxha2UgICAKVGhlIGRhcmtlc3QgZXZl
bmluZyBvZiB0aGUgeWVhci4gICAKCkhlIGdpdmVzIGhpcyBoYXJuZXNzIGJlbGxzIGEgc2hha2Ug
ICAKVG8gYXNrIGlmIHRoZXJlIGlzIHNvbWUgbWlzdGFrZS4gICAKVGhlIG9ubHkgb3RoZXIgc291
bmTigJlzIHRoZSBzd2VlcCAgIApPZiBlYXN5IHdpbmQgYW5kIGRvd255IGZsYWtlLiAgIAoKVGhl
IHdvb2RzIGFyZSBsb3ZlbHksIGRhcmsgYW5kIGRlZXAsICAgCkJ1dCBJIGhhdmUgcHJvbWlzZXMg
dG8ga2VlcCwgICAKQW5kIG1pbGVzIHRvIGdvIGJlZm9yZSBJIHNsZWVwLCAgIApBbmQgbWlsZXMg
dG8gZ28gYmVmb3JlIEkgc2xlZXAu`

export default function encodingTest() {
  describe('encodingTest', () => {
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
    it("charset_utf_8", 0, async () => {
      const s = new Uint8Array([82, 101, 58, 116, 101, 115, 116]);
      const t = "Re:test"
      // Warn: util.TextDecoder存在问题
      expect(decodeCharset(s, 'utf-8')).assertEqual(t);
      // expect(encodeUtf8(t)).assertEqual()
    });

    it("utf_7", 0, async () => {
      const s = '"INBOX/我的收件箱 啊"';
      const t = '"INBOX/&YhF2hGU2TvZ7sQ- &VUo-"';
      expect(encodeUtf7(s)).assertEqual(t);
      expect(decodeUtf7(t)).assertEqual(s);
    });

    it("rfc2047", 0, async () => {
      const s = "=?UTF-8?Q?Re:testmail2?=";
      const t = "Re:testmail2";
      // Warn: util.TextDecoder存在问题
      expect(decodeRFC2047(s)).assertEqual(t);
      // expect(encodeRFC2047(t)).assertEqual(s);
    });

    it("base64Encode", 0, async () => {
      let s = "这是主题";
      let t = "6L+Z5piv5Li76aKY";
      expect(base64Encode(s)).assertEqual(t);
      s = "主题 /主题加了空格和特殊字符";
      t = "5Li76aKYIC/kuLvpopjliqDkuobnqbrmoLzlkoznibnmrorlrZfnrKY=";
      expect(base64Encode(s)).assertEqual(t);
    })

    it("base64Decode", 0, () => {
      const s = "5Li76aKYIC/kuLvpopjliqDkuobnqbrmoLzlkoznibnmrorlrZfnrKY=";
      const t = "主题 /主题加了空格和特殊字符";
      expect(buffer.from(base64Decode(s)).toString()).assertEqual(t);
    })

    it("qpEncode", 0, () => {
      let s = "Hello, world!";
      let t = "Hello,=20world!"
      expect(qpEncode(s)).assertEqual(t);
      s = "广州总部--2024年夜饭通知";
      t = "=E5=B9=BF=E5=B7=9E=E6=80=BB=E9=83=A8--2024=E5=B9=B4=E5=A4=9C=E9=A5=AD=E9=80=9A=E7=9F=A5"
      expect(qpEncode(s, 90)).assertEqual(t)
    })

    it("qpDecode", 0, () => {
      const s = "=E5=B9=BF=E5=B7=9E=E6=80=BB=E9=83=A8--2024=E5=B9=B4=E5=A4=9C=E9=A5=AD=E9=80=9A=E7=9F=A5";
      const t = "广州总部--2024年夜饭通知";
      expect(buffer.from(qpDecode(s)).toString()).assertEqual(t)
    })

    // it("getEncodeMethod", 0, () => {
    //   // Warn: util.TextDecoder存在问题
    //   let s = base64Encode("这是主题");
    //   expect(getEncodeMethod(s)).assertEqual('B');
    //   s = qpEncode("这是主题");
    //   expect(getEncodeMethod(s)).assertEqual('Q');
    // })

    it("encodeRFC2047", 0, () => {
      let s = "这是主题";
      expect(encodeRFC2047(s)).assertEqual("=?UTF-8?B?6L+Z5piv5Li76aKY?=");
      s = "主题 内容、/收件人,te特";
      expect(encodeRFC2047(s)).assertEqual("=?UTF-8?B?5Li76aKYIOWGheWuueOAgS/mlLbku7bkurosdGXnibk=?=");
    })

    it("decodeRFC2047", 0, () => {
      const s = "=?UTF-8?B?5Li76aKYIOWGheWuueOAgS/mlLbku7bkurosdGXnibk=?=";
      // Warn: util.TextDecoder存在问题
      expect(decodeRFC2047(s)).assertEqual("主题 内容、/收件人,te特");
    })

    it("encodeUtf7", 0, () => {
      const s = "这是主题+内容";
      expect(encodeUtf7(s)).assertEqual("&j9lmL047mJg-+&UYVbuQ-");
    })

    it("decodeUtf7", 0, () => {
      const s = "&j9lmL047mJg-+&UYVbuQ-";
      expect(decodeUtf7(s)).assertEqual("这是主题+内容");
    })

    // it('base64', 0, async () => {
    //   // expect(base64Decode(poet1base64)).assertEqual(poet1);
    //   const buffer = createBuffer({});
    //   for (let i = 0; i < poet1base64.length; i += 25) {
    //     const chunk = poet1base64.substring(i, i + 25);
    //     await buffer.feed(chunk);
    //   }
    //   await buffer.end();
    //   const r = base64DecodeStream(buffer);
    //   let res = ""
    //   for await (const chunk of r) {
    //     res += Array.from(chunk.values()).map(v => String.fromCharCode()).join("")
    //   }
    //   expect(res).assertEqual(poet1);
    //   // expect(base64Encode(poet1)).assertEqual(poet1base64);
    // })
  })
}
