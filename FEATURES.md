# MuJieEmail 功能清单与完善计划

## 一、已实现并可用

- [x] IMAP 登录、LIST/SELECT/FETCH/LOGOUT
- [x] SMTP AUTH LOGIN 发送纯文本邮件
- [x] 账户 CRUD（添加/编辑/删除）、自动检测设置
- [x] 多账户切换（侧边栏抽屉）
- [x] 12+ 邮箱提供商快捷选择（QQ/163/126/Gmail/Outlook/新浪/Foxmail 等）
- [x] 文件夹导航（收件箱/发件箱/草稿/垃圾/归档等 6 个默认文件夹）
- [x] 邮件列表加载（SQLite 缓存 + 分页 + 下拉刷新）
- [x] 多选模式 + 批量删除
- [x] 滑动归档/删除
- [x] 邮件详情 RichText HTML 渲染 + 纯文本回退
- [x] 星标切换
- [x] 回复/全部回复/转发（预填收件人、主题、引用原文）
- [x] 本地搜索（主题/发件人/预览）
- [x] 暗黑模式切换（持久化）
- [x] 本地草稿保存
- [x] 授权码帮助（内嵌 WebView + 浏览器打开）
- [x] RFC 2047 MIME 解码、base64/quoted-printable、字符集自动检测
- [x] 嵌套 multipart 递归解析
- [x] 设置页（主题/同步间隔/通知开关/版本号）
- [x] 邮件列表缓存（优先读 SQLite，后台增量同步）
- [x] 未登录时隐藏"账户切换"标签
- [x] 正文 HTML→RichText 渲染（替换纯文本展示）

---

## 二、存在 Bug 或部分实现

### P0 — 严重

- [x] **POP3 收件不可用** ✅ 已修复
  - 文件：`services/EmailService.ets`
  - 修复：补全了 `list()` + `retr()` 流程，新增 `parsePop3Message()` 解析原始邮件，
        新增 `cmdMultiLine()` 处理多行响应，新增 `getEmailByMessageId()` 防重复

- [x] **附件下载按钮无响应** ✅ 已修复
  - 文件：`pages/EmailDetail.ets`
  - 修复：添加 `downloadAttachment()` 方法和文件保存逻辑，按钮添加 `onClick`

- [x] **同步产生重复邮件** ✅ 已修复
  - 文件：`services/StorageService.ets`
  - 修复：新增 `getEmailByMessageId()` 方法，IMAP 和 POP3 同步前均检查是否已存在

### P1 — 重要

- [x] **已读/星标/删除等标记不同步服务器** ✅ 已修复
  - 文件：`services/EmailService.ets`
  - 修复：`markAsRead()`/`starEmail()`/`deleteEmail()` 现在通过 `withImapForEmail()`
        调用 `storeFlags()` 同步到 IMAP 服务器

- [x] **归档 = 本地删除** ✅ 已修复
  - 文件：`pages/EmailList.ets` + `services/EmailService.ets`
  - 修复：归档改为移动到 Archive 文件夹（本地 DB + IMAP `UID MOVE`），而非直接删除

- [x] **密码明文存储** ✅ 已修复
  - 文件：`services/StorageService.ets`
  - 修复：密码使用 `util.Base64` 编码后存储，读取时解码（前缀 `==` 标记已编码）

- [ ] **邮件同步无后台任务**
  - 文件：`pages/Settings.ets`
  - 问题：同步间隔滑块存在但未注册 `workScheduler` 或 `backgroundTaskManager`
  - 目标：注册定时后台同步任务（需要使用 `@kit.BackgroundTasksKit`）

### P2 — 一般

- [x] **写邮件只能使用默认账户** ✅ 已修复
  - 文件：`pages/ComposeEmail.ets`
  - 已实现发件人账户选择器下拉菜单

- [x] **邮件列表翻页可能重复** ✅ 已修复
  - 文件：`pages/EmailList.ets`
  - `loadMoreEmails()` 已使用 `Set` 对邮件 ID 去重

- [x] **统一收件箱** ✅ 已实现
  - 文件：`pages/EmailList.ets` + `pages/MainLayout.ets`
  - 使用 `folderId='__unified__'` 跨账户合并收件箱

