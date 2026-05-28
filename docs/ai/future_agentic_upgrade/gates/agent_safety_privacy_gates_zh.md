# Agent Safety And Privacy Gates

## 1. Pre-Gate

任何涉及 AI 生成、外发正文、工具写入或同步的任务，执行前必须确认：

- AI 生成内容默认是 `draft`。
- 写入 notes、memory、cards、tags、sync assets 前必须进入 Review 或用户显式确认。
- 外发书籍正文、笔记、卡片、复习弱点给 LLM/embedding provider 前有功能级开关或明确提示。
- API key 不进入 WebDAV 明文同步。
- 第三方 AGPL/商业项目只借鉴架构思想，不复制代码。

## 2. Required Acceptance

任务完成时必须证明：

- 无未确认 AI 内容进入正式用户资产。
- 敏感字段没有进入日志、同步快照或明文备份。
- 工具权限符合 scene 白名单。
- 写工具有审批或显式确认路径。

## 3. Rescue Review Questions

- 这个任务是否把模型推断当成用户确认事实？
- 是否有任何无 evidence 的内容进入正式知识库？
- 是否新增外发数据路径但没有提示或开关？
- 是否新增同步字段但没有密钥排除策略？
- 是否复制了外部项目代码或许可证不明内容？

