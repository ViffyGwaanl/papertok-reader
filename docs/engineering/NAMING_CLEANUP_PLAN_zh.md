# PaperTok Reader 命名收口计划（工程方案 v1）

> 目标：把项目当前“对外产品名已改、内部技术底座仍残留 anx”的状态，整理成一个可执行、分风险、可回滚的收口计划。
>
> 2026-03-07 更新：低风险收口已完成，已覆盖 README / docs 入口、App 内可见文案 / l10n、以及 iOS / Android 显示名。本文档现用于描述已完成边界与下一阶段计划。

## 1. 问题定义

项目之所以仍会反复被叫成 `anx` / `anx-reader`，不是因为没有改名，而是因为**存在多套并存的命名真值源**：

- 对外品牌 / 产品文案：现已统一到 `PaperTok Reader`
- 仓库 / 工作区 / 上游关系：仍大量保留 `anx-reader`
- Flutter package / import / 部分构建产物：仍大量保留 `anx_reader`

所以这不是单点 bug，而是一个典型的**命名分层未收口问题**。

## 2. 当前命名分层（As-Is）

### 2.1 产品层

目标产品名：
- **PaperTok Reader**（产品名）

需要避免的混写：
- `Paper Reader`
- `papertok-reader`
- `anx-reader`

### 建议口径

- **产品名**：`PaperTok Reader`
- **仓库 slug**：`papertok-reader`
- **上游来源**：`Anx Reader`

### 2.2 仓库 / 工作区层

当前仍存在：
- 工作目录名：`anx-reader`
- 远端中同时存在 `papertok-reader` 与 `anx-reader` 上游 / fork 关系

这会持续强化“这是 anx-reader 项目”的开发者心智。

### 2.3 技术底座层

当前仍保留大量：
- `pubspec.yaml` package name：`anx_reader`
- `package:anx_reader/...` import
- 桌面产物 / 脚本 / 某些平台配置仍带历史命名

这层不是简单文本替换，而是高风险技术重命名。

## 3. 设计原则

### 3.1 先统一对外口径，再决定是否做技术大迁移

优先级应当是：
1. 产品文档、发布文案、交互统一使用 `PaperTok Reader`
2. 说明哪些地方的 `Anx Reader` 只是“上游来源 / 历史技术名”
3. 最后再单独评估是否做 package rename

### 3.2 不把“产品名改对”与“技术包名大迁移”绑在同一波

原因：
- 对外口径统一是低风险、高收益
- package rename 是高风险、高 blast radius
- 两者一起做会让发布链路风险急剧上升

### 3.3 保留必要的历史可追溯性

不建议把所有 `Anx Reader` 痕迹无差别抹掉。
应保留：
- 上游来源说明
- compat / import / 迁移脚注
- 某些暂未迁移的技术标识说明

## 4. 风险分层计划

### 4.1 低风险（已完成）

目标：统一所有**对外可见**命名，不碰核心技术标识。

### 已完成范围

- README / docs index / 发布说明 / QA 文档
- App 内对外文案
- 主要 l10n 中的产品名
- iOS / Android 显示名元数据

### 已完成规则

- 默认称 `PaperTok Reader`
- 只有在说明上游项目或技术历史时，才提 `Anx Reader`
- 不再使用含糊的 `Paper Reader`

### 已完成验收

- 主要对外文档与产品入口统一为 `PaperTok Reader`
- App 可见品牌文案已统一为 `PaperTok Reader`
- iOS / Android 显示名已统一为 `PaperTok Reader`

### 4.2 中风险（下一阶段）

目标：统一 repo / workspace / release artifact 口径，但仍不动 Flutter 根包名。

### 范围

- 本地工作目录名
- 状态文件路径
- 构建脚本中的 repo / path 命名
- Release artifact / installer / workflow artifact 文案
- 某些平台可安全修改的 display / artifact 名
- macOS / 桌面端仍残留的显示名 / 产物名

### 原则

- 尽量只改“路径 / 文案 / 产物名”
- 不改 import 根名
- 不改移动端核心 bundle / applicationId / URL scheme

### 风险

- 脚本路径硬编码
- CI / 本地缓存路径漂移
- Release tooling 引用失配
- 桌面产物 / packaging 验证成本更高

### 4.3 高风险（单独项目）

目标：把技术底座从 `anx_reader` 真正重命名为 `papertok_reader`。

### 涉及范围

- `pubspec.yaml` package name
- 约数百处 `package:anx_reader/...` import
- Dart / Flutter generated references
- Windows / Linux / macOS 产物名
- 部分 iOS / Android 工程配置
- 可能涉及 bundle / scheme / path / build scripts / signing assumptions

### 为什么不能和当前收口混做

- 影响面过大
- 回滚成本高
- 极易把“文档收口”演变成“全仓大重构”
- 当前主线目标是产品化收口，不是技术底座大迁移

### 建议

把它作为一个单独 rename 项目，单独评估与执行。

## 5. 推荐执行顺序

### Step 1（已完成）

完成低风险收口：
- 文档统一
- App 可见文案统一
- iOS / Android 显示名统一
- 保留技术标识不变

### Step 2（下一阶段）

完成中风险收口：
- 工作区路径与发布路径口径统一
- 构建产物名与可见文案统一
- macOS / 桌面 artifact naming 收口

### Step 3（单独立项）

是否要做高风险 package rename：
- 先出 blast radius 报告
- 再决定是否启动

## 6. 术语真值表（推荐写法）

### 对外 / 产品

- `PaperTok Reader`

### 仓库 slug

- `papertok-reader`

### 上游来源

- `Anx Reader`

### 当前技术底座（暂保留）

- `anx_reader`

## 7. 与后续工作的关系

这份命名计划会直接影响：
- Memory 工作流文档
- Share / Shortcuts / diagnostics 文档
- 发布说明与 QA 文档
- 后续所有产品相关沟通口径
- 未来的路径 / artifact / package rename 评估

因此当前最稳的策略仍是：先完成低风险层统一，再分阶段推进更深的技术收口。

## 8. 结论

当前最正确、最低风险的策略是：

- **对外统一使用 `PaperTok Reader`**
- **把 `Anx Reader` 收敛为“上游 / 历史技术来源”**
- **不在当前收口阶段启动 `anx_reader -> papertok_reader` 全仓重命名**

低风险收口已经完成；下一步如要继续推进，应进入中风险第二阶段，而不是直接跳到 package rename。
