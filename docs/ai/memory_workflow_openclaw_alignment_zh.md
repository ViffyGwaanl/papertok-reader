# PaperTok Reader Memory 工作流对齐 OpenClaw（产品方案 v1）

> 目标：在**不推翻现有 Memory 检索层**的前提下，把 PaperTok Reader 的 Memory 从“可检索的 Markdown 记忆库”补齐为“**daily + long-term + review inbox**”的完整工作流。
>
> 2026-03-07 更新：M1（manual-first）已落地，包含候选 workflow store 与索引 cache 分离、聊天显式保存到 daily / long-term、加入 review inbox、Memory 设置页最小 Review Inbox UI，以及统一的 Markdown memory 写协调器。M1.5 / M2 现已补齐一版产品可用收口：结束会话时可生成 session digest；自动化候选可在“进入 Review Inbox / 自动写入今日日记”之间切换；长期记忆默认保持二次确认；仍不支持 silent auto-write 到 long-term。

## 1. 当前状态（As-Is）

### 1.1 已经对齐 OpenClaw 的部分

PaperTok Reader 当前已经基本对齐 OpenClaw 的“检索层”设计：

- Markdown 为 source-of-truth
  - `memory/` 下的 Markdown 文件是最终真相来源
- 索引为派生缓存，可删可重建
- 支持本地 FTS/BM25、可选 semantic/hybrid 检索
- dirty + debounce 后台刷新
- 搜索不阻塞索引完成

也就是说，当前系统已经具备：
- 自动索引（index freshness）
- 自动召回（memory_search / snippet retrieval）

### 1.2 还没完全对齐 OpenClaw 的部分

当前缺的已经不是“基础 workflow 是否存在”，而是“**workflow 后续阶段做多深**”：

- M1（manual-first）已补齐：
  - `daily memory`
  - `long-term memory`
  - `review inbox`
  - 候选记忆 -> 审核 -> 应用 的最小闭环
- Memory 和 Chat History 仍是两套系统，但现在已经有了显式桥接入口：
  - AI 对话历史仍主要落在 `ai_history.json`
  - 用户可以从聊天显式保存到 `memory/`
- 当前仍待补齐的是：
  - session-end candidate digest
  - optional auto-daily
  - 更细的写入触发器、确认策略和自动化边界

## 2. 设计原则（Why）

### 2.1 不要把“自动索引”误解成“自动记住”

要区分 4 件事：

- **记忆**：真正写入 Markdown 的内容
- **索引**：为了更快更准找到记忆而生成的辅助结构
- **自动索引 / 自动召回**：文件变化后自动更新索引；提问时自动检索
- **静默自动写入**：系统不问用户，直接把新内容写进记忆

本方案延续 OpenClaw 的优势：
- 自动索引
- 自动召回

但不建议一开始就默认开启：
- 完全静默自动写入长期记忆

### 2.2 `daily` 可更自动，`long-term` 必须更克制

这是本方案的核心：

- `daily` 是当天原始日志，容错高，可以更自动
- `long-term` 会持续影响后续召回与行为，因此必须更谨慎

因此：
- `daily`：半自动（甚至可选自动）
- `long-term`：默认确认后写入

### 2.3 不把 workflow 元数据写进 Markdown 正文

Markdown 继续作为最终记忆内容的 source-of-truth；
“候选记忆”“审核状态”“来源消息”这些 workflow 元数据，应该单独存储，而不是混进 `MEMORY.md` / 日记正文。

## 3. 目标架构（To-Be）

## 3.1 三层结构

### Layer A — Source of Truth（最终记忆）

- `memory/YYYY-MM-DD.md`
- `memory/MEMORY.md`

职责：
- 存储最终被接受的记忆内容
- 继续作为检索索引的输入源

### Layer B — Retrieval Index（派生索引）

- FTS/BM25
- semantic / hybrid index
- embedding cache

职责：
- 自动索引
- 自动召回
- 结果排序 / snippet / ranking

### Layer C — Workflow State（候选与审核）

新增一套 workflow store，专门存：
- 候选记忆
- 来源消息
- 审核状态
- 提升（promote）记录

这层不是“最终记忆”，而是“记忆写入工作流”。

## 3.2 文件与状态职责

### Daily memory

- 文件：`memory/YYYY-MM-DD.md`
- 语义：当天原始事件、对话结论、临时上下文、待办
- 特点：
  - 允许碎片化
  - 允许冗余
  - 允许将来再提炼

### Long-term memory

- 文件：`memory/MEMORY.md`
- 语义：长期稳定偏好、项目背景、长期决策、持续有效规则
- 特点：
  - 更短
  - 更稳定
  - 更克制

### Review Inbox

- 不是 Markdown 文件
- 是候选记忆的工作流队列
- 用于承接：
  - 会话结束自动生成的候选
  - 用户显式“保存到记忆”但尚未确认的候选
  - 从 daily 提炼 long-term 的候选

## 4. 数据模型

建议新增：`MemoryCandidate`

最小字段：

- `id`
- `sourceType`：`chat | manual | import`
- `conversationId`
- `messageNodeId`
- `targetDoc`：`daily | memory`
- `text`
- `summary`
- `sensitivity`
- `confidence`
- `status`：`pending | applied | dismissed`
- `createdAt`
- `appliedAt`

### 推荐新增组件

- `memory_candidate_store.dart`
- `memory_workflow_service.dart`
- `memory_write_coordinator.dart`

### 为什么需要 `MemoryWriteCoordinator`

当前 file append / replace 还是偏底层直接写文件。
如果后面加入：
- 自动 daily 写入
- review inbox 应用
- promote to long-term

就会出现并发写入/覆盖风险，因此需要统一协调器串行化写入。

## 5. 写入策略

## 5.1 Daily memory 写入策略

