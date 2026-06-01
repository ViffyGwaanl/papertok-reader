# 用户决策摘要

> 状态：Ready  
> 用途：帮助产品决策。这里只按“用户能不能用、怎么用、继续做什么、做成后有什么效果”说明，不写人日、月份或排期。

## 1. 这份文档回答什么

`README_zh.md` 和 `04_user_facing_activation_plan_zh.md` 已经记录了完整入口和验收任务。本文件把它们压缩成决策视角：

- 当前分支已经能让用户走通的功能。
- 已经做了代码地基，但用户不会直接感知的功能。
- 还没有产品化的大块能力，每块要怎么做，做成后对用户有什么价值。

本文件描述的是 `codex/future-agentic-upgrade` 分支，不代表 `main`、TestFlight 或用户已安装版本已经包含这些能力。

## 2. 当前用户可以使用的功能

| 功能 | 用户从哪里用 | 做成后的体验 | 关键边界 |
| --- | --- | --- | --- |
| 选中文本生成知识卡 | 阅读页选中文本 -> `知识卡` -> `Settings -> AI -> Review inbox` | 读到重点时点一下，生成带原文证据和跳转来源的 KnowledgeCard，先进入 Review。 | 不自动写长期记忆、笔记或复习；重复点击不会制造重复卡。 |
| 图片解析生成知识卡 | 图片大图 -> `AI图片解析` -> `知识卡` | 对 EPUB 图片、图表、插图做 AI 解析后，把结果变成待审知识卡。 | 图片本体和 base64 不写进卡片；只保存解析结果、来源和证据摘录。 |
| AI Chat 回答生成知识卡 | 阅读页选中文本 -> `AI` -> 等回答完成 -> 回答旁 `知识卡` | 普通问答结束后，把有价值回答沉淀为待审知识卡，并保留能否跳回原文的来源状态。 | streaming 中按钮禁用；无 reader grounding 的旧聊天只保留 conversation provenance。 |
| 多角色 Seminar | 阅读页选中文本 -> `研讨`，或 `Settings -> AI -> Seminar Mode` | 围绕一段原文启动 critical、supportive、synthesizer 多角色讨论，展示 evidence、角色发言、共享白板和综合总结。 | 结果只进入 Review；默认 current book 优先；不自动写长期资产。 |
| Seminar 预算与恢复 | Seminar 页面本地 budget 区、Provider readiness 区、job 状态区 | 用户能看到 provider/model 能力、token 用量、本地估算成本、当前 job id/status；可取消、重试、排队下一场。 | 这是本机 job/cache，不是跨进程后台续跑；重启中的 running job 会恢复为 interrupted/retryable。 |
| Review Inbox | `Settings -> AI -> Review inbox` | 所有 AI 生成的卡片、记忆、图谱关系、flashcard、同步冲突都先进入审批入口。 | 空 inbox 只代表没有 producer 写入，不代表入口不存在。 |
| Memory 候选审核 | AI Chat 回答旁书签图标 -> `Add to Review inbox` | 有价值的聊天内容先进入 Review，再由用户决定写入 daily/long-term memory。 | Apply 才写 Markdown memory；Dismiss 不写 memory。 |
| Memory 来源审计 | 首页 `Memory / 记忆` tab -> 条目详情 | 已应用的 memory 能显示 evidence、来源状态和可跳回原文的链接。 | 不往 Markdown 写隐藏来源字段；只做只读投影。 |
| Concept Graph 局部探索 | `Settings -> AI -> Concept graph`，或阅读页选中文本 -> `图谱` | 像 WikiLinks 一样围绕局部概念看节点-连线图、关联、证据、草稿关系、孤立节点和断链。 | 图谱是派生层；用户确认过的关系才是资产；当前是轻量局部 canvas，不做无限画布。 |
| RAG 结果生成知识卡 | Concept Graph 空态 -> `知识卡` | 没有现成概念时，从本地 RAG 证据生成待审知识卡。 | 只接受带 traceable chunk SourceRef 的结果。 |
| Spaced Review | `Settings -> AI -> Spaced review` | 已应用知识卡或 Seminar flashcard 可以进入复习队列，按 Again/Hard/Good/Easy 更新间隔。 | 跨设备复习同步还没接。 |
| Knowledge Sync / Export | `Settings -> AI -> Knowledge sync/export` | 可导出 manifest、Markdown、HTML report、Anki TSV、sync bundle；可预览远端 bundle，安全冲突进 Review。 | 这是前台安全编排，不是完整后台云同步。 |
| Custom Skills | `Settings -> AI -> 自定义技能`，再到 `当前技能` 选择 | 用户可导入受治理的 JSON skill，让 AI 在指定 scene 中追加行为和只读工具。 | 写工具、递归 sub-agent、未知字段和禁用 skill 都不会注入运行时。 |
| OpenAI Responses 兼容诊断 | `Settings -> AI -> Provider Center` 配置 Responses provider | 官方支持 `previous_response_id` 的 provider 继续走 server-side continuation；拒绝该参数的兼容网关会自动降级重试，并在错误里给出 endpoint/model/参数诊断。 | 只对明确 `previous_response_id` unsupported 的 HTTP 400 重试；非该错误保留原始失败。 |
| 当前书语义检索保护 | 阅读页搜索、Seminar evidence、`semantic_search_current_book` 工具 | 当前书向量搜索改为分页、串行、可取消、带进度，并优先 bounded FTS/BM25 候选，降低 OOM、发热和掉帧风险。 | 这是保护层，不是真 ANN 向量索引；无候选时只做预算内 fallback 扫描。 |
| 旧索引全局层补建 | `Settings -> AI Index / Library Index` -> `全局层索引` -> `补建` | 用已有 chunk 给旧索引书籍补建 RAPTOR 全局摘要层和当前 GraphRAG 派生层，页面显示进度并可取消。 | 不重新生成 embedding；不是 sqlite-vec/ANN；当前纯中文 graph node 抽取仍需后续增强。 |

