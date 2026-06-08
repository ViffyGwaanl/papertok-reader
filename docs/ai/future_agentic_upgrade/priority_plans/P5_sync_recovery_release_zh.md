# P5 Sync Recovery Release

> 状态：In Progress
> 最后更新：2026-06-08
> 目标：把 P1-P4 的 AI 闭环做成可恢复、可同步、可测试、可发布的产品能力。

## 1. 用户价值

用户不关心内部有多少 runtime、索引、缓存、队列和 Review adapter。用户关心的是：

- App 重启后研讨会、图谱构建、索引任务不会悄悄丢失。
- 失败时知道发生了什么，能继续、重试或放弃。
- 跨设备时知识资产不会被静默覆盖。
- 发布版不会把草稿、派生缓存或低置信 AI 内容当成正式资产。
- TestFlight 或正式版有清楚迁移说明。

## 2. 当前状态

当前分支已有：

- Knowledge sync/export、manifest、Markdown、HTML、Anki TSV、sync bundle。
- 远端 preview、安全写回、部分 conflict Review handoff。
- Seminar checkpoint、scoped runtime、queued job 和 provider/budget 诊断。
- AI Index 层状态、部分修复入口和失败提示。
- 既有 release/TestFlight 脚本和构建经验。
- `2026-06-08` 已把发布目标 commit `2e0ab4a5f408b7c01ad4fc45ee659736e8a54528` 推送并完成一次 release promotion：版本 `1.68.7+6513`，iOS 上传 App Store Connect/TestFlight 后 build `6513` 状态为 `VALID`，GitHub Release `android-v1.68.7-6513` 已包含 Android APK、macOS zip 和 `CHECKSUMS.txt`。

当前主要问题：

- P1 原生 Seminar 完成后，需要重新收口聊天消息 schema、恢复和旧历史兼容。
- P2 AI semantic graph builder 会引入长任务、成本、失败重试和派生缓存失效。
- P3 ANN/AI graph 构建需要真机资源 gate 和可恢复 job。
- P4 Review Inbox 重新定位后，需要迁移旧 pending 项和旧文案。
- 本次 build `1.68.7+6513` 是当前分支切片的 TestFlight/GitHub 预发布，不等于 v7 全部完成；P1-P4 的新闭环、迁移说明、资源 gate 和后续稳定版发布边界仍要继续收口。

## 3. 阶段计划

### P5-S1：AI Chat Seminar 恢复 gate

围绕 P1 的原生 Seminar，补完整 message part 历史恢复、旧 panel 历史兼容、scoped runtime state 和 interrupted 状态。

验收：

- App 重启后用户能看懂研讨会处于待开始、运行中、已完成、已中断或需恢复。
- 恢复前显示 provider/model/evidence mismatch。
- 不重复外发已完成角色。

### P5-S2：AI graph build job 恢复 gate

围绕 P2 的 AI semantic graph builder，设计可暂停、可重试、可失效的 job。

验收：

- 每个章节抽取可单独失败和重试。
- 模型/provider/schema 变化可触发重建。
- 取消或失败不会写 ready 状态。

### P5-S3：ANN 和索引真机资源 gate

围绕 P3 的 ANN 和索引任务，补移动端资源限制。

验收：

- 大书构建有内存和耗时 gate。
- 后台/前台策略明确。
- extension 不可用时降级搜索可用。

### P5-S4：Review/asset migration gate

围绕 P4 的 Review Inbox 收窄，处理旧 pending、旧 draft 和旧 Review 文案。

验收：

- 旧 pending items 不丢。
- 普通保存路径不再新增普通 ReviewItem。
- 用户能区分历史待审和新异常队列。

### P5-S5：发布回归套件

围绕 P1-P4 形成发布前回归命令集合。

验收：

- AI Chat Seminar 原生入口测试。
- AI graph builder/schema/parser 测试。
- hybrid retrieval/ANN readiness 测试。
- AI reviewer/Review Inbox 测试。
- sync/export/recovery 测试。
- 触及文件 analyze、format、diff check。

### P5-S6：TestFlight / release promotion

把 v7 切片完成后的版本走构建、上传、发布说明和迁移说明。

验收：

- iOS/TestFlight artifact 有日志证据。
- Android/macOS artifact 或明确边界。
- 发布说明写清用户能用什么、还不能用什么、旧数据如何处理。

当前证据：

- `2026-06-08` 已完成 build `1.68.7+6513` 最新 promotion：target commit `2e0ab4a5f408b7c01ad4fc45ee659736e8a54528`。
- iOS 日志：`/Users/gwaanl/.openclaw/workspace/artifacts/papertok-reader/2e0ab4a5-20260608092222/logs/ios.log` 记录上传成功；ASC build state 查询返回 `buildNumber=6513`、`processingState=VALID`、`uploadedDate=2026-06-08T06:43:14-07:00`。
- Android/macOS artifact：GitHub Release `https://github.com/ViffyGwaanl/papertok-reader/releases/tag/android-v1.68.7-6513` 已包含 `papertok-reader-1.68.7-6513.apk`、`PaperTok-Reader-macOS-1.68.7-6513.zip` 和 `CHECKSUMS.txt`。macOS app 是脚本构建出的 unsigned `.app`，本轮以 zip artifact 发布，不等同于签名/公证完成。
- release 脚本最终有 `cleanup_paths[@]: unbound variable` 清理警告，但命令 exit `0`，iOS/Android/macOS/GitHub release 证据均已单独验证。

## 4. 不做事项

- 不在 P1/P2 主闭环未完成前用发布收尾掩盖体验缺口。
- 不把 derived cache 当作用户资产同步。
- 不同步 API key。
- 不在没有 release gate 的情况下宣称发布版可用。

## 5. 更新要求

推进 P5 时必须更新：

- 本文件的 gate 和发布状态。
- `../implementation_status_zh.md` 的验证命令和 artifact 证据。
- `../04_user_facing_activation_plan_zh.md` 的发布可用边界。
- 如执行发布，还要更新 release notes 或对应发布文档。

## 6. 状态更新记录

- 2026-06-08：完成 build `1.68.7+6513` release promotion。`git push origin codex/future-agentic-upgrade` 已把 HEAD `2e0ab4a5f408b7c01ad4fc45ee659736e8a54528` 推到远端；`FORCE_MANUAL_SIGNING=1 ./scripts/release_from_commit.sh 2e0ab4a5f408b7c01ad4fc45ee659736e8a54528` 构建并上传 iOS/TestFlight、Android APK、macOS unsigned app，GitHub Release 为 `android-v1.68.7-6513`；后续手动补传 macOS zip 并更新 `CHECKSUMS.txt`。本轮关闭了“当前分支完全没有 release promotion”的旧口径，但 P5 仍为 In Progress，因为跨设备后台同步、迁移说明、P1-P4 完整 gate 和稳定版边界仍未完成。
- 2026-06-03：建立 P5 详细计划。当前状态为 In Progress；已有同步/恢复/发布底座，但需要围绕 v7 的 P1-P4 新闭环重新收口。
