# E02 Library RAG / RAPTOR / GraphRAG

> 状态：In Review
> 目标：把 RAG/RAPTOR/GraphRAG 从技术路线图重构成可执行、可验证、可回滚的能力栈。

## 1. 当前事实

- 现有 Library RAG 已支持 hybrid retrieval、FTS/BM25、vector、MMR 和 reader jump link。
- `ai_index.db` 是可重建派生缓存，不是用户资产 source-of-truth。
- 当前实现已有 RAPTOR/GraphRAG 方向的表和 builder 雏形。
- 新迁移必须以当前 `kAiIndexDbVersion` 为事实；不得在计划中继续写过期的 v6/v7 作为未来目标。

## 2. Capability

### E02-C01 Evidence Contract Alignment

把 `semantic_search_library`、`semantic_search_current_book`、RAPTOR、GraphRAG 输出对齐到 SourceRef。

### E02-C02 Retrieval Quality Stack

能力分层：

1. deterministic text retrieval
2. vector retrieval
3. query fusion
4. rerank
5. neighbor expansion
6. contextual chunk
7. RAPTOR summary retrieval
8. GraphRAG local/global retrieval

每层必须可单独关闭或降级。

### E02-C03 Index Lifecycle

覆盖：

- 旧 DB 升级。
- 新索引失效。
- 书籍删除。
- provider 切换。
- 无 embedding。
- FTS5 不可用。
- 网络失败。
- 重启续跑。
- 书籍级进度。

### E02-C04 GraphRAG Evidence Rules

GraphRAG 的 node/edge/community 必须保留 chunk evidence。模型推断和书内证据必须分开。

## 3. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E02-C01-T01 | 对齐 RAG evidence 到 SourceRef | E00 Ready | evidence contract | current/book/library/global evidence 字段一致。 |
| E02-C01-T02 | 接入 library/current-book evidence SourceRef | E02-C01-T01 | RAG result `sourceRef`, `SourceRefAdapter` | RAG evidence 可回指 source ref，GraphRAG/RAPTOR summary 与书内 evidence 分离。 |
| E02-C02-T01 | 拆分检索能力开关 | E02-C01-T01 | capability matrix | 每层有 enable/disable 和降级说明。 |
| E02-C03-T01 | 定义索引生命周期测试矩阵 | E02-C02-T01 | test matrix | 覆盖旧 DB、删除、provider、FTS5、网络、重启。 |
| E02-C03-T02 | 定义书籍级进度 contract | E02-C03-T01 | progress spec | UI 能显示当前书、章节、阶段、失败原因。 |
| E02-C03-T03 | 接入 index schema/progress validation | E02-C03-T01, E02-C03-T02 | v10 migration/progress tests | DB version 从 main v8 递增，`force_rebuild` 和 detailed progress 可验证。 |
| E02-C04-T01 | 定义 GraphRAG evidence policy | E02-C01-T01 | graph evidence policy | 无 chunk evidence 的 node/edge 只能是 draft。 |
| E02-C04-T02 | 接入 live provider smoke harness | E02-C01-T02 | `live_rag_gateway_smoke_test.dart` | embedding/rerank gateway smoke 显式 opt-in，默认测试无网络依赖。 |

## 4. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | `ai_index_schema.dart` 当前 DB version、`semantic_search_library.dart`、`ai_book_indexer.dart`、RAG optimization docs/tests。 |
| Allowed Modules | `lib/service/rag`, `lib/service/ai/tools/semantic_search_library_tool.dart`, focused RAG tests/docs。 |
| Forbidden Changes | 不回退 DB version；不把 v6/v7 写成未来迁移目标；不默认同步 `ai_index.db`；不移除 fallback。 |
| Verification Commands | Focused RAG tests covering migration/retrieval/progress/fallback; `git diff --check`。 |
| Reviewer Gate | Retrieval Quality Gate + Mobile Resource Gate + Review And Rescue Gate。 |
| Rollback / Degrade Path | 每层 retrieval capability 必须可关闭，失败时回退到现有 hybrid RAG。 |

## 5. Gates

- Retrieval Quality Gate：所有正式 evidence 可追溯。
- Mobile Resource Gate：长索引任务可暂停、取消、恢复或重试。
- Review And Rescue Gate：检查 `ai_index.db` 没有被写成用户资产真相源。

## 6. Non-Goals

- 不把 ANN/native vector 作为默认生产路径。
- 不默认同步 `ai_index.db`。
- 不在无证据时生成正式 GraphRAG 节点。
