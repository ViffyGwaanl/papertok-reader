# P2 Understand-Anything Book Map

> 状态：Draft/In Progress
> 最后更新：2026-06-03
> 目标：把当前规则派生图谱升级为 Understand-Anything 式全书 AI 理解地图。

## 1. 用户价值

用户打开一本书后，不只是看到一堆节点和边，而是能快速理解：

- 这本书主要讲什么。
- 核心概念有哪些。
- 概念之间是什么关系。
- 哪些章节解释了哪些概念。
- 哪些观点互相支持、冲突、递进或举例。
- 如果只想快速入门，应该先看哪条导读路径。
- 如果想深入复习，应该围绕哪些概念和证据。

目标参考 Understand-Anything 的呈现方向：结构解析 + LLM 语义理解 + 图谱探索 + guided tours。PaperTok 的差异是必须以书内 SourceRef 为边界，不能把无证据推断写成书内事实。

## 2. 当前状态

当前分支已有：

- `ai_chunks`、RAG、SourceRef 和章节/chunk 证据回链。
- `ai_graph_nodes`、`ai_graph_edges`、`ai_graph_node_chunks` 等派生图谱表。
- `AiGlobalIndexBuilder` 可用本地规则生成 RAPTOR/GraphRAG 风格全局层。
- `ConceptGraphExplorerPage` 可显示当前书只读全书派生图谱。
- 节点和边可以查看证据、打开来源、保存为草稿图谱资产。

当前主要问题：

- 全书图谱 builder 没有真正调用 LLM。
- 节点主要来自正则、中文 marker 和本地短语抽取。
- 关系主要来自同 chunk 共现，不是 AI 判断的语义关系。
- 摘要多为截断拼接或模板文本，不是 AI 对概念的解释。
- 没有 guided tours、概念层级、社区解释、难点路径、章节导读路径。
- UI 仍像设置页工具，不像阅读页的一等理解地图。

## 3. 目标形态

全书 AI 理解地图由四层组成：

1. 结构层：章节、chunk、标题、原文位置、SourceRef。
2. AI 语义层：概念、主题、人物、术语、claims、问题、结论、例子、难点。
3. 关系层：supports、contrasts、causes、depends_on、part_of、example_of、explains、develops、appears_in。
4. 导读层：全书速览、核心概念入门、章节推进、难点解释、复习路径、争议观点路径。

规则抽词和共现图谱只能作为候选层，不能标记为最终智能图谱。

## 4. 数据和 schema 计划

新增或扩展 AI semantic graph 结构时，需要支持：

- `node.kind`：concept、theme、claim、person、term、question、chapter、example。
- `node.summary`：AI 生成的人话解释。
- `node.aliases`：同义词、翻译、简称。
- `node.evidenceRefs`：可展示的 SourceRef。
- `node.confidence`：基于证据覆盖、模型自评和 reviewer pass 的置信度。
- `edge.type`：语义关系类型。
- `edge.reason`：AI 解释为什么这两个节点有关。
- `edge.evidenceRefs`：支持这条关系的原文证据。
- `tour.steps`：导读路径的节点、章节、证据和解释。
- `builder.modelId/providerId/schemaVersion`：用于重建、失效和对比。

现有 `ai_graph_nodes/edges` 可继续承载派生缓存，但需要明确区分 deterministic layer 和 ai_semantic layer。

## 5. 阶段计划

### P2-S1：AI semantic graph builder schema

定义模型输出 JSON schema、SourceRef 输入范围、节点/边/tour schema、错误恢复和版本字段。

验收：

- 有测试 fixture 覆盖中文书、英文书、短书和无足够证据场景。
- 模型输出必须能被严格解析和修复。
- 无 SourceRef 的节点/边不能进入高置信图谱。

### P2-S2：章节级 AI 抽取

按章节或 chunk group 调用 LLM，抽取概念、claims、问题、例子和候选关系。

验收：

- 每个候选节点/边至少带一个 chunk SourceRef。
- 失败章节可重试，不导致整本书图谱损坏。
- 进度和成本估算可见。

### P2-S3：全书合并和去重

对章节级候选做同义合并、canonical name、层级归并和重复关系合并。

验收：

- `工作记忆` / `working memory` / `短时记忆` 等可被合并或明确区分。
- 合并不会丢 SourceRef。
- 模型版本变化时可重建。

### P2-S4：关系判断和 AI reviewer pass

让 AI 对关系类型、关系原因和证据充分性做二次判断。

验收：

- 关系不再只有 co_occurs。
- 低证据关系降级为候选或隐藏。
- reviewer 能标记 hallucination、duplicate、weak evidence、ambiguous relation。

### P2-S5：guided tours

生成全书速览、核心概念入门、章节推进、难点解释、复习路径和争议观点路径。

验收：

- 用户能按路径一步步看概念、章节和证据。
- 每一步都有一句解释和至少一个来源。
- 路径可被 AI Chat 调用并继续追问。

### P2-S6：阅读页一等 UI

把图谱从 Settings 工具页升级为阅读页 `本书理解地图`。

验收：

- 阅读页可打开全书地图。
- 支持搜索、社区/章节/概念/导读切换。
- 点击节点显示解释、相邻关系、证据和追问入口。
- 移动端手势、布局和性能通过资源 gate。

### P2-S7：AI Chat 联动

AI Chat 可调用全书理解地图回答问题、解释节点、展开导读路径或发起围绕节点的 Seminar。

验收：

- 用户能问“这本书讲什么”“解释这个概念和上一章的关系”。
- 回答引用图谱节点和书内证据。
- 研讨会可选择图谱节点作为 evidence scope。

## 6. 不做事项

- 不把本地抽词 + 共现边包装成 AI 智能图谱。
- 不自动把 AI 推断写成正式用户资产。
- 不展示无证据节点为书内事实。
- 不优先做复杂无限画布而忽略 AI 语义质量。
- 不把外部知识库扩展放在第一阶段；先做好当前书。

## 7. 更新要求

推进 P2 时必须更新：

- 本文件的 builder、schema、UI 和验收状态。
- `../implementation_status_zh.md` 的实现证据。
- `../04_user_facing_activation_plan_zh.md` 的图谱入口和用户能用边界。
- `P3_intelligent_index_retrieval_foundation_zh.md` 中对索引/检索底座的依赖状态。

## 8. 状态更新记录

- 2026-06-03：建立 P2 详细计划。确认当前只有规则派生图谱，真正 AI semantic graph builder 仍缺失。
