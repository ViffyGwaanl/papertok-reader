# E08 Sync, Backup, And Export

> 状态：In Review
> 目标：同步和导出用户确认过的知识资产，而不是默认同步派生索引。

## 1. 数据策略

| 数据 | 归属 | 默认同步 | 默认备份 | 说明 |
| --- | --- | --- | --- | --- |
| API key | secret | 否 | 仅加密手动备份可选 | 永不同步到 WebDAV 明文设置。 |
| AI settings | config | 是 | 是 | 继续排除密钥。 |
| `ai_index.db` | derived-cache | 否 | 可选 | 可删除重建。 |
| RAPTOR/GraphRAG 索引 | derived-cache | 否 | 可选 | 不是 source-of-truth。 |
| KnowledgeCard approved | user asset | 是 | 是 | per-entity sync。 |
| Review history | user asset | 是 | 是 | 包含敏感学习状态。 |
| AI draft | draft | 否或可选 | 可选 | 默认不跨设备扩散。 |

SourceRef 同步/导出默认只包含 `sourceTextSnippet`，且 snippet 上限 500 个字符。完整 chunk、整章文本、图片原始内容和长 OCR 文本不得随 source ref 默认同步；需要用户显式选择导出全文证据包时，必须在 export manifest 中标明。

## 2. Capability

### E08-C01 Per-Entity Sync Contract

用户资产不能使用 settings-style whole-file newer-wins。需要：

- stable id
- updatedAt
- deletedAt/tombstone
- sourceRefs
- schemaVersion
- conflict status

### E08-C02 Conflict Review

冲突默认进入 Review，不静默覆盖：

- 两端都改过卡片。
- 一端删除一端修改。
- source book 缺失。
- schema 版本未知。

当前本分支已接入本地冲突 handoff、远端 bundle preview 和受保护 sync bundle 上传：`Knowledge sync/export` 页面可把待审冲突发送为 `sync-conflict` ReviewItem，也可读取配置 SyncClient/WebDAV 上的 `paper_reader/.knowledge/knowledge_sync_bundle_v1.json`，展示 remote/incoming/outgoing/conflict 计数，并把远端冲突送入同一 Review 流。该 handoff 只保存安全 metadata、payload key 列表和 SourceRef；没有 SourceRef 的冲突会带 `sync-conflict-no-source` 不可跳原因；不保存 raw payload value、API key、token、secret 或派生缓存内容。安全的本地 KnowledgeCard 冲突可由用户在 Review Inbox 中 approve/apply 后解除 pending conflict metadata；安全条件固定为 `entityType=knowledge-card`、`schemaVersion=1`、payload 不含 secret-like key、且 SourceRef 可追踪到书内来源或 reader jump link。远端 preview 产生的冲突在 v1 中一律 `canApply=false`，只支持 triage/dismiss，直到后续 staging/import 执行器接入。`Upload sync bundle` 上传前重新生成本机安全 bundle；远端不存在时可初始化写出，远端存在时必须先通过 preview gate，若存在 incoming 或 conflict 则阻止覆盖。双向自动合并、staging/import、rollback 和冲突写回执行器仍是独立任务。

### E08-C03 Export

导出目标：

- Markdown
- HTML study report
- Anki-compatible package
- source citation manifest
- machine-readable sync bundle

导出必须保留 source refs 和 evidence status。

