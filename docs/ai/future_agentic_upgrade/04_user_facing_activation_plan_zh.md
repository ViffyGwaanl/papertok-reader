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
| 图片解析 -> KnowledgeCard | 阅读页点开图片 -> `AI Image Analysis / AI图片解析` -> `Card / 知识卡`。 | 本分支已接入 `ImageAnalysisKnowledgeCardProducer`、图片解析结果弹层入口和 ImageViewer 工具栏点击级路径，解析结果会进入 KnowledgeCard store 与 Review Inbox。 | 默认只进入 Review，不写长期记忆、不写笔记、不写 spaced review；SourceRef 使用当前阅读位置的 book/cfi/href 回跳；图片本体不写入 card payload。 |
| 选中文本 -> AI Seminar | 阅读页选中文本 -> `研讨`，或 `Settings -> AI -> Seminar Mode / 研讨会模式`。 | 本分支已接入结构化 runtime：用户可启动 role-by-role Seminar，查看 evidence、角色输出、Shared Whiteboard、synthesis，并把 traceable synthesis、候选卡和候选 flashcard 送入 Review Inbox；Seminar 页面会在启动前显示 `Provider readiness`，列出当前 provider、model、context/max output、Tools/Vision/Thinking 能力、Streaming 状态未知提示和成本状态；角色完成后优先显示 provider 返回的 `Provider reported usage`，没有 provider usage metadata 时显示 `Local token estimate`、input/output 估算和 `Provider billing may differ` 提示；页面提供本地 `Role output token budget`、`Run token budget`，当 provider capability cache 带 pricing metadata 时还启用估算 `Run cost cap USD`；页面可在同一书籍/同一入口问题恢复本机保存的 completed/cancelled/failed Seminar state，并显示 `Recovered local Seminar state`。 | 阅读页优先 current book evidence；Settings 独立入口没有 current book 时会走 library fallback。Seminar synthesis 本身只进入 Review，不自动应用；候选卡和候选 flashcard 仍需用户在 Review Inbox 中批准/应用后才成为长期资产或复习项；provider readiness 只读本地 Provider Center 配置和 capability cache，不记录 API key；provider token usage 只表示 provider/SDK 回传的 token metadata；估算美元成本来自 pricing metadata 与 token usage，不等于真实 provider 发票；缺少 pricing metadata 时继续显示成本未知原因且禁用美元 cap；重启前仍在 running 的 Seminar 只恢复为 interrupted/retryable，不伪装继续后台生成；换书或换选区打开 Seminar 会丢弃旧 runtime/cache，不显示不属于当前入口的旧研讨。 |
| AI Chat 普通解释 -> KnowledgeCard | 阅读页选中文本 -> `AI` -> 等回答完成 -> 回答旁 `知识卡`。 | 本分支已接入 `AiChatKnowledgeCardProducer` 和回答旁显性 `知识卡` action；streaming 中 `知识卡` 按钮禁用且不会调用 producer；回答旁显示 `可跳转来源` 或 `已标记不可用` 来源状态，tooltip 解释是否能跳回原文；选中文本进入 AI 草稿时会带上精确 reader SourceRef，并随 `conversationV2` 历史持久化，点击后写入 KnowledgeCard store 与 Review Inbox；reader-grounded card 会带保守 `conceptRefs`。 | 必须用户显式点击；不会在回答生成时直接写 KnowledgeCard 或 ConceptGraph；如果用户把预填草稿改成不包含原选中文本或 SourceRef snippet 的无关问题，本轮 user node 不保存旧 reader SourceRef；短公共片段只靠碰巧包含不会保留精确 reader grounding；用户在 Review Inbox 中 Apply 后，带 `conceptRefs` 的 reader-grounded AI Chat card 才会生成 draft ConceptGraph relation 和 pending relation ReviewItem；纯聊天 card 不生成 `conceptRefs`；没有持久化 reader SourceRef 的旧历史只保留 conversation provenance，不用当前阅读位置伪造 reader grounding。 |
| AI Chat -> Memory 候选审核 | AI Chat 回答旁 `Memory actions` -> `Add to Review inbox` -> `Settings -> AI -> Review inbox`。 | 本分支已接入 MemoryCandidate 到统一 ReviewItem 的 handoff、Memory source-specific apply/dismiss adapter 和 Review Inbox Apply UI。 | Memory 候选必须经用户批准和应用；Apply 先追加到目标 daily/long-term Markdown，再推进 ReviewItem；Dismiss 不写 memory；无书内跳转的 conversation memory 会显示证据摘录和不可跳原因；不写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。 |
| Memory 独立浏览 SourceRef 审计 | 首页底部 `Memory / 记忆` tab 打开 daily/long-term memory 列表，再进入条目详情；该 tab 默认隐藏，可先到 `Settings -> Home navigation / 首页导航` 打开。 | 本分支已接入 `MemoryEntrySourceRefAdapter`、Memory home row source audit chips、Memory detail `SourceRefEvidenceList` 和 `Open source` action；只从已应用 MemoryCandidate 只读投影 SourceRef，按目标文档与条目 body 匹配，long-term `MEMORY.md` 按 H1 分段 body 匹配。 | 匹配只认实际写入 memory 的 `text/displayText`，不能只靠 summary 命中；不往 Markdown memory 写隐藏来源字段；没有 book anchor 的 conversation memory 只显示 unavailable/unresolved；可跳来源只使用合法 `paperreader://reader/open?...`；long-term H1 分段不能被批量删除/打标签，避免误操作整份 `MEMORY.md`；浏览页不创建 KnowledgeCard、ReviewItem、ConceptGraph、SpacedReview、Sync 或 Note。 |
| 旧划线/笔记 SourceRef 审计 | 书籍笔记列表或搜索结果里的笔记条目。 | 本分支已接入 `BookNoteSourceRefAdapter`、`BookNoteTile` source audit、`SourceRefEvidenceList` 和 `PaperReaderSourceJumpAudit`；条目显示 Evidence、可跳转/不可跳状态、来源书名/章节和不可跳原因。 | 有有效 `bookId + cfi` 的条目保持原文跳转；无有效 book anchor 的旧条目点击时显示不可跳原因，不调用阅读页空 CFI 或无效 book anchor 跳转；不写 KnowledgeCard、ReviewItem、Memory、ConceptGraph、SpacedReview 或 Sync。 |
| Custom Skill 导入 | `Settings -> AI -> Custom skills` 粘贴 governed JSON -> `Import skill`，再到 `Active Skill` 选择启用后的自定义 skill。 | 本分支已接入导入页面、`CustomSkillStore`、Settings 入口、`AiSkillRegistry` 合并和 LangChain runtime 工具收窄。 | 只接受 `CustomSkillContract(schemaVersion=1)`；unsafe JSON 不落库、不激活；禁用 skill 不进入 Active Skill 列表；运行时只保留自定义 skill 声明过、当前 scene 可用、permission matrix 允许的只读工具；custom skill 激活时不加载 MCP 工具。 |
| ConceptGraph / WikiLinks Explorer | `Settings -> AI -> Concept graph / 概念图谱`，或阅读页选中文本 -> `图谱/Graph`。 | 本分支已接入 Explorer、Settings 点击入口、选中文本入口、KnowledgeCard -> draft ConceptGraph producer、Seminar candidate card -> conceptRefs -> KnowledgeCard -> ConceptGraph 候选链路、reader-grounded AI Chat card -> conceptRefs -> KnowledgeCard -> ConceptGraph 候选链路，以及空态 `Create draft candidate` 显性 action：可列出现有概念、按选中文本筛选相关概念、打开 dossier、查看局部图谱摘要、局部路径、draft/formal 状态、evidence 状态和 orphan/broken link，并可把 derived RAG/GraphRAG result 写成待审图谱候选；空态动作会显示已进入 Review 或跳过原因。 | 只有 `applied + traceable + conceptRefs` 的 KnowledgeCard，或带 `derivedLayer/derivedSummary + traceable chunk SourceRef` 的 library RAG result，会生成 draft node/edge 和 pending relation ReviewItem；空态草稿入口使用本地文本检索，关闭 query embedding、vector fallback 和 rerank；AI Chat 不直接调用 RAG/GraphRAG producer，不自动创建正式节点。 |
| RAG/GraphRAG -> KnowledgeCard | 阅读页选中文本 -> `图谱/Graph` -> 无相关概念空态 -> `Card / 知识卡`。 | 本分支已接入 `RagEvidenceKnowledgeCardProducer` 和 ConceptGraph 空态 Card action；本地 RAG/GraphRAG 结果可进入 KnowledgeCard store 与 Review Inbox；写入后页面会提示已加入 Review inbox。 | 只接受带 traceable chunk SourceRef 和可保存 chunk snippet 的 RAG evidence；derived summary 只作为 explanation，正式 quote/evidence 使用书内 chunk snippet；不自动写图谱、长期记忆、笔记或 spaced review。 |
| Spaced Review | `Settings -> AI -> Spaced review / 间隔复习`；KnowledgeCard 或 Seminar 候选 flashcard 在 Review Inbox 中 `Apply` 后入队。 | 本分支已接入 Settings 点击入口、`.knowledge/spaced_review_items_v1.json`、复习页、证据摘录预览、Again/Hard/Good/Easy 评分、来源跳转状态；Seminar 的 `reviewSuggestion` 会作为 flashcard candidate 进入 Review，并可由 Review Inbox Apply UI 应用到 Spaced Review。 | KnowledgeCard apply 和 flashcard candidate apply 已接入；跨设备同步还没接。 |
| Sync / Export / Remote Preview 知识资产 | `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。 | 本分支已接入安全 manifest 预览、Markdown 学习导出、HTML study report、Anki TSV 导出、机器可读 sync bundle、创建入口、远端同步状态面板、`Send conflicts to Review` 冲突 handoff、`Preview remote sync` 远端 bundle 预览、`Send remote incoming to Review` 安全远端 KnowledgeCard 导入、`Send remote review history to Review` 安全远端复习记录导入、`Stage safe remote card conflicts to Review` 安全远端 KnowledgeCard 冲突暂存导入、`Send remote conflicts to Review` 远端冲突 triage handoff、受保护 `Upload sync bundle` 写出，以及 Review inbox 直达入口；只纳入已应用 KnowledgeCard 和复习历史，显性显示排除项、待审冲突、远端 incoming/outgoing/conflict 计数和 `Not previewed / Review required / Ready to upload / Uploaded / Failed` 状态；provider 级闭环覆盖安全的本地 KnowledgeCard 冲突进入 Review Inbox 后 approve/apply，并解除 pending conflict 回到 export included 集合。 | 目前是本地导出 + 远端 bundle 预览 + 远端状态提示 + 安全远端 KnowledgeCard Review 导入 + 安全远端 review history Review 导入 + 安全远端 KnowledgeCard 冲突 staged Review 恢复 + 安全 bundle 写出 + 冲突 Review handoff；本地 staged 或远端 staged 且满足 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef` 的冲突可 apply，远端 staged ReviewItem 写入失败会回滚暂存 entry，远端 incoming KnowledgeCard 和 review history 都会降级为 pending Review；旧的远端 preview conflict triage 入口只支持 dismiss/triage；写出前如果发现远端 incoming/conflict 会阻止覆盖；不是完整云同步引擎，不执行双向自动合并、远端写回或跨端写回恢复。 |

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
- 页面启动前必须显示当前 provider/model/capability 诊断；缺少 pricing metadata 时必须显示 `Cost: unknown` 和原因，不伪造美元成本估算。
- 角色完成后如果 provider/SDK 返回 usage metadata，必须显示 `Provider reported usage` 并持久化到 turn/run；如果没有返回 usage metadata，必须显示本地 token 估算和 `Provider billing may differ` 提示；本地估算只能来自本地 prompt/evidence/response 字符计数，不得伪装成 provider billing。
- 用户填写的本地 role output token budget 和 run token budget 只能使用 `local-char-estimate-v1` 执行；超限时停止后续 Seminar 步骤、保留已完成 traceable turn、显示失败原因并允许重试。
- 当 provider capability cache 带 pricing metadata 时，页面必须启用估算 `Run cost cap USD`；runtime 使用 provider-reported usage 或本地 fallback usage 聚合估算美元成本，超出 cap 时停止后续 Seminar 步骤并保留失败原因。
- 页面必须说明估算 cost cap 不是真实 provider 发票或扣费上限；缺少 pricing metadata 时必须禁用美元 cap 并显示原因；不得把 provider token usage 或本地 token budget 单独当作真实账单上限。
- completed/cancelled/failed Seminar state 可作为本机恢复缓存保存；该缓存不得进入普通 prefs backup，不得同步，不得包含 API key；恢复出的页面必须显示 recovered 提示。
- 从阅读页进入 Seminar 时，现有 runtime/cache 必须匹配当前 `bookId` 和入口问题；不匹配时必须清除本机 runtime/cache 并显示新的空白 runtime，不得把旧书/旧选区的结果展示到当前入口。
- persisted `running` state 必须恢复为 interrupted/retryable，清空 active role 和 partial text，不得伪装后台 stream 仍在继续。
- 研讨结果不自动写 KnowledgeCard、Memory、Note 或 Sync asset。
- synthesis、候选卡和候选 flashcard 只进入 Review；用户必须在 Review Inbox 中批准或应用，才会进入长期知识资产或复习队列。
- 当前入口必须保留降级路径：用户仍可用普通 `AI` 按钮解释选中文本。

