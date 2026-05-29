# Implementation Status

> 状态：In Review
> 用途：记录本分支把 agentic upgrade spec 落到代码中的证据。这里不写月份、人日或传统排期，只写 artifact、gate 和验收命令。

## 1. 分支边界

- 工作分支：`codex/future-agentic-upgrade`
- 主线保护：不在 `main` 上实现。
- 旧文档角色：`docs/ai/ai_status_roadmap_zh.md`、`docs/ai/agent_system_architecture_zh.md`、`docs/superpowers/specs/2026-05-28-library-rag-optimization-design.md` 仅作为历史锚点。

## 2. Epic Evidence Ledger

| Epic | 当前代码 artifact | Gate 证据 | 状态 |
| --- | --- | --- | --- |
| E00 SourceRef & Provenance | `lib/models/source_ref.dart`、`lib/service/rag/source_ref_adapter.dart`、current-book/library RAG evidence `sourceRef` | SourceRef safe JSON、derived chunk hint、reader jump link、hash-only fingerprint 不算正式 evidence | In Review slice |
| E01 AI Seminar | `lib/models/ai_seminar.dart`、`AiSeminarOrchestrationService`、`AiSeminarEvidenceBroker`、`SeminarSynthesisReviewAdapter`、Seminar runtime governance scene、`ExcerptMenu` selection seminar launcher | fixed roles、role turn contract validation、current book first、library fallback service rule、Shared Whiteboard handoff、ReviewItem/KnowledgeCard candidates 不直接写用户资产；阅读页 `研讨` 入口降级到 prompt skill flow | In Review slice |
| E02 RAG / RAPTOR / GraphRAG | RAG evidence SourceRef alignment、`live_rag_gateway_smoke_test.dart` opt-in provider smoke、current branch `kAiIndexDbVersion = 10` | schema migration increments from main v8 through detailed progress and `force_rebuild`, embedding/rerank endpoint smoke isolated from normal CI | In Review slice |
| E03 KnowledgeCard | `lib/models/knowledge_card.dart`、`KnowledgeCardReviewAdapter`、`KnowledgeCardStore`、`SelectionKnowledgeCardProducer`、`ExcerptMenu` KnowledgeCard action | draft/pending boundary, duplicate candidate guard, source-required apply, card-to-review tests, reader selection SourceRef, `.knowledge/knowledge_cards_v1.json` local persistence, Review Inbox write | In Review slice |
| E04 ConceptGraph | `lib/models/concept_graph.dart`、`ConceptGraphStore`、`ConceptGraphReviewAdapter`、`ConceptGraphExplorerPage`、`conceptGraphExplorerProvider` | node/edge evidence, draft-only store writes, relation apply via ReviewItem, dossier assembly via traceable edges, orphan/broken link detection, local exploration depth/width limits, malformed graph degrade, Settings AI visible Explorer | In Review slice |
| E05 Review Inbox / Spaced Review | `lib/models/review_item.dart`、`ReviewItemStore`、`ReviewInboxController`、`reviewInboxProvider`、`ReviewInboxPage`、`MemoryCandidateReviewAdapter`、`FlashcardReviewAdapter`、`ConceptGraphReviewAdapter` | strict status transitions, versioned local inbox persistence, source-required apply, apply/dismiss traceability, KnowledgeCard and ConceptGraph decision mirror, source jump audit UI, spaced review sourceRefs | In Review slice |
| E06 Agent Tools / Skills Platform | `lib/models/ai_agent_governance.dart`、`AiToolRegistry` governance filters、`SubAgentRunner.allowedToolIdsForAgent`、`ToolOrchestrator` permission matrix | whitelist, no recursion, read-only Seminar sub-agent filtering, execution-time concurrency safety, `CustomSkillContract` strict schema/parser/validator/runtime injection gate | In Review slice |
| E07 Mobile UX / Deep Link / Observability | SourceRef jump links, reader intent reuse, `PaperReaderSourceJumpAudit`, deep-link evidence tests, selected-text `知识卡` / `研讨` menu entries, Settings AI `Concept graph` entry | formal knowledge objects carry jump-capable SourceRef, book anchor, or unavailable reason; source jump audit identifies jumpable, unavailable, and unresolved refs; user-facing activation tests cover visible menu actions and graph explorer entry | In Review slice |
| E08 Sync / Backup / Export | `lib/models/knowledge_sync.dart` | user asset vs derived cache boundary, default sync policy, secret payload exclusion, draft/export defaults, conflict review status | In Review slice |

