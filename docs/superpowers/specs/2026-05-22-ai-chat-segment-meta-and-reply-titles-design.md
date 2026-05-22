# 设计：AI 对话「每段元数据」+「基于回复的标题」

> 日期：2026-05-22
> 状态：已与用户对齐，待写实现计划
> 范围：仅 AI 对话两项功能，互不依赖

## 背景

PaperTok Reader 的 AI 对话支持多 tab、多轮、可编辑/重新生成（每个 assistant 回复是 `AiConversationTree` 中的一个节点，重生成产生兄弟变体）。当前：

- **模型**：每个对话只在 `AiChatHistoryEntry.model` 存一个「最后用的模型」，不是按段。历史列表副标题显示 `服务名 · 模型名`。
- **Token**：`AiUsageTracker` 是整会话累计（累加每次 API 调用），仅在每轮结束后把累计值显示在输入框上方的一个 chip 里（`aiChatUsageSummaryProvider`，全局字符串），重载即清空、不持久化。
- **标题**：两条路径——heuristic `deriveFallbackTitle` 取第一条**用户提问**首行；LLM `generateTitle` 把整段对话（含问+答，前 8 条）喂模型。

用户诉求：
1. 在**每一段** assistant 回复末尾用小字显示「该段使用的模型 + 该段 token」；最后一段额外显示会话累计；并把输入框上方那块 token 统计移到这里。
2. 对话标题改为基于 **AI 回复内容**而非用户提问；两条路径都改。

## Feature 1 — 每段末尾「模型 + token」footer

### 关键架构决策：元数据存哪里

选 **存到 `AiConversationNode`**。原因：
- langchain `AIChatMessage` 只序列化 `content`+`toolCalls`，无可持久化 metadata，挂消息上重载即丢——排除。
- 仅内存不持久化，重载后每段都没了，不满足「每段」——排除。
- 节点存储与树结构一致，随 `conversationV2`（`tree.toJson()`）落盘，向后兼容（旧数据缺 `meta` → null → footer 不显示该项）。

### 数据层 — `lib/models/ai_conversation_tree.dart`

`AiConversationNode` 新增可选字段：

```
final AiSegmentMeta? meta;   // 仅 assistant 节点有，其他为 null
```

`AiSegmentMeta`（同文件新建小值类）：

```
class AiSegmentMeta {
  final String? model;       // 该轮使用的模型名
  final int? inputTokens;    // 该轮输入 token（delta）
  final int? outputTokens;   // 该轮输出 token（delta）
}
```

- `AiConversationNode.toJson`：`meta` 非空时写入 `'meta': meta.toJson()`，为空则省略。
- `AiConversationNode.fromJson`：缺失 `meta` → null（向后兼容）。
- `copyWith` 增加 `meta` 参数。
- `AiSegmentMeta.toJson/fromJson` 往返；任一字段可缺省。

### 采集层 — `lib/providers/ai_chat.dart`

- 发送一轮前（已有 `model = config['model']`），快照当前 `tracker` 的 `inputTokens/outputTokens`，连同 `model` 暂存到 draft 状态（如 `_draftModel`、`_draftTokenSnapshot`）。
- `_finalizeStreaming`：
  - `deltaIn = tracker.inputTokens - snapshot.in`，`deltaOut = tracker.outputTokens - snapshot.out`（tracker 为 null 或无增量时 meta 仍记录 model，token 留 null）。
  - 把 `AiSegmentMeta(model, deltaIn, deltaOut)` 写入 `_draftAssistantNodeId` 对应节点（`tree.copyWithNode` + `node.copyWith(meta: ...)`），再 `upsert`（`conversationV2` 已在 upsert 序列化）。
- notifier 新增 `AiSegmentMeta? segmentMetaForMessageIndex(int index)`：经 `_activeNodeIds[index]` 取节点 `meta`（`state` 与 `_activeNodeIds` 由 `_rebuildFromTree` 保证 1:1 对应）。

### UI 层 — `lib/widgets/ai/ai_chat_stream.dart`

- `_buildLinearMessageItem` 的 assistant 分支（`!isUser`）：在气泡内容下方追加一行小字 footer。
  - 样式：`textTheme.labelSmall`（或 `bodySmall`）+ `colorScheme.outline`，左对齐，紧贴在现有 copy/regenerate 操作区附近。
  - 文案：`模型名 · 1.2K tok (320 in / 880 out)`；缺字段则省略对应部分（如旧数据无 meta 则整行不显示）。
  - **最后一段** assistant（`index == 最后一个 AIChatMessage 的 index`）：footer 后追加会话累计，复用现有 `aiChatUsageSummaryProvider` 值，如 `· 会话累计 12.3K tok`。
- **移除**输入框上方 token chip（约 2616–2653 的 `usageSummary` 部分）；`contextNotice`（上下文窗口提醒）**保留**在原位置。

### token 数字格式

复用 `AiUsageTracker._formatTokenCount` 的口径（K/M 缩写）。文案用 `in / out`（英文，与现有 UI 一致；非中文以免混排）。

## Feature 2 — 标题基于「第一条 AI 回复」

取**第一条** AI 回复（而非最新），保证标题稳定、不随每轮变化。

- `lib/service/ai/conversation_title_service.dart`：
  - `deriveFallbackTitle`：遍历找**第一条 `AIChatMessage`**，取其纯文本首行做标题（替换原来的「第一条 Human」逻辑）；无 AI 回复时回退到 `'Conversation'`。
  - `generateTitle` / `_buildTranscript`：改为以**第一条 AI 回复**内容为主构造 prompt（截断到合理长度），提示词改为「概括下面这段回答的主题，生成简短标题」。
- `lib/widgets/ai/ai_chat_stream.dart` `_deriveTitle`：UI fallback 同步——`entry.title` 为空时取第一条 `AIChatMessage` 首行（替换原「第一条 Human」）。

## 明确不做（YAGNI）

- 不在每段展示成本（$）——累计区已有，且 footer 要保持精简。
- 不改变体（variant）切换逻辑、不动 `contextNotice`。
- 不为旧对话回填 meta——自然显示为「无该项」。
- 不把知识图谱可视化纳入本设计（另起独立 feature）。

## 验证

**单元测试**
- `deriveFallbackTitle`：给定「Human + AI」消息序列，返回基于第一条 AI 回复首行的标题；只有 Human 时回退。
- `AiSegmentMeta` / `AiConversationNode` 的 toJson↔fromJson 往返；缺 `meta`/缺字段的向后兼容。
- token delta 计算：snapshot→finalize 的差值正确。

**手动（真机/模拟器跑 app）**
- 发一轮 → 每段末尾出现「模型 · 本段 token」小字；最后一段额外有会话累计。
- 关闭再重新打开该对话 → meta 仍在（持久化生效）。
- 旧对话（无 meta）→ 不显示该行，不报错。
- 关 LLM 标题开关 → 标题取第一条 AI 回复首行；开 → LLM 基于回复生成。
- 输入框上方不再有 token chip，但上下文提醒仍在。
