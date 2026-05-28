# E00 Foundation: SourceRef And Provenance

> 状态：In Review
> 目标：统一 PaperTok Reader 中所有 AI 学习产物的证据引用、数据归属和回跳原文能力。

## 1. 为什么先做

AI Seminar、KnowledgeCard、ConceptGraph、ReviewItem、复习题和导出都依赖同一个事实：任何知识产物必须能说明“来自哪里、由谁生成、是否被用户确认、如何跳回原文”。没有 SourceRef，后续能力会产生不可追溯的聊天文本和悬空知识节点。

## 2. Capability

### E00-C01 SourceRef Contract

定义统一引用结构，至少覆盖：

- `bookId`
- `href`
- `cfi`
- `chunkId`
- `jumpLink`
- `sourceTextSnippet`
- `sourceHash`
- `modelId`
- `algorithmVersion`
- `createdAt`
- `sourceKind`
- `confidence`

默认规则：

- `bookId + href/cfi` 是 reader 回跳主路径。
- `chunkId` 是 RAG/GraphRAG 证据路径。
- `sourceHash` 用于书籍变更、卡片重复检测和旧证据失效。
- `sourceTextSnippet` 只保存短摘录，默认上限 500 个字符；同步和导出默认只包含 snippet，不包含整章、整页或完整 chunk 正文。
- 无 source 的 AI 内容只能是 `draft`。

### E00-C02 AI Output Ownership

所有 AI 产物必须标记：

- `AI-generated-draft`
- `AI-generated-approved`
- `user-authored`
- `derived-cache`
- `source-of-truth`

Seminar 结论、图谱节点、自动卡片和复习题默认是 `AI-generated-draft`。

### E00-C03 Provenance Display Contract

所有面向用户展示的知识产物都必须能显示：

- 来源书名或资料名。
- 章节或位置。
- 是否来自模型推断。
- 是否有书内证据。
- 跳回原文按钮或不可跳转原因。

## 3. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E00-C01-T01 | 盘点现有 source/evidence 字段 | 无 | 字段映射表 | 覆盖 RAG evidence、note、highlight、memory、conversation。 |
| E00-C01-T02 | 设计 SourceRef domain contract | E00-C01-T01 | SourceRef spec | 字段、可空规则、hash 规则、deep link 规则明确。 |
| E00-C01-T03 | 接入 SourceRef runtime model 和 RAG adapter | E00-C01-T02 | `lib/models/source_ref.dart`, `lib/service/rag/source_ref_adapter.dart` | JSON 兼容、snippet 上限、hash-only draft、reader jump link 校验通过。 |
| E00-C02-T01 | 定义 AI 内容归属枚举 | E00-C01-T02 | ownership spec | 每种归属有写入、同步、删除策略。 |
| E00-C02-T02 | 接入 AI output provenance contract | E00-C02-T01 | `AiProvenance`, `AiOutputOwnership` | AI draft、approved user asset、derived cache 边界有模型测试。 |
| E00-C03-T01 | 定义 provenance UI contract | E00-C01-T02 | UI contract | 用户能看到来源、证据状态和回跳动作。 |
| E00-C03-T02 | 接入 source jump audit contract | E00-C03-T01, E07-C03-T01 | `PaperReaderSourceJumpAudit` | jumpable、unavailable、unresolved source refs 可区分。 |

## 4. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | `semantic_search_library` evidence、reader deep link、notes/highlights、Memory candidate、AI conversation metadata。 |
| Allowed Modules | 仅允许 touch source/provenance 相关模型、RAG evidence adapter、文档和测试；不改 reader scheme。 |
| Forbidden Changes | 不迁移旧用户数据；不把 `ai_index.db` 改成用户资产库；不把完整书籍正文放入 SourceRef。 |
| Verification Commands | `flutter test --no-pub` 的 focused model/adapter tests；`git diff --check`。 |
| Reviewer Gate | Retrieval Quality Gate + Agent Safety And Privacy Gate + Review And Rescue Gate。 |
| Rollback / Degrade Path | SourceRef 新字段必须可选读旧数据；无 source 时降级为 draft/unverified。 |

## 5. Gates

- Retrieval Quality Gate：无 evidence 的内容不得进入正式知识库。
- Agent Safety And Privacy Gate：外发正文生成 provenance 前必须保留功能级提示。
- Review And Rescue Gate：检查是否把 `ai_index.db` 派生数据误写成 source-of-truth。

## 6. Non-Goals

- 不在本 Epic 实现完整 KnowledgeCard。
- 不迁移旧高亮或旧 Memory。
- 不改变现有 reader deep link scheme。
