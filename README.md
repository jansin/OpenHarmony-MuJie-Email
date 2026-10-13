# 沐界邮箱 MuJieEmail
沐界邮箱（MuJieEmail）是一款基于 **ArkTS / ArkUI** 与 **Stage 模型** 开发的 OpenHarmony / HarmonyOS 原生邮件客户端，支持 **IMAP / POP3 / SMTP** 三大协议，并预置了 12 家主流邮箱服务商的服务器配置。

| 项目 | 内容 |
| --- | --- |
| bundleName | `com.jason.email` |
| 应用名称 | 沐界邮箱（`AppScope/resources/base/element/string.json`） |
| 版本 | versionName `1.0.0`，versionCode `1000000`（`AppScope/app.json5`） |
| 开发语言 | ArkTS（`.ets`）/ ArkUI 声明式 UI |
| 目标平台 | HarmonyOS（`runtimeOS: "HarmonyOS"`），设备类型 `phone`、`tablet` |
| compatibleSdkVersion | `5.0.0(12)` |
| targetSdkVersion | `6.0.2(22)` |
| 开源协议 | Apache License 2.0 |

> 项目当前处于开发阶段，功能与界面仍在持续演进。

---
## 一、项目简介
沐界邮箱是一个**纯端侧**的轻量邮件客户端：直接与邮件服务商的 IMAP / POP3 / SMTP 服务器交互，不经过第三方中转服务器。

- **多邮箱聚合**：同时管理 QQ、163、Gmail、Outlook 等账号并快速切换；账号数大于 1 时提供"统一收件箱"。
- **国内邮箱授权码登录**：把"密码登录"与"授权码登录"拆为两种方式，内置授权码获取指引。
- **原生体验与深色模式**：ArkUI 原生组件构建界面，支持深色模式与全局主题色切换。

> **关于 `FEATURES.md`**：仓库内含一份 `FEATURES.md`（功能清单与完善计划），但其内容与现有代码存在多处不一致（例如记录 POP3 收件已修复、富文本编辑器待实现、签名可在设置页编辑等，均与当前源码不符）。因此本文档**不以其为事实依据**，全部结论以当前源码为准。

---
## 二、功能特性
以下功能均对应仓库中真实存在的源码实现。

### 1. 邮件协议（基于内置的 `mail_base` SDK）
- **IMAP**：文件夹列表、按文件夹取邮件、按 `messageId` 取单封邮件、信封、正文（纯文本与 HTML）、附件与内联图片信息。
- IMAP 另支持已读与星标标记、删除、跨文件夹移动（归档）。
- **POP3**：`AccountProtocol.POP3` 为可选值，收信统一经 `mail_base` 的 `Pop3Store`。
- POP3 **未做专项适配**，当前版本实际可用性（待补充）。
- **SMTP**：经 SDK 的 `ITransport.sendMail()` 发送，支持收件人 / 抄送 / 密送、主题与正文。
- 协议细节（MIME、MSG / RTF 解析等）由 `mail_base` 提供，见第九章；`IMAP` 为推荐接收协议。

### 2. 预置邮箱服务商（12 家）
`common/Constants.ets` 硬编码了 12 家服务商：Gmail、Outlook、QQ 邮箱、163、126、188、新浪、Foxmail、139、搜狐、阿里云、TOM。

- IMAP 均为 `993 / SSL`，POP3 均为 `995 / SSL`。
- SMTP：Gmail、Outlook、QQ、Foxmail 为 `587 / TLS`，其余为 `465 / SSL`。
- 域名识别见 `Utils.detectProvider()`：`yeah.net` → 163，`vip.qq.com` / `foxmail.com` → QQ，`hotmail.com` / `live.com` → Outlook。
- 识别不到时返回 `custom`，默认仍用 IMAP `993 / SSL` 与 SMTP `587 / TLS`。

### 3. 账号与文件夹管理
- 账号添加、编辑、删除（`AccountList.ets` / `AccountConfig.ets`），删除前有二次确认。
- 可设为默认账号并在首页"我的"标签页点击切换。
- 输入邮箱地址自动探测服务商并回填服务器信息，也可手动配置。
- 内置 6 类标准文件夹（收件箱、已发送、草稿箱、垃圾箱、垃圾邮件、归档），首次进入自动创建本地记录。
- IMAP 账号进入首页后延迟 300ms 触发一次后台文件夹同步并刷新未读数。
- 未读角标展示在文件夹行与底部"收件箱"标签。

