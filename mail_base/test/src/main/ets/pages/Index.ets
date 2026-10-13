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

import { ImapStore } from "@coremail/mail_base"

@Entry
@Component
struct Index {
  @State message: string = '';
  @State email: string = 'fff@607.net'
  @State pass: string = '123'
  @State host: string = '172.16.10.110'
  @State port: string = '143'
  @State @Watch("onProtocol") isSSL: boolean = false
  @State @Watch("onProtocol") protocol: string = "IMAP"

  async testConnect() {
    const store = new ImapStore();
    store.setProperties({
      imap: {
        host: this.host,
        port: parseInt(this.port),
        secure: this.isSSL
      },
      userInfo: {
        username: this.email,
        password: this.pass
      },
      smtp: {
        host: '',
        port: 1,
        secure: false
      }
    })
    store.check().then(() => {
      this.message = '连接成功'
    }).catch(() => {
      this.message = '连接失败'
    })
  }

  onProtocol() {
    if (this.protocol == 'IMAP') {
      this.port = this.isSSL ? '993' : '143';
    } else if (this.protocol == 'POP3') {
      this.port = this.isSSL ? '995': '110'
    } else if (this.protocol == 'SMTP') {
      this.port = this.isSSL ? '465' : '25'
    }
  }

  build() {
    Row() {
      Column() {
        Row() {
          Select([
            { value: 'IMAP' },
            { value: 'POP3' },
            { value: 'SMTP' },
          ])
            .selected(0)
            .value($$this.protocol)
          Checkbox({ name: "SSL" })
            .select($$this.isSSL)
        }
        .width('100%')
        TextInput({
          placeholder: "请输入邮箱地址",
          text: $$this.email
        })
        TextInput({
          placeholder: "请输入邮箱密码",
          text: $$this.pass
        })
          .type(InputType.Password)
        TextInput({
          placeholder: "请输入服务器",
          text: $$this.host
        })
        TextInput({
          placeholder: "请输入端口",
          text: $$this.port
        })
        Button("确定")
          .onClick((event: ClickEvent) => {
            this.message = '';
            this.testConnect();
          })
        Text(this.message)
      }
      .width('30%')
    }
    .height('100%')
  }
}