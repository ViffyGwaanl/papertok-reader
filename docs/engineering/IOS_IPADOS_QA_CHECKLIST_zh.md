# iOS / iPadOS 真机验收 Checklist（Paper Reader / papertok-reader）

> 目标：用最短路径验证 **Home TabBar / AI 对话 / AI 翻译 / Provider Center 多 Key 轮询与冷却 / 备份恢复 / WebDAV 同步** 在真机上可用、稳定。

## 0. 准备

- 建议用 **TestFlight** 或 Xcode Archive 安装（避免 dev install 的签名/沙盒差异）。
- 确认构建时 AI 功能开关已开启（如果项目使用了 dart-define/env 开关）。
- 如要验证“同步/备份不包含密钥”，建议准备：
  - 1 个 WebDAV 账号/目录
  - 1 个 iCloud Drive / Files 可写目录

## 1. Home TabBar（苹果风格浮动 Tab 栏）

**目标**：不遮挡、不乱跳、键盘出现时行为一致。

1) 进入 Home 任意 Tab，确认底部 TabBar 为“浮动磨砂胶囊”样式。
2) 进入 **AI** Tab：
   - 观察底部输入框未被 TabBar 遮挡。
3) 点击输入框弹出键盘：
   - 预期：**TabBar 全局隐藏**（键盘可见期间不应被“顶上来”覆盖输入区）。
4) 收起键盘：
   - 预期：TabBar 恢复显示。

## 2. Provider Center（供应商中心）与多 Key 管理

**目标**：Key 列表可编辑、可测试、可观察统计与冷却；并可手动解除。

1) 设置 → **AI Provider Center** → 选择一个 provider（建议先用你实际可用的 OpenAI-compatible 或 OpenAI Responses）。
2) 进入 API Keys：
   - 添加 2 个 key：
     - Key A：故意填错（用于触发失败）
     - Key B：正确可用
   - 两个 key 均 enabled。
3) 点击 **Test**（单个或全部测试）：
   - 预期：Key A FAIL、Key B OK；并写入 lastTest 信息。
4) 进入“高级策略”：
   - 调整：连续失败阈值、401/429/503 冷却分钟数。
   - 预期：修改后自动保存（无需手动点保存也会生效）。
5) 触发一次真实请求（见第 3/4 节），回到 Key 列表：
   - 预期：失败 key 的 fails / consecutive / cooldown 会更新。
6) 手动操作：
   - 对某个 key 选择“**解除冷却**”：预期 cooldown 消失。
   - 对某个 key 选择“**重置统计**”：预期 success/fail/consecutive 清零。

## 3. Home AI 对话（不带书籍上下文）

**目标**：可发消息、流式输出、失败时自动切 key。

1) Home → AI，输入一句短问题点击发送。
2) 若当前选中的 key 失败（Key A），应自动 failover 到 Key B：
   - 预期：最终能得到回答。
   - 回到 Provider Detail：Key A failureCount 增加，可能进入 cooldown。
3) 验证“思考强度默认值”：
   - 未显式设置 thinking_mode 的情况下，默认应为 **Auto**。

## 4. Deep Links（Reader 导航 / Shortcuts 回传）

**目标**：`paperreader://...` deep link 行为正确，且不影响 Shortcuts 回传。

1) 在 iOS 备忘录（或任意可点击链接的地方）粘贴并点击：
- `paperreader://reader/open?bookId=<id>&href=<href>`
- `paperreader://reader/open?bookId=<id>&cfi=<epubcfi(...)>`

预期：能拉起 App 并打开对应书，定位到 href/cfi（best-effort）。

2) Shortcuts 回传（如果你有现成 shortcut）：
- 触发一次 `paperreader://shortcuts/result?...`
- 预期：App 内 Shortcuts 等待器能收到回传，不应被 reader 路由误判。

## 5. AI 索引（书库）/ 全库检索（Phase 3）

**目标**：书库索引队列与 `semantic_search_library` 可用、稳定。

1) Settings → 顶层 **AI 索引（书库）**：
   - 切换筛选：未索引/过期/已索引（应为 DB 真值）。
   - 手动多选几本书加入队列。
