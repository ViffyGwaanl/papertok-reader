# Agent 工作契约

> 适用对象:在本仓库工作的所有 agent(codex、Claude、其他)与人。
> 最后更新:2026-06-11。修改本文件需用户确认。

## 0. 为什么有这份契约

2026-05/06 的教训:计划文档膨胀到 2.4MB,agent 每个 session 的上下文被文档吃光,只能做防御性微切片,而每个微切片又要追加大段进度叙事,恶性循环,半个月无法收口一个优先级。本契约围绕 agent 的上下文经济学设计:**开工必读 ≤10K token,其余信息按需 grep**。

## 1. 开工规则

- 必读且只需读:`README_zh.md` + `STATUS_zh.md` + 当前任务的 `briefs/*.md`。
- 禁止通读 `archive/`、禁止通读大源文件;用定向 grep/局部读获取代码事实。
- 开工前确认 `STATUS_zh.md` 中该任务状态为 in progress(不是就先改为它)。

## 2. 切片规则

- 一个切片 = 验收脚本中的一步打通,或一个真机验收失败项的修复,或 brief 中列出的一个批次。
- 禁止防御性微切片(为单个标签、单个 tile 的可见性单开切片)。
- 切片必须以可运行的验证命令结束(见 §5)。

## 3. 状态规则

- 状态只有 4 档:`backlog` / `in progress` / `待真机验收` / `done`。
- 禁止 "In Review slice"、"Draft/In Progress" 等无限中间态。
- **只有用户在真机按验收脚本走完后,才能把任务标为 done。** agent 最多推进到 `待真机验收`。
- 用户可见性描述必须诚实区分:底座已有 / 入口可点 / 闭环可走 / 已验收。

## 4. 文档规则

- 每个切片允许的文档改动:`STATUS_zh.md` 对应行(≤3 行)+ commit message。没了。
- 进度叙事一律不写;git log 就是 ledger。禁止"最新进展"段落、禁止往验收清单追加实现细节条目。
- 验收标准只写用户可观察行为,不写 `messageParts.type=...` 这类实现细节。
- 新计划 = 新 brief(≤150 行)放入 `briefs/`;启动一个优先级前重写其 brief,旧的归档。
- 文档预算:`docs/ai/future_agentic_upgrade/**.md`(archive 除外)单文件 ≤30KB,由脚本强制。

## 5. 验证规则

- 每个切片结束时必须:
  1. 列出本片改动的文件;
  2. 给出验证命令(`flutter analyze`、最小 `flutter test` 子集);
  3. 运行 `tool/check_repo_budgets.sh` 并通过。
- flutter 命令在用户的 Mac 上执行(Cowork 沙箱无 flutter);本地 agent(codex/Claude Code)自己跑。
- 测试策略:优先 service/provider 级测试;widget 测试只做 smoke,禁止长轮询等待 live signal(历史上反复超时 flaky)。flaky 测试比没有测试更糟,发现即降级或修复。

## 6. 架构红线

- 新 UI 代码不得进入 `lib/widgets/ai/ai_chat_stream.dart`;Seminar 相关 UI 一律放 `lib/widgets/ai/seminar/`(R1 进行中也适用)。
- 禁止新增兼容 fallback 层。预发布产品用一次性迁移函数,不养永久兼容层。
- R2 完成后:`AgentRunGraphStore` 事件流是唯一 source of truth,禁止再写 runtime snapshot 双写路径。
- 角色/子 agent 执行必须走 sub-agent 平台(R3 后);禁止再为单一功能新建专用 runtime。
- 代码文件行数 ratchet:`lib/` 单文件 ≤1500 行、`test/` 单文件 ≤2500 行;超限文件在 `tool/size_baseline.txt` 白名单内,只许变短不许变长。

## 7. 提交规范

- 沿用 conventional commits(`feat(seminar): ...`、`refactor(ai): ...`、`docs: ...`)。
- commit message 正文即本切片的完整记录:做了什么、验证命令、结果。
- 不在 commit 里混入无关文档膨胀。