验证命令：

```bash
flutter test --no-pub \
  test/service/ai/langchain_runner_usage_test.dart \
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

### 2.4 AI Chat Memory 候选审核

用户路径：

1. 在 AI Chat 中找到一条回答。
2. 点击回答旁的 `Memory actions`。
3. 选择 `Add to Review inbox`。
4. 系统创建 `MemoryCandidate(status=pending)`，写入 `.workflow/review_inbox_v2.json`。
5. 系统创建对应 `ReviewItem(sourceType=memory-candidate)`，写入 `.workflow/review_items_v1.json`。
6. 用户进入 `Settings -> AI -> Review inbox`，审核这条 memory 候选。
7. 用户可以查看证据摘录、来源标题/位置、不可跳原因或打开来源动作。
8. 用户点击 `Approve` 后，再点击 `Apply`。
9. 系统先通过 `MemoryWorkflowService.applyCandidate` 追加到目标 daily 或 long-term Markdown memory，再推进 ReviewItem 到 `applied`。

Gate：

- Memory 候选必须经用户显式 `Approve -> Apply`，不能自动写长期 memory。
- `Dismiss` 必须同步 MemoryCandidate 状态，且不写 memory Markdown。
- Apply 必须走 Memory source-specific adapter；不能通过泛型 ReviewItem 状态推进绕过 source 写入。
- 无书内跳转的 conversation memory 必须保留 evidence snippet、source hash 和不可跳原因，使用户能解释来源不可跳。
- Apply/dismiss 不写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。
- MemoryCandidate 缺失、targetDoc 缺失或 SourceRef 不满足 gate 时，不得推进 ReviewItem 到 applied。

验证命令：

```bash
flutter test --no-pub \
  test/service/review/knowledge_review_adapter_test.dart \
  test/service/memory_workflow_service_test.dart \
  test/service/review/review_inbox_controller_test.dart \
  test/page/settings_page/review_inbox_page_test.dart \
  -r compact