2) 队列控制：
   - Pause → Resume
   - Cancel（running/queued）
   - Clear finished
   - 失败自动重试一次（第二次失败落 failed 并显示错误摘要）
3) Home → AI（Agent 模式）：让模型调用 `semantic_search_library`：
   - 预期返回 evidence 列表含 `jumpLink`，并且以 `paperreader://reader/open?...` 开头。
4) 点 evidence 的 jumpLink：
   - 同书应在当前阅读器内跳转。
   - 跨书应打开对应书并定位（best-effort）。

## 6. 阅读页 AI（带书籍上下文）

**目标**：阅读页 AI 面板打开/最小化/继续流式，且不抢焦点/不乱滚动。

1) 打开任意 EPUB。
2) 打开阅读页 AI：
   - iPad：验证 dock/bottom sheet 模式切换（如果开启）。
   - iPhone：验证面板输入时不被 UI 遮挡。
3) 发送一条消息并最小化/切换界面：
   - 预期：流式继续（不应因为 UI 最小化而中断）。

## 5. Inline 全文翻译（阅读页）

**目标**：翻译不会被页面切换取消；HUD 状态可见；失败可重试。

1) 在阅读设置里开启 inline 全文翻译。
2) 翻页/滚动：
   - 预期：上一页翻译任务不被取消；HUD 进度正常更新。
3) 刻意制造失败（例如用 Key A 或限流）：
   - 预期：失败段落会记录失败原因。
4) 点击“重试翻译”：
   - 预期：能对失败段落强制重试；状态区显示最近一次重试信息。

## 6. WebDAV 同步（不含密钥）

**目标**：配置可同步，密钥不出本机。

1) 打开 WebDAV 同步并执行一次同步。
2) 在另一台设备/或清空后恢复：
   - 预期：provider 列表、URL、model、prompt 等同步成功。
   - 预期：`api_key` / `api_keys` **不会被同步**（需要你本机重新导入或用加密备份）。

## 7. iCloud Drive / Files 备份与恢复

**目标**：明文备份不含密钥；加密备份可携带密钥；导入可回滚。

1) 导出 **明文备份**：确认内容不含 `api_key` / `api_keys`。
2) 导出 **加密备份**：选择包含密钥（如有该选项），然后导入验证：
   - 预期：导入后 keys 恢复；且导入过程中发生错误时应有 .bak 回滚（无半恢复状态）。

## 8. iOS 系统工具（EventKit：提醒事项/日历）

**目标**：AI 工具能在 iOS 上稳定调用 EventKit 能力，并受到 Tool Safety 审批保护。

### 8.1 Reminders（提醒事项）
1) 设置 → AI 工具：确保开启（至少开启 reminders_list_lists / reminders_list / reminders_create / reminders_update / reminders_complete / reminders_delete）。
2) Home → AI：触发一次只读调用：
   - 让 AI 先调用 `reminders_list_lists`，再用默认清单调用 `reminders_list`（未来7天）。
3) 触发写入：让 AI 创建一条提醒（预期弹出审批弹窗）。
4) 更新/完成：让 AI 更新 dueIso，然后 complete，再 uncomplete。
5) 删除：让 AI 删除该提醒（预期 destructive 强确认）。

### 8.2 Calendar（日历）
1) 设置 → AI 工具：确保开启（calendar_list_calendars / calendar_list_events / calendar_create_event / calendar_update_event / calendar_delete_event）。
2) 创建事件：让 AI 创建一个带 `alarmMinutes=10` 的事件（预期审批弹窗）。
3) 列表确认：让 AI 调用 `calendar_list_events(includeAlarms=true)`，确认能看到 alarmMinutes。
4) 更新：让 AI 修改标题/时间（预期审批弹窗）。
5) 删除：让 AI 删除该事件（预期 destructive 强确认）。

> 备注：重复事件（recurrence + span=thisEvent/futureEvents）建议作为加分项验证。

## 9. 结论记录（建议）

每次验收后记录：
- 测试设备型号 + iOS/iPadOS 版本
- 本次 app 的 git commit / build number
- blocker/major/minor 问题列表（附复现步骤）
