# Standard Email Protocol SDK

Chinese document：[中文文档](https://gitee.com/openharmony-sig/mail_base/blob/master/README.md)

## Introduction

**mail_base** is a standard email protocol SDK specifically developed for the OpenHarmony system, implemented entirely in TypeScript. This repository contains the source code for the standard email protocol SDK as well as relevant usage instructions and documentation.

**The main features supported by the SDK are as follows**

1. Supports configuration and connection to standard protocol (IMAP, POP3, SMTP) servers.
2. Provides core functionalities such as receiving, sending, reading, and searching emails.
3. Enables folder management and operations.
4. Supports protocol extensions.
5. Facilitates secondary development of email clients.


## RleaseNote&ChangeLog

Click here to view the RleaseNote&ChangeLog：[RleaseNote&ChangeLog](https://gitee.com/openharmony-sig/mail_base/blob/master/lib/CHANGELOG.md)


## How to use the SDK

### Referencing

1. By ohpm

```bash
ohpm install @coremail/mail_base
```

2. By source code

Developers can clone the source code and import the code under the **mail_client_sdk** directory into their own projects for reference. The recommended development platform is Dev Eco


3. By har package

To use the .har package in your project, you need to introduce it into your engineering environment.


### Secondary Development

Please refer to Wiki for instructions on how to use the SDK.：[Wiki](https://gitee.com/openharmony-sig/mail_base/blob/master/lib/README.en.md)

## Constraints and Limitations

```
DevEco Studio version：4.1 Canary2(4.1.3.401)

SDK version：API11 Canary2(4.1.0.36)

OpenHarmony system version：2.1.3.5（Canary）
```


## Contribute Code

Issue link:[Issue](https://gitee.com/openharmony-sig/mail_base/issues)

PR link:[PR](https://gitee.com/openharmony-sig/mail_base/pulls) 


## Open Source License

```
Copyright 2023 Coremail论客

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