```

### 2.5 Memory 独立浏览 SourceRef 审计

用户路径：

1. 用户在 `Settings -> Home navigation / 首页导航` 打开默认隐藏的 `Memory / 记忆` tab。
2. 用户从首页底部导航进入 `Memory / 记忆` tab。
3. 页面加载 daily memory 和 long-term memory 条目。
4. 系统用已应用的 `MemoryCandidate` 按目标文档和条目 body 只读投影 SourceRef。
5. 条目行显示 `traceable/unavailable/unresolved` 来源状态。
6. 用户点击一条 memory 进入详情页。
7. 详情页显示 `Evidence`、证据摘录、来源标题/位置和不可跳原因。
8. 如果 SourceRef 可解析为 `paperreader://reader/open?...`，用户点击 `Open source` 回到原文。
9. 如果来源没有 book anchor，用户点击 `Open source` 时看到不可跳原因，不触发空跳转。

Gate：

- Memory 独立浏览页只能读取已应用 MemoryCandidate 生成 SourceRef，不写新的 ReviewItem 或知识资产。
- SourceRef 投影必须匹配 `daily/longTerm` 目标文档和条目正文；只能用实际写入 memory 的 `text/displayText` 证明归属，不能只靠 summary 命中；long-term `MEMORY.md` 使用 H1 分段 body，不能把整文件来源全部挂到每个分段。
- 不往 Markdown memory 文件写隐藏 metadata；旧 Markdown 仍可正常打开。
- long-term H1 分段不可批量删除/打标签，避免把一个分段的操作变成整份 `MEMORY.md` 的资产修改。
- 有效来源必须通过 `PaperReaderReaderIntent.fromSourceRef` 生成 reader intent；非法 jump link 不能算 traceable。
- conversation-only memory 保留 evidence snippet、source hash 和 `memory-source-not-jumpable` 不可跳原因。
- 详情页只展示已裁剪 evidence，不读取整章正文、图片原文、OCR 长文本或派生索引。

验证命令：

```bash
flutter test --no-pub \
  test/page/memory/memory_home_page_test.dart \
  test/service/memory/markdown_memory_store_test.dart \
  test/service/memory/memory_source_ref_adapter_test.dart \
  test/page/memory/memory_row_test.dart \
  test/page/memory/memory_detail_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.6 旧划线/笔记 SourceRef 审计

用户路径：

1. 用户打开某本书的笔记列表，或在全局搜索里看到命中的笔记/划线。
2. 系统用 `BookNoteSourceRefAdapter.fromBookNote` 把旧 `BookNote` 投影成 `SourceRef`。
3. 笔记条目显示 `Evidence`、证据摘录、来源书名、章节位置和 `traceable/unavailable` 状态。
4. 有 `bookId + cfi` 的条目沿用原有阅读页跳转。
5. 缺失 CFI 或无有效 book anchor 的旧条目点击时显示 `book-note-source-not-jumpable` 原因，不调用空 CFI 跳转。

Gate：

- 旧 BookNote/highlight 不制造 KnowledgeCard、ReviewItem、Memory、ConceptGraph、SpacedReview 或 Sync side effect。
- `BookNoteSourceRefAdapter` 必须区分 highlight 与 note。
- 有 `bookId + cfi` 的 SourceRef 必须生成 `paperreader://reader/open?...` jumpLink。
- 缺失 CFI 或无有效 bookId 的旧条目必须写 `unavailableReason`，并仍可在 UI 中看到来源证据。
- `SourceRefEvidenceList` 只展示裁剪后的 snippet、title、location 和 unavailable reason，不读取章节正文或 `ai_index.db`。

验证命令：

```bash
flutter test --no-pub \
  test/service/review/knowledge_review_adapter_test.dart \
  test/widgets/book_notes/book_note_tile_test.dart \
  -r compact
```

### 2.7 图片解析生成知识卡

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

### 2.8 概念图谱探索

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

### 2.9 RAG / GraphRAG 结果生成知识卡

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

### 2.10 间隔复习

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

### 2.11 知识同步 / 导出

用户路径：

