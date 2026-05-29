# User-Facing Activation Plan

> 状态：In Review  
> 用途：把 agentic upgrade 的底层能力转成用户能找到、能触发、能验证的产品入口。

本文件只回答三个问题：

- 用户现在从哪里用。
- 哪些能力已有底层 artifact，但还没有产品入口。
- 剩余 Agent Task 怎样把能力接成可用闭环。

## 1. 当前用户可用性

| 能力 | 用户入口 | 当前状态 | 真实边界 |
| --- | --- | --- | --- |
| Review Inbox | `Settings -> AI -> Review inbox`，以及 Settings 顶层知识审核入口。 | 已接入 UI，可展示、批准、忽略、应用 KnowledgeCard 和 ConceptGraph relation 类型审批项。 | 只有 producer 写入 `ReviewItemStore` 后，用户才会看到内容。 |
| 选中文本 -> KnowledgeCard | 阅读页选中文本 -> `知识卡`。 | 本分支已接入 `SelectionKnowledgeCardProducer` 和选中菜单入口，选中文本会进入 KnowledgeCard store 与 Review Inbox。 | 默认只进入 Review，不写长期记忆、不写笔记、不写 spaced review。 |
| 选中文本 -> AI Seminar | 阅读页选中文本 -> `研讨`。 | 本分支已接入最小可用入口：打开 AI 面板、切到 `seminar_mode`，把选中文段放入研讨草稿。 | 当前是 prompt skill flow；结构化 role runtime、Shared Whiteboard UI、自动 Review handoff 还没有接成产品入口。 |
| AI Chat 普通解释 | 阅读页选中文本 -> `AI`。 | 仍可用，保留原行为。 | 不自动生成 KnowledgeCard 或 ConceptGraph。 |
| ConceptGraph / WikiLinks Explorer | 无正式用户入口。 | 底层 `ConceptGraphStore`、dossier、局部探索、relation Review adapter 已存在。 | 缺 RAG/GraphRAG producer、概念页、局部图 UI、阅读页入口。 |
| Spaced Review | 无正式用户入口。 | `SpacedReviewItem` 模型和 KnowledgeCard adapter 已有切片。 | 缺队列、复习页、到期调度和与 Review apply 的连接。 |
| Sync / Export 知识资产 | 无正式用户入口。 | `KnowledgeSyncEnvelope` 和 policy 已定义 asset/cache/secret 边界。 | 缺 per-entity sync、冲突 Review UI、导出 manifest。 |

## 2. 已接入的用户路径

### 2.1 选中文本生成知识卡

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `知识卡`。
4. 系统创建 `KnowledgeCard(origin=selection)`，写入 `.knowledge/knowledge_cards_v1.json`。
5. 系统创建对应 `ReviewItem(sourceType=knowledge-card)`，写入 `.workflow/review_items_v1.json`。
6. 用户进入 `Settings -> AI -> Review inbox`，审核这张卡。
7. 用户可以批准、忽略、应用，并通过 SourceRef 跳回原文。

Gate：

- 卡片必须带 `bookId/cfi/jumpLink/sourceHash/createdAt`。
- 相同书籍、相同 CFI、相同选中文本重复点击，不制造重复卡。
- 空选中文本不写 store。
- 生成内容只进入 Review，不直接进入长期资产。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/selection_knowledge_card_producer_test.dart \
  test/widgets/context_menu/excerpt_menu_actions_test.dart \
  -r compact
