# 用户决策摘要

> 状态：Ready
> 用途：帮助产品决策。这里只按“用户能不能用、怎么用、继续做什么、做成后有什么效果”说明，不写人日、月份或排期。

## 1. 这份文档回答什么

`README_zh.md` 和 `04_user_facing_activation_plan_zh.md` 已经记录了完整入口和验收任务。本文件把它们压缩成决策视角：

- 当前分支已经能让用户走通的功能。
- 已经做了代码地基，但用户不会直接感知的功能。
- 还没有产品化的大块能力，每块要怎么做，做成后对用户有什么价值。

本文件描述的是 `codex/future-agentic-upgrade` 分支。`2026-06-08` 已把发布目标 commit `2e0ab4a5f408b7c01ad4fc45ee659736e8a54528` 发布为 TestFlight/GitHub 预发布 build `1.68.7+6513`，但这不代表 `main`、稳定版或所有用户已安装版本已经包含这些能力，也不代表 v7 全部完成。

最新 P1 决策：AI Chat 原生 Seminar 先不做旧 LLM/provider stream 的“原地续传”。可用版优先保证用户能在 AI Chat 内稳定开始、查看证据与角色输出、保存结论、异常送审，并在中断或失败后保留证据和已完成角色，从缺失或失败角色重新生成；旧 stream 原地续传后续只作为 provider 支持时的增强项。`Seminar Mode / 研讨会模式` 也不再作为普通 `Active Skill` 或一段 prompt style 使用；Settings 的 Active Skill 选择器、AI Chat `Choose style / 选择风格` 和普通 Chat runtime 都会忽略旧 `activeAiSkillId=seminar_mode`，真正研讨只能从 AI Chat 原生 `AI 研讨会` 任务卡进入；全局角色默认配置仍从 Settings -> AI -> `Seminar settings` 进入。

最新 P5 决策：build `1.68.7+6513` 只说明当前 commit 已有 TestFlight/GitHub 预发布入口。用户沟通时必须同时说明仍未完成的 v7 边界：P1 的完整 streaming tool-call / 自由工具调用 loop、P2 的 AI semantic graph builder、P3 的生产级移动端 ANN gate、P4 的完整 AI 审核/异常中心和 P5 的跨设备后台同步/迁移说明仍在继续。

## 2. 当前用户可以使用的功能

