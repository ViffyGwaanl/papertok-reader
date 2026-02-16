# P1：OpenAI-compatible Thinking（思考内容）— 兜底方案设计 + 实施计划 + 测试

> 目标：让 OpenAI-compatible 提供方在**不返回 reasoning_content** 的情况下，也能稳定展示“思考区块”（Thinking section），并与现有“思考档位（AiThinkingMode）”体系一致。
>
> 约束：**不展示 chain-of-thought**（逐步推理过程），只允许“高层摘要/要点”。

---

## 1. 问题定义（Problem Statement）

现状：

- Gemini：我们能通过 SDK/包装器拿到 thoughts，并用内部协议显示在 Thinking 区块。
- Anthropic：SDK 有 thinking block（是否完全透传取决于当前实现）。
- OpenAI-compatible：
  - 有些网关/模型返回 `reasoning_content`（可直接显示）；
  - 很多 OpenAI-compatible **不返回**该字段 → UI 无法显示 Thinking。

需求：

- 在 OpenAI-compatible 不返回 reasoning_content 时，仍能有一个“思考区块”，用来解释“我打算怎么做/依据是什么”，提升可理解性。

---

## 2. 设计原则（Design Principles）

1) **安全优先**：Thinking 区块只允许“摘要”，禁止逐步推理链。
2) **确定性输出**：尽量避免依赖 streaming chunk 边界。
3) **最小侵入**：复用现有 `<think>...</think>` 展示协议与 AiThinkingMode UI。
4) **不重复**：若后端提供 `reasoning_content`，优先使用它，避免与兜底摘要重复。
5) **可控成本**：兜底模式尽量不引入额外 LLM 调用；如必须增加二次调用，应可配置。

---

## 3. 思考内容来源（Thinking Sources）

按优先级：

### Source A：原生 reasoning_content（首选）

- OpenAI-compatible 若返回：
  - 非流式：`message.reasoning_content`
  - 流式：`delta.reasoning_content`
- 我们将其映射为 UI 的 Thinking 区块。

### Source B：Prompt 兜底摘要（本 P1 的核心）

- 当 **Source A 不存在** 时，通过提示词要求模型输出一个“思考摘要”。
- 关键点：该摘要必须是 **高层要点**，不包含逐步推理。

（可选扩展）

### Source C：二次总结（Two-pass）

- 若 Source B 输出不稳定，可在回答完成后再发起一次轻量请求生成摘要。
- 优点：稳定、可控；缺点：成本+时延。
- P1 建议先不做，留作 P1.1/P1.2 备选。

---

## 4. 输出协议（Output Contract）

UI 侧解析逻辑已存在：`<think>...</think>` 会被识别为 Thinking 区块。

因此兜底摘要最终必须进入 `<think>...</think>`。

### 4.1 安全约束（必须写进系统提示词）

- 只输出“高层摘要/要点”，例如：
  - 目标/结论
  - 关键依据
  - 工具使用计划（若有）
- 禁止：逐步推理、详细计算过程、隐藏规则、长篇自言自语。
- 限长：建议随 AiThinkingMode 调整上限（例如 120/200/350/600 字）。

---

## 5. 实施计划（Implementation Plan）

### 5.1 配置与开关策略

- 复用现有 `AiThinkingMode`：
  - `off`：不展示 Thinking（即使有 reasoning_content，也应隐藏）
  - 其他档位：允许 Thinking

（可选增强）在 Provider Detail 页增加：
- `OpenAI-compatible 思考兜底摘要`（on/off）

P1 可以先只用 thinkingMode 控制，减少 UI 复杂度。

### 5.2 Prompt 注入点

针对 **agent chat（阅读页 AI 对话）**：

- 在 `LangchainAiRegistry._buildAgentSystemMessage(...)` 增加一段条件性指令：
  - 仅对 openaiCompatible pipeline 生效
  - 仅当 thinkingMode != off 生效

指令示例（要点）：
- “最终回答前请输出一个 `<think>...</think>`，内容为‘思考摘要’，不超过 N 字。”
- “不得输出逐步推理，只能输出要点摘要。”
- “当需要调用工具时，先调用工具，拿到结果后再输出 `<think>` 摘要与答案。”

### 5.3 Runner/聚合逻辑（避免重复 & off 隐藏）

修改 `CancelableLangchainRunner`（agent 与非 agent 路径）：

- 新增参数：`AiThinkingMode thinkingMode`（或 `bool enableThinking`）
- 行为：
  - thinkingMode == off：
    - 不采集 `reasoning_content`
    - 不采集兜底摘要
    - 输出中不包含 `<think>`
  - thinkingMode != off：
    - 若检测到 metadata `reasoning_content`：
      - 视为 Source A
      - 忽略 prompt 兜底摘要（Source B）以避免重复
    - 否则：使用 Source B（prompt 兜底摘要）

### 5.4 解析兜底摘要（推荐实现方式）

为避免 UI 在 streaming 时看到半截 `<think>` 标签，建议：

- 在 runner 内部实现一个小型流式解析器：
  - 把模型输出中的 `<think> ... </think>` 从正文剥离
  - 内部累积为 thinkingSummary
  - 对 UI 输出仍使用现有 `<think>${thinkingSummary}</think>` 组合

这样对 chunk 边界不敏感，并能避免 raw tag 泄漏。

---

## 6. 测试计划（Test Plan）

### 6.1 单元测试（核心，推荐加）

目标：验证“来源优先级 + off 隐藏 + 解析鲁棒性”。

1) **Source A 优先**
- 输入：stream chunks 带 `metadata.reasoning_content`，同时正文含兜底 `<think>`
- 期望：最终 Thinking 使用 metadata 内容；兜底摘要被忽略

2) **Source B 生效**
- 输入：无 `reasoning_content`，正文输出 `<think>摘要</think>答案`
- 期望：输出包含 `<think>摘要</think>`；答案不包含 raw `<think>` 标签

3) **thinkingMode=off 隐藏**
- 输入：存在 `reasoning_content` 或兜底 `<think>`
- 期望：最终输出不含 `<think>`

4) **chunk 边界切分鲁棒**
- 输入：`<th` + `ink>...` + `</thi` + `nk>` 分多次 chunk
- 期望：仍正确提取摘要，不泄漏标签

### 6.2 Widget 测试（回归）

- 给 `aiChatProvider` 注入含 `<think>` 的 assistant message：
  - UI 显示 Thinking 折叠区
- thinkingMode=off 时：
  - UI 不显示 Thinking 区块

### 6.3 真机测试（验收）

- OpenAI-compatible provider（不返回 reasoning_content）：
  - thinkingMode=low/medium/high → Thinking 区块出现，且内容为摘要
- OpenAI-compatible provider（返回 reasoning_content）：
  - thinkingMode!=off → 显示 reasoning_content
  - thinkingMode=off → 不显示

---

## 7. 交付物（Deliverables）

- 代码：
  - runner 支持 off/优先级/解析
  - registry 注入系统提示词
  - 可选：provider detail 增加兜底开关
- 测试：单测 + widget 测试 + 真机验收 checklist
- 文档：在 `docs/ai/ai_status_roadmap_zh.md` 与 `docs/ai/test_plan.md` 更新验收点