## 3. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E08-C01-T01 | 定义 per-entity sync schema | E03-C01-T01 Accepted, E05-C01-T01 Accepted | sync contract | stable id、tombstone、conflict 明确。 |
| E08-C01-T02 | 接入 knowledge sync policy model | E08-C01-T01 | `lib/models/knowledge_sync.dart` | user asset、AI draft、derived cache、secret payload 默认策略有测试。 |
| E08-C02-T01 | 定义 conflict review flow | E08-C01-T01 | conflict spec | 冲突进入 Review，不自动 last-write-wins。 |
| E08-C02-T02 | 接入 conflict classification contract | E08-C02-T01 | `KnowledgeSyncConflictDetector.reviewEnvelopeFor` | old/unknown schema、delete-modify、missing fields 进入 Review。 |
| E08-C02-T03 | 接入本地 sync-conflict Review handoff | E08-C02-T02, E05 ReviewItemStore | `KnowledgeAssetExportService.submitConflictsToReview`、`ReviewItemSourceType.syncConflict`、`KnowledgeAssetExportPage` action | 待审冲突可从 Knowledge sync/export 发送到 Review Inbox；重复点击不制造重复 ReviewItem；无 SourceRef 冲突有不可跳原因；ReviewItem payload 不包含 raw payload value 或 secret 值；ReviewItem payload 用 `canApply` 明确区分可本地恢复和只可 triage 的冲突。 |
| E08-C02-T04 | 接入安全 KnowledgeCard 冲突本地恢复 | E08-C02-T03, E03 KnowledgeCardStore, E05 ReviewInboxController | `KnowledgeCardStore.resolveSyncConflict`、`ReviewItemStore.applyResolvedSyncConflict`、`ReviewInboxController` sync-conflict apply gate、Review Inbox safe approve/apply UI | 只有 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef` 的冲突可 approve/apply；apply 后解除 pending conflict metadata 并写回为用户确认资产；generic `ReviewItemStore.apply` 拒绝 sync-conflict；unsafe conflict 仍只显示 dismiss；不创建 SpacedReview、ConceptGraph、Memory、Note 或远端同步 side effect。 |
| E08-C02-T05 | 接入远端 sync bundle preview 和远端冲突 Review handoff | E08-C02-T04, SyncClient/WebDAV config, E05 ReviewItemStore | `KnowledgeRemoteSyncPreview`、`KnowledgeAssetExportService.previewRemoteSync`、`submitRemoteConflictsToReview`、`KnowledgeAssetExportPage` remote actions | 页面可读取远端 sync bundle 并展示 remote/incoming/outgoing/conflict 计数；preview 不导入 incoming、不覆盖本地资产；远端冲突进入 `sync-conflict` ReviewItem，payload 不含 raw remote payload value 或 secret；不执行远端写回或自动合并。 |
| E08-C02-T06 | 接入受保护 sync bundle 远端写出 | E08-C02-T05, SyncClient/WebDAV config | `KnowledgeAssetExportService.uploadRemoteSyncBundle`、`KnowledgeRemoteSyncUploadResult`、`KnowledgeAssetExportPage` upload action | 上传前重新生成安全 bundle；远端不存在时创建目录并写出；远端存在时先 preview，只有无 incoming 且无 conflict 才允许 replace；阻止时不写远端、不导入 incoming、不应用远端冲突。 |
| E08-C03-T01 | 定义 export manifest、本地 Markdown 导出、HTML study report、Anki TSV 导出和 sync bundle | E00 Ready, E03 Ready | export spec, local Markdown writer, local HTML report writer, local Anki TSV writer, safe sync bundle writer | Manifest、Markdown、HTML study report、Anki TSV 和 sync bundle 保留 source refs；本地/远端冲突 handoff 已接入，远端写回和双向合并执行器仍需独立任务接入。 |

## 4. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | AI settings sync policy, backup/restore docs, KnowledgeCard/Review contracts, SourceRef snippet policy。 |
| Allowed Modules | sync/backup/export services, manifest docs/tests, review conflict UI specs。 |
| Forbidden Changes | 不同步 API key；不默认同步 `ai_index.db`；不默认导出完整书籍正文；不使用 whole-file newer-wins 同步用户资产。 |
| Verification Commands | Focused tests for old schema, missing fields, unknown fields, key preservation, tombstone/conflict; `git diff --check`。 |
| Reviewer Gate | Agent Safety And Privacy Gate + Sync Backup Export Gate + Review And Rescue Gate。 |
| Rollback / Degrade Path | 同步失败进入 local-only pending/conflict 状态；导出失败不修改用户资产。 |

## 5. Gates

- Agent Safety And Privacy Gate：密钥永不同步；学习弱点默认本地或明确提示。
- Sync Backup Export Gate：旧 schema、缺字段、未知字段、冲突恢复有验证。
- Review And Rescue Gate：同步/导出冲突必须可审查。
- Retrieval Quality Gate：导出内容保留 source/evidence 状态。

## 6. Non-Goals

- 不默认同步 `ai_index.db`。
- 不用 whole-file newer-wins 同步用户知识资产。
- 不导出未经确认的 AI draft，除非用户显式选择。
