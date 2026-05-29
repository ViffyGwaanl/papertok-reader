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

### E08-C03 Export

导出目标：

- Markdown
- HTML study report
- Anki-compatible package
- source citation manifest

导出必须保留 source refs 和 evidence status。

## 3. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E08-C01-T01 | 定义 per-entity sync schema | E03-C01-T01 Accepted, E05-C01-T01 Accepted | sync contract | stable id、tombstone、conflict 明确。 |
| E08-C01-T02 | 接入 knowledge sync policy model | E08-C01-T01 | `lib/models/knowledge_sync.dart` | user asset、AI draft、derived cache、secret payload 默认策略有测试。 |
| E08-C02-T01 | 定义 conflict review flow | E08-C01-T01 | conflict spec | 冲突进入 Review，不自动 last-write-wins。 |
| E08-C02-T02 | 接入 conflict classification contract | E08-C02-T01 | `KnowledgeSyncConflictDetector.reviewEnvelopeFor` | old/unknown schema、delete-modify、missing fields 进入 Review。 |
| E08-C03-T01 | 定义 export manifest 和本地 Markdown 导出 | E00 Ready, E03 Ready | export spec, local Markdown writer | Manifest 和 Markdown 保留 source refs；HTML/Anki 仍需独立任务接入。 |

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
