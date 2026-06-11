# User-Facing Activation Plan

> 状态：In Review
> 用途：把 agentic upgrade 的底层能力转成用户能找到、能触发、能验证的产品入口。

本文件只回答三个问题：

- 用户现在从哪里用。
- 哪些能力已有底层 artifact，但还没有产品入口。
- 剩余 Agent Task 怎样把能力接成可用闭环。

v4 方向重置：

- 普通学习动作不再默认送到 `Review Inbox`。默认路径改为：AI 生成 -> 当前阅读页或 AI Chat 卡片内预览 -> 用户一键添加、编辑、合并、忽略或撤销。
- `Review Inbox` 保留为异常处理中心，只处理同步冲突、批量导入、低置信候选、敏感记忆、来源断裂、重复关系无法判断、跨设备恢复异常。
- 表格中仍写 `进入 Review Inbox` 的路径，表示当前分支已有可测试旧闭环；后续 agent task 必须把这些普通路径逐步改成内联确认，不应继续扩大默认送审范围。
- AI Chat Seminar 的长期主入口必须是 AI Chat 消息流和结构化任务卡；旧独立 runtime page/panel 不再作为详情、调试、恢复或兼容入口保留，剩余详情能力必须继续补进 AI Chat 原生卡片。
- ConceptGraph 的默认用户价值是全书主干图和导读地图；选中文本只负责聚焦局部相关图，不应把图谱体验退化成相似关键词搜索结果。
- 阅读页选中文本进入 ConceptGraph 时，全书派生图谱会按节点、关系和 evidence 命中收窄为局部子图，并显示 `Focused by selection / 按选中文本聚焦`；这个聚焦只读 derived-cache，不写用户图谱、不进入 Review Inbox、不外发正文。
- ConceptGraph 的全书 `Book map / 本书地图` 会从核心节点和主干关键节点的 `SourceRef.sourceTitle`、`SourceRef.locationLabel` 聚合 `Evidence sections / 证据章节`。点击证据章节会打开对应全书节点详情；该信息只来自已索引 chunk evidence，不调用 LLM、不外发正文、不写用户图谱、不进入 Review Inbox。
- AI Chat Seminar 的 P1 可用版不再等待旧 LLM/provider stream 原地续传。恢复体验先做成：保留已收集 evidence、保留已完成角色，断点或失败后从缺失/失败角色重新生成；旧 stream 原地续传后续只作为 provider 支持时的增强项。

入口前置条件和命名：