### 4. 邮件列表与阅读
- 默认每页 50 封；下拉或手动刷新会拉取当前文件夹最新 50 封，并与本地缓存合并去重。
- 会话视图：按主题聚合（去掉 `Re:` / `Fwd:` / `回复:` / `转发:` 前缀），可展开 / 折叠。
- 支持多选批量删除。
- 列表与详情页均可切换星标与已读；提供"只看未读"开关。
- 侧滑操作按文件夹区分：非垃圾箱为「归档」「删除」（移入垃圾箱），垃圾箱为「恢复」「彻底删除本地记录」。
- 正文优先经 ArkWeb 的 `loadData` 渲染本地拼装 HTML，为空、超长或需纯文本回退时改用纯文本。
- 内联图片：把 HTML 中的 `cid:` 引用替换为 `data:` URL。

### 5. 写邮件
- 新建、回复、回复全部、转发（`ComposeEmail.ets` 按路由参数 `mode` 区分）。
- 收件人 / 抄送 / 密送可按需添加；正文使用 `TextArea` 纯文本编辑器（**非富文本编辑器**）。
- 账号数大于 1 时可切换发件账号；账号有 `signature` 字段时，正文末尾自动追加签名。
- 可保存本地草稿；经 `picker.DocumentViewPicker()` 选取附件，可移除单个附件。
- 未保存内容离开时会弹出"放弃编辑？"确认框；回复 / 转发以 `RichText` 展示引用原文。

### 6. 搜索、附件与过滤规则
- **搜索**：经 `MailEngine.search(...)` 执行**服务端 IMAP 搜索**，最多返回 50 封；文件夹内搜索会再按 `folderId` 过滤。
- **附件**：写信时可选取附件；详情页"下载"写入 `context.filesDir + '/downloads/'`。
- **过滤规则**：`FilterRules.ets` 支持规则增删与启用 / 停用，收信时逐条应用。
- 条件为发件人、收件人、主题、正文（多条为"与"）；动作为移动、标记已读、标记星标、删除、归档。

### 7. 主题、设置与工程化能力
- **设置页**：深色模式、自动同步间隔（5–60 分钟，步长 5，默认 15）、新邮件通知开关（默认开）、"清空缓存"。
- **深色模式**：持久化在 `AppSettings / isDarkMode` 并经 `AppStorage` 全局广播；`Theme.ets` 定义明 / 暗两套色板。
- 应用颜色模式交还系统控制，状态栏文字颜色随明暗主题同步调整。
- **缓存与备份**：清空缓存删除 `filesDir/downloads/` 与 `cacheDir` 下文件；`EntryBackupAbility` 注册 `type: "backup"`。
- **日志**：`LogUtil.ets` 基于 `hilog`，Tag 前缀固定为 `MuJieEmail`，支持 DEBUG / INFO / WARN / ERROR 四级过滤。
- **启动自愈**：`ServiceLocator.initialize()` 调用 `StorageService.cleanDuplicateEmails()` 清理重复邮件记录。

### 8. 已知未接入 / 与宣传不符的实现（务必阅读）
以下事项在仓库中可见，但当前并未完整接通：

- **OAuth2 登录**：`OAuth2Service.ets` 已实现 Gmail / Outlook 授权码交换与令牌刷新，`pages/OAuth2Login.ets` 源码存在，但**未注册**在 `main_pages.json`，也无 `router.pushUrl` 指向它——无法从界面进入。
- **授权帮助页**：`pages/WebAuthHelp.ets` 已注册（内置 `Web` 组件 + "用系统浏览器打开"），但全仓库**没有任何跳转入口**。
- **附件发送**：`ComposeEmail` 可选择附件，但 `MailSdkService.sendEmail()` 的附件与内联图片参数传的是 `[], []`，**未传给 SDK**——附件不会真正随邮件发出。
- **附件下载**：`EmailDetail.downloadAttachment()` 只写入**附件元信息文本**，未拉取附件二进制内容。
- **后台同步与通知**："自动同步间隔""新邮件通知"**仅作偏好持久化**，未发现后台定时任务与 `notificationManager` 投递实现。
- **文件夹管理**：`StorageService` 提供 `renameFolder()` / `deleteFolder()`，但界面**无新建、重命名入口**。
- **邮件签名编辑**：写信时会自动追加签名，但**没有任何界面可写入账号的 `signature` 字段**，该能力无法被用户配置。
- **富文本工具条**：资源中定义了 `compose_tool_bold` / `italic` / `underline` / `list` 等字符串，代码中**零引用，属死资源**（编辑器实为纯文本）。