| 功能 | 用户从哪里用 | 做成后的体验 | 关键边界 |
| --- | --- | --- | --- |
| 选中文本生成知识卡 | 阅读页选中文本 -> `知识卡` | 读到重点时点一下，生成带原文证据和跳转来源的 draft KnowledgeCard，并在当前菜单提示 `已保存为草稿知识卡`，不再要求先去 Review Inbox。 | 不自动写长期记忆、笔记或复习；重复点击不会制造重复卡；旧 Review producer 路径仍保留给兼容和异常场景。 |
| 图片解析生成知识卡 | 图片大图 -> `AI图片解析` -> `知识卡` | 对 EPUB 图片、图表、插图做 AI 解析后，把结果保存为 draft KnowledgeCard，并在当前图片解析弹层提示 `已保存为草稿知识卡`。 | 图片本体和 base64 不写进卡片；只保存解析结果、来源和证据摘录；不自动写长期记忆、复习或正式图谱；旧 Review producer 路径只保留给兼容和异常场景。 |
| AI Chat 回答生成知识卡 | 阅读页选中文本 -> `AI` -> 等回答完成 -> 回答旁 `知识卡` | 普通问答结束后，把有价值回答保存为 draft KnowledgeCard，并在当前 AI Chat 提示 `已保存为草稿知识卡`；卡片保留能否跳回原文的来源状态。 | streaming 中按钮禁用；无 reader grounding 的旧聊天只保留 conversation provenance 和不可跳原因；不自动写长期记忆、复习或正式图谱；旧 Review producer 路径只保留给兼容和异常场景。 |
| 多角色 Seminar | 阅读页选中文本 -> `研讨`，AI Chat `+` -> `AI 研讨会` | 围绕一段原文或一个聊天问题启动 critical、supportive、synthesizer 多角色讨论，展示 evidence、角色发言、共享白板和综合总结；阅读页选中文本入口已改为打开 AI Chat 并写入原生 Seminar 任务卡，保留 SourceRef，不进入旧独立页面；AI Chat `+` 入口先写入原生 Seminar 任务卡，待开始卡会显示 `本次设置` 摘要，可在卡内编辑本次研讨问题、调整最多讨论轮次、启用或停用本次角色、编辑启用角色本次 prompt 并切换 current book/library/notes/memory/conceptGraph 证据范围，再在卡内启动；阅读页/外部入口也会用同一 `seminarSessionId` 在会话历史里留下可持久化 `AI 研讨会` 任务卡，进程被杀或重启后用户能从 AI Chat 历史重新找到这场讨论；AI Chat `+` 入口同样会写入任务卡，历史重载后待开始卡可点 `开始研讨`，本机 checkpoint 断点详情会在当前卡内展开；`AiChatStream` 组件内旧 inline panel 状态、渲染函数、全页跳转函数和同步 listener 分支也已移除；scoped runtime 运行、完成或刷新证据时，会把卡片状态、来源数量、证据调用（工具名、查询、结果数量、可见角色和返回证据）、证据快照、角色观点、研讨总结、分歧数、开放问题数和 `研讨白板` 正文回写到同一张卡；运行中如果 evidence bundle 已返回、角色输出还没完成，任务卡会先显示 `证据调用`，让用户看到这场研讨已经调用了书内语义检索、查了什么、返回了几条证据；如果当前角色 stream 已经开始，任务卡还会显示 `角色发言生成中`、角色身份和 partial 文本，并写入 `messageParts.role_partial`，让历史卡也能恢复生成中状态；running role partial 会写入 `messageParts.role_partial`，completed 证据调用会写入 `messageParts.tool_call`，completed 证据快照会写入 `messageParts.evidence`，completed 角色回合会写入 `messageParts.role_turn`，completed 总结会写入 `messageParts.synthesis`，completed 分歧详情会写入 `messageParts.disagreement`，completed 分歧扫描会写入 `messageParts.contradiction_scan`，分歧反驳回合会写入 `messageParts.disagreement_rebuttal`，completed 异常预览详情会写入 `messageParts.review_triage`，completed 读者回合会写入 `messageParts.reader_turn`，askUser cue 会写入 `messageParts.director_state`，askUser 可参与状态会写入 `messageParts.reader_composer`，历史卡可从这个结构恢复调用视图、角色时间线、本轮 evidence、读者参与、主持人下一步、可用动作、可回应角色、默认动作、默认角色、当前动作、当前角色、草稿回复、独立动作选择、分歧详情、分歧扫描、分歧反驳回合、异常原因、AI 预审建议和异常候选明细；历史卡已有 `全部 / 调用 / 证据 / 角色 / 分歧 / 白板 / 总结 / 异常` 子视图，`调用` 子视图会显示证据收集的工具名、查询、结果数量、可见角色和返回证据，`分歧` 子视图可显示分歧正文、分歧扫描、关联角色、关联 evidence 摘录和分歧反驳回合，`异常` 子视图可在没有 active runtime synthesis 时从 review-triage parts 恢复异常原因、AI 预审建议、候选明细和候选证据；AI Chat 原生任务卡 snapshot、卡内异常送审、completed 卡片内低负担保存动作和 `读者参与` composer 已按 `seminarSessionId` 使用 scoped runtime，多个 scoped runtime 的模型调用会本机串行化；当前活跃同 session 且需要异常处理的任务卡会显示 `异常送审`，把低置信、冲突或来源异常的可追踪 synthesis 和候选项送入 pending Review；`异常` 子视图会在送审前显示异常原因、AI 预审建议、待送审内容计数、候选明细和可追踪证据；completed 卡片可直接 `保存知识卡`、`编辑后保存`、`加入复习`、`加入我的图谱` 或 `忽略`，不写普通 ReviewItem；completed 历史卡如果已有分歧且仍匹配当前 scoped runtime，会按分歧逐条显示 `分歧继续讨论`，默认让 critical 围绕选中的分歧反驳；如果本场没有启用 critical，则退回到当前可用角色回应；也可围绕选中的分歧重找 evidence 并重跑讨论；Seminar settings 可编辑每个角色的显示名、custom prompt、启用状态、会话证据提示和允许的只读工具；关闭角色后新讨论会跳过该角色，全部关闭时保留 synthesizer 兜底；工具范围会过滤写工具、联网工具、unknown tool 和递归 `spawn_sub_agent`；当白板留下 open question 或 disagreement，状态区会显示主持人下一步是邀请读者参与还是重新检索证据；需要用户参与时，或 completed 历史卡显示 `读者参与` 时，用户可输入回复，用动作 chips 选择让某个角色回应、重新找证据或整理总结；选择让角色回应时，所选角色会生成 follow-up turn 并更新 synthesis；选择重新找证据时，会重新检索 evidence、重跑角色并更新 synthesis；选择整理总结时，会用现有 evidence 和 turns 执行本地 synthesis 并收束 Director；如果一轮讨论只留下 disagreement 且仍有轮次预算，runtime 会自动重新找证据并重跑角色，预算用完仍有分歧时再请用户介入。 | 任务卡已有运行中证据调用首片、运行中角色 partial 发言首片、completed tool-call message part 首片、completed evidence message part 首片、completed role-turn message part 首片、completed synthesis message part 首片、completed disagreement message part 首片、completed contradiction-scan message part 首片、completed disagreement-rebuttal message part 首片、completed review-triage message part 首片、completed reader-turn message part 首片、askUser director-state message part 首片、askUser reader-composer message part 首片和只读证据/角色/总结 snapshot、白板正文首片、分歧详情首片、分歧扫描首片、首片异常送审按钮、completed 卡片内读者参与 composer、分歧逐条追问/重找证据入口、分歧反驳回合恢复首片和 AI Chat scoped runtime，但还不是包含完整 message part schema migration、完整角色自由工具调用和完整 contradiction scanner 的完整结构化消息卡；旧独立详情页已删除，后续完整详情能力继续补到 AI Chat 卡内；旧 stream 原地续传已延期，不作为 P1 可用版 gate，恢复先采用保留 evidence/已完成角色并重新生成缺失或失败角色；角色工具范围目前是配置和 prompt 治理，不代表每个角色都能自由调用工具；用户回复不进入 formal evidence；还没有完整 contradiction scanner/tab 或多分歧自动反驳策略；普通沉淀不再只进入 Review，旧候选卡、候选 flashcard 和异常路径仍进 Review；默认 current book 优先；不自动写长期资产。 |
| Seminar 预算与恢复 | Seminar 页面本地 budget 区、Provider readiness 区、job 状态区 | 用户能看到 provider/model 能力、token 用量、本地估算成本、当前 job id/status；可取消、重试、排队下一场；从本地 checkpoint 恢复 running Seminar 时，状态区会说明从哪个角色继续、provider/model 会为缺失角色或读者点名角色回合再次调用、费用仍是估算而不是 provider 发票。 | 这是本机 job/cache，不是跨进程后台续跑；重启中的 running job 只有在证据可追踪且 provider/model/pricing 仍匹配时才会重新生成缺失角色，旧 LLM stream 不会原地续传。 |
| Review Inbox | `Settings -> AI -> Review inbox` | 处理异常、低置信、来源断裂、同步冲突、批量导入和旧兼容 producer 写入的待审项。 | 普通学习动作不应默认进入这里；空 inbox 只代表没有异常或兼容 producer 写入，不代表入口不存在。 |
| Memory 直接记住与异常审核 | AI Chat 回答旁书签图标 -> `Remember this / 记住这条`，或结束会话时的 `Smart save / 智能保存`；异常才用 `Add to Review inbox` | 普通显式保存可直接写入今日日记并在当前消息菜单撤销；会话摘要默认按本地置信度智能路由，高置信候选写入今日日记，低置信、敏感、冲突或想稍后处理时才加入 Review。 | 撤销只移除刚直接追加的文本；智能摘要是本地规则评分，不调用额外 LLM；Review apply 才写异常 memory；Dismiss 不写 memory。 |
| Memory 来源审计 | 首页 `Memory / 记忆` tab -> 条目详情 | 已应用的 memory 能显示 evidence、来源状态和可跳回原文的链接。 | 不往 Markdown 写隐藏来源字段；只做只读投影。 |
| Concept Graph 局部探索 | `Settings -> AI -> Concept graph`，或阅读页选中文本 -> `图谱` | 像 WikiLinks 一样围绕局部概念看节点-连线图、关联、证据、草稿关系、孤立节点和断链；全书图谱预览可显示核心节点、关系证据和原文跳转。 | 图谱是派生层；普通图谱草稿在当前页保存、编辑、合并或忽略，不默认进 Review；当前是轻量局部 canvas，不做无限画布。 |
| RAG 结果生成知识卡 | Concept Graph 空态 -> `知识卡` | 没有现成概念时，从本地 RAG 证据生成 draft KnowledgeCard，并在当前图谱页提示已保存。 | 只接受带 traceable chunk SourceRef 和可保存 chunk snippet 的结果；不写 ReviewItem。 |
| Spaced Review | `Settings -> AI -> Spaced review`；completed Seminar 卡片 -> `加入复习` | 已应用知识卡、Seminar flashcard 或 completed Seminar synthesis 可以进入复习队列，按 Again/Hard/Good/Easy 更新间隔。 | completed Seminar 内联复习项可在未复习前撤销；跨设备复习同步还没接。 |
| Knowledge Sync / Export | `Settings -> AI -> Knowledge sync/export` | 可导出 manifest、Markdown、HTML report、Anki TSV、sync bundle；可预览远端 bundle，安全冲突进 Review。 | 这是前台安全编排，不是完整后台云同步。 |
| Custom Skills | `Settings -> AI -> 自定义技能`，再到 `当前技能` 或 AI Chat `+ -> Choose style / 选择风格` 选择；也可从 AI Chat `Choose style` 的自定义 skill 行点 `Custom skills / 自定义技能` 回到配置页。 | 用户可导入受治理的 JSON skill，让 AI 在指定 scene 中追加行为和只读工具；在 AI Chat 里选择风格时也能回到配置页，不必退出当前对话去找 Settings；普通内置 skill 行也可点 `Skill settings / 技能设置` 保存个人提示词补充。 | 写工具、递归 sub-agent、未知字段和禁用 skill 都不会注入运行时；点击配置入口不改变当前 active skill；普通内置 skill 的提示词补充不能覆盖隐私、证据、工具权限和写入确认规则。 |
| OpenAI Responses 兼容诊断 | `Settings -> AI -> Provider Center` 配置 Responses provider | 官方支持 `previous_response_id` 的 provider 继续走 server-side continuation；拒绝该参数的兼容网关会自动降级重试，并在错误里给出 endpoint/model/参数诊断。 | 只对明确 `previous_response_id` unsupported 的 HTTP 400 重试；非该错误保留原始失败。 |
| 当前书 Hybrid 召回 | 阅读页搜索、Seminar evidence、`semantic_search_current_book` 工具 | 当前书检索已接入 book-scoped `AiVectorSearchBackend`：先按 `bookId` 调用向量后端；如果 per-book Vec1 sidecar 完整，会先用 book-scoped ANN 召回；全局 Vec1 ANN 和无预算 `vector_full_scan` native path 在当前书场景会跳过，避免全局 topK 后过滤漏召回或绕过扫描预算；ANN winner 与 FTS/BM25 候选按 chunk id 去重。 | 这能降低大书 current-book 搜索的内存和发热风险，但不是移动端 sqlite-vec/Vec1 发布闭环；当前书的 ANN 路径只在 per-book sidecar 完整时启用，不用全局 ANN 假装 book-scoped recall。 |
| 书库 Hybrid RAG 召回 | AI Chat、Seminar library fallback、agent tool、ConceptGraph 空态等调用 `semantic_search_library` 的入口 | 书库检索已从“文本 miss 后才走 vector fallback”改成“FTS/BM25 精确召回 + 向量后端语义召回共同进入候选池”，结果可用 `usedVectorRecall` 判断向量是否参与；默认 backend 是 ANN -> native -> exact，Vec1/sqlite-vec function 和对应 ANN 表存在且完整时先用 ANN，只 hydrate winner 正文；不可用或不完整时合并/降级 native/exact，避免漏掉未升级书籍；删除书籍时会清理该书的派生图谱、native shadow vector 和 ANN 行。 | 已有 extension-ready Vec1 路径，但还不是真正发布级 sqlite-vec/ANN：移动端 extension 打包、UI build job 和 provider/model 失效没闭环；ConceptGraph 本地文本入口仍关闭 embedding/vector/rerank，避免外发正文；旧索引缺 blob 时仍保留 JSON fallback。 |
| 旧索引全局层补建 | `Settings -> AI Index / Library Index` -> `全局层索引` -> `补建` | 用已有 chunk 给旧索引书籍补建 RAPTOR 全局摘要层和当前 GraphRAG 派生层，页面显示进度并可取消；纯中文 chunk 已能本地抽取常见概念节点，关系来自同 chunk 共现计数。 | 不重新生成 embedding；不是 sqlite-vec/ANN；中文抽取是 deterministic 第一片，不等于完整实体消歧、跨章节主题聚类、独立 edge evidence 表或 LLM-backed concept extraction。 |
| 旧索引向量层升级 | `Settings -> AI Index / Library Index` -> `向量索引升级` -> `升级`，再点 `ANN 向量索引` -> `构建` | 用已有 embedding 给旧索引书籍补建紧凑 native vector shadow layer，为 sqlite-vec/ANN 后端做迁移准备；页面显示缺失数量、进度和取消；`ANN 向量索引` 会检查 Vec1/sqlite-vec 扩展、ANN group/global row 缺口和 per-book sidecar 缺口，可用时从 shadow rows 重建 provider/model/dim 隔离的全书库 Vec1 ANN 表，并同步生成 per-book Vec1 sidecar。 | 不重嵌入；未加载 Vec1/sqlite-vec 扩展时只显示 ANN 暂不可用并继续 fallback；当前是 extension-ready schema/backend seam，不是已打包的 sqlite-vec/ANN 发布能力。 |
| 全书自动图谱预览 | `Settings -> AI -> Concept graph`，或阅读页选中文本 -> `图谱` | Settings 入口会列出已有全局层的已索引书，用户可直接选择一本书查看只读全书关系图；阅读页入口会直接显示当前书的全书派生图谱；点图谱节点可查看摘要、相邻关系、证据摘录，并可 `Open source / 打开来源` 回到原文。 | 只读派生缓存，不写正式知识资产；没有全局层时先去 AI Index 补建；不是无限画布。 |