- 补充：AI Chat Seminar 的角色 agent stream 现在会在系统提示里明确列出本角色允许使用的只读工具，例如 `semantic_search_current_book`、`notes_search`，并明确不能调用列表外工具，工具只能用于证据收集或核验，最终仍必须返回 Seminar role JSON。这样用户在本次研讨设置里选择的只读工具不会只停留在权限过滤或 UI 状态块里，也会进入角色 agent 的实际执行提示。当前只是受控工具边界提示和 executor 稳定性补强，不代表完整自由多轮工具 loop、完整 tool wait/cancel 执行器、完整 streaming tool-call 统一组件或旧 provider stream 原地续传。
- 补充：AI Chat Seminar 的历史/混合卡如果只有旧 `openQuestions` 自动恢复出的 `ask-user` 提示，不再因此回退到旧 `研讨时间线` 概览。用户会继续在默认 `全部` 视图看到原生 `研讨流`，其中包含证据、角色观点、主持人提问和研讨总结；真正带多条 reader/agent 控制历史的旧卡仍保留旧概览以保证控制记录不丢。当前只是 legacy openQuestions 迁移到原生研讨流的 gate 修复，不代表完整 streaming tool-call 统一组件、完整角色自由工具调用 loop 或完整 `sendInput/resumeAgent/retry` 协作协议已经完成。
- 补充：AI Chat Seminar 的历史/当前研讨消息卡头不再显示 `研讨会设置` 调参按钮，也不会从当前 AI Chat 卡片直接跳到 Settings 的 `Seminar settings` 页面。全局默认角色、核验者和预算保护仍在 Settings -> AI -> `Seminar settings` 管理；本次研讨的问题、轮次、角色、证据范围和只读工具仍在 AI Chat `+ -> AI 研讨会` 入口或 ready 状态卡内调整。当前只是消息卡头全局设置跳转收口，不代表完整 streaming tool-call 统一组件、完整角色自由工具调用 loop 或完整 `sendInput/resumeAgent/retry` 协作协议已经完成。
- 补充：AI Chat Seminar 的本机 checkpoint 恢复入口现在显示为 `断点详情 / Checkpoint details`，不再显示旧 `恢复详情 / Resume details`。用户看到 `可从中断处继续` 后，可以点 `继续研讨` 直接从缺失角色续跑，也可以点 `断点详情` 在同一张 AI Chat 卡内展开断点状态、已保存证据、下一步和 provider/model；这不是打开旧 runtime page，也不是旧 LLM stream 原地续传。当前只是 checkpoint 入口文案和测试等待边界收口，不代表 OS 后台执行、旧 stream 原地续传或完整恢复协议。
- 补充：AI Chat Seminar 的 Settings 默认设置说明不再指向旧“运行页 / run page”。用户在 Settings -> AI -> Seminar settings 里看到的是默认角色、核验者和预算保护会预填新的研讨；每次运行的预算覆盖仍要在 AI Chat 里开始本次研讨前调整，不再暗示还有独立 runtime page。当前只是 Settings 文案和用户入口心智收口，不代表完整 AI Chat 原生运行流、完整预算 UI 或完整角色自由工具调用 loop。
- 补充：AI Chat Seminar 的来源缺失沉淀动作会在中文卡片里显示清楚原因。历史恢复时如果一条保存知识卡、加入复习或加入图谱动作因为没有可追溯来源而被降级，用户看到的是 `缺少可追溯来源，不能直接保存为知识资产；请先送入异常处理。`，并同时看到 `已中断 / 中断原因 / 来源缺失 / 异常送审`，不会只看到英文内部错误，也不会误以为知识卡已经保存成功。当前只是来源异常沉淀动作的用户可见说明补齐，不代表完整 AI reviewer service、完整 Review Inbox 自动审批或完整 artifact action 审计。
- 补充：AI Chat Seminar 历史恢复时，缺少可追溯 `SourceRef` 的普通沉淀动作不会再显示成已确认知识资产。如果 graph replay 里只有证据摘录、没有可打开来源或来源不可用原因，却写着 `knowledge-card-saved`、`spaced-review-added` 或 `concept-graph-added`，AI Chat 会把它降级为来源异常/可送审语义，不再恢复 `已保存知识卡 / 复习已加入 / 图谱已加入` 和撤销入口。当前只是 graph replay / 历史恢复层的来源 gate，不代表完整 AI reviewer service、完整 Review Inbox 自动审批或完整 artifact action 审计。
- 补充：AI Chat Seminar ready 状态的 `调整设置` 区也不再把单次配置描述成“这张研讨卡 / Only this Seminar card changes”。用户在卡内改轮次或本次研讨问题时，看到的是“只影响本次研讨 / Only this Seminar run changes”，同时仍明确不会写回全局 Settings。当前只是 ready 设置区文案和用户心智收口，不代表完整 streaming tool-call 统一组件、完整角色自由工具调用 loop 或完整 `sendInput/resumeAgent/retry` 协作协议已经完成。
- 补充：AI Chat Seminar 的 Add-to-Chat 设置 sheet 不再把单次配置描述成“即将插入的研讨卡”，英文也不再写 `next Seminar card` 或 `panel can continue`。用户看到的是“即将开始的研讨 / next Seminar run”，分歧后的继续讨论也明确发生在 chat 内。当前只是入口文案和用户心智收口，不代表完整 streaming tool-call 统一组件、完整角色自由工具调用 loop 或完整 `sendInput/resumeAgent/retry` 协作协议已经完成。
- 补充：AI Chat Seminar 的等待类失败提示现在也使用等待语义。`等待角色` 或 `等待工具调用` 如果因为目标 run/tool-call 不可解析、graph 无对应事件或历史卡无法刷新而失败，提示会显示 `未能等待角色 / 未能等待工具调用`，不再显示旧的 `未能刷新角色 / 未能刷新工具调用`。当前只是失败提示文案收口，不代表 provider stream 阻塞等待、provider 级单工具硬中断或完整 tool wait/cancel 执行器已经完成。
- 补充：AI Chat Seminar 的 `等待工具调用` 现在不是单纯刷新工具详情。用户在当前 AI Chat 卡的 `调用 / 工具调用详情` 点击 running 工具调用的 `等待工具调用` 后，会在同一张卡写入可恢复的工具等待记录，并在 `全部` 视图看到 `等待工具调用 · 批判者` 和 `待处理`；同一个工具调用不会继续显示重复的等待按钮，仍可点击 `取消工具调用`。工具事件完成后再次等待会把该记录收口为 `已处理`。当前只是 graph-backed 工具等待记录和卡内可见性，不是 provider stream 阻塞等待、provider 级单工具硬中断、完整 tool wait/cancel 执行器或角色自由工具调用 loop。
- 补充：AI Chat Seminar 手动取消现在会保留取消前已经完成的角色回合和账单快照。此前如果 completed turn 已经从 role stream 发出但还没应用到 provider state，点击取消可能生成没有 billingSnapshot 的 cancelled run；现在取消前已收到的 completed turn 会先进入 cancelled run，当前卡和本机恢复看到的 usage/billing 不会凭空丢掉。当前只是取消时序和账单快照保真，不是旧 provider stream 原地续传、provider 级单工具硬中断或完整自由工具调用 loop。
- 补充：AI Chat Seminar 的默认 runtime provider 现在会把 streamed role thinking/tool-call/status 写入持久化 `AgentRunGraphStore`。此前 service 层已支持 graph store，但生产默认 `aiSeminarRuntimeServiceProvider` 未传入，所以真实 AI Chat Seminar 的 live role 工具调用更依赖当前 runtime state 和卡片 snapshot；现在当前卡和历史恢复可以使用同一套 parent/child graph-backed 工具事件来显示工具详情、运行追踪和 wait/cancel/close 控制。当前只是默认 provider 的 graph store 接线补齐，不是 provider 级单工具硬中断、完整自由工具调用 loop、完整 tool wait/cancel 执行器或旧 stream 原地续传。
- 补充：AI Chat Seminar 的 live 角色工具调用现在点击 `取消工具调用` 后会在当前 AI Chat 卡内直接变成 `已停止`。此前按钮已经显示在 `调用 / 工具调用详情`，但 scoped runtime state 仍可能保留 running `roleAgentToolCallEvents`，导致 graph 已停后当前卡又显示回 `调用中 / 可用控制`；现在取消整场 active runtime 时会同步把非终态 live tool-call event 标成 shutdown 并清空 actionIds。当前只是 live 工具调用取消后的卡片状态一致性收口，不是 provider 级单工具硬中断、完整 tool wait/cancel 执行器、角色自由多轮工具调用 loop 或旧 provider stream 原地续传。
- 补充：AI Chat Seminar 的读者控制记录如果被标记为 `canceled`，现在也会在原生 `研讨流` 里显示为 `已取消`，并使用 `取消时间`。这覆盖 `发送输入 / 继续角色 / 重新生成角色 / 等待角色` 这类 reader_turn 控制回合，避免历史恢复或 graph replay 使用另一种取消拼写时误显示成普通 `处理时间`。当前只是读者控制记录取消终态别名保真，不代表完整 blocking wait、完整 `sendInput/resumeAgent/retry` 协作协议或角色自由工具调用 loop。
- 补充：AI Chat Seminar 的工具调用如果被标记为 `canceled`，现在也会在原生 `研讨流` 里显示为 `已取消`，并使用 `取消原因 / 取消时间`。此前只有 `cancelled` 拼写会走取消语义，provider、adapter 或历史 replay 写入 `canceled` 时可能掉回普通 `工具输出 / 执行时间`，让用户误以为工具调用正常执行。当前只是工具调用取消终态别名保真，不代表完整 streaming tool-call 统一组件、完整工具取消/等待/恢复协议或角色自由工具调用 loop。
- 补充：AI Chat Seminar 的核验者角色在原生思考块里也会显示为 `核验者`。如果历史卡或 graph replay 恢复出 `roleId=verifier` 的 thinking message part，但没有自带显示名，AI Chat 不再 fallback 成 `验证者`；Settings、Add-to-Chat 调参、本次设置和原生研讨流里的同一角色命名保持一致。内部 `roleId=verifier`、agentRunId 和历史 JSON 不变。当前只是原生消息块角色术语一致性首片，不代表完整 role registry、本地化持久化 schema、完整 thinking/tool-call 统一组件或角色自由多轮工具调用 loop。
- 补充：AI Chat Seminar 的运行追踪标签现在按中文界面显示为 `运行追踪 / 父运行`。用户在状态、控制、调用、思考、沉淀或原生研讨流里查看可追踪运行信息时，不再看到旧英文 `Agent trace / Parent run` 标签；底层 `agentRunId/parentRunId`、trace 出现位置和深看页可追踪能力不变。当前只是 trace 标签本地化首片，不代表隐藏调试 id、完整 trace 折叠策略、完整 tool-call/thinking 统一组件或角色自由多轮工具调用 loop。
- 补充：AI Chat Seminar 写进当前会话历史的 `本次研讨设置` 也会显示可读角色名。用户开始一场研讨后，历史/恢复用的 setup 块不再显示 `角色：critical、supportive、synthesizer`，而是显示 `角色：批判者、支持者、综合者`；核验者也会显示为中文可读名称。内部 `roleIds`、ValueKey、agentRunId、角色配置和 prompt 协议仍使用 role id。当前只是本次设置持久化文案的 raw role id 隐藏首片，不代表完整角色配置 UI、完整 role registry、本地化持久化 schema、角色自由多轮工具调用 loop 或完整 streaming tool-call 统一组件。
- 补充：AI Chat Seminar 写进当前会话历史的 `本次研讨设置` 也会显示可读证据范围。用户开始一场研讨后，历史/恢复用的 setup 块不再显示 `证据：current-book`，而是显示 `证据：当前书籍`；书库、笔记、记忆和概念图谱等范围也会显示为中文可读名称。内部 `evidenceScopeIds`、ValueKey、角色配置和 prompt 协议仍使用 scope id。当前只是本次设置持久化文案的 raw scope id 隐藏首片，不代表完整 role id 本地化、完整 evidence broker、完整 tool registry UI、角色自由多轮工具调用 loop 或完整 streaming tool-call 统一组件。
- 补充：AI Chat Seminar 的工具设置项现在显示用户可读名称。用户在 AI Chat 任务卡内调整 `本次只读工具`，或在 Settings -> AI -> Seminar settings 里配置 `允许的只读工具` 时，会看到 `书内语义检索 / 书库语义检索 / 笔记搜索 / 记忆搜索 / 图谱检索 / 原文定位`，而不是 `semantic_search_current_book / memory_search / concept_graph_search` 这类内部 id；内部配置、权限过滤和 prompt 协议仍使用 tool id。当前只是设置入口工具名可读性和 raw id 隐藏首片，不代表完整 tool registry UI、MCP 工具配置面板、角色自由多轮工具调用 loop 或完整 streaming tool-call 统一组件。
- 补充：AI Chat Seminar 的 `调用` 子视图现在显示为 `工具调用详情`。用户在研讨卡里看到书内语义检索、笔记搜索、记忆搜索或图谱检索等工具调用后，点击 `调用` tab 会进入工具调用详情，而不是看到容易误解的 `证据调用` 标题；同时由工具调用派生出的证据块会按工具来源携带 `toolId` 并参与同一套 scope 过滤，当前只启用 current-book 的研讨不会在默认 `研讨流` 里漏出禁用的 library fallback 证据。当前只是工具调用详情命名、toolId 证据拆分和禁用 scope 可见性保真，不代表完整 streaming tool-call 统一组件、工具等待/取消/恢复详情、角色自由多轮工具调用 loop 或完整 evidence broker。
- 补充：AI Chat Seminar 的主持人/父运行状态现在有 `状态` 深看入口。用户在研讨卡里看到 `主持人正在等待你的回应 / 研讨正在运行 / 研讨已中断 / 研讨已停止 / 研讨运行失败` 等整场状态后，可以在同一张 AI Chat 卡内切到 `状态详情`，查看状态正文、运行追踪和父运行；带旧 snapshot 内容的多条主持人历史仍保持旧概览，避免旧恢复记录被紧凑研讨流隐藏。当前只是 Director / 父运行状态原生详情入口首片，不代表完整 Director orchestration、完整 checkpoint recovery 协议、完整 `sendInput/resumeAgent/retry` 协作协议、完整角色自由多轮工具调用 loop 或旧 provider stream 原地续传。
- 补充：AI Chat Seminar 的角色生命周期控制现在有 `控制` 深看入口。用户在研讨卡里看到 `等待角色 / 停止角色 / 发送输入 / 继续角色 / 重新生成角色` 等控制后，可以在同一张 AI Chat 卡内切到 `控制详情`，查看这些控制对应的角色状态、允许工具、运行追踪和父运行；带旧 snapshot 内容的控制历史仍保持旧概览，避免多条 reader/agent 控制记录被紧凑研讨流隐藏。当前只是 control 原生详情入口和控制历史保真首片，不代表完整 blocking wait、完整 `sendInput/resumeAgent/retry` 协作协议、完整角色自由多轮工具调用 loop 或旧 provider stream 原地续传。
- 补充：AI Chat Seminar 的思考状态现在有 `思考` 深看入口。用户在研讨卡里看到角色或主持人的思考状态后，可以在同一张 AI Chat 卡内切到 `思考详情`，查看角色上下文、思考内容、时间和 运行追踪；默认折叠的 `研讨流` 也会优先保留最新角色 thinking，避免用户只看到主持人状态却看不到当前角色正在如何准备基于证据发言。当前只是 thinking 原生详情入口和默认可见性首片，不代表完整 provider reasoning stream、完整 thinking/tool-call 统一组件、完整角色自由工具调用 loop 或旧 provider stream 原地续传。
- 补充：AI Chat Seminar 的沉淀动作现在有 `沉淀` 深看入口。用户在研讨卡里看到保存知识卡、加入复习、加入我的图谱、异常送审或忽略建议后，可以在同一张 AI Chat 卡内切到 `沉淀动作详情`，查看动作状态、执行结果或失败/取消原因、关联证据和 运行追踪，而不是只能在默认 `研讨流` 里扫一块历史记录。当前只是 artifact action 原生详情入口首片，不代表完整审计详情页、跨设备撤销恢复 gate、完整 AI reviewer service、完整 Review Inbox 自动审批或角色自由工具调用 loop。
- 补充：AI Chat Seminar 的纯异常预审历史卡现在也会显示 `异常` 深看入口。也就是说，即使一张历史卡只有 `AI 风险等级` 和 `建议动作`，没有综合总结或证据快照，用户仍能在同一张 AI Chat 卡里切到异常处理预览，而不是只能在默认 `研讨流` 里看到两行风险提示。当前只是 review triage-only 历史卡的异常子视图可达性补齐，不代表完整 AI reviewer service、完整 Review Inbox 自动审批、完整 artifact action 审计或角色自由工具调用 loop。
- 补充：AI Chat Seminar 的历史异常预审卡即使没有单独的 `证据快照` 块，也会从原生 `研讨总结`、`知识卡候选`、`复习候选` 等 message parts 自带的 evidence refs 统计可追踪证据。这样用户在 `异常` 视图里不会看到候选证据明明存在、但顶部却显示 `可追踪证据：0 条` 的矛盾状态。当前只是原生 messageParts evidence refs 的计数和证据视图保真，不代表完整统一 evidence broker、SourceRef 自动修复、完整 AI reviewer service 或角色自由工具调用 loop。
- 补充：AI Chat Seminar 默认折叠的原生 `研讨流` 现在也会优先保留异常预审。长研讨流里即使前面已经有很多角色发言，用户仍能在默认概览看到 `AI 风险等级`、`建议动作` 和 `送入异常中心`，不需要先展开深看页才知道为什么这次内容应当走异常中心。Review 预览里的可追踪证据条数会按来源去重，避免同一证据重复出现在多个原生 part 后把证据数量夸大。当前只是异常预审默认可见性和证据计数保真，不代表完整 AI reviewer service、完整 Review Inbox 自动审批、完整 artifact action 审计或角色自由工具调用 loop。
- 补充：AI Chat Seminar 的沉淀动作详情文本现在会显示清楚的审计标签。用户在原生 `研讨流` 里看到保存知识卡、加入复习、加入我的图谱、异常送审或忽略建议的历史记录时，会看到 `执行结果 / 处理说明 / 失败原因 / 未找到原因 / 取消原因` 这类标签，不再只看到一段没有语义说明的正文。当前只是 artifact action 审计详情标签首片，不代表完整审计详情页、跨设备撤销恢复 gate、完整 AI reviewer service 或角色自由工具调用 loop。
- 补充：AI Chat Seminar 的沉淀动作如果被取消，会在原生 `研讨流` 里显示 `已取消` 和 `取消时间`。这样用户能区分“保存/加入/送审动作被取消”和“动作已经执行成功”，不会因为旧的默认 `执行时间` 文案误以为知识卡、复习、图谱或异常送审已经落地。当前只是取消终态文案防误导，不代表完整 artifact action 审计、跨设备撤销恢复 gate、完整 AI reviewer service 或角色自由工具调用 loop。
- 补充：AI Chat Seminar 默认折叠的原生 `研讨流` 现在会优先保留 `沉淀动作`。如果一场研讨已经有很多角色发言，用户仍能在默认概览里看到 `保存知识卡 / 加入复习 / 加入我的图谱 / 异常送审` 这类下一步学习闭环动作，不需要先切到深看页才知道可以保存或加入复习。当前只是默认概览的动作可见性保真和 legacy/native 时间线合并收口，不代表完整 artifact action 审计、跨设备撤销恢复 gate、完整 AI reviewer service 或角色自由工具调用 loop。
- 补充：AI Chat `Choose style / 选择风格` 现在只展示普通可激活 skill，不再显示 `Seminar Mode / 研讨会模式` 或 `Seminar settings / 研讨会设置` 行。AI 研讨会的用户入口继续收窄为 AI Chat `+ -> AI 研讨会` 原生任务卡；全局角色默认配置仍从 Settings -> AI -> `Seminar settings` 进入；单次运行配置仍在 `AI 研讨会` 任务卡内完成。当前只是入口心智收窄，不代表完整 streaming tool-call 组件、完整角色自由工具调用 loop 或完整 `sendInput/resumeAgent/retry` 协作协议。
- 补充：历史恢复的 AI Chat Seminar 沉淀动作现在会继续保留可撤销/可恢复入口。已保存知识卡会恢复 `撤销保存`，已加入复习会恢复 `撤销复习`，已加入我的图谱会恢复 `撤销图谱`，已忽略沉淀建议会恢复 `恢复操作`；不会因为 graph event 只记录了终态动作，就让用户重开历史后只能看见“已保存/已忽略”而不能在当前 Chat 卡内回退。当前只是 graph replay 的 action affordance 保真，不代表跨设备撤销恢复 gate 或完整 AI reviewer service。
- 补充：运行中的 current AI Chat Seminar 卡片现在会把当前正在生成的角色显示成原生 `角色状态` 块。用户在同一张 AI Chat 原生流里能看到 `角色正在生成`、`等待角色` 和 `停止角色`，并且该状态块和角色 partial、thinking、tool call 保持同一 child run identity。当前只是 active role status/control 可见性首片，不代表完整 blocking wait、完整 `sendInput/resumeAgent/retry` 协作协议、角色自由工具 loop 或旧 provider stream 原地续传。
- 补充：默认 `研讨流` 折叠时也会优先保留运行中角色的 `角色状态` 块。即使同一张卡同时有证据、工具调用和 partial 发言，用户仍能直接看到 `角色正在生成`、`等待角色` 和 `停止角色`，不用切到分类 tab 才能操作。当前只是默认流可见性保真，不代表完整 provider stream 中断恢复或角色自由工具 loop。
- 补充：带旧 snapshot 内容的历史/混合 AI Chat Seminar 卡片，在默认 `全部` 概览回退到 legacy overview 时，也会显示全部原生 `agent_status` 角色状态。也就是说，第 4 条及后续 `角色状态`、`发送输入`、`等待角色` 或 `停止角色` 控制不会只留在内部数据里。当前只是 legacy overview 的角色状态可见性保真，不代表完整 blocking wait、完整 provider stream 中断恢复或角色自由工具 loop。
- 补充：运行中的 current AI Chat Seminar 卡片里，普通主流程角色的 `停止角色` 现在会真正取消本场 scoped runtime。也就是说，用户看到某个角色正在生成时点 `停止角色`，不再只是在 graph/status 层留下停止痕迹而让当前 runtime 继续跑；当前只是主流程 active role stop 修复，不代表完整 child-level provider stream 中断、完整 wait/resume 协议或旧 provider stream 原地续传。
- 补充：AI Chat Seminar 的 `分歧` 深看子视图不再只显示原生 `messageParts.type=disagreement`、`messageParts.type=contradiction_scan` 和 `messageParts.type=disagreement_rebuttal` 的前四条。用户主动切到 `分歧` tab 时，会看到历史或当前 snapshot 里全部原生分歧内容、全部原生分歧扫描内容和全部原生反驳回合；默认 `研讨流` 和 compact timeline 仍保留代表性折叠。当前只是深看页 disagreement / contradiction-scan / disagreement-rebuttal parts 保真，不代表完整 contradiction scanner、自动反驳策略、反驳/扫描分页、完整卡内详情、SourceRef 自动修复或角色自由工具 loop。
- 补充：completed runtime 把白板分歧写入当前 AI Chat 卡片 snapshot 时，也不再先截成前四条。也就是说，角色一次产出的第 5 条及后续结构化分歧会进入 `snapshot.disagreementDetails`、`messageParts.type=disagreement` 和 `messageParts.type=contradiction_scan`，之后用户切到 `分歧` 深看页才能看到完整数据。默认 `研讨流` 仍保留代表性折叠；当前只是生成阶段和深看页的数据保真，不代表完整 contradiction scanner、自动反驳策略或角色自由工具 loop。
- 补充：completed/restored AI Chat Seminar 卡片的分歧快捷操作也不再只给前三条分歧。用户看到第 4 条及后续分歧时，同一张卡会继续显示对应的 `让批判者反驳` 和 `围绕分歧重找证据` 操作，能直接推动该条讨论，而不是只能在深看页读到它。当前只是多分歧操作入口保真，不代表完整自动反驳策略、完整 contradiction scanner、操作区分页或角色自由工具 loop。
- 补充：`contradiction_scan` 的 `优先处理` 队列也不再只显示前三个可点击项。用户在 `分歧` 深看页看到多个证据缺口和已有证据分歧时，队列会按“先补证据、再反驳已有证据分歧”的顺序显示全部 actionable 项，不会把第 4 个及后续反驳/补证据入口静默挤掉。当前只是优先处理队列完整性，不代表完整 contradiction scanner、自动优先级策略、操作区分页或角色自由工具 loop。
- 补充：`contradiction_scan` 的 `证据缺口汇总` 也不再只显示前三条缺口正文。用户在 `分歧` 深看页看到第 4 条及后续证据缺口时，汇总区和逐条扫描明细都会显示这些缺口，不会出现数量 chip 显示 4 条但汇总正文只列 3 条。当前只是证据缺口汇总可见性保真，不代表完整 contradiction scanner、自动优先级策略、证据分页或角色自由工具 loop。
- 补充：带旧 snapshot 内容的历史 AI Chat Seminar 卡片，在默认 `全部` 概览回退到 legacy overview 时，也不再只显示前四条 `reader_turn`。如果同一张卡里已经有第 5 条及后续 `发送输入 / 继续角色 / 重新生成角色 / 等待角色` 记录，用户会在 `读者参与` 区看到完整读者控制历史，而不是只保留在数据里、界面上静默消失。当前只是 legacy overview 的 reader control 可见性保真，不代表完整 `sendInput/resumeAgent/retry` 协作协议、provider stream 阻塞等待或角色自由工具 loop。
- 补充：带旧 snapshot 内容的历史 AI Chat Seminar 卡片，在默认 `全部` 概览回退到 legacy overview 时，也不再只显示前三条 `director_state`。如果同一张卡里已经有第 4 条及后续 `主持人下一步`、`主持人准备重新找证据`、`主持人已完成本轮研讨`、`研讨运行失败` 或其它 Director state 记录，用户会在 `主持人下一步` 区看到完整主持人状态历史，而不是只保留在数据里、界面上静默消失。当前只是 legacy overview 的 Director cue 可见性保真，不代表完整 Director orchestration、完整 `sendInput/resumeAgent/retry` 协作协议、provider stream 阻塞等待或角色自由工具 loop。
- 补充：带旧 snapshot 内容的历史 AI Chat Seminar 卡片，在默认 `全部` 概览回退到 legacy overview 时，也不再只显示前两条 `reader_composer`。如果同一张卡里已经有第 3 条及后续 `可回应角色 / 可用动作 / 当前动作 / 当前角色 / 草稿回复` 这类只读 reader composer 记录，用户会在 `读者参与` 区看到完整可参与状态历史，而不是只保留在数据里、界面上静默消失。当前只是 legacy overview 的 reader composer 可见性保真，不代表 live composer 提交流程、完整 `sendInput/resumeAgent/retry` 协作协议、provider stream 阻塞等待或角色自由工具 loop。
- 补充：AI Chat Seminar 的 askUser `读者参与` composer 在用户已经提交 `让角色回应 / 重新找证据 / 整理总结` 后，会在当前卡片状态里收口，不再因为 legacy `openQuestions` 仍在 snapshot 里而重新显示“主持人正在等待你的回应”或可再次提交的 composer。用户会看到已提交的 `reader_turn` 和后续角色/总结状态，而不是同一张卡同时像“已处理”和“仍待回复”。当前只是已提交 composer 的状态收口，不代表完整 live composer 提交流程或完整 `sendInput/resumeAgent/retry` 协作协议。
- 补充：AI Chat Seminar 卡片里已经停止或不可找到的角色，不会因为后续旧 runtime snapshot 又回到“角色正在生成”并重新显示 `等待角色 / 停止角色`。这让用户点过停止后看到的终态更稳定；当前只是 `role-shutdown / role-not-found` 这类不可继续状态的卡内保真，不代表完整 provider stream 中断恢复或角色自由工具 loop。
- 补充：带旧 snapshot 内容的历史 AI Chat Seminar 卡片，在默认 `全部` 概览回退到 legacy overview 时，也不再只显示前四条 `role_partial`。如果同一张卡里已经有第 5 条及后续 `角色发言生成中` 片段，用户会在 `研讨时间线` 区看到完整角色流式发言历史，而不是只保留在数据里、界面上静默消失。当前只是 legacy overview 的 role partial 可见性保真，不代表完整 streaming role UI、完整 thinking/tool-call 统一组件或角色自由工具 loop。
- 补充：带旧 snapshot 内容的历史 AI Chat Seminar 卡片，在默认 `全部` 概览回退到 legacy overview 时，也不再只显示前四条 `role_turn` 或 legacy `roleSummaries`。如果同一张卡里已经有第 5 条及后续已完成角色观点，用户会在 `研讨时间线` 区看到完整角色发言历史，而不是只保留在数据里、界面上静默消失。当前只是 legacy overview 的 role turn 可见性保真，不代表完整 streaming role UI、完整 sub-agent 协作协议或角色自由工具 loop。
- 补充：scoped runtime / 本机恢复态把围绕分歧继续反驳的回合写入当前 AI Chat 卡片 snapshot 时，也不再只保留前四条 `messageParts.type=disagreement_rebuttal`。同一场研讨已经有第 5 条及后续反驳回合时，当前卡片 snapshot 会保留全部反驳 parts，用户切到 `分歧` 深看页能看到完整反驳记录；默认 `研讨流` 仍保留代表性折叠。当前只是生成/恢复阶段的反驳记录保真，不代表完整自动反驳策略、完整 contradiction scanner 或角色自由工具 loop。
- 补充：scoped runtime / 本机恢复态把已完成角色回合写入当前 AI Chat 卡片 snapshot 时，也不再只保留前四条 `messageParts.type=role_turn` 和 `snapshot.roleSummaries`。同一场研讨已经有第 5 个及后续角色回合时，当前卡片 snapshot 会保留全部 role turns，用户切到 `角色` 深看页能看到完整角色观点记录；默认 `研讨流` 仍保留代表性折叠。当前只是生成/恢复阶段的角色回合保真，不代表完整 streaming role UI、完整 sub-agent 协作协议或角色自由工具 loop。
- 补充：scoped runtime / 本机恢复态把本场可追溯证据写入当前 AI Chat 卡片 snapshot 时，也不再只保留前三条 `snapshot.evidence` 和 `messageParts.type=evidence`。同一场研讨已经有第 4 条、第 5 条及后续被引用证据时，当前卡片 snapshot 会保留全部 evidence refs，用户切到 `证据` 深看页能看到完整证据快照；默认 `研讨流` 仍保留代表性折叠。当前只是生成/恢复阶段的 evidence bundle 保真，不代表完整证据分页、SourceRef 自动修复或统一 evidence broker。
- 补充：scoped runtime / 本机恢复态把本场 evidence bundle 派生成证据工具调用时，也不再只保留前五条 `snapshot.toolCalls` 和 `messageParts.type=tool_call`。同一场 currentChapter、currentBook、library、notes、memory、conceptGraph 都有可追溯 evidence 时，当前卡片 snapshot 会保留全部 evidence-scope 工具调用，用户切到 `调用` 深看页能看到 `concept_graph_search` 等最后一个工具调用来源；默认 `研讨流` 仍保留代表性折叠。当前只是生成/恢复阶段的证据工具调用保真，不代表完整 streaming tool-call 统一组件、工具分页或角色自由工具 loop。
- 补充：AI Chat Seminar 的 `调用` 深看子视图不再只显示 legacy/current snapshot tool calls 的前五条。用户主动切到 `调用` tab 时，会看到 snapshot/messageParts 中全部通过当前场景过滤的工具调用；默认 `研讨流` 和 compact timeline 仍保留代表性折叠。当前只是深看页工具调用保真，不代表完整 streaming tool-call 组件、工具分页/虚拟列表、SourceRef 自动修复或角色自由工具 loop。
- 补充：AI Chat Seminar 的 `证据` 深看子视图不再只显示 legacy/current snapshot evidence 的前三条。用户主动切到 `证据` tab 时，会看到 snapshot 里全部非空证据，并继续使用完整证据 tile 的 `打开来源 / 来源不可用 / 来源缺失` 追溯语义；默认 `研讨流` 和 compact timeline 仍保留折叠。当前只是深看页证据保真，不代表完整证据分页、SourceRef 自动修复或统一 evidence broker。
- 补充：AI Chat Seminar 的异常处理预览不再把候选知识卡和复习候选的证据截成两条。异常 tab 中 `知识卡候选` 会显示候选自身引用的全部可追溯证据，`复习候选` 的 `综合证据` 会显示 synthesis handoff 的全部可追溯证据；证据较多时，`异常送审` 按钮仍在同一张 AI Chat 卡内通过滚动触达。这让送审前的异常依据不再丢第三条及后续来源。当前只是异常预览/送审前证据保真，不代表完整 AI reviewer、Review Inbox 自动审批、证据分页或 SourceRef 自动修复。
- 补充：AI Chat Seminar 的异常处理预览也不再把候选条目本身截成前三项。异常 tab 中 `知识卡候选明细` 和 `复习候选明细` 会显示全部候选；如果 AI 预审或历史 `review_triage` 给出第 4 项及后续候选，用户能直接看到这些候选及其证据，不会出现计数显示 4 项但明细只列 3 项。当前只是异常预览候选明细保真，不代表完整 AI reviewer、Review Inbox 自动审批、批量 triage 或 artifact action 审计。
- 补充：AI Chat Seminar 默认 `研讨流` 里的 compact `关联证据` 行现在会复用完整证据 tile 的来源动作；如果 evidence ref 带 traceable `SourceRef`，用户可直接点 `打开来源` 跳回 reader source；如果只有不可跳原因，会显示 `来源不可用` 说明。这样研讨总结、异常预审等原生文本块的证据不再只是纯文本摘录。当前只是 compact 证据来源动作首片，不代表完整统一证据服务、跨 P1/P2/P3 evidence broker 或完整 streaming tool-call 组件。
- 补充：AI Chat Seminar 默认 `研讨流` 的 compact `关联证据` 不再只显示前两条 evidence refs；同一 synthesis、异常预审或其它原生文本块携带的所有非空关联证据都会显示一行紧凑摘录和来源动作。这样多证据结论不会在第三条之后静默丢失可追溯入口。当前只是文本块 evidence refs 可见性补齐，不代表完整证据详情分页或统一证据服务。
- 补充：AI Chat Seminar 默认 `研讨流` 的 compact `关联证据` 如果缺少 `SourceRef`，会显示 `来源缺失`，而不是只显示摘录。这样用户能区分“可跳回原文的证据”和“历史/迁移数据里只有文本、不能作为正式可追溯证据的材料”。当前只是缺来源可见性，不代表自动修复 SourceRef 或正式资产保存 gate 已完成。
- 补充：AI Chat Seminar 默认 `研讨流` 和证据深看里的完整 `证据快照` 也会标出缺来源状态。如果 evidence block 本身没有 `SourceRef`，tile 会显示 `来源缺失`；可跳来源仍显示 `打开来源`，不可跳但有原因的来源仍显示 `来源不可用`。这样完整证据块和 compact `关联证据` 的追溯语义一致，不会把历史/迁移数据里的纯文本证据伪装成已可跳回原文。
- 补充：AI Chat Seminar 默认 `研讨流` 里的 `证据快照` 不再只显示前三条 evidence refs。`messageParts.type=evidence/evidence_bundle` 如果带 4 条或更多证据，证据块会显示全部非空证据，并继续使用完整证据 tile 的 `打开来源 / 来源不可用 / 来源缺失` 追溯语义。这样 evidence block 本身不会在第四条以后静默丢失来源材料。
- 补充：AI Chat Seminar 默认 `研讨流` 里的 `tool_call` 返回证据不再只显示前两条。工具调用如果返回 3 条或更多 evidence refs，当前工具调用块会显示全部非空证据，并继续使用完整证据 tile 的 `打开来源 / 来源不可用 / 来源缺失` 追溯语义。这样用户能看见一次书内搜索、记忆搜索或图谱检索实际返回的全部可用证据，不会在第三条以后静默丢失。
- 补充：AI Chat Seminar 卡片的 legacy `证据调用` snapshot 也不再只保留前两条被引用 evidence refs。运行完成后，如果 evidence broker 返回 5 条结果、角色/总结实际引用其中 4 条，`证据调用` 数据源会保留这 4 条可追溯引用，并继续排除未被引用的结果。这样深看证据调用时不会出现 `resultCount` 很多但只能追溯前两条的割裂状态。当前只是旧 snapshot 数据源的引用保真，不代表完整 evidence broker、证据分页或角色自由工具调用 loop。
- 补充：AI Chat Seminar 的 graph replay 数据也不再只保存前两条 evidence refs。父级 evidence broker tool-call event 和角色级 evidence tool-call event 都会把全部可追溯 refs 写入 `AgentRunEvent.evidenceRefs`，后续历史恢复到 AI Chat 原生 `tool_call` 或 evidence block 时不会在落盘层先丢第三条及后续证据。当前只是 graph event 落盘层引用保真，仍不是完整 streaming tool-call 组件、证据分页、SourceRef 自动修复或角色自由工具调用 loop。
- 补充：AI Chat Seminar 正在运行中的当前卡片也不再把角色级 fallback `tool_call` 证据截成两条。角色尚未完成、但 evidence bundle 已经返回时，当前卡片从 role profile scopes 和 allowed tools 派生的角色工具调用块会保留全部可追溯 refs；如果真实 provider/agent stream 已经发出同 toolId 的 live tool-call event，则仍优先显示真实事件。当前只是 running 卡片 fallback 数据保真，仍不是完整 streaming tool-call 统一组件或角色自由工具调用 loop。
- 补充：AI Chat Seminar 默认 `研讨流` 里的角色发言 `本轮证据` 也不再只显示前两条。角色回答如果引用 3 条或更多 evidence refs，角色发言块会显示全部非空证据，并继续使用完整证据 tile 的来源状态。这样用户能直接看到某个角色结论实际依赖的全部证据，不会把第三条及后续引用藏掉。
- 补充：AI Chat Seminar 的异常工具调用终态时间现在会按状态显示。`completed` 仍显示 `执行时间 / Executed at`；`errored/interrupted/shutdown/cancelled/notFound` 分别显示 `失败时间 / 中断时间 / 停止时间 / 取消时间 / 未找到时间`。这样用户在历史 `研讨流` 中不会把中断、取消或停止误读成正常执行完成；当前只是状态化时间文案和 replay 时间锚点，不代表 timeout/slow-call policy、完整 streaming tool-call 组件、tool wait/cancel/resume 详情或旧 provider stream 原地续传。
- 补充：AI Chat Seminar 同一次工具调用从 `调用中` 进入 `调用完成/调用失败` 等终态后，graph replay 会把开始时间保留到终态工具块；如果终态块同时有 `startedAt/completedAt`，默认原生 `研讨流` 还会显示 `耗时 / Duration`。用户重新打开历史时不会因为 running 事件被折叠而丢掉这次工具调用等了多久；当前仍不是 timeout/slow-call policy、完整 streaming tool-call 组件、tool wait/cancel/resume 详情或旧 provider stream 原地续传。
- 补充：AI Chat Seminar 历史或 graph replay 恢复出的 running/pending `messageParts.type=tool_call` 如果带有 `startedAt`，默认原生 `研讨流` 现在会显示 `开始时间 / Started at`；终态工具调用仍显示 `执行时间 / Executed at`。用户能区分“工具刚开始调用”和“工具已经卡住一段时间”，但当前只是时间锚点可见化，不代表 duration/timeout、完整 streaming tool-call 组件、tool wait/cancel/resume 详情或旧 provider stream 原地续传。
- 补充：AI Chat Seminar 历史或 graph replay 恢复出的 `messageParts.type=thinking` 如果带有 `completedAt`，默认原生 `研讨流` 现在会显示 `思考时间 / Thought at`。用户能在同一张聊天卡里看见角色或主持人的思考摘要何时被记录；这只是 thinking 时间锚点可见化，不代表完整 provider reasoning stream、完整 thinking/tool-call 统一组件或旧 provider stream 原地续传。
- 阅读页入口来自选中文本后的横向菜单；窄屏上 `知识卡 / 研讨 / 图谱 / AI` 可能需要横向滑动才能看到。
- `Review Inbox` 有两个可达路径：Settings 顶层 AI 区的直达入口，以及 `Settings -> AI -> Review inbox`。
- AI Chat 的 Memory 入口是回答旁书签图标；tooltip 是 `Memory actions / 记忆操作`。普通显式保存的主动作是 `Remember this / 记住这条`，会直接写入今日日记并在同一条消息菜单切换为 `Undo memory / 撤销本条记忆`；撤销会移除刚追加的 Markdown 文本并把该候选标记为 dismissed。`Add to Review inbox / 加入待审核队列` 保留为低置信、敏感、冲突或用户想稍后处理的异常入口。结束会话时的自动摘要默认使用 `Smart save / 智能保存`：高置信候选直接写入今日日记，低置信候选才进入 Review Inbox。
- 图片知识卡必须先在 ImageViewer 点工具栏魔法棒 `AI Image Analysis / AI图片解析`，解析结果弹层出现后才会显示 `Card / 知识卡`。
- AI Chat 回答旁 `知识卡` 只在回答完成后可用；streaming 中禁用，不会写 store。普通点击会在当前 AI Chat 内保存 draft KnowledgeCard 并提示 `已保存为草稿知识卡`，不写 ReviewItem；旧 Review producer 只保留给兼容和异常路径。
- AI Chat 左下角 `+` 打开 Add-to-Chat sheet；其中 `AI 研讨会` 会在当前会话里写入一张原生 `AI 研讨会` 任务卡，不默认展开旧嵌入式研讨面板；待开始任务卡可在卡内展开 `本次设置`，编辑本次研讨问题、修改最多讨论轮次、启用/停用角色、编辑启用角色本次 prompt、切换启用角色本次只读工具范围并切换启用角色 current book/library/notes/memory/conceptGraph 证据范围，再点 `开始研讨` 启动；它不等同于 `Choose style / 选择风格`，而且 `Choose style / 选择风格` 现在不再显示 Seminar 行。旧 `openInlineSeminar(...)` 桥接 API 已从 `AiChatStream` 删除；外部入口只通过 `AiMultiTabChat.openSeminar(...) -> openNativeSeminarCard(...)` 写入原生任务卡；AI Chat 组件内的旧 inline panel 状态、渲染函数、全页跳转函数和同步 listener 分支也已移除；当前 AI Chat 原生任务卡按 `seminarSessionId` 使用 scoped runtime；阅读页或外部入口没有传入 session id 时会生成 `seminar-chat-*`，并用同一 session id 写入 AI Chat 任务卡作为进程死亡后的可见恢复锚点；不同 scoped runtime 的模型调用由本机 coordinator 串行化；任务卡随 `conversationV2` 保存，历史重载后仍保持原生卡片；待开始卡可点 `开始研讨`；如果同 session 本机 running checkpoint 可续跑，历史卡会显示 `可从中断处继续`、`继续研讨` 和 `断点详情`，其中 `继续研讨` 会在 AI Chat 卡片内直接复用保存 evidence 并从缺失角色续跑，`断点详情` 只在当前 AI Chat 卡片内展开断点状态、已保存证据、下一步和 provider/model；runtime 运行、完成或刷新证据时会按同一个 `seminarSessionId` 回写卡片状态和只读 snapshot，evidence fetch 尚未返回时卡片会先显示 `status=running` 的 pending 证据调用和 `调用中`，返回后卡片直接显示证据调用（工具名、查询、结果数量、可见角色、运行追踪和返回证据）、证据快照、角色观点、研讨总结、分歧数、开放问题数和 `研讨白板` 正文；历史卡如果是 explicit `messageParts` 已承载且没有 legacy snapshot 内容的迁移形态，默认 `全部` 概览会先显示按 part 顺序排列的 `研讨流`，单个 `seminar_run_setup`、`reader_turn`、`director_state`、`role-running` status 或 `reader_composer` 也会进入这条线性流，分类子视图只作为深看入口；当任务卡对应当前 scoped runtime 且 synthesis 已满足 `readyForReview` 时，卡片内会显示 `异常` 子视图和 `异常送审`，`异常` 子视图列出异常处理预览、综合总结、可追踪证据数量、待送审内容计数、候选明细、知识卡候选证据摘录、复习候选综合证据和 AI 预审建议，点击 `异常送审` 会调用同一 scoped runtime 的异常 Review handoff，把低置信、冲突或来源异常的可追踪 synthesis 和候选项送入 pending Review；`messageParts.review_triage` 首片已能让历史卡在没有 active runtime synthesis 时恢复异常原因、AI 预审建议、候选明细和候选证据；围绕分歧触发的角色反驳会写入 `messageParts.type=disagreement_rebuttal`，历史卡即使没有 active scoped runtime，也能在 `分歧` 子视图恢复目标分歧、回应角色、回应正文、证据引用和 运行追踪 / 父运行；`messageParts.type=disagreement` 与 `messageParts.type=contradiction_scan` 也已能在 `分歧` 子视图显示分歧/扫描正文、角色、证据和 运行追踪 / 父运行；`AiSeminarDirectorState` 第一片已可随 runtime state 保存，并能把 completed run 中的 open question 标为 `askUser`、disagreement 标为 `refreshEvidence` 且在状态区显示主持人下一步；`askUser` cue 已写入 `messageParts.type=director_state`，历史卡即使没有 active scoped runtime，也能在 `全部` 视图显示 `主持人下一步`、`主持人正在等待你的回应` 和第一条开放问题；`askUser` 可参与状态已写入 `messageParts.type=reader_composer`，历史卡没有 active scoped runtime 时也能只读显示 `可用动作`、`可回应角色`、`默认动作`、`默认角色`、`当前动作`、`当前角色`、`草稿回复` 和 Director 提问；同 session active runtime 仍使用真实 `读者参与` 输入框和提交按钮，避免把只读历史 schema 当成可提交表单；`askUser` 状态下用户可以输入回复并选择让角色回应、重新找证据或整理总结，回复只保存为 human intervention，不进入 formal evidence；其中“让角色回应”已会调用所选角色生成 follow-up turn 并更新 synthesis，“重新找证据”已会重新检索 evidence、重跑角色并更新 synthesis，“整理总结”已会用现有 evidence 和 turns 执行本地 synthesis 并收束 Director；completed run 完成后会在 synthesis 后显示 `Continue discussion / 继续讨论`，即使没有 open question，用户也能继续追问某个角色、要求重找证据或重新整理总结，输入仍只保存为读者回合；当 completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，runtime 会自动重新检索 evidence、重跑角色，并在预算耗尽仍有分歧时转为 `askUser`；Seminar settings 已能配置角色显示名、custom prompt、启用状态、会话证据提示和允许的只读工具；`AI 研讨会` 调参按钮可打开 `本次研讨设置`，只为下一张任务卡临时设置角色 prompt、启用状态、current book/library/notes/memory/conceptGraph 证据范围、核验者和最多讨论轮次；ready 任务卡也可直接编辑本次研讨问题、启用角色本次 prompt 和启用角色本次只读工具范围，不写回全局 Settings；disabled role 会从新 run 跳过，写工具、联网工具、unknown tool 和递归 `spawn_sub_agent` 会被过滤；AI Chat scoped runtime 的本机恢复缓存使用 `aiSeminarRuntimeStateV1:<seminarSessionId>`，普通 prefs backup 会跳过这些缓存；App 重启时如果 active Seminar 可从 traceable checkpoint 续跑，带完整 session 的 queued Seminar 会继续排队并在 active 完成后自动启动；但还没有完整异常详情表、完整 contradiction scanner/tab、完整 `sendInput/resumeAgent` 协作协议、真实 provider stream 中断/阻塞等待、旧 stream 原地续传和 AI Chat 同源详情状态。
- 补充：`Seminar Mode / 研讨会模式` 不再作为普通 `Active Skill` 使用。Settings 的 `Active Skill` 选择器会过滤 Seminar Mode，AI Chat 普通 skill button / Add-to-Chat active style 和 `Choose style / 选择风格` 也会把旧 `activeAiSkillId=seminar_mode` 当作无普通 skill；普通 LangChain Chat 不再注入 `Active Skill: Seminar Mode` prompt，也不会因为旧偏好值切到 Seminar scene。真正启动研讨必须走 AI Chat `+ -> AI 研讨会` 原生任务卡；全局角色默认配置从 Settings -> AI -> `Seminar settings / 研讨会设置` 进入。
- 补充：AI Chat Seminar 历史 `研讨流` 从 agent graph 恢复工具调用时，会保留同一角色 run 内不同 call id 的重复工具调用；即使两次调用使用同一个工具和同一个 query，也不会只剩最后一条。同一次工具调用的 `调用中 -> 调用完成/调用失败` 仍会收口为最新状态。这个补的是历史工具调用时间线准确性，不代表完整自由多轮工具调用 loop 或完整 streaming tool-call 统一组件。
- 补充：AI Chat Seminar 历史卡现在同时识别 `messageParts.type=evidence` 和目标 schema 的 `messageParts.type=evidence_bundle`。如果历史或后续 agent graph replay 使用 `evidence_bundle`，默认 `研讨流` 仍会显示 `证据快照` 和证据摘录，不会因为旧实现和目标 schema 命名不同而把证据块丢掉。这只是证据块原生展示兼容，不代表完整统一证据服务已经完成。
- 补充：AI Chat Seminar 历史和当前 `messageParts.tool_call` 如果带有终态 `completedAt`，默认 `研讨流` 与 `调用` 子视图里的工具调用块现在会显示 `执行时间 / Executed at`。用户能在同一张原生 AI Chat 卡里看到某次只读工具调用何时收口；如果旧数据同时残留 `status=running/pending` 和 `completedAt`，卡片仍按运行中显示，不展示执行时间，避免把未收口调用误读成已完成。这仍只是执行时间可见化和恢复一致性防线，不代表完整 tool wait/cancel/resume 详情、完整 streaming tool-call 组件或旧 provider stream 原地续传。
- 前置补充：AI Chat Seminar 的 `调用` 深看页会显示工具调用自身的 `可用控制` metadata。如果历史、graph replay 或未来 provider 写入 `messageParts.type=tool_call / actionIds=['wait-tool-call','cancel-tool-call']`，用户能在工具调用详情中看到 `等待工具调用 / 取消工具调用`，而不是让这些控制信息留在内部 JSON 里。后续首片已经把 running 角色级工具调用的 `cancel-tool-call` 接成可点击控制，并把 `wait-tool-call` 从早期刷新首片升级为 graph-backed waitRequest / `reader_turn(label=wait-tool-call)`；完整 provider 级单个工具请求硬中断和完整自由多轮工具 loop 仍未完成。
- 补充：AI Chat Seminar 历史 `异常` 子视图和默认 `研讨流` 现在可从 `messageParts.review_triage label=risk/suggested-action` 恢复 `AI 风险等级` 和 `建议动作`；未解决分歧的本地规则化首片显示 `中风险` 与 `送入异常中心`，不会在聊天流正文里暴露 `medium/send-to-review` 这类内部值。Default `研讨流` 只是把异常预审结果变得可读，不代表完整 LLM reviewer service、重复/冲突检查、Review Inbox risk 分组或批量异常处理。
- 补充：历史里 `待开始` 且没有运行结果 snapshot（或只有 setup-only snapshot）的 `AI 研讨会` 任务卡现在可展开 `本次设置`，在卡内编辑本次研讨问题、启用角色本次 prompt 和证据范围后同步写入 `messageParts.type=seminar_run_setup`，再点 `开始研讨`，用同一张卡的 session、问题、SourceRef、角色、轮次和本次角色配置启动 scoped runtime，不打开旧独立页面或嵌入式面板；完成后的证据、角色发言和总结仍回写到同一张卡。已有运行结果 snapshot 的旧卡不会显示重新开始入口。
- 补充：AI Chat `本次研讨设置` 现在还可为下一张任务卡临时覆盖每个角色的 current book/library/notes/memory/conceptGraph 证据范围；该选择只写入本张 Seminar 任务卡的 role profile，不写回全局 Settings。运行时已开始把已收集 evidence 按角色 `roleProfiles.evidenceScopes` 过滤后交给对应角色，并按角色 scope 校验引用和 checkpoint；notes/memory/conceptGraph 独立检索首片已接入 broker，真实角色工具调用 loop 和 streaming/tool-call 细化仍未接入。
- 补充：ready/draft 且没有运行结果 snapshot（或只有 setup-only snapshot）的原生 `AI 研讨会` 任务卡现在显示 `本次设置` 摘要，用户可在卡内展开 `调整设置`，编辑本次研讨问题、用 +/- 修改最多讨论轮次、启用/停用本次研讨角色、编辑启用角色本次 prompt、切换启用角色本次只读工具范围，并为启用角色切换 current book/library/notes/memory/conceptGraph 证据范围；这些修改只回写同一张任务卡，并同步写入/替换 `messageParts.type=seminar_run_setup`，不打开 runtime panel，也不写回全局 Settings。运行时已开始按角色 scope 过滤已收集 evidence；notes/memory/conceptGraph 已有运行前 broker 独立检索首片，真实角色工具调用 loop 和完整 streaming 工具调用 UI 仍需继续内联化。
- 补充：运行中的原生 `AI 研讨会` 任务卡现在不仅能先显示证据调用；当 scoped runtime 正在生成某个角色发言时，同一张卡会显示 `角色发言生成中`、当前角色身份和 partial 文本。这个首片让用户在 AI Chat 内看到角色正在说什么；后续 `messageParts.role_partial` 首片已补上，历史卡即使没有 active scoped runtime 也能恢复 `角色发言生成中` 和 partial 文本，完成后由正式 `role_turn` 接管。
- 补充：运行中的同 session 原生 `AI 研讨会` 任务卡现在有 `取消研讨` 按钮。点击后只调用当前卡片对应 scoped runtime 的 `cancel()`，把状态转为 `cancelled` 并清掉 active role，不打开旧独立页面或内嵌面板。close/wait/send/resume 的 graph 控制首片已陆续接入，但真实 provider stream 中断、完整 `sendInput/resumeAgent` 协作协议和角色自由工具调用仍未完成。
- 补充：Director 进入 `askUser` 等待用户回应时，现在会在同一个 agent graph 里写入父 Director `status:waiting_input` event，并可在历史恢复时通过 event adapter 还原为 `messageParts.reader_composer`，带 `ask-role / refresh-evidence / synthesize` 可用动作和开放问题或分歧 prompt。这个只是等待状态进入 subagent event replay 的首片；close/wait/send/resume 的可点击首片已陆续接入，但完整 `sendInput/resumeAgent` 协作协议、真实 provider stream 中断和角色自由工具调用仍未完成。
- 补充：如果历史或 graph replay 里恢复出父 Director 的 `pendingInit/running` 状态，AI Chat 原生卡现在会按 `director_state(label=pending/running)` 显示为整场 `研讨等待启动 / 研讨正在运行`，不会再混成某个角色的 `角色等待生成 / 角色正在生成`。子角色排队或运行仍显示为角色状态，并保留等待、停止等角色控制。这个只是父运行 active 状态和 child role active 状态的语义分离，不代表完整 streaming tool-call 或旧 provider stream 原地续传。
- 补充：如果历史或 graph replay 里恢复出父 Director 的 `errored` 状态或 error event，AI Chat 原生卡现在会按 `director_state(label=failed)` 显示为整场 `研讨运行失败`，不会再混成某个角色的 `角色生成失败`。子角色失败仍显示为角色状态，并保留 `重新生成角色` 控制。这个只是父运行失败和 child role 失败的语义分离，不代表完整恢复协议或旧 provider stream 原地续传。
- 补充：如果历史或 graph replay 里恢复出父 Director 的 `interrupted` 状态，AI Chat 原生卡现在会按 `director_state(label=interrupted)` 显示为整场 `研讨已中断`，不会再混成某个角色的 `角色生成已中断`。子角色中断仍显示为角色状态，并保留 `继续角色` 控制。这个只是父运行中断和 child role 中断的语义分离，不代表旧 provider stream 原地续传。
- 补充：如果历史或 graph replay 里恢复出父 Director 的 `shutdown/notFound` 状态，AI Chat 原生卡现在会按 `director_state(label=stopped/not-found)` 显示为整场 `研讨已停止 / 研讨运行未找到`，不会再混成某个角色的 `角色生成已停止 / 角色运行未找到`。子角色停止或未找到仍显示为角色状态。这个只是父运行 terminal 状态和 child role terminal 状态的语义分离，不代表旧 provider stream 原地续传。
- 补充：点击角色状态里的 `等待角色` 时，如果 graph 中目标 child 已经完成，当前 AI Chat 卡会刷新出完成状态和角色输出；如果目标 child 仍在运行，会写入可回放的 `wait_request`，历史恢复时在原生 `研讨流` 显示 `等待角色` 和 `待处理`。这个 wait request 只是用户动作痕迹和刷新锚点，不会进入 runtime pending control 队列，也不是 provider stream 阻塞等待。
- 补充：如果用户先点了 `等待角色`，随后该角色已经完成，再次刷新或点击等待时，AI Chat 不会再生成第二条等待记录；原来的 `等待角色` 记录会通过统一 `AgentRunGraphStore.acknowledgeControlEvent(...)` 变成 `已处理`，并显示处理时间，同时同一张卡刷新出角色完成输出。这样历史里不会同时出现“角色已完成”和“等待仍待处理”的矛盾状态；`wait_request` 仍不进入 runtime pending control 队列，这仍不是旧 provider stream 原地续传或 provider stream 阻塞等待。
- 补充：重新加载历史 `AI 研讨会` 卡片时，如果旧 snapshot 里已经有某个角色的 `等待角色 / wait-agent` 待处理记录，而 graph replay 已经补进同一角色的完成结果、失败、停止或找不到等终态，provider 合并层也会把这条等待记录标为 `已处理`，并保留角色结果、失败原因或停止状态。这样用户不会因为历史恢复顺序不同而再次看到“等待仍待处理”和“角色已完成/已失败/已停止”并存；这仍只是等待动作满足状态，不代表 provider stream 阻塞等待。
- 补充：如果旧 snapshot 或当前卡里已有某个角色的 `等待角色 / wait-agent` 待处理记录，而 graph 后续显示同一角色进入 `已中断 / role-interrupted`，AI Chat 也会把这条等待记录标为 `已处理`，同时保留角色的 `继续角色` 入口。这样用户不会一边看到“等待仍待处理”，一边又看到“角色已中断可继续”；这只是 wait request 的状态收口，不代表旧 provider stream 原地续传，也不会把 `发送输入 / 继续角色 / 重新生成角色` 这类真正运行控制误标为已处理。
- 补充：同 session active runtime 消费子角色 `发送输入 / 继续角色 / 重新生成角色` 控制事件时，只有目标角色真正完成并写回 `roleCompleted` 后，才会把对应 reader control 标为 `已处理`；如果因为缺少可追踪 evidence、prior turns 不合格、provider 失败或取消而只进入 `needsEvidence/failed/cancelled`，该 control 会继续保持 `待处理`，历史卡不会误显示为已处理。这仍只是 ack 边界收紧，不代表完整 `sendInput/resumeAgent` 协作协议或真实 provider stream 阻塞等待已完成。
- 补充：如果主流程角色，或上述 active runtime 消费控制后的目标角色，生成了引用缺失/不可追踪 evidence 的结果，父研讨会仍显示为需要补证据，但对应 child 角色不会继续伪装成 `正在生成`；graph 会把该 child run 收口为 `已中断 / interrupted` 并保留原因。这样历史恢复或当前卡刷新时，用户看到的是可继续/需补证据的角色状态，而不是一个永远 running 的角色；对应 `发送输入 / 继续角色 / 重新生成角色` 控制也不会被误标为已处理。
- 补充：如果主流程角色，或上述 active runtime 消费控制后的目标角色，在 provider/role stream 阶段失败，父研讨会仍显示为运行失败，但对应 child 角色不会继续伪装成 `正在生成`；graph 会把该 child run 收口为 `生成失败 / errored` 并保留原因。这样历史恢复或当前卡刷新时，用户看到的是失败角色和可重新生成入口，而不是一个永远 running 的角色；对应 `发送输入 / 继续角色 / 重新生成角色` 控制也不会被误标为已处理。
- 补充：如果主流程角色，或上述 active runtime 消费控制后的目标角色，role stream 正常结束但没有返回 completed turn，父研讨会也会显示为运行失败；graph 会把该 child run 收口为 `生成失败 / errored` 并保留 `produced no turn` 原因。这样用户看到的是失败角色和可重新生成入口，而不是一个永远 running 的角色；对应 `发送输入 / 继续角色 / 重新生成角色` 控制也不会被误标为已处理。
- 补充：如果主流程角色，或上述 active runtime 消费控制后的目标角色，返回的是带 error 的 failed turn，父研讨会也会显示为运行失败；graph 会把该 child run 收口为 `生成失败 / errored` 并保留角色失败原因。这样 provider/parser 已经把失败包装成 role turn 时，用户仍会看到失败角色和可重新生成入口；对应 `发送输入 / 继续角色 / 重新生成角色` 控制也不会被误标为已处理。
- 补充：如果主流程角色，或上述 active runtime 消费控制后的目标角色，返回了错误角色，例如本来要让批判者回应却返回了支持者回应，父研讨会也会显示为运行失败；graph 会把目标 child run 收口为 `生成失败 / errored` 并保留错误角色原因。这样用户不会看到目标角色一直卡在 `正在生成`，也不会把这次 `发送输入 / 继续角色 / 重新生成角色` 误显示为已处理。
- 补充：如果主流程角色，或上述 active runtime 消费控制后的目标角色，超过了本地角色输出预算，父研讨会也会显示为运行失败；graph 会把目标 child run 收口为 `生成失败 / errored` 并保留预算超限原因。这样用户不会看到超预算角色一直卡在 `正在生成`，也不会把这次 `发送输入 / 继续角色 / 重新生成角色` 误显示为已处理。
- 补充：如果上述 active runtime 准备消费 `发送输入 / 继续角色 / 重新生成角色` 前发现本场证据不可追踪，或已有角色回合本身不可信，父研讨会会显示需要补证据；graph 会把目标 child run 收口为 `已中断 / interrupted` 并保留原因。这样用户不会在已经提交控制后还看到角色继续停在 `等待输入`，对应控制也不会被误标为已处理。
- 补充：如果上述子角色控制续跑过程中用户主动取消，runtime 现在会给目标 child role 写入 `已停止 / shutdown` 终态，再把父研讨会标为 cancelled。这样历史恢复时同一条未消费的 `发送输入 / 继续角色 / 重新生成角色` 会显示为 `已取消`，而不是长期留在 `待处理`。
- 补充：上述取消不只在历史恢复后生效，当前 AI Chat 卡片也会立刻把本次 `发送输入 / 继续角色 / 重新生成角色` 的 reader turn 标为 `已取消`，并显示 `取消时间`。用户不需要关闭再打开会话才能看见这次控制已经被取消，也不会把取消误读成已经处理完成。
- 补充：重新加载历史 `AI 研讨会` 卡片时，如果旧 snapshot 里还有未处理的 `发送输入 / 继续角色 / 重新生成角色`，但 graph replay 后续显示同一 child 角色已经完成、失败、停止或找不到，provider 合并层会把这些未消费 reader control 标为 `已取消 / Cancelled`，并保留角色终态。这样用户不会再看到“输入仍待处理”但角色已经停止的矛盾状态，也不会把未被角色消费的输入误标成 `已处理`；这仍只是历史恢复取消态首片，不代表完整 `sendInput/resumeAgent/retry` 协作协议完成。
- 补充：同样，如果这些 reader control 本身来自 agent graph replay 而不是旧 snapshot，event adapter 也会在进入 `messageParts` 前按后续终态规范化为 `已取消` 或 `已处理`。也就是说，直接恢复 graph 事件和合并旧历史卡两条入口会显示同一套状态，避免用户在不同恢复路径里看到互相矛盾的待处理控制。
- 补充：历史 replay 里同一个角色 run 如果后续已有已处理的 `发送输入 / 继续角色 / 重新生成角色` 控制事件，早于它的旧未处理 `发送输入 / 继续角色 / 重新生成角色` 不会继续显示成 `待处理`，避免用户在同一张 AI Chat `研讨流` 里同时看到“角色已按 retry 处理”和“旧输入仍待处理”的矛盾状态。`等待角色` 仍只作为刷新/等待痕迹，不进入 runtime pending control 队列，也不会被这条规则误删。
- 补充：重新打开历史会话时，如果旧 snapshot 里还保存着某个角色的未处理 `发送输入 / 继续角色 / 重新生成角色`，而 agent graph 已经 replay 出同一角色的已处理控制事件，AI Chat 卡片会用已处理状态替换旧 `待处理` 状态，不会把 stale snapshot 和 graph replay 叠成两条读者回合。`等待角色` 仍按等待/刷新事件显示，不被当作 runtime control 自动吞掉。
- 补充：上述历史恢复规则也覆盖较早的 id-only `reader_turn` snapshot：即使旧 part 没有显式 `agentRunId`，只要 id 里保留 `:user-input:`、`:resume-request:` 或 `:retry-request:` 这类 child run 标记，AI Chat 仍能识别同一角色 run，并用 graph replay 的已处理控制事件清理旧 `待处理` 显示。`wait-request` 只用于识别等待记录归属，不会被当作 runtime control 自动消费。
- 补充：如果用户在同一个 interrupted / failed 角色状态上重复点击 `继续角色` 或 `重新生成角色`，AI Chat 不会再为同一 child run 追加第二条同类型 pending request；已有未消费的 `resume_request` 或 `retry_request` 会被复用并刷新当前卡片。这样历史 `研讨流` 里不会因为重复点击堆出多条一模一样的 `继续角色 / 重新生成角色` 待处理记录；这仍只是 pending control 去重，不代表完整 `sendInput/resumeAgent/retry` 协作协议或旧 provider stream 原地续传。
- 补充：如果用户在同一个 waiting child role 上重复提交完全相同的 `发送输入` 文本，AI Chat 不会再为同一 child run 追加第二条相同 `user_input`；已有未消费的同文本输入会被复用并刷新当前卡片。这样双击提交、网络重试或 UI 重入不会在 `研讨流` 里堆出重复读者输入。不同文本仍可作为新的读者输入记录下来；这仍只是 exact-duplicate pending control 去重，不代表完整 `sendInput/resumeAgent/retry` 协作协议、provider stream 阻塞等待或旧 provider stream 原地续传。
- 补充：如果卡片还显示某个角色在 `等待输入`，但后台 graph 里该角色其实已经完成，用户提交输入时不会再停留在旧输入状态；AI Chat 会刷新到 graph 里的完成结果，也不会把这条过期输入写成新的 `user_input`。这样用户点到旧输入框时仍能看到真实结果，而不是得到一个静默失败的按钮。
- 补充：如果卡片还显示某个角色 `已中断` 并提供 `继续角色`，但后台 graph 里该角色其实已经完成，用户点击继续时不会再停留在旧中断状态；AI Chat 会刷新到 graph 里的完成结果，也不会把这次过期点击写成新的 `resume_request`。这只是过期按钮刷新，不代表旧 provider stream 原地续传。
- 补充：如果卡片还显示某个角色 `生成失败` 并提供 `重新生成角色`，但后台 graph 里该角色其实已经完成，用户点击重新生成时不会再停留在旧失败状态；AI Chat 会刷新到 graph 里的完成结果，也不会把这次过期点击写成新的 `retry_request`。这只是过期重试按钮刷新，不代表旧 provider stream 原地续传或完整失败恢复协议。
- 补充：当同 session active runtime 已经接受某条 `发送输入 / 继续角色 / 重新生成角色` 控制时，当前 AI Chat 卡片里的这条读者控制会显示 `处理中`；如果角色已经进入 activeRole，则仍要求该 activeRole 与控制目标角色一致；如果角色尚未开始输出，则要求 runtime 的 `activeAgentControlRunId` 与这条 reader control 的 child run id 匹配。这样用户点下继续/重试/发送输入后，即使角色正文还没开始输出，也能在原生研讨流里看到请求正在执行，同时旧 `lastUserIntervention`、普通 running runtime 或本机恢复出的旧 checkpoint 不会被误标为处理中；完成后显示 `已处理`，取消后显示 `已取消`。这仍不是 provider stream 阻塞等待，也不是旧 provider stream 原地续传。
- 补充：当同一 child run 已经有待处理的 `发送输入 / 继续角色 / 重新生成角色` reader turn 时，AI Chat 会从该角色状态块里移除对应的重复按钮，只保留仍然合理的其它控制，例如 `停止角色`。这样用户不会在同一张卡里一边看到“发送输入待处理”，一边又看到同一个 `发送输入` 按钮继续可点；当前卡片、新 graph replay 和已保存旧历史卡加载都会使用同一套 snapshot 规则。这仍只是卡片控制状态收口，不代表完整 `sendInput/resumeAgent/retry` 协作协议、provider stream 阻塞等待或旧 provider stream 原地续传。
- 补充：如果卡片因为旧 snapshot 还显示 `停止角色`，但后台 graph 里该角色其实已经完成、失败、停止或找不到，点击停止不会再把已有终态覆盖成 `已停止`。AI Chat 会刷新到 graph 里的真实终态，避免用户因为一个过期按钮误伤已经完成的角色结果；仍在运行的角色才会被停止。
- 补充：如果 `停止角色` 对应的是当前同 session scoped runtime 正在处理的 active child control，AI Chat 会同时取消这次 runtime，而不是只把 agent graph 里的 child run 关掉。也就是说，用户停止当前正在执行的 `发送输入 / 继续角色 / 重新生成角色` 控制时，当前研讨会会进入取消语义；没有 active scoped runtime 的历史卡仍只做 graph 状态刷新。这仍不是旧 provider stream 原地续传或完整 provider stream 中断恢复。
- 补充：如果当前卡片里已有 `发送输入 / 继续角色 / 重新生成角色` 的待处理记录，但后续 active runtime snapshot 只同步了同一个 child role 的终态结果，没有带回同一控制已被处理的 reader turn，AI Chat 会保留这条用户控制并显示为 `已取消` 和取消时间，不会让用户输入或继续/重试请求凭空消失，也不会把没有 ack 证明的请求伪装成 `已处理`。这只是当前卡片和 graph replay 的终态语义对齐，不是完整 `sendInput/resumeAgent/retry` 协作协议。
- 补充：如果某条 `发送输入 / 继续角色 / 重新生成角色 / 等待角色` 已经在卡片里显示为 `已处理` 或 `已取消`，后续 stale runtime snapshot 不会再把它降级回 `待处理`。AI Chat 会保留终态和处理/取消时间，避免用户看到同一个控制请求一会儿完成、一会儿又像没处理过。这个只是 reader control 终态保护，不是 provider stream 原地续传。
- 补充：如果同一个 child run 已经显示 `重新生成角色` 已处理，后续 stale runtime snapshot 又带回旧的 `发送输入` 待处理记录，AI Chat 会继续保留已处理的重试状态，不会把旧输入重新显示成当前待处理操作。这样用户不会在当前卡片里看到“重试已完成”和“旧输入仍待处理”互相打架；这仍只是当前卡片 reader-control 终态保护，不代表完整 `sendInput/resumeAgent/retry` 协作协议或旧 provider stream 原地续传。
- 补充：如果同一个 child run 已经通过 `重新生成角色` 产生了新的角色结果，后续 stale runtime snapshot 只带回旧的 `角色生成失败` 状态和重试按钮时，AI Chat 会保留已处理的重试记录和 retry 后的角色结果，并隐藏过期重试按钮。这样用户不会看到刚重试成功的角色又被旧失败状态盖掉；这仍只是当前卡片状态合并保真，不代表完整失败恢复协议或旧 provider stream 原地续传。
- 补充：`等待角色` 也纳入同一类重复按钮收口：如果同一 child run 已经显示 `等待角色 / wait-agent` 待处理，角色状态块会移除重复 `等待角色` 按钮，但仍保留 `停止角色`。这避免用户把等待动作重复点成多条记录；`wait_request` 仍只是刷新/等待痕迹，不进入 runtime pending control 队列，也不是 provider stream 阻塞等待。
- 补充：如果用户已经在当前 AI Chat 卡片里点过 `等待角色`，随后同一个 active scoped runtime 自然完成该角色，新的 runtime snapshot 合并进卡片时会保留这条等待记录并显示为 `已处理` 和 `处理时间`，不会让等待请求消失，也不会继续显示 `待处理`。这只是当前卡片的等待状态收口；`wait_request` 仍不进入 runtime pending control 队列，也不是 provider stream 阻塞等待或旧 stream 原地续传。
- 补充：如果同一个 child run 已经完成过一次等待并被标为 `已处理`，随后该角色因为重新生成或重启又回到 `running`，用户再次点击 `等待角色` 会记录新的 `待处理` 等待；同一次 running 中已有待处理等待时仍不会重复追加。这样失败重跑复用同一角色 run id 时，旧等待不会挡住新的等待动作；这仍不是 provider stream 阻塞等待。
- 补充：如果 Seminar 角色的 agent stream 或普通模型回复只返回空白 `responseText`，或者 agent stream 只有工具时间线 `<tool-step .../>`、没有最终 `<reply>`/可解析 role JSON，AI Chat 不会把它当成有效角色发言写进研讨结果。该角色输出会在 executor 解析层被判为格式错误，再由 runtime 的失败/重试路径承接，避免用户看到一条“工具调用完成了但角色没有内容”的假完成记录。这只是角色输出 schema 和 parser bridge 严格性收口，不是完整 provider 多轮 JSON/tool loop。
- 补充：如果 Seminar 角色的 agent stream 已经输出最终 `<reply>`，后续 provider/runner 又补发普通尾随文本，AI Chat 会继续使用先前的最终 reply JSON，不会让尾随文本覆盖角色回复并把成功回合误变成解析失败。这个只是 agent stream parser bridge 的稳定性收口，不是完整 provider 多轮 JSON/tool loop。
- 补充：Director `waiting_input` event 现在也会带本场可回应角色 ids；历史恢复成 `messageParts.reader_composer` 时，会同时恢复 `可回应角色`、默认角色、当前角色和默认 `ask-role` 动作。这个只是只读历史 replay 的信息补齐；同 session active runtime 仍使用真实 `读者参与` composer；close/wait/send/resume 的可点击首片已陆续接入，但完整 `sendInput/resumeAgent` 协作协议、真实 provider stream 中断和角色自由工具调用仍未完成。
- 补充：Seminar 角色状态现在会把该角色 profile 允许的只读工具恢复并显示在 AI Chat 原生 `角色状态` 块里，例如 `允许工具 / Allowed tools` 下的 `semantic_search_current_book`、`notes_search`、`memory_search` 和 `concept_graph_search`。全局 Seminar settings 与 AI Chat ready 卡内 `本次只读工具` 都已能选择 `memory_search` 和 `concept_graph_search`；这些选择会作为本场 role profile 的受控只读工具进入启动 prompt，并且 `concept_graph_search` 已注册为真实只读 AI 工具，可被生产 role agent-stream 工具集合构建出来；它只搜索本地图谱节点/关系并只返回带可追溯 `SourceRef` 的结果。当前仍只是受控工具权限可见性、记忆搜索工具和图谱搜索工具开放，不代表角色已能自由发起完整多轮工具调用 loop，也不恢复旧独立页面或 provider stream 原地续传。
- 补充：Seminar 角色工具矩阵现在已明确排除递归 `spawn_sub_agent`。也就是说普通 `spawn_sub_agent` 工具仍作为 E06/sub-agent 底座存在，但 AI 研讨会角色本身不会再把 `spawn_sub_agent` 暴露为可选/可运行工具；Seminar 角色只允许受控、非递归、非联网、无需审批的只读工具进入本场工具集合。这个边界是为了避免“研讨会角色再开子代理”的套娃心智，不代表普通 sub-agent 能力被删除，也不代表完整自由工具调用 loop 已完成。
- 补充：当角色真正拿到自己可见且白名单允许的 traceable evidence 时，runtime 现在会把这次角色级检索写成该角色 child run 下的原生 `tool_call`。历史恢复后用户能在同一张 AI Chat `研讨流` 里看到某个角色对应的工具调用、命中数、运行追踪和关联证据；如果某个 allowed tool 没有命中 evidence，不会伪造成已调用。这个仍只是角色级工具调用痕迹首片，不是 LLM 自主决定何时查工具的完整多轮 loop。
- 补充：普通 `spawn_sub_agent` 的真实工具调用现在也会进入 agent graph：子 agent 在实际 `streamAgent` loop 里发起工具调用时，会记录 `running / completed / errored` lifecycle，并由 `spawn_sub_agent` 写成 child run 下的 `tool_call` event。这个能力目前主要是 P1-S7/E06 底座，帮助后续把 Seminar 角色迁到同一套 sub-agent adapter；当前用户在 AI Seminar 中看到的仍是角色级 evidence/tool-call 痕迹，不代表研讨角色已经能像完整 subagent 一样自主多轮选择和等待工具。
- 补充：Seminar runtime 现在也能接收角色 executor 或未来 sub-agent adapter 发出的真实工具事件，并把这些事件写到当前角色 child run 下，而不是落到父级 evidence broker 或另起一条 run。默认 `AiSeminarModelRoleExecutor` 也已有受控 agent-stream 首片：当角色 profile 明确允许只读工具、生产 provider 能构造 Seminar 权限矩阵下的工具集合时，该角色会走当前模型 + `streamAgent`，并把真实工具事件交回 role observer。`streamAgent` 工具时间线里的最终 `<reply text_b64='...'>` 现在也能被解包成 Seminar JSON，继续进入原有 role/evidence 校验。当前仍不是完整自由多轮工具循环，因为真实 provider 多轮 tool loop、工具等待/取消/继续 UI 和更多 live streaming 组件收口还没完成。
- 补充：受控 role agent stream 里的 `<tool-step ...>` 工具时间线现在会进入同一套 `AgentToolCallEvent`，再恢复成 AI Chat 原生 `tool_call`。`LangchainRunner` 生成的 `<tool-step>` 会带 `call_id`，所以工具 runner 自身 observer 和时间线 parser 会指向同一条工具调用；role executor 也会按 `toolId + callId/fallback-input-id + status` 去重，避免同一工具调用因为 observer 和 timeline 两条来源重复刷新。用户在原生 `研讨流` 看到的是同一工具调用的 running/completed/errored 收口，而不是内部标签文本或重复工具块。当前仍不是完整自由多轮工具 loop 或工具等待/取消/继续 UI。
- 补充：受控 role agent stream 的真实工具事件现在还有最后一道本场角色 allowlist 与场景矩阵防线。executor 转发 `<tool-step ...>` 或 adapter 主动发出的 `AgentToolCallEvent` 前会按该角色 `roleProfile.allowedToolIds` 和当前上下文过滤，runtime 写入 child run graph 前也会再次过滤；未授权、写入型、本角色没有勾选的工具，以及带 `bookId` 阅读研讨里的 `semantic_search_library` 这类 library fallback 工具，不会显示成 AI Chat `研讨流` 里的真实角色工具调用。原生 `角色状态` 块里的 `允许工具` 和从 evidence bundle 反推的角色级 `tool_call` 也会按同一规则显示，避免用户在当前书研讨里误以为角色可以调用全库 fallback 搜索；当前卡片从 live evidence bundle 反推父级证据调用时，也只显示本场 session scopes 已启用的证据工具。历史恢复出来的 role child `messageParts.tool_call` 和 legacy `toolCalls` 也会在默认 `研讨流` 与 `调用` 子视图中套用同一规则，避免重载历史后又把全库 fallback 显示成角色工具调用。本机恢复或当前卡片 snapshot 生成路径里的 `roleAgentToolCallEvents` 也会在进入 `messageParts` 前套用这道 UI 防线；合法 `notes_search` 等当前矩阵允许的只读工具仍然显示。最新补充后，历史恢复出来的父级 evidence broker `messageParts.tool_call` 和 legacy `toolCalls` 也会按本场 `evidenceScopeIds` 过滤；只启用当前书证据的历史研讨不会再把未启用的全库检索显示成父级证据调用。无当前书上下文时才走 Seminar library fallback 矩阵。这个是治理边界收口，不代表角色可以任意调用工具。
- 补充：运行中的当前 AI Chat 卡片也会显示 active role 的角色级 `tool_call`。例如批判者正在输出 partial 时，如果它的白名单允许 `semantic_search_current_book` 且本轮确实有书内 evidence，卡片的原生 `研讨流` 会出现带该角色 运行追踪 的工具调用和关联证据；`notes_search` 这类没有命中证据的 allowed tool 不会被显示成已调用。用户不需要等重载历史才能看见角色使用了哪类证据工具。
- 补充：如果角色 executor 或受控 sub-agent adapter 在运行中真实发出 `AgentToolCallEvent`，当前 AI Chat 卡片现在也会直接显示这条真实角色工具调用。例如 evidence bundle 只有书内证据，但角色 stream 真实调用了 `notes_search` 时，原生 `研讨流` 会显示 `笔记搜索`、查询、调用状态、工具输出、运行追踪和父运行；这类真实 stream 工具调用会优先于从 evidence bundle 反推的工具痕迹。当前仍只是 live tool event 可见化首片，还不是完整自由多轮工具 loop、统一 tool-call/thinking 组件或旧 provider stream 原地续传。
- 补充：本机恢复出的真实角色工具调用现在也会按最新 lifecycle 收口。若恢复快照里同一 `notes_search` 同时残留 `running` 和后续 `completed/errored` 事件，AI Chat `研讨流` 只显示最新的完成或失败状态，不再同时显示过期 `调用中`。这让恢复后的工具调用更接近普通 AI Chat 工具块的原地更新体验，但仍不是旧 provider stream 原地续传。
- 补充：重新加载历史 `AI 研讨会` 卡片时，如果旧 snapshot 里同一工具调用已经是 `notFound/not_found/not-found` 终态，graph replay 后续只补进过期 `running/pending`，AI Chat 会保留终态并显示 `调用未找到`，不会降级回 `调用中`；如果这条工具调用带详情文本，也会显示为 `未找到原因`，而不是普通 `工具输出`。同样，`interrupted/shutdown/cancelled` 工具调用会显示为 `已中断 / 已停止 / 已取消`，详情文本会显示为 `中断原因 / 停止原因 / 取消原因`。这只是缺失、中断、停止和取消工具调用状态的历史合并和异常详情标签保护，不代表旧 provider stream 原地续传。
- 补充：如果 provider 或工具 adapter 没有返回 `callId`，AI Chat Seminar 和普通 sub-agent 的工具调用现在会用工具名加输入内容生成稳定 event id。这样同一角色连续两次调用同一个搜索工具但查询不同，不会在原生 `研讨流` 或历史 graph replay 里互相覆盖；同一次调用的 running/completed/errored 生命周期仍会收口到同一条工具块。当前补的是工具调用身份稳定性，不代表角色已经完成完整自由多轮工具 loop。
- 补充：真实角色工具调用的 `running` 状态现在也能在工具阻塞期间先进入当前 AI Chat 卡片。也就是说角色 stream 还没吐出下一段文本、工具也还没返回时，用户已经能在原生 `研讨流` 看到该角色的工具块和 `调用中`；工具完成或失败后再用同一 role child run 收口到完成/失败状态。这个补的是运行中 lifecycle 可见性，不代表已经完成完整自由多轮工具 loop、工具等待/取消/继续 UI 或旧 provider stream 原地续传。
- 补充：真实 live role agent 的 running 工具调用现在也会自动带 `wait-tool-call / cancel-tool-call` actionIds。用户进入当前卡的 `调用 / 工具调用详情` 后，会看到 `可用控制`、`等待工具调用` 和 `取消工具调用` 可点击入口；工具 completed 或 errored 后不会继续保留这些 actionIds，避免终态假按钮。这是把真实 role agent stream 事件接近普通 AI Chat 工具块的一片，仍不是 provider 级单工具硬中断或完整自由多轮工具 loop。
- 补充：运行中的角色级工具调用如果带 `cancel-tool-call`，现在会在 AI Chat `调用 / 工具调用详情` 中显示为可点击的 `取消工具调用`。用户点击后不会打开旧面板，而是在当前卡内把同一条 graph `tool_call` 收口为 `已停止`，并关闭所属 child role run；如果这正是 active scoped runtime 的当前角色，还会先取消当前 runtime。`wait-tool-call` 后续已从当时的卡内刷新控制升级为 graph-backed waitRequest 记录，当前卡可显示 pending/completed 工具等待。这个首片让工具调用控制开始接近普通 AI Chat 原生工具块，但仍不是 provider 级单个工具请求硬中断，也不是完整自由多轮工具 loop。
- 补充：已完成、已失败、已停止、已中断或已取消的历史工具调用即使残留 `wait-tool-call / cancel-tool-call` actionIds，也不会再显示成可点击按钮。AI Chat `调用 / 工具调用详情` 会把这类只读记录归到 `历史控制` 下，保留 `等待工具调用`、`取消工具调用` 作为历史 metadata；只有 running/pending/pendingInit 且能定位到稳定 toolCallId 或 agentRunId 的工具调用才显示 `可用控制` 并允许点击等待或取消。这个补的是终态假按钮和误导标题收口，避免用户对已经完成的工具调用执行无意义等待；仍不是 provider stream 阻塞等待或完整 tool wait/cancel 执行器。
- 补充：角色/Director 控制也采用同样的可执行/历史区分。运行中或等待输入的角色状态会显示 `可用控制`，并允许等待、停止、发送输入、继续或重试；但如果历史卡里一个已完成、已停止或未找到的角色仍残留旧 `wait-agent / close-agent` actionIds，AI Chat 只会在 `历史控制` 下显示 `等待角色 / 停止角色` 只读 chip，不会出现可点击按钮。整场 failed 的 `重新生成角色` 仍保留为可点击控制。这个补的是状态恢复后的假按钮收口，不代表真实 provider stream 中断或完整 `sendInput/resumeAgent/retry` 协作协议。
- 补充：受控 role agent stream 的工具时间线不会再覆盖已经收到的最终角色回复。如果 provider 先返回 `<reply text_b64='...'>`，随后又补发尾随 `<tool-step .../>`，AI Chat 仍会把工具步骤显示为 `tool_call`，但角色完成解析会继续使用最后一个有效 reply JSON，避免把内部工具标记当成角色正文或导致本轮完成失败。当前仍不是完整自由多轮工具 loop，也不恢复旧 provider stream 原地续传。
- 补充：受控 role agent stream 的 `<think>...</think>` 内部 thinking 标签也不会再作为角色正文显示。thinking-only chunk 会被拦在内部 timeline 层，带最终 reply 的 chunk 仍只显示干净的角色回答文本；这能减少用户在 AI Chat `研讨流` 中看到 XML-like 内部标记的割裂感。当前仍不是完整 provider reasoning stream，也不是完整 thinking/tool-call 统一组件。
- 补充：如果受控 role agent stream 输出了可展示的 thinking summary，AI Chat 当前卡片现在会把它显示为原生 `思考` 块，而不是丢掉或混进角色正文。该 thinking summary 会写在同一角色 child run 下，本机恢复时也能保留。这里展示的是 runner/provider 给出的可解释摘要，不是完整 chain-of-thought；完整 thinking/tool-call 统一组件和自由多轮工具调用 loop 仍未完成。
- 补充：当同一角色已经有 streamed thinking summary 时，当前 AI Chat 卡片会优先显示这条真实摘要，不再同时显示通用的 `正在准备基于证据发言`。如果还没有 streamed thinking，通用准备状态仍会显示，避免角色开始后卡片空白等待。
- 补充：重新加载历史 `AI 研讨会` 卡片时，graph replay 也会沿用同样的优先级：同一角色 run 有 streamed thinking summary 时，只恢复真实摘要，不再额外恢复通用 start thinking；如果旧历史 snapshot 里已经保存过通用 `thinking:start`，graph replay 后续补进同一角色的 `thinking:stream:0` 时，provider 合并层也会移除旧通用 thinking。没有 streamed thinking 的角色仍保留通用准备状态。
- 补充：本机恢复出的角色 thinking 现在也会沿用这套优先级。若 scoped runtime 恢复快照里同时残留 `thinking:start` 和 `thinking:stream:0`，当前 AI Chat `研讨流` 只显示 streamed thinking 摘要，不再双显泛化准备状态和具体思考摘要。这个补的是本机恢复一致性，不是完整 provider reasoning stream。
- 补充：当前 AI Chat 卡片刚完成研讨并回写 snapshot 时，也会保留 completed 角色自己的 `tool_call`，与该角色的正式发言出现在同一条原生 `研讨流` 中。用户能在完成态直接看见某个角色用了哪类受控只读证据工具、命中多少条证据和对应 运行追踪；没有命中 evidence 的 allowed tool 仍不会伪造成已调用。这个仍是角色级工具调用痕迹可见化，不代表完整自主工具调用 loop。
- 补充：历史卡或 graph replay 恢复出的 `tool_call` 如果带有工具输出或失败原因，默认 `研讨流` 和 `调用` 子视图现在都会显示同一段 `工具输出 / Tool output` 文本。用户切到深看调用详情时不会丢失工具返回说明；当前仍只是 tool-call detail 展示补齐，不代表完整 streaming 工具调用组件。
- 补充：历史 `AI 研讨会` 卡片中的 `发送输入 / 继续角色 / 重新生成角色` reader control，如果已经被同 session active runtime 实际消费，恢复成原生 `研讨流` 时会显示 `已处理` 和 `处理时间`；如果还没有被消费，则继续显示 `待处理` 且不显示处理时间。当前卡片中点击 `发送输入` 并被 active runtime 成功处理后，也会直接在同一张卡显示 `已处理` 与处理时间，不必等到重载历史后才看见。这样用户能看出某条控制请求是“已执行过”还是“只是等待恢复”。当前仍不是完整 `sendInput/resumeAgent/retry` 协作协议，也不是 provider stream 阻塞等待或旧 stream 原地续传。
- 补充：如果 Seminar 角色 partial 已经作为 `AgentRunGraphStore` 的同 session child `message_delta` event 持久化，重新加载 AI Chat 历史时也会把这些 persisted delta 自动补进该 `AI 研讨会` 卡的 `messageParts.role_partial`，历史卡可恢复 `角色发言生成中` 和 partial 文本。persisted parent Director events 与 child events 已能合并恢复为原生 message parts：历史卡能显示 `角色正在生成`、完成输出、失败状态，并能把父 Director completed status 恢复为 `director_state(label=end)`、父 Director result 恢复为 `messageParts.synthesis`；persisted `tool_call` event 也已能保存 agentRunId、parentRunId、toolId、query、resultCount、roleIds、evidenceRefs 和 SourceRef，并恢复为 `messageParts.tool_call`；runtime evidence broker 已开始把 traceable evidence bundle 写成 parent Seminar run 的 `tool_call` event；Seminar 父 Director run 已开始作为可查询 agent run 写入 graph，能记录 running、completed/needsEvidence、cancelled/interrupted、fetch failed/errored 和证据缺口 interrupted lifecycle。这仍不代表完整 `sendInput/resumeAgent` 协作协议、真实 provider stream 中断/阻塞等待、角色自由工具调用或完整 subagent 控制 UI 已完成。
- 补充：如果 graph replay 的 `tool_call` event 已带可追踪 evidenceRefs，即使旧历史卡的 `snapshot.evidence` 为空，AI Chat 也会额外恢复 `messageParts.evidence` 证据块。这样用户在历史 `研讨流` 里既能看到工具调用，也能看到独立 `证据快照`，并继续打开可用 SourceRef。
- 补充：如果同一个 Seminar tool run 在 agent graph 中先保存了 `running` 工具调用，后续又保存了同一 run/tool/query 的 completed 或 errored 工具调用，历史恢复进入 `messageParts.tool_call` 前会只保留最新工具事件。即使旧历史卡 snapshot 里已经保存过同一 `agentRunId/toolId/query` 的 running 工具块、而 graph replay 补进的新工具块 event id 不同，AI Chat 也会用 graph 最新状态替换旧 snapshot 工具块；旧 snapshot 工具块没有 `agentRunId` 但保留同一 `parentRunId/toolId/query` 时，也会被带 trace 的 graph 工具块晋级替换。这样用户不会在同一张 `研讨流` 里同时看到同一个证据工具“调用中”和“调用完成/调用失败”，也能在旧历史恢复后看到对应的 运行追踪；不同工具、不同查询或不同 run 的多次调用仍会分别显示。
- 补充：如果历史 graph replay 收到同一个 `eventId` 的多份事件，例如同一个角色工具调用先是 `running`、后面更新为 `completed` 或 `errored`，AI Chat 进入原生 `研讨流` 前会只保留最新事件。这样用户重新打开会话时不会看到同一个底层事件重复成两条工具调用或状态块；不同 event id 的真实多次调用仍会保留。这只是本机历史恢复一致性收口，不是旧 provider stream 原地续传，也不是跨设备自动合并。
- 补充：如果历史卡已经保存了同一个证据工具的 completed、errored、interrupted、shutdown、not_found 或 cancelled 终态工具块，而 graph replay 只补进同源 running/pending 工具事件，AI Chat 会保留历史终态结果，不会把已经可见的工具输出或失败原因降级回 `调用中`。
- 补充：同一个 Seminar child run 如果历史 graph 里先有 `running/waiting/interrupted` 这类临时状态，后面又已经有 `result` 或 `error`，AI Chat 历史恢复会收口掉前面的临时状态，只显示完成的角色回应或失败状态；如果旧历史卡 snapshot 本身已经保存了 `role-running`，后续 graph replay 补进同一 child run 的 terminal part 时也会按 `agentRunId` 替换旧状态。这样用户不会在同一张历史卡里同时看到“角色正在运行”和“角色已完成/已失败”，也不会误点过期的 `等待角色 / 停止角色` 控制。
- 补充：如果旧历史卡 snapshot 里已经保存了某个角色的 `role_partial`，但同一 child run 后续已经从 agent graph 回放出 completed result 或 error，AI Chat 历史恢复会清理这条过期 partial，只显示完成后的角色发言或失败状态。即使 partial 是从 graph `message_delta` 直接回放出来，或者旧 snapshot 没有显式 `agentRunId`、只在 id 中保留 `:delta:` marker，只要同一 run 后面已经有 result/error terminal event，也会在进入 `messageParts` 前被过滤。这样用户不会在同一张 `研讨流` 里同时看到“角色发言生成中”和该角色的正式结果或失败状态。
- 补充：如果旧历史卡 snapshot 已经保存了没有 `运行追踪` 的角色发言，而 graph replay 后续补进同一角色、同一文本、带 `agentRunId/parentRunId` 的角色结果，AI Chat 历史恢复会保留带 trace 的版本并移除旧重复发言。这样用户不会在 `研讨流` 里看到同一角色回答重复两次，同时还能看到该回答对应的 child agent run。
- 补充：当前 scoped runtime 刚完成并回写同一张 AI Chat Seminar 卡片时，completed `role_turn` 也会直接带 `agentRunId` 和 `parentRunId`，因此展开完整 `研讨流` 或查看非紧凑原生流时能看到角色发言对应的 child agent run，不需要等到重新加载历史后才获得 trace。默认紧凑概览会隐藏详细 trace 行，避免把 `保存知识卡`、`加入复习` 和 `加入我的图谱` 等沉淀动作推到输入框下方；这个只是当前 snapshot 的角色发言身份和布局边界补齐，不代表旧 provider stream 可以原地续传。
- 补充：当前 scoped runtime 刚完成并回写同一张 AI Chat Seminar 卡片时，completed `synthesis` 也会直接带本场 Director run 的 `agentRunId=<seminarSessionId>`，和历史 graph replay 恢复出的 synthesis trace 对齐。展开完整 `研讨流` 或查看非紧凑原生流时能看到总结属于哪一场父 Director run；默认紧凑概览仍隐藏详细 trace 行，保证 `保存知识卡`、`加入复习` 和 `加入我的图谱` 这些沉淀动作保持可触达。
- 补充：当前 scoped runtime 刚完成并回写同一张 AI Chat Seminar 卡片时，可追踪 synthesis 的沉淀建议现在也会写入 `messageParts.type=artifact_actions`。默认 `研讨流` 会显示 `沉淀动作` 原生块，提示可保存为知识卡、加入复习、加入我的图谱，异常时送审，并携带 `save-knowledge-card / edit-knowledge-card / add-spaced-review / add-concept-graph / send-to-review / ignore-artifact-actions` action ids；紧凑概览会优先保留该块，避免用户只在卡片尾部才看到学习闭环。保存知识卡、加入复习或加入我的图谱后，该原生块会分别回写为 `knowledge-card-saved / undo-knowledge-card`、`spaced-review-added / undo-spaced-review`、`concept-graph-added / undo-concept-graph` 状态，并显示 `知识卡已保存 / 复习已加入 / 图谱已加入`，撤销后恢复对应保存/加入动作；点击 `忽略` 后会回写为 `artifact-actions-ignored / restore-artifact-actions` 并显示 `沉淀建议已忽略`，`恢复操作` 后回到普通沉淀动作；点击 `异常送审` 后会回写为 `sent-to-review`、显示 `异常已送审`，并隐藏重复送审按钮；provider snapshot 更新会把 `knowledge-card-saved / spaced-review-added / concept-graph-added / artifact-actions-ignored / sent-to-review` 完成态写入可回放 `artifact_action` execution event，历史加载时可恢复为原生 `artifact_actions` part，并替换 stale available 动作；撤销知识卡、撤销复习、撤销图谱和恢复沉淀动作会额外写入 `undo-* / restore-artifact-actions` execution marker，历史加载时用这些 marker 替换 stale saved/added/ignored 状态并恢复当前可用动作；历史沉淀动作块会显示处理状态、执行时间、运行追踪 / 父运行 和紧凑关联证据，方便用户区分哪些动作已经实际执行过。后续 runtime snapshot 同步如果再次生成 `send-to-review`，provider 合并层会继续保留已送审终态。保存、编辑、撤销、复习、图谱、忽略和异常送审的点击执行仍沿用同卡现有按钮逻辑；当前只是 artifact action execution event 和审计可见性首片，不是完整 artifact action 审计详情页，也不是完整 AI reviewer / Review Inbox 自动审批流程。
- 补充：历史 graph replay 恢复出的 completed 角色发言和 Director 总结现在会继续保留 result event 中的 `evidenceRefs`。因此用户在展开完整 `研讨流` 或查看非紧凑原生流时，不只看到角色/总结文本和 运行追踪，也能继续看到关联证据并打开来源；这只是 result 事件证据链补齐，不代表旧 provider stream 可以原地续传。
- 补充：如果当前 scoped runtime 已经把 completed 角色发言写进同一张 AI Chat Seminar 卡片，后续历史恢复又从 agent graph 回放出同一个 child run 的 result event，历史卡会保留 graph result 版本并移除旧 live snapshot 版本。这样同一个角色回答不会在 `研讨流` 中重复出现，且 graph result 里的稳定 event id、父运行 和 evidenceRefs 会继续用于证据展示与来源打开；这仍只是历史 replay 合并收口，不是旧 provider stream 原地续传。
- 补充：completed 角色发言已经开始迁入原生消息结构：完成后的 snapshot 会写入 `messageParts` 中的 `role_turn`，包含角色身份、发言文本和本轮 evidence refs。历史卡现在即使只有 `role_turn` parts、没有旧 `roleSummaries`，也能显示 `研讨时间线` 和 `本轮证据`。后续切片已补上 completed 证据调用 `messageParts.tool_call`、证据快照 `messageParts.evidence`、总结 `messageParts.synthesis`、分歧 `messageParts.disagreement`、分歧反驳回合 `messageParts.disagreement_rebuttal`、读者回合 `messageParts.reader_turn`、askUser cue `messageParts.director_state` 和只读可参与状态 `messageParts.reader_composer` 的首片；`reader_composer` 当前已能恢复可用动作、可回应角色、默认动作、默认角色、当前动作、当前角色、草稿回复和独立动作选择。仍未完成的是完整异常详情、完整 contradiction scanner/tab、旧 stream 原地续传和AI Chat 同源详情状态。
- 补充：同一张 completed AI Chat Seminar 历史卡现在可以保留多次分歧反驳回合。用户连续围绕不同分歧点击 `分歧继续讨论` 后，snapshot 会从角色 follow-up turn 的 `Reader intervention` prompt 恢复多条 `messageParts.disagreement_rebuttal`，在 `分歧` 子视图显示每次反驳的目标分歧、回应角色、回应正文和 evidence 引用，而不是只显示最后一次分歧插话。
- 补充：completed 分歧现在还会写入 `messageParts.type=contradiction_scan` 第一片。历史卡即使只有 contradiction-scan parts、没有 legacy `disagreementDetails`，也能在 `分歧` 子视图显示 `分歧扫描`、关联角色和关联证据；这仍只是从已有结构化分歧派生的只读扫描结果，不是完整 contradiction gap scanner、多因素优先级排序或多分歧自动反驳策略。
- 补充：contradiction scan 的概览、下一步建议、优先处理队列、证据缺口提示、gap-first 展示和多缺口汇总第一片已接入。历史卡里的 scan part 如果标记 `label=evidence-gap`，或 completed 分歧没有可追踪 evidence refs，`分歧扫描` tile 会显示 `扫描结论 -> 证据缺口` 和 `缺少可追踪证据`；带 `agentRunId/parentRunId` 的基础分歧、scan 和分歧反驳回合会显示 `运行追踪 / 父运行`；多条 scan 混排时会把证据缺口排在普通分歧前面；同一张卡有两条以上 evidence-gap scan 时会显示 `证据缺口汇总` 和缺口数量；逐条 scan 前会显示 `分歧扫描概览`，统计总扫描数、证据缺口数和已有证据分歧数，并用 `下一步建议` 提示先补证据、再让角色反驳已有证据分歧；`优先处理` 队列会按 `补证据` 分歧优先、已有证据 `反驳` 分歧随后列出具体 scan 文本，避免用户把无证据分歧误看成已有证据支持。同 session active runtime 进入 `refreshEvidence` 时，旧 scan 队列不会被 Director state 覆盖，evidence-gap 优先项可在卡内直接触发补证据；同 session active runtime 下，已有证据 `反驳` 优先项也可在卡内直接触发 `askRole`，默认让 critical 围绕该分歧追加反驳，并写回 `messageParts.disagreement_rebuttal`。完整自动反驳策略仍未完成。
- 补充：Director `refreshEvidence` cue 现在也会写入 `messageParts.type=director_state` 第一片。证据为空或不可追踪导致 runtime 进入 `needsEvidence` 时，历史卡可恢复 `主持人下一步`、`主持人准备重新找证据` 和证据刷新原因，不需要打开旧嵌入式研讨面板才知道主持人为什么停住。
- 补充：用户在 AI Chat 原生 `读者参与` composer 中选择 `整理总结` 并提交后，同一张任务卡会先写回 `messageParts.type=director_state`、`label=synthesize`，显示 `主持人准备整理总结` 和用户的整理要求；Director 本地收束完成后再写回 `label=end` 和 synthesis 文本，历史卡可显示 `主持人已完成本轮研讨` 和本轮总结。这是用户触发整理总结后的 pre-execute cue 与 end cue 验收，不代表完整 Director 调度器已完成。
- completed AI Chat Seminar 历史卡已有低负担知识保存入口：点击 `保存知识卡` 会把可追踪综合总结保存为 draft KnowledgeCard，不写 ReviewItem；点击 `编辑后保存` 会先在当前 AI Chat 中弹出知识卡编辑框，让用户修改标题和解释，再保存为同一类 draft KnowledgeCard；保存后同一卡片切换为 `撤销保存`，点击只移除这张 AI draft 卡，已确认用户资产不能被这个撤销入口删除。点击 `加入复习` 会把同一可追踪综合总结作为 due flashcard 直接加入 Spaced Review，不写 ReviewItem；保存后同一卡片切换为 `撤销复习`，只移除尚未复习过的内联 flashcard。点击 `加入我的图谱` 会把同一可追踪综合总结保存为 claim 类型 draft ConceptNode，不写 ReviewItem；保存后同一卡片切换为 `撤销图谱`，只移除这张 AI draft 图谱节点并清理它的 incident relations。点击 `忽略` 会收起本张卡片的沉淀建议，不写任何知识资产或待审项；用户可点 `恢复操作` 重新显示这些按钮。
- explicit `messageParts` 已承载且没有 legacy snapshot 内容的 AI Chat Seminar 历史卡，不再要求多类型或至少两个 part；单个 `seminar_run_setup`、`tool_call`、`reader_turn`、`director_state`、`role-running` status 或 `reader_composer` 也会默认显示为 `研讨流`，并保留本次设置、工具调用、读者回合、主持人状态、角色控制、可回应角色和草稿回复。`seminar_run_setup` part 可恢复为原生 `本次设置` 块，显示问题、角色、证据范围和轮次摘要；ready 卡创建、卡内配置更新和 legacy ready 卡启动后的 runtime snapshot 合并，已开始持久化或派生保留该 setup part，且 setup-only ready 卡仍可继续编辑并点击 `开始研讨`。tool-call-only 历史卡、带 运行追踪 的 tool_call 历史卡、pending evidence tool calls、运行中 completed evidence tool calls 和 live role partial 都不会再默认把用户带到单独 `证据调用` 分类；单一 pending tool-call 流即使合并了 setup part，也会保留多条工具调用；`调用` 子视图只作为深看入口。completed AI Chat Seminar 的同 session active runtime 混合卡，以及没有可用 `messageParts` 的纯 legacy snapshot 历史卡，默认 `全部` 概览也会显示紧凑 `研讨流`：优先展示本次设置、工具调用、证据或读者控制事件、首个/最新角色发言和总结；有隐藏片段时，用户可在同一张卡点击 `展开全部研讨流` 查看完整派生流，再点 `收起研讨流` 回到代表性概览；`调用/证据/角色/分歧/白板/总结/异常` 子视图继续作为按类型查看入口。保存知识卡、加入复习、加入我的图谱、忽略、异常送审和 `打开来源` 等动作仍在当前卡内可点击。这是 setup 持久化/渲染首片和默认概览收敛，不是持久化历史格式迁移，也不是完整 streaming tool-call/thinking 组件或旧 provider stream 续传。
- 补充：当同 session AI Seminar scoped runtime 失败并带错误原因时，当前 AI Chat 卡片会在 `研讨流` 中显示 `研讨运行失败` 和错误文本，并在 `可用控制` 中显示可点击的 `重新生成角色`。点击后会留在当前卡片内调用该 session 的 scoped runtime `retry()`，重跑同一场研讨并刷新结果；这只是 failed Director 的整场 retry，不是精确 child-role retry，也不是旧 provider stream 原地续传。
- 补充：当历史或 graph replay 出来的 Seminar child role 状态是 `agent_status(status=errored)`，或者 child role 的 `error` event 被恢复成 `agent_status(label=role-error)` 时，当前 AI Chat 卡片也会在该角色状态块显示 `重新生成角色`。点击后会先写入同一 session、同一 child run 的 `retry_request` 控制事件，并在同一卡恢复为 `reader_turn(label=retry-agent-control)`；如果同 session active scoped runtime 仍存在，会继续消费这个 retry request，复用当前 evidence/prior turns 重新运行该 child role 并把事件标为已处理。最新补充后，active runtime 消费 retry 时会忽略同一目标角色之前留下的 failed turn，避免“失败记录本身”阻止重新生成；如果同一个失败 child run 还残留更早的 `user_input`，runtime 会优先消费新的 `retry_request`，不会让旧输入覆盖 `重新生成角色`；其它角色的无证据或失败历史仍会按原 gate 拦截。同 session active runtime 消费成功后，当前卡片会把本地 `lastUserIntervention` 生成的 reader turn 也显示为 `重新生成角色 / retry-agent-control`、`已处理` 和处理时间，并保留被重试 child 的 运行追踪 / 父运行，不再退化成普通 `ask-role`。没有 active runtime 的历史卡只显示待处理 retry request，不会假装角色已经重新生成；该待处理 reader_turn 现在会显示 `重新生成角色` 动作标签，用户不需要从 raw retry 文本猜测它是什么意思。这不是旧 LLM/provider stream 原地续传，也不是跨进程自动恢复所有失败角色。
- `Custom skills` 已完成中文适配；中文界面中对应 `自定义技能`，英文界面仍显示 `Custom skills`；AI Chat `+ -> Choose style / 选择风格` 里，自定义 skill 行也可直接点 `Custom skills / 自定义技能` 进入同一个导入/启用/删除页面，且不会改变当前 active skill；普通内置 skill 行可点 `Skill settings / 技能设置` 保存该 skill 的个人提示词补充，不会改变当前 active skill。
- Review Inbox 只有 producer 写入 pending item 后才会显示内容；空 inbox 不代表入口不存在。
- Review Inbox 批量处理同步冲突的入口是 `Approved` 状态 + `Sync conflict` 类型筛选；只对 `canApply=true` 且有可追踪 SourceRef 的安全冲突显示 `Apply Sync conflict`，部分失败后失败项留在 approved 可用 `Retry Sync conflict` 重试。
- `Settings -> AI Index / Library Index` 的书籍行会把基础索引队列的 latest job 贴回到对应书名下方：queued/running/paused/failed/cancelled 都会显示基础索引任务状态、进度和错误摘要；失败或取消时行内 `Continue indexing / 继续索引` 可重试基础索引，且 Vector/ANN/Global 派生层按钮会先隐藏，直到基础索引队列稳定。

