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
import commonTest from './common.test';
import encodingTest from './encoding.test';
import file_streamTest from './file_stream.test';
import imap_storeTest from './imap_store.test';
import lruTest from './lru.test';
import mimeTest from './mime.test';
import pop3_storeTest from './pop3_store.test';
import imap_mailAttrTest from './imap_mail_attr.test';

export default function testsuite() {
  commonTest();
  encodingTest();
  file_streamTest();
  lruTest();
  mimeTest();
  imap_storeTest();
  pop3_storeTest();
  imap_mailAttrTest();
}