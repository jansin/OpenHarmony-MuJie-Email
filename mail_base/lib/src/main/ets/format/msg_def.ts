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

// 只有STRING和UNICODE类型的字段才会被解析
export enum FieldType {
  NULL = 0x0001,
  UNKNOWN = 0x0001,
  INT16 = 0x0002,
  INT32 = 0x0003,
  FLOAT32 = 0x0004,
  FLOAT64 = 0x0005,
  CURRENCY = 0x0006,
  FLOATINGTIME = 0x0007,
  ERRORCODE = 0x000a,
  BOOLEAN = 0x000b,
  OBJECT = 0x000d,
  INT64 = 0x0014,
  STRING = 0x001e,
  UNICODE = 0x001f,
  TIME = 0x0040,
  GUID = 0x0048,
  BINARY = 0x0102,
}