## 3. 已做但用户不直接感知的功能

| 内部能力 | 为什么重要 | 用户间接获得什么 |
| --- | --- | --- |
| `SourceRef` / provenance 统一 | 所有 AI 结论、知识卡、图谱关系、复习项需要知道来自哪本书、哪个 CFI、哪个 chunk、哪个模型。 | 用户点击卡片或复习题能解释“这条知识从哪里来”，也能跳回原文。 |
| Review source-specific adapters | KnowledgeCard、Memory、ConceptGraph、flashcard、sync conflict 的 Apply 逻辑不同，不能只改一个状态字段。 | 审批动作更可追踪，减少“点了 Apply 但资产没真正写入”的错位。 |
| Seminar runtime contract | 多角色讨论需要结构化保存 session、evidence、turn、whiteboard、synthesis、billing snapshot。 | 用户看到的是一个可取消、可重试、可异常送审、也能在卡片内直接保存知识成果的讨论界面，而不是一次 prompt-only 输出。 |
| OpenMAIC-style Director 思路 | OpenMAIC 把多 agent 讨论拆成 DirectorState、agent turn summary、whiteboard ledger 和 USER cue；这个结构适合 PaperTok 的长讨论。 | 角色显示名、custom prompt、启用状态、会话证据提示和只读工具范围已先接到 Seminar settings；`AiSeminarDirectorState` 已能在 runtime state 里记录轮次、已完成角色、证据账本、白板账本、分歧和用户插话，并把 open question / disagreement 转成 `askUser` 或 `refreshEvidence` 的下一步提示；用户回复可保存为 human intervention 并路由成 `runRole / refreshEvidence / synthesize` intent，其中 `runRole` 已能调用所选角色生成 follow-up turn，`refreshEvidence` 已能重新检索 evidence 并重跑角色，`synthesize` 已能用现有 evidence/turns 执行本地 synthesis；completed run 只留下 disagreement 且仍有轮次预算时，runtime 会自动刷新 evidence 并重跑角色；AI Chat 历史任务卡已能持久化 evidence/role/synthesis snapshot，显示 `研讨白板` 中的分歧和开放问题正文，`分歧` 子视图可展示关联角色和关联 evidence 摘录，并在同 session active runtime 需要异常处理时显示 `异常送审`、待送审内容计数、候选明细、知识卡候选证据摘录、复习候选综合证据和 AI 预审建议；AI Chat 原生任务卡、completed 卡内低负担保存动作和读者参与 composer 已接入 scoped runtime，阅读页/外部入口也会写入同 session 任务卡作为恢复锚点。下一步是让 AI Chat 原生 Seminar 继续做完整 Chat run 子视图、完整 contradiction scanner/tab、异常送审详情和 AI Chat 卡内详情，而不是固定一轮就总结。 |
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