```

### 2.2 一键开启研讨

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `研讨`。
4. 系统把当前 AI skill 切到 `seminar_mode`。
5. 系统打开 AI 面板，把选中文段放入 PaperTok AI Seminar 草稿。
6. 用户发送后，由现有 AI Chat streaming 执行多视角研讨提示。

Gate：

- 默认使用 current book 语境。
- 默认不开 web。
- 研讨结果不自动写 KnowledgeCard、Memory、Note 或 Sync asset。
- 当前入口必须保留降级路径：用户仍可用普通 `AI` 按钮解释选中文本。

验证命令：

```bash
flutter test --no-pub test/widgets/context_menu/excerpt_menu_actions_test.dart -r compact
```

## 3. 剩余用户入口任务

| TaskID | 状态 | Parent Capability | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| UFA-C01-T01 | In Review | Selection KnowledgeCard | 选中文本生成待审 KnowledgeCard。 | E00 SourceRef, E03 store, E05 ReviewItemStore | `SelectionKnowledgeCardProducer` | 已通过 producer 测试，重复点击不重复写入。 |
| UFA-C01-T02 | In Review | Selection KnowledgeCard | 阅读页选中菜单显示 `知识卡`。 | UFA-C01-T01, E07 menu | `ExcerptMenu` action, l10n keys | widget smoke 能看到 `Card/Seminar` 入口。 |
| UFA-C02-T01 | In Review | Seminar launcher | 阅读页选中菜单显示 `研讨`，打开 `seminar_mode` 草稿。 | AI Chat, `AiSkillRegistry` | `ExcerptMenu` action | 入口可见；不自动写用户资产。 |
| UFA-C02-T02 | Ready | Structured Seminar runtime UI | 把 `AiSeminarOrchestrationService` 接入真实模型流式事件。 | E01 services, E06 governance, E07 progress UI | Seminar session page/panel | 角色 turn、evidence、whiteboard、synthesis 可恢复；失败可重试或取消。 |
| UFA-C02-T03 | Ready | Seminar Review handoff | Seminar synthesis 和候选卡进入 Review Inbox。 | UFA-C02-T02, E05 controller | Seminar producer adapter | 只有 `readyForReview + traceable handoff` 的 synthesis 进入 pending Review。 |
| UFA-C03-T01 | Ready | Concept producer | 从 RAG/GraphRAG/KnowledgeCard 提取有证据的 ConceptNode/Edge 候选。 | E02, E03, E04 store | ConceptGraph producer adapter | 每个 node/edge 有 evidence 或 unavailable reason；写入为 draft。 |
| UFA-C03-T02 | Ready | Concept Explorer page | 提供局部图谱探索入口。 | UFA-C03-T01, E04 dossier/explore | Concept Explorer page/provider | 用户能打开概念页、看 1-2 层关系、跳回原文、检测 orphan/broken link。 |
| UFA-C03-T03 | Ready | Reader concept entry | 阅读页选中文本可进入概念探索。 | UFA-C03-T02 | `ExcerptMenu` graph action | 没有相关概念时展示空态和创建候选入口，不生成无证据正式节点。 |
| UFA-C04-T01 | Ready | Spaced Review | Review apply 后生成复习队列。 | E03, E05 | scheduler/store/page | 复习项可回溯到卡片和原文；删除书后显示可解释状态。 |
| UFA-C05-T01 | Ready | Sync / Export | 用户确认资产进入同步和导出入口。 | E08 policy | export manifest, conflict Review UI | API key 不同步；派生索引不当作 source-of-truth；冲突进入 Review。 |

## 4. Agent 执行约束

每个剩余任务必须使用 `02_agent_execution_model_zh.md` 的 Agent Task 模板，并附加这些约束：

- 阅读场景优先 current book；只有用户显式跨书或 evidence 不足时才查 library。
- 外发正文给 provider 必须经过现有 AI 功能开关或显式用户动作。
- 写入用户资产必须经过 Review 或用户确认。
- ConceptGraph 是派生层；用户确认过的关系才是用户资产。
- UI 入口要能在移动端触达，不把核心阅读内容遮住。
- 长任务必须有取消、失败提示、重启恢复或可重试路径。

## 5. Rescue Review 要点

执行完成前，reviewer/rescue agent 必须逐项检查：

- 入口是否真实可触发，而不是只写了文档。
- 生成的 KnowledgeCard、Seminar synthesis、ConceptNode、ConceptEdge 是否都有 SourceRef。
- Review Inbox 是否能解释每个待审项的来源和状态。
- 任何自动化输出是否越过 Review 写入了长期资产。
- 文档是否把未接入口的能力标成已可用。
- 测试是否覆盖重复点击、空输入、source 不可跳、provider 失败和取消路径。