### 默认策略

- 默认支持**半自动**
- 可选开启“自动保存到今日日记”

### 写入触发器

建议支持这些触发条件：

- 用户显式说：
  - “记住这个”
  - “以后按这个来”
  - “这是我的偏好/规则”
- 用户点击：
  - “保存到今日日记”
- 系统识别到：
  - 一次对话中出现明确决策 / 待办 / 阶段性结论
- 导入/恢复记忆后
- Memory 编辑器保存后

### Daily 的默认行为

- 先生成一条 candidate
- 如果“自动保存到今日日记”开启：
  - 直接写 daily
- 如果关闭：
  - 进入 Review Inbox，等待确认

## 5.2 Long-term memory 写入策略

### 默认策略

- **默认需要确认**
- 不建议 silent auto-write

### Long-term 的触发器

- 用户显式说：
  - “长期记住这个”
  - “这是长期偏好”
  - “以后都按这个来”
- 从 daily / review inbox 中提炼得到候选长期记忆

### Long-term 的默认行为

- 先生成 candidate
- 进入 Review Inbox
- 用户确认后写入 `memory/MEMORY.md`

## 5.3 静默自动写入（可选高级开关）

如果未来要支持“系统自己判断值得记住并直接写入”，建议：

- **只对 `daily` 开放**
- 默认关闭
- `long-term` 一律不默认静默写入

原因：
- 错误长期记忆污染成本远高于 daily
- 一旦检索层很强，错误长期记忆会不断被召回

## 6. UI / UX 方案

## 6.1 设置页

当前已落地 3 个设置项：

- 结束会话时生成记忆候选
- 自动 daily 路由：`进入 Review Inbox` / `自动写入今天`
- 长期记忆写入前需要确认

本轮未落地、继续保留为后续增强：

- 周期性整理 daily 为长期候选
- 更细粒度的自动静默 daily 规则（例如仅高置信度）
- 语义记忆检索（embedding provider disclosure）
- 备份时默认是否包含 memory/

## 6.2 对话页入口

在 AI 聊天页当前已提供两类入口：

- user / assistant message 轻量操作：
  - 保存到今日日记
  - 保存为长期记忆
  - 加入待审队列
- 会话结束入口：
  - 结束当前会话时，按设置生成 0–3 条 session digest 候选
  - 默认进入 Review Inbox；可切换为自动写入今日日记

## 6.3 Memory 页结构

当前 Memory 页更像“文件编辑器 + 搜索页”。
目标结构建议改成三块：

- `Today`
- `Long-term`
- `Review Inbox`

### Review Inbox 能做什么

- 预览候选摘要
- 查看来源消息
- 应用到 daily
- 提升到 long-term
- 驳回 / 删除候选

## 7. 安全与隐私规则

### 7.1 默认不自动进入记忆的内容

- secrets / token / 密码
- 敏感隐私
- 附件全文
- 长文本原文
- 低置信度自动提炼结果

### 7.2 semantic / hybrid disclosure

如果 memory 文本要发给 embedding provider：
- 必须有设置项说明
- 最好显示 provider 是本地还是云端

### 7.3 backup/export 默认值

建议：
- `Include Memory` 默认关闭
- 或至少记住上次选择，并加更明显 warning

## 8. 与现有实现的衔接

## 8.1 不推翻当前检索层

保留现有：
- MarkdownMemoryStore
- memory index database
- dirty + debounce coordinator
- memory tools
- semantic / hybrid retrieval

新增的是 workflow 层，不是重写 retrieval 层。

## 8.2 不破坏现有用户文件格式

- 不改 `MEMORY.md`
- 不改 `YYYY-MM-DD.md` 命名规则
- 用户现有 memory/ 数据可原样继续使用

## 8.3 chat history 回填不是默认行为

如果以后做“从聊天历史回填候选记忆”：
- 只能是显式 opt-in wizard
- 不能默认静默回填

原因：
- `ai_history.json` 是 cache，不完整
- 默认只保留最近窗口，不是权威历史源

## 9. Rollout 计划

### P0 — 文档与 schema 准备

- 补本方案文档
- 新增 workflow 数据模型 / store / prefs
- 不改默认行为

### P1 — 显式保存入口（已完成 / M1）

- 聊天页支持：
  - 保存到今日日记
  - 保存到长期记忆
  - 加入待审队列
- Memory 页新增最小 Review Inbox
- 候选 workflow state 与索引 cache 分离存储
- Markdown 写入统一走串行协调器

### P2 — Promote to Long-term（已完成 / M1）

- Review Inbox 支持提升到 `MEMORY.md`
- long-term 仍然是显式触发，不做 silent auto-write

### P3 — Session-end candidate digest（已完成 / M1.5）

- 结束当前聊天会话时，可生成 0–3 条 session candidate
- 默认进入 Review Inbox，不直接写入 long-term
- 当前采用产品安全优先的本地整理策略，不依赖 silent long-term write

### P4 — 可选自动 daily（已完成 / M2 的稳定子集）

- 设置页可切换 automated/session candidate 的 daily 路由：
  - `Review Inbox`
  - `Auto-save to today`
- long-term 仍然要求确认
- 本轮未做“后台静默自动抓取任意候选并自动写 daily”的激进模式

## 10. 结论

PaperTok Reader 当前已经具备了 OpenClaw 式 Memory 的“检索基础”，下一步不是再造搜索，而是补齐：

- 记忆分层
- 写入触发
- 候选审核
- UI 流程
- 隐私边界

推荐策略明确为：

- `daily`：半自动 / 可选自动
- `long-term`：确认后写入
- 检索层：继续沿用现有自动索引 / 自动召回 / hybrid 检索

这样既能对齐 OpenClaw 的优点，又不会因为静默长期写入而污染记忆质量。
