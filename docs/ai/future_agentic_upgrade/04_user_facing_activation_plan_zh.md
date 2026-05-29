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
| Review Inbox | `Settings -> AI -> Review inbox`，以及 Settings 顶层知识审核入口。 | 已接入 UI，可展示、批准、忽略、应用 KnowledgeCard、ConceptGraph relation 和 flashcard candidate 类型审批项；每个有证据的待审项会显示证据摘录、来源标题/位置、不可用来源原因和打开来源动作。 | 只有 producer 写入 `ReviewItemStore` 后，用户才会看到内容。 |
| 选中文本 -> KnowledgeCard | 阅读页选中文本 -> `知识卡`。 | 本分支已接入 `SelectionKnowledgeCardProducer` 和选中菜单入口，选中文本会进入 KnowledgeCard store 与 Review Inbox。 | 默认只进入 Review，不写长期记忆、不写笔记、不写 spaced review。 |
| 图片解析 -> KnowledgeCard | 阅读页点开图片 -> `AI Image Analysis / AI图片解析` -> `Card / 知识卡`。 | 本分支已接入 `ImageAnalysisKnowledgeCardProducer` 和图片解析结果弹层入口，解析结果会进入 KnowledgeCard store 与 Review Inbox。 | 默认只进入 Review，不写长期记忆、不写笔记、不写 spaced review；SourceRef 使用当前阅读位置的 book/cfi/href 回跳。 |
| 选中文本 -> AI Seminar | 阅读页选中文本 -> `研讨`，或 `Settings -> AI -> Seminar Mode / 研讨会模式`。 | 本分支已接入结构化 runtime：用户可启动 role-by-role Seminar，查看 evidence、角色输出、Shared Whiteboard、synthesis，并把 traceable synthesis、候选卡和候选 flashcard 送入 Review Inbox。 | 阅读页优先 current book evidence；Settings 独立入口没有 current book 时会走 library fallback。Seminar synthesis 本身只进入 Review，不自动应用；候选卡和候选 flashcard 仍需用户在 Review Inbox 中批准/应用后才成为长期资产或复习项。 |
| AI Chat 普通解释 -> KnowledgeCard | 阅读页选中文本 -> `AI` -> 等回答完成 -> 回答旁 `知识卡`。 | 本分支已接入 `AiChatKnowledgeCardProducer` 和回答旁显性 `知识卡` action；回答旁显示 `可跳转来源` 或 `已标记不可用` 来源状态，tooltip 解释是否能跳回原文；选中文本进入 AI 草稿时会带上精确 reader SourceRef，并随 `conversationV2` 历史持久化，点击后写入 KnowledgeCard store 与 Review Inbox；reader-grounded card 会带保守 `conceptRefs`。 | 必须用户显式点击；不会在回答生成时直接写 KnowledgeCard 或 ConceptGraph；如果用户把预填草稿改成不包含原选中文本或 SourceRef snippet 的无关问题，本轮 user node 不保存旧 reader SourceRef；短公共片段只靠碰巧包含不会保留精确 reader grounding；用户在 Review Inbox 中 Apply 后，带 `conceptRefs` 的 reader-grounded AI Chat card 才会生成 draft ConceptGraph relation 和 pending relation ReviewItem；纯聊天 card 不生成 `conceptRefs`；没有持久化 reader SourceRef 的旧历史只保留 conversation provenance，不用当前阅读位置伪造 reader grounding。 |
| ConceptGraph / WikiLinks Explorer | `Settings -> AI -> Concept graph / 概念图谱`，或阅读页选中文本 -> `图谱/Graph`。 | 本分支已接入 Explorer、选中文本入口、KnowledgeCard -> draft ConceptGraph producer、Seminar candidate card -> conceptRefs -> KnowledgeCard -> ConceptGraph 候选链路、reader-grounded AI Chat card -> conceptRefs -> KnowledgeCard -> ConceptGraph 候选链路，以及空态 `Create draft candidate` 显性 action：可列出现有概念、按选中文本筛选相关概念、打开 dossier、查看局部图谱摘要、局部路径、draft/formal 状态、evidence 状态和 orphan/broken link，并可把 derived RAG/GraphRAG result 写成待审图谱候选。 | 只有 `applied + traceable + conceptRefs` 的 KnowledgeCard，或带 `derivedLayer/derivedSummary + traceable chunk SourceRef` 的 library RAG result，会生成 draft node/edge 和 pending relation ReviewItem；空态草稿入口使用本地文本检索，关闭 query embedding、vector fallback 和 rerank；AI Chat 不直接调用 RAG/GraphRAG producer，不自动创建正式节点。 |
| RAG/GraphRAG -> KnowledgeCard | 阅读页选中文本 -> `图谱/Graph` -> 无相关概念空态 -> `Card / 知识卡`。 | 本分支已接入 `RagEvidenceKnowledgeCardProducer` 和 ConceptGraph 空态 Card action；本地 RAG/GraphRAG 结果可进入 KnowledgeCard store 与 Review Inbox。 | 只接受带 traceable chunk SourceRef 和可保存 chunk snippet 的 RAG evidence；derived summary 只作为 explanation，正式 quote/evidence 使用书内 chunk snippet；不自动写图谱、长期记忆、笔记或 spaced review。 |
| Spaced Review | `Settings -> AI -> Spaced review / 间隔复习`；KnowledgeCard 或 Seminar 候选 flashcard 在 Review Inbox 中 `Apply` 后入队。 | 本分支已接入 `.knowledge/spaced_review_items_v1.json`、复习页、证据摘录预览、Again/Hard/Good/Easy 评分、来源跳转状态；Seminar 的 `reviewSuggestion` 会作为 flashcard candidate 进入 Review。 | KnowledgeCard apply 和 flashcard candidate apply 已接入；跨设备同步还没接。 |
| Sync / Export 知识资产 | `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。 | 本分支已接入安全 manifest 预览、Markdown 学习导出、HTML study report、Anki TSV 导出和创建入口；只纳入已应用 KnowledgeCard 和复习历史，显性显示排除项和待审冲突。 | 目前是本地 manifest + Markdown + HTML study report + Anki TSV 导出入口，不是完整云同步引擎；per-entity remote sync 和冲突 Review UI 仍在剩余任务中。 |

## 2. 已接入的用户路径

### 2.1 选中文本生成知识卡

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `知识卡`。
4. 系统创建 `KnowledgeCard(origin=selection)`，写入 `.knowledge/knowledge_cards_v1.json`。
5. 系统创建对应 `ReviewItem(sourceType=knowledge-card)`，写入 `.workflow/review_items_v1.json`。
6. 用户进入 `Settings -> AI -> Review inbox`，审核这张卡。
7. 用户可以先查看证据摘录、来源标题/位置和不可用来源原因，再批准、忽略、应用，并通过 SourceRef 跳回原文。

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
4. 系统进入 `AiSeminarRuntimePage`，并把选中文段预填为 Seminar question。
5. 用户点击 `Start Seminar`。
6. 系统先取 evidence：阅读页入口优先 current book；Settings 独立入口没有 current book 时使用 library fallback。
7. 系统按 `critical -> supportive -> synthesizer` 串行执行角色，页面展示 role turn、evidence、Shared Whiteboard 和 synthesis。
8. 用户可以取消运行；失败或证据不足时可以重试。
9. synthesis 满足 `readyForReview + traceable handoff` 后，用户点击 `Send to Review`。
10. 系统把 Seminar synthesis 写成 pending ReviewItem，把候选卡写成 pending KnowledgeCard + ReviewItem，把 `reviewSuggestion` 写成 pending flashcard ReviewItem。

Gate：

- 默认使用 current book 语境。
- 默认不开 web。
- 研讨结果不自动写 KnowledgeCard、Memory、Note 或 Sync asset。
- synthesis、候选卡和候选 flashcard 只进入 Review；用户必须在 Review Inbox 中批准或应用，才会进入长期知识资产或复习队列。
- 当前入口必须保留降级路径：用户仍可用普通 `AI` 按钮解释选中文本。

验证命令：

```bash
flutter test --no-pub \
  test/service/ai/ai_seminar_runtime_service_test.dart \
  test/providers/ai_seminar_runtime_test.dart \
  test/page/settings_page/ai_seminar_runtime_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  test/widgets/context_menu/excerpt_menu_actions_test.dart \
  -r compact