## 1. 当前用户可用性

| 能力 | 用户入口 | 当前状态 | 真实边界 |
| --- | --- | --- | --- |
| Review Inbox | `Settings -> AI -> Review inbox`，以及 Settings 顶层知识审核入口。 | 已接入 UI，可展示、批准、忽略、应用 KnowledgeCard、ConceptGraph relation 和 flashcard candidate 类型审批项；每个有证据的待审项会显示证据摘录、来源标题/位置、不可用来源原因和打开来源动作；Settings 顶层 AI 区和 `Settings -> AI` 子页两条路径都有点击级导航证据。 | 只有 producer 写入 `ReviewItemStore` 后，用户才会看到内容；空 inbox 显示空态，不代表入口失败。 |
| 选中文本 -> KnowledgeCard | 阅读页选中文本 -> `知识卡`。 | 本分支已接入低负担保存：选中文本会在当前阅读菜单动作中保存为 draft KnowledgeCard，提示 `Saved as draft knowledge card / 已保存为草稿知识卡`，并保留 book/cfi/sourceTitle/locationLabel/jumpLink SourceRef。 | 普通阅读保存不写 ReviewItem、不进入 Review Inbox、不写长期记忆、不写笔记、不写 spaced review；`SelectionKnowledgeCardProducer` 默认 `createReviewItem:false`，只有显式兼容、异常或低置信 handoff 才用 `createReviewItem:true` 写入 Review。 |
| 图片解析 -> KnowledgeCard | 阅读页点开图片 -> `AI Image Analysis / AI图片解析` -> `Card / 知识卡`。 | 本分支已接入低负担保存：图片解析结果弹层和 ImageViewer 工具栏路径会把解析结果保存为 draft KnowledgeCard，提示 `Saved as draft knowledge card / 已保存为草稿知识卡`，不写 ReviewItem、不进入 Review Inbox。 | 图片本体和 base64 不写入 card payload；SourceRef 使用当前阅读位置的 book/cfi/href 回跳；不写长期记忆、不写笔记、不写 spaced review；`ImageAnalysisKnowledgeCardProducer(createReviewItem:true)` 仍保留旧 Review 兼容路径。 |
| 选中文本 / AI Chat -> AI Seminar | 阅读页选中文本 -> `研讨`，或 AI Chat 左下角 `+` -> `AI 研讨会`；全局默认角色配置在 Settings -> AI -> `研讨会设置`，AI Chat `选择风格` 不再显示 Seminar 行。 | 本分支已接入结构化 runtime：用户可启动 role-by-role Seminar，查看 evidence、角色输出、Shared Whiteboard、synthesis，并在 completed AI Chat 卡片内保存知识卡、加入复习、加入我的图谱，异常时再送入 Review Inbox；阅读页选中文本 `研讨` 会打开阅读页 AI Chat，并在当前会话写入原生 `AI 研讨会` 任务卡，不默认展开旧嵌入式研讨面板，带入选中文段和真实 reader `SourceRef`，不会把 `activeAiSkillId` 改成 `seminar_mode`，也不会覆盖用户当前 `Choose style`，同时会向当前 `conversationV2` 写入同一 `seminarSessionId` 的 `AI 研讨会` 任务卡，保证 App 重启或进程被杀后用户能从 AI Chat 历史重新找到这场讨论；AI Chat 的 Add-to-Chat sheet 显示独立 `AI 研讨会` 卡片，点击后向当前 `conversationV2` 写入原生 `AI 研讨会` 任务卡，带入当前输入框问题，但不默认展开 runtime panel；历史重载后待开始卡可展开 `本次设置`，在卡内编辑本次研讨问题、修改最多讨论轮次、启用/停用角色、编辑启用角色本次 prompt、切换启用角色本次只读工具范围并切换启用角色 current book/library/notes/memory/conceptGraph 证据范围，然后点 `开始研讨`；runtime 完成或刷新后会把证据调用（工具名、查询、结果数量、可见角色、运行追踪和返回证据）、证据快照、角色观点、研讨总结、分歧数和开放问题数写回同一张卡；证据快照、角色本轮证据和分歧关联证据会随 `conversationV2` 保存 SourceRef safe JSON，并在历史卡内显示 `打开来源 / Open source` 跳回原文；如果同 session scoped runtime 从本机 checkpoint 恢复为可续跑 running state，历史卡会直接显示 `可从中断处继续`、`继续研讨` 和 `断点详情`，用户点 `继续研讨` 会在卡片内直接调用同 session scoped runtime 续跑缺失角色，点 `断点详情` 只在当前卡片内展开断点状态、已保存证据、下一步和 provider/model；当该卡片仍对应当前活跃且需要异常处理的 runtime 时，卡片内可先切到 `异常` 子视图查看 `异常处理预览`，再点 `异常送审` 把 synthesis 和候选项送入 pending Review；completed 卡片可在当前 AI Chat 内直接 `保存知识卡`、`编辑后保存`、`加入复习`、`加入我的图谱` 或 `忽略`，对应保存动作都保留 SourceRef evidence，不写 ReviewItem；`忽略` 只收起当前卡片的沉淀建议并可恢复，不写任何资产；旧独立 Seminar runtime page/panel 已删除，不再作为详情、调试或兼容入口；`Choose style / 选择风格` 不再显示 Seminar 行；Seminar settings 已可配置角色显示名、custom prompt、启用状态、会话证据提示和允许的只读工具，disabled role 会从新 session 与 AI Chat Seminar 任务卡 role ids 中跳过，全部关闭时降级为 synthesizer；role profile 会丢弃疑似密钥的 custom prompt，并过滤写工具、联网工具、unknown tool 和递归 `spawn_sub_agent`；阅读页选中文本入口会把真实 reader `SourceRef`、CFI、jump link、snippet 带入 Seminar session，并在 evidence broker 中优先生成 `Reader selection` evidence；AI Chat Seminar 启动前显示 `Provider readiness`，列出当前 provider、model、context/max output、Tools/Vision/Thinking 能力、Streaming 状态未知提示和成本状态；角色完成后优先显示 provider 返回的 `Provider reported usage`，没有 provider usage metadata 时显示 `Local token estimate`、input/output 估算和 `Provider billing may differ` 提示；AI Chat Seminar 配置提供本地 `Role output token budget`、`Run token budget`，当 provider capability cache 带 pricing metadata 时还启用估算 `Run cost cap USD`；Scoped runtime 保存当前本机 `Background job` snapshot 和最近 job 账本并显示当前 job id/status，可在同一书籍/同一入口问题恢复本机保存的 completed/cancelled/failed/interrupted Seminar state，并显示 `Recovered local Seminar state`；如果重启时 running state 已有可追踪 evidence 且 provider/model/pricing 仍匹配当前配置，会复用已保存 evidence，从第一个缺失角色继续；已有 completed role 会跳过不重跑，缺 tokenUsage 的 checkpoint turn 会补本地估算；运行中再次点击会显示 `Queue Seminar`，把新问题加入本机串行队列，页面展示 `Seminar job queue`；当同一恢复快照存在可续跑 active job 和带完整 session 的 queued job 时，queued job 会保持 queued 并在 active 续跑完成后自动启动；`AiSeminarDirectorState` 第一片会随 runtime state 记录轮次、已完成角色、证据账本、白板账本、分歧 id、最后一次用户插话和下一步 intent；completed run 留下 open question 时会标记 `askUser`，留下 disagreement 且仍有轮次预算时会标记 `refreshEvidence`，状态区显示主持人下一步；用户在 `askUser` 中选择“让所选角色回应”会追加目标角色 follow-up turn 并更新 synthesis，选择“重新找证据”会重新调用 evidence broker、重跑角色并更新 synthesis，选择“整理总结”会用现有 evidence 和 turns 执行本地 synthesis 并收束 Director；completed run 完成后会在 synthesis 后显示 `Continue discussion / 继续讨论`，即使没有 open question，也可让用户继续追问某角色、重找证据或再次整理总结，输入仍只写 `lastUserIntervention`；completed run 只留下 disagreement 且仍有 maxRounds 刷新预算时，会自动刷新 evidence、重跑角色；刷新后仍有分歧且预算耗尽时转为 askUser。 | 阅读页优先 current book evidence，且选中文段本身会先作为可跳回原文的 evidence；AI Chat 入口没有 reader anchor 时只带入问题文本和当前阅读书籍上下文，不伪造选区 SourceRef；Settings 独立入口没有 current book 时会走 library fallback。AI Chat 原生任务卡 snapshot、可恢复 checkpoint 提示、卡内直接续跑、卡内异常送审和 completed 卡片内联保存动作已按 `seminarSessionId` 使用 scoped runtime；阅读页/外部入口会写入同 session 任务卡作为恢复锚点；任务卡已有 evidence/role/synthesis 快照和同 session active runtime 的首片异常送审按钮，但还不是完整结构化 chat message part，不支持完整同源详情状态、完整 run-scoped composer 信息架构或每个角色的真实工具调用 loop；不同 scoped runtime 的模型调用仍由本机 coordinator 串行化，不并发外发 Seminar；DirectorState 已能驱动 askRole follow-up、用户触发的 refreshEvidence、completed continuation composer、disagreement 预算内自动 refresh 和 synthesize，但还没有驱动完整多轮分歧检测、结构化 rebuttal turn 或澄清调度；Seminar synthesis 默认不自动应用，只有用户在 completed 卡片显式点击 `保存知识卡`、`编辑后保存`、`加入复习`、`加入我的图谱` 或异常场景下的 `异常送审` 才写对应资产或 Review handoff；点击 `忽略` 不写资产或 Review，只隐藏本卡片沉淀建议，`恢复操作` 会重新显示按钮；旧候选卡和候选 flashcard 仍需用户在 Review Inbox 中批准/应用后才成为长期资产或复习项；provider readiness 只读本地 Provider Center 配置和 capability cache，不记录 API key；provider token usage 只表示 provider/SDK 回传的 token metadata；估算美元成本来自 pricing metadata 与 token usage，不等于真实 provider 发票；缺少 pricing metadata 时继续显示成本未知原因且禁用美元 cap；取消当前 job 只命中当前活跃 job id，取消 queued job 不会误取消当前运行；当前 job 终态后才串行启动下一条 queued job；恢复续跑只信任 traceable evidence checkpoint 和合法 completed role prefix；历史卡 `继续研讨` 会直接续跑缺失角色，`断点详情` 只在卡内展开断点状态且不自动重发模型请求；只有 half-stream partial 时丢弃 partial 并重新生成缺失角色；同一恢复快照里带完整 session 的 queued job 可在 active 完成后启动；checkpoint 无效、evidence 不可追踪、provider 已切换、没有可恢复 active job 或 queued job 缺少 session 时会标记为 interrupted/retryable；它不会继续旧 LLM stream，也不是 OS 后台执行；换书或换选区打开 Seminar 会丢弃旧 runtime/cache，不显示不属于当前入口的旧研讨。 |
| AI Chat 普通解释 -> KnowledgeCard | 阅读页选中文本 -> `AI` -> 等回答完成 -> 回答旁 `知识卡`。 | 本分支已接入低负担保存：回答旁 `知识卡` 默认调用 `AiChatKnowledgeCardProducer(createReviewItem:false)`，把回答保存为 draft KnowledgeCard，提示 `Saved as draft knowledge card / 已保存为草稿知识卡`，不写 ReviewItem、不进入 Review Inbox；streaming 中按钮禁用且不会调用 producer。AI 回答流式文本更新会合并到 160ms UI flush 窗口，阅读页底部 AI 面板隐藏或多 tab 非活动 chat 时降到约 1000ms，重新可见时立即补刷 pending 文本，减少生成中阅读页滚动/翻页重建压力；回答旁显示 `可跳转来源` 或 `已标记不可用` 来源状态，tooltip 解释是否能跳回原文；选中文本 `AI` 入口点击级测试覆盖打开 chat draft 并传入 reader SourceRef；选中文本进入 AI 草稿时会带上精确 reader SourceRef，并随 `conversationV2` 历史持久化；reader-grounded card 会带保守 `conceptRefs`。 | 必须用户显式点击；不会在回答生成时直接写 KnowledgeCard 或 ConceptGraph；如果用户把预填草稿改成不包含原选中文本或 SourceRef snippet 的无关问题，本轮 user node 不保存旧 reader SourceRef；短公共片段只靠碰巧包含不会保留精确 reader grounding；无有效 anchor 的选中文本只打开 AI draft，不伪造 reader grounding；旧 `createReviewItem:true` Review 兼容路径或异常路径在用户 Apply 后，带 `conceptRefs` 的 reader-grounded AI Chat card 才会生成 draft ConceptGraph relation 和 pending relation ReviewItem；纯聊天 card 不生成 `conceptRefs`；没有持久化 reader SourceRef 的旧历史只保留 conversation provenance，不用当前阅读位置伪造 reader grounding；这不是完整真机性能证明，仍需 release/profile gate。 |
| Responses 兼容模型提问 | `Settings -> AI -> Provider Center` 选择 OpenAI Responses 兼容 provider，在详情页 `API 密钥` 区导入或添加本机密钥，并按 provider 配置打开或保留 `Use previous_response_id continuation`。 | 本分支已接入 `previous_response_id` 和 `store` 兼容 fallback：当 Responses provider 返回 HTTP 400 且错误体明确指向 `Unsupported parameter: previous_response_id` 时，当前请求会标记该运行时实例不再发送 `previous_response_id`，并用同一消息/工具输出重建 replay body 重试一次；当第三方网关拒绝 `store` 时，会降级到无 `store`、无 `previous_response_id` 的 replay body；正常 OpenAI Responses provider 仍使用 server-side continuation。Provider Center API key 管理和模型能力面板已完成中文界面适配，并持续提示 API key 只保存在本机。 | 只对明确的 `previous_response_id` 或 `store` unsupported 生效；非相关 HTTP 400 保留原始错误并不重试；fallback 是当前运行时实例内的兼容保护，不是 provider capability schema 的永久迁移；仍需用户在 Provider Center 正确配置 base URL、model、streaming 和 reasoning 选项。 |
| 书库 Hybrid RAG 召回 | AI Chat、Seminar library fallback、agent tool、ConceptGraph 空态或其它调用 `semantic_search_library` 的入口。 | 本分支已把书库 RAG 从“文本没有候选才走向量 fallback”改为“FTS/BM25 精确文本召回 + `AiVectorSearchBackend` 语义召回共同进入候选池”：只要允许 query embedding，向量后端都会参与召回，结果 JSON 会显示 `usedVectorRecall`；FTS 命中时 `usedVectorFallback=false`，但纯语义命中的 chunk 仍可进入 hybrid/MMR/rerank 排序；默认 backend 是 ANN -> native -> exact：Vec1/sqlite-vec function 和 per-provider/model/dim ANN 表存在且完整时优先走 `AiVec1VectorSearchBackend`，只 hydrate ANN winner 正文；Vec1 不可用、ANN 表缺失或 shadow layer 不完整时合并/降级 native SQL seam 和 compact exact backend。 | 当前代码已经有 extension-ready ANN 路径，但还不是已打包的 sqlite-vec/Vec1 发布能力；ConceptGraph 空态和 RAG KnowledgeCard 本地文本入口显式关闭 query embedding、vector fallback 和 rerank，因此不外发正文；正式 evidence 仍必须有 SourceRef 和 chunk snippet；老索引缺 `embedding_blob` 时 exact backend 仍会按命中页批量回查 `embedding_json`。 |
| 当前书语义检索资源保护 | 阅读页搜索、AI Seminar current-book evidence、`semantic_search_current_book` 工具。 | 本分支已把当前书语义搜索接入 book-scoped `AiVectorSearchBackend` 优先召回：先按 `bookId` 调用向量后端；`AiVec1VectorIndexBuilder` 会为 provider/model/dim 建全局 Vec1 ANN 表，并为每本书建 per-book Vec1 sidecar 表，current-book 查询只在 per-book 表存在且 shadow rows 完整时用 ANN；全局 Vec1 ANN 仍不用于 current-book，避免全局 topK 后过滤漏召回；现有 `vector_full_scan` native adapter 也会在 `bookId` 场景跳过，避免扩展内部无预算扫描；后端无结果或不可用时进入 bounded FTS/BM25 候选预筛、compact exact 或预算内分页 fallback。backend winner 进入 current-book 候选池前会剥掉 `text/raw_text/context_text/embedding_json/embedding_blob`，只保留 id、章节和 SourceRef 所需轻量元数据；分页扫描页只取 id、章节、hash、context 和 vector blob/norm，不取 `text/raw_text/embedding_json`；只为 topK 命中回查正文；ANN 与 FTS/BM25 命中同一 chunk 时应用层去重，只保留较高分证据；老索引缺少 blob 时按页批量回查 `embedding_json`；搜索服务全局串行，页内/页末让出 UI isolate，向量扫描 progress 会合并快速页通知并强制保留取消/最终状态，工具 registry 也默认串行该工具；FTS/BM25 继续承担精确文本候选，只扫描候选 vector row；FTS5 不可用、MATCH 失败、无候选、候选过期或后端无结果时，阅读页 fallback 扫描上限为 1024 行，Seminar evidence 和 agent tool fallback 扫描上限为 2048 行；阅读页 stale query 会取消旧 token，目录搜索进度条显示 semantic progress，工具 timeout 会取消底层搜索。 | 这是 OOM/发热/掉帧保护层和 extension-ready per-book ANN 接入 seam，不是完整发布级向量引擎；有完整 per-book Vec1 sidecar、book-scoped exact 后端召回或 FTS 候选时不会完整扫描全书向量；无后端结果、无 FTS 候选、FTS 不可用或候选过期时，用户入口只做预算内分页 fallback，达到上限会返回带 message 的降级结果；移动端 sqlite-vec/Vec1 extension 打包、可恢复 ANN build job 和 provider/model 失效提示仍未产品化。 |
| 旧索引全局层补建 | 批量路径：`Settings -> AI Index / Library Index` -> `全局层索引` -> `补建`；单书路径：同页书籍行 `Global Missing` -> `Build global layer / 补建全局层`；当前书路径：`Settings -> AI -> Concept graph / 概念图谱` 或阅读页选中文本 -> `图谱/Graph` -> 当前书全书图谱为空态 -> `立即生成全局层索引`。 | 本分支已接入旧 chunk-only 索引的全局层补建入口：批量页检查已索引书籍是否缺少 RAPTOR 全局层，显示缺失数量、补建进度、取消按钮和完成/取消/失败提示；AI Index 书籍行在 `Base` 已就绪且 `Global` 缺失时会显示行内 `Build global layer / 补建全局层`，只对该书调用 `AiGlobalIndexBuilder.rebuildBook(bookId:)`，完成后刷新这一行的 readiness 与顶部全局层状态；服务层用已有 chunk rebuild book-level summary、RAPTOR links 和当前 deterministic GraphRAG 派生层，不重新生成 embedding；ConceptGraph 当前书为空态会检查该书 chunk/global-layer 状态，有旧 chunk 索引时可直接补建该书全局层，完成后刷新当前书只读全书派生图谱；取消后未处理的书会继续显示为缺失，用户可再次补建；中文 GraphRAG 派生层已能从纯中文 chunk 中本地抽取常见概念短语，生成带 chunk SourceRef evidence 的节点；关系目前来自同 chunk 共现计数，展示时借用两端节点 SourceRef；没有可抽取节点的中文书，只要 RAPTOR 全局层存在，也不会被反复标记为缺失。 | 这是旧索引升级为可被 RAPTOR/GraphRAG 派生层使用的补建入口，不是 sqlite-vec/ANN；行内按钮只处理单本书全局层，不升级 native vector、不构建 ANN、不重新生成 embedding、不外发正文；当前中文抽取是本地 deterministic 第一片，覆盖常见短语和概念 marker，不等于完整中文实体消歧、跨章节主题聚类或 LLM-backed concept extraction。 |
| 旧索引向量层升级 | 批量路径：`Settings -> AI Index / Library Index` -> `向量索引升级` -> `升级`，再点顶部 `ANN 向量索引` -> `构建`；单书路径：同页书籍行 `Vector Missing` -> `Upgrade vector layer / 升级向量层`，或 `ANN Missing` -> `Build ANN sidecar / 构建 ANN sidecar`。 | 本分支已接入 native vector shadow layer 升级入口：页面检查已索引书籍是否缺少 `ai_vector_index_rows`，显示可升级书籍数、完整准备书籍数、升级进度、取消按钮和完成/取消提示；服务层用已有 `embedding_blob` 或旧 `embedding_json` 生成紧凑 float32 shadow rows，不重新生成 embedding；AI Index 书籍行在 `Base` 已就绪、已有 embedding、全部 stored chunk 都有 embedding 且 `Vector` 缺失时会显示 `Upgrade vector layer / 升级向量层`，只对该书调用 `AiNativeVectorIndexBuilder.backfillBook(db, bookId:)`，完成后刷新这一行、顶部 native vector 状态和 ANN 状态；如果 stored chunk 只有部分已有 embedding、缺少维度元数据或存在混合维度，行内会显示缺失/不一致原因并显示 `Repair base embeddings / 修复基础 embedding`，默认把该书送回基础索引队列；队列执行 `rebuild:false` 时会原地补缺失或错维的 chunk embedding，不继续补 vector/ANN，避免只用部分或不一致 chunk 生成 sidecar；当 `Base` 与 `Vector` 已就绪但 `ANN` 缺失时，行内会显示 `Build ANN sidecar / 构建 ANN sidecar`，只调用 `AiVec1VectorIndexBuilder.rebuildBookSidecarFromNativeRows(db, bookId:)` 为这本书写 per-book Vec1 sidecar，不写全局 ANN 表、不写 `vec1-ann` meta、不重新 embedding；单书 ANN sidecar 构建期间会在同一书籍行显示 group/row 进度，例如 `ANN sidecar progress: 0/2 group(s), 1 row(s) written.`；`AiVec1VectorIndexBuilder` 也能从 shadow rows 按 provider/model/dim 建立全局 Vec1 virtual table，并同步建立 per-book Vec1 sidecar table，写入 `vec1-ann` meta；顶部 `ANN 向量索引` tile 会检查 Vec1/sqlite-vec 加载状态、shadow rows、ANN group/global row 缺口和 per-book sidecar 缺口，并在可用时触发可取消的整库构建；默认向量后端会先尝试 Vec1 ANN，再降级 native SQL seam 与 exact backend；删除书籍时会显式清理该书的 RAPTOR/GraphRAG、native vector shadow、全局 ANN 行、per-book ANN 行和对应 meta。 | 当前不自动打包或加载 Vec1/sqlite-vec 扩展；未加载扩展时页面显示 ANN 暂不可用并保持 fallback；单书向量层升级只复用已有 embedding，不生成新 embedding、不外发正文、不构建 ANN；`Repair base embeddings` 仍复用既有基础索引队列和 provider 配置，队列的非重建执行只补缺失/错维 chunk embedding，不创建新通道，也不是后台可恢复派生层 job；单书 ANN sidecar 构建只复用已有 compact vector rows；真实 package/extension adapter、平台打包、可恢复 build job 和 provider/model 失效仍需独立任务；候选 ANN 后端必须继续通过现有 `AiVectorRecallOverlapGate`，且 book-scoped 对比必须传入同一 `bookId`。 |
| 书籍索引状态 | `Settings -> AI Index / Library Index` 查看书籍列表行；或 `Settings -> AI -> Concept graph / 概念图谱`、阅读页选中文本 -> `图谱/Graph` 查看当前书全书派生图谱。 | 本分支已接入 `Book index readiness / 书籍索引状态` 和 AI Index 行内 `Index layers / 索引层状态`：ConceptGraph 当前书区域会把基础索引、native 向量层、ANN、全局摘要层和图谱层分开显示；AI Index 的每本书行也会在书名下方显示 `Base / Vector / ANN / Global / Graph` 状态，并新增 `Available now / 现在可用` 与 `Next unlock / 下一步解锁` 两行，把状态翻译为当前书问答、原文跳转、语义搜索、大书快速召回、本书地图和导读路径，帮助用户在批量索引页直接判断哪本书缺什么、现在能用什么、补完下一层有什么用。失败的基础索引会显示失败原因；向量层显示 compact vector rows 与 stored chunk / embedding chunk 的完成度；如果 stored chunk 只有部分有 embedding、缺少维度元数据或存在混合维度，行内会显示类似 `1/2 chunk embeddings are available` 的原因，隐藏 vector/ANN 派生层补建按钮，并显示 `Repair base embeddings / 修复基础 embedding` 把该书送回基础索引队列；队列执行 `rebuild:false` 时会原地补缺失或错维的 chunk embedding；ANN 未加载 Vec1/sqlite-vec 时显示暂不可用而不是误报失败；全局层以 RAPTOR nodes 作为存在标记，图谱层可以显示 ready、missing 或无可展示节点；当基础索引已就绪且已有 embedding 但向量层缺失时，书籍行会显示 `Upgrade vector layer / 升级向量层` 行内动作；当基础索引和向量层已就绪且 ANN sidecar 缺失时，书籍行会显示 `Build ANN sidecar / 构建 ANN sidecar` 行内动作，构建期间显示 ANN sidecar group/row 进度；当基础索引已就绪且全局层缺失时，书籍行会显示 `Build global layer / 补建全局层` 行内动作；这三类单书动作失败后，失败原因会保留在同一书籍行，对应按钮切换为 `Retry global layer / Retry vector layer / Retry ANN sidecar`，重试成功后刷新该行状态并清掉失败提示；如果某本书进入 `Expired / 已过期` 列表，行内会提示 provider/model 或索引配置已过期，应先重建基础索引，并隐藏旧层补建按钮。 | 这是诊断和批量补建前的用户提示，不会自动重建全部索引或自动外发正文；单书向量层升级只复用已有 embedding；基础 embedding 修复仍走 Settings AI Index 基础索引队列，用户点击后会按当前 embedding provider 配置原地补齐缺失/错维 chunk；单书 ANN sidecar 只复用已有 compact vector rows；单书全局层补建只复用已有 chunk；失败状态和单书 ANN 进度只保留在当前前台页面，不是后台可恢复 build job；过期行不继续补旧层，基础索引重试仍走 Settings AI Index 队列，整库 ANN 构建仍走顶部 ANN 构建入口。 |
| AI Chat -> Memory 直接记住与异常审核 | AI Chat 回答旁或用户消息旁书签图标 `Memory actions / 记忆操作` -> `Remember this / 记住这条`；异常场景用 `Add to Review inbox / 加入待审核队列`；结束会话时默认 `Smart save / 智能保存`。 | 本分支已接入普通显式记忆的低负担内联保存：`Remember this` 直接写入今日日记 Markdown，并在同一条消息菜单切换为 `Undo memory / 撤销本条记忆`；`Add to review inbox` 仍作为低置信、敏感、冲突或用户想稍后处理的异常 handoff，已有点击级测试覆盖。会话摘要默认不再全部送审，`MemoryWorkflowDailyStrategy.smartDaily` 会用本地候选置信度把高置信内容写入今日日记，低置信内容才进入 Review。 | `Remember this` 会记录 direct_save MemoryCandidate，撤销只移除刚追加的精确 Markdown block；Review apply 才写异常 memory；Dismiss 不写 memory；streaming 中或空回答不会写 memory candidate；智能摘要是本地规则评分，不是 provider 发票或外部 LLM 判断；无书内跳转的 conversation memory 会显示证据摘录和不可跳原因；不写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。 |
| Memory 独立浏览 SourceRef 审计 | 首页底部 `Memory / 记忆` tab 打开 daily/long-term memory 列表，再进入条目详情；该 tab 默认隐藏，可先到 `Settings -> Home navigation / 首页导航` 打开。 | 本分支已接入 `MemoryEntrySourceRefAdapter`、Memory home row source audit chips、Memory detail `SourceRefEvidenceList` 和 `Open source` action；只从已应用 MemoryCandidate 只读投影 SourceRef，按目标文档与条目 body 匹配，long-term `MEMORY.md` 按 H1 分段 body 匹配。 | 匹配只认实际写入 memory 的 `text/displayText`，不能只靠 summary 命中；不往 Markdown memory 写隐藏来源字段；没有 book anchor 的 conversation memory 只显示 unavailable/unresolved；可跳来源只使用合法 `paperreader://reader/open?...`；long-term H1 分段不能被批量删除/打标签，避免误操作整份 `MEMORY.md`；浏览页不创建 KnowledgeCard、ReviewItem、ConceptGraph、SpacedReview、Sync 或 Note。 |
| 旧划线/笔记 SourceRef 审计 | 书籍笔记列表或搜索结果里的笔记条目。 | 本分支已接入 `BookNoteSourceRefAdapter`、`BookNoteTile` source audit、`SourceRefEvidenceList` 和 `PaperReaderSourceJumpAudit`；条目显示 Evidence、可跳转/不可跳状态、来源书名/章节和不可跳原因。 | 有有效 `bookId + cfi` 的条目保持原文跳转；无有效 book anchor 的旧条目点击时显示不可跳原因，不调用阅读页空 CFI 或无效 book anchor 跳转；不写 KnowledgeCard、ReviewItem、Memory、ConceptGraph、SpacedReview 或 Sync。 |
| Custom Skill 导入 | `Settings -> AI -> 自定义技能 / Custom skills` 粘贴 governed JSON -> `导入技能 / Import skill`，再到 `当前技能 / Active Skill` 或 AI Chat `+ -> Choose style / 选择风格` 选择启用后的自定义 skill；在 AI Chat `Choose style` 里可从自定义 skill 行点 `Custom skills / 自定义技能` 回到配置页。 | 本分支已接入导入页面、`CustomSkillStore`、Settings 入口、AI Chat Choose style 自定义 skill 配置入口、中文界面适配、`AiSkillRegistry` 合并、Active Skill picker 点击级选择测试和 LangChain runtime 工具收窄；AI Chat Choose style 列表已改为可滚动，skill 较多时不溢出；普通内置 skill 行也可点 `Skill settings / 技能设置` 保存个人提示词补充。 | 只接受 `CustomSkillContract(schemaVersion=1)`；unsafe JSON 不落库、不激活；禁用 skill 不进入 Active Skill 列表；点击配置入口不改变当前 active skill；普通内置 skill 的个人提示词补充不能覆盖隐私、证据、工具权限和写入确认规则；运行时只保留自定义 skill 声明过、当前 scene 可用、permission matrix 允许的只读工具；custom skill 激活时不加载 MCP 工具。 |
| ConceptGraph / WikiLinks Explorer | `Settings -> AI -> Concept graph / 概念图谱`，或阅读页选中文本 -> `图谱/Graph`。 | 本分支已接入 Explorer、Settings 点击入口、选中文本入口、KnowledgeCard -> draft ConceptGraph producer、Seminar candidate card -> conceptRefs -> KnowledgeCard -> ConceptGraph 候选链路、reader-grounded AI Chat card -> conceptRefs -> KnowledgeCard -> ConceptGraph 候选链路，以及空态 `Create draft candidate` 显性 action：可列出现有概念、按选中文本筛选相关概念、打开 dossier、查看局部节点-连线图、局部图谱摘要、局部路径、draft/formal 状态、evidence 状态和 orphan/broken link；页面顶部和空态文案已改为“AI 草稿在当前页内联预览、创建、编辑、忽略或保存，Review 只处理冲突、低置信或来源断裂”，不再把普通图谱学习动作描述为默认待审。Settings 入口会列出已完成全局层索引的书，用户可直接选择一本书查看只读 `全书自动图谱 / Full-book auto graph`；从阅读页进入时会带入当前 bookId 并直接显示当前书全局层 `全书派生图谱 / Full-book derived graph`，默认展示 `主干图 / Core map`，核心节点按关系强度、证据数量和全书连接度排序，而不是按节点列表顺序截取；用户可点画布节点查看该节点摘要、相邻关系、证据摘录和 `Open source / 打开来源`；用户也可点画布关系边或节点详情中的相邻关系行，查看关系类型、两端节点、confidence、edge evidence 和 `Open source / 打开来源`；也可点击 `加入我的图谱 / Add to my graph`，把有证据的派生节点直接保存为 draft 概念节点，不进入 Review Inbox；保存后同一节点详情会显示 `已在我的图谱 / Already in my graph`，防止重复添加；用户也可点击 `编辑后保存 / Edit and save`，先改节点名称和摘要，再保存为 draft 概念节点；如果已有概念节点，用户可点 `合并 / Merge`，显式选择一个目标节点，把派生 evidence 合并到该目标节点；已保存节点可点击 `Remove from my graph` 在当前页移除 draft 节点，并清理该节点的 incident relations；关系详情可点击 `Add relation to my graph`，把带 evidence 的派生关系和缺失端点保存为 draft 图谱资产，也可点击 `Edit and save` 先改关系标签和类型再保存；如果已有同两端关系，用户可点击 `Merge`，显式选择目标关系并合并 evidence；保存后再次打开同一关系会显示 `Already in my graph` 并禁用重复添加；关系可点击 `Ignore` 在当前页临时隐藏且保留两端概念节点；已保存关系可点击 `Remove from my graph` 在当前页移除 draft 关系；用户还可点击节点级 `忽略 / Ignore`，在当前图谱页临时隐藏这个派生预览节点和相关边；如果当前书已有旧 AI chunk 索引但缺少全局层，空态会显示 `立即生成全局层索引`，补建成功后刷新当前书全书派生图谱；纯中文 chunk 现在可生成常见概念节点和 chunk evidence，关系来自同 chunk 共现计数；空态 `Create draft candidate` 会把带 traceable SourceRef 的 derived RAG/GraphRAG result 直接保存为 draft 图谱节点/关系，并显示 `Added to my graph / 已加入我的图谱`，不再写普通图谱 ReviewItem；空态 `Card / 知识卡` 会把同一类本地 RAG evidence 保存为 draft KnowledgeCard，显示 `Saved as draft knowledge card / 已保存为草稿知识卡`，不再进入 Review Inbox。 | 只有 `applied + traceable + conceptRefs` 的 KnowledgeCard 会生成 draft node/edge 和 pending relation ReviewItem；带 `derivedLayer/derivedSummary + traceable chunk SourceRef` 的 library RAG result 经空态 `Create draft candidate` 会生成 draft node/edge，但不写 ReviewItem；空态 `Card / 知识卡` 只保存 draft KnowledgeCard，不写 ReviewItem、不写图谱、不写 memory/note/spaced review；全书派生图谱只读取 `ai_graph_nodes / ai_graph_edges / ai_graph_node_chunks / ai_chunks`，只展示带 chunk SourceRef 的 derived-cache 节点，并展示这些节点之间的共现关系；`加入我的图谱` 和 `编辑后保存` 只保存带 evidence 的节点为 draft，不进入 Review、不外发正文；`合并` 只在用户显式选择目标节点后合并 SourceRef evidence，保留目标节点 id、名称和摘要，不进入 Review、不做自动相似概念判断；节点 `Remove from my graph` 只删除这条 draft 节点，并清理 source/target 指向它的 draft relations，防止 broken edge；不写 Review、不外发正文；`Add relation to my graph` 只把有 evidence 的派生关系保存为 draft 关系，缺失端点会以 draft 节点补齐，不把 derived edge 写成正式关系、不送审、不外发正文；关系 `Edit and save` 只覆盖用户输入的 label/type，继续保留原 relation id、两端节点和 SourceRef evidence，不写 Review、不外发正文；关系 `Merge` 只在用户显式选择同两端目标关系后合并 SourceRef evidence，保留目标关系 id、label、type 和 ownership，不自动判断相似关系、不写 Review、不外发正文；已保存关系由 Explorer state 的 saved edge list 识别，重新打开同一关系时显示已保存状态并禁用重复添加；关系级 `Ignore` 只是当前页面的 edge-id 临时过滤状态，不删除两端概念节点、不写 ConceptGraphStore、不写 ReviewItem、不参与跨设备同步；`Remove from my graph` 只删除这条 draft 关系，不删除两端概念节点、不写 Review、不外发正文；节点级 `忽略` 也是当前页面的临时过滤状态，不写 ConceptGraphStore、不写 ReviewItem、不参与跨设备同步；Settings 书籍选择只列出已有全局层的已索引书，不自动外发正文；当前书空态补建只复用已有 chunk，不重新生成 embedding；空态草稿入口使用本地文本检索，关闭 query embedding、vector fallback 和 rerank；AI Chat 不直接调用 RAG/GraphRAG producer，不自动创建正式节点；当前图形视图是移动端轻量局部 canvas 和全书可点选派生图谱，不是无限画布；中文抽取仍不是完整实体消歧或跨书概念聚类。 |
| RAG/GraphRAG -> KnowledgeCard | 阅读页选中文本 -> `图谱/Graph` -> 无相关概念空态 -> `Card / 知识卡`。 | 本分支已接入 `RagEvidenceKnowledgeCardProducer` 和 ConceptGraph 空态 Card action；本地 RAG/GraphRAG 结果会保存为 draft KnowledgeCard，并在当前图谱页提示 `Saved as draft knowledge card / 已保存为草稿知识卡`，不进入 Review Inbox。 | 只接受带 traceable chunk SourceRef 和可保存 chunk snippet 的 RAG evidence；derived summary 只作为 explanation，正式 quote/evidence 使用书内 chunk snippet；不自动写图谱、长期记忆、笔记、ReviewItem 或 spaced review。 |
| Spaced Review | `Settings -> AI -> Spaced review / 间隔复习`；AI Chat completed Seminar 历史卡 `加入复习`；KnowledgeCard 或旧 Seminar 候选 flashcard 在 Review Inbox 中 `Apply` 后入队。 | 本分支已接入 Settings 点击入口、`.knowledge/spaced_review_items_v1.json`、复习页、证据摘录预览、Again/Hard/Good/Easy 评分、来源跳转状态；Seminar 的旧 `reviewSuggestion` 仍作为 flashcard candidate 进入 Review，并可由 Review Inbox Apply UI 应用到 Spaced Review；completed Seminar synthesis 可在 AI Chat 卡片内直接 `加入复习`，并可在未复习前 `撤销复习`。 | 内联 Seminar 复习项必须有 traceable SourceRef，不写 ReviewItem；撤销只删除尚未复习过的内联 flashcard。KnowledgeCard apply 和 flashcard candidate apply 仍保留旧路径；跨设备同步还没接。 |
| Sync / Export / Remote Preview 知识资产 | `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。 | 本分支已接入安全 manifest 预览、Markdown 学习导出、HTML study report、Anki TSV 导出、机器可读 sync bundle、创建入口、远端同步状态面板、`Send conflicts to Review` 冲突 handoff、`Preview remote sync` 远端 bundle 预览、`Check remote changes` 前台只读远端检查、`Run safe remote sync` 前台一键安全编排、`Send remote incoming to Review` 安全远端 KnowledgeCard 导入、`Send remote review history to Review` 安全远端复习记录导入、`Stage safe remote card conflicts to Review` 安全远端 KnowledgeCard 冲突暂存导入、`Send remote conflicts to Review` 远端冲突 triage handoff、只读 remote merge planner、带 rollback snapshot 和 ETag/CAS 条件写保护的 remote writeback executor、受保护 `Upload sync bundle` 写出，以及 Review inbox 直达入口；只纳入已应用 KnowledgeCard 和复习历史，显性显示排除项、待审冲突、远端 incoming/outgoing/conflict 计数、只读远端检查摘要和 `Not previewed / Review required / Ready to upload / Uploaded / Re-preview required / Concurrency guard unavailable / Failed` 状态；provider 级闭环覆盖安全的本地 KnowledgeCard 冲突进入 Review Inbox 后 approve/apply，并解除 pending conflict 回到 export included 集合。 | 目前是本地导出 + 远端 bundle 预览 + 前台只读远端检查 + 远端状态提示 + canonical per-envelope merge plan + 安全远端 KnowledgeCard Review 导入 + 安全远端 review history Review 导入 + 安全远端 KnowledgeCard 冲突 staged Review 恢复 + 前台一键安全编排 + 带 rollback 和条件写 guard 的安全 bundle 写回 + 冲突 Review handoff；`Check remote changes` 只读取远端 bundle 并展示 incoming/conflict 摘要，不上传、不发送 Review、不应用资产；`Run safe remote sync` 会先 preview，存在远端 blocker 时只批量送入 Review/暂存 Review 并停止上传，无 blocker 时才执行受保护 upload；本地 staged 或远端 staged 且满足 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef` 的冲突可 apply，远端 staged ReviewItem 写入失败会回滚暂存 entry，远端 incoming KnowledgeCard 和 review history 都会降级为 pending Review；旧的远端 preview conflict triage 入口只支持 dismiss/triage；写回前如果发现远端 incoming/conflict 会阻止覆盖；WebDAV 写回使用 `If-Match` 或 `If-None-Match`，preview 后远端变化或远端被其他设备创建时会停止上传并要求重新 preview；provider 不暴露 ETag/CAS 时拒绝覆盖并显示 concurrency guard unavailable；普通写回失败仍会恢复旧远端 bundle 或删除半写入的新 bundle 并显示状态。 |

