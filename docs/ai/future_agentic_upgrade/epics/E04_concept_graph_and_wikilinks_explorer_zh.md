# E04 ConceptGraph And WikiLinks Explorer

> 状态：Ready  
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

## 3. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E04-C01-T01 | 定义 ConceptNode schema | E00 Ready, E02 Ready | node contract | 类型、source、draft 规则明确。 |
| E04-C02-T01 | 定义 ConceptEdge schema | E04-C01-T01 | edge contract | 每条边能说明为什么相关。 |
| E04-C03-T01 | 设计 Concept Dossier | E04-C02-T01 | dossier spec | 概念页可显示证据、相关路径、回跳。 |
| E04-C04-T01 | 定义 exploration constraints | E04-C03-T01 | path policy | 限制深度、宽度、外部来源和返回路径。 |

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