```

### 2.3 AI Chat 回答生成知识卡

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `AI`。
4. AI 面板打开，并把选中文本放入草稿；如果用户发送的草稿仍包含原选中文本或 SourceRef snippet，系统把本轮草稿的 reader SourceRef 写入会话树用户节点，随 `conversationV2` 历史保存。
5. 用户发送问题并等待回答完成。
6. 用户查看回答气泡旁边的来源状态：`可跳转来源` 表示卡片会带 reader source；`已标记不可用` 表示只保留 conversation provenance，不能跳回原文。
7. 用户点击回答气泡旁边的 `知识卡`。
8. 系统创建 `KnowledgeCard(origin=ai-chat)`，写入 `.knowledge/knowledge_cards_v1.json`。
9. 系统创建对应 `ReviewItem(sourceType=knowledge-card)`，写入 `.workflow/review_items_v1.json`。
10. 用户进入 `Settings -> AI -> Review inbox`，审核这张卡。
11. 用户可以批准、忽略、应用；有 reader SourceRef 时可跳回原文，没有 reader SourceRef 时仍保留 conversation provenance 和不可跳原因。
12. 如果这张卡有 reader grounding 和保守 `conceptRefs`，用户 `Apply` 后系统会创建 draft ConceptGraph node/edge 和 pending relation ReviewItem；relation 仍需再次 Review。

Gate：

- 入口必须是回答完成后的用户显式 `知识卡` 点击；streaming 中按钮不可用。
- 回答旁必须显示来源状态：有 reader grounding 或有效当前阅读位置 fallback（`bookId + cfi`）时显示可跳转；旧历史、没有 reader source 或当前阅读位置缺少可保存锚点时显示已标记不可用，并通过 tooltip 说明不能跳回原文。
- 从选中文本打开 AI 时，KnowledgeCard 必须优先使用该选中文本的 reader SourceRef。
- 如果用户把预填草稿改成不包含原选中文本或 SourceRef snippet 的无关问题，本轮 user node 不得保存旧 reader SourceRef，回答旁 `知识卡` 只能使用 conversation provenance 或显式持久化的新 reader SourceRef。
- 短公共片段不能只因为被改写后的问题碰巧包含就保留精确 reader SourceRef；短片段只有发送内容等于该片段本身时才保留。
- 选中文本 reader SourceRef 必须随 `conversationV2` 保存；历史重载后回答旁 `知识卡` 仍优先使用原始 reader SourceRef。
- 没有 reader SourceRef 的普通聊天也必须保留 conversation SourceRef 和不可跳原因；从历史加载且没有持久化 reader SourceRef 的会话不能使用当前阅读位置 fallback。
- 只有 reader-grounded AI Chat card 能生成保守 `conceptRefs`；纯聊天 card 的 `conceptRefs` 必须为空。
- 空回答不写 store。
- 长回答在写入 KnowledgeCard、SourceRef 和 ReviewItem payload 前必须裁剪。
- 重复点击同一 conversation/message/prompt/answer 不制造重复卡。
- 本入口不调用额外 LLM、embedding、rerank 或 web provider；只保存当前已有回答。
- Producer 只写 pending KnowledgeCard 和 pending ReviewItem，不直接写 ConceptGraph、长期记忆、笔记或 spaced review；ConceptGraph 候选只能由 Review apply 后的 `ReviewInboxController -> ConceptGraphProducer` 生成。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/ai_chat_knowledge_card_producer_test.dart \
  test/ai_chat_stream_knowledge_card_test.dart \
  -r compact
```