## 3. 已做但用户不直接感知的功能

| 内部能力 | 为什么重要 | 用户间接获得什么 |
| --- | --- | --- |
| `SourceRef` / provenance 统一 | 所有 AI 结论、知识卡、图谱关系、复习项需要知道来自哪本书、哪个 CFI、哪个 chunk、哪个模型。 | 用户点击卡片或复习题能解释“这条知识从哪里来”，也能跳回原文。 |
| Review source-specific adapters | KnowledgeCard、Memory、ConceptGraph、flashcard、sync conflict 的 Apply 逻辑不同，不能只改一个状态字段。 | 审批动作更可追踪，减少“点了 Apply 但资产没真正写入”的错位。 |
| Seminar runtime contract | 多角色讨论需要结构化保存 session、evidence、turn、whiteboard、synthesis、billing snapshot。 | 用户看到的是一个可取消、可重试、能送 Review 的讨论界面，而不是一次 prompt-only 输出。 |
| Provider capability / billing snapshot | provider 是否支持 tools、vision、thinking、streaming、pricing metadata，需要和运行记录分开。 | 页面能说清楚“provider 用量”和“本地估算”区别，不把估算当账单。 |
| Current-book semantic search paging | 旧实现一次拉全书 chunk 和 embedding，容易 OOM。 | 用户感知为搜索更不容易卡死，AI 提问时更少把阅读页拖慢。 |
| CustomSkill schema/parser/validator | 自定义 skill 不能只靠一段 YAML/JSON 文本直接注入。 | 用户能导入能力，但写操作、递归、未知字段被挡在运行时外面。 |
| Remote merge planner / writeback guard | 远端同步必须区分 incoming、outgoing、conflict、unsafe payload、ETag/CAS。 | 用户看到的是“预览、冲突进 Review、安全时再上传”，而不是覆盖式同步。 |
| 中文 l10n 补齐 | ARB 缺 key 或页面硬编码英文会让中文用户以为功能没接好。 | Settings、Seminar、自定义技能、Review/Graph/Export 相关入口更一致地显示中文。 |

## 4. 还没产品化的大块能力

### 4.1 完整后台跨设备云同步

当前已经有：

- 本地知识资产导出。
- 远端 bundle preview。
- 前台 `Check remote changes`。
- 前台 `Run safe remote sync`。
- incoming / conflict 进入 Review。
- WebDAV ETag / CAS 条件写保护。
- 写回失败 rollback snapshot。