## 2. 已接入的用户路径

### 2.1 选中文本生成知识卡

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `知识卡`。
4. 系统默认调用 `SelectionKnowledgeCardProducer(createReviewItem:false)`，创建 `KnowledgeCard(origin=selection, reviewState=draft)`，写入 `.knowledge/knowledge_cards_v1.json`。
5. 系统在当前阅读菜单提示 `Saved as draft knowledge card / 已保存为草稿知识卡`，不创建 `ReviewItem`，不进入 Review Inbox。
6. 用户稍后查看这张 draft card 时，可以看到证据摘录、来源标题/位置和不可用来源原因，并通过 SourceRef 跳回原文。
7. 旧 `createReviewItem:true` 只作为兼容或异常路径保留；这类旧路径才会创建 pending ReviewItem。

Gate：

- 卡片必须带 `bookId/cfi/jumpLink/sourceHash/createdAt`。
- 相同书籍、相同 CFI、相同选中文本重复点击，不制造重复卡。
- 空选中文本不写 store。
- 普通选中文本保存只写 draft KnowledgeCard，不进入 Review，不直接进入长期资产。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/selection_knowledge_card_producer_test.dart \
  test/widgets/context_menu/excerpt_menu_actions_test.dart \
  -r compact
```

### 2.2 一键开启研讨

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `研讨`。
4. 系统打开阅读页 AI Chat，并在当前会话写入一张原生 `AI 研讨会` 任务卡，把选中文段作为 Seminar question，并携带 reader `SourceRef`、CFI、jump link 和 snippet；旧独立研讨运行页已删除，不再作为 Settings、旧历史兼容或调试入口。
5. 用户点击 `Start Seminar`。
6. 系统先取 evidence：阅读页入口先把选中文段作为 `Reader selection` evidence，再优先 current book；AI Chat 入口没有 reader anchor 时只使用问题文本和当前阅读书籍上下文，不伪造选区 SourceRef。
7. 系统按 `critical -> supportive -> synthesizer` 串行执行角色，AI Chat 原生任务卡展示 role turn、evidence、Shared Whiteboard 和 synthesis。
8. 用户可以取消运行；失败或证据不足时可以重试。
9. 运行中用户可修改问题并点击 `Queue Seminar`，新任务进入本机串行队列；当前 job 终态后系统启动下一条 queued job。
10. 运行完成后，AI Chat Seminar 历史卡在当前卡片内显示 `保存知识卡`、`编辑后保存`、`加入复习`、`加入我的图谱`、`忽略` 和异常场景的 `异常送审`。
11. 用户仍可在 synthesis 后的 `Continue discussion / 继续讨论` 输入读者回合，并选择继续问某个角色、重新找证据或重新整理总结。
12. 普通保存动作只写 draft KnowledgeCard、inline SpacedReviewItem 或 draft ConceptNode，不写普通 ReviewItem；只有低置信、冲突、来源异常或旧兼容 `reviewSuggestion` 路径才进入 pending Review。

Gate：

- 默认使用 current book 语境。
- 阅读页选中文本入口必须把可追踪 reader SourceRef 写入 Seminar session；SourceRef 不可追踪时不能伪造 evidence。
- 默认不开 web。
- Seminar role profile 必须可治理：disabled role 不进入新 session 执行顺序和 AI Chat Seminar 任务卡 role ids；角色 profile 的会话证据提示必须合并进 session scopes，当前可见 UI 只开放 current book/library；notes/memory/conceptGraph 的运行前 evidence broker 与 `memory_search` / `concept_graph_search` 受控只读工具必须只返回可追溯结果，不得伪造成书内锚点或完整自由工具调用 loop；允许工具只保留 Seminar scene 允许的只读、非联网、非审批工具，且必须过滤写工具、unknown tool 和 `spawn_sub_agent`；疑似密钥的 custom prompt 不得进入 profile。
- 当前角色工具范围是 contract/prompt 注入和权限过滤，不得被描述为角色已拥有任意工具调用 loop；实际 role execution 仍走现有串行 runtime 和 evidence bundle。
- 页面启动前必须显示当前 provider/model/capability 诊断；缺少 pricing metadata 时必须显示 `Cost: unknown` 和原因，不伪造美元成本估算。
- 角色完成后如果 provider/SDK 返回 usage metadata，必须显示 `Provider reported usage` 并持久化到 turn/run；如果没有返回 usage metadata，必须显示本地 token 估算和 `Provider billing may differ` 提示；本地估算只能来自本地 prompt/evidence/response 字符计数，不得伪装成 provider billing。
- 用户填写的本地 role output token budget 和 run token budget 只能使用 `local-char-estimate-v1` 执行；超限时停止后续 Seminar 步骤、保留已完成 traceable turn、显示失败原因并允许重试。
- 当 provider capability cache 带 pricing metadata 时，页面必须启用估算 `Run cost cap USD`；runtime 使用 provider-reported usage 或本地 fallback usage 聚合估算美元成本，超出 cap 时停止后续 Seminar 步骤并保留失败原因。
- 页面必须说明估算 cost cap 不是真实 provider 发票或扣费上限；缺少 pricing metadata 时必须禁用美元 cap 并显示原因；不得把 provider token usage 或本地 token budget 单独当作真实账单上限。
- completed/cancelled/failed Seminar state 可作为本机恢复缓存保存；该缓存不得进入普通 prefs backup，不得同步，不得包含 API key；恢复出的页面必须显示 recovered 提示。
- 从阅读页进入 Seminar 时，现有 runtime/cache 必须匹配当前 `bookId` 和入口问题；不匹配时必须清除本机 runtime/cache 并显示新的空白 runtime，不得把旧书/旧选区的结果展示到当前入口。
- persisted `running` state 如果有可追踪 evidence、completed turns 是合法连续前缀且 provider/model/pricing 仍匹配当前配置，必须复用已保存 evidence 并从第一个缺失角色继续；不得重跑已完成角色；缺 tokenUsage 的 checkpoint turn 必须补本地估算后再进入终态 usage/cost。
- persisted `running` state 如果没有 completed role 但已有可追踪 evidence，必须丢弃 active partial text 并从首个角色重新生成；如果 checkpoint 无效、证据不可追踪或 provider/model/pricing 已变化，必须恢复为 interrupted/retryable，清空 active role 和 partial text，不得伪装后台 stream 仍在继续。
- 运行中再次启动 Seminar 必须排入本机串行 queued job，不得取消当前 active stream；用户取消 queued job 时不得取消 active stream；重启时如果 active job 可从 traceable checkpoint 续跑，且 queued job 带完整 session payload，queued job 必须保持 queued 并在 active 续跑完成后自动启动；如果没有可续跑 active job、queued job 缺少 session、checkpoint 无效、证据不可追踪或 provider 已切换，queued job 必须标记 interrupted/retryable，不得伪装旧 stream 仍在继续。
- 研讨结果不自动写 KnowledgeCard、Memory、Note、Sync asset 或正式图谱；只有用户在当前 AI Chat 卡片显式点击保存、加入复习、加入我的图谱或异常送审，才写对应 draft/inline 资产或 Review handoff。
- completed continuation composer 的读者输入必须保存为 `lastUserIntervention`，不得写入 formal evidence ledger，不得生成没有 SourceRef 的正式证据。
- 普通 completed Seminar synthesis 采用当前卡片内联确认；异常、低置信、来源断裂、重复无法判断和旧兼容候选才进入 Review Inbox。内联复习项必须可撤销且未复习前才能删除；内联图谱节点保持 draft ownership，不能伪装成正式用户图谱资产。
- 当前入口必须保留降级路径：用户仍可用普通 `AI` 按钮解释选中文本。

验证命令：

```bash
flutter test --no-pub \
  test/service/ai/langchain_runner_usage_test.dart \
  test/service/ai/ai_seminar_runtime_service_test.dart \
  test/providers/ai_seminar_runtime_test.dart \
  test/ai_chat_stream_seminar_entry_test.dart \
  test/ai_multi_tab_chat_visibility_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  test/widgets/context_menu/excerpt_menu_actions_test.dart \
  -r compact
