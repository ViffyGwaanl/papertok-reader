# E04 ConceptGraph And WikiLinks Explorer

> 状态：In Review
> 目标：融合 Understand-Anything 的图谱理解思路和 WikiLinks 的局部概念探索，建立可证据追溯的 PaperTok ConceptGraph。

## 1. 融合方式

ConceptGraph 服务于阅读理解，不是炫技图谱：

- 先做局部概念页和 1-3 跳探索。
- 所有正式 node/edge 都要有 evidence。
- 关系来自书内 chunk、KnowledgeCard、用户确认关系或 AI draft。
- 图谱默认是派生层；用户确认过的关系才是用户资产。

## 2. Capability

### E04-C01 Concept Node Contract

节点类型：

- concept
- entity
- claim
- method
- book
- chapter
- card

节点必须包含 source refs 或标记为 draft/unverified。

### E04-C02 Concept Edge Contract

边类型：

- explains
- supports
- contradicts
- exemplifies
- depends_on
- related_to
- appears_in

每条边必须保留 evidenceRefs、confidence 和 ownership。

### E04-C03 Concept Dossier

概念页展示：

- 定义。
- 出现在哪些书/章节/卡片。
- 相关概念。
- 支持和反驳证据。
- 推荐下一跳。
- 回到阅读位置。

### E04-C04 Exploration Path

WikiLinks 式探索必须可控：

- 默认深度不超过 2。
- 默认每层不超过 7 个节点。
- 记录返回路径。
- 外部百科补充默认 opt-in。

### E04-C05 Full-Book Derived Graph Preview

全书图谱是只读派生层，不等于用户确认资产：

- Settings Explorer 可列出已有全局层索引的书。
- 阅读页图谱入口可直接带入当前 bookId。
- 只展示有 chunk SourceRef 的 GraphRAG node/edge。
- 点击全书图谱节点必须显示摘要、相邻关系、证据摘录和回跳来源；无 SourceRef 时不能伪造来源。
- 当前书已有旧 AI chunk 索引但缺全局层时，书籍级 Explorer 可在原地触发单本书全局层补建；没有可用 chunk 索引时再提示先完成 AI Index。
- 单本书补建只复用本地 chunk，不重新生成 embedding，不自动外发正文。
- 不写正式 ConceptGraphStore，不进入 Review，除非用户显式把局部证据转成候选。

## 3. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E04-C01-T01 | 定义 ConceptNode schema | E00 Ready, E02 Ready | node contract | 类型、source、draft 规则明确。 |
| E04-C02-T01 | 定义 ConceptEdge schema | E04-C01-T01 | edge contract | 每条边能说明为什么相关。 |
| E04-C02-T02 | 接入 ConceptGraph relation Review apply | E04-C02-T01, E05-C01-T02 In Review slice | `ConceptGraphReviewAdapter`, `ConceptGraphStore.applyReviewDecision` | approved 不进入正式图谱；applied 且有 evidence 的关系才升级 ownership。 |
| E04-C03-T01 | 设计 Concept Dossier | E04-C02-T01 | dossier spec | 概念页可显示证据、相关路径、回跳。 |
| E04-C04-T01 | 定义 exploration constraints | E04-C03-T01 | path policy | 限制深度、宽度、外部来源和返回路径。 |
| E04-C05-T01 | 接入 Settings 全书图谱书籍选择 | E02 global layer, E04-C03-T01 | `AiGlobalDerivedBookConceptGraphCatalog`, `conceptGraphDerivedBookCatalogProvider`, Explorer book picker | Settings `Concept graph` 可选择已有全局层的已索引书并显示只读全书图谱；不补建索引、不外发正文、不写正式图谱。 |
| E04-C05-T02 | 接入阅读页当前书全书图谱 | E04-C05-T01, E07 reader entry | `ConceptGraphExplorerPage.bookId`, reader graph action | 阅读页 `图谱` 入口显示当前书只读全书派生图谱，并保留局部探索入口。 |
| E04-C05-T03 | 接入当前书全局层原地补建 | E02 global layer, E04-C05-T02 | `AiGlobalIndexBuilder.getBookLayerStatus`, `conceptGraphGlobalLayerRebuilderProvider`, Explorer empty graph action | 当前书已有旧 chunk 索引但没有 RAPTOR/GraphRAG 全局层时，Explorer 显示 `立即生成全局层索引`；补建完成后刷新只读全书图谱；没有 chunk 索引时只提示先索引。 |
| E04-C05-T04 | 接入全书图谱节点证据详情 | E04-C05-T02, E07 SourceRef opener | `full-book-derived-graph-map` tap hit-test, derived node detail sheet/panel | 点击全书 derived-cache 节点后显示摘要、相邻关系、证据摘录和 `Open source`；只读取 SourceRef，不写正式图谱、不进入 Review、不外发正文；compact 宽屏不产生布局溢出。 |

## 4. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | RAG chunks, GraphRAG tables, KnowledgeCard SourceRef, notes/highlights, reader deep links。 |
| Allowed Modules | concept graph service/docs/tests, RAG graph adapters, concept explorer UI specs。 |
| Forbidden Changes | 不做 full Wikipedia client；不默认 web；不把模型推断写成书内事实；不先做无限画布。 |
| Verification Commands | Focused tests for node/edge evidence, orphan detection, path width/depth constraints; `git diff --check`。 |
| Reviewer Gate | Retrieval Quality Gate + Agent Safety And Privacy Gate + Review And Rescue Gate。 |
| Rollback / Degrade Path | Graph unavailable 时回退到 RAG evidence list 和 card links。 |

## 5. Gates

- Retrieval Quality Gate：无 evidence 的 node/edge 不进入正式图。
- Agent Safety And Privacy Gate：外部百科和 web 补充默认 opt-in。
- Review And Rescue Gate：broken link、orphan node、source 删除必须可检测。

## 6. Non-Goals

- 不做完整 Wikipedia 客户端。
- 不做大型无限画布作为第一交付。
- 不把模型推断当成书内事实。