1. 用户先在 Review Inbox 中 `Apply` KnowledgeCard，或完成间隔复习记录。
2. 用户进入 `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。
3. 页面展示本次默认纳入的知识资产数量、默认排除项数量和待审冲突数量。
4. 用户可以刷新计划，确认哪些 envelope 会进入导出，哪些因草稿、派生缓存、密钥或冲突被排除。
5. 如果页面显示待审冲突，用户点击 `Send conflicts to Review / 发送冲突到 Review`。
6. 系统为每个尚未进入 Review 的待审冲突创建 `ReviewItem(sourceType=sync-conflict, status=pending)`，只保存安全 metadata、payload key 列表和 SourceRef；如果冲突没有 SourceRef，则写入 `sync-conflict-no-source` 不可跳原因，不把 raw payload 值或 secret 值写入 ReviewItem payload。
7. 页面显示 `Review inbox` 直达入口；用户点击后进入 Review Inbox，也可以从 `Settings -> AI -> Review inbox` 进入。
8. 用户查看 `Sync conflict / 同步冲突` 类型的待审项、冲突原因、来源证据和可跳转状态。
9. 如果该冲突是 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef`，页面显示 `Approve` 和 `Apply`；用户 `Apply` 后系统把该 KnowledgeCard 写回为用户确认资产，并解除 pending conflict metadata。
10. 如果冲突含 secret payload、未知 schema、无可追踪 SourceRef、非 KnowledgeCard 或 payload 不可解析，页面只显示 `Dismiss`，不提供 approve/apply。
11. 用户点击 `Create export / 创建导出`。
12. 系统写入 `.knowledge/knowledge_export_manifest_v1.json`，其中只包含安全的实体 ID、格式、时间戳和裁剪后的 SourceRef 引用。
13. 系统同时写入 `.knowledge/knowledge_export_v1.md`，作为可阅读的 Markdown 学习导出，只包含已纳入资产、裁剪后的证据片段和可跳转来源。
14. 系统同时写入 `.knowledge/knowledge_export_study_report.html`，作为可打开的本地 HTML 学习报告；页面不加载外部资源、不执行同步，只展示已纳入资产、裁剪后的证据片段和可跳转来源。
15. 系统同时写入 `.knowledge/knowledge_export_anki.tsv`，作为 Anki 兼容 TSV；Front/Back/Source 只来自默认纳入资产、裁剪后的证据片段和可跳转来源。
16. 系统同时写入 `.knowledge/knowledge_sync_bundle_v1.json`，作为机器可读 per-entity envelope bundle；它只包含默认纳入的安全 envelope，不包含 draft、pending conflict、secret payload 或派生缓存。
17. 如果用户已配置 WebDAV/SyncClient，用户点击 `Preview remote sync / 预览远端同步`。
18. 系统读取远端 `paper_reader/.knowledge/knowledge_sync_bundle_v1.json`，按 entity id 比对本地 included envelope，展示 `remote / incoming / outgoing / remote conflict` 计数。
19. 页面显示远端同步状态：`Not previewed / Review required / Ready to upload / Uploaded / Failed`，并显示对应下一步动作说明。
20. 用户点击 `Send remote incoming to Review / 发送远端待引入到 Review`。
21. 系统只把安全远端 incoming KnowledgeCard 降级为 `KnowledgeCard(reviewState=pending, ownership=AI-generated-draft)` 和 `ReviewItem(sourceType=knowledge-card, status=pending)`；重复导入、非 KnowledgeCard、无 evidence 或 unsafe payload 被跳过。
22. 用户点击 `Send remote review history to Review / 发送远端复习记录到 Review`。
23. 系统只把安全远端 review history 降级为 `ReviewItem(sourceType=review-history-import, status=pending)`；用户 Apply 后才写入本机 SpacedReviewStore；重复导入、无 evidence 或 unsafe payload 被跳过。
24. 用户点击 `Stage safe remote card conflicts to Review / 暂存安全远端知识卡冲突到 Review`。
25. 系统只把安全远端 KnowledgeCard conflict 写入本机 staged conflict store，并创建可 apply 的 `ReviewItem(sourceType=sync-conflict, status=pending, canApply=true, remoteStaged=true)`；ReviewItem 不保存 remote raw payload value。
26. 用户在 Review Inbox 中批准并应用后，系统才把 staged remote KnowledgeCard 写回为本机已确认资产，并清掉 staged conflict；未 Apply 前原本机 KnowledgeCard 不被覆盖。
27. 用户点击 `Send remote conflicts to Review / 发送远端冲突到 Review`。
28. 系统把远端冲突创建为 preview-only `ReviewItem(sourceType=sync-conflict, status=pending, canApply=false)`；ReviewItem 只保存安全 metadata、payload key 列表、SourceRef count 和 SourceRef safe JSON，不保存 remote raw payload value。
29. preview-only 远端 `sync-conflict` 只用于 triage/dismiss，不显示 approve/apply；可恢复 apply 必须来自 staged conflict 入口。
30. 用户点击 `Upload sync bundle / 上传 sync bundle`。
31. 系统重新生成本机安全 sync bundle；如果远端 bundle 不存在，创建远端目录并上传；如果远端 bundle 已存在，先执行 preview gate，只有 `incoming=0` 且 `conflict=0` 时才允许覆盖写出。
32. 如果远端存在 incoming 或 conflict，上传中止并显示错误，不删除远端内容、不覆盖本地资产、不把远端冲突自动应用到本地。

Gate：

- 默认只纳入 `applied + user asset` 的 KnowledgeCard 和 review history。
- `ai-draft`、`derived-index`、包含 API key/token/secret/auth/authorization/bearer/private-key/credential/password 的 payload 默认排除。
- 待审冲突显示为排除项，不进入 manifest。
- `Send conflicts to Review` 只为待审冲突创建 `sync-conflict` ReviewItem；重复点击不制造重复 ReviewItem，不覆盖已经存在的 pending/approved/dismissed/applied 审核决策；无 SourceRef 冲突必须带不可跳原因。
- sync conflict ReviewItem 只保存 entity id/type/schema/update/conflict reason/payload keys/sourceRef count；不得保存 raw payload value、API key、token、secret 或派生缓存内容。
- sync conflict ReviewItem 只有在 payload 标记 `canApply=true` 且底层 store 再次验证为 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef` 时，才可 approve/apply；其他 sync conflict 只能 dismiss/triage。
- safe sync conflict apply 只允许解除该 KnowledgeCard 的 pending conflict metadata 并写回为用户确认资产；不得创建 SpacedReview、ConceptGraph、Memory、Note 或远端同步 side effect。
- manifest 不写 `ai_index.db`，不把派生索引当作 source-of-truth。
- SourceRef 文本片段必须使用现有裁剪规则，不导出无限正文。
- Markdown 导出只能读取默认纳入资产；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 Markdown 正文。
- HTML study report 只能读取默认纳入资产；正文和链接属性必须转义，不加载远端脚本、图片、样式或 provider 内容；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 HTML 正文。
- Anki TSV 导出只能读取默认纳入资产；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 TSV 正文；TSV 字段必须清理制表符和换行，避免破坏导入结构。
- sync bundle 只能包含默认纳入 envelope；不得包含 draft、pending conflict、secret payload、`ai_index.db` 或 derived cache。
- remote preview 只读取配置的 SyncClient/WebDAV bundle；读取失败进入页面错误状态，用户可刷新重试；不会自动导入 incoming envelope，不会自动覆盖本地资产。
- remote incoming 导入必须由用户点击触发；只接受安全 KnowledgeCard，且导入后仍是 pending Review，不直接成为本机用户资产。
- remote review history 导入必须由用户点击触发；只接受安全 review history，且导入后仍是 pending Review，不直接写入 SpacedReviewStore。
- remote conflict 有两条显式入口：preview-only triage 入口必须 `canApply=false`；staged restore 入口只接受安全 KnowledgeCard conflict，必须先写 staged conflict store，再由 Review Inbox approve/apply 恢复；若 ReviewItem 写入失败，必须回滚 staged entry。
- remote upload 只上传本机重新生成的安全 sync bundle；远端存在 incoming 或 conflict 时必须阻止上传，不能用本机 bundle whole-file 覆盖远端用户资产。
- 当前入口创建本地 manifest、Markdown 学习导出、HTML study report、Anki TSV、sync bundle，能把安全远端 incoming KnowledgeCard、远端 review history、本地冲突、安全远端 KnowledgeCard staged conflict 和远端 preview-only conflict 送入 Review Inbox，并能在无远端 incoming/conflict 时上传安全 sync bundle；支持安全 KnowledgeCard 本地冲突和安全远端 KnowledgeCard staged conflict 的用户确认恢复，且 staged ReviewItem 写入失败会清理暂存项；不执行双向自动合并、远端写回或自动同步备份。

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

### 2.12 Custom Skill 导入

用户路径：

1. 用户进入 `Settings -> AI -> Custom skills`。
2. 用户粘贴 `CustomSkillContract(schemaVersion=1)` JSON，或点击 `Paste safe example` 填入安全示例。
3. 用户点击 `Import skill`。
4. 系统解析 JSON、校验 schema、scene、工具权限和 runtime 注入边界。
5. 如果校验失败，页面显示错误，skill 不写入本地 store，也不出现在 `Active Skill`。
6. 如果校验通过，系统写入 SharedPreferences 中的 `customAiSkillContractsV1`，并在页面的 Installed skills 列表显示 runtime 状态、scene 和允许工具。
7. 用户可以开关或删除该 custom skill。
8. 用户回到 `Settings -> AI -> Active Skill`，选择启用后的 custom skill。
9. AI Chat runtime 构建 system prompt 时合并 custom skill prompt；工具列表只保留 custom skill 声明过、当前 scene 可用、permission matrix 允许的只读工具。

Gate：

- 只接受 JSON object，不接受空输入或数组根节点。
- `schemaVersion` 必须是整数 `1`。
- unknown field、unknown scene、system scene、字段类型错误、未知工具、写工具、`spawn_sub_agent` 均阻止导入。
- disabled custom skill 可以保存在 Installed skills，但不进入 `Active Skill`，也不会注入 runtime。
- active custom skill scene 不匹配时不注入 prompt，工具列表为空。
- active custom skill 运行时不加载 MCP 工具，避免绕过 contract 的 tool whitelist。
- 导入、开关、删除不写 KnowledgeCard、ReviewItem、Memory、Note、ConceptGraph 或 Sync asset。

验证命令：

```bash
flutter test --no-pub \
  test/service/ai/skills/custom_skill_store_test.dart \
  test/service/ai/langchain_registry_custom_skill_test.dart \
  test/page/settings_page/custom_skills_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