```

### 2.3 AI Chat 回答生成知识卡

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `AI`。
4. AI 面板打开，并把选中文本放入草稿；如果用户发送的草稿仍包含原选中文本或 SourceRef snippet，系统把本轮草稿的 reader SourceRef 写入会话树用户节点，随 `conversationV2` 历史保存。
5. 用户发送问题并等待回答完成。
6. 用户查看回答气泡旁边的来源状态：`可跳转来源` 表示卡片会带 reader source；`已标记不可用` 表示只保留 conversation provenance，不能跳回原文。
7. 用户点击回答气泡旁边的 `知识卡`。
8. 系统默认调用 `AiChatKnowledgeCardProducer(createReviewItem:false)`，创建 `KnowledgeCard(origin=ai-chat, reviewState=draft)`，写入 `.knowledge/knowledge_cards_v1.json`。
9. 系统在当前 AI Chat 内提示 `Saved as draft knowledge card / 已保存为草稿知识卡`，不创建 `ReviewItem`，不进入 Review Inbox。
10. 用户可以在当前对话继续追问，也可以稍后从知识卡入口查看；有 reader SourceRef 时可跳回原文，没有 reader SourceRef 时仍保留 conversation provenance 和不可跳原因。
11. 旧 `createReviewItem:true` 只作为兼容或异常路径保留；只有这类旧 Review 路径被用户 `Apply` 后，带 reader grounding 和保守 `conceptRefs` 的卡才会创建 draft ConceptGraph node/edge 和 pending relation ReviewItem。

Gate：

- 入口必须是回答完成后的用户显式 `知识卡` 点击；streaming 中按钮不可用。
- 回答旁必须显示来源状态：有 reader grounding 或有效当前阅读位置 fallback（`bookId + cfi`）时显示可跳转；旧历史、没有 reader source 或当前阅读位置缺少可保存锚点时显示已标记不可用，并通过 tooltip 说明不能跳回原文。
- 从选中文本打开 AI 时，KnowledgeCard 必须优先使用该选中文本的 reader SourceRef。
- 如果用户把预填草稿改成不包含原选中文本或 SourceRef snippet 的无关问题，本轮 user node 不得保存旧 reader SourceRef，回答旁 `知识卡` 只能使用 conversation provenance 或显式持久化的新 reader SourceRef。
- 短公共片段不能只因为被改写后的问题碰巧包含就保留精确 reader SourceRef；短片段只有发送内容等于该片段本身时才保留。
- 选中文本 reader SourceRef 必须随 `conversationV2` 保存；历史重载后回答旁 `知识卡` 仍优先使用原始 reader SourceRef。
- 没有 reader SourceRef 的普通聊天也必须保留 conversation SourceRef 和不可跳原因；从历史加载且没有持久化 reader SourceRef 的会话不能使用当前阅读位置 fallback。
- 只有 reader-grounded AI Chat card 能生成保守 `conceptRefs`；纯聊天 card 的 `conceptRefs` 必须为空。
- 空回答不写 store。
- 长回答在写入 KnowledgeCard、SourceRef 和可选旧 Review payload 前必须裁剪。
- 重复点击同一 conversation/message/prompt/answer 不制造重复卡。
- 本入口不调用额外 LLM、embedding、rerank 或 web provider；只保存当前已有回答。
- Producer 默认只写 draft KnowledgeCard，不直接写 ReviewItem、ConceptGraph、长期记忆、笔记或 spaced review；旧 `createReviewItem:true` 兼容路径才写 pending KnowledgeCard 和 pending ReviewItem，ConceptGraph 候选只能由该旧 Review apply 后的 `ReviewInboxController -> ConceptGraphProducer` 生成。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/ai_chat_knowledge_card_producer_test.dart \
  test/ai_chat_stream_knowledge_card_test.dart \
  -r compact
```

### 2.4 AI Chat Memory 直接记住与异常送审

用户路径：

1. 在 AI Chat 中找到一条回答。
2. 点击回答旁的 `Memory actions`。
3. 普通保存时选择 `Remember this / 记住这条`。
4. 系统直接调用 `MemoryWorkflowService.saveToDaily`，把这条内容追加到今日日记 Markdown，并记录 `MemoryCandidate(status=applied, decisionSource=direct_save)`。
5. 同一条消息的 `Memory actions` 菜单切换为 `Undo memory / 撤销本条记忆`。
6. 用户点击撤销时，系统调用 `MemoryWorkflowService.undoDirectSave`，只移除刚追加的精确 Markdown 文本，并把该候选标记为 dismissed。
7. 如果用户认为这条内容低置信、敏感、冲突或想稍后处理，可选择 `Add to Review inbox / 加入待审核队列`。
8. 异常送审路径会创建 `MemoryCandidate(status=pending)` 和 `ReviewItem(sourceType=memory-candidate)`。
9. 用户进入 `Settings -> AI -> Review inbox` 后，仍可对异常 memory 候选查看证据、批准、忽略或应用。
10. 用户结束当前 AI Chat 会话时，如果开启会话摘要，默认 `Smart save / 智能保存` 会整理最多 3 条候选：高置信候选直接写入今日日记，低置信候选进入 Review Inbox。

Gate：

- 普通显式保存不进入 Review Inbox；必须在当前 AI Chat 消息菜单内能完成保存和撤销。
- `Undo memory / 撤销本条记忆` 只能撤销 `direct_save` 产生的 applied MemoryCandidate；不得删除 Review apply 得到的正式 memory 或其他用户资产。
- 撤销必须移除刚追加的精确 Markdown block；找不到文本时必须失败并提示，不能只改 UI 状态。
- `Add to Review inbox / 加入待审核队列` 只作为异常、低置信、敏感、冲突或暂存路径；pending memory 的 `Dismiss` 必须同步 MemoryCandidate 状态，且不写 memory Markdown。
- 自动会话摘要默认 `smartDaily`；只有置信度达到阈值的候选可直接写 daily，低置信候选必须保留为 pending Review，不能为了省事全部直写。
- 异常 memory apply 必须走 Memory source-specific adapter；不能通过泛型 ReviewItem 状态推进绕过 source 写入。
- 无书内跳转的 conversation memory 必须保留 evidence snippet、source hash 和不可跳原因，使用户能解释来源不可跳。
- Apply/dismiss 不写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。
- MemoryCandidate 缺失、targetDoc 缺失或 SourceRef 不满足 gate 时，不得推进 ReviewItem 到 applied。

验证命令：

```bash
flutter test --no-pub \
  test/ai_chat_stream_memory_actions_test.dart \
  test/service/review/knowledge_review_adapter_test.dart \
  test/service/memory_workflow_service_test.dart \
  test/service/review/review_inbox_controller_test.dart \
  test/page/settings_page/review_inbox_page_test.dart \
  -r compact
```

### 2.5 Memory 独立浏览 SourceRef 审计

用户路径：

1. 用户在 `Settings -> Home navigation / 首页导航` 打开默认隐藏的 `Memory / 记忆` tab。
2. 用户从首页底部导航进入 `Memory / 记忆` tab。
3. 页面加载 daily memory 和 long-term memory 条目。
4. 系统用已应用的 `MemoryCandidate` 按目标文档和条目 body 只读投影 SourceRef。
5. 条目行显示 `traceable/unavailable/unresolved` 来源状态。
6. 用户点击一条 memory 进入详情页。
7. 详情页显示 `Evidence`、证据摘录、来源标题/位置和不可跳原因。
8. 如果 SourceRef 可解析为 `paperreader://reader/open?...`，用户点击 `Open source` 回到原文。
9. 如果来源没有 book anchor，用户点击 `Open source` 时看到不可跳原因，不触发空跳转。

Gate：

- Memory 独立浏览页只能读取已应用 MemoryCandidate 生成 SourceRef，不写新的 ReviewItem 或知识资产。
- SourceRef 投影必须匹配 `daily/longTerm` 目标文档和条目正文；只能用实际写入 memory 的 `text/displayText` 证明归属，不能只靠 summary 命中；long-term `MEMORY.md` 使用 H1 分段 body，不能把整文件来源全部挂到每个分段。
- 不往 Markdown memory 文件写隐藏 metadata；旧 Markdown 仍可正常打开。
- long-term H1 分段不可批量删除/打标签，避免把一个分段的操作变成整份 `MEMORY.md` 的资产修改。
- 有效来源必须通过 `PaperReaderReaderIntent.fromSourceRef` 生成 reader intent；非法 jump link 不能算 traceable。
- conversation-only memory 保留 evidence snippet、source hash 和 `memory-source-not-jumpable` 不可跳原因。
- 详情页只展示已裁剪 evidence，不读取整章正文、图片原文、OCR 长文本或派生索引。

验证命令：

```bash
flutter test --no-pub \
  test/page/memory/memory_home_page_test.dart \
  test/service/memory/markdown_memory_store_test.dart \
  test/service/memory/memory_source_ref_adapter_test.dart \
  test/page/memory/memory_row_test.dart \
  test/page/memory/memory_detail_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.6 旧划线/笔记 SourceRef 审计

用户路径：

1. 用户打开某本书的笔记列表，或在全局搜索里看到命中的笔记/划线。
2. 系统用 `BookNoteSourceRefAdapter.fromBookNote` 把旧 `BookNote` 投影成 `SourceRef`。
3. 笔记条目显示 `Evidence`、证据摘录、来源书名、章节位置和 `traceable/unavailable` 状态。
4. 有 `bookId + cfi` 的条目沿用原有阅读页跳转。
5. 缺失 CFI 或无有效 book anchor 的旧条目点击时显示 `book-note-source-not-jumpable` 原因，不调用空 CFI 跳转。

Gate：

- 旧 BookNote/highlight 不制造 KnowledgeCard、ReviewItem、Memory、ConceptGraph、SpacedReview 或 Sync side effect。
- `BookNoteSourceRefAdapter` 必须区分 highlight 与 note。
- 有 `bookId + cfi` 的 SourceRef 必须生成 `paperreader://reader/open?...` jumpLink。
- 缺失 CFI 或无有效 bookId 的旧条目必须写 `unavailableReason`，并仍可在 UI 中看到来源证据。
- `SourceRefEvidenceList` 只展示裁剪后的 snippet、title、location 和 unavailable reason，不读取章节正文或 `ai_index.db`。

验证命令：

```bash
flutter test --no-pub \
  test/service/review/knowledge_review_adapter_test.dart \
  test/widgets/book_notes/book_note_tile_test.dart \
  -r compact
```

### 2.7 图片解析生成知识卡

用户路径：

1. 打开一本书。
2. 点开正文中的图片。
3. 点击图片工具栏里的 `AI Image Analysis / AI图片解析`。
4. 等待图片解析结果出现在弹层中。
5. 点击弹层里的 `Card / 知识卡`。
6. 系统创建 `KnowledgeCard(origin=image-analysis)`，写入 `.knowledge/knowledge_cards_v1.json`。
7. 系统在当前弹层提示 `Saved as draft knowledge card / 已保存为草稿知识卡`。
8. 用户可以稍后在知识资产里处理这张 draft card，并通过 SourceRef 跳回图片所在阅读位置。

Gate：

- 图片解析结果必须由用户显式点击 `Card / 知识卡` 后才写入。
- 卡片必须带当前阅读位置的 `bookId/cfi/href/jumpLink/sourceHash/createdAt`。
- 相同书籍、相同阅读锚点、相同图片上下文和相同解析结果重复点击，不制造重复卡。
- 图片解析结果普通入口只写 draft KnowledgeCard，不写 ReviewItem、不直接进入长期资产、笔记或 spaced review。
- 图片本身不写入 knowledge card payload；SourceRef 只保存裁剪后的图片上下文、alt/title 和当前阅读锚点。
- `ImageAnalysisKnowledgeCardProducer(createReviewItem:true)` 只作为旧 Review 兼容或异常路径。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/image_analysis_knowledge_card_producer_test.dart \
  test/page/book_player/image_viewer_test.dart \
  -r compact
```

### 2.8 概念图谱探索

用户路径：

1. 用户进入 `Settings -> AI -> Concept graph / 概念图谱`，或在阅读页选中文本后点击 `图谱/Graph`。
2. 普通图谱学习动作在当前图谱页内完成：用户可以查看派生节点/关系，直接保存为 draft、编辑后保存、合并到已有节点/关系、忽略或撤销。
3. 只有旧兼容 producer、正式关系升级、重复无法判断、来源断裂或跨设备导入等异常场景，才写入 `ReviewItem(sourceType=concept-graph-relation, status=pending)`。
4. 用户在 Review Inbox 中审核这些异常 relation；只有 relation 被 `Apply` 后，edge 才升级为正式图谱关系。
5. 如果用户先在 Review Inbox 中 `Apply` 一个带 `conceptRefs` 和可追踪 SourceRef 的 KnowledgeCard，系统仍可创建 card node、concept node 和 draft `appears_in` edge。
6. 该兼容路径可继续把需要正式化的 relation 送入 Review；普通图谱页内 draft 保存不需要这一步。
7. 用户进入图谱页后，如果入口带有当前 bookId，页面读取 `ai_graph_nodes / ai_graph_edges` 全局层，只展示有 chunk SourceRef 的只读 `全书派生图谱 / Full-book derived graph`。
8. 页面显示 `Book map / 本书地图`，把核心主题、主干关键概念数、主干关系数和证据覆盖数放在顶部；用户点击核心主题，会打开该节点摘要、相邻关系、证据摘录和来源跳转详情。
9. 页面根据中心性、证据数量和强关系生成 `Reading path / 导读路径`；用户点击路径中的概念，会打开同一套节点摘要、相邻关系、证据摘录和来源跳转详情；路径中相邻概念之间会显示关系标签和 evidence 数量，点击关系 chip 会打开 `Selected full-book relation` 详情。
10. 用户点全书图谱画布里的节点，页面显示该节点摘要、相邻关系、证据摘录和 `Open source / 打开来源`。
11. 系统列出 `ConceptGraphStore` 中已有概念节点；从阅读页进入时，会先按选中文本筛选相关概念。
12. 用户点一个概念。
13. 页面显示该概念的定义、来源证据、局部图谱摘要、局部路径和可回溯关联；局部图谱摘要会标出中心概念、直接关系、二跳节点、evidence link 数量和 draft/formal 状态。
14. 页面显示 orphan node / broken edge 计数，用于发现悬空图谱关系。
15. 有可跳转 SourceRef 时，用户可以点 `Open source / 打开来源` 回到原文。
16. 如果选中文本没有匹配到已有概念，页面展示空态和 `Create draft candidate / 创建草稿候选` 入口。
17. 当 Seminar candidate card 或 reader-grounded AI Chat card 带有 `conceptRefs` 时，用户在 Review Inbox 中应用该 KnowledgeCard 后，系统复用同一 producer 创建 draft 概念节点和 draft card 关系；需要正式化或无法判断重复时，才进入 relation Review。
18. 用户点击 `Create draft candidate` 后，系统执行本地文本 library RAG search，并关闭 query embedding、vector fallback、rerank；只有 search result 带 `derivedLayer/derivedSummary` 且有 traceable chunk SourceRef 时，才通过 producer 创建 draft 概念节点和 draft RAG claim 节点，不写普通 relation ReviewItem。

Gate：

- 只有 `applied + user asset + traceable + conceptRefs` 的 KnowledgeCard 会触发 producer。
- 只有带 `derivedLayer/derivedSummary` 且 SourceRef 可追踪到书内 chunk 的 library RAG result 会触发 RAG/GraphRAG producer。
- 普通图谱页内 producer 只写 draft node/edge，不写 ordinary ReviewItem；正式 relation 升级、异常冲突或兼容路径才进入 Review apply。
- 没有 `conceptRefs` 的 KnowledgeCard 不制造图谱噪声。
- 普通 RAG 命中不制造 ConceptGraph 节点；GraphRAG/RAPTOR summary 只作为 derived summary，正式 evidence snippet 必须来自书内 chunk SourceRef。
- 旧 Seminar candidate card 和 reader-grounded AI Chat card 的 `conceptRefs` 仍可先随 KnowledgeCard 进入 Review；只有用户 Apply 后才会生成兼容图谱候选关系。completed Seminar 卡片的普通图谱沉淀走当前卡片内联保存。
- Producer 失败不回滚 KnowledgeCard apply 或 spaced review 入队。
- 只展示已有图谱数据，不把 AI 推断直接变成用户确认关系。
- 全书派生图谱只读取当前书全局层和 chunk evidence，节点保持 `derived-cache`；关系来自同 chunk 共现计数并借用端点节点 SourceRef，不写正式 `ConceptGraphStore`，不进入 Review，不外发正文。
- 全书派生图谱 loader 在 `nodeLimit` 截断前必须优先保留有 chunk evidence、强关系和主干连接度的 grounded concepts，不能先按 confidence 裁剪后再让 UI 计算 `Book map / 本书地图` 或 `Reading path / 导读路径`。
- `Book map / 本书地图` 只统计主干连通概念、主干关系和它们的 SourceRef evidence；不把孤立低价值节点算成关键概念，不生成 LLM 报告，不写正式图谱资产，不外发正文。
- `Reading path / 导读路径` 只从可见的全书派生图谱计算，不写正式图谱资产，不外发正文；路径关系 chip 只读取当前派生边的 label/type 与 SourceRef evidence 数量；用户忽略节点或关系后，路径必须跟随当前页可见图谱重新计算。
- 全书图谱节点详情只能展示已有 SourceRef evidence；没有 jumpable SourceRef 时必须显示不可跳原因，不能伪造来源。
- 局部路径只使用有 evidence 的边。
- broken link / orphan node 必须显性可见。
- 没有图谱数据时展示空态，而不是制造无证据节点。
- 阅读页 `图谱/Graph` 入口不自动调用 LLM、embedding、rerank 或 web provider，不外发正文，不写正式 `ConceptGraphStore` 资产；用户点击 `Create draft candidate` 时只执行关闭 query embedding、vector fallback、rerank 的本地文本 library RAG search 和 draft 写入。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/concept_graph_producer_test.dart \
  test/service/knowledge/derived_book_concept_graph_loader_test.dart \
  test/service/review/review_inbox_controller_test.dart \
  test/providers/concept_graph_explorer_test.dart \
  test/page/settings_page/concept_graph_explorer_page_test.dart \
  test/widgets/context_menu/excerpt_menu_actions_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.9 RAG / GraphRAG 结果生成知识卡

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `图谱/Graph`。
4. 如果没有匹配到已有概念，页面展示空态。
5. 用户点击空态里的 `Card / 知识卡`。
6. 系统执行本地文本 library RAG search，并关闭 query embedding、vector fallback、rerank。
7. 系统只从带 traceable chunk SourceRef 的 RAG evidence 创建 `KnowledgeCard(origin=rag-evidence, reviewState=draft)`。
8. 系统在当前图谱页提示 `Saved as draft knowledge card / 已保存为草稿知识卡`，不创建 `ReviewItem`，不进入 Review Inbox。
9. 用户可以稍后查看这张 draft card，并通过 SourceRef 跳回原文 chunk。
10. 旧 `createReviewItem:true` 只作为兼容或异常路径保留；这类旧路径才会创建 pending ReviewItem。

Gate：

- 入口必须是用户显式点击 `Card / 知识卡`。
- 本入口不调用 LLM、embedding、rerank 或 web provider，不外发正文。
- 只有 `SourceRef.hasDerivedChunkHint`、可追踪回书内 chunk、且带可保存 chunk snippet 的 evidence 能进入卡片。
- `derivedSummary` 只作为 explanation，不作为 formal evidence snippet；quote 使用书内 chunk snippet。
- 普通入口 Producer 只写 draft KnowledgeCard，不写 ReviewItem、ConceptGraph node/edge、Memory、Note 或 Spaced Review；旧 `createReviewItem:true` 兼容路径才写 pending KnowledgeCard 和 pending ReviewItem。
- 重复点击同一 query 和同一 evidence 不制造重复卡。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/rag_evidence_knowledge_card_producer_test.dart \
  test/providers/concept_graph_explorer_test.dart \
  test/page/settings_page/concept_graph_explorer_page_test.dart \
  -r compact
```

### 2.10 间隔复习

用户路径：

1. 普通阅读路径中，用户可先把选中文本或 Seminar 结论保存为 draft KnowledgeCard，再在当前卡片或 AI Chat 卡片内选择 `加入复习`；异常、低置信或旧兼容 producer 仍可写入待审知识卡/复习卡。
2. 对内联 `加入复习` 路径，系统直接把有 SourceRef 的 flashcard / spaced review item 写入 `.knowledge/spaced_review_items_v1.json`，并在当前卡片提供撤销入口。
3. 对异常或兼容 Review 路径，用户进入 `Settings -> AI -> Review inbox`。
4. 用户先批准，再点击 `Apply`。
5. 系统把已应用且有 SourceRef 的 KnowledgeCard 或 flashcard candidate 写入 `.knowledge/spaced_review_items_v1.json`。
6. 用户进入 `Settings -> AI -> Spaced review / 间隔复习`。
7. 页面刷新时会对账已应用 KnowledgeCard，补齐缺失的复习队列项。
8. 页面显示到期复习项、答案、证据摘录、来源标题/位置、可跳转来源、不可用来源和未解析来源计数。
9. 用户点击 `Again / Hard / Good / Easy` 后，系统记录复习历史并更新下一次到期时间。

Gate：

- 只有 `applied + traceable + user asset` 的 KnowledgeCard，或 `applied + traceable + flashcard candidate`，能进入复习队列。
- 同一 KnowledgeCard 或同一 flashcard candidate 重复入队不会制造重复复习项。
- 如果 KnowledgeCard Review apply 已成功但队列写入曾失败，复习页刷新会按已应用 KnowledgeCard 对账恢复；flashcard candidate 需要重新 Apply 或由后续对账任务补齐。
- 复习项必须保留 SourceRef；证据摘录、来源位置、可跳转、不可用、未解析来源都要显性展示。
- 复习记录只更新 spaced review 队列，不写长期记忆、不写笔记、不写同步资产。
- 删除书或恢复备份导致来源不可跳时，页面显示不可用或未解析状态，而不是静默丢失。

验证命令：