### 2.4 图片解析生成知识卡

用户路径：

1. 打开一本书。
2. 点开正文中的图片。
3. 点击图片工具栏里的 `AI Image Analysis / AI图片解析`。
4. 等待图片解析结果出现在弹层中。
5. 点击弹层里的 `Card / 知识卡`。
6. 系统创建 `KnowledgeCard(origin=image-analysis)`，写入 `.knowledge/knowledge_cards_v1.json`。
7. 系统创建对应 `ReviewItem(sourceType=knowledge-card)`，写入 `.workflow/review_items_v1.json`。
8. 用户进入 `Settings -> AI -> Review inbox`，审核这张卡。
9. 用户可以批准、忽略、应用，并通过 SourceRef 跳回图片所在阅读位置。

Gate：

- 图片解析结果必须由用户显式点击 `Card / 知识卡` 后才写入。
- 卡片必须带当前阅读位置的 `bookId/cfi/href/jumpLink/sourceHash/createdAt`。
- 相同书籍、相同阅读锚点、相同图片上下文和相同解析结果重复点击，不制造重复卡。
- 图片解析结果只进入 Review，不直接进入长期资产、笔记或 spaced review。
- 图片本身不写入 knowledge card payload；SourceRef 只保存裁剪后的图片上下文、alt/title 和当前阅读锚点。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/image_analysis_knowledge_card_producer_test.dart \
  test/page/book_player/image_viewer_test.dart \
  -r compact