### 4.2 AI Chat 原生多轮 Seminar

当前已经有：

- AI Chat `+` 中有独立 `AI 研讨会` 功能卡，点击后会在当前会话写入原生任务卡；待开始卡点 `开始研讨` 即可在卡内启动 scoped runtime。
- 阅读页选中文本 `研讨` 已迁到阅读页 AI Chat 原生 Seminar 任务卡：携带 reader SourceRef，不再把当前 active skill 改成 `seminar_mode`，不进入旧独立页面，并会写入同 `seminarSessionId` 的 AI Chat 任务卡作为恢复锚点。
- 旧 `openInlineSeminar(...)` 桥接 API 已从 `AiChatStream` 删除；外部入口只通过原生 `openNativeSeminarCard(...)` 写入任务卡；`AiChatStream` 组件内的旧 inline panel 状态、渲染函数、全页跳转函数和同步 listener 分支也已移除。
- 历史里 `待开始` 的 AI Chat Seminar 任务卡现在会显示 `本次设置` 摘要，可展开 `调整设置` 在卡内编辑本次研讨问题、修改最多讨论轮次、启用或停用本次角色、编辑启用角色本次 prompt、切换启用角色本次只读工具范围，并为启用角色切换 current book/library/notes/memory/conceptGraph 证据范围；然后直接点 `开始研讨`，用同一张卡的 session、问题、SourceRef、角色、轮次和本次角色配置启动 scoped runtime；设置调整、启动和完成都不需要打开内嵌面板，完成后 snapshot 回写到同一张聊天卡。
- 旧 Seminar runtime page 和 runtime panel 已删除；Settings 只保留 Seminar settings 配置入口，不再提供旧历史兼容或调试运行入口。
- `Choose style / 选择风格` 不再显示 Seminar 行；它只负责普通可激活 skill。全局 Seminar 默认配置从 Settings -> AI -> `Seminar settings` 进入，单次研讨设置从 AI Chat `+ -> AI 研讨会` 的任务卡进入。
- 独立 Seminar runtime 已支持 evidence、角色输出、共享白板、synthesis、Review handoff、budget、job 状态和本机恢复。
- Seminar settings 已支持每个默认角色的显示名、custom prompt、启用状态、会话证据提示和允许的只读工具；新 session 会把这些设置注入角色 prompt，session JSON 和恢复缓存会保留 profile；当前可见证据提示只开放 current book/library，并合并到整场 evidence bundle；关闭角色后新 run 会跳过该角色，全部关闭时降级为 synthesizer；写工具、联网工具、unknown tool 和递归 `spawn_sub_agent` 会被过滤。
- 阅读页选中文本入口能带入真实 SourceRef。
- completed 或 Director `askUser` 的 AI Chat Seminar 历史卡已显示 `读者参与`；`askUser` 时卡内会提示 `主持人正在等待你的回应` 并贴近显示第一条开放问题；这条 cue 已写入 `messageParts.type=director_state`，历史卡没有 active scoped runtime 时也能恢复 `主持人下一步`。`askUser` 的可参与状态也已写入 `messageParts.type=reader_composer`，历史卡没有 active scoped runtime 时能只读显示可用动作、可回应角色、默认动作、默认角色、当前动作、当前角色、草稿回复、独立动作选择和 Director 提问；同 session active runtime 仍显示真实输入框和提交按钮。用户可在同一张卡里输入回复，点名某个角色回应、重新找证据或整理总结；输入只写 user-turn ledger，不进入 formal evidence。
- Director `refreshEvidence` cue 也已写入 `messageParts.type=director_state` 第一片：当证据为空或不可追踪导致 runtime 进入 `needsEvidence` 时，历史卡没有 active scoped runtime 也能显示 `主持人下一步`、`主持人准备重新找证据` 和证据刷新原因。它只是主持人状态恢复首片，不代表完整 contradiction gap scanner 或 `synthesize/end` 操作卡已经完成。
- 用户在 askUser composer 里选择 `整理总结` 并提交后的收束状态已补测试证据：任务卡会写入 `messageParts.type=director_state`、`label=end` 和 synthesis 文本，历史卡能显示 `主持人已完成本轮研讨`。这只是用户触发整理总结后的 end cue，不代表独立 `synthesize` pre-execute cue、完整 Director 调度或旧 stream 原地续传已经完成。
- completed AI Chat Seminar 历史卡如果已有分歧，会逐条显示 `分歧继续讨论`，用户可以不用复制分歧文本，默认让 critical 反驳选中的分歧；如果本场没有启用 critical，则退回到当前可用角色回应；也可围绕选中的分歧重新找 evidence。围绕分歧生成的角色反驳已写入 `messageParts.type=disagreement_rebuttal`，历史卡没有 active scoped runtime 时也能恢复目标分歧、回应角色、回应正文和证据引用；同一场连续围绕多个分歧反驳时，历史卡会保留多条 `disagreement_rebuttal` parts，不再被最后一次用户插话覆盖。
- completed AI Chat Seminar 历史卡现在还会从结构化分歧派生 `messageParts.type=contradiction_scan`。历史卡即使只有 contradiction-scan parts、没有 legacy `disagreementDetails`，也能在 `分歧` 子视图恢复 `分歧扫描`、关联角色和关联 evidence；这仍不是完整 contradiction gap scanner，也不自动做多角色自动反驳。
- contradiction scan 的概览、下一步建议、优先处理队列、证据缺口提示、gap-first 展示和多缺口汇总已有第一片：`label=evidence-gap` 或无可追踪 evidence refs 的 scan 会在 `分歧扫描` tile 显示 `证据缺口` 和 `缺少可追踪证据`；多条 scan 混排时会先显示证据缺口；同一张卡有两条以上 evidence-gap scan 时，会显示 `证据缺口汇总` 和缺口数量；逐条 scan 前会显示 `分歧扫描概览`，统计总扫描数、证据缺口数和已有证据分歧数，并提示先补证据、再让角色反驳已有证据分歧；`优先处理` 队列会按 `补证据` 分歧优先、已有证据 `反驳` 分歧随后列出具体 scan 文本；同 session active runtime 进入 `refreshEvidence` 时会保留旧 scan 队列，evidence-gap 优先项可在卡内直接触发补证据；同 session active runtime 下，已有证据 `反驳` 优先项也可在卡内直接触发 `askRole`，默认让 critical 追加反驳，并把回应写回 `messageParts.disagreement_rebuttal`。这里只是 scanner overview、处理建议、手动优先处理队列、单条 scan 缺口提示、gap-first 排序、多缺口汇总、手动补证据入口和手动反驳入口，不代表完整多因素优先级排序或自动反驳策略完成。
- AI Chat Seminar 历史卡的 snapshot 已有第一片子视图：用户可在 `全部 / 调用 / 证据 / 角色 / 分歧 / 白板 / 总结 / 异常` 之间切换；切到 `分歧` 时聚焦分歧正文和分歧反驳回合，切到 `证据` 时只看证据快照；切到 `异常` 时可看到异常原因、AI 预审建议、AI 风险等级、建议动作、待送审内容计数、候选明细和可追踪证据。