---
## 三、技术栈
| 类别 | 采用方案 |
| --- | --- |
| 语言 / UI | ArkTS（`.ets`）；ArkUI 声明式范式（`@Entry` / `@Component` / `@State` / `@StorageLink`） |
| 应用模型 / 路由 | Stage 模型（`apiType: "stageMode"`，`UIAbility` + `ExtensionAbility`）；`@kit.ArkUI` 的 `router.*` |
| 网络能力 | `@kit.NetworkKit` 的 `http`（OAuth2 令牌交换）；邮件协议由 `mail_base` 经 TCP/TLS Socket 直连 |
| 数据存储 | `@kit.ArkData` 的 `preferences`（账号与设置）+ `relationalStore` RDB |
| 图片 / 文件 | `util.Base64` 的 `data:` URL；ArkWeb `Web` 渲染正文；`@kit.CoreFileKit` 的 `fileIo` 与 `DocumentViewPicker` |
| 日志 / 状态 / DI | `hilog`；`AppStorage` + `@StorageLink('isDarkMode')`；手写 `ServiceLocator` 单例定位器 |
| 三方库 / 工程 / 检查 | `@coremail/mail_base`、`@ohos/hypium`；`modelVersion: "6.0.2"`；`code-linter.json5` 启用 performance、typescript-eslint 与 security 规则 |

---
## 四、目录结构（关键部分）
```text
OpenHarmony-MuJie-Email/
├── AppScope/                     # 应用级配置与资源（app.json5、图标、应用名）
├── build-profile.json5 / oh-package.json5   # 工程配置、模块与签名声明
├── hvigorfile.ts / hvigor/hvigor-config.json5   # modelVersion 6.0.2
├── code-linter.json5             # 静态检查规则集
├── scripts/imap_selftest.mjs     # IMAP over TLS 登录自检脚本
├── entry/src/main/               # 主 HAP 模块（type: entry）
│   ├── module.json5              # 权限、EntryAbility、EntryBackupAbility
│   ├── ets/common/ · components/ · models/
│   ├── ets/pages/                # 10 个页面，见第七章
│   ├── ets/services/             # Storage、Account、Email、MailSdk、Filter、OAuth2
│   ├── resources/                # 资源、main_pages.json、backup_config.json
│   └── ohosTest/ · test/         # hypium 测试
├── mail_base/                    # vendored 第三方邮件协议 SDK（Apache-2.0，见第九章）
│   ├── LICENSE / OAT.xml / README.md
│   └── lib/                      # SDK 本体（@coremail/mail_base，1.0.0-Canary6）
└── README.md
```

---
## 五、环境要求
| 项目 | 要求 |
| --- | --- |
| DevEco Studio | 建议 **6.0.0 Release 或更高**（需支持 `modelVersion 6.0.2`）；最低 IDE 版本（待补充） |
| HarmonyOS SDK | `compatibleSdkVersion 5.0.0(12)`（API 12）及以上；`targetSdkVersion 6.0.2(22)` |
| 运行系统 / 设备 | HarmonyOS（`runtimeOS: "HarmonyOS"`）；设备类型 `phone`、`tablet` |
| ohpm | 需可执行（用于拉取 `@ohos/hypium`）；版本要求（待补充） |
| Node.js | 需 DevEco Studio 内置 Node 或兼容版本以驱动 hvigor；精确版本要求（待补充） |
| hvigor | 工程 `modelVersion` 为 `6.0.2`，依赖由 DevEco Studio 模板提供 |