```

### 2.5 概念图谱探索

用户路径：

1. 用户先在 Review Inbox 中 `Apply` 一个带 `conceptRefs` 和可追踪 SourceRef 的 KnowledgeCard。
2. 系统创建 card node、concept node 和 `appears_in` edge，全部保持 draft ownership。
3. 系统为每条 relation 创建 `ReviewItem(sourceType=concept-graph-relation, status=pending)`。
4. 用户在 Review Inbox 中审核这些 relation；只有 relation 被 `Apply` 后，edge 才升级为正式图谱关系。
5. 用户进入 `Settings -> AI -> Concept graph / 概念图谱`，或在阅读页选中文本后点击 `图谱/Graph`。
6. 系统列出 `ConceptGraphStore` 中已有概念节点；从阅读页进入时，会先按选中文本筛选相关概念。
7. 用户点一个概念。
8. 页面显示该概念的定义、来源证据、局部图谱摘要、局部路径和可回溯关联；局部图谱摘要会标出中心概念、直接关系、二跳节点、evidence link 数量和 draft/formal 状态。
9. 页面显示 orphan node / broken edge 计数，用于发现悬空图谱关系。
10. 有可跳转 SourceRef 时，用户可以点 `Open source / 打开来源` 回到原文。
11. 如果选中文本没有匹配到已有概念，页面展示空态和 `Create draft candidate / 创建草稿候选` 入口。
12. 当 Seminar candidate card 或 reader-grounded AI Chat card 带有 `conceptRefs` 时，用户在 Review Inbox 中应用该 KnowledgeCard 后，系统复用同一 producer 创建 draft 概念节点、draft card 关系和 pending relation ReviewItem。
13. 用户点击 `Create draft candidate` 后，系统执行本地文本 library RAG search，并关闭 query embedding、vector fallback、rerank；只有 search result 带 `derivedLayer/derivedSummary` 且有 traceable chunk SourceRef 时，才通过 producer 创建 draft 概念节点、draft RAG claim 节点和 pending relation ReviewItem。

Gate：

- 只有 `applied + user asset + traceable + conceptRefs` 的 KnowledgeCard 会触发 producer。
- 只有带 `derivedLayer/derivedSummary` 且 SourceRef 可追踪到书内 chunk 的 library RAG result 会触发 RAG/GraphRAG producer。
- Producer 只写 draft node/edge 和 pending relation ReviewItem；正式 relation 必须经过 Review apply。
- 没有 `conceptRefs` 的 KnowledgeCard 不制造图谱噪声。
- 普通 RAG 命中不制造 ConceptGraph 节点；GraphRAG/RAPTOR summary 只作为 derived summary，正式 evidence snippet 必须来自书内 chunk SourceRef。
- Seminar candidate card 和 reader-grounded AI Chat card 的 `conceptRefs` 必须先随 KnowledgeCard 进入 Review；只有用户 Apply 后才会生成图谱候选关系。
- Producer 失败不回滚 KnowledgeCard apply 或 spaced review 入队。
- 只展示已有图谱数据，不把 AI 推断直接变成用户确认关系。
- 局部路径只使用有 evidence 的边。
- broken link / orphan node 必须显性可见。
- 没有图谱数据时展示空态，而不是制造无证据节点。
- 阅读页 `图谱/Graph` 入口不自动调用 LLM、embedding、rerank 或 web provider，不外发正文，不写正式 `ConceptGraphStore` 资产；用户点击 `Create draft candidate` 时只执行关闭 query embedding、vector fallback、rerank 的本地文本 library RAG search 和 draft/pending 写入。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/concept_graph_producer_test.dart \
  test/service/review/review_inbox_controller_test.dart \
  test/providers/concept_graph_explorer_test.dart \
  test/page/settings_page/concept_graph_explorer_page_test.dart \
  test/widgets/context_menu/excerpt_menu_actions_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.6 RAG / GraphRAG 结果生成知识卡

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `图谱/Graph`。
4. 如果没有匹配到已有概念，页面展示空态。
5. 用户点击空态里的 `Card / 知识卡`。
6. 系统执行本地文本 library RAG search，并关闭 query embedding、vector fallback、rerank。
7. 系统只从带 traceable chunk SourceRef 的 RAG evidence 创建 `KnowledgeCard(origin=rag-evidence)`。
8. 系统创建对应 `ReviewItem(sourceType=knowledge-card)`。
9. 用户进入 `Settings -> AI -> Review inbox` 审核这张卡。
10. 用户可以批准、忽略、应用，并通过 SourceRef 跳回原文 chunk。

Gate：

- 入口必须是用户显式点击 `Card / 知识卡`。
- 本入口不调用 LLM、embedding、rerank 或 web provider，不外发正文。
- 只有 `SourceRef.hasDerivedChunkHint`、可追踪回书内 chunk、且带可保存 chunk snippet 的 evidence 能进入卡片。
- `derivedSummary` 只作为 explanation，不作为 formal evidence snippet；quote 使用书内 chunk snippet。
- Producer 只写 pending KnowledgeCard 和 pending ReviewItem，不写 ConceptGraph node/edge、Memory、Note 或 Spaced Review。
- 重复点击同一 query 和同一 evidence 不制造重复卡。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/rag_evidence_knowledge_card_producer_test.dart \
  test/providers/concept_graph_explorer_test.dart \
  test/page/settings_page/concept_graph_explorer_page_test.dart \
  -r compact
```