还要做什么：

- 把当前带 snapshot、白板正文首片、首片异常送审按钮、异常送审内容计数、候选明细、知识卡候选证据摘录、复习候选综合证据和 AI 预审建议、completed 卡内低负担保存动作、completed / askUser 卡内读者参与 composer、askUser cue message part、refreshEvidence director_state 首片、synthesize 后 end director_state 验收、reader_composer 可用动作/默认动作只读恢复、分歧逐条继续讨论入口、contradiction_scan 恢复首片、contradiction evidence-gap 首片、evidence-gap 优先显示首片、多 evidence-gap 汇总首片、分歧扫描概览/下一步建议/优先处理队列首片、active refreshEvidence 保留旧 scan 队列并从 evidence-gap 优先项手动补证据首片、已有证据优先项手动触发 askRole 反驳首片、disagreement_rebuttal 恢复首片、snapshot 子视图首片和 AI Chat scoped runtime 的历史任务卡继续升级为完整 AI Chat message part / run 卡片，补齐完整异常送审详情表和完整 AI reviewer service、完整 contradiction scanner/tab、message part schema migration 和 AI Chat 卡内详情。
- 让 `DirectorState` 从已接入的可恢复账本和 next-intent policy 升级为真实调度器输入：根据已发言角色、分歧、证据刷新次数、用户插话和下一步 intent 决定继续找证据、让某个角色反驳、向用户提问或总结。
- 补齐聊天内设置和角色 profile 治理的剩余部分：ready 卡已能显示设置摘要、卡内编辑本次研讨问题、调整最大轮次、启用/停用角色、编辑启用角色本次 prompt、切换启用角色本次只读工具范围并为启用角色切换 current book/library/notes/memory/conceptGraph 证据范围；默认角色仍是 `critical/supportive/synthesizer/verifier`；显示名、custom prompt、启用状态、会话证据提示和只读工具范围已有 Settings 全局默认；AI Chat 单次 run 已能临时覆盖 prompt、启用状态、current book/library/notes/memory/conceptGraph 证据范围和只读工具范围，ready 任务卡也可直接编辑本次研讨问题、启用角色本次 prompt 和启用角色本次只读工具范围；运行时已开始把已收集 evidence 按角色 `roleProfiles.evidenceScopes` 过滤后传给对应角色，并按角色 scope 校验引用和 checkpoint；notes/memory/conceptGraph 独立 evidence broker 已有首片，`concept_graph_search` 也已补成真实受控只读工具；后续还要增加空 prompt 显式提示、角色级预算、notes/memory/conceptGraph streaming/tool-call 细化和完整真实角色工具调用闭环。
- 增加多轮机制：第一轮观点后做 contradiction scan；证据不足或角色冲突时重新检索，再进入反驳轮，最后 synthesis。
- 继续完善用户讨论环节：用户输入框、动作选择、“某角色回应”、“重新找证据”、“直接总结”和 disagreement 预算内自动刷新执行路径已接入；后续要把运行结果落到完整结构化 Chat run card 子视图，并接入完整 contradiction scanner/tab 和多分歧自动反驳策略。
- 删除旧独立 Seminar 页面；断点详情和后续完整详情能力都在 Chat run card 内完成。

做成后的效果：

- 用户不需要离开 AI Chat，就能看到多个角色围绕同一个问题交锋、补证据、反驳和总结。
- 角色不再只是固定 prompt；用户已能改名称、风格、是否启用、为整场研讨补充 current book/library 证据提示，以及限制哪些安全只读工具会写入 role prompt；AI Chat 单次 run 已能通过 ready 任务卡临时覆盖 prompt、启用状态、current book/library/notes/memory/conceptGraph 证据范围和只读工具范围，ready 任务卡也已能在卡内修改本次研讨问题、启用角色的本次 prompt、本次只读工具范围与 current book/library/notes/memory/conceptGraph 证据范围；运行时已开始把已收集 evidence 按角色 `roleProfiles.evidenceScopes` 过滤后传给对应角色，并按角色 scope 校验引用和 checkpoint；notes/memory/conceptGraph 独立 evidence broker 已有首片，`concept_graph_search` 也已补成真实受控只读工具；后续还要补角色级预算、notes/memory/conceptGraph streaming/tool-call 细化和完整真实角色工具调用闭环。
- 讨论遇到矛盾不会一轮结束，而是会把争议点列出来，再按证据缺口重新查书内或书库 evidence。
- AI Chat 的 thinking、tool call、skill/plugin 面板和 Seminar 会变成同一个工作台：用户在同一个输入框里提问、插话、点名某个角色、要求重查证据或收束送审。
- 旧独立 Seminar 页面已删除；日常入口和断点详情都落在 AI Chat 的结构化 Seminar run card 内。

