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
/**
 * 文件名后缀与MIME对照表
 */
export const ExtVsMimeDict:Record<string, string> = {
  "doc": "application/msword",
  "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "xls": "application/vnd.ms-excel",
  "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "ppt": "application/vnd.ms-powerpoint",
  "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "aif": "audio/x-aiff",
  "aifc": "audio/x-aiff",
  "aiff": "audio/x-aiff",
  "asf": "video/x-ms-asf",
  "asr": "video/x-ms-asf",
  "asx": "video/x-ms-asf",
  "au": "audio/basic",
  "avi": "video/x-msvideo",
  "bas": "text/plain",
  "bmp": "image/bmp",
  "c": "text/plain",
  "eml": "message/rfc822",
  "gif": "image/gif",
  "htm": "text/html",
  "html": "text/html",
  "jpe": "image/jpeg",
  "jpeg": "image/jpeg",
  "jpg": "image/jpeg",
  "png": "image/png",
  "mov": "video/quicktime",
  "movie": "video/x-sgi-movie",
  "mp2": "video/mpeg",
  "mp3": "audio/mpeg",
  "mp4": "audio/mpeg",
  "mpa": "video/mpeg",
  "mpe": "video/mpeg",
  "mpeg": "video/mpeg",
  "mpg": "video/mpeg",
  "pdf": "application/pdf",
  "svg": "image/svg+xml",
  "tgz": "application/x-compressed",
  "tif": "image/tiff",
  "tiff": "image/tiff",
  "txt": "text/plain",
  "wav": "audio/x-wav",
  "xla": "application/vnd.ms-excel",
  "xlc": "application/vnd.ms-excel",
  "xlm": "application/vnd.ms-excel",
  "xlt": "application/vnd.ms-excel",
  "xlw": "application/vnd.ms-excel",
  "z": "application/x-compress",
  "zip": "application/zip",
}