## 3. Verification Commands

Focused model, adapter, tool-governance, RAG evidence and live-smoke skip tests:

```bash
flutter test --no-pub \
  test/models/source_ref_test.dart \
  test/models/ai_seminar_test.dart \
  test/models/knowledge_card_test.dart \
  test/models/review_item_test.dart \
  test/models/concept_graph_test.dart \
  test/models/ai_agent_governance_test.dart \
  test/models/knowledge_sync_test.dart \
  test/service/deeplink/paperreader_reader_intent_test.dart \
  test/service/rag/source_ref_adapter_test.dart \
  test/service/rag/semantic_search_result_test.dart \
  test/service/rag/semantic_search_library_search_test.dart \
  test/service/ai/tools/semantic_search_library_tool_test.dart \
  test/service/ai/tools/ai_tool_registry_governance_test.dart \
  test/service/ai/sub_agent_runner_governance_test.dart \
  test/service/ai/langchain_registry_governance_test.dart \
  test/service/ai/tool_orchestrator_governance_test.dart \
  test/service/ai/ai_seminar_evidence_broker_test.dart \
  test/service/ai/ai_seminar_orchestration_service_test.dart \
  test/service/knowledge/concept_graph_store_test.dart \
  test/providers/concept_graph_explorer_test.dart \
  test/page/settings_page/concept_graph_explorer_page_test.dart \
  test/service/knowledge/knowledge_card_store_test.dart \
  test/service/knowledge/selection_knowledge_card_producer_test.dart \
  test/service/review/knowledge_review_adapter_test.dart \
  test/service/review/seminar_synthesis_review_adapter_test.dart \
  test/service/review/review_item_store_test.dart \
  test/service/review/review_inbox_controller_test.dart \
  test/providers/review_inbox_test.dart \
  test/page/settings_page/review_inbox_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  test/widgets/context_menu/excerpt_menu_actions_test.dart \
  test/service/rag/live_rag_gateway_smoke_test.dart \
  -r compact
```

Focused E02 schema/progress tests:

```bash
flutter test --no-pub \
  test/service/rag/ai_index_schema_v2_test.dart \
  test/service/rag/ai_library_index_queue_repository_test.dart \
  test/service/rag/ai_library_index_queue_runner_test.dart \
  test/service/rag/ai_library_index_progress_text_test.dart \
  test/service/rag/ai_book_indexer_progress_test.dart \
  -r compact
```

Opt-in local provider smoke for the user-provided gateway:

```bash
PAPERTOK_LIVE_RAG_SMOKE=1 \
PAPERTOK_LIVE_RAG_BASE_URL=http://localhost:3003/v1 \
PAPERTOK_LIVE_RAG_API_KEY=<local-secret> \
PAPERTOK_LIVE_EMBED_MODEL=Qwen/Qwen3-Embedding-8B \
PAPERTOK_LIVE_RERANK_MODEL=Qwen/Qwen3-Reranker-8B \
flutter test --no-pub test/service/rag/live_rag_gateway_smoke_test.dart -r compact
```

安全要求：`PAPERTOK_LIVE_RAG_API_KEY` 只从环境变量读取，不进入仓库、fixture、golden、日志或同步数据。

最近验证记录：

- `2026-05-28 12:13 EDT`：focused suite 通过，`flutter test --no-pub ... -r compact` 结果为 `91 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 12:13 EDT`：`git diff --check` 通过。
- `2026-05-28 12:13 EDT`：future agentic docs 空话扫描通过；命令使用 README 中定义的禁用词清单作为匹配模式。
- `2026-05-28 12:13 EDT`：`dart analyze --no-fatal-warnings ...` 被 analyzer plugin setup 阻塞，原因是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 12:13 EDT`：rescue reviewer 复核 E01 修复，结论为 no blockers remain；复核范围是 role/evidence validation、`readyForReview` gate、candidate card ID 去重。
- E05 ReviewItemStore 局部验证：`flutter test --no-pub test/service/review/review_item_store_test.dart -r compact` 通过，覆盖 `.workflow/review_items_v1.json`、list/filter、draft submit、approve/apply、dismiss、orphan applied 降级和 malformed file degrade。
- `2026-05-28 12:22 EDT`：focused suite 通过，加入 `ReviewItemStore` 后结果为 `98 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 12:22 EDT`：E02 schema/progress focused tests 通过，覆盖 v10 migration、progress details、`force_rebuild` 入队并传入 runner executor。
- `2026-05-28 12:30 EDT`：E03 KnowledgeCardStore 局部验证通过，`flutter test --no-pub test/service/knowledge/knowledge_card_store_test.dart -r compact` 结果为 `6 passed`；覆盖 versioned file、duplicate guard、ReviewItem decision apply、legacy orphan downgrade、malformed file degrade、draft/applied sync envelope boundary。
- `2026-05-28 12:31 EDT`：agentic focused suite 通过，加入 `KnowledgeCardStore` 后结果为 `104 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 12:32 EDT`：`git diff --check` 通过；future agentic docs 禁用词扫描无命中。
- `2026-05-28 12:32 EDT`：`dart analyze --no-fatal-warnings lib/service/knowledge/knowledge_card_store.dart test/service/knowledge/knowledge_card_store_test.dart` 被 analyzer plugin setup 阻塞，原因仍是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 12:38 EDT`：rescue reviewer 指出的 E03 blocker 已修复并加回归测试：`upsertCandidate` 不再接受 pre-applied 候选绕过 Review，同 ID 候选冲突不覆盖已有用户内容；`flutter test --no-pub test/service/knowledge/knowledge_card_store_test.dart -r compact` 结果为 `8 passed`。
- `2026-05-28 12:38 EDT`：E03/E05/E08 相邻 suite 通过，结果为 `36 passed`；agentic focused suite 通过，结果为 `106 passed, 2 skipped`，两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 12:39 EDT`：`git diff --check` 通过；future agentic docs 禁用词扫描无命中。
- `2026-05-28 12:39 EDT`：`dart analyze --no-fatal-warnings lib/service/knowledge/knowledge_card_store.dart test/service/knowledge/knowledge_card_store_test.dart` 仍被 analyzer plugin setup 阻塞，原因是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 12:41 EDT`：rescue re-review 确认 E03 blockers no blockers remain；复核点包括 candidate Review 边界、same-ID 不覆盖、dedupe 仍有效、无 memory/notes/highlights/spaced-review 写入、文档禁用词无命中。残余风险：`upsert` 仍是宽写入口，后续 UI/runtime 接入时需限定为 internal/manual/migration path 或增加调用约束。
- `2026-05-28 12:43 EDT`：E04 ConceptGraphStore 局部验证通过，`flutter test --no-pub test/service/knowledge/concept_graph_store_test.dart -r compact` 结果为 `6 passed`；覆盖 versioned graph file、dossier、orphan/broken edge report、depth/width-limited exploration、malformed file degrade。
- `2026-05-28 12:44 EDT`：E04/E03 相邻 suite 通过，结果为 `20 passed`；agentic focused suite 通过，加入 `ConceptGraphStore` 后结果为 `112 passed, 2 skipped`，两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 12:45 EDT`：`git diff --check` 通过；future agentic docs 禁用词扫描无命中。
- `2026-05-28 12:45 EDT`：`dart analyze --no-fatal-warnings lib/service/knowledge/concept_graph_store.dart test/service/knowledge/concept_graph_store_test.dart` 被 analyzer plugin setup 阻塞，原因仍是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 12:50 EDT`：E04 rescue reviewer 指出的 graph formal bypass 和 untraceable traversal 已修复并加回归测试；`ConceptGraphStore` 写入 node/edge 时保持 `AI-generated-draft`，dossier/explore 只使用 traceable edge。局部验证 `flutter test --no-pub test/service/knowledge/concept_graph_store_test.dart -r compact` 结果为 `8 passed`。
- `2026-05-28 12:50 EDT`：E08 KnowledgeSyncPolicy 局部验证通过，`flutter test --no-pub test/models/knowledge_sync_test.dart -r compact` 结果为 `5 passed`；覆盖 draft/derived-index/secret payload 默认排除、unknown schema 和 delete-modify conflict 进入 Review。
- `2026-05-28 12:50 EDT`：E04/E08 相邻 suite 通过，结果为 `34 passed`；agentic focused suite 通过，结果为 `116 passed, 2 skipped`，两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 12:51 EDT`：`git diff --check` 通过；future agentic docs 禁用词扫描无命中。
- `2026-05-28 12:51 EDT`：`dart analyze --no-fatal-warnings lib/service/knowledge/concept_graph_store.dart test/service/knowledge/concept_graph_store_test.dart lib/models/knowledge_sync.dart test/models/knowledge_sync_test.dart` 被 analyzer plugin setup 阻塞，原因仍是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 12:52 EDT`：E07 SourceRef deep-link contract 局部验证通过，`flutter test --no-pub test/service/deeplink/paperreader_reader_intent_test.dart -r compact` 结果为 `4 passed`；覆盖 SourceRef -> reader intent、jumpLink 优先、unavailable/unresolved audit、malformed/non-reader link 拒绝。
- `2026-05-28 12:53 EDT`：rescue re-review 确认 E04/E08 no blockers remain；复核点包括 draft-only graph writes、traceable-edge dossier/explore、store write boundary、sync policy secret/cache exclusion、unknown schema/delete-modify conflict review。残余风险：ConceptGraph formal promotion API 尚未实现，Concept Dossier 当前是一跳且无独立 width cap。
- `2026-05-28 12:53 EDT`：E07/E00/E03/E04 相邻 suite 通过，结果为 `35 passed`。
- `2026-05-28 12:54 EDT`：agentic focused suite 通过，加入 E07 deep-link contract 后结果为 `120 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 12:55 EDT`：`git diff --check` 通过；future agentic docs 禁用词扫描无命中。
- `2026-05-28 12:55 EDT`：`dart analyze --no-fatal-warnings lib/service/deeplink/paperreader_reader_intent.dart test/service/deeplink/paperreader_reader_intent_test.dart lib/service/knowledge/concept_graph_store.dart test/service/knowledge/concept_graph_store_test.dart lib/models/knowledge_sync.dart test/models/knowledge_sync_test.dart` 被 analyzer plugin setup 阻塞，原因仍是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 13:05 EDT`：E06 custom skill contract 局部验证通过，`flutter test --no-pub test/models/ai_agent_governance_test.dart -r compact` 结果为 `8 passed`；覆盖 schemaVersion、JSON/Map parser、unknown field、unknown scene、system scene、write tool、recursive sub-agent、runtime injection gate。
- `2026-05-28 13:06 EDT`：E06 工具治理相邻 suite 通过，`flutter test --no-pub test/models/ai_agent_governance_test.dart test/service/ai/tools/ai_tool_registry_governance_test.dart test/service/ai/sub_agent_runner_governance_test.dart test/service/ai/tool_orchestrator_governance_test.dart -r compact` 结果为 `19 passed`。
- `2026-05-28 13:07 EDT`：E06 rescue blocker 修复后局部验证通过，`flutter test --no-pub test/models/ai_agent_governance_test.dart -r compact` 结果为 `10 passed`；新增覆盖 missing/non-integer `schemaVersion`、malformed `id/name/systemPromptAppend/allowedToolIds/scenes/enabled` 类型错误阻止 `canInject`。
- `2026-05-28 13:07 EDT`：E06 工具治理相邻 suite 复跑通过，`flutter test --no-pub test/models/ai_agent_governance_test.dart test/service/ai/tools/ai_tool_registry_governance_test.dart test/service/ai/sub_agent_runner_governance_test.dart test/service/ai/tool_orchestrator_governance_test.dart -r compact` 结果为 `21 passed`。
- `2026-05-28 13:08 EDT`：E06 rescue re-review 确认 no blockers remain；复核点包括 strict schemaVersion、malformed field type errors、unknown field、unknown scene、system scene、write tool、recursive sub-agent 和 `canInject` gate。
- `2026-05-28 13:09 EDT`：agentic focused suite 通过，加入 strict CustomSkillContract 后结果为 `125 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 13:11 EDT`：E06 analyzer info 修复后局部验证通过，`flutter test --no-pub test/models/ai_agent_governance_test.dart -r compact` 结果为 `10 passed`。
- `2026-05-28 13:11 EDT`：`dart analyze --no-fatal-warnings lib/models/ai_agent_governance.dart test/models/ai_agent_governance_test.dart` 仍被 analyzer plugin setup 阻塞，原因是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；移除多余 const 后该命令未返回代码诊断。
- `2026-05-28 13:23 EDT`：整体 rescue review 指出的 4 个 P1 blocker 已修复并加回归测试：RAPTOR/GraphRAG summary 与书内 evidence 分离、SourceRef jumpLink 严格校验、KnowledgeCardStore/ReviewItemStore raw upsert 不能绕过 Review、KnowledgeSyncPolicy 扩展 secret-like key 检测。
- `2026-05-28 13:23 EDT`：blocker adjacent suite 通过，`flutter test --no-pub test/models/source_ref_test.dart test/service/deeplink/paperreader_reader_intent_test.dart test/models/knowledge_sync_test.dart test/service/knowledge/knowledge_card_store_test.dart test/service/review/review_item_store_test.dart test/service/rag/semantic_search_library_search_test.dart test/service/rag/semantic_search_result_test.dart test/service/ai/tools/semantic_search_library_tool_test.dart -r compact` 结果为 `48 passed`。
- `2026-05-28 13:25 EDT`：agentic focused suite 通过，修复整体 rescue blockers 后结果为 `128 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 13:25 EDT`：`git diff --check` 通过；future agentic implementation docs 禁用词扫描无命中。
- `2026-05-28 13:25 EDT`：`dart analyze --no-fatal-warnings lib/models/source_ref.dart lib/models/knowledge_sync.dart lib/service/deeplink/paperreader_reader_intent.dart lib/service/knowledge/knowledge_card_store.dart lib/service/review/review_item_store.dart lib/service/rag/semantic_search_library.dart test/models/source_ref_test.dart test/models/knowledge_sync_test.dart test/service/deeplink/paperreader_reader_intent_test.dart test/service/knowledge/knowledge_card_store_test.dart test/service/review/review_item_store_test.dart test/service/rag/semantic_search_library_search_test.dart` 仍被 analyzer plugin setup 阻塞，原因是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 13:29 EDT`：整体 rescue re-review 确认 no blockers remain；复核点包括 E02 derived summary 分离、E00/E07 strict jumpLink、E03/E05 raw upsert boundary、E08 secret-like key 递归排除、文档未误标 Accepted。残余风险仅限 UI/runtime 端到端串接和真实 reader 打开行为验证。
- `2026-05-28 13:45 EDT`：E05 Review Inbox runtime/UI slice 通过，`flutter test --no-pub test/service/review/review_inbox_controller_test.dart test/providers/review_inbox_test.dart test/page/settings_page/review_inbox_page_test.dart -r compact` 结果为 `7 passed`；覆盖 KnowledgeCard approve/apply/dismiss mirror、source failure 不推进 ReviewItem、source jump audit、provider filter/action refresh、统一 Review Inbox 页面 smoke。
- `2026-05-28 13:47 EDT`：agentic focused suite 通过，加入 Review Inbox runtime/UI 后结果为 `136 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 13:47 EDT`：`git diff --check` 通过；future agentic implementation docs 禁用词扫描无命中。
- `2026-05-28 13:47 EDT`：`dart analyze --no-fatal-warnings lib/service/review/review_inbox_controller.dart lib/providers/review_inbox.dart lib/page/settings_page/review_inbox.dart lib/page/settings_page/ai.dart lib/page/home_page/settings_page.dart test/service/review/review_inbox_controller_test.dart test/providers/review_inbox_test.dart test/page/settings_page/review_inbox_page_test.dart` 仍被 analyzer plugin setup 阻塞，原因是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 13:57 EDT`：E05 rescue blockers 已修复并加回归测试：unsupported source type 不能被泛型 `apply` 推进为 applied，dismissed KnowledgeCard 保持 `AI-generated-draft` ownership；局部验证 `flutter test --no-pub test/service/review/review_inbox_controller_test.dart test/service/review/knowledge_review_adapter_test.dart test/page/settings_page/review_inbox_page_test.dart -r compact` 结果为 `13 passed`。
- `2026-05-28 13:57 EDT`：agentic focused suite 通过，结果为 `138 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 13:57 EDT`：`git diff --check` 通过；future agentic implementation docs 禁用词扫描无命中。
- `2026-05-28 13:57 EDT`：`dart analyze --no-fatal-warnings lib/service/review/review_inbox_controller.dart lib/providers/review_inbox.dart lib/page/settings_page/review_inbox.dart lib/service/review/knowledge_review_adapter.dart lib/page/settings_page/ai.dart lib/page/home_page/settings_page.dart test/service/review/review_inbox_controller_test.dart test/service/review/knowledge_review_adapter_test.dart test/providers/review_inbox_test.dart test/page/settings_page/review_inbox_page_test.dart test/page/settings_page/settings_navigation_compile_test.dart` 仍被 analyzer plugin setup 阻塞，原因是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 13:57 EDT`：E05 rescue re-review 确认 no blockers remain；复核点包括 unsupported non-KnowledgeCard apply 拒绝、dismissed KnowledgeCard draft ownership、UI Apply sourceType gate、文档禁用词扫描。残余风险：source mirror 与 ReviewItem persistence 仍是两个文件写入、UI disabled Apply 缺少 widget 级断言、analyzer 被 TLS 阻塞。
- `2026-05-28 14:03 EDT`：E04/E05 ConceptGraph relation Review apply 局部验证通过，`flutter test --no-pub test/service/review/knowledge_review_adapter_test.dart test/service/knowledge/concept_graph_store_test.dart test/service/review/review_inbox_controller_test.dart -r compact` 结果为 `26 passed`；覆盖 relation -> ReviewItem、approved 不 formal、applied 才升级 ownership、missing/mismatched edge 拒绝、ReviewInboxController source mirror。
- `2026-05-28 14:06 EDT`：agentic focused suite 通过，加入 ConceptGraph relation Review apply 后结果为 `144 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 14:06 EDT`：`git diff --check` 通过；future agentic implementation docs 禁用词扫描无命中。
- `2026-05-28 14:06 EDT`：`dart analyze --no-fatal-warnings lib/service/review/review_inbox_controller.dart lib/providers/review_inbox.dart lib/page/settings_page/review_inbox.dart lib/service/review/knowledge_review_adapter.dart lib/service/knowledge/concept_graph_store.dart lib/page/settings_page/ai.dart lib/page/home_page/settings_page.dart test/service/review/review_inbox_controller_test.dart test/service/review/knowledge_review_adapter_test.dart test/service/knowledge/concept_graph_store_test.dart test/providers/review_inbox_test.dart test/page/settings_page/review_inbox_page_test.dart test/page/settings_page/settings_navigation_compile_test.dart` 仍被 analyzer plugin setup 阻塞，原因是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 14:09 EDT`：Epic 文件头和 task table 已对齐到 In Review slice 口径；`git diff --check` 通过，future agentic implementation docs 禁用词扫描无命中。
- `2026-05-28 14:14 EDT`：rescue review 指出的 2 个 P1 blocker 已修复并加回归测试：`ReviewItemStore.apply` 对未接 source-specific apply adapter 的来源抛出 `UnsupportedError` 且不推进状态；`KnowledgeSyncEnvelope.fromJson` 对缺 required fields 标记 `missing-required-fields` conflict，缺 `conflictStatus` 本身不制造 conflict；E08 artifact 名称已对齐为 `KnowledgeSyncConflictDetector.reviewEnvelopeFor`。局部验证 `flutter test --no-pub test/service/review/review_item_store_test.dart test/models/knowledge_sync_test.dart -r compact` 结果为 `16 passed`。
- `2026-05-28 14:16 EDT`：agentic focused suite 通过，修复最终 rescue blockers 后结果为 `147 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 14:16 EDT`：`git diff --check` 通过；future agentic implementation docs 禁用词扫描无命中；用户提供的本地 gateway API key 明文扫描无命中。
- `2026-05-28 14:16 EDT`：`dart analyze --no-fatal-warnings lib/service/review/review_item_store.dart lib/models/knowledge_sync.dart test/service/review/review_item_store_test.dart test/models/knowledge_sync_test.dart` 仍被 analyzer plugin setup 阻塞，原因是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 14:16 EDT`：final rescue re-review 确认 no blockers remain；复核点包括 `ReviewItemStore.apply` 底层 sourceType 白名单、unsupported source direct apply 回归测试、E08 artifact 名称、missing required fields conflict review、缺 `conflictStatus` 兼容行为。
- `2026-05-28 23:26 EDT`：用户可用入口切片通过，`flutter test --no-pub test/service/knowledge/selection_knowledge_card_producer_test.dart test/widgets/context_menu/excerpt_menu_actions_test.dart -r compact` 结果为 `5 passed`；覆盖选中文本 -> KnowledgeCard -> Review Inbox、重复选中不重复写卡、已批准卡不重新进入 pending Review、空选中拒绝写入、阅读页选中菜单显示 `Card/Seminar`。
- `2026-05-28 23:26 EDT`：KnowledgeCard/Review Inbox 相邻 suite 通过，`flutter test --no-pub test/service/knowledge/selection_knowledge_card_producer_test.dart test/service/knowledge/knowledge_card_store_test.dart test/service/review/review_item_store_test.dart test/service/review/review_inbox_controller_test.dart test/page/settings_page/review_inbox_page_test.dart test/widgets/context_menu/excerpt_menu_actions_test.dart -r compact` 结果为 `30 passed`。
- `2026-05-28 23:23 EDT`：`dart analyze --no-fatal-warnings lib/service/knowledge/selection_knowledge_card_producer.dart lib/widgets/context_menu/excerpt_menu.dart test/service/knowledge/selection_knowledge_card_producer_test.dart test/widgets/context_menu/excerpt_menu_actions_test.dart` 仍被 analyzer plugin setup 阻塞，原因是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 23:26 EDT`：独立 rescue reviewer 复核用户入口切片，结论为 no blockers；指出的重复已批准卡 toast 边界已用 `knowledgeCardAlreadySaved` 和回归测试修正。残余风险：真实 reader SourceRef 回跳仍缺端到端 UI 测试，card store 与 review store 是两个文件写入。
- `2026-05-28 23:27 EDT`：agentic focused suite 通过，加入用户入口切片后结果为 `152 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 23:35 EDT`：ConceptGraph Explorer 入口切片通过，`flutter test --no-pub test/providers/concept_graph_explorer_test.dart test/page/settings_page/concept_graph_explorer_page_test.dart test/page/settings_page/settings_navigation_compile_test.dart -r compact` 结果为 `4 passed`；覆盖 graph provider refresh、dossier/local path、orphan/broken link 可见、Settings AI 页面编译。
- `2026-05-28 23:38 EDT`：agentic focused suite 通过，加入 ConceptGraph Explorer 入口后结果为 `155 passed, 2 skipped`；两个 skipped 均为 opt-in live RAG gateway smoke。
- `2026-05-28 23:38 EDT`：`git diff --check` 通过；future agentic docs 禁用词扫描无命中；用户提供的本地 gateway API key 明文扫描无命中。
- `2026-05-28 23:38 EDT`：`dart analyze --no-fatal-warnings lib/providers/concept_graph_explorer.dart lib/page/settings_page/concept_graph_explorer.dart lib/page/settings_page/ai.dart test/providers/concept_graph_explorer_test.dart test/page/settings_page/concept_graph_explorer_page_test.dart test/page/settings_page/settings_navigation_compile_test.dart` 仍被 analyzer plugin setup 阻塞，原因是 `custom_lint` 从 `https://pub.dev` 解析时出现 TLS error；该命令未返回代码诊断。
- `2026-05-28 23:41 EDT`：独立 rescue reviewer 复核 ConceptGraph Explorer 用户入口与 README/04 状态表，结论为 no blockers；确认 README 未把 producer/阅读页入口/Spaced Review/Sync Export 标成已可用，Explorer 只调用 `listNodes`、`inspectIntegrity`、`buildDossier`、`exploreFrom`，不创建 node/edge，不绕过 Review。