是否值得优先做：

- 如果你喜欢 OpenMAIC 那种多人讨论感，这是 Seminar 方向最值得优先做的一块。
- 它比 OS 后台续跑更直接影响日常体验，也比无限画布更贴近“读不懂时点一下”的主线。

### 4.3 Seminar 进程死亡后继续跑

当前已经有：

- 本机 runtime state cache。
- current job id/status。
- queued job 串行队列。
- running job 重启后，如果已经有证据可追踪且 provider/model/pricing 仍匹配当前配置的 checkpoint，可以复用已保存 evidence，从第一个缺失角色继续；已有 completed role 会跳过不重跑。
- 如果只有 active partial stream 但 evidence 已保存，partial 会被丢弃并重新生成当前缺失角色；checkpoint 无效、evidence 不可追踪、provider 已切换或 queued job 时，仍恢复为 interrupted/retryable。
- restored running 状态会在页面提示从哪个角色继续、是否会再次调用当前 provider/model、费用仍按估算显示且不是 provider 发票；读者点名 follow-up 会显示为点名角色回合，不会误写成缺失角色。
- 页面不会假装旧 LLM stream 仍在继续，也不会把它说成 OS 后台执行。

还要做什么：

- 定义真正的 background execution contract：iOS/Android 对长时间网络流式任务的限制不同。
- 扩展 checkpoint 粒度：当前已支持 traceable evidence checkpoint 和 completed role prefix；后续还要覆盖 review handoff ready 和 provider idempotency。
- provider request 需要 idempotency key 或本地去重策略，避免重启后重复扣费、重复写 turn。
- 增加恢复前的用户确认 gate：当前已提示续跑角色、provider 再调用和估算成本边界，但可恢复 running checkpoint 仍会自动续跑。
- queued job 重启后由用户确认继续，避免 App 被系统杀掉后自动外发正文。

做成后的效果：

- Seminar 跑到一半 App 被系统杀掉，重新打开后可以复用已保存证据，从当前缺失角色继续；如果已有完成角色则跳过这些角色，而不是只能整场重试。
- 多角色讨论可以承载更长任务，但仍保持用户确认和证据链。

是否值得优先做：

- 如果 Seminar 会成为核心卖点，值得做。
- 如果当前使用场景是短文本讨论，本机 interrupted/retryable 已足够，不必先做 OS background。

### 4.4 Provider 发票导入

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

### 4.5 sqlite-vec / ANN 真向量索引

当前已经有：

