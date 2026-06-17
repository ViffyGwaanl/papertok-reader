# R3 Brief — Seminar 并入 sub-agent 平台(原 P1.5 / P1-S7)

> 前置:R1、R2 完成。
> DoD:Seminar 角色运行完全经由 `SubAgentRunner` 平台(同一 run identity、状态流、工具权限、取消/等待/恢复);`AiSeminarRuntimeService` 中重复编排逻辑删空,只保留 evidence broker 与 Director policy 两个领域件;角色获得受控自由多轮工具 loop;Seminar 与普通 AI Chat 共用同一 streaming tool-call 组件;真机验收脚本(本文件 §验收)通过。
> 最后更新:2026-06-11

## 目标模型

- 研讨会对主对话而言就是一个可调用的 agent 工具:P1 的 `start_seminar` MVP 在 R3 升级为真正的子 agent 调用——主对话 LLM 发起、研讨结果(总结/分歧/证据)回流主对话上下文,可被后续对话引用。
- **读者参与在此重生(P1 五轮失败后冻结移交)**:没有卡内第二输入框——研讨运行中,主对话输入框的消息直接路由给 Director,由其分配角色回应或调整讨论;参与反馈以普通研讨流块出现,无跳转。这是"聊天即参与"的最终形态,DoD 必含。
- Director = parent agent run(调度、轮次、askUser、synthesis)。
- 每个角色(critical/supportive/synthesizer/verifier)= 平台子 agent:profile + 本场 prompt + evidence scope + 只读工具白名单(`AiToolPermissionMatrix`)。
- **角色 prompt 强化(P1 六轮记入,DoD 含)**:现状 `promptForRole`(`ai_seminar_orchestration_service.dart`)只传角色名 + 问题 + 证据 id + 前序角色名,分工全靠模型猜角色名,薄而不稳。R3 写厚每角色指令:综合者显式调和批判/支持两方、核验者逐条核对前序结论与证据、批判/支持各自明确立场;让四角色分工可靠可验。
- evidence broker = 共享只读工具输入,作为平台工具暴露,不再是私有旁路。
- 取消/等待/恢复/重试走平台统一控制(`wait/cancel/resume/retry`),UI 用统一 agent run 组件渲染,Seminar 不再有专用控制路径。

## 为什么以前做不动、现在能做

P1 期间这是 S7,排在最后,导致 S1–S6 全部在旧 runtime 上打补丁。R1 后 UI 是小文件、R2 后只有一条事件流,本任务的每次改动都落在 <1000 行文件和单一数据源上,成本只有原来的零头。

## 执行批次

1. ADR:盘点 `SubAgentRunner`(~380 行)与 `ai_seminar_runtime_service.dart` 的职责重叠表,定义平台需要补的最小能力(多轮 tool loop、waiting_input、child retry)。
2. 平台补强:在 `SubAgentRunner`/`ToolOrchestrator` 上实现受控多轮工具 loop(轮数/预算上限、只读白名单、每轮事件落 graph)。普通 sub-agent 先受益并先行验证。
3. 角色切换:`AiSeminarModelRoleExecutor` 改为薄 adapter(组 prompt + 解析 Seminar JSON),执行走平台;删 runtime service 里的角色编排。
4. Director 切换:Director 成为 parent agent,轮次/askUser/synthesis 作为其决策输出;删旧 Director 私有状态机。
5. 统一 streaming tool-call 组件:Seminar 卡的工具调用块复用普通 AI Chat 的 tool tile(R1 已拆出),删 Seminar 专用渲染。
6. 清尾:`ai_seminar_runtime_service.dart` 目标 ≤800 行(evidence broker + Director policy);全量测试 + 真机回归。

## 验收(真机,用户执行)

1. 发起研讨,某角色在发言中自主发起第二次工具调用(loop 生效),全程可见统一工具块。
2. 对运行中角色执行 等待→取消→重试,行为与普通 sub-agent 一致。
3. 杀进程恢复后,角色与工具调用历史完整,可续跑。
4. P1 十步脚本全量回归通过。

## 红线

- 平台能力先在普通 sub-agent 上验证,再切 Seminar;禁止为 Seminar 单做特殊分支。
- 写工具永不进角色白名单。