还要做什么：

- 把前台按钮编排拆成可恢复的 sync job ledger。
- 设计后台触发条件：App 启动、App 回前台、用户手动同步、可选定时。
- 增加跨设备 baseline 版本、remotePath 绑定、schema migration gate。
- 增加冲突通知入口，把“有远端变更需要审核”放到用户能看见的位置。
- 增加 provider adapter 分层：WebDAV、iCloud/Files、对象存储或自建 API 不能混在一个实现里。
- 增加端到端恢复测试：断网、远端被改、CAS 失败、半写入、旧 schema、未知字段、删除书籍、恢复备份。

做成后的效果：

- 用户在一台设备批准知识卡或复习记录，另一台设备可以通过安全同步看到待导入内容。
- 冲突不会自动 last-write-wins，而是进入 Review，让用户决定。
- API key、派生索引、缓存 DB 不同步。

是否值得优先做：

- 如果目标是多设备真实学习闭环，优先级高。
- 如果当前主要是单设备阅读和 AI 辅助，现有前台安全 sync/export 已经够支撑试用。

### 4.2 Seminar 进程死亡后继续跑

当前已经有：

- 本机 runtime state cache。
- current job id/status。
- queued job 串行队列。
- running job 重启后，如果已经有连续、证据可追踪且 provider/model/pricing 仍匹配当前配置的 completed role turn，可以复用已保存 evidence，从下一个缺失角色继续。
- 没有 completed role、只有 active partial stream、checkpoint 无效、provider 已切换或 queued job 时，仍恢复为 interrupted/retryable。
- 页面不会假装旧 LLM stream 仍在继续，也不会把它说成 OS 后台执行。

还要做什么：

- 定义真正的 background execution contract：iOS/Android 对长时间网络流式任务的限制不同。
- 扩展 checkpoint 粒度：当前已支持 completed role prefix；后续还要覆盖 evidence-only、review handoff ready 和 provider idempotency。
- provider request 需要 idempotency key 或本地去重策略，避免重启后重复扣费、重复写 turn。
- 中断恢复时明确提示用户：从哪个角色继续、是否会再次调用 provider、预估成本如何计算。
- queued job 重启后由用户确认继续，避免 App 被系统杀掉后自动外发正文。

做成后的效果：

- Seminar 跑到一半 App 被系统杀掉，重新打开后可以从已完成角色继续，而不是只能整场重试。
- 多角色讨论可以承载更长任务，但仍保持用户确认和证据链。

是否值得优先做：

- 如果 Seminar 会成为核心卖点，值得做。
- 如果当前使用场景是短文本讨论，本机 interrupted/retryable 已足够，不必先做 OS background。

### 4.3 Provider 发票导入

当前已经有：

- provider usage metadata 展示。
- 本地 token estimate fallback。
- billing snapshot。
- invoice reconciliation 状态位。
- 页面明确 `Not connected`，不会把估算说成账单。

还要做什么：

- 每个 provider 单独建 invoice adapter：OpenAI、SiliconFlow、Anthropic、Gemini、OpenAI-compatible 网关都不同。
- 定义只读鉴权：账单 API key 和模型调用 API key 分开保存，默认不同步。
- 定义账单时间窗口、币种、价格单位、缓存策略和失败降级。
- 把 provider invoice line item 和本地 run id 做弱匹配：时间、model、token、request id。如果 provider 不给 request id，只能显示 low-confidence。
- UI 中区分三类：provider reported usage、local estimate、invoice imported cost。
- 增加隐私 gate：用户显式开启后才读取账单，不把账单明细写入 sync bundle。

做成后的效果：

- 用户可以看到某场 Seminar 或 AI 提问的估算成本和 provider 账单是否接近。
- 成本管理从“估算”升级为“可对账”。

是否值得优先做：

- 如果用户会频繁跑高成本模型或团队共享 provider，值得做。
- 如果主要是个人试用，先保留本地估算和 provider usage 已经够用。

### 4.4 sqlite-vec / ANN 真向量索引

当前已经有：

- 当前书搜索分页扫描。
- bounded FTS/BM25 候选预筛。
- 搜索取消、进度、串行、background isolate scoring。
- 老索引 JSON fallback 的分页回查。

