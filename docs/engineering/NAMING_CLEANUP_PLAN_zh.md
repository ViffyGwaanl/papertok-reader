# PaperTok Reader 命名收口计划（工程方案 v1）

> 目标：把项目当前“对外产品名已改、内部技术底座仍残留 anx”的状态，整理成一个可执行、分风险、可回滚的收口计划。

## 1. 问题定义

当前项目之所以还会反复被叫成 `anx` / `anx-reader`，不是因为没有改名，而是因为**存在多套并存的命名真值源**：

- 对外品牌 / 产品文案：不少地方已经是 `Paper Reader` / `PaperTok Reader`
- 仓库/工作区/上游关系：仍大量是 `anx-reader`
- Flutter package / import / 构建产物：仍大量是 `anx_reader`

所以这不是单点 bug，而是一个典型的**命名分层未收口问题**。

## 2. 当前命名分层（As-Is）

## 2.1 产品层

目标产品名应该统一为：
- **PaperTok Reader**（产品名）

需要避免的混写：
- `Paper Reader`
- `papertok-reader`
- `anx-reader`

### 建议口径

- **产品名**：`PaperTok Reader`
- **仓库 slug**：`papertok-reader`
- **上游来源**：`Anx Reader`

## 2.2 仓库 / 工作区层

当前仍存在：
- 工作目录名：`anx-reader`
- 远端中既有 `papertok-reader`，也有 `anx-reader` 上游/fork 关系

这会不断强化“这是 anx-reader 项目”的开发者心智。

## 2.3 技术底座层

当前仍保留大量：
- `pubspec.yaml` package name：`anx_reader`
- 大量 `package:anx_reader/...` import
- 桌面产物 / 脚本 / 某些平台配置仍带 `anx_reader`

这层不是简单文本替换，而是高风险技术重命名。

## 3. 设计原则

## 3.1 先统一对外口径，再决定是否做技术大迁移

优先级应该是：
1. 产品文档、发布文案、交互中统一用 `PaperTok Reader`
2. 说明哪些地方的 `Anx Reader` 只是“上游来源 / 历史技术名”
3. 最后再单独评估是否做 package rename

## 3.2 不把“产品名改对”与“技术包名大迁移”绑在同一波

原因：
- 对外口径统一是低风险、高收益
- package rename 是高风险、高 blast radius
- 两者一起做会让发布链路风险急剧上升

## 3.3 保留必要的历史可追溯性

不建议把所有 `Anx Reader` 痕迹无差别抹掉。
应保留：
- 上游来源说明
- compat / import / 迁移脚注
- 某些暂未迁移的技术标识说明

## 4. 风险分层计划

## 4.1 低风险（立即可做）

目标：统一所有**对外可见**命名，不碰核心技术标识。

### 范围

- 文档标题 / 文案
- 发布说明 / QA 文档
- 产品介绍页 / docs index
- Share / AI / Memory 方案文档
- release notes / troubleshooting 中的产品称呼

### 规则

- 默认称 `PaperTok Reader`
- 只有在说明上游项目或技术历史时，才提 `Anx Reader`
- 尽量避免使用含糊的 `Paper Reader`

### 验收标准

- 新文档与更新后的主要文档，对外都统一为 `PaperTok Reader`
- 我在后续沟通里默认也只叫 `PaperTok Reader`

## 4.2 中风险（第二阶段）

目标：统一 repo/workspace/path/release artifact 口径，但仍不动 Flutter 根包名。

### 范围

- 本地工作目录名
- 状态文件路径
- 构建脚本中的 repo/path 命名
- Release artifact / installer / DMG / workflow artifact 文案
- 某些平台可安全修改的 display/artifact 名

### 原则

- 尽量只改“路径/文案/产物名”
- 不改 import 根名
- 不改移动端核心 bundle / applicationId（除非已确认安全）

### 风险

- 脚本路径硬编码
- CI / 本地缓存路径漂移
- Release tooling 引用失配

## 4.3 高风险（单独项目）

目标：把技术底座从 `anx_reader` 真正重命名为 `papertok_reader`。

### 涉及范围

- `pubspec.yaml` package name
- 约数百处 `package:anx_reader/...` import
- Dart/Flutter generated references
- Windows/Linux/macOS 产物名
- 部分 iOS/Android 工程配置
- 可能涉及 bundle / scheme / path / build scripts / signing assumptions

### 为什么不能和当前收口混做

- 影响面过大
- 回滚成本高
- 极易把“文档收口”演变成“全仓大重构”
- 当前主线目标是产品化收口，不是技术底座大迁移

### 建议

把它作为一个单独的 rename 项目，单独评估与执行。

## 5. 推荐执行顺序

### Step 1（当前）

完成低风险收口：
- 文档统一
- 说明产品名 / 仓库名 / 上游名的区别
- 把模糊用法改成 `PaperTok Reader`

### Step 2

完成中风险收口：
- 工作区路径与发布路径口径统一
- 构建产物名与可见文案统一

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
- 以后所有产品相关沟通口径

因此建议先完成文档层统一，再考虑更深的技术迁移。

## 8. 结论

当前最正确、最低风险的策略是：

- **对外统一使用 `PaperTok Reader`**
- **把 `Anx Reader` 收敛为“上游/历史技术来源”**
- **不在当前收口阶段启动 `anx_reader -> papertok_reader` 全仓重命名**

这样可以先把品牌、文档、沟通、发布口径全部收正，同时避免 package rename 带来的大规模工程风险。