## 3. 当前还不能用

这些能力没有产品入口或没有完成端到端验收，不应在用户沟通中描述为已经可用：

| 能力 | 当前边界 | 下一步 Agent Task | Gate |
| --- | --- | --- | --- |
| 完整云同步引擎 | 当前已有本地导出、机器可读 sync bundle、远端 bundle preview、远端同步状态面板、安全远端 incoming KnowledgeCard Review 导入、安全远端 review history Review 导入、安全远端 KnowledgeCard 冲突 staged Review 恢复、受保护 bundle 上传、安全冲突 Review handoff 和安全 KnowledgeCard 冲突本地恢复；还没有双向自动合并、远端写回和失败回滚执行器。 | 设计并实现双向合并器、远端写回和 rollback。 | API key 永不同步；冲突进入 Review；不得使用 whole-file newer-wins 覆盖用户资产。 |
| Seminar 后台续跑和真实账单对账 | Seminar runtime 已能流式、取消、重试、Review handoff，并显示 provider readiness、capability cache、成本未知原因、provider token usage、本地 token 估算 fallback、本地 role/run token budget、pricing metadata 驱动的估算 `Run cost cap USD` 和本机 state 恢复；running state 重启后恢复为 interrupted/retryable。未接真正后台任务续跑，也不做 provider invoice reconciliation。 | 接入后台任务队列、重启续跑、移动资源 gate 和真实账单/价格版本对账说明。 | 移动资源 gate；长任务可取消、失败可恢复或重试；无 pricing metadata 时继续显示成本未知原因并禁用美元 cap；估算美元成本不等于 provider 发票；本地 token budget 不得声明为 provider billing cap；不能把本机 recovery cache 当作同步资产。 |
| 复杂无限画布式 ConceptGraph | 当前是局部图谱、dossier、路径和摘要，不做无限画布、缩放手势或跨书外部知识扩展。 | 如需画布，先定义移动端资源、证据可见性和 graph ownership gate。 | 关系必须有 evidence；正式关系必须 Review apply。 |
| 发布版可用 | 本文件描述 `codex/future-agentic-upgrade` 分支；不代表 `main`、TestFlight 或已安装版本。 | 走 release promotion gate，完成合并、构建、回归、发布说明和用户迁移说明。 | 发布前必须重跑权威验证命令并记录 commit。 |

## 4. 用户入口任务验收状态

这张表是分支内的 agent task 台账，不是发布排期。`Accepted` 表示在当前分支已有代码和测试证据；`In Review` 表示已有切片但仍有上表列出的用户证据或发布 gate 未完成。

