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
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium'
import { delay, LRUCache } from '@coremail/mail_base'


export default function lruTest() {
  describe('lruTest', () => {
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
    it('lru_test', 0, async () => {
      let cache = new LRUCache<string>(v => v, 3, 100);
      cache.add("a");
      cache.add("b");
      cache.add("c");
      cache.add("d");
      expect(cache.get("a")).assertUndefined();
      expect(cache.get("b")).assertEqual("b");
      expect(cache.get("c")).assertEqual("c");
      expect(cache.get("d")).assertEqual("d");
      await delay(1000);
      expect(cache.get("b")).assertUndefined();
      expect(cache.get("c")).assertUndefined();
      expect(cache.get("d")).assertUndefined();
    })
    it('lru_test2', 0, async () => {
      let cache = new LRUCache<string>(v => v, 3, 100);
      cache.add("a");
      cache.add("b");
      cache.add("c");
      cache.add("d");
      // 读取之后节点要放到第一位
      expect(cache._cache[0]).assertEqual("d");
      cache.get("b");
      expect(cache._cache[0]).assertEqual("b");
    })

    it("lru_test3", 0, async () => {
      let cache = new LRUCache<string>(v => v, 3, 100);
      cache.clean()
      cache.add("a");
      expect(cache.has('a')).assertTrue()
      cache.clean()
      await delay(1000)
      expect(cache.has('a')).assertFalse()
    })
  })
}