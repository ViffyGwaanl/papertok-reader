# P3 Intelligent Index Retrieval Foundation

> 状态：In Progress
> 最后更新：2026-06-03
> 目标：补完支撑 AI Chat 原生研讨会和全书 AI 理解地图的生产级索引、检索、向量和 ANN 底座。

## 1. 用户价值

这个优先级不是为了证明“能语义检索”。PaperTok 已经有语义检索能力。现在要补的是生产级底座：大书、多书、全书理解地图、AI 研讨会证据收集、图谱生成和 AI Chat 检索都需要快、准、可解释、可恢复、低内存。

用户最终看到的是：

- 每本书当前能用哪些 AI 能力。
- 缺哪一层索引会影响什么体验。
- 修复、升级和构建进度可见。
- 大书搜索不发热、不全量扫、不漏召回。
- AI 结论都能回到稳定 SourceRef。

## 2. 当前状态

当前分支已有：

- 基础 `ai_chunks` 和 embedding 存储。
- current-book / library semantic search。
- FTS/BM25 + vector hybrid recall 方向。
- native vector shadow rows。
- Vec1/ANN table builder、per-book sidecar、ANN fallback 方向。
- AI Index readiness 行内状态、vector/ANN/global/graph 层提示。
- 部分 embedding 缺失、维度混用、旧 provider/model row 的 gate。
- 旧索引全局层补建和 derived graph 预览。

当前主要问题：

- 移动端 sqlite-vec/Vec1 extension/package 还不是发布级能力。
- ANN build job 还缺恢复、暂停、失败续跑和真机资源 gate。
- provider/model/dim 失效后整体派生层重建策略还不完整。
- P2 需要的 AI semantic graph builder 还没有接入统一检索和证据层。
- RAG、RAPTOR、GraphRAG/AI graph、rerank 的统一候选池仍需明确最终策略。

## 3. 目标形态

索引底座分为五层：

1. Base：chunk、章节、SourceRef、原文摘录、hash、分块版本。
2. Embedding：provider/model/dim 一致的 chunk embedding。
3. Vector：native compact vector rows，作为 ANN 构建来源和 exact fallback。
4. ANN：per-book sidecar 和 library-level ANN，带完整性检查和 fallback。
5. Global/Graph：RAPTOR、AI semantic graph、guided tours 的可重建派生缓存。

所有层都必须有 readiness、进度、失败原因、修复动作和用户价值解释。

## 4. 阶段计划

### P3-S1：readiness 语义稳定

统一 `Base / Embedding / Vector / ANN / Global / AI Graph` 的状态定义。

验收：

- 部分 embedding 缺失不能显示 vector ready。
- provider/model/dim 不一致不能继续构建 ANN。
- 旧 chunk/hash/schema 失效时屏蔽派生层补建。
- 页面用用户能懂的话解释当前可用能力和下一步。

### P3-S2：移动端 ANN 发布闭环

把 Vec1/sqlite-vec 或候选 ANN backend 做成可打包、可加载、可降级的移动端能力。

验收：

- iOS/Android/macOS 真机或等效环境有加载 gate。
- extension 不可用时自动 fallback，不影响搜索。
- ANN/exact overlap gate 通过固定 fixture。

### P3-S3：可恢复 ANN build job

ANN 构建要支持进度、取消、失败重试、断点恢复和资源限制。

验收：

- 大书构建不会阻塞 UI。
- 取消后不写 ready meta。
- 失败后保留可读错误和 retry 动作。
- 低电量/后台/内存压力策略明确。

### P3-S4：统一 hybrid retrieval

把 FTS/BM25、vector、ANN、RAPTOR summary、AI graph evidence、rerank 放进统一候选池和排序策略。

验收：

- chunk evidence 和 derived summary 分开标记。
- RRF/rerank 策略可测试。
- SourceRef 始终指向原文 chunk，而不是只指向摘要。
- AI Chat、Seminar、Book Map 共用同一证据服务。

### P3-S5：AI semantic graph 索引依赖

为 P2 的 AI semantic graph builder 提供稳定输入和失效策略。

验收：

- builder 能读取稳定 chunk group 和章节结构。
- model/schema 变化可触发只重建 AI graph layer。
- deterministic graph layer 和 ai_semantic graph layer 状态可区分。

### P3-S6：用户可见索引任务中心

把索引状态、修复、升级、ANN 构建、全局层构建、AI graph 构建放在用户能理解的任务队列中。

验收：

- 用户知道为什么需要构建。
- 用户知道构建完成会解锁什么。
- 用户可以暂停/重试/查看失败原因。

## 5. 不做事项

- 不因为已有旧 semantic search 就把索引底座标成完成。
- 不在 ANN 不完整时假装 ANN ready。
- 不把 GraphRAG/AI graph summary 当作原文证据。
- 不让图谱和研讨会各自实现一套检索逻辑。

## 6. 更新要求

推进 P3 时必须更新：

- 本文件的层状态和完成情况。
- `../implementation_status_zh.md` 的测试证据。
- `../04_user_facing_activation_plan_zh.md` 的 AI Index 用户入口。
- P1/P2 文档中依赖 P3 的状态说明。

## 7. 状态更新记录

- 2026-06-03：建立 P3 详细计划。当前状态为 In Progress；语义检索已存在，但生产级 ANN、恢复构建和统一 evidence service 仍需补完。
