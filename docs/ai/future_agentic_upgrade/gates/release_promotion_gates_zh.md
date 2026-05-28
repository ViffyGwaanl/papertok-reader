# Release Promotion Gates

## 1. Pre-Gate

涉及移动端 UI、deep link、索引进度、Seminar 入口或同步导出的任务，在进入发布候选前必须确认：

- 关键路径有 focused tests 或 smoke checklist。
- iPhone/iPad/Android 的主要差异已列出。
- 新入口可关闭或降级。
- 失败提示和恢复路径可见。

## 2. Required Acceptance

至少覆盖适用项：

- 阅读页不因 AI 面板、Seminar 入口或进度提示遮挡核心阅读。
- `paperreader://reader/open?...` 可拉起并定位。
- 长任务失败后有重试、取消或恢复状态。
- 同步/导出失败不修改用户资产。
- 成本、资料范围、web 使用状态可见。

## 3. Release Notes Requirements

发布说明必须写：

- 新增入口。
- 默认关闭/开启状态。
- 隐私或外发数据变化。
- 已知降级路径。
- 需要用户重新索引、重新登录或重新确认的事项。