> **重要提示**：本仓库**未包含 hvigorw / hvigorw.bat 命令行包装脚本**，`hvigor/` 下只有 `hvigor-config.json5`（`hvigorw`、`hvigorw.bat`、`hvigor/hvigor-wrapper.js` 已被 `.gitignore` 忽略且不在 git 跟踪列表中）。直接执行 `./hvigorw assembleHap` 会失败，补救方式见下一章。

---
## 六、构建与运行
### 6.1 获取代码
```bash
git clone git@github.com:jansin/OpenHarmony-MuJie-Email.git
cd MuJieEmail
```

`entry/oh-package.json5` 中 `@coremail/mail_base` 指向 `file:../mail_base/lib`，即以**源码方式本地引用**，无需联网下载；首次打开工程时 DevEco Studio 会提示 Sync 并自动执行 ohpm 安装。

### 6.2 用 DevEco Studio 构建（推荐）
1. **Open** 工程根目录，等待 Sync 完成；若提示缺少 hvigor 文件，按 6.3 补齐后重新 Sync。
2. 选择 `entry` 模块与 `default` 产品，执行 **Build → Build Hap(s)**，产物在 `entry/build/default/outputs/default/`。
3. 连接设备后点击 Run 直接安装运行。

### 6.3 命令行构建与 hvigor 包装脚本
标准命令形如（**需先补齐包装脚本**）：

```bash
hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug   # Windows
./hvigorw assembleHap --mode module -p product=default -p buildMode=debug     # macOS / Linux
hvigorw clean                                                                 # 清理
```

产物路径：`entry/build/default/outputs/default/entry-default-signed.hap`（签名配置正确时）。

`hvigorw`、`hvigorw.bat`、`hvigor/hvigor-wrapper.js` 是 DevEco Studio 工程模板文件，本仓库因 `.gitignore` 规则未纳入版本控制。需要命令行构建时，可执行一次工程 Sync 由官方模板生成，或从 IDE 安装目录的工程模板中复制到本工程根目录。

### 6.4 签名配置（必须替换）
`build-profile.json5` 的 `signingConfigs[0]` 中，`certpath` / `profile` / `storeFile` 指向提交者本机绝对路径，口令亦为本地加密值。

**在别人的机器上这些路径不存在，构建必然失败。** 请通过 **File → Project Structure → Signing Configs → 勾选 Automatically generate signature** 重新生成自己的调试签名（需登录华为开发者账号），或手动替换为自己的证书 / Profile / 密钥库。

### 6.5 安装到设备
设备开启"开发者选项 → USB 调试"并授权本机后，用 `hdc install entry/build/default/outputs/default/entry-default-signed.hap` 安装。

---
## 七、使用说明
当前注册页面（`base/profile/main_pages.json`）：`MainLayout`、`AccountList`、`AccountConfig`、`FolderList`、`EmailList`、`EmailDetail`、`ComposeEmail`、`Settings`、`FilterRules`、`WebAuthHelp`。

- **首次启动**：`EntryAbility` 加载 `pages/MainLayout`；无账号时展示欢迎视图，点击「添加账户」进入 `pages/AccountList`。
- **添加账号**：在 `pages/AccountConfig` 选择邮箱类型，或输入邮箱地址自动识别服务商并回填服务器信息。
- **登录方式**：填写邮箱地址、密码（或授权码）、显示名称，并选择**密码登录**或**授权码 / 应用专用密码**。
- 国内邮箱请选授权码，界面给出分步指引与「粘贴」按钮。
- **服务器配置**：可展开"手动配置服务器"填写接收协议（IMAP / POP3）、服务器、端口及安全类型（`SSL` / `TLS` / `NONE`）。
- 安全类型须与端口一一对应（如 `imap.qq.com:993` + `SSL`、`smtp.qq.com:587` + `TLS`），填错会导致连接失败。
- **测试与保存**：点击「测试连接」校验可达性与凭证；保存后可「设为默认」。
- **收信与读信**：进入 `pages/EmailList` 选择文件夹，列表默认读本地缓存，刷新时经 IMAP 拉取最新 50 封并写入数据库。
- 点击邮件进入 `pages/EmailDetail`，本地无正文时按需从服务器拉取并以 HTML 渲染，失败可重试。
- **写信与回复**：首页「写邮件」或列表页右下角按钮进入 `pages/ComposeEmail`，填写收件人（必填）、可选抄送 / 密送、主题与正文。
- **归档与删除**：侧滑「归档」时若为 IMAP 账号且本地归档文件夹存在，会先更新本地归属再尝试同步服务器。
- 非垃圾箱「删除」移入垃圾箱；垃圾箱「恢复」移回收件箱、「删除」彻底删除本地记录。
- **搜索**：首页搜索栏或列表页内搜索，结果为服务端搜索（最多 50 条）。
- **多账号**：「我的」标签页可切换账号；账号数大于 1 时出现「统一收件箱」（`folderId = '__unified__'`）。
- **设置与过滤规则**：首页右上角齿轮或「我的」→ 设置 → `pages/Settings`；「我的」→ 邮件过滤规则 → `pages/FilterRules`。