```bash
flutter test --no-pub \
  test/service/review/spaced_review_store_test.dart \
  test/service/review/review_inbox_controller_test.dart \
  test/providers/spaced_review_test.dart \
  test/page/settings_page/spaced_review_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.11 知识同步 / 导出

用户路径：

1. 用户先在 Review Inbox 中 `Apply` KnowledgeCard，或完成间隔复习记录。
2. 用户进入 `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。
3. 页面展示本次默认纳入的知识资产数量、默认排除项数量和待审冲突数量。
4. 用户可以刷新计划，确认哪些 envelope 会进入导出，哪些因草稿、派生缓存、密钥或冲突被排除。
5. 如果页面显示待审冲突，用户点击 `Send conflicts to Review / 发送冲突到 Review`。
6. 系统为每个尚未进入 Review 的待审冲突创建 `ReviewItem(sourceType=sync-conflict, status=pending)`，只保存安全 metadata、payload key 列表和 SourceRef；如果冲突没有 SourceRef，则写入 `sync-conflict-no-source` 不可跳原因，不把 raw payload 值或 secret 值写入 ReviewItem payload。
7. 页面显示 `Review inbox` 直达入口；用户点击后进入 Review Inbox，也可以从 `Settings -> AI -> Review inbox` 进入。
8. 用户查看 `Sync conflict / 同步冲突` 类型的待审项、冲突原因、来源证据和可跳转状态。
9. 如果该冲突是 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef`，页面显示 `Approve` 和 `Apply`；用户 `Apply` 后系统把该 KnowledgeCard 写回为用户确认资产，并解除 pending conflict metadata。
10. 如果冲突含 secret payload、未知 schema、无可追踪 SourceRef、非 KnowledgeCard 或 payload 不可解析，页面只显示 `Dismiss`，不提供 approve/apply。
11. 用户点击 `Create export / 创建导出`。
12. 系统写入 `.knowledge/knowledge_export_manifest_v1.json`，其中只包含安全的实体 ID、格式、时间戳和裁剪后的 SourceRef 引用。
13. 系统同时写入 `.knowledge/knowledge_export_v1.md`，作为可阅读的 Markdown 学习导出，只包含已纳入资产、裁剪后的证据片段和可跳转来源。
14. 系统同时写入 `.knowledge/knowledge_export_study_report.html`，作为可打开的本地 HTML 学习报告；页面不加载外部资源、不执行同步，只展示已纳入资产、裁剪后的证据片段和可跳转来源。
15. 系统同时写入 `.knowledge/knowledge_export_anki.tsv`，作为 Anki 兼容 TSV；Front/Back/Source 只来自默认纳入资产、裁剪后的证据片段和可跳转来源。
16. 系统同时写入 `.knowledge/knowledge_sync_bundle_v1.json`，作为机器可读 per-entity envelope bundle；它只包含默认纳入的安全 envelope，不包含 draft、pending conflict、secret payload 或派生缓存。
17. 如果用户已配置 WebDAV/SyncClient，用户可以先点击 `Check remote changes / 检查远端变更` 执行前台只读检查；这个入口只读取远端 bundle 并显示 incoming/conflict 摘要，不上传、不发送 Review、不应用资产。
18. 用户也可以点击 `Preview remote sync / 预览远端同步` 查看完整远端 preview，或点击 `Run safe remote sync / 运行安全远端同步` 执行前台安全编排。
19. 系统读取远端 `paper_reader/.knowledge/knowledge_sync_bundle_v1.json`，按 entity id 比对本地 included envelope，展示 `remote / incoming / outgoing / remote conflict` 计数。
20. 页面显示远端同步状态：`Not previewed / Review required / Ready to upload / Uploaded / Re-preview required / Concurrency guard unavailable / Failed`，并显示对应下一步动作说明；如果来自 `Check remote changes`，页面额外显示只读检查提示。
21. 如果用户点击 `Run safe remote sync` 且 preview 发现 incoming 或 conflict，系统只批量执行安全 Review handoff：安全远端 incoming KnowledgeCard 进入 Review、安全远端 review history 进入 Review、安全远端 KnowledgeCard conflict 写入 staged conflict store 并进入 Review、远端 preview conflict 进入 triage Review；本次不会上传。
22. 如果用户点击 `Run safe remote sync` 且 preview 没有 incoming/conflict，系统走受保护 `Upload sync bundle`，成功后显示上传路径、上传 envelope 数量，并清理旧的 Review handoff 计数。
23. 用户也可以单独点击 `Send remote incoming to Review / 发送远端待引入到 Review`。
24. 系统只把安全远端 incoming KnowledgeCard 降级为 `KnowledgeCard(reviewState=pending, ownership=AI-generated-draft)` 和 `ReviewItem(sourceType=knowledge-card, status=pending)`；重复导入、非 KnowledgeCard、无 evidence 或 unsafe payload 被跳过。
25. 用户点击 `Send remote review history to Review / 发送远端复习记录到 Review`。
26. 系统只把安全远端 review history 降级为 `ReviewItem(sourceType=review-history-import, status=pending)`；用户 Apply 后才写入本机 SpacedReviewStore；重复导入、无 evidence 或 unsafe payload 被跳过。
27. 用户点击 `Stage safe remote card conflicts to Review / 暂存安全远端知识卡冲突到 Review`。
28. 系统只把安全远端 KnowledgeCard conflict 写入本机 staged conflict store，并创建可 apply 的 `ReviewItem(sourceType=sync-conflict, status=pending, canApply=true, remoteStaged=true)`；ReviewItem 不保存 remote raw payload value。
29. 用户在 Review Inbox 中批准并应用后，系统才把 staged remote KnowledgeCard 写回为本机已确认资产，并清掉 staged conflict；未 Apply 前原本机 KnowledgeCard 不被覆盖。
30. 用户点击 `Send remote conflicts to Review / 发送远端冲突到 Review`。
31. 系统把远端冲突创建为 preview-only `ReviewItem(sourceType=sync-conflict, status=pending, canApply=false)`；ReviewItem 只保存安全 metadata、payload key 列表、SourceRef count 和 SourceRef safe JSON，不保存 remote raw payload value。
32. preview-only 远端 `sync-conflict` 只用于 triage/dismiss，不显示 approve/apply；可恢复 apply 必须来自 staged conflict 入口。
33. 用户点击 `Upload sync bundle / 上传 sync bundle`。
34. 系统重新生成本机安全 sync bundle；如果远端 bundle 不存在，创建远端目录并上传；如果远端 bundle 已存在，先执行 preview gate，只有 `incoming=0` 且 `conflict=0` 时才允许覆盖写出。
35. 如果远端存在 incoming 或 conflict，上传中止并显示错误，不删除远端内容、不覆盖本地资产、不把远端冲突自动应用到本地。

Gate：

- 默认只纳入 `applied + user asset` 的 KnowledgeCard 和 review history。
- `ai-draft`、`derived-index`、包含 API key/token/secret/auth/authorization/bearer/private-key/credential/password 的 payload 默认排除。
- 待审冲突显示为排除项，不进入 manifest。
- `Send conflicts to Review` 只为待审冲突创建 `sync-conflict` ReviewItem；重复点击不制造重复 ReviewItem，不覆盖已经存在的 pending/approved/dismissed/applied 审核决策；无 SourceRef 冲突必须带不可跳原因。
- sync conflict ReviewItem 只保存 entity id/type/schema/update/conflict reason/payload keys/sourceRef count；不得保存 raw payload value、API key、token、secret 或派生缓存内容。
- sync conflict ReviewItem 只有在 payload 标记 `canApply=true` 且底层 store 再次验证为 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef` 时，才可 approve/apply；其他 sync conflict 只能 dismiss/triage。
- safe sync conflict apply 只允许解除该 KnowledgeCard 的 pending conflict metadata 并写回为用户确认资产；不得创建 SpacedReview、ConceptGraph、Memory、Note 或远端同步 side effect。
- manifest 不写 `ai_index.db`，不把派生索引当作 source-of-truth。
- SourceRef 文本片段必须使用现有裁剪规则，不导出无限正文。
- Markdown 导出只能读取默认纳入资产；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 Markdown 正文。
- HTML study report 只能读取默认纳入资产；正文和链接属性必须转义，不加载远端脚本、图片、样式或 provider 内容；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 HTML 正文。
- Anki TSV 导出只能读取默认纳入资产；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 TSV 正文；TSV 字段必须清理制表符和换行，避免破坏导入结构。
- sync bundle 只能包含默认纳入 envelope；不得包含 draft、pending conflict、secret payload、`ai_index.db` 或 derived cache。
- remote preview 只读取配置的 SyncClient/WebDAV bundle；读取失败进入页面错误状态，用户可刷新重试；不会自动导入 incoming envelope，不会自动覆盖本地资产。
- `Check remote changes` 是前台只读 remote preview：只更新远端检查摘要和远端状态，不调用 upload，不调用任何 `submitRemote*ToReview` handoff，不调用 apply，不修改本地 confirmed asset。
- remote incoming 导入必须由用户点击触发；只接受安全 KnowledgeCard，且导入后仍是 pending Review，不直接成为本机用户资产。
- remote review history 导入必须由用户点击触发；只接受安全 review history，且导入后仍是 pending Review，不直接写入 SpacedReviewStore。
- remote conflict 有两条显式入口：preview-only triage 入口必须 `canApply=false`；staged restore 入口只接受安全 KnowledgeCard conflict，必须先写 staged conflict store，再由 Review Inbox approve/apply 恢复；若 ReviewItem 写入失败，必须回滚 staged entry。
- `Run safe remote sync` 必须先 preview；存在 incoming/conflict blocker 时只执行安全 Review handoff 和 staged conflict handoff，不调用 upload；无 blocker 时才调用受保护 upload，并清理旧 Review handoff 计数。
- remote upload 只上传本机重新生成的安全 sync bundle；远端存在 incoming 或 conflict 时必须阻止上传，不能用本机 bundle whole-file 覆盖远端用户资产。
- 当前入口创建本地 manifest、Markdown 学习导出、HTML study report、Anki TSV、sync bundle，能把安全远端 incoming KnowledgeCard、远端 review history、本地冲突、安全远端 KnowledgeCard staged conflict 和远端 preview-only conflict 送入 Review Inbox，能通过 `Run safe remote sync` 串联 preview、Review handoff 和无 blocker 写回，并能在无远端 incoming/conflict 时通过带 rollback snapshot 和条件写 guard 的 executor 写回安全 sync bundle；支持安全 KnowledgeCard 本地冲突和安全远端 KnowledgeCard staged conflict 的用户确认恢复，且 staged ReviewItem 写入失败会清理暂存项；WebDAV 写回使用 ETag/CAS 条件写，preview 后远端变化会停止上传并要求重新 preview，provider 缺少条件写能力会拒绝覆盖；写回失败会恢复旧远端 bundle 或删除半写入的新 bundle；不执行双向自动合并或自动同步备份。

验证命令：

```bash
flutter test --no-pub \
  test/models/knowledge_sync_test.dart \
  test/service/sync/knowledge_asset_export_service_test.dart \
  test/providers/knowledge_asset_export_test.dart \
  test/page/settings_page/knowledge_asset_export_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.12 Custom Skill 导入

用户路径：

1. 用户进入 `Settings -> AI -> 自定义技能 / Custom skills`。
2. 用户粘贴 `CustomSkillContract(schemaVersion=1)` JSON，或点击 `粘贴安全示例 / Paste safe example` 填入安全示例。
3. 用户点击 `导入技能 / Import skill`。
4. 系统解析 JSON、校验 schema、scene、工具权限和 runtime 注入边界。
5. 如果校验失败，页面显示错误，skill 不写入本地 store，也不出现在 `Active Skill`。
6. 如果校验通过，系统写入 SharedPreferences 中的 `customAiSkillContractsV1`，并在页面的 Installed skills 列表显示 runtime 状态、scene 和允许工具。
7. 用户可以开关或删除该 custom skill。
8. 用户回到 `Settings -> AI -> Active Skill`，选择启用后的 custom skill。
9. AI Chat runtime 构建 system prompt 时合并 custom skill prompt；工具列表只保留 custom skill 声明过、当前 scene 可用、permission matrix 允许的只读工具。

Gate：

- 只接受 JSON object，不接受空输入或数组根节点。
- `schemaVersion` 必须是整数 `1`。
- unknown field、unknown scene、system scene、字段类型错误、未知工具、写工具、`spawn_sub_agent` 均阻止导入。
- disabled custom skill 可以保存在 Installed skills，但不进入 `Active Skill`，也不会注入 runtime。
- active custom skill scene 不匹配时不注入 prompt，工具列表为空。
- active custom skill 运行时不加载 MCP 工具，避免绕过 contract 的 tool whitelist。
- 导入、开关、删除不写 KnowledgeCard、ReviewItem、Memory、Note、ConceptGraph 或 Sync asset。

验证命令：

```bash
flutter test --no-pub \
  test/service/ai/skills/custom_skill_store_test.dart \
  test/service/ai/langchain_registry_custom_skill_test.dart \
  test/page/settings_page/custom_skills_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.13 Responses 兼容模型提问

用户路径：

1. 用户进入 `Settings -> AI -> Provider Center`。
2. 用户选择或创建 OpenAI Responses 兼容 provider。
3. 用户在详情页 `API 密钥` 区导入或添加本机密钥；中文界面会显示 `API 密钥 / 导入 / 添加 / 测试 / 未配置 API 密钥`，并提示密钥仅保存在本机。
4. 用户按 provider 需要配置 model、base URL、streaming/reasoning 选项。
5. 用户可以保持 `Use previous_response_id continuation` 开启。
6. 用户在阅读页 AI Chat、Seminar 或工具调用场景中发起请求。
7. 如果 provider 支持 `previous_response_id`，系统继续使用 server-side continuation；请求体显式发送 `store: true`，且不与 `conversation` 同时发送。
8. 如果 provider 明确以 HTTP 400 拒绝 `previous_response_id`，系统自动重建为不带该字段的 tool-output replay body，并重试一次。
9. 如果 provider 明确以 HTTP 400 拒绝 `store`，系统自动重建为不带 `store` 和 `previous_response_id` 的 replay body，并重试一次。
10. 如果错误不是 `previous_response_id` 或 `store` unsupported，系统保留原错误并显示给用户，不把 provider 配置错误误判为兼容 fallback。

Gate：

- 只有请求体确实包含 `previous_response_id`，且 HTTP status 是 `400`，且错误正文同时包含 `previous_response_id` 和 `unsupported`，才允许 fallback。
- 只有请求体确实包含 `store: true`，且 HTTP status 是 `400`，且错误正文同时包含 `store` 和 `unsupported`，才允许 store fallback；store fallback 后同一个 runtime instance 不再使用 `previous_response_id`。
- fallback 后同一个 `ChatOpenAIResponses` runtime instance 不再发送 `previous_response_id`。
- 正常支持 `previous_response_id` 的 provider 不受影响。
- 非 `previous_response_id` / `store` 的 HTTP 400 不允许 retry。
- fallback 不记录 API key，不改 provider 设置，不把第三方 provider 的兼容行为写成永久 capability。

验证命令：

```bash
flutter test --no-pub \
  test/service/openai_responses_chat_model_test.dart \
  -r compact
```

### 2.14 当前书语义检索资源保护

用户路径：

1. 用户先为当前书构建本地 AI semantic index。
2. 用户在阅读页触发普通搜索、AI Seminar current-book evidence，或 agent tool 调用 `semantic_search_current_book`。
3. 系统嵌入 query 后先按 `bookId/provider/model` 调用 `AiVectorSearchBackend`。
4. 如果 provider/model/dim/bookId 对应的 per-book Vec1 sidecar 完整，向量后端先用 book-scoped ANN 召回，并只为 ANN winner 回查正文。
5. 如果 per-book ANN 不完整、Vec1 不可用或向量后端无结果，系统继续尝试用 `ai_chunks_fts` 取得 bounded FTS/BM25 候选 id，再进入 compact exact 或预算内 fallback 分页扫描。
6. 全局 Vec1 ANN 不参与 current-book recall；`vector_full_scan` native adapter 在 `bookId` 场景没有可验证预算时也会跳过。
7. 无论 ANN、候选预筛还是完整分页扫描，热路径只读取 vector 和 provenance 所需列，不读取 `text/raw_text/embedding_json`。
8. 系统维护 bounded topK 候选；ANN winner 和 FTS/BM25 candidate 命中同一 chunk 时按 chunk id 去重，保留高分候选，只为最终命中的 chunk 回查正文。
9. 如果旧索引 chunk 还没有 `embedding_blob`，系统按页批量回查 `embedding_json`，不做逐行 SQL 回查。
10. 同进程 current-book semantic search 通过全局 lock 串行化；agent tool registry 也把 `semantic_search_current_book` 标为非并发。
11. 每页向量解码和 cosine scoring 通过 `AiCurrentBookVectorPageScorer` seam 执行，默认使用 background isolate，避免长循环独占 UI isolate。
12. 阅读页新搜索、清空搜索或离开页面会 cancel stale semantic search；stale query 不写入 partial results。
13. 阅读页目录搜索进度条显示 semantic progress；progress 总量使用候选数或 fallback 扫描预算。
14. `semantic_search_current_book` 工具超时时会 cancel 底层 token 并返回 `cancelled=true` degrade；fallback 达到预算时返回带 message 的降级结果。

Gate：

- hot scan query 不允许选择 `text/raw_text/embedding_json`。
- current-book ANN 只能使用完整 per-book Vec1 sidecar；不得用全局 ANN topK 后过滤伪装 book-scoped recall。
- `vector_full_scan` native path 只有在能证明 book-scoped budget 时才能用于 current-book；当前 adapter 继续跳过该路径。
- FTS/BM25 预筛只允许取候选 id，不能把正文列带入向量扫描热路径。
- FTS5 缺失、MATCH 抛错或无候选时，阅读页、AI Seminar evidence 和 agent tool 路径必须提供 fallback vector scan budget。
- ANN、FTS/BM25 和 exact 候选合并时必须按 chunk id 去重，并保留更高分候选。
- topK 候选必须 bounded，不能把全书 scored rows 常驻内存。
- text/raw_text 只能为 winners 回查。
- JSON fallback 只能按页批量回查 blob 缺失行。
- 直接调用路径和 tool orchestrator 路径都不能并发扫描当前书。
- 阅读页 fallback 扫描上限为 1024 行；AI Seminar evidence 和 agent tool fallback 扫描上限为 2048 行；达到上限时不得继续扫描下一页。
- fallback progress 的 `totalRows` 必须使用预算后的行数，不能让 UI 误以为要扫完整本书。
- 向量 scoring 默认不得在 UI isolate 长循环执行；可替换 backend 必须保留 SourceRef provenance 所需字段。
- 取消后不得回查 winners 正文或写入 semantic results。
- 本切片不是发布级 ANN/sqlite-vec/Vec1 后端；per-book sidecar 不完整、无 FTS 候选且 compact exact 无结果时仍是预算内分页扫描；任何替换后端都必须继续保留 SourceRef 和 evidence gate。

验证命令：

```bash
flutter test --no-pub \
  test/service/rag/semantic_search_current_book_search_test.dart \
  test/providers/toc_search_test.dart \
  test/service/ai/tools/semantic_search_current_book_tool_test.dart \
  test/service/ai/tools/ai_tool_registry_governance_test.dart \
  -r compact
```

### 2.15 书库 Hybrid RAG 向量召回

用户路径：

1. 用户在 AI Chat、Seminar library fallback、agent tool 或其它书库 RAG 入口提出问题。
2. `semantic_search_library` 先执行 FTS/BM25 或 LIKE 文本召回，保留精确关键词候选。
3. 只要该入口允许 query embedding，系统同时调用 `AiVectorSearchBackend` 做语义召回。
4. 文本候选、RAPTOR/GraphRAG 全局层候选和向量召回候选进入同一个 RRF/hybrid/MMR/rerank 排序池。
5. 最终 evidence 仍只返回带 `SourceRef`、chunkId、jumpLink 和可保存 snippet 的 chunk。
6. 结果 JSON 中 `usedVectorRecall=true` 表示向量后端参与候选召回；`usedVectorFallback=true` 只表示文本召回没有候选时的向量兜底。

Gate：

- FTS/BM25 是精确文本召回层；向量后端是语义召回层；二者不能互相替代。
- 只要 `allowQueryEmbedding=true` 且入口允许向量召回，书库搜索必须调用 `AiVectorSearchBackend`，即使 FTS 已命中候选。
- ConceptGraph 空态、RAG KnowledgeCard 本地文本入口继续设置 `allowQueryEmbedding=false`、`allowVectorFallback=false`、`allowRerank=false`，不得外发正文。
- `usedVectorFallback=false` 不能被解释为没有语义召回；必须用 `usedVectorRecall` 判断向量后端是否参与。
- 默认 backend 是 ANN -> native -> exact；Vec1 不可用、ANN 表缺失、native shadow layer 不完整、native 不可用或 native 无结果时，exact backend 必须补足 recall，不得漏掉未升级书籍。
- exact backend 主扫描不得读取 `text/raw_text/context_text/embedding_json`，只能为缺 blob 行批量回查 JSON fallback，并只为 top winner hydrate 正文。
- 替换成 sqlite-vec/ANN backend 时必须保持 SourceRef、chunk evidence、RRF/hybrid/MMR/rerank contract。

验证命令：

```bash
flutter test --no-pub \
  test/service/rag/semantic_search_library_search_test.dart \
  test/service/rag/ai_vector_index_test.dart \
  test/service/ai/tools/semantic_search_library_tool_test.dart \
  -r compact
```

### 2.16 书库 exact 向量后端资源保护

用户路径：

1. 用户通过 AI Chat、Seminar library fallback 或 agent tool 触发书库 RAG。
2. `semantic_search_library` 调用默认 ANN -> native -> exact 后端做语义召回。
3. 当 Vec1/native 不可用或不完整时，exact fallback backend 先扫描 compact vector/provenance row，按 cosine 选出 top winner。
4. 只有 winner chunk 再回查 `text/raw_text/context_text/embedding_json`，用于 evidence snippet、MMR/rerank 和 SourceRef 输出。

Gate：

- 主扫描 SQL 不得选择 `c.text`、`c.raw_text`、`c.context_text` 或 `c.embedding_json`。
- 旧索引缺 `embedding_blob` 时，只允许对缺 blob 的扫描行批量回查 `embedding_json`，不得全表正文热扫。
- 返回给上层的 winner 仍必须带 `chapter_href`、`text/raw_text/context_text`、embedding metadata、provider/model 和 `local_vector_score`。
- 本切片只声明 extension-ready ANN search/build seam 和设置页前台 build action；sqlite-vec/ANN 发布能力仍需平台 package/extension、provider/model 失效和 overlap gate。

验证命令：

```bash
flutter test --no-pub \
  test/service/rag/ai_vector_index_test.dart \
  test/service/rag/ai_local_vector_index_test.dart \
  test/service/rag/semantic_search_library_search_test.dart \
  test/service/ai/tools/semantic_search_library_tool_test.dart \
  -r compact
```

### 2.17 旧索引向量层升级

用户路径：

1. 用户进入 `Settings -> AI Index / Library Index`。
2. 页面显示 `向量索引升级`。
3. 系统检查已完成书库索引中哪些书缺少 `ai_vector_index_rows` shadow rows。
4. 用户可点击顶部 `升级` 做批量 shadow row 补齐；也可在单本书行点击 `Upgrade vector layer / 升级向量层` 只补这本书。
5. 系统用已有 `embedding_blob` 或旧 `embedding_json` 写入紧凑 float32 shadow rows，不重新生成 embedding。
6. 顶部批量路径显示升级进度和取消按钮；取消后未处理书籍仍保留为可升级；单书路径完成后刷新该书行和顶部 native vector/ANN 状态。
7. 用户再点顶部 `ANN 向量索引 -> 构建` 时，系统从 shadow rows 重建 provider/model/dim 级全书库 Vec1 table，并同步生成 per-book Vec1 sidecar。
8. 如果某本书已有 compact vector rows 但 ANN sidecar 缺失，用户也可在该书行直接点 `Build ANN sidecar / 构建 ANN sidecar`，只为这本书生成 per-book Vec1 sidecar。
9. 后续检索默认先尝试 ANN，再降级 native SQL backend seam 和 exact backend；current-book 只在 per-book sidecar 完整时使用 book-scoped ANN。

Gate：

- 不外发正文，不调用 embedding provider，不重嵌入。
- 只处理实际存在 `ai_chunks` 且 `index_status=succeeded` 的旧索引书籍；`ai_book_index.chunk_count` 只能作为历史元数据展示，不得单独作为可补建依据。
- 缺失、损坏或空向量不得写入 shadow rows。
- 书籍删除和 chunk 删除必须显式清理 stale rows，不能只依赖后续 backfill 掩盖残留。
- 顶部 ANN 构建必须同时处理全书库 Vec1 table 和 per-book Vec1 sidecar；单书 ANN sidecar 构建只写目标书 per-book Vec1 sidecar，不得改写全局 ANN table 或全局 `vec1-ann` meta；删除书籍必须清理全书库 ANN 行和 per-book ANN 行。
- 页面必须显示进度、取消和完成/取消结果。
- 本切片不得宣称 sqlite-vec/ANN 发布完成；真实 native package/extension adapter、平台打包和 provider/model 失效仍需独立验收；候选 backend 必须复用现有 recall overlap gate。

验证命令：

```bash
flutter test --no-pub \
  test/service/rag/ai_native_vector_index_test.dart \
  test/service/rag/ai_index_schema_global_layers_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.18 当前书索引状态

用户路径：

1. 用户进入 `Settings -> AI -> Concept graph / 概念图谱`，或在阅读页选中文本后点击 `图谱/Graph`。
2. 如果入口带有当前 `bookId`，全书派生图谱区域会尝试读取当前书索引事实；纵向视图和宽屏双栏顶部都显示同一组状态。
3. 页面显示 `Book index readiness / 书籍索引状态`。
4. 用户可以分别看到 `Base index / 基础索引`、`Vector layer / 向量层`、`ANN`、`Global summary / 全局摘要层`、`Graph map / 图谱层` 的状态。
5. 基础索引失败时显示失败原因；基础索引缺失时提示先完成书籍 AI 索引；旧元数据声称有 chunk 但实际没有 `ai_chunks` 时显示缺失，不显示可补建全局层按钮。
6. native 向量层读取 `ai_vector_index_rows` 与已有 chunk embedding 的完成度。
7. ANN 读取 Vec1/sqlite-vec availability 和当前书 per-book sidecar 完整度；扩展未加载时显示 unavailable，并继续让检索路径降级。
8. 全局摘要层使用 RAPTOR node 数作为 durable marker；图谱节点为空但 RAPTOR 已存在时显示为空图谱层，而不是把整本书反复标为缺失。
9. 如果当前书缺全局层且已有基础 chunk 索引，空态仍显示 `立即生成全局层索引`，用户可在当前页补建单本书全局层。

Gate：

- readiness 只能读取本地 `ai_index.db` 派生缓存和当前书 `bookId`，不得外发正文或调用 embedding/model provider。
- 基础索引 ready/missing 必须以实际 `ai_chunks` 行数为准；陈旧的 `ai_book_index.chunk_count` 不得让书籍进入全局层补建或显示为 ready。
- 全局层是否存在必须以 RAPTOR node 为准，不能只用 graph node 数判断。
- ANN 未加载 extension 时必须显示 unavailable，不得误导为索引损坏或要求全量重建。
- 基础索引 failed reason 必须透传到状态层。
- 加载中不得使用无限动画占位挤压图谱交互；未加载完成前不改变现有图谱布局。
- 该状态层不自动触发全量重建；补建动作由用户点击当前书全局层补建、AI Index 行内 `Upgrade vector layer / Build ANN sidecar / Build global layer` 或 Settings AI Index 顶部批量入口触发。
- 宽屏双栏和 compact 图谱布局也必须展示同一组 readiness 状态；compact 只压缩长原因文案，不隐藏状态层。

验证命令：

```bash
flutter test --no-pub \
  test/service/rag/ai_book_index_readiness_test.dart \
  test/page/settings_page/concept_graph_explorer_page_test.dart \
  -r compact
```

## 3. 当前还不能用

这些能力没有产品入口或没有完成端到端验收，不应在用户沟通中描述为已经可用：

Seminar 补充边界：AI Chat `本次研讨设置` 已能为下一张任务卡临时覆盖角色 prompt、启用状态、current book/library/notes/memory/conceptGraph 证据范围、核验者和 `maxRounds`；ready 任务卡已能在卡内显示设置摘要、直接编辑本次研讨问题、调整最多讨论轮次、启用/停用角色、编辑启用角色本次 prompt、切换启用角色本次只读工具范围并切换启用角色 current book/library/notes/memory/conceptGraph 证据范围，且不写回全局 Settings；pending evidence tool-call 可见化首片、`review_triage` 异常预览详情首片、`contradiction_scan` 分歧扫描首片、contradiction evidence-gap 首片、evidence-gap 优先显示首片、多 evidence-gap 汇总首片、分歧扫描概览/下一步建议/优先处理队列首片、active `refreshEvidence` 保留旧 scan 队列并从 evidence-gap 优先项手动补证据首片、`refreshEvidence` Director state 首片、用户触发 `synthesize -> end` Director state pre-execute cue 与 end cue 验收、open child role status `可用控制` 显示、AI Chat 卡内可点击 `close-agent / 停止角色` 首片、AI Chat 卡内可点击 `wait-agent / 等待角色` graph refresh 首片、AI Chat 卡内可点击 `send-input / 发送输入` 输入记录首片和 active scoped runtime 消费首片、AI Chat 卡内可点击 `resume-agent / 继续角色` 继续请求首片和 active scoped runtime 消费首片、graph-store `close-agent` 执行语义、`user_input` event、`resume_request` event、control inbox + ack、status latest-only replay 以及 notes/memory/conceptGraph broker 独立检索首片已补。当前 pending evidence tool-call 只是 evidence broker 返回前按 `session.scopes` 显示 `调用中`，返回后由真实 result/evidence 覆盖；`停止角色` 只是关闭对应 child graph run 并刷新卡片为 `role-shutdown`，`等待角色` 只是从 graph store 拉取已落盘 child 最新状态/结果并刷新卡片；`发送输入` 会先把读者输入写成可恢复的 `user_input` event 并刷新为 `reader_turn(label=send-input)`，如果同 session active scoped runtime 仍存在且已有 evidence，会继续调用 `runPendingAgentControl(...)` 消费首个 pending `user_input`、让目标 role 追加 follow-up turn 并 ack，历史卡或无 active runtime 时仍只是恢复读者输入；`继续角色` 会先把继续意图写成可恢复的 `resume_request` event 并刷新为 `reader_turn(label=resume-agent)`，如果同 session active scoped runtime 仍存在且已有 evidence，会继续调用 `runPendingAgentControl(...)` 消费首个 pending `resume_request`、重新运行目标 role follow-up turn 并 ack，历史卡或无 active runtime 时仍只是恢复继续请求；它不代表真实 provider stream 硬中断、阻塞等待真实模型流或恢复旧 stream 继续生成；notes/memory/conceptGraph 检索的 streaming/tool-call 细化、完整 `sendInput/resumeAgent` 协作协议、真实 provider stream 中断/阻塞/恢复、完整 contradiction/rebuttal loop、自动反驳策略、完整异常详情表和完整 message part schema migration 仍未完成。

Seminar 可见状态补充：运行中的 current AI Chat Seminar 卡片点击普通主流程角色的 `停止角色` 后，后台 scoped runtime 会进入 cancelled，当前卡片也会显示 `研讨已停止`。这只是同一张 AI Chat 卡内的停止确认，不是旧 provider stream 原地续传，也不是完整 provider stream 硬中断/恢复协议。

Seminar 控制补充：用户点击 `等待角色` 后，如果同一个 child role 之后由 active scoped runtime 正常完成，当前 AI Chat 卡片会把这条等待记录从 pending 收口为 completed，并显示已完成角色结果；`发送输入 / 继续角色 / 重新生成角色` 由 active runtime 消费后，也会优先把 runtime 最新输出写回卡片，再刷新 graph。当前仍不是 provider stream 级别的阻塞等待或原地续传，而是可恢复事件和当前 runtime snapshot 的一致性补齐。

Seminar retry/restart 补充边界：失败 child role 的 `重新生成角色` 已能在 active scoped runtime 下复用同一个 child run id 重跑；重跑开始后 graph edge 会重新变成 open，历史 replay 也会隐藏被这次重启 supersede 的旧失败 terminal 和旧 partial，避免同一张 AI Chat 卡同时显示旧失败和新重跑状态。最新补充后，如果旧失败已经保存在历史卡 snapshot 里，而 graph replay 只补进同一 child run 的新 partial 或新完成结果，provider 合并层也会移除旧 `role-error`，只显示新的角色生成片段或完成回答；旧 `role-running / role-waiting-input / role-interrupted` 这类 transient 控制状态仍会保留，正常 `role-completed + role_turn` 也仍可并存。历史卡没有 active runtime 时仍只记录 pending retry request；这不是旧 provider stream 原地续传，也不是跨进程自动重启所有失败角色。

| 能力 | 当前边界 | 下一步 Agent Task | Gate |
| --- | --- | --- | --- |
| 完整云同步引擎 | 当前已有本地导出、机器可读 sync bundle、远端 bundle preview、`Check remote changes` 前台只读检查、远端同步状态面板、`Run safe remote sync` 前台安全编排、安全远端 incoming KnowledgeCard Review 导入、安全远端 review history Review 导入、安全远端 KnowledgeCard 冲突 staged Review 恢复、安全冲突 Review handoff、安全 KnowledgeCard 冲突本地恢复、Review Inbox 已审核安全冲突批量 apply/retry、只读 remote merge planner、本机 remotePath baseline 持久化、带 rollback snapshot 的 remote writeback executor 和 WebDAV ETag/CAS 条件写 guard；build `1.68.7+6514` 已把当前分支切片推到 TestFlight/GitHub 预发布，但还没有跨设备后台同步任务和完整迁移闭环。 | 继续拆跨设备后台同步、迁移说明和后续稳定版 release gate。 | API key 永不同步；冲突进入 Review；不得使用 whole-file newer-wins 覆盖用户资产；不能宣称后台跨设备自动同步已完成。 |
| AI Chat 原生 Seminar 仍未完整 | 当前 AI Chat 已有 `AI 研讨会` 入口、原生任务卡、卡内 `开始研讨`、`断点详情` 卡内展开、全局 `研讨会设置` 和单次 `本次研讨设置` 入口；Choose style 仍主要负责选择 active skill，不承载多角色讨论的证据刷新、用户插话和分歧回合。Seminar settings 已能保存角色显示名、custom prompt、启用状态、会话证据提示和只读工具范围，并注入新 Seminar session；AI Chat `本次研讨设置` 能为下一张任务卡临时设置当前问题、角色 prompt、启用状态、核验者和 `maxRounds`，不写回全局 Settings；ready 任务卡也可直接编辑本次研讨问题、启用角色本次 prompt 和启用角色本次只读工具范围，并只回写同一张卡；disabled role 会从新 run 跳过，会话证据提示会合并进 session scopes，写工具、联网工具、unknown tool 和 `spawn_sub_agent` 会被过滤；任务卡可随 runtime 状态回写 toolCalls/evidence/role/synthesis snapshot，`调用` 子视图会显示证据收集的工具名、查询、结果数量、可见角色、运行追踪和返回证据，并在 snapshot 内显示 `研讨白板` 中的分歧和开放问题正文；AI Chat 原生任务卡 snapshot、卡内开始/续跑和卡内 `异常送审` 已按 `seminarSessionId` 使用 scoped runtime，普通 assistant 回答的 KnowledgeCard/Memory/regenerate 动作仍不出现在 Seminar 卡片上；`AiSeminarDirectorState` 已能保存 Director 账本，并在 completed run 后根据 whiteboard 自动标记下一步：open question -> `askUser`，disagreement + 轮次预算 -> `refreshEvidence`，页面状态区显示主持人下一步；`askUser` 状态下页面提供用户回复输入框、动作 chips、目标角色选择和 `执行选中动作` 按钮，用户输入只写 `lastUserIntervention`，其中“让所选角色回应”会执行目标角色 follow-up turn 并更新 synthesis，“重新找证据”会重新检索 evidence、重跑角色并更新 synthesis，“整理总结”会用现有 evidence 和 turns 执行本地 synthesis 并收束 Director；completed run 即使没有 open question，也会在 synthesis 后提供 `Continue discussion / 继续讨论`，让用户继续追问角色、刷新证据或重新整理总结，输入仍只写 `lastUserIntervention`；completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，runtime 会自动刷新 evidence、重跑角色，并在刷新后仍有分歧且预算耗尽时转为 `askUser`；独立真实角色工具调用 loop 和完整 Director 每轮调度仍未接入。 | 继续拆完整 Chat run 子视图、真正 contradiction/rebuttal loop、run-scoped composer 和同源 AI Chat 详情状态。 | 同一讨论按 `seminarSessionId` 隔离 runtime；AI Chat 原生任务卡与 runtime store 已共享 SourceRef、turn ledger、budget 与 Review handoff；旧独立详情页已删除，后续详情能力必须继续在 AI Chat 同源状态内补齐；用户插话不得被当作 AI evidence；重新检索必须保留 current book first 和默认不开 web；角色工具范围不得绕过 E06 工具权限矩阵。 |
| Seminar OS 后台执行、queued job 重启确认和 provider 发票导入 | Seminar runtime 已能流式、取消、重试、Review handoff，并显示 provider readiness、capability cache、成本未知原因、provider token usage、本地 token 估算 fallback、本地 role/run token budget、pricing metadata 驱动的估算 `Run cost cap USD`、billing snapshot / reconciliation UI、本机 state 恢复、当前 `Background job` snapshot、最近本机 job 账本、本机串行 queued job scheduler 和 traceable evidence checkpoint resume；running state 重启后如果已有可追踪 evidence 且 provider/model/pricing 仍匹配当前配置，会保留 job id、复用已保存 evidence，并从第一个缺失角色继续；已有 completed role prefix 会跳过不重跑，只有 active partial stream 时丢弃 partial 并重新生成缺失角色；同一恢复快照里带完整 session 的 queued job 会继续排队并在 active 续跑完成后启动；checkpoint 无效、evidence 不可追踪、provider 已切换、没有可恢复 active job 或 queued job 缺少 session 时会标记为 interrupted/retryable。当前没有并发并行 Seminar、OS/background execution gate、旧 LLM stream 原地续传，也没有连接 provider invoice import API；UI 会把估算成本、provider usage metadata、pricing source 和 invoice reconciliation 状态分开展示。 | 拆分 OS/background execution gate、provider request idempotency 和 queued job 跨设备确认；真实 provider invoice import 另拆 provider-specific adapter、鉴权、只读账单导入和失败恢复 gate。 | 移动资源 gate；长任务可取消、失败可恢复或重试；无 pricing metadata 时继续显示成本未知原因并禁用美元 cap；估算美元成本不等于 provider 发票；本地 token budget 不得声明为 provider billing cap；不能把本机 recovery cache 当作同步资产；不得把 job 账本、queued job 或 interrupted snapshot 描述成 OS 后台继续生成；恢复续跑必须说明会重新调用 provider 生成缺失角色。 |
| sqlite-vec/ANN 实验后端 | 当前书语义搜索已接入 book-scoped `AiVectorSearchBackend` 优先召回，并保留 per-book Vec1 sidecar、ANN/FTS chunk 去重、分页、topK、串行、background isolate scoring、取消 token、progress callback、阅读页 stale query cancel、工具超时 cancel、bounded FTS/BM25 候选预筛、fallback scan budget 和 synthetic large-book scan acceptance；书库 RAG 已进入 hybrid recall：向量后端和 FTS/BM25 一起召回，不再只在文本 miss 后兜底；exact fallback backend 主扫描不再加载正文大字段；当前 `kAiIndexDbVersion = 12`，已有 `ai_vector_index_rows/meta` shadow schema、旧索引向量层升级入口、Vec1 table builder、全书库 Vec1 table、per-book Vec1 sidecar、`vec1-ann` meta、ANN -> native -> exact backend、设置页 ANN 构建入口、删除书籍派生索引清理和固定 fixture ANN/exact overlap gate。仍不是已打包的 ANN/Vec1/sqlite-vec 发布后端：书库无 `bookId` 检索可在 Vec1 extension/table 存在时使用 ANN；当前书 `bookId` 检索只使用完整 per-book Vec1 sidecar，不使用全局 Vec1 ANN 后过滤，也不走无预算 `vector_full_scan` native path；后端无结果且无 FTS 候选时仍是预算内分页扫描。 | 拆真实 sqlite-vec/Vec1 package/extension adapter、平台打包、可恢复 ANN build job、provider/model 失效和真机资源 gate；候选 ANN backend 必须继续接入 `AiVectorRecallOverlapGate`，book-scoped 验收必须传入同一 `bookId`。 | 不得牺牲 SourceRef；无 evidence 不返回正式结果；旧 DB、无 embedding、FTS5 缺失、书籍删除和 provider 切换都有 degrade path；移动端大书搜索必须有取消或可恢复状态；ANN topK 与 exact backend 必须通过固定 fixture 重合率验收。 |
| 复杂无限画布式 ConceptGraph | 当前是局部图谱、dossier、路径、摘要、轻量节点-连线 canvas 和当前书全局层的只读派生图谱预览，不做无限画布、缩放手势或跨书外部知识扩展。 | 如需画布，先定义移动端资源、证据可见性和 graph ownership gate。 | 关系必须有 evidence；正式关系必须 Review apply。 |
| 发布版可用 | `2026-06-08` 已把发布目标 commit `cbf073aabcfb61ca410819f52ee19dfaa380a57a` 发布为 build `1.68.7+6514`：TestFlight/ASC build `6514` 状态为 `VALID`，GitHub Release `android-v1.68.7-6514` 包含 Android APK、macOS unsigned app zip 和 `CHECKSUMS.txt`。这只代表这个 commit 的预发布切片可通过对应 TestFlight/GitHub release 获取，不代表 `main`、稳定版或所有已安装用户都已包含，也不代表 v7 全部完成。 | 后续继续走 P1-P4 完整 gate、迁移说明、跨设备同步和稳定版 release promotion。 | 发布前必须重跑权威验证命令并记录 commit；用户沟通必须写明 build 号、commit 和仍未完成的功能边界。 |

## 4. 用户入口任务验收状态

这张表是分支内的 agent task 台账，不是发布排期。`Accepted` 表示在当前分支已有代码和测试证据；`In Review` 表示已有切片但仍有上表列出的用户证据或发布 gate 未完成。

| TaskID | 状态 | Parent Capability | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| UFA-C01-T01 | Accepted | Selection KnowledgeCard | 选中文本生成 draft KnowledgeCard，旧 Review producer 路径保留为兼容。 | E00 SourceRef, E03 store, E05 ReviewItemStore | `SelectionKnowledgeCardProducer` | 已通过 producer 测试：默认 `createReviewItem=false` 生成 draft KnowledgeCard、保留 SourceRef、不写 ReviewItem；显式 `createReviewItem=true` 才生成 pending KnowledgeCard/ReviewItem 兼容路径，重复点击不重复写入。 |
| UFA-C01-T02 | Accepted | Selection KnowledgeCard | 阅读页选中菜单显示 `知识卡` 并内联保存。 | UFA-C01-T01, E07 menu | `ExcerptMenu` action, l10n keys, reader context fallback resolver | widget 覆盖 `Card/Seminar/Graph` 入口可见；点击 `Card` 调用 selection KnowledgeCard producer，传入 book/cfi/选中文本/标题上下文，显示 `Saved as draft knowledge card / 已保存为草稿知识卡` 并关闭菜单；无注入 context/creator 的点击级测试覆盖 reader context fallback resolver 和默认 `SelectionKnowledgeCardProducer(createReviewItem:false)` 文件 store 写入，验证 draft KnowledgeCard、SourceRef、无 ReviewItem、重复点击不重复写。生产默认 resolver 仍读取 `epubPlayerKey.currentState`。 |
| UFA-C01-T03 | Accepted | Image Analysis KnowledgeCard | 图片解析结果生成 draft KnowledgeCard，旧 Review producer 路径保留为兼容。 | E00 SourceRef, E03 store, E05 ReviewItemStore, E07 image analysis sheet | `ImageAnalysisKnowledgeCardProducer`, `AiImageAnalysisSheet` Card action, `ImageViewer` analysis/card seams | 图片解析结果弹层显示 `Card` 入口；producer 默认 `createReviewItem=false`，生成 draft KnowledgeCard、保留 book/cfi/href SourceRef、不写 ReviewItem、不保存图片本体/base64；显式 `createReviewItem=true` 仍覆盖旧 pending KnowledgeCard/ReviewItem 兼容路径；ImageViewer 工具栏点击 `AI Image Analysis` 后使用可注入分析流打开弹层，点击 `Card` 保存 draft image-analysis KnowledgeCard，并显示 `Saved as draft knowledge card / 已保存为草稿知识卡`。 |
| UFA-C01-T04 | Accepted | RAG Evidence KnowledgeCard | 本地 RAG/GraphRAG evidence 生成 draft KnowledgeCard，旧 Review producer 路径保留为兼容。 | E00 SourceRef, E02 RAG evidence, E03 store, E05 ReviewItemStore, E07 ConceptGraph empty state | `RagEvidenceKnowledgeCardProducer`, `ConceptGraphExplorerNotifier.createKnowledgeCardFromLibrarySearch`, 空态 `Card` action | 只有 traceable chunk SourceRef 且带可保存 chunk snippet 的 RAG evidence 能写 KnowledgeCard；derived summary 不替代书内 chunk evidence；ConceptGraph 空态 `Card` 走默认非送审路径，保存 draft KnowledgeCard、显示 `Saved as draft knowledge card / 已保存为草稿知识卡`、不写 ReviewItem、不进入 Review Inbox；显式 `createReviewItem=true` 才保留 pending KnowledgeCard/ReviewItem 兼容路径；不写正式图谱、长期资产或 spaced review。 |
| UFA-C01-T05 | Accepted | AI Chat KnowledgeCard | AI Chat 回答显式生成 draft KnowledgeCard，旧 Review producer 路径保留为兼容。 | E00 SourceRef, E03 store, E05 ReviewItemStore, E07 AI Chat message action | `AiChatKnowledgeCardProducer`, `AiChatStream` 回答旁 `知识卡` action, answer-side source status chip, `ExcerptMenu` AI sourceRef handoff, `conversationV2` user-node SourceRef persistence | 回答完成后才可点击 `知识卡`，streaming 中按钮禁用且 producer 调用数为零；普通点击默认 `createReviewItem=false`，保存 draft KnowledgeCard、显示 `Saved as draft knowledge card / 已保存为草稿知识卡`、不写 ReviewItem；显式 `createReviewItem=true` 仍覆盖旧 pending KnowledgeCard/ReviewItem 兼容路径；回答旁显示可跳转或不可用来源状态；选中文本进入 AI 草稿且发送内容仍包含原选中文本或 SourceRef snippet 时，才保留并持久化精确 reader SourceRef；历史重载后 `知识卡` 仍优先使用原始 reader SourceRef；无关改写不保存旧 reader SourceRef；短公共片段碰巧命中不保存旧 reader SourceRef；reader-grounded card 带保守 `conceptRefs`，纯聊天 card 不带；重复点击不制造重复卡；不直接写 ConceptGraph、长期记忆、笔记或 spaced review。 |
| UFA-C01-T06 | Accepted | Selected-text AI launcher widget evidence | 阅读页选中文本 `AI` 按钮点击级 widget 测试，证明会打开 AI chat draft 并传 reader SourceRef。 | UFA-C01-T05, E07 menu | `ExcerptMenu.aiChatDraftOpener` seam, `ExcerptMenu` AI action widget tests | 点击 `AI` 后草稿包含选中文本；有效 `bookId + cfi` SourceRef 被传入 chat；无有效 anchor 时不伪造 reader grounding。 |
| UFA-C02-T01 | Accepted | Seminar launcher | 阅读页选中菜单显示 `研讨`，写入 AI Chat 原生 Seminar 任务卡。 | AI Seminar runtime, E07 menu | `ExcerptMenu` action | 入口可见；选中文本预填；不自动写用户资产。 |
| UFA-C02-T02 | Accepted | Structured Seminar runtime UI | 把 `AiSeminarOrchestrationService` 接入真实模型流式事件。 | E01 services, E06 governance, E07 progress UI | `AiSeminarRuntimeService`、`aiSeminarRuntimeProvider`、AI Chat 原生 `seminarRunCard` / `messageParts` | 角色 turn、evidence、whiteboard、synthesis 进入可序列化 runtime state，并回写同一张 AI Chat Seminar 卡；失败可重试，运行可取消；旧独立运行页面不是验收入口。 |
| UFA-C02-T03 | Accepted | Seminar Review handoff | Seminar synthesis 和候选卡进入 Review Inbox。 | UFA-C02-T02, E05 controller | `AiSeminarRuntimeNotifier.sendToReview` + `SeminarSynthesisReviewAdapter` | 只有 `readyForReview + traceable handoff` 的 synthesis 进入 pending Review；候选卡保持 AI draft/pending，不直接应用；页面级 widget 覆盖用户点击 `Start Seminar` 后再点击 `异常送审`，并断言 synthesis、KnowledgeCard ReviewItem 和 seminar KnowledgeCard 均为 pending/draft 边界。 |
| UFA-C02-T04 | Accepted | Seminar Flashcard handoff | Seminar reviewSuggestion 进入 flashcard Review。 | UFA-C02-T03, UFA-C04-T01 | `SeminarSynthesisReviewAdapter.flashcardsFromSynthesis`, `FlashcardReviewAdapter`, `ReviewInboxController` | 只有 traceable synthesis 的 candidate review question 会生成 pending flashcard；页面级 widget 覆盖 `异常送审` 后 flashcard candidate 进入 pending ReviewItem；用户 Apply 后进入 Spaced Review；该旧兼容 flashcard 路径不绕过 Review。 |
| UFA-C02-T05 | Accepted | Seminar provider readiness | AI Chat Seminar 启动前显示当前 provider/model/capability 和成本透明度。 | Provider Center capability cache, UFA-C02-T02 | `AiSeminarProviderContextService`, `AiSeminarRuntimeState.providerDiagnostics`, AI Chat Seminar provider readiness section | 从 `Prefs.selectedAiService`、provider metadata、AI config 和 `AiModelCapability` cache 解析 provider/model/context/max output/Tools/Vision/Thinking/pricing metadata；当前 schema 没有 streaming 字段时显示 `Streaming unknown`，不伪造支持；runtime `start` 前捕获 diagnostics 并随 state JSON restore；页面显示 `Provider readiness`、capability chips、缺少 pricing metadata 时的 `Cost: unknown` 和原因，有 pricing metadata 时显示可用于 estimated USD cap；不读取或展示 API key，不把估算成本声明为真实账单。 |
| UFA-C02-T06 | Accepted | Seminar local token usage | Seminar 角色输出显示本地 token 估算并随 runtime state 恢复。 | UFA-C02-T02, UFA-C02-T05 | `AiSeminarTokenUsage`, `AiSeminarRuntimeService` local estimator, AI Chat Seminar usage/status blocks | 每个通过 evidence gate 的 completed role turn 都写入 `tokenUsage(inputTokens/outputTokens/isEstimated/estimationMethod=local-char-estimate-v1)`；`AiSeminarRun` 聚合 usage，state JSON restore 保留 turn/run usage；AI Chat Seminar 卡显示 `Local token estimate`、input/output 和 `Provider billing may differ`，继续显示 `Cost: unknown`，不读取 API key，不调用 provider，不把本地估算当作美元成本。 |
| UFA-C02-T07 | Accepted | Seminar local recovery | Seminar runtime state 保存为本机恢复缓存，重新打开同一 AI Chat Seminar 卡可恢复同一入口的已完成或已中断状态。 | UFA-C02-T02, UFA-C02-T06, E07 recovery gate | `aiSeminarRuntimeStateV1:<seminarSessionId>`, `AiSeminarRuntimeNotifier` persistence/restore, AI Chat Seminar recovered/checkpoint banner, prefs backup skip | completed/cancelled/failed state 会写入本机 scoped 缓存；AI Chat native run 使用 `aiSeminarRuntimeStateV1:<seminarSessionId>`；同一书籍/同一入口问题和同一 `seminarSessionId` 的 AI Chat 卡会恢复 state 并显示 `Recovered local Seminar state` 或卡内 checkpoint 操作；换书、换选区或换 session 会清掉旧 runtime/cache，不展示旧研讨；traceable evidence checkpoint 的 running 恢复由 `UFA-C02-T16` 接管；checkpoint 无效、evidence 不可追踪或 provider 已切换时降级为 cancelled/interrupted 且 `canRetry=true`，并回写清理 active role / partial text；scoped 缓存被普通 prefs backup 排除，不同步，不导出 API key 或正文到 backup；恢复态保留生成时保存的 provider/model diagnostics，retry 时再使用当前 provider 设置；旧 Settings 独立运行页不再作为恢复入口。 |
| UFA-C02-T08 | Accepted | Seminar local token budgets | 用户在 AI Chat Seminar 配置中设置本地 role/run token budget，并在超限时停止后续步骤。 | UFA-C02-T06, mobile resource gate | `AiSeminarBudgetPolicy`, `AiSeminarRuntimeService` budget gate, AI Chat Seminar local budget guardrails | Session contract round-trip 保存 `maxRoleOutputTokens/maxRunTokens`；页面显示 `Local budget guardrails`、`Role output token budget` 和 `Run token budget`；runtime 用 `local-char-estimate-v1` 判断 token 超限，流式 partial 超出 role output budget 时取消 active stream，completed turn 超出 role/run budget 时停止后续步骤；超限进入 failed/retryable，不生成 synthesis，不发送 Review；restore/retry 保留 session budget policy；不把本地 token 预算冒充 provider billing 或美元成本上限。 |
| UFA-C02-T09 | Accepted | Seminar provider token usage | provider/SDK 返回 token usage metadata 时，Seminar turn/run 保存并显示 provider-reported token usage。 | UFA-C02-T06, UFA-C02-T08 | `CancelableLangchainRunner.stream`, `AiUsageTracker`, `AiSeminarModelRoleExecutor`, `AiSeminarTokenUsage.source`, AI Chat Seminar usage/status blocks | 非 agent stream 完成后把 provider usage 记录到会话 tracker；role executor 按 session usage tracker 前后差值写入 `provider-reported` tokenUsage；run 聚合 provider/local mixed usage；AI Chat Seminar 卡显示 `Provider reported usage` 或 mixed/local fallback；local role/run token budget 仍只使用 `local-char-estimate-v1`；provider token usage 只作为估算成本输入之一，不等于真实账单。 |
| UFA-C02-T10 | Accepted | Seminar estimated USD cost cap | 用户在 AI Chat Seminar 配置中设置估算 `Run cost cap USD`，超出时停止后续步骤。 | UFA-C02-T05, UFA-C02-T09 | `AiModelCapability` pricing metadata, `AiSeminarBudgetPolicy.maxRunCostUsd`, `AiSeminarRuntimeService` cost gate, AI Chat Seminar cost cap UI | Provider capability cache 带 input/output/cache pricing metadata 时，页面启用 `Run cost cap USD` 并显示 pricing source；session/run JSON round-trip 保存 pricing policy 和 estimated cost；runtime 聚合 provider-reported usage 或本地 fallback usage 估算美元成本，超出 cap 时进入 failed/retryable、保留已完成 turn、不生成 synthesis、不发送 Review；无 pricing metadata 时禁用 cost cap 并显示原因；估算成本不声明为 provider invoice。 |
| UFA-C02-T11 | Accepted | Seminar background job snapshot | 把 Seminar running state 接入可取消的本机 job snapshot，并为恢复语义保留 job id。 | UFA-C02-T07, mobile resource gate | `AiSeminarBackgroundJobSnapshot`, `AiSeminarRuntimeState.backgroundJob`, `AiSeminarRuntimeNotifier` job lifecycle, AI Chat Seminar job status block | 启动会持久化 running job id；completed/needsEvidence/failed/cancelled 会写终态；cancel 会标记 cancelled；retry 会生成新 job id；有 traceable evidence checkpoint 的 persisted running 由 `UFA-C02-T16` 复用同一 job id 继续缺失角色；同一恢复快照里带完整 session 的 queued job 可继续排队；checkpoint 无效、evidence 不可追踪、provider 已切换、没有可恢复 active job 或 queued job 缺少 session 时标记 interrupted/retryable，且不生成 synthesis、不开放 Review；AI Chat Seminar 卡显示 `Background job: <status> · <id>`；不含 API key，不同步；不是并发队列，也不是旧 LLM stream 原地续传。 |
| UFA-C02-T12 | Accepted | Provider billing reconciliation | 记录 provider pricing source/optional version/usage snapshot，并在 UI 中区分 estimate、provider metadata 和 invoice reconciliation。 | UFA-C02-T10 | `AiSeminarBillingContext`、`AiSeminarBillingSnapshot`、`AiSeminarRuntimeService` billing snapshot、AI Chat Seminar billing/status blocks | 每个有 token usage 的终态 Seminar run 保存 usage snapshot、provider/model、pricing source/optional version、pricing captured time、估算 USD 和 invoice status；AI Chat Seminar 卡显示 `Estimated cost, not invoice`、`Usage snapshot`、`Pricing snapshot` 和 `Invoice reconciliation`；默认 invoice import 未连接时显示 `Not connected` 和原因；已覆盖 snapshot round-trip、runtime not-connected 状态和卡内展示；不把 local budget 或 estimated USD cap 声明为真实扣费上限。 |
| UFA-C02-T13 | Accepted | Selected-text Seminar SourceRef seed | 阅读页选中文本 `研讨` 入口把真实 reader SourceRef 写入 Seminar session，并作为优先 evidence seed。 | UFA-C02-T01, E00 SourceRef, E01 evidence broker, E07 menu | `AiSeminarSessionContract.sourceRefs`, `AiSeminarEvidenceBroker`, AI Chat native Seminar task card SourceRef handoff, `ExcerptMenu` seminar launcher | session JSON round-trip 保留 reader SourceRef；点击 `研讨` 后 AI Chat Seminar task card/session 持有 bookId/CFI/snippet/sourceKind；`Start Seminar` 把 SourceRef 传入 session，evidence broker 先生成 `Reader selection` evidence，再执行 current-book search；runtime provider 重建 session 时保留 sourceRefs；同书同问题但 CFI/SourceRef 不同时会丢弃旧本机恢复缓存；hash-only、不可追踪或无 snippet 的 SourceRef 不进入 formal evidence。 |
| UFA-C02-T14 | Accepted | Seminar background job ledger | 本机保存最近 Seminar job 账本，并让取消操作只命中对应 job。 | UFA-C02-T11, mobile resource gate | `AiSeminarRuntimeState.backgroundJobs`, `AiSeminarRuntimeNotifier.cancelBackgroundJob`, `aiSeminarRuntimeStateV1` / scoped JSON | 多次 Seminar run 会在本机 runtime cache 中保留去重后的最近 job 记录；`backgroundJob` 仍代表当前页面显示的当前 job；AI Chat scoped runtime 使用 scoped cache 保存账本，legacy Settings 入口使用 global cache；terminal event 会同步更新账本中的对应 job；旧 terminal job id 调用 `cancelBackgroundJob` 不影响当前运行；当前 job id 会走同一 cancel lifecycle；不同 scoped runtime 的模型调用由本机 coordinator 串行化；账本不含 API key，不同步，不表示进程死亡后继续 stream。 |
| UFA-C02-T15 | Accepted | Seminar local serial queue | 运行中再次启动 Seminar 时进入本机串行 queued job，并在 AI Chat 卡内可见和可取消。 | UFA-C02-T14, mobile resource gate | `AiSeminarBackgroundJobStatus.queued`, queued `AiSeminarBackgroundJobSnapshot.session`, `AiSeminarRuntimeNotifier` serial scheduler, AI Chat Seminar `Queue Seminar` / `Seminar job queue` controls | active Seminar 运行中再次点击会创建 queued job，不取消 active token；当前 job 进入 completed/failed/cancelled/needs-evidence 后才启动下一条 queued job；queued 真正启动前会按当前 provider diagnostics 重新绑定 billing context 和 budget policy；取消 queued job 不取消 active stream；本机恢复时如果没有可续跑 active checkpoint，queued job 标记为 interrupted，不自动继续生成；同一恢复快照存在可续跑 active 且 queued 带完整 session 时，queued 保持 queued 并在 active 续跑完成后启动；AI Chat Seminar 卡显示 running/queued job 和问题文本；测试覆盖 provider scheduler、provider switch rebind、queued cancel、restore interrupted 和卡内点击路径；不是并行执行、不是 OS/background execution，也不是 provider invoice import。 |
| UFA-C02-T16 | Accepted | Seminar checkpoint resume | App 重启后从 traceable evidence checkpoint 继续 Seminar。 | UFA-C02-T07, UFA-C02-T11, UFA-C02-T15, mobile resource gate | `AiSeminarRuntimeCheckpoint`, `AiSeminarRuntimeService.run(checkpoint:)`, `AiSeminarRuntimeNotifier.resumeRestoredRunning`, `AiSeminarRuntimeState.canResumeRestoredRunning` | 恢复只信任可追踪 evidence、合法连续 completed role prefix 和当前匹配的 provider/model/pricing；加载本机 checkpoint 后先展示断点详情和 `继续 / Resume` 操作，不在 notifier/page 初始化时自动外发 provider 请求；用户确认继续后复用持久化 evidence bundle，不重新 fetch evidence；已有 completed role 不重跑，缺 tokenUsage 的 checkpoint turn 会补 `local-char-estimate-v1`，避免终态 usage/cost 漏算；没有 completed turn 但已有 evidence 时从首个角色重新生成；只有 active partial stream 时丢弃半截文本并重新生成缺失角色；继续时保留原 background job id；同一恢复快照里带完整 session 的 queued job 会保持 queued，并在 active 续跑完成后自动启动；checkpoint 无效、evidence 不可追踪、provider 已切换、没有可恢复 active job 或 queued job 缺少 session 时标记 interrupted/retryable；dispose 后不得写已销毁 notifier；不是 OS/background execution，也不是旧 LLM stream 原地续传。 |
| UFA-C02-T17 | In Review slice | Chat Seminar DirectorState | 把 Seminar 从固定角色顺序推进为 AI Chat 可恢复 Director loop。 | UFA-C02-T16, E01-C05-T01 | `AiSeminarDirectorState`、`AiSeminarRuntimeState.directorState`、runtime JSON、tests | 第一片已接入：DirectorState 可记录轮次、已完成角色、已完成 turn id、证据账本、白板账本、分歧 id、证据刷新次数、用户插话状态和下一步 intent；runtime state JSON 可恢复该账本；用户插话明确不是 formal evidence；恢复时已有 `remainingRolesFor` 可跳过已完成角色；completed run 留下 open question 时会标记 `askUser`，留下 disagreement 且有轮次预算时会标记 `refreshEvidence`，状态区显示主持人下一步；用户提交回复后写入 `lastUserIntervention` 并把下一步 intent 转成 `runRole / refreshEvidence / synthesize`；`runRole` 已能通过 `executeDirectorNextStep` 调用目标角色生成 follow-up turn，用户触发的 `refreshEvidence` 已能重新检索 evidence、重跑角色并更新 synthesis，用户触发的 `synthesize` 已能用现有 evidence/turns 执行本地 synthesis 并收束为 `end`；completed run 即使没有 open question，也会在 synthesis 后显示 `Continue discussion / 继续讨论` 并保存读者回合；completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，会自动刷新 evidence 并重跑角色，刷新后仍有分歧且预算耗尽时转为 `askUser`。AI Chat 历史任务卡已能回写 evidence/role/synthesis snapshot；AI Chat inline runtime、任务卡状态读取和卡内异常送审已按 `seminarSessionId` 隔离 scoped runtime；仍需完整 rebuttal loop、结构化白板详情和 run-scoped composer；不得生成第二套 Seminar runtime state。 |
| UFA-C02-T18 | In Review slice | Seminar role prompt settings | 用户可编辑多角色提示词和角色策略。 | UFA-C02-T17, E06 governance | `AiSeminarRoleProfile`、`Prefs.aiSeminarRoleProfiles`、`AiSeminarConfigPage` role profile fields、AI Chat `本次研讨设置`、runtime prompt injection | 已完成 Settings 全局默认和 AI Chat 本次 run 第一片：默认角色保留 `critical/supportive/synthesizer/verifier`；设置页可保存显示名、custom prompt、启用状态、会话证据提示和允许的只读工具；AI Chat `+ -> AI 研讨会` 的调参按钮可打开 `本次研讨设置`，只为下一张任务卡设置当前问题、角色 prompt、启用状态、核验者和 `maxRounds`，不写回全局 Settings；ready 任务卡也可直接编辑本次研讨问题、启用角色本次 prompt 和启用角色本次只读工具范围，并只回写同一张卡；新 session 会把 profile 写入 `AiSeminarSessionContract` 并注入 role prompt；session JSON 与 provider budget rewrite 不丢 profile；disabled role 会从 session execution order 和 AI Chat Seminar 任务卡 role ids 中跳过，全部关闭时降级为 `synthesizer`；角色 profile 的会话证据提示会合并到 session scopes；疑似密钥的 custom prompt 会被丢弃；写工具、联网工具、unknown tool 和递归 `spawn_sub_agent` 会被过滤。`memory_search` 和 `concept_graph_search` 已是可注册/可过滤的受控只读工具，其中 `concept_graph_search` 已有真实工具定义并只返回可追溯图谱节点/关系。剩余部分是空 prompt 显式提示、角色级预算和完整真实角色工具调用 loop；当前工具范围不代表角色可以任意调用工具。 |
| UFA-C02-T19 | In Review slice | Multi-round evidence refresh | 讨论出现分歧或证据不足时，Director 可以重新检索并进入反驳轮。 | UFA-C02-T17, UFA-C07-T05 | Director loop service、contradiction scan、evidence refresh tests | 已完成用户触发和自动触发的 evidence refresh 执行路径：用户在 `askUser` 状态选择“重新找证据”后点击 `执行选中动作`后，runtime 会重新调用 evidence broker、保留 current book first、重跑角色并更新 synthesis；completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，runtime 会在启动 queued job 前自动刷新 evidence 并重跑角色；每次刷新后的 evidence 仍需 SourceRef，刷新后仍有分歧且预算耗尽时转为 `askUser`。AI Chat 历史任务卡已能回写被引用 evidence 的快照、角色观点和总结；仍需覆盖结构化 contradiction gap scan、角色针锋相对的 rebuttal turn 和完整 Chat run card 子视图；默认不开 web。 |
| UFA-C02-T20 | In Review slice | User-in-the-loop Seminar | 用户能在 AI Chat 中插话、指定追问角色或回答澄清问题。 | UFA-C02-T17, E07 Chat UI | `AiSeminarUserIntervention`、`AiSeminarRuntimeNotifier.recordUserIntervention`、`AiSeminarRuntimeNotifier.executeDirectorNextStep`、`AiSeminarRuntimeService.runUserDirectedRole`、AI Chat native `reader_composer` / `reader_turn` UI、tests | 第一片已接入：Director 可进入 `needsUserInput`；AI Chat Seminar 卡显示用户回复输入框、动作 chips、目标角色选择和 `执行选中动作` 按钮；用户输入保留为 `lastUserIntervention` human turn，不写 `evidenceBundle`、不当作 AI evidence；选择“让角色回应”后点击 `执行选中动作`会把用户输入注入目标角色 prompt，调用所选角色生成 follow-up turn，并用现有 evidence 与 prior turns 更新 synthesis；选择“重新找证据”后点击 `执行选中动作`会保存 human intervention、重新检索 evidence、重跑角色并更新 synthesis；选择“整理总结”后点击 `执行选中动作`会保存 human intervention，用现有 evidence 与 turns 执行本地 synthesis，并把 Director 收束为 `end`；completed run 没有 Director 提问时也显示 `Continue discussion / 继续讨论`，允许用户继续推动角色或证据刷新。AI Chat 历史任务卡已有只读 snapshot；仍需完整 Chat run card 子视图。 |
| UFA-C02-T21 | In Review slice | AI Chat Seminar run card | 在 AI Chat 内展示多角色讨论，而不是强制跳到独立 Seminar 页面。 | UFA-C02-T17, UFA-C02-T20 | AI Chat native run card entry、`AiSeminarRunCardMeta` / `AiSeminarRunCardSnapshot`、scoped Seminar runtime service、l10n | 已完成最新片：AI Chat `+` -> `AI 研讨会` 不再默认展开 Seminar runtime panel，而是在当前 `conversationV2` 追加用户问题和带 `seminarRunCard` meta 的 assistant fallback message；待开始且没有运行结果 snapshot（或只有 setup-only snapshot）的任务卡显示 `本次设置` 摘要、卡内本次研讨问题编辑、最大轮次调整、角色启用开关、启用角色本次 prompt 编辑、启用角色 current book/library/notes/memory/conceptGraph 证据范围切换、启用角色本次只读工具范围切换和 `开始研讨`，点击后用同一张卡的 session、问题、SourceRef、角色、轮次和本次角色配置启动 scoped runtime，点击卡片正文不会打开面板；ready 卡创建和卡内配置更新会同步写入/替换 `messageParts.type=seminar_run_setup`，legacy ready 卡启动后的 runtime snapshot 合并也会保留 setup part；已有运行结果 snapshot 的历史卡不显示重新开始入口；本机 checkpoint `断点详情` 会在当前卡内展开，不再打开兼容面板。阅读页/外部 `研讨` 入口也会用同一 `seminarSessionId` 写入任务卡，避免进程死亡后用户无法从历史找到该 scoped runtime；runtime 运行、完成或刷新证据时，会按 `seminarSessionId` 回写 `status/sourceRefCount/snapshot`，卡片显示证据调用、被角色或 synthesis 明确引用过的证据快照、研讨时间线、角色观点、研讨总结、分歧数、开放问题数和 `研讨白板` 正文；如果 evidence fetch 尚未返回，卡片会按本次 scopes 先显示 `status=running` 的 pending `证据调用` 和 `调用中`；如果运行中已经取得 evidence bundle 但角色输出尚未完成，卡片会显示 completed `证据调用`、工具名、查询、结果数量、可见角色、可用时的 运行追踪和返回证据，不需要打开兼容面板或等待 completed snapshot；`AiSeminarRunCardRoleSummary` 会随 `conversationV2` 保存每个角色发言引用的 evidence refs；explicit `messageParts` 已承载且没有 legacy snapshot 内容的迁移历史卡，能在默认 `全部` 概览按原始顺序显示为线性 `研讨流`，单个 `seminar_run_setup`、`tool_call`、`reader_turn`、`director_state`、`role-running` status 或 `reader_composer` 也会进入同一原生流，并保留工具调用、读者回合、主持人状态、角色控制、可回应角色和草稿回复；tool-call-only 历史卡、带 运行追踪 的 tool_call 历史卡、pending evidence tool calls、运行中 completed evidence tool calls 和 live role partial 都不会再默认把用户带到单独 `证据调用` 分类；同 session active runtime 刚完成且 `messageParts` 已覆盖 legacy snapshot 内容的混合卡，以及没有可用 `messageParts` 的纯 legacy snapshot 历史卡，也会在默认 `全部` 概览显示最多 5 个代表性 part 的紧凑 `研讨流`，有隐藏片段时可在同一卡内展开全部研讨流，同时保证保存知识卡、加入复习、加入我的图谱、忽略、异常送审和 `打开来源` 等沉淀/来源动作仍可点击；历史卡仍保留 `全部 / 调用 / 证据 / 角色 / 分歧 / 白板 / 总结 / 异常` 子视图作深看，`调用` 子视图会显示证据收集的工具名、查询、结果数量、可见角色、运行追踪和返回证据，`分歧` 子视图可显示分歧正文、关联角色和关联 evidence 摘录，`异常` 子视图可从 `messageParts.review_triage` 恢复异常原因、AI 预审建议、候选明细和候选证据；runtime 完成并生成 role/synthesis/review/tool message parts 时，会保留全部非空可追溯 evidence refs，不再在生成 snapshot 阶段先截成两条，后续完整证据 tile 和紧凑关联证据行才能显示完整引用；历史任务卡状态读取和卡内 `异常送审` 已按 `seminarSessionId` 使用 scoped runtime，点击只调用同一 scoped runtime 的 Seminar Review handoff，不暴露普通 assistant 写入动作；阅读页选中文本 `研讨` 已改为进入阅读页 AI Chat 的原生任务卡，带入 reader SourceRef 且不默认展开 runtime panel；notes/memory/conceptGraph 已有运行前 evidence broker 独立检索首片；`Choose style` 不再显示 Seminar 行；全局默认设置从 Settings -> AI -> `研讨会设置` 进入。仍需完整 message part schema migration、同源 AI Chat 详情状态、结构化 contradiction scanner、更完整的角色 rebuttal loop、完整 AI reviewer service，以及 notes/memory/conceptGraph 检索的 streaming/tool-call 细化、完整工具调用 schema 和同源 AI Chat run detail state；纯 legacy 默认研讨流当前是渲染时派生，不是持久化历史格式迁移。 |
| UFA-C02-T21a | In Review slice | Seminar card inline KnowledgeCard save | completed Seminar 历史卡在当前 AI Chat 内直接保存 synthesis 知识卡。 | UFA-C02-T21, UFA-C04 low burden save, E00 SourceRef | `AiChatStream._buildSeminarRunCard`, `aiSeminarKnowledgeCardStoreProvider`, `KnowledgeCardStore.upsertCandidate` | completed 且 scoped runtime/evidence 匹配的 Seminar 卡片显示 `保存知识卡`；点击后把 synthesis summary 保存为 `KnowledgeCardOrigin.seminar` 的 draft KnowledgeCard，sourceRefs 来自 synthesis 引用的 traceable evidence；不写 ReviewItem、不进入 Review Inbox、不自动加入 SpacedReview 或 ConceptGraph；重复点击走 KnowledgeCardStore 去重。 |
| UFA-C02-T22 | In Review slice | Seminar entry migration | 阅读页和 AI Chat 的 Seminar 入口默认进入 Chat 原生 run，不再保留独立页兼容/调试入口。 | UFA-C02-T21 | entry router、compatibility tests | 已完成第五片：阅读页选中文本 `研讨` 和 AI Chat `+` 入口都已进入原生任务卡：阅读页路径打开 AI Chat 后只追加同 `seminarSessionId` 的可持久化历史任务卡，保留 SourceRef/bookId/snippet，不改 `activeAiSkillId`，不默认展开兼容面板；历史重载后待开始卡可点 `开始研讨` 在卡内启动，runtime 状态变化会回写被引用 evidence/role/synthesis snapshot；当前活跃同 session 且需要异常处理的任务卡可先在 `异常` 子视图查看异常处理预览，再直接 `异常送审`；历史卡异常送审预览已在卡片 snapshot 子视图中接入。仍需把任务卡升级为完整结构化 Chat run card，并继续把历史恢复、queued job、budget、Review handoff 等详情补进 AI Chat 原生状态；不得重新引入独立页面分叉。 |
| UFA-C03-T01 | Accepted | Concept producer | 从 KnowledgeCard、Seminar candidate concept refs、reader-grounded AI Chat concept refs 和 derived RAG/GraphRAG search result 提取有证据的 ConceptNode/Edge 候选。 | E03, E04 store, E05 controller, UFA-C01-T05, UFA-C02-T03, E02 SourceRef evidence | `ConceptGraphProducer`, ReviewInboxController apply hook, Seminar candidate `conceptRefs` handoff, AI Chat card `conceptRefs` handoff, `createFromLibrarySearchResult`, `ConceptGraphExplorerNotifier.createDraftCandidateFromLibrarySearch` | 只有 `applied + traceable + conceptRefs` 的 KnowledgeCard，或 `derivedLayer/derivedSummary + traceable chunk SourceRef` 的 library RAG result，生成 draft node/edge；Seminar candidate card 和 reader-grounded AI Chat card 可携带 conceptRefs 并在用户 Apply 后进入同一链路；KnowledgeCard-derived relation 仍保留 pending Review 旧路径；ConceptGraph 空态 `Create draft candidate` 传 `createReviewItems=false`，只写 draft node/edge、不写 ReviewItem，并展示 `Added to my graph / 已加入我的图谱` 或 skip feedback。 |
| UFA-C03-T02 | Accepted | Concept Explorer page | 提供局部图谱探索入口。 | E04 dossier/explore | `ConceptGraphExplorerPage`, provider, Settings AI entry, local graph map canvas, local graph map summary, injectable source opener | 用户能打开概念页、看中心概念、直接关系、二跳节点、evidence link 数量、draft/formal 状态、局部节点-连线图、局部路径、原文跳转和 orphan/broken link；`Open source` 点击会把 jumpable SourceRef 交给 opener，不可跳来源显示原因且不触发 opener；Settings AI 点击级测试覆盖 `Settings -> AI -> Concept graph` 导航到 Explorer。 |
| UFA-C03-T03 | Accepted | Reader concept entry | 阅读页选中文本可进入概念探索。 | UFA-C03-T02 | `ExcerptMenu` graph action, `ConceptGraphExplorerPage.initialQuery` | 选中文本可打开图谱页并筛选相关概念；没有相关概念时展示空态和草稿候选入口，不生成无证据正式节点。 |
| UFA-C03-T04 | Accepted | Full-book derived graph preview | Settings 和阅读页图谱入口展示书籍级全局层派生关系图预览。 | E02 global layer, E04 Explorer, E07 reader entry | `AiGlobalDerivedBookConceptGraphLoader`, `AiGlobalDerivedBookConceptGraphCatalog`, `conceptGraphDerivedBookLoaderProvider`, `conceptGraphDerivedBookCatalogProvider`, `ConceptGraphExplorerPage.bookId`, `ConceptGraphExplorerPage.initialQuery`, `ExcerptMenu` graph action, `full-book-map-summary`, `full-book-reading-path` | Settings `Concept graph` 入口会列出已有全局层的已索引书，可选择书籍并显示 `全书自动图谱 / Full-book auto graph`；阅读页 `图谱/Graph` 入口把当前 bookId 传入 Explorer 并直接显示 `全书派生图谱 / Full-book derived graph`、节点数、关系数、canvas、`Book map / 本书地图` 和 `Reading path / 导读路径`；从阅读页选中文本进入时，`initialQuery` 会按派生节点、关系和 evidence 命中把全书图谱收窄为局部子图，并显示 `Focused by selection / 按选中文本聚焦`，不会因 `Chunk 5` 这类位置标签把无关编号节点误拉入局部图；Book map 按主干连通概念统计核心主题、关键概念数、主干关系数和证据覆盖数，点击核心主题会打开摘要、相邻关系、证据摘录和来源跳转详情；导读路径按中心性、证据数量、edge confidence 和连接强度选择中心概念与强关系邻居，点击路径节点会打开同一套摘要、相邻关系、证据摘录和来源跳转详情，相邻路径节点之间会显示关系标签和 evidence 数量，点击关系 chip 会打开 `Selected full-book relation`；loader 只读取 `ai_graph_nodes / ai_graph_edges / ai_graph_node_chunks / ai_chunks`，只展示带 chunk SourceRef 的 derived-cache 节点和这些节点之间的共现关系；关系详情借用端点节点 SourceRef，用户显式点击后可把有 evidence 的派生节点或关系保存为 draft 图谱资产；已保存节点可从当前页移除，移除时清理 incident relations；保存关系前可先编辑 relation label/type；已有同两端关系时可显式选择目标 relation 并合并 evidence；也可在当前页临时忽略单条派生关系，保留两端概念节点；保存关系后重新打开同一关系会显示已保存状态，也可从当前页移除这条 draft 关系；缺表、无 evidence 或无全局层时显示空态/提示；不写正式 ConceptGraph、ReviewItem、KnowledgeCard、Memory、Note、Sync 或 spaced review。 |
| UFA-C03-T04a | Accepted | Book map evidence sections | 本书地图显示主干证据来自哪些章节或 chunk，并可点进对应节点。 | UFA-C03-T04, E00 SourceRef | `full-book-map-summary`, `_bookMapEvidenceSections`, `_sourceRefSectionLabel` | `Book map / 本书地图` 会从核心节点和主干关键节点的 `SourceRef.sourceTitle`、`SourceRef.locationLabel` 聚合 `Evidence sections / 证据章节`；点击章节 chip 会打开对应全书节点详情；只读取已存在的 chunk SourceRef，不调用 LLM、不外发正文、不写用户图谱、不进入 Review Inbox；测试覆盖章节标题、chunk 位置、核心主题点击详情和章节点击详情。 |
| UFA-C04-T01 | Accepted | Spaced Review | Review apply 后生成复习队列。 | E03, E05 | `SpacedReviewStore`, `spacedReviewProvider`, `SpacedReviewPage`, `SourceRefEvidenceList`, injectable source opener, Settings AI entry | 复习项可回溯到卡片和原文；页面显示证据摘录和不可用来源原因；删除书后显示可解释状态；评分记录下一次到期时间；`Open source` 点击会把 jumpable SourceRef 交给 opener，不可跳来源显示原因且不触发 opener；Settings AI 点击级测试覆盖 `Settings -> AI -> Spaced review` 导航到复习页。 |
| UFA-C04-T02 | Accepted | Flashcard Review apply | 待审 flashcard 应用后进入 Spaced Review。 | E05 controller, UFA-C02-T04 | `SpacedReviewStore.reviewIdForFlashcard`, `upsertFromFlashcardReviewItem`, `ReviewInboxPage` Apply gate | pending/approved flashcard 不直接入队；只有用户在 Review Inbox 点击 enabled `Apply` 后，applied 且 traceable 的 flashcard 才能入队；重复入队不制造重复复习项。 |
| UFA-C04-T03 | Accepted | Memory Review apply | 待审 MemoryCandidate 通过统一 Review Inbox 应用到本地 Markdown memory。 | E05 controller, MemoryWorkflowService, MemoryCandidateReviewAdapter | `MemoryWorkflowService.addToReviewInbox` -> `ReviewItemStore` handoff, `ReviewInboxController` memory source-specific apply/dismiss adapter, `ReviewInboxPage` Apply gate | AI Chat memory action 创建 pending MemoryCandidate 时同步创建 pending ReviewItem；conversation-only memory SourceRef 带 evidence snippet、source hash 和不可跳原因；Review Inbox `Approve -> Apply` 先调用 MemoryWorkflowService 追加到目标 daily/long-term Markdown，再推进 ReviewItem；`Dismiss` 同步 MemoryCandidate 且不写 memory；source candidate 缺失不推进 ReviewItem；不写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。 |
| UFA-C04-T04 | Accepted | BookNote SourceRef audit | 旧划线/笔记条目显示来源证据和可跳/不可跳状态。 | E00 SourceRef, E07 deep link, BookNote UI | `BookNoteSourceRefAdapter`, `BookNoteTile`, `BookNotesList`, search note result, `SourceRefEvidenceList` | Notes 列表和搜索结果传入 source title；BookNoteTile 显示 evidence、traceable/unavailable chip、来源位置和不可跳原因；有有效 `bookId + cfi` 的条目保持原文跳转；无有效 book anchor 条目点击只显示不可跳 snackbar，不触发空 CFI 或无效 book anchor 跳转；测试覆盖 adapter 和 widget。 |
| UFA-C04-T05 | Accepted | Memory browse SourceRef audit | Memory home、daily memory、long-term memory 浏览 UI 显示来源证据和可跳/不可跳状态。 | E00 SourceRef, E05 MemoryCandidate, E07 deep link, Memory browse UI | `MemoryEntrySourceRefAdapter`, `MemoryEntryRef.body/supportsBulkActions`, `MemoryRow` source audit chips, `MemoryDetailPage` source evidence/open source, Home navigation Memory label/icon | 只读投影已应用 MemoryCandidate；按目标文档和条目 body 匹配，summary-only 不归因，long-term H1 分段不共享整文件来源；列表显示 traceable/unavailable/unresolved chip；详情页显示 Evidence 和 `Open source`；可跳来源交给 reader opener，不可跳来源显示原因且不调用 opener；long-term H1 分段不允许批量删除/打标签，详情页也不显示会写整份 `MEMORY.md` 的 tag editor；不写 Markdown metadata、不写任何新知识资产。 |
| UFA-C04-T06 | Accepted | AI Chat Memory popup widget evidence | 回答旁书签图标打开 popup 并点击 `Add to Review inbox` 的 widget 测试。 | UFA-C04-T03, AI Chat message actions | `AiChatStream.memoryWorkflowService` seam, `test/ai_chat_stream_memory_actions_test.dart` | 点击 Memory icon 展示 `Memory actions / 记忆操作` 菜单；点击 `Add to Review inbox / 加入待审核队列` 调用 memory handoff；streaming 或空回答不写 memory candidate。 |
| UFA-C04-T07 | Accepted | Settings Review Inbox navigation evidence | Settings 顶层 AI 区和 `Settings -> AI` 子页进入 Review Inbox 的点击级 widget 测试。 | E05 Review Inbox UI, E07 navigation | `test/page/settings_page/settings_navigation_compile_test.dart` | 两条路径都能打开 `ReviewInboxPage`；空 inbox 显示空态而不是导航失败；不创建 ReviewItem。 |
| UFA-C05-T01 | Accepted | Sync / Export | 用户确认资产进入同步和导出入口。 | E08 policy | `KnowledgeAssetExportService`、`knowledgeAssetExportProvider`、`KnowledgeAssetExportPage`、Settings AI entry、export manifest、Markdown export、HTML study report、Anki TSV export、sync-conflict ReviewItem handoff | API key 不同步；派生索引不当作 source-of-truth；冲突被排除并显性显示；当前创建本地 manifest、Markdown 学习导出、HTML study report 和 Anki TSV，并能把待审冲突送入 Review Inbox；导出页在发送成功后显示 `Review inbox` 直达入口；provider 级测试覆盖 `KnowledgeAssetExportNotifier -> ReviewInboxNotifier -> ReviewInboxController -> KnowledgeCardStore/ReviewItemStore` 的安全 KnowledgeCard 冲突 approve/apply 闭环，解除 pending conflict 并重新进入导出集合；不执行远端写回或自动跨设备合并。 |
| UFA-C05-T02 | Accepted | Remote sync preview | 用户从 Knowledge sync/export 读取远端 sync bundle，预览 per-entity incoming/outgoing/conflict，并把远端冲突送入 Review。 | UFA-C05-T01, E08 sync bundle, SyncClient/WebDAV config, E05 ReviewItemStore | `.knowledge/knowledge_sync_bundle_v1.json`, `KnowledgeRemoteSyncPreview`, `KnowledgeAssetExportService.previewRemoteSync`, `submitRemoteConflictsToReview`, `KnowledgeAssetExportNotifier.previewRemoteSync`, `KnowledgeAssetExportPage` `Preview remote sync` / `Send remote conflicts to Review` actions | sync bundle 只包含默认纳入的安全 envelope；remote preview 读取 `paper_reader/.knowledge/knowledge_sync_bundle_v1.json` 并展示 remote/incoming/outgoing/conflict 计数；preview 不导入 incoming、不覆盖本地资产；远端冲突 ReviewItem 只保存安全 metadata、payload keys、SourceRef count 和 safe SourceRef；远端 preview 冲突一律 `canApply=false`，只支持 dismiss/triage；安全 KnowledgeCard 本地 staged 冲突继续走 approve/apply，本地解除 pending conflict；不执行远端写回、自动合并或备份同步。 |
| UFA-C05-T03 | Accepted | Protected remote sync upload | 用户从 Knowledge sync/export 把本机安全 sync bundle 写到 WebDAV/SyncClient。 | UFA-C05-T02, SyncClient/WebDAV config | `KnowledgeAssetExportService.uploadRemoteSyncBundle`, `KnowledgeRemoteSyncUploadResult`, `KnowledgeAssetExportNotifier.uploadRemoteSyncBundle`, `KnowledgeAssetExportPage` `Upload sync bundle` action | 上传前重新生成本机安全 sync bundle；远端不存在时创建 `paper_reader/.knowledge` 并上传；远端存在时先 preview，只有 `incoming=0` 且 `conflict=0` 时允许 replace；存在 incoming 或 conflict 时抛错并保持 remote 未改；页面显示上传路径和上传数量；不导入 incoming、不应用远端冲突、不执行双向自动合并或备份同步。 |
| UFA-C05-T04 | Accepted | Remote incoming KnowledgeCard Review import | 用户从 Knowledge sync/export 把远端 incoming KnowledgeCard 发送到 Review Inbox。 | UFA-C05-T02, E03 KnowledgeCardStore, E05 ReviewItemStore | `KnowledgeAssetExportService.submitRemoteIncomingToReview`, `KnowledgeRemoteIncomingReviewResult`, `KnowledgeAssetExportNotifier.submitRemoteIncomingToReview`, `KnowledgeAssetExportPage` `Send remote incoming to Review` action | 只接受 `knowledge-card + schemaVersion=1 + 无 secret payload + 有 evidence` 的远端 incoming envelope；导入时降级为 pending KnowledgeCard 和 pending ReviewItem；重复导入不制造重复卡；非 KnowledgeCard、无 evidence 或 unsafe payload 跳过；不导入 reviewHistory、不应用远端冲突、不自动写用户资产、不写 memory/note/graph/spaced review。 |
| UFA-C05-T05 | Accepted | Remote review history Review import | 用户从 Knowledge sync/export 把远端 review history 发送到 Review Inbox。 | UFA-C05-T02, E05 ReviewInboxController, SpacedReviewStore | `KnowledgeAssetExportService.submitRemoteReviewHistoryToReview`, `KnowledgeRemoteReviewHistoryReviewResult`, `ReviewItemSourceType.reviewHistoryImport`, `ReviewInboxController` review history apply adapter, `SpacedReviewStore.upsertImportedReviewHistory`, `KnowledgeAssetExportPage` `Send remote review history to Review` action | 只接受 `review-history + schemaVersion=1 + 无 secret payload + 有 evidence` 的远端 incoming envelope；导入时只创建 pending ReviewItem；generic ReviewItemStore apply 被拒绝；用户在 Review Inbox approve/apply 后才写入 SpacedReviewStore；重复导入不制造重复复习记录；不应用远端冲突、不写 KnowledgeCard/Memory/Note/ConceptGraph。 |
| UFA-C05-T06 | Accepted | Remote KnowledgeCard conflict staged restore | 用户从 Knowledge sync/export 把安全远端 KnowledgeCard conflict 暂存到 Review Inbox，并在 Review Inbox 中确认恢复。 | UFA-C05-T02, E03 KnowledgeCardStore, E05 ReviewInboxController | `KnowledgeAssetExportService.stageRemoteKnowledgeCardConflictsToReview`, `KnowledgeRemoteConflictStageResult`, `KnowledgeCardStore.stageRemoteSyncConflict`, `KnowledgeCardStore.removeStagedRemoteSyncConflict`, `remote_sync_conflicts_v1.json`, `KnowledgeAssetExportPage` `Stage safe remote card conflicts to Review` action | 只接受 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef` 的远端 conflict；staging 只写 staged conflict store 和 pending sync-conflict ReviewItem，未 Apply 前不覆盖本机 KnowledgeCard；ReviewItem 写入失败会删除 staged entry；用户 Apply 后才写为本机 approved asset 并清掉 staged conflict；preview-only `Send remote conflicts to Review` 仍 `canApply=false`；重复、unsafe、untraceable 或无 staged envelope 的 apply 失败关闭；不远端写回、不双向自动合并、不写 Memory/Note/ConceptGraph/SpacedReview。 |
| UFA-C05-T07 | Accepted | Remote sync status panel | 用户从 Knowledge sync/export 看到远端同步当前状态和下一步动作。 | UFA-C05-T02, UFA-C05-T03, E07 observability | `KnowledgeRemoteSyncStatus`, `KnowledgeAssetExportState.remoteSyncStatus`, `KnowledgeAssetExportPage` remote status panel, l10n keys | 页面显示 `Not previewed / Review required / Ready to upload / Uploaded / Re-preview required / Concurrency guard unavailable / Failed`；远端 preview 出现 incoming/conflict 时显示 Review required；无 blocker 时显示 Ready to upload；上传成功显示 Uploaded；远端在 preview 后变化显示 Re-preview required；provider 缺少条件写保护显示 Concurrency guard unavailable；远端操作失败显示 Failed；刷新或重新创建 manifest 会清理旧上传状态；状态面板只解释下一步，不自动合并、不绕过 Review。 |
| UFA-C05-T08 | Accepted | Remote merge planner | 对 local/remote/base envelope 做三路 diff，输出 incoming/outgoing/conflict plan，不写本地或远端资产。 | UFA-C05-T07, E08 policy | `KnowledgeRemoteMergePlanner`、`KnowledgeRemoteMergePlan`、`KnowledgeAssetExportService._previewRemoteSync`、`test/models/knowledge_remote_merge_planner_test.dart` | Planner 支持 optional `base` 三路判断；远端 preview 会把同 remotePath 的本机 baseline 传入 planner，无 baseline 或 baseline 不合格时降级为保守 preview。已覆盖 same id same content、local changed vs base、remote changed vs base、delete/modify、unknown schema、secret payload、base unsafe envelope、no base divergent content、duplicate id、missing required id、whitespace padded id；canonical fingerprint 排除 `updatedAt`，不使用 whole-file newer-wins；preview conflicts 保持 pending Review handoff。 |
| UFA-C05-T09 | Accepted | Remote writeback executor | 只在 merge plan 无 incoming/conflict blocker 时写回远端 bundle，并保留 rollback snapshot。 | UFA-C05-T08 | `KnowledgeRemoteWritebackExecutor`、`KnowledgeRemoteWritebackException`、`KnowledgeRemoteSyncUploadResult.rollbackSnapshotFile`、provider rollback state、page rollback status | 远端写失败不改本地 confirmed asset；旧远端 bundle 写回失败后用 rollback snapshot 恢复；新远端 bundle 半写入失败后删除 partial remote；API key 和派生索引不得写出；状态面板显示 rollback snapshot、恢复或删除 partial 的结果。 |
| UFA-C05-T10 | Accepted | Remote writeback CAS guard | 在 SyncClient 层支持条件写或 ETag guard，降低 preview 与 replace/create 之间的并发覆盖风险。 | UFA-C05-T09, SyncClientBase/WebDAV | `SyncRemoteWritePrecondition`、`SyncClientBase.uploadFileConditionally`、`WebdavClient.uploadFileConditionally`、`SyncPreconditionFailedException`、`SyncConditionalWriteNotSupportedException`、provider/page `repreviewRequired` 与 `concurrencyGuardUnavailable` 状态、race tests、WebDAV adapter header tests | WebDAV 写回使用 `If-Match` 或 `If-None-Match`；远端在 preview 后被其他设备修改时不得覆盖；远端在 create 前被其他设备创建时不得覆盖；无法提供 ETag/CAS 的 provider 会拒绝覆盖并显示 guard unavailable；precondition 失败会显示重新 preview；测试覆盖 replace race、create race、unsupported CAS、页面状态、真实 WebDAV adapter 请求头和 HTTP 412 映射。 |
| UFA-C05-T11 | Accepted | Remote sync baseline source-of-truth | 成功远端写回后保存本机 remotePath baseline，下一次 preview 用它做三方 diff。 | UFA-C05-T08, UFA-C05-T10 | `KnowledgeAssetExportService.remoteSyncBaselineFile`、`_readRemoteSyncBaseline`、`_writeRemoteSyncBaseline`、`test/service/sync/knowledge_asset_export_service_test.dart` baseline tests | 只有 `uploadRemoteSyncBundle` 写回成功后才更新 `.knowledge/knowledge_sync_remote_baseline_v1.json`；baseline keyed by remotePath，只保存默认同步策略纳入的安全 envelopes，不保存 draft、secret payload、派生索引或待审冲突；写入新 baseline 时会丢弃旧文件中已污染或不合格的 remote entries；preview 读取同 remotePath baseline 后 local 单边变化成为 outgoing，remote 单边变化成为 incoming；baseline 缺失、损坏、路径不匹配、重复 ID、future schema、unsafe payload 或 malformed envelope 会降级为保守 preview；不自动导入 incoming、不自动覆盖本地或远端资产、不替代 ETag/CAS guard，也不声明完整跨设备后台同步。 |
| UFA-C05-T12 | Accepted | Safe remote sync run | 用户点击 `Run safe remote sync`，把远端 preview、Review blocker handoff 和无 blocker 上传串成前台安全运行。 | UFA-C05-T02, UFA-C05-T06, UFA-C05-T10, UFA-C05-T11 | `KnowledgeAssetExportNotifier.runSafeRemoteSync`、`KnowledgeAssetExportPage` `Run safe remote sync` action、l10n keys、provider/page tests | 点击后先执行 remote preview；存在 incoming/conflict blocker 时调用安全远端 KnowledgeCard incoming Review、review history Review、safe remote KnowledgeCard conflict staged Review 和 preview-only conflict triage Review，且不调用 upload；无 blocker 时调用受保护 `uploadRemoteSyncBundle`；上传成功清理旧 Review handoff 计数；不自动 apply 任何 ReviewItem，不同步 API key，不声明后台跨设备自动同步。 |
| UFA-C05-T13 | Accepted | Review Inbox safe sync conflict batch apply/retry | 用户在 Review Inbox 的 `Approved + Sync conflict` 视图批量应用已审核安全冲突，失败项保持 approved 可重试。 | UFA-C05-T06, UFA-C05-T12, E05 controller | `ReviewInboxController.applyApprovedSyncConflicts`、`ReviewInboxState.canApplyApprovedSyncConflicts`、`ReviewInboxNotifier.applyApprovedSyncConflicts`、`ReviewInboxPage` `Apply Sync conflict` / `Retry Sync conflict` action | 只批量处理 `approved + sync-conflict + canApply=true + traceable SourceRef` 的项目；preview-only、memory-candidate、pending 和无 evidence 项不进入批量 apply；批量执行按项调用 source-specific apply adapter，成功项推进 applied，失败项留在 approved 且保留重试入口；UI 显示部分失败错误，不把失败项伪装为已应用；测试覆盖 controller、provider 和页面入口。 |
| UFA-C05-T14 | Accepted | Foreground remote change check | 用户从 Knowledge sync/export 点 `Check remote changes`，只读检查远端 bundle 并看到 incoming/conflict 摘要。 | UFA-C05-T02, UFA-C05-T07 | `KnowledgeAssetExportState.lastRemoteCheckAt`、`KnowledgeAssetExportNotifier.checkRemoteChanges`、`KnowledgeAssetExportPage` `Check remote changes` action、l10n keys、provider/page tests | 点击后只调用 remote preview，记录本次前台检查，显示 `Remote changes found` 或 clean 摘要和 read-only 提示；不得调用 upload、不得调用任何 remote Review handoff、不得 apply；失败时清理 stale preview 和检查状态并进入 Failed；刷新或创建导出会清理旧检查状态；测试覆盖 provider read-only flags 和页面可见提示。 |
| UFA-C06-T01 | Accepted | Custom Skill 导入 | 用户从 Settings 导入 governed JSON skill，并在 Active Skill 或 AI Chat Choose style 中启用。 | E06 CustomSkillContract, AiSkillRegistry, LangChain runtime | `CustomSkillStore`、`CustomSkillsPage`、Settings AI entry、AI Chat `Choose style` configurable custom skill row、中文 ARB/l10n、`AiSkill.allowedToolIds/sceneIds`、`LangchainAiRegistry.enabledToolIdsForActiveSkill` | 有效 `CustomSkillContract(schemaVersion=1)` 可导入、upsert、禁用和删除；危险工具、递归 sub-agent、unknown scene/field 和类型错误不落库不激活；禁用 skill 不进入 Active Skill 或 AI Chat Choose style；运行时只保留 custom skill 声明过且当前 scene/permission matrix 允许的只读工具；custom skill 激活时不加载 MCP 工具；widget 覆盖 `Settings -> AI -> Custom skills` 导航、粘贴 JSON 导入、AI Chat `Choose style` 自定义 skill 配置入口和配置点击不改变 active skill；中文界面显示 `自定义技能`、`导入技能`、`已安装技能` 和导入结果。 |
| UFA-C06-T02 | Accepted | Responses previous_response_id fallback | OpenAI 官方 Responses continuation 保持 server-side state；第三方 Responses provider 拒绝 `previous_response_id` 或 `store` 时自动降级重试。 | Provider Center Responses config, LangChain runtime | `ChatOpenAIResponses` compatibility latch, explicit `store: true` continuation body, fallback request builder, endpoint normalization, failure diagnostics | OpenAI 官方兼容路径不发送 `conversation`，启用 `previous_response_id` 时显式发送 `store: true`；只有明确 `previous_response_id` unsupported 的 HTTP 400 会禁用 previous 并 fallback；只有明确 `store` unsupported 的 HTTP 400 会禁用 stateful continuation 并 fallback；正常 provider 继续用 server-side continuation；unrelated 400 不 retry；用户把完整 `/responses` endpoint 粘进 baseUrl 时不会生成 `/responses/responses`；非 fallback 错误会附带 endpoint、model、是否发送 `previous_response_id`、是否发送 `conversation`、是否发送 `store`、是否已经 fallback retry 的诊断；测试覆盖正向 previous fallback、store fallback、负向错误保留和 endpoint normalization。 |
| UFA-C06-T03 | Accepted | Active Skill picker widget evidence | 从 `Settings -> AI -> Active Skill` 选择已启用 custom skill 的点击级 widget 测试。 | UFA-C06-T01 | `test/page/settings_page/settings_navigation_compile_test.dart` | 已启用 custom skill 出现在 picker；disabled custom skill 不出现；选择后 runtime registry 能读取 active custom skill 并收窄工具。 |
| UFA-C06-T04 | In Review slice | Built-in Skill prompt settings | AI Chat `Choose style` 的普通内置 skill 不再只有选择动作，可打开该 skill 的提示词附加设置。 | UFA-C06-T01, E06 governance, E07 Chat UI | `Prefs.aiSkillCustomPrompts`、`Prefs.setAiSkillCustomPrompt`、AI Chat `Choose style` built-in configurable row、`LangchainAiRegistry._activeSkillPrompt`、`test/ai_chat_stream_choose_style_config_test.dart`、`test/service/ai/langchain_registry_custom_skill_test.dart` | 普通内置 skill 行显示 `Skill settings / 技能设置`；点击设置不会改变当前 active skill；保存的 custom prompt 写入 `aiSkillPromptProfilesV1`，空内容清除 profile；prompt add-on 上限 2000 字符，保存时保留 profile 未来扩展字段；新 agent 请求会在该 skill 原始 system prompt 后追加 `## User Skill Settings`，并声明该段低于 PaperTok 隐私、证据、工具权限和写入确认规则；profile 只作用于普通内置 skill，不作用于 custom skill 或 native Seminar marker；Seminar 不再进入 `Choose style`；全局默认设置从 Settings -> AI -> `Seminar settings` 进入，custom skill 行仍进入 `CustomSkillsPage`；当前只支持 prompt add-on，不支持内置 skill 的工具范围、证据策略、输出模板 schema 或单次 Chat run 临时覆盖。 |
| UFA-C07-T01 | Accepted | Current-book semantic search resource guard | 当前书语义搜索避免一次性全书向量/正文加载并串行化扫描。 | E02 current-book index, E06 tool governance, mobile resource gate | `SemanticSearchCurrentBook` book-scoped vector backend recall/paged scan/topK/text winner load/global lock, `AiToolRegistry` non-concurrent flag | current-book search 会先按 `bookId` 调用 `AiVectorSearchBackend`，后端调用继承 fallback scan budget，book-scoped 路径只允许完整 per-book Vec1 sidecar 或 compact exact，不用全局 Vec1 ANN 后过滤；后端有结果时不进入整书 fallback scan；scan columns 不含 `text/raw_text/embedding_json`；JSON fallback 按页批量；只为 winners 取正文；直接调用与 tool 调用都不并发扫描；测试覆盖 vector backend recall、预算透传、分页列、winner text load、直接调用串行和 tool non-concurrent。 |
| UFA-C07-T02 | Accepted | Current-book semantic search background backend | 为当前书语义搜索增加候选预筛、book-scoped ANN 或后台 isolate，并暴露取消或进度状态。 | UFA-C07-T01, E02 schema gate | `AiCurrentBookVectorPageScorer` backend seam, default background isolate scoring, FTS/BM25 candidate prefilter, per-book Vec1 sidecar, cancellation/progress tests, synthetic large-book scan acceptance, `TocSearch.semanticProgress`, reading-page stale search cancel, tool timeout cancel | 已覆盖 background isolate scoring seam、完整 per-book Vec1 sidecar 优先、FTS/BM25 只取候选 id、ANN/FTS chunk 去重、synthetic large-book 只扫描 candidate limit 而非全书 chunk、候选 vector row 不含 `text/raw_text/embedding_json`、FTS 无候选、MATCH 失败、候选过期或表缺失时进入 fallback 分页扫描路径、JSON fallback 仅覆盖候选页 blob 缺失行、取消后不回查 winners/不写 partial result、阅读页 semantic progress state 和工具 timeout cancel；SourceRef evidence 不降级；不是已打包 sqlite-vec/Vec1/ANN 发布后端。 |
| UFA-C07-T03 | Accepted | AI Chat hidden streaming UI throttle | 阅读页 AI 面板隐藏或多 tab 非活动 chat 继续生成时降低 UI 重建频率。 | UFA-C01-T05, E07 mobile resource gate | `aiChatUiVisibleProvider`、`AiChat.setStreamingUiVisible`、`AiChat.flushPendingStreamingUi`、provider `onDispose` cleanup、`AiChatStream.uiVisible`、`AiMultiTabChat.uiVisible`、ReadingPage bottom-sheet `uiVisible` handoff、`test/providers/ai_chat_new_conversation_test.dart`、`test/ai_multi_tab_chat_visibility_test.dart` | 可见 chat 仍按 160ms 合并流式文本；隐藏阅读页 AI 面板或非活动 tab 的 chat 会把 pending streaming UI flush 降到约 1000ms；从可见切到隐藏时会取消已排队的短 flush 并按隐藏窗口重排；用户重新打开面板或切回 tab 时立即补刷 pending 文本；每个 tab 的 visibility provider scope 独立，切换 tab 不把活动/非活动状态串到其它 tab；关闭 streaming tab 会 dispose scope 并取消该 tab 的 generation subscription/timer；stream 完成时仍强制 flush；隐藏/切 tab 不取消后台生成、不丢 conversation history、不把该测试等同于真机 profile 通过。 |
| UFA-C07-T04 | Accepted | Current-book fallback scan budget | 无 FTS 候选或 FTS 不可用时限制前台 fallback 向量扫描规模。 | UFA-C07-T01, UFA-C07-T02, mobile resource gate | `SemanticSearchCurrentBook.maxFallbackVectorRows`, `foregroundFallbackVectorRowBudget`, `toolFallbackVectorRowBudget`, 阅读页/Seminar/tool 显式预算接入 | 阅读页 fallback 扫描最多 1024 行；AI Seminar evidence 和 `semantic_search_current_book` tool fallback 扫描最多 2048 行；FTS 命中候选路径不受 fallback 预算误伤；fallback progress 总量使用预算后行数；扫描列仍不含 `text/raw_text/embedding_json`；预算耗尽时返回带 message 的降级结果；测试覆盖无候选 fallback 只扫描预算行数。 |
| UFA-C07-T05 | Accepted | Library hybrid vector recall | 书库 RAG 让向量后端与 FTS/BM25 同时召回候选，而不是只在文本 miss 后 fallback。 | E02 library RAG, E06 tool contract | `SemanticSearchLibrary.usedVectorRecall`, `AiVectorSearchBackend`, `semantic_search_library_search_test.dart` | FTS 命中候选时仍调用 `AiVectorSearchBackend`；纯语义命中的 chunk 可进入最终 hybrid/MMR/rerank 排序；结果 JSON 区分 `usedVectorRecall` 与 `usedVectorFallback`；本地文本入口仍可关闭 query embedding/vector/rerank，避免外发正文；默认 backend 是 ANN -> native -> exact，但没有 Vec1 extension/table 时会降级，不误标发布级 ANN 完成。 |
| UFA-C07-T06 | Accepted | Library exact vector compact scan | 降低默认 exact backend 在书库 hybrid recall 中的内存峰值，并给 sqlite-vec/ANN backend 固化 winner hydrate contract。 | UFA-C07-T05, E02 library RAG | `AiExactVectorSearchBackend`, `ai_vector_index_test.dart`, `ai_local_vector_index_test.dart` | 主扫描不读取 `text/raw_text/context_text/embedding_json`；旧索引缺 blob 时只批量回查缺失行 JSON；只 hydrate top winner 正文；返回 winner 仍带 `local_vector_score` 和完整 evidence 所需字段；不是 ANN/Vec1/sqlite-vec 完成。 |
| UFA-C07-T07 | Accepted | Native vector shadow index prep | 为旧书库索引补建 native vector shadow rows，并把默认向量 backend 接成 ANN -> native -> exact fallback。 | UFA-C07-T05, UFA-C07-T06, E02 schema gate | `kAiIndexDbVersion = 12`, `ai_vector_index_rows`, `ai_vector_index_meta`, `AiNativeVectorIndexBuilder`, `AiVec1VectorIndexBuilder`, `AiAnnThenNativeThenExactVectorSearchBackend`, `AiLibraryIndexPage` `向量索引升级` tile | v12 schema 创建 shadow rows/meta 表和索引；backfill 可把已有 blob 或旧 JSON vector 写成 compact float32 rows，跳过损坏向量并清理 stale rows；inspect/status 能报告已索引书籍、完整准备书籍、已写入 vector row 数和缺失书籍；页面显示升级入口、进度、取消和结果；Vec1 可用且全书库 ANN 表完整时书库优先返回 ANN winner；current-book 只在 per-book sidecar 完整时返回 book-scoped ANN winner；Vec1 不可用、ANN 表缺失、native SQL seam 不可用或无结果时 exact backend 接管；shadow layer 不完整时 fallback rows 与 ANN/native rows 合并，避免漏掉未升级书籍；不是已打包的 ANN/Vec1/sqlite-vec 发布完成。 |
| UFA-C07-T09 | In Review slice | Vec1 ANN backend seam | 在不牺牲 fallback 的前提下，把真实 sqlite-vec/Vec1 查询形态接入默认书库和当前书向量后端。 | UFA-C07-T05, UFA-C07-T06, UFA-C07-T07, UFA-C07-T08 | `AiVec1VectorIndexBuilder`, `AiVec1VectorSearchBackend`, `AiAnnThenNativeThenExactVectorSearchBackend`, `AiVectorIndexPurger`, `AiIndexDatabase.clearBook`, `AiLibraryIndexPage` `ANN 向量索引`, AI Index 行内 `Build ANN sidecar`, `ai_native_vector_index_test.dart`, `ai_library_index_page_test.dart`, `ai_index_schema_global_layers_test.dart` | Vec1 表名按 provider/model/dim 固定隔离；builder 可从 shadow rows rebuild per-model ANN table 并写 `vec1-ann` meta，同时为每本书生成 per-book Vec1 sidecar；builder 也可只为指定 bookId 从已有 shadow rows 重建 per-book sidecar，不改写全局 ANN table 或全局 meta；status API 报告 extension 可用性、group/global row 缺口、per-book sidecar ready/missing 和是否可构建；设置页可触发前台整库 ANN 构建并取消，书籍行可在 `ANN Missing` 且 compact vector 已就绪时触发单书 `Build ANN sidecar / 构建 ANN sidecar`，并在构建期间显示该书 sidecar group/row 进度；ANN search 只 hydrate winner；book-scoped search 只使用完整 per-book sidecar；Vec1 不存在、ANN 表缺失或 ANN rows 不完整时降级 native/exact；删除书籍会清理该书 native vector rows、全书库 Vec1 ANN 行、per-book sidecar 行并更新/移除 meta，且不误删同 group 的其它书；仍需平台打包、可恢复 ANN build job 和 provider/model 失效。 |
| UFA-C07-T08 | Accepted | ANN/exact recall overlap gate | 给真实 sqlite-vec/ANN 后端接入前建立可执行召回质量验收。 | UFA-C07-T05, UFA-C07-T06, UFA-C07-T07 | `AiVectorRecallOverlapGate`, `ai_vector_recall_overlap_test.dart` | Gate 会分别调用候选 ANN/native backend 和 exact backend，比对 topK `chunk_id`，输出 candidate/exact/overlap/missing/unexpected chunk id、overlap ratio 和 threshold 结果；固定 fixture 覆盖 4/5 overlap 通过、2/4 overlap 失败，确认 limit/maxScanRows 转发到 backend，并能把同一个 `bookId` 传给候选 backend 与 exact backend；该 gate 不替代真实 ANN adapter、index build job 或平台打包。 |

## 5. Agent 执行约束

每个剩余任务必须使用 `02_agent_execution_model_zh.md` 的 Agent Task 模板，并附加这些约束：

- 阅读场景优先 current book；只有用户显式跨书或 evidence 不足时才查 library。
- 外发正文给 provider 必须经过现有 AI 功能开关或显式用户动作。
- 写入用户资产必须经过 Review 或用户确认。
- ConceptGraph 是派生层；用户确认过的关系才是用户资产。
- UI 入口要能在移动端触达，不把核心阅读内容遮住。
- 长任务必须有取消、失败提示、重启恢复或可重试路径。

## 6. Rescue Review 要点

执行完成前，reviewer/rescue agent 必须逐项检查：

- 入口是否真实可触发，而不是只写了文档。
- 生成的 KnowledgeCard、Seminar synthesis、ConceptNode、ConceptEdge 是否都有 SourceRef。
- Review Inbox 是否能解释每个待审项的来源和状态。
- 任何自动化输出是否越过 Review 写入了长期资产。
- 文档是否把未接入口的能力标成已可用。
- 测试是否覆盖重复点击、空输入、source 不可跳、provider 失败和取消路径。
