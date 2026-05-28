# Sync Backup Export Gates

## 1. Pre-Gate

涉及同步、备份、恢复或导出的任务，执行前必须确认：

- 数据是 source-of-truth、user asset、AI draft、derived-cache 还是 secret。
- 是否包含 `sourceTextSnippet`，以及 snippet 是否超过 500 个字符。
- 是否包含完整书籍正文、完整 chunk、图片原始内容或长 OCR 文本。
- 是否包含 API key 或 provider secret。
- 冲突是否进入 Review，而不是静默覆盖。

## 2. Required Acceptance

任务完成时必须证明：

- API key 永不同步到明文 WebDAV。
- 用户资产有 stable id、schemaVersion、updatedAt 和 tombstone 策略。
- 派生索引默认不作为跨端 source-of-truth。
- 旧 schema、缺字段、未知字段可读或有明确失败提示。
- 导出 manifest 标明是否包含全文证据包。

## 3. Default Policies

- `ai_index.db` 默认不同步，可选备份时必须标记为 rebuildable cache。
- KnowledgeCard approved 和 Review history 是用户资产，可以进入 per-entity sync。
- AI draft 默认不同步；用户显式选择时必须标记为 draft。
- SourceRef 默认只同步短 snippet、hash、deep link 和 evidence metadata。

## 4. Rescue Review Questions

- 是否把 whole-file newer-wins 用在用户知识资产上？
- 是否把派生缓存当作唯一真相源？
- 是否把长正文随 source ref 默认同步或导出？
- 冲突是否会覆盖用户确认内容？