## 4. Rescue Review Checklist

- AI 生成内容默认 draft 或 pending，不自动写长期记忆、笔记、卡片或复习项。
- KnowledgeCardStore 只持久化卡片资产状态，不写长期记忆、笔记、高亮或 spaced review；`upsertCandidate` 会把 Review 前候选保持为 draft/pending + `AI-generated-draft`，raw `upsert` 只接受 draft/pending AI candidates，draft/pending envelope 使用 `ai-draft`，只有 Review apply 后的 user asset 才使用 `knowledge-card`。
- SelectionKnowledgeCardProducer 只把选中文本写成待审 KnowledgeCard 和 ReviewItem；重复选中复用已有卡，不写长期记忆、笔记、高亮或 spaced review。
- KnowledgeCardStore 的候选写入把同 ID 视为冲突，不用生成内容覆盖已有用户 note、quote 或 title；显式修改必须走 source-specific apply/update 路径。
- 正式 KnowledgeCard、ReviewItem、Seminar synthesis、ConceptNode、ConceptEdge 必须有 SourceRef book anchor、jump link 或不可跳原因；hash-only fingerprint 只能保留为 draft/unapplied。
- ConceptGraphStore 只写 `.knowledge/concept_graph_v1.json`，node/edge 写入保持 draft ownership；dossier 和局部探索只走有 traceable evidence 的边，并按 depth 和每层 width clamp；orphan node 与 broken edge 必须可报告，不把图谱推断自动写成用户确认资产。
- ConceptGraphExplorerPage 只读取和展示已有 ConceptGraphStore 数据；没有 producer 数据时展示空态，不自动创建概念节点或关系。
- ConceptGraph relation 通过 `ConceptGraphReviewAdapter` 进入 Review；approved 只推进 ReviewItem，不把 edge 变成 formal，只有 applied 且有 evidence 的 edge 才升级为 `AI-generated-approved` ownership。
- KnowledgeSyncPolicy 默认只同步用户确认资产类 envelope；`ai-draft`、`derived-index`、含 API key/token/secret/auth/authorization/bearer/private-key/credential/password 类 payload 的 envelope 默认排除，冲突和未知 schema 进入 Review。
- PaperReaderReaderIntent 可以从 SourceRef 生成 reader deep link intent；SourceRef jumpLink 必须是可解析的 `paperreader://reader/open?...` 且包含 bookId 与 href/cfi 才能算 jumpable evidence；PaperReaderSourceJumpAudit 负责区分 jumpable、unavailable 和 unresolved source refs。
- RAPTOR/GraphRAG summary 只能作为 `derivedSummary/derivedLayer` 检索提示返回，SourceRef 的 formal evidence snippet 必须来自映射到的书内 chunk 原文。
- `chunkId` 只作为 `ai_index.db` derived cache hint，不作为用户资产身份。
- ReviewItemStore 只记录审批状态和 sourceRefs，不直接执行 KnowledgeCard、Memory、Flashcard 等源资产写入；raw `upsert` 只接受 draft/pending item，UI/runtime 必须走 `ReviewInboxController`，由 source-specific adapter 先验证源资产再推进 ReviewItem transition；未接 source-specific apply adapter 的来源不能通过泛型 apply 进入 applied。
- Seminar/governed sub-agent 默认不开 web；写工具不进入 Seminar 白名单。
- CustomSkillContract 只接受 schemaVersion `1` 的显式 JSON/Map contract；缺失或非整数 schemaVersion、malformed 字段类型、未知字段、未知 scene、system scene、写工具和 `spawn_sub_agent` 都会阻止 runtime injection。
- AI Seminar 编排服务默认串行执行 `critical / supportive / synthesizer`，`verifier` 只在 session contract 中显式出现时加入，且 `synthesizer` 保持最后。
- AI Seminar role executor 的返回值必须匹配当前 role，且每个非失败 role turn 必须引用可追踪 evidence；不合格 turn 不进入后续 `priorTurns`。
- AI Seminar evidence broker 默认 current book first；只有 current-book evidence 不足或 session 明确包含 library scope 时才使用 library evidence。
- Seminar synthesis 只有同时满足 `readyForReview` 和 traceable handoff 才能进入 pending Review；候选 KnowledgeCard ID 必须处理空 ID 和重复 ID。
- 阅读页 `研讨` 入口当前只打开 `seminar_mode` 草稿，不等同于结构化多 agent runtime，也不自动写 ReviewItem。
- API key 不同步、不导出、不写测试文件。
- Live smoke 是显式 opt-in，不进入默认 `flutter test` 网络依赖。
