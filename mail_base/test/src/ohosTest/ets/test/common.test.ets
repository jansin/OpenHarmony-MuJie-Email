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
import { assert, delay, isDigit, wrapCallback, parseDateString } from '@coremail/mail_base'

export default function commonTest() {
  describe('commonTest', () => {
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

    it('common_delay', 0, () => {
      let p = delay(0)
      setTimeout(() => {
        expect(p).assertPromiseIsResolved()
      })
    })

    it("common_assert_test", DEFAULT, () => {
      let action = false
      let message = "test error"
      expect(() => {
        assert(action, message)
      }).assertThrowError(message)
    })

    it("common_digit_test", 0, () => {
      let a = "aa"
      expect(isDigit(a)).assertFalse()
      let b = "22"
      expect(isDigit(b)).assertTrue()
    })

    it("common_wrapCallback", DEFAULT, async () => {
      let p = Promise.resolve()
      await wrapCallback(p)
      expect(p).assertPromiseIsResolved()
      let back = () => {
      }
      let reject = Promise.reject()
      await wrapCallback(reject, back)
      expect(reject).assertPromiseIsRejected()
    })

    it("date_parse", 0, () => {
      let date = parseDateString("Sun Jan 28 2024 20:00:00 CDT")
      expect(date).not().assertContain('CDT')
      let day = parseDateString('Mon Jan 29 2024 10:00:00')
      expect(day).not().assertNull()
    })
  })
}