还要做什么：

- 选型：sqlite-vec、sqlite-vss、FAISS wrapper、平台原生向量库，必须考虑 iOS 可打包性。
- 新增 schema migration，从当前 `kAiIndexDbVersion` 递增。
- 建立 ANN index build job：可取消、可恢复、可重建、删除书籍后清理。
- 定义向量维度兼容：不同 embedding model 切换时必须让旧索引失效。
- 增加召回质量 gate：ANN topK 与当前 exact scan 在固定 fixture 上的重合率。
- 增加移动端资源 gate：大书索引构建、查询延迟、内存峰值、发热和后台中断恢复。

做成后的效果：

- 大书和大书库的语义检索更快。
- 无 FTS 候选时不需要预算内线性扫描。
- Seminar evidence 和 agent tool 的检索延迟下降。

是否值得优先做：

- 如果目标用户会导入很多大书、论文集或长 PDF，值得做。
- 如果当前 OOM/发热已由分页和 FTS 候选压住，可以先用现有实现收集真实数据。

### 4.5 复杂无限画布图谱

当前已经有：

- Concept Graph 局部探索和轻量节点-连线 canvas。
- dossier。
- 局部路径。
- evidence badge。
- orphan/broken link 检测。
- draft/formal 状态。

还要做什么：

- 定义移动端图谱交互：缩放、拖拽、节点聚合、搜索定位、证据侧栏。
- 定义图谱资产边界：哪些 node/edge 是用户确认资产，哪些只是派生视图。
- 加入布局缓存和 incremental layout，避免每次打开都重算大图。
- 加入 evidence-first rendering：点任何节点/边都能看到证据，不让图谱变成无来源的漂亮图。
- 加入图谱规模 gate：节点数、边数、布局耗时、内存、手势帧率。
- 加入导出和恢复：用户确认关系可以同步，派生布局缓存可重建。

做成后的效果：

- 用户可以像在大脑图或知识地图中探索阅读过的概念关系。
- 复杂主题、跨书关联、课程式复习会更直观。

是否值得优先做：

- 如果 PaperTok Reader 要强调知识地图和长期知识库，这是高价值方向。
- 如果当前目标是“读不懂时点一下获得可信讨论”，局部图谱更贴近移动端使用，不必先做无限画布。

## 5. 推荐决策顺序

| 顺序 | 建议做什么 | 原因 |
| --- | --- | --- |
| 1 | 先验证当前已接入的用户路径 | 这些入口已经能形成“阅读 -> 生成 -> Review -> Apply -> 复习/图谱/导出”的闭环，最容易发现真实体验问题。 |
| 2 | 先收集 Seminar、AI Chat、语义检索的真实使用数据 | 这能判断发热、掉帧、成本、检索质量是不是已经被现有保护层压住。 |
| 3 | 如果多设备是刚需，推进完整后台云同步 | 它影响用户资产安全和跨设备学习连续性，工程风险也最高。 |
| 4 | 如果 Seminar 是主卖点，推进进程死亡续跑 | 它能把多角色讨论从短任务提升为可恢复长任务。 |
| 5 | 如果大书检索仍慢，再推进 sqlite-vec/ANN | 先用真实数据证明分页 + FTS 候选不够，再引入复杂索引后端。 |
| 6 | 如果知识地图成为核心差异化，再推进无限画布图谱 | 它很有吸引力，但移动端成本和证据可见性 gate 都重。 |

## 6. 当前优先体验闭环

最建议先试这条路径：

1. 阅读页选中一段难懂文本。
2. 点 `研讨`，看多角色讨论是否比普通 AI 解释更有帮助。
3. 点 `Send to Review`。
4. 到 `Review Inbox` 审核卡片和 flashcard。
5. Apply 后去 `Spaced Review` 复习，或去 `Concept graph` 看局部关系。
6. 用 `Knowledge sync/export` 导出当前确认过的资产。

这条链路最能代表 PaperTok Reader 融合 OpenMAIC、MarginNote、WikiLinks 和 Understand-Anything 思路后的目标体验：读到不懂处，点一下，有讨论、有证据、有分歧、有总结，最后能沉淀、复习、跳回原文。