### 2.7 间隔复习

用户路径：

1. 阅读页选中文本生成 `KnowledgeCard`，Seminar 生成 `reviewSuggestion`，或其他 producer 写入待审知识卡/复习卡。
2. 用户进入 `Settings -> AI -> Review inbox`。
3. 用户先批准，再点击 `Apply`。
4. 系统把已应用且有 SourceRef 的 KnowledgeCard 或 flashcard candidate 写入 `.knowledge/spaced_review_items_v1.json`。
5. 用户进入 `Settings -> AI -> Spaced review / 间隔复习`。
6. 页面刷新时会对账已应用 KnowledgeCard，补齐缺失的复习队列项。
7. 页面显示到期复习项、答案、证据摘录、来源标题/位置、可跳转来源、不可用来源和未解析来源计数。
8. 用户点击 `Again / Hard / Good / Easy` 后，系统记录复习历史并更新下一次到期时间。

Gate：

- 只有 `applied + traceable + user asset` 的 KnowledgeCard，或 `applied + traceable + flashcard candidate`，能进入复习队列。
- 同一 KnowledgeCard 或同一 flashcard candidate 重复入队不会制造重复复习项。
- 如果 KnowledgeCard Review apply 已成功但队列写入曾失败，复习页刷新会按已应用 KnowledgeCard 对账恢复；flashcard candidate 需要重新 Apply 或由后续对账任务补齐。
- 复习项必须保留 SourceRef；证据摘录、来源位置、可跳转、不可用、未解析来源都要显性展示。
- 复习记录只更新 spaced review 队列，不写长期记忆、不写笔记、不写同步资产。
- 删除书或恢复备份导致来源不可跳时，页面显示不可用或未解析状态，而不是静默丢失。

