# Retrieval Quality Gates

## 1. Pre-Gate

涉及 RAG、RAPTOR、GraphRAG、ConceptGraph、Seminar evidence 或 KnowledgeCard source 的任务，执行前必须确认：

- 输入来源是 current book、library RAG、notes、memory、card 还是 external web。
- 输出是否需要 SourceRef。
- 无 evidence 的输出是否只能作为 draft。
- `ai_index.db` 是否仍是 derived-cache。

## 2. Required Acceptance

至少覆盖适用项：

- RAG result 带 provenance。
- `paperreader://reader/open?...` 可从 UI 或测试路径回跳。
- GraphRAG 推断和书内证据分开标记。
- ConceptNode/ConceptEdge 有 evidenceRefs 或为 draft。
- 旧 DB 升级、新索引失效、书籍删除、provider 切换、无 embedding、FTS5 不可用、网络失败、重启续跑有验证说明。

## 3. Failure Handling

- 无 embedding：降级到 text/FTS/LIKE 检索，并在诊断中标明。
- 无 FTS5：使用 fallback，并保留 evidence。
- 网络失败：任务进入 retry/failed 状态，不丢已完成进度。
- source book 缺失：输出标记 orphan，不自动删除用户资产。

## 4. Rescue Review Questions

- 输出是否能解释“为什么相关”？
- 是否有任何 node/edge/card 缺少证据却被标成正式？
- 是否把可重建索引当成同步真相源？
- 是否破坏 current book 优先的默认检索范围？