- 当前书搜索分页扫描。
- bounded FTS/BM25 候选预筛。
- 书库 RAG 的 hybrid recall 管线：向量后端和 FTS/BM25 一起召回，不再只是文本 miss 后兜底。
- exact 向量后端主扫描只取 compact vector/provenance row，再 hydrate winner 正文。
- `kAiIndexDbVersion = 12` 的 native vector shadow schema：`ai_vector_index_rows` 和 `ai_vector_index_meta`。
- 旧索引向量层升级入口：用已有 blob/JSON embedding 补建 compact float32 rows，不重嵌入。
- ANN -> native -> exact backend seam：能检测 Vec1/sqlite-vec capability 和 per-model ANN table，不可用或不完整时自动降级 native/exact。
- Vec1 table builder：能按 provider/model/dim 从 `ai_vector_index_rows` 重建独立 Vec1 virtual table，并写 `vec1-ann` meta。
- per-book Vec1 sidecar：builder 会为每本书额外生成 book-scoped ANN table，状态 API 会单独报告 sidecar ready/missing，当前书检索只在 sidecar 完整时使用它，避免全局 ANN 后过滤。
- ANN/exact recall overlap gate：能用固定 fixture 比对候选 ANN/native backend 与 exact backend 的 topK chunk id 重合率。
- overlap gate 可传入 `bookId`，候选 backend 和 exact backend 使用同一个 book scope 验证。
- 搜索取消、进度、串行、background isolate scoring。
- 老索引 JSON fallback 的分页回查。

还要做什么：

- 最终选型：当前优先预留 sqlite-vec/Vec1 路径；若换 sqlite-vss、FAISS wrapper 或平台原生向量库，必须证明 iOS 可打包性和 fallback contract 不变。
- 接入真实 sqlite-vec/Vec1 package 或平台向量扩展，并验证 iOS/Android 打包。
- 把当前前台 ANN build action 扩展成可恢复 job，并补 provider/model 失效重建策略。
- 定义向量维度兼容：不同 embedding model 切换时必须让旧索引失效。
- 把真实 ANN backend 接入召回质量 gate：ANN topK 与当前 exact scan 在固定 fixture 上必须达到阈值；当前 extension-ready seam 已有测试，真机 extension 仍需验收。
- 增加移动端资源 gate：大书索引构建、查询延迟、内存峰值、发热和后台中断恢复。

做成后的效果：

- 大书和大书库的语义检索更快。
- 书库搜索由 ANN 做主语义召回、FTS 做精确文本召回；当前书在 per-book Vec1 sidecar 完整时，无 FTS 候选也能先走 book-scoped ANN，不依赖全局 ANN 后过滤。
- Seminar evidence 和 agent tool 的检索延迟下降。

是否值得优先做：

- 如果目标用户会导入很多大书、论文集或长 PDF，值得做。
- 如果当前 OOM/发热已由分页和 FTS 候选压住，可以先用现有实现收集真实数据。

### 4.6 复杂无限画布图谱

当前已经有：

- Concept Graph 局部探索和轻量节点-连线 canvas。
- 全书派生图谱节点点击详情、证据摘录和来源跳转。
- dossier。
- 局部路径。
- evidence badge。
- orphan/broken link 检测。
- draft/formal 状态。

还要做什么：

- 定义移动端图谱交互：缩放、拖拽、节点聚合、搜索定位、证据侧栏。
- 定义图谱资产边界：哪些 node/edge 是用户确认资产，哪些只是派生视图。
- 加入布局缓存和 incremental layout，避免每次打开都重算大图。
- 加入更完整的 evidence-first rendering：当前已支持全书节点点开证据；复杂画布还需要边详情、聚合节点和证据侧栏。
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
| 1 | 先验证当前已接入的用户路径 | 这些入口已经能形成“阅读 -> 生成 -> 当前页内联保存/撤销 -> 复习/图谱/导出，异常才进 Review”的闭环，最容易发现真实体验问题。 |
| 2 | 先收集 Seminar、AI Chat、语义检索的真实使用数据 | 这能判断发热、掉帧、成本、检索质量是不是已经被现有保护层压住。 |
| 3 | 如果多设备是刚需，推进完整后台云同步 | 它影响用户资产安全和跨设备学习连续性，工程风险也最高。 |
| 4 | 如果 Seminar 是主卖点，先推进 AI Chat 内嵌多轮 Seminar | 它直接解决“不要单独页面、角色可设置、多轮争论、用户能插话”的体验问题。 |
| 5 | 如果长讨论会被频繁打断，再推进进程死亡续跑 | 它能把多角色讨论从短任务提升为可恢复长任务。 |
| 6 | 如果大书检索仍慢，再推进 sqlite-vec/ANN | 先用真实数据证明分页 + FTS 候选不够，再引入复杂索引后端。 |
| 7 | 如果知识地图成为核心差异化，再推进无限画布图谱 | 它很有吸引力，但移动端成本和证据可见性 gate 都重。 |

## 6. 当前优先体验闭环

最建议先试这条路径：

1. 阅读页选中一段难懂文本。
2. 点 `研讨`，看多角色讨论是否比普通 AI 解释更有帮助。
3. 在 completed Seminar 卡片里点 `保存知识卡`、`加入复习` 或 `加入我的图谱`。
4. 如果来源异常、低置信或冲突，再点 `异常送审` 到 `Review Inbox` 处理。
5. 去 `Spaced Review` 复习，或去 `Concept graph` 看局部关系。
6. 用 `Knowledge sync/export` 导出已确认资产；草稿和派生缓存仍不默认同步。

这条链路最能代表 PaperTok Reader 融合 OpenMAIC、MarginNote、WikiLinks 和 Understand-Anything 思路后的目标体验：读到不懂处，点一下，有讨论、有证据、有分歧、有总结，最后能沉淀、复习、跳回原文。