---
## 八、配置说明
### 8.1 权限声明
`entry/src/main/module.json5` 的 `requestPermissions` 中实际只声明了 **2 个**权限，均为 `normal` 级别，无需运行时授权弹窗：

| 权限 | 授权场景 | 用途（取自资源 `reason`） |
| --- | --- | --- |
| `ohos.permission.INTERNET` | `EntryAbility`，`when: always` | 用于连接邮件服务器收发邮件 |
| `ohos.permission.GET_NETWORK_INFO` | `EntryAbility`，`when: always` | 用于检测网络连接状态 |

> 资源文件 `base/element/string.json` 中还定义了 `PermissionBackgroundSync`（"用于后台定时同步邮件"），但 `module.json5` **并未申请**对应的后台任务权限，也未发现后台定时同步实现。

### 8.2 需要填写的配置项
| 配置项 | 位置 / 说明 |
| --- | --- |
| 邮箱地址 / 显示名称 / 用户名 | 用于服务商识别与发件人名称，用户名默认等于邮箱地址 |
| 密码 / 授权码 | 依据所选「登录方式」填写；选"授权码"时给出分步指引与粘贴入口 |
| 接收协议 / 服务器 / 端口 / 安全类型 | 预置服务商自动回填，也可手动填写；默认接收 IMAP `993 / SSL`、发送 SMTP `587 / TLS` |
| 同步间隔 / 通知 / 深色模式 | `pages/Settings`；默认 15 分钟（5–60，步长 5）/ 开启 / 关闭 |

安全类型取值 `SSL`、`TLS`、`NONE`；连接时 `secure = (security !== 'NONE')`，即前两者均按加密连接处理。

### 8.3 本地数据与存储键
| 存储 | 键 / 名称 | 内容 |
| --- | --- | --- |
| `Preferences` | `MailPreferences` → `accounts` / `current_account` | 账号列表 / 当前（默认）账号 id |
| `Preferences` | `AppSettings` → `isDarkMode` / `syncInterval` / `notificationEnabled` | 主题、同步间隔、通知开关 |
| `relationalStore` | 数据库 `MailClientDB`（`DB_VERSION = 2`） | 表：`accounts`、`folders`、`emails`、`attachments`、`contacts`、`filter_rules` |

**密码存储方式**：`StorageService` 对密码字段做 Base64 + 固定密钥异或后再 Base64，并以 `==` 前缀标识。这属于**混淆（obfuscate）而非加密**，请勿视作安全存储方案。

### 8.4 应用内常量（`common/Constants.ets`）
`DB_NAME` / `DB_VERSION` = `MailClientDB` / `2`；`SYNC_INTERVAL_MINUTES` = 15；`MAX_CACHE_SIZE_MB` = 500；`MAX_ATTACHMENT_SIZE_MB` = 25；`EMAIL_LIST_PAGE_SIZE` = 50；`MAX_ATTACHMENT_DOWNLOAD_CONCURRENT` = 3。

### 8.5 辅助自检脚本
`scripts/imap_selftest.mjs` 用于在本机直连 IMAP over TLS 验证登录（与应用内 LOGIN 行为一致），便于区分"账号 / 授权码问题"与"应用问题"：

```bash
$env:IMAP_USER="你的邮箱"; $env:IMAP_PASS="授权码"; node scripts/imap_selftest.mjs
# 可选：IMAP_HOST（默认 imap.qq.com）、IMAP_PORT（默认 993）
```