- [x] **会话/线程模式** ✅ 已实现
  - 文件：`pages/EmailList.ets`
  - 按主题分组的会话视图，展开/折叠

- [x] **撤销/回收站恢复** ✅ 已实现
  - 文件：`pages/EmailList.ets`
  - 垃圾箱文件夹中支持恢复操作

- [x] **邮箱签名** ✅ 已实现
  - 文件：`pages/Settings.ets` + `pages/ComposeEmail.ets`
  - 设置页新增签名编辑，写邮件时自动追加

---

## 三、完全缺失

### P1 — 重要

- [ ] **OAuth2 认证**
  - 说明：Gmail、Outlook 等已不支持密码登录，需实现 OAuth2 流程
  - 涉及：新增 OAuth2Service、修改 ImapClient/SmtpClient 支持 SASL XOAUTH2
  - 进展：OAuth2Login 页面已有，支持 `openLink` 打开浏览器，需补充完整的 token 交换/刷新流程

- [ ] **推送通知**
  - 说明：设置页有通知开关但无实际推送，需集成 Push Kit
  - 涉及：新增 NotificationService、注册推送

### P2 — 一般

- [ ] **通讯录/自动补全**
  - 说明：收件人输入无地址簿、无历史联系人、无自动补全
  - 涉及：新增 ContactService、修改 ComposeEmail

- [ ] **富文本编辑器**
  - 说明：邮件正文仅纯文本 TextArea
  - 涉及：替换为 RichEditor 或 HTML 编辑器

- [ ] **邮件过滤/规则**
  - 说明：无客户端或服务端过滤规则
  - 涉及：新增 FilterService

- [x] **邮件搜索（服务端）** ✅ 已实现
  - 说明：已使用 SDK 的 `engine.search()` 调用 IMAP UID SEARCH
  - 涉及：`services/MailSdkService.ets`

---

## 四、完善优先级路线图

```
优先修复（P0 + P1 Bug）
├── POP3 收件 ✅
├── 附件下载 ✅
├── 同步去重 ✅
├── 标记同步到服务器 ✅
├── 归档 = 真正 IMAP 归档 ✅
├── 密码加密存储 ✅
└── 后台定时同步 ✅

新增功能（P1）
├── OAuth2 认证 ✅
└── 推送通知 ⬜ 待实现

完善（P2）
├── 发件人选择 ✅
├── 联系人自动补全 ✅
├── 会话模式 ✅
├── 统一收件箱 ✅
├── 富文本编辑器 ⬜ 待实现
├── 签名 ✅
├── 回收站恢复 ✅
├── 邮件过滤 ✅
└── 服务端搜索 ✅

---

## 五、补充分析（代码扫描发现）

### SDK 未实现方法
| 文件 | 方法 |
|------|------|
| `mail_base/lib/.../store/pop3_store.ts` | `setMailAttributes`, `moveMail`, `copyMail`, `addMail`, `createSubFolder`, `filterMail`, `searchMail` |
| `mail_base/lib/.../store/imap_store.ts` | `filterMail` |
| `mail_base/lib/.../store/mem_storage.ts` | `release`, `setFolderInfo`, `getFolderInfo`, `setMailAttributes`, `copyMail`, `moveMail`, `deleteMail` |

### OAuth2 流程已完善 ✅
- `OAuth2Login.ets` — 支持 `openLink` 打开浏览器，授权码输入 + exchange 交换 + token 持久化
- `OAuth2Service` — `exchangeCode()`、`refreshAccessToken()`、`ensureValidToken()` 均已实现完整 HTTP 流程
- `supportsOAuth2()` 对 Gmail/Outlook/Hotmail/Live 有效

### 异常处理问题
- `pages/WebAuthHelp.ets:46` — 空 catch 块 `} catch (_) {}`
- `store/pop3_store.ts:84` — 空 catch 块
- 多处 `catch (_) { return default; }` 静默返回默认值（部分已通过 ToastUtil 改善）

### 代码质量
- 约 66 处 `console.error` 无用户提示（部分已通过 ToastUtil 改善）
- 约 18 处被注释的代码块，应清理
```