验证命令：

```bash
flutter test --no-pub \
  test/service/review/spaced_review_store_test.dart \
  test/service/review/review_inbox_controller_test.dart \
  test/providers/spaced_review_test.dart \
  test/page/settings_page/spaced_review_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.8 知识同步 / 导出

用户路径：

1. 用户先在 Review Inbox 中 `Apply` KnowledgeCard，或完成间隔复习记录。
2. 用户进入 `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。
3. 页面展示本次默认纳入的知识资产数量、默认排除项数量和待审冲突数量。
4. 用户可以刷新计划，确认哪些 envelope 会进入导出，哪些因草稿、派生缓存、密钥或冲突被排除。
5. 用户点击 `Create export / 创建导出`。
6. 系统写入 `.knowledge/knowledge_export_manifest_v1.json`，其中只包含安全的实体 ID、格式、时间戳和裁剪后的 SourceRef 引用。
7. 系统同时写入 `.knowledge/knowledge_export_v1.md`，作为可阅读的 Markdown 学习导出，只包含已纳入资产、裁剪后的证据片段和可跳转来源。
8. 系统同时写入 `.knowledge/knowledge_export_study_report.html`，作为可打开的本地 HTML 学习报告；页面不加载外部资源、不执行同步，只展示已纳入资产、裁剪后的证据片段和可跳转来源。
9. 系统同时写入 `.knowledge/knowledge_export_anki.tsv`，作为 Anki 兼容 TSV；Front/Back/Source 只来自默认纳入资产、裁剪后的证据片段和可跳转来源。

Gate：

- 默认只纳入 `applied + user asset` 的 KnowledgeCard 和 review history。
- `ai-draft`、`derived-index`、包含 API key/token/secret/auth/authorization/bearer/private-key/credential/password 的 payload 默认排除。
- 待审冲突显示为排除项，不进入 manifest。
- manifest 不写 `ai_index.db`，不把派生索引当作 source-of-truth。
- SourceRef 文本片段必须使用现有裁剪规则，不导出无限正文。
- Markdown 导出只能读取默认纳入资产；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 Markdown 正文。
- HTML study report 只能读取默认纳入资产；正文和链接属性必须转义，不加载远端脚本、图片、样式或 provider 内容；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 HTML 正文。
- Anki TSV 导出只能读取默认纳入资产；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 TSV 正文；TSV 字段必须清理制表符和换行，避免破坏导入结构。
- 当前入口创建本地 manifest、Markdown 学习导出、HTML study report 和 Anki TSV；不执行远端上传、不解决冲突、不自动同步备份。

验证命令：