---
## 九、第三方依赖与开源许可
### 9.1 依赖清单
- **工程级（`oh-package.json5`）**：`dependencies` 为空；`devDependencies` 仅 `@ohos/hypium` `1.0.25`（测试框架）。
- **模块级（`entry/oh-package.json5`）**：`@coremail/mail_base`，`file:../mail_base/lib`（实际版本 `1.0.0-Canary6`）。

### 9.2 vendored 第三方库：`mail_base`
仓库根目录下的 `mail_base/` 是一份**完整的第三方开源 SDK 源码副本（vendored）**，并非本项目原创代码。

| 项目 | 内容 |
| --- | --- |
| 包名 / 版本 / 作者 | `@coremail/mail_base`，`1.0.0-Canary6`，作者 `coremail` |
| 版权声明 | `Copyright 2023 Coremail论客`（见 `mail_base/README.md`） |
| 上游仓库 | <https://gitee.com/openharmony-sig/mail_base>（OpenHarmony SIG 仓库） |
| 开源协议 | **Apache License 2.0** |
| 许可证文件 | `mail_base/LICENSE` 与 `mail_base/lib/LICENSE`，均为 Apache License 2.0 标准全文且内容一致 |
| 引入方式 | `entry/oh-package.json5` 以 `file:../mail_base/lib` 本地引用；`build-profile.json5` 把 `mail_base/lib` 注册为名为 **`lib`** 的模块（`srcPath: "./mail_base/lib"`），`module.json5` 声明依赖该 `lib` 模块 |
| 上游约束 | 上游声明：DevEco Studio 4.1 Canary2、SDK API11 Canary2、OpenHarmony 2.1.3.5（Canary） |

**合规声明**：`mail_base/` 及其 `lib/`、`test/` 中的代码版权归 **Coremail论客** 所有，以 **Apache License 2.0** 授权使用。任何对本仓库的分发或再许可，都必须**完整保留** `mail_base/LICENSE`、`mail_base/lib/LICENSE` 及上游的版权与许可声明。本项目自身代码以第十章的 Apache License 2.0 授权，两者许可文本相互独立；除 `mail_base/` 外未发现其他 vendored 源码。

---
## 十、开源协议
本项目采用 **Apache License 2.0** 授权，许可证全文见 [LICENSE](LICENSE)，或访问 <http://www.apache.org/licenses/LICENSE-2.0>。

在 Apache License 2.0 下，你可以：**自由使用**（个人与商业项目）、**修改**源码、**分发**原始或修改后的版本、获得贡献者授予的**专利授权**。同时需要遵守以下条件：

- **保留声明**：必须保留原始的版权声明、许可声明与免责声明，并在修改过的文件中标注已做修改；
- **附带许可证**：分发时须随附一份 Apache License 2.0 全文；
- **商标**：本许可不授予任何商标使用权；
- **不提供担保**：软件按"原样（AS IS）"提供，不附带任何明示或默示的担保。

---
## 十一、贡献与联系方式
欢迎通过 Issue 与 Pull Request 参与共建。报告问题请附设备型号、系统版本与复现步骤，协议问题请附脱敏日志（Tag 前缀 `MuJieEmail`）；提交代码请从 `main` 切出单一职责分支，遵循 ArkTS 规范与 `pages` / `services` / `models` / `common` 分层，提交前运行 `code-linter.json5` 检查。**请勿**提交真实邮箱账号、授权码、签名证书与密钥库。

- **GitHub 主页**：<https://github.com/jansin>
- **仓库地址**：<https://github.com/jansin/OpenHarmony-MuJie-Email>
- **问题反馈**：欢迎在仓库 Issues 中提出建议与缺陷报告。

### 致谢
- 感谢 **Coremail论客** 与 **OpenHarmony SIG** 开源的 [`mail_base`](https://gitee.com/openharmony-sig/mail_base)——本项目的 IMAP / POP3 / SMTP 协议栈与 MIME / MSG / RTF 解析能力均由该 SDK 提供。
- 感谢 **OpenHarmony / HarmonyOS** 生态提供的 ArkTS、ArkUI 与系统能力。

---
<sub>沐界邮箱目前为开发阶段，欢迎体验与反馈！</sub>