| TaskID | 状态 | Parent Capability | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| UFA-C01-T01 | Accepted | Selection KnowledgeCard | 选中文本生成待审 KnowledgeCard。 | E00 SourceRef, E03 store, E05 ReviewItemStore | `SelectionKnowledgeCardProducer` | 已通过 producer 测试，重复点击不重复写入。 |
| UFA-C01-T02 | Accepted | Selection KnowledgeCard | 阅读页选中菜单显示 `知识卡`。 | UFA-C01-T01, E07 menu | `ExcerptMenu` action, l10n keys, reader context fallback resolver | widget 覆盖 `Card/Seminar/Graph` 入口可见；点击 `Card` 调用 selection KnowledgeCard producer，传入 book/cfi/选中文本/标题上下文，显示 Review feedback 并关闭菜单；无注入 context/creator 的点击级测试覆盖 reader context fallback resolver 和默认 `SelectionKnowledgeCardProducer()` 文件 store 写入，验证 pending KnowledgeCard、pending ReviewItem、SourceRef、重复点击不重复写。生产默认 resolver 仍读取 `epubPlayerKey.currentState`。 |
| UFA-C01-T03 | Accepted | Image Analysis KnowledgeCard | 图片解析结果生成待审 KnowledgeCard。 | E00 SourceRef, E03 store, E05 ReviewItemStore, E07 image analysis sheet | `ImageAnalysisKnowledgeCardProducer`, `AiImageAnalysisSheet` Card action, `ImageViewer` analysis/card seams | 图片解析结果弹层显示 `Card` 入口；producer 覆盖 pending KnowledgeCard 和 pending ReviewItem、重复点击和不自动写长期资产；ImageViewer 工具栏点击 `AI Image Analysis` 后使用可注入分析流打开弹层，点击 `Card` 写入 pending image-analysis KnowledgeCard 和 pending ReviewItem，保留 book/cfi/href SourceRef 且不保存图片本体。 |
| UFA-C01-T04 | Accepted | RAG Evidence KnowledgeCard | 本地 RAG/GraphRAG evidence 生成待审 KnowledgeCard。 | E00 SourceRef, E02 RAG evidence, E03 store, E05 ReviewItemStore, E07 ConceptGraph empty state | `RagEvidenceKnowledgeCardProducer`, `ConceptGraphExplorerNotifier.createKnowledgeCardFromLibrarySearch`, 空态 `Card` action | 只有 traceable chunk SourceRef 且带可保存 chunk snippet 的 RAG evidence 能写 pending KnowledgeCard 和 pending ReviewItem；derived summary 不替代书内 chunk evidence；不写正式图谱或长期资产；写入后页面显示 Review inbox 反馈。 |
| UFA-C01-T05 | Accepted | AI Chat KnowledgeCard | AI Chat 回答显式生成待审 KnowledgeCard。 | E00 SourceRef, E03 store, E05 ReviewItemStore, E07 AI Chat message action | `AiChatKnowledgeCardProducer`, `AiChatStream` 回答旁 `知识卡` action, answer-side source status chip, `ExcerptMenu` AI sourceRef handoff, `conversationV2` user-node SourceRef persistence | 回答完成后才可点击 `知识卡`，streaming 中按钮禁用且 producer 调用数为零；回答旁显示可跳转或不可用来源状态；选中文本进入 AI 草稿且发送内容仍包含原选中文本或 SourceRef snippet 时，才保留并持久化精确 reader SourceRef；历史重载后 `知识卡` 仍优先使用原始 reader SourceRef；无关改写不保存旧 reader SourceRef；短公共片段碰巧命中不保存旧 reader SourceRef；reader-grounded card 带保守 `conceptRefs`，纯聊天 card 不带；重复点击不制造重复卡；不直接写 ConceptGraph、长期记忆、笔记或 spaced review。 |
| UFA-C02-T01 | Accepted | Seminar launcher | 阅读页选中菜单显示 `研讨`，打开结构化 Seminar runtime page。 | AI Seminar runtime, E07 menu | `ExcerptMenu` action | 入口可见；选中文本预填；不自动写用户资产。 |
| UFA-C02-T02 | Accepted | Structured Seminar runtime UI | 把 `AiSeminarOrchestrationService` 接入真实模型流式事件。 | E01 services, E06 governance, E07 progress UI | `AiSeminarRuntimeService`、`aiSeminarRuntimeProvider`、`AiSeminarRuntimePage` | 角色 turn、evidence、whiteboard、synthesis 进入可序列化 runtime state；失败可重试，运行可取消。 |
| UFA-C02-T03 | Accepted | Seminar Review handoff | Seminar synthesis 和候选卡进入 Review Inbox。 | UFA-C02-T02, E05 controller | `AiSeminarRuntimeNotifier.sendToReview` + `SeminarSynthesisReviewAdapter` | 只有 `readyForReview + traceable handoff` 的 synthesis 进入 pending Review；候选卡保持 AI draft/pending，不直接应用；页面级 widget 覆盖用户点击 `Start Seminar` 后再点击 `Send to Review`，并断言 synthesis、KnowledgeCard ReviewItem 和 seminar KnowledgeCard 均为 pending/draft 边界。 |
| UFA-C02-T04 | Accepted | Seminar Flashcard handoff | Seminar reviewSuggestion 进入 flashcard Review。 | UFA-C02-T03, UFA-C04-T01 | `SeminarSynthesisReviewAdapter.flashcardsFromSynthesis`, `FlashcardReviewAdapter`, `ReviewInboxController` | 只有 traceable synthesis 的 candidate review question 会生成 pending flashcard；页面级 widget 覆盖 `Send to Review` 后 flashcard candidate 进入 pending ReviewItem；用户 Apply 后进入 Spaced Review；不绕过 Review。 |
| UFA-C02-T05 | Accepted | Seminar provider readiness | Seminar 页面启动前显示当前 provider/model/capability 和成本透明度。 | Provider Center capability cache, UFA-C02-T02 | `AiSeminarProviderContextService`, `AiSeminarRuntimeState.providerDiagnostics`, `AiSeminarRuntimePage` Provider readiness section | 从 `Prefs.selectedAiService`、provider metadata、AI config 和 `AiModelCapability` cache 解析 provider/model/context/max output/Tools/Vision/Thinking/pricing metadata；当前 schema 没有 streaming 字段时显示 `Streaming unknown`，不伪造支持；runtime `start` 前捕获 diagnostics 并随 state JSON restore；页面显示 `Provider readiness`、capability chips、缺少 pricing metadata 时的 `Cost: unknown` 和原因，有 pricing metadata 时显示可用于 estimated USD cap；不读取或展示 API key，不把估算成本声明为真实账单。 |
| UFA-C02-T06 | Accepted | Seminar local token usage | Seminar 角色输出显示本地 token 估算并随 runtime state 恢复。 | UFA-C02-T02, UFA-C02-T05 | `AiSeminarTokenUsage`, `AiSeminarRuntimeService` local estimator, `AiSeminarRuntimePage` usage UI | 每个通过 evidence gate 的 completed role turn 都写入 `tokenUsage(inputTokens/outputTokens/isEstimated/estimationMethod=local-char-estimate-v1)`；`AiSeminarRun` 聚合 usage，state JSON restore 保留 turn/run usage；页面显示 `Local token estimate`、input/output 和 `Provider billing may differ`，继续显示 `Cost: unknown`，不读取 API key，不调用 provider，不把本地估算当作美元成本。 |
| UFA-C02-T07 | Accepted | Seminar local recovery | Seminar runtime state 保存为本机恢复缓存，重新打开页面可恢复同一入口的已完成或已中断状态。 | UFA-C02-T02, UFA-C02-T06, E07 recovery gate | `aiSeminarRuntimeStateV1PrefsKey`, `AiSeminarRuntimeNotifier` persistence/restore, `AiSeminarRuntimePage` recovered banner, prefs backup skip | completed/cancelled/failed state 会写入 `aiSeminarRuntimeStateV1` 本机缓存；同一书籍/同一入口问题的新页面会恢复 state 并显示 `Recovered local Seminar state`；换书或换选区会清掉旧 runtime/cache，不展示旧研讨；persisted running state 降级为 cancelled/interrupted 且 `canRetry=true`，并回写清理 active role / partial text；该缓存被普通 prefs backup 排除，不同步，不导出 API key 或正文到 backup；恢复态保留生成时保存的 provider/model diagnostics，retry 时再使用当前 provider 设置。 |
| UFA-C02-T08 | Accepted | Seminar local token budgets | 用户在 Seminar 页面设置本地 role/run token budget，并在超限时停止后续步骤。 | UFA-C02-T06, mobile resource gate | `AiSeminarBudgetPolicy`, `AiSeminarRuntimeService` budget gate, `AiSeminarRuntimePage` Local budget guardrails | Session contract round-trip 保存 `maxRoleOutputTokens/maxRunTokens`；页面显示 `Local budget guardrails`、`Role output token budget` 和 `Run token budget`；runtime 用 `local-char-estimate-v1` 判断 token 超限，流式 partial 超出 role output budget 时取消 active stream，completed turn 超出 role/run budget 时停止后续步骤；超限进入 failed/retryable，不生成 synthesis，不发送 Review；restore/retry 保留 session budget policy；不把本地 token 预算冒充 provider billing 或美元成本上限。 |
| UFA-C02-T09 | Accepted | Seminar provider token usage | provider/SDK 返回 token usage metadata 时，Seminar turn/run 保存并显示 provider-reported token usage。 | UFA-C02-T06, UFA-C02-T08 | `CancelableLangchainRunner.stream`, `AiUsageTracker`, `AiSeminarModelRoleExecutor`, `AiSeminarTokenUsage.source`, `AiSeminarRuntimePage` usage UI | 非 agent stream 完成后把 provider usage 记录到会话 tracker；role executor 按 session usage tracker 前后差值写入 `provider-reported` tokenUsage；run 聚合 provider/local mixed usage；页面显示 `Provider reported usage` 或 mixed/local fallback；local role/run token budget 仍只使用 `local-char-estimate-v1`；provider token usage 只作为估算成本输入之一，不等于真实账单。 |
| UFA-C02-T10 | Accepted | Seminar estimated USD cost cap | 用户在 Seminar 页面设置估算 `Run cost cap USD`，超出时停止后续步骤。 | UFA-C02-T05, UFA-C02-T09 | `AiModelCapability` pricing metadata, `AiSeminarBudgetPolicy.maxRunCostUsd`, `AiSeminarRuntimeService` cost gate, `AiSeminarRuntimePage` cost cap UI | Provider capability cache 带 input/output/cache pricing metadata 时，页面启用 `Run cost cap USD` 并显示 pricing source；session/run JSON round-trip 保存 pricing policy 和 estimated cost；runtime 聚合 provider-reported usage 或本地 fallback usage 估算美元成本，超出 cap 时进入 failed/retryable、保留已完成 turn、不生成 synthesis、不发送 Review；无 pricing metadata 时禁用 cost cap 并显示原因；估算成本不声明为 provider invoice。 |
| UFA-C03-T01 | Accepted | Concept producer | 从 KnowledgeCard、Seminar candidate concept refs、reader-grounded AI Chat concept refs 和 derived RAG/GraphRAG search result 提取有证据的 ConceptNode/Edge 候选。 | E03, E04 store, E05 controller, UFA-C01-T05, UFA-C02-T03, E02 SourceRef evidence | `ConceptGraphProducer`, ReviewInboxController apply hook, Seminar candidate `conceptRefs` handoff, AI Chat card `conceptRefs` handoff, `createFromLibrarySearchResult`, `ConceptGraphExplorerNotifier.createDraftCandidateFromLibrarySearch` | 只有 `applied + traceable + conceptRefs` 的 KnowledgeCard，或 `derivedLayer/derivedSummary + traceable chunk SourceRef` 的 library RAG result，生成 draft node/edge；Seminar candidate card 和 reader-grounded AI Chat card 可携带 conceptRefs 并在用户 Apply 后进入同一链路；relation 进入 pending Review；ConceptGraph 空态显性 action 已接，并展示 Review/skip feedback。 |
| UFA-C03-T02 | Accepted | Concept Explorer page | 提供局部图谱探索入口。 | E04 dossier/explore | `ConceptGraphExplorerPage`, provider, Settings AI entry, local graph map summary, injectable source opener | 用户能打开概念页、看中心概念、直接关系、二跳节点、evidence link 数量、draft/formal 状态、局部路径、原文跳转和 orphan/broken link；`Open source` 点击会把 jumpable SourceRef 交给 opener，不可跳来源显示原因且不触发 opener；Settings AI 点击级测试覆盖 `Settings -> AI -> Concept graph` 导航到 Explorer。 |
| UFA-C03-T03 | Accepted | Reader concept entry | 阅读页选中文本可进入概念探索。 | UFA-C03-T02 | `ExcerptMenu` graph action, `ConceptGraphExplorerPage.initialQuery` | 选中文本可打开图谱页并筛选相关概念；没有相关概念时展示空态和草稿候选入口，不生成无证据正式节点。 |
| UFA-C04-T01 | Accepted | Spaced Review | Review apply 后生成复习队列。 | E03, E05 | `SpacedReviewStore`, `spacedReviewProvider`, `SpacedReviewPage`, `SourceRefEvidenceList`, injectable source opener, Settings AI entry | 复习项可回溯到卡片和原文；页面显示证据摘录和不可用来源原因；删除书后显示可解释状态；评分记录下一次到期时间；`Open source` 点击会把 jumpable SourceRef 交给 opener，不可跳来源显示原因且不触发 opener；Settings AI 点击级测试覆盖 `Settings -> AI -> Spaced review` 导航到复习页。 |
| UFA-C04-T02 | Accepted | Flashcard Review apply | 待审 flashcard 应用后进入 Spaced Review。 | E05 controller, UFA-C02-T04 | `SpacedReviewStore.reviewIdForFlashcard`, `upsertFromFlashcardReviewItem`, `ReviewInboxPage` Apply gate | pending/approved flashcard 不直接入队；只有用户在 Review Inbox 点击 enabled `Apply` 后，applied 且 traceable 的 flashcard 才能入队；重复入队不制造重复复习项。 |
| UFA-C04-T03 | Accepted | Memory Review apply | 待审 MemoryCandidate 通过统一 Review Inbox 应用到本地 Markdown memory。 | E05 controller, MemoryWorkflowService, MemoryCandidateReviewAdapter | `MemoryWorkflowService.addToReviewInbox` -> `ReviewItemStore` handoff, `ReviewInboxController` memory source-specific apply/dismiss adapter, `ReviewInboxPage` Apply gate | AI Chat memory action 创建 pending MemoryCandidate 时同步创建 pending ReviewItem；conversation-only memory SourceRef 带 evidence snippet、source hash 和不可跳原因；Review Inbox `Approve -> Apply` 先调用 MemoryWorkflowService 追加到目标 daily/long-term Markdown，再推进 ReviewItem；`Dismiss` 同步 MemoryCandidate 且不写 memory；source candidate 缺失不推进 ReviewItem；不写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。 |
| UFA-C04-T04 | Accepted | BookNote SourceRef audit | 旧划线/笔记条目显示来源证据和可跳/不可跳状态。 | E00 SourceRef, E07 deep link, BookNote UI | `BookNoteSourceRefAdapter`, `BookNoteTile`, `BookNotesList`, search note result, `SourceRefEvidenceList` | Notes 列表和搜索结果传入 source title；BookNoteTile 显示 evidence、traceable/unavailable chip、来源位置和不可跳原因；有有效 `bookId + cfi` 的条目保持原文跳转；无有效 book anchor 条目点击只显示不可跳 snackbar，不触发空 CFI 或无效 book anchor 跳转；测试覆盖 adapter 和 widget。 |
| UFA-C04-T05 | Accepted | Memory browse SourceRef audit | Memory home、daily memory、long-term memory 浏览 UI 显示来源证据和可跳/不可跳状态。 | E00 SourceRef, E05 MemoryCandidate, E07 deep link, Memory browse UI | `MemoryEntrySourceRefAdapter`, `MemoryEntryRef.body/supportsBulkActions`, `MemoryRow` source audit chips, `MemoryDetailPage` source evidence/open source, Home navigation Memory label/icon | 只读投影已应用 MemoryCandidate；按目标文档和条目 body 匹配，summary-only 不归因，long-term H1 分段不共享整文件来源；列表显示 traceable/unavailable/unresolved chip；详情页显示 Evidence 和 `Open source`；可跳来源交给 reader opener，不可跳来源显示原因且不调用 opener；long-term H1 分段不允许批量删除/打标签，详情页也不显示会写整份 `MEMORY.md` 的 tag editor；不写 Markdown metadata、不写任何新知识资产。 |
| UFA-C05-T01 | Accepted | Sync / Export | 用户确认资产进入同步和导出入口。 | E08 policy | `KnowledgeAssetExportService`、`knowledgeAssetExportProvider`、`KnowledgeAssetExportPage`、Settings AI entry、export manifest、Markdown export、HTML study report、Anki TSV export、sync-conflict ReviewItem handoff | API key 不同步；派生索引不当作 source-of-truth；冲突被排除并显性显示；当前创建本地 manifest、Markdown 学习导出、HTML study report 和 Anki TSV，并能把待审冲突送入 Review Inbox；导出页在发送成功后显示 `Review inbox` 直达入口；provider 级测试覆盖 `KnowledgeAssetExportNotifier -> ReviewInboxNotifier -> ReviewInboxController -> KnowledgeCardStore/ReviewItemStore` 的安全 KnowledgeCard 冲突 approve/apply 闭环，解除 pending conflict 并重新进入导出集合；不执行远端写回或自动跨设备合并。 |
| UFA-C05-T02 | Accepted | Remote sync preview | 用户从 Knowledge sync/export 读取远端 sync bundle，预览 per-entity incoming/outgoing/conflict，并把远端冲突送入 Review。 | UFA-C05-T01, E08 sync bundle, SyncClient/WebDAV config, E05 ReviewItemStore | `.knowledge/knowledge_sync_bundle_v1.json`, `KnowledgeRemoteSyncPreview`, `KnowledgeAssetExportService.previewRemoteSync`, `submitRemoteConflictsToReview`, `KnowledgeAssetExportNotifier.previewRemoteSync`, `KnowledgeAssetExportPage` `Preview remote sync` / `Send remote conflicts to Review` actions | sync bundle 只包含默认纳入的安全 envelope；remote preview 读取 `paper_reader/.knowledge/knowledge_sync_bundle_v1.json` 并展示 remote/incoming/outgoing/conflict 计数；preview 不导入 incoming、不覆盖本地资产；远端冲突 ReviewItem 只保存安全 metadata、payload keys、SourceRef count 和 safe SourceRef；远端 preview 冲突一律 `canApply=false`，只支持 dismiss/triage；安全 KnowledgeCard 本地 staged 冲突继续走 approve/apply，本地解除 pending conflict；不执行远端写回、自动合并或备份同步。 |
| UFA-C05-T03 | Accepted | Protected remote sync upload | 用户从 Knowledge sync/export 把本机安全 sync bundle 写到 WebDAV/SyncClient。 | UFA-C05-T02, SyncClient/WebDAV config | `KnowledgeAssetExportService.uploadRemoteSyncBundle`, `KnowledgeRemoteSyncUploadResult`, `KnowledgeAssetExportNotifier.uploadRemoteSyncBundle`, `KnowledgeAssetExportPage` `Upload sync bundle` action | 上传前重新生成本机安全 sync bundle；远端不存在时创建 `paper_reader/.knowledge` 并上传；远端存在时先 preview，只有 `incoming=0` 且 `conflict=0` 时允许 replace；存在 incoming 或 conflict 时抛错并保持 remote 未改；页面显示上传路径和上传数量；不导入 incoming、不应用远端冲突、不执行双向自动合并或备份同步。 |
| UFA-C05-T04 | Accepted | Remote incoming KnowledgeCard Review import | 用户从 Knowledge sync/export 把远端 incoming KnowledgeCard 发送到 Review Inbox。 | UFA-C05-T02, E03 KnowledgeCardStore, E05 ReviewItemStore | `KnowledgeAssetExportService.submitRemoteIncomingToReview`, `KnowledgeRemoteIncomingReviewResult`, `KnowledgeAssetExportNotifier.submitRemoteIncomingToReview`, `KnowledgeAssetExportPage` `Send remote incoming to Review` action | 只接受 `knowledge-card + schemaVersion=1 + 无 secret payload + 有 evidence` 的远端 incoming envelope；导入时降级为 pending KnowledgeCard 和 pending ReviewItem；重复导入不制造重复卡；非 KnowledgeCard、无 evidence 或 unsafe payload 跳过；不导入 reviewHistory、不应用远端冲突、不自动写用户资产、不写 memory/note/graph/spaced review。 |
| UFA-C05-T05 | Accepted | Remote review history Review import | 用户从 Knowledge sync/export 把远端 review history 发送到 Review Inbox。 | UFA-C05-T02, E05 ReviewInboxController, SpacedReviewStore | `KnowledgeAssetExportService.submitRemoteReviewHistoryToReview`, `KnowledgeRemoteReviewHistoryReviewResult`, `ReviewItemSourceType.reviewHistoryImport`, `ReviewInboxController` review history apply adapter, `SpacedReviewStore.upsertImportedReviewHistory`, `KnowledgeAssetExportPage` `Send remote review history to Review` action | 只接受 `review-history + schemaVersion=1 + 无 secret payload + 有 evidence` 的远端 incoming envelope；导入时只创建 pending ReviewItem；generic ReviewItemStore apply 被拒绝；用户在 Review Inbox approve/apply 后才写入 SpacedReviewStore；重复导入不制造重复复习记录；不应用远端冲突、不写 KnowledgeCard/Memory/Note/ConceptGraph。 |
| UFA-C05-T06 | Accepted | Remote KnowledgeCard conflict staged restore | 用户从 Knowledge sync/export 把安全远端 KnowledgeCard conflict 暂存到 Review Inbox，并在 Review Inbox 中确认恢复。 | UFA-C05-T02, E03 KnowledgeCardStore, E05 ReviewInboxController | `KnowledgeAssetExportService.stageRemoteKnowledgeCardConflictsToReview`, `KnowledgeRemoteConflictStageResult`, `KnowledgeCardStore.stageRemoteSyncConflict`, `KnowledgeCardStore.removeStagedRemoteSyncConflict`, `remote_sync_conflicts_v1.json`, `KnowledgeAssetExportPage` `Stage safe remote card conflicts to Review` action | 只接受 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef` 的远端 conflict；staging 只写 staged conflict store 和 pending sync-conflict ReviewItem，未 Apply 前不覆盖本机 KnowledgeCard；ReviewItem 写入失败会删除 staged entry；用户 Apply 后才写为本机 approved asset 并清掉 staged conflict；preview-only `Send remote conflicts to Review` 仍 `canApply=false`；重复、unsafe、untraceable 或无 staged envelope 的 apply 失败关闭；不远端写回、不双向自动合并、不写 Memory/Note/ConceptGraph/SpacedReview。 |
| UFA-C05-T07 | Accepted | Remote sync status panel | 用户从 Knowledge sync/export 看到远端同步当前状态和下一步动作。 | UFA-C05-T02, UFA-C05-T03, E07 observability | `KnowledgeRemoteSyncStatus`, `KnowledgeAssetExportState.remoteSyncStatus`, `KnowledgeAssetExportPage` remote status panel, l10n keys | 页面显示 `Not previewed / Review required / Ready to upload / Uploaded / Failed`；远端 preview 出现 incoming/conflict 时显示 Review required；无 blocker 时显示 Ready to upload；上传成功显示 Uploaded；远端操作失败显示 Failed；刷新或重新创建 manifest 会清理旧上传状态；状态面板只解释下一步，不自动合并、不远端写回、不绕过 Review。 |
| UFA-C06-T01 | Accepted | Custom Skill 导入 | 用户从 Settings 导入 governed JSON skill，并在 Active Skill 中启用。 | E06 CustomSkillContract, AiSkillRegistry, LangChain runtime | `CustomSkillStore`、`CustomSkillsPage`、Settings AI entry、`AiSkill.allowedToolIds/sceneIds`、`LangchainAiRegistry.enabledToolIdsForActiveSkill` | 有效 `CustomSkillContract(schemaVersion=1)` 可导入、upsert、禁用和删除；危险工具、递归 sub-agent、unknown scene/field 和类型错误不落库不激活；禁用 skill 不进入 Active Skill；运行时只保留 custom skill 声明过且当前 scene/permission matrix 允许的只读工具；custom skill 激活时不加载 MCP 工具；widget 覆盖 `Settings -> AI -> Custom skills` 导航和粘贴 JSON 导入。 |

## 5. Agent 执行约束

每个剩余任务必须使用 `02_agent_execution_model_zh.md` 的 Agent Task 模板，并附加这些约束：

- 阅读场景优先 current book；只有用户显式跨书或 evidence 不足时才查 library。
- 外发正文给 provider 必须经过现有 AI 功能开关或显式用户动作。
- 写入用户资产必须经过 Review 或用户确认。
- ConceptGraph 是派生层；用户确认过的关系才是用户资产。
- UI 入口要能在移动端触达，不把核心阅读内容遮住。
- 长任务必须有取消、失败提示、重启恢复或可重试路径。

## 6. Rescue Review 要点

执行完成前，reviewer/rescue agent 必须逐项检查：

- 入口是否真实可触发，而不是只写了文档。
- 生成的 KnowledgeCard、Seminar synthesis、ConceptNode、ConceptEdge 是否都有 SourceRef。
- Review Inbox 是否能解释每个待审项的来源和状态。
- 任何自动化输出是否越过 Review 写入了长期资产。
- 文档是否把未接入口的能力标成已可用。
- 测试是否覆盖重复点击、空输入、source 不可跳、provider 失败和取消路径。