```bash
flutter test --no-pub \
  test/models/knowledge_sync_test.dart \
  test/service/sync/knowledge_asset_export_service_test.dart \
  test/providers/knowledge_asset_export_test.dart \
  test/page/settings_page/knowledge_asset_export_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

## 3. 剩余用户入口任务

| TaskID | 状态 | Parent Capability | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| UFA-C01-T01 | In Review | Selection KnowledgeCard | 选中文本生成待审 KnowledgeCard。 | E00 SourceRef, E03 store, E05 ReviewItemStore | `SelectionKnowledgeCardProducer` | 已通过 producer 测试，重复点击不重复写入。 |
| UFA-C01-T02 | In Review | Selection KnowledgeCard | 阅读页选中菜单显示 `知识卡`。 | UFA-C01-T01, E07 menu | `ExcerptMenu` action, l10n keys | widget smoke 能看到 `Card/Seminar` 入口。 |
| UFA-C01-T03 | In Review | Image Analysis KnowledgeCard | 图片解析结果生成待审 KnowledgeCard。 | E00 SourceRef, E03 store, E05 ReviewItemStore, E07 image analysis sheet | `ImageAnalysisKnowledgeCardProducer`, `AiImageAnalysisSheet` Card action | 图片解析结果弹层显示 `Card` 入口；点击后写 pending KnowledgeCard 和 pending ReviewItem；重复点击不制造重复卡；不自动写长期资产。 |
| UFA-C01-T04 | In Review | RAG Evidence KnowledgeCard | 本地 RAG/GraphRAG evidence 生成待审 KnowledgeCard。 | E00 SourceRef, E02 RAG evidence, E03 store, E05 ReviewItemStore, E07 ConceptGraph empty state | `RagEvidenceKnowledgeCardProducer`, `ConceptGraphExplorerNotifier.createKnowledgeCardFromLibrarySearch`, 空态 `Card` action | 只有 traceable chunk SourceRef 且带可保存 chunk snippet 的 RAG evidence 能写 pending KnowledgeCard 和 pending ReviewItem；derived summary 不替代书内 chunk evidence；不写正式图谱或长期资产。 |
| UFA-C01-T05 | In Review | AI Chat KnowledgeCard | AI Chat 回答显式生成待审 KnowledgeCard。 | E00 SourceRef, E03 store, E05 ReviewItemStore, E07 AI Chat message action | `AiChatKnowledgeCardProducer`, `AiChatStream` 回答旁 `知识卡` action, answer-side source status chip, `ExcerptMenu` AI sourceRef handoff, `conversationV2` user-node SourceRef persistence | 回答完成后才可点击 `知识卡`；回答旁显示可跳转或不可用来源状态；选中文本进入 AI 草稿且发送内容仍包含原选中文本或 SourceRef snippet 时，才保留并持久化精确 reader SourceRef；历史重载后 `知识卡` 仍优先使用原始 reader SourceRef；无关改写不保存旧 reader SourceRef；短公共片段碰巧命中不保存旧 reader SourceRef；reader-grounded card 带保守 `conceptRefs`，纯聊天 card 不带；重复点击不制造重复卡；不直接写 ConceptGraph、长期记忆、笔记或 spaced review。 |
| UFA-C02-T01 | In Review | Seminar launcher | 阅读页选中菜单显示 `研讨`，打开结构化 Seminar runtime page。 | AI Seminar runtime, E07 menu | `ExcerptMenu` action | 入口可见；选中文本预填；不自动写用户资产。 |
| UFA-C02-T02 | In Review | Structured Seminar runtime UI | 把 `AiSeminarOrchestrationService` 接入真实模型流式事件。 | E01 services, E06 governance, E07 progress UI | `AiSeminarRuntimeService`、`aiSeminarRuntimeProvider`、`AiSeminarRuntimePage` | 角色 turn、evidence、whiteboard、synthesis 进入可序列化 runtime state；失败可重试，运行可取消。 |
| UFA-C02-T03 | In Review | Seminar Review handoff | Seminar synthesis 和候选卡进入 Review Inbox。 | UFA-C02-T02, E05 controller | `AiSeminarRuntimeNotifier.sendToReview` + `SeminarSynthesisReviewAdapter` | 只有 `readyForReview + traceable handoff` 的 synthesis 进入 pending Review；候选卡保持 AI draft/pending，不直接应用。 |
| UFA-C02-T04 | In Review | Seminar Flashcard handoff | Seminar reviewSuggestion 进入 flashcard Review。 | UFA-C02-T03, UFA-C04-T01 | `SeminarSynthesisReviewAdapter.flashcardsFromSynthesis`, `FlashcardReviewAdapter`, `ReviewInboxController` | 只有 traceable synthesis 的 candidate review question 会生成 pending flashcard；用户 Apply 后进入 Spaced Review；不绕过 Review。 |
| UFA-C03-T01 | In Review | Concept producer | 从 KnowledgeCard、Seminar candidate concept refs、reader-grounded AI Chat concept refs 和 derived RAG/GraphRAG search result 提取有证据的 ConceptNode/Edge 候选。 | E03, E04 store, E05 controller, UFA-C01-T05, UFA-C02-T03, E02 SourceRef evidence | `ConceptGraphProducer`, ReviewInboxController apply hook, Seminar candidate `conceptRefs` handoff, AI Chat card `conceptRefs` handoff, `createFromLibrarySearchResult`, `ConceptGraphExplorerNotifier.createDraftCandidateFromLibrarySearch` | 只有 `applied + traceable + conceptRefs` 的 KnowledgeCard，或 `derivedLayer/derivedSummary + traceable chunk SourceRef` 的 library RAG result，生成 draft node/edge；Seminar candidate card 和 reader-grounded AI Chat card 可携带 conceptRefs 并在用户 Apply 后进入同一链路；relation 进入 pending Review；ConceptGraph 空态显性 action 已接。 |
| UFA-C03-T02 | In Review | Concept Explorer page | 提供局部图谱探索入口。 | E04 dossier/explore | `ConceptGraphExplorerPage`, provider, Settings AI entry, local graph map summary | 用户能打开概念页、看中心概念、直接关系、二跳节点、evidence link 数量、draft/formal 状态、局部路径、原文跳转和 orphan/broken link。 |
| UFA-C03-T03 | In Review | Reader concept entry | 阅读页选中文本可进入概念探索。 | UFA-C03-T02 | `ExcerptMenu` graph action, `ConceptGraphExplorerPage.initialQuery` | 选中文本可打开图谱页并筛选相关概念；没有相关概念时展示空态和草稿候选入口，不生成无证据正式节点。 |
| UFA-C04-T01 | In Review | Spaced Review | Review apply 后生成复习队列。 | E03, E05 | `SpacedReviewStore`, `spacedReviewProvider`, `SpacedReviewPage`, `SourceRefEvidenceList`, Settings AI entry | 复习项可回溯到卡片和原文；页面显示证据摘录和不可用来源原因；删除书后显示可解释状态；评分记录下一次到期时间。 |
| UFA-C04-T02 | In Review | Flashcard Review apply | 待审 flashcard 应用后进入 Spaced Review。 | E05 controller, UFA-C02-T04 | `SpacedReviewStore.reviewIdForFlashcard`, `upsertFromFlashcardReviewItem` | pending/approved flashcard 不直接入队；只有 applied 且 traceable 才能入队；重复入队不制造重复复习项。 |
| UFA-C05-T01 | In Review | Sync / Export | 用户确认资产进入同步和导出入口。 | E08 policy | `KnowledgeAssetExportService`、`knowledgeAssetExportProvider`、`KnowledgeAssetExportPage`、Settings AI entry、export manifest、Markdown export、HTML study report、Anki TSV export | API key 不同步；派生索引不当作 source-of-truth；冲突被排除并显性显示；当前创建本地 manifest、Markdown 学习导出、HTML study report 和 Anki TSV，不执行远端同步。 |

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
