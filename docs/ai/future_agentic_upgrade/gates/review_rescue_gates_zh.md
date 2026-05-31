# Review And Rescue Gates

## 1. 什么时候运行

每个 Epic 完成前必须运行一次 rescue review。若环境没有独立 `/codex:rescue` 工具，则派一个独立 reviewer subagent，要求只读审查并输出问题清单。

## 2. Review Inputs

Reviewer 至少读取：

- 本 Epic 文档。
- 相关 Capability 和 Agent Task。
- 触碰过的代码或文档 diff。
- 对应 `gates/` 文件。
- 测试命令和输出。

## 3. Checklist

Reviewer 必查：

- 是否还存在 `02_agent_execution_model_zh.md` 定义的不可执行表达。
- 数据归属是否清楚：source-of-truth、derived-cache、user-authored、AI draft、AI approved。
- SourceRef 是否保留。
- 是否有无证据内容进入正式知识库。
- 工具权限是否按 scene 限制。
- 写入是否需要 Review 或显式确认。
- 测试是否能由命令复现。
- 是否碰了 Epic 之外的模块。
- 是否复制外部项目代码或引入许可证风险。

## 4. Acceptance

Epic 进入 `Accepted` 前必须有：

- reviewer 问题清单。
- 每个问题的处理结果：fixed、accepted risk、not applicable。
- 最终验证命令。
- 剩余风险。

## 5. Blocking Findings

出现以下任一问题，Epic 不能 Accepted：

- AI draft 静默写入用户资产。
- API key 或敏感正文进入明文同步。
- 无 evidence 的正式卡片、图节点或 Seminar claim。
- `ai_index.db` 被当作跨端 source-of-truth。
- 测试或验收无法复现。
- 外部 AGPL/商业代码未经隔离审查直接复制。
