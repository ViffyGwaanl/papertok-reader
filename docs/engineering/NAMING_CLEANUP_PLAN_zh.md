# PaperTok Reader 命名收口计划（工程方案 v1）

> 目标：把项目当前“对外产品名已改、内部技术底座仍残留 anx”的状态，整理成一个可执行、分风险、可回滚的收口计划。
>
> 2026-03-07 更新：低风险收口已完成，已覆盖 README / docs 入口、App 内可见文案 / l10n、以及 iOS / Android 显示名。
>
> **2026-04-14 更新：全部三层收口已完成。** 低风险层（文档/文案）、中风险层（桌面 artifact / Wave U commit `9cfced66`）、高风险层（Dart package rename / Sub-project A2 commit `b0fe7c2b`）全部落地。本文档现用作历史记录 + 命名真值表。

## 1. 问题定义（已解决）

项目之所以曾经反复被叫成 `anx` / `anx-reader`，不是因为没有改名，而是因为**存在多套并存的命名真值源**：

- 对外品牌 / 产品文案：已统一到 `PaperTok Reader` ✅
- 仓库 / 工作区 / 上游关系：仓库 slug `papertok-reader`、工作目录 `papertok-reader` ✅
- Flutter package / import / 部分构建产物：2026-04-14 由 Sub-project A2 完成全部 import rename ✅

所有三层现已收口，`anx` 只在 git 历史和上游来源说明中保留。

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

### 2.2 仓库 / 工作区层（已完成）

- 工作目录名：`papertok-reader` ✅
- 仓库 slug：`papertok-reader` ✅
- 上游来源 `Anx Reader` 在 README / changelog 中以“上游 / 历史来源”形式保留

### 2.3 技术底座层（已完成）

2026-04-14 Wave U + A2 完成：

- `pubspec.yaml` package name：`papertok_reader` ✅
- 458 个 Dart 文件的 `package:anx_reader/...` → `package:papertok_reader/...` ✅
- Linux / Windows / macOS 桌面 artifact 名：`papertok_reader` ✅
- iOS `CFBundleName`：`papertok_reader` ✅
- Linux `APPLICATION_ID`：`ai.papertok.paperreader` ✅
- Windows Runner.rc CompanyName / ProductName：`PaperTok Reader` ✅

已抹掉的历史残留：
- `com.anxcye.anx_reader`（Linux APPLICATION_ID）
- `com.anxcye`（Windows CompanyName / Copyright）
- `Paper Reader`（macOS PRODUCT_NAME，现为 `PaperTok Reader`）

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

## 4. 风险分层计划（全部完成）

### 4.1 低风险层 ✅（已完成）

- README / docs index / 发布说明 / QA 文档
- App 内对外文案 / l10n
- iOS / Android 显示名元数据

### 4.2 中风险层 ✅（Wave U, 2026-04-14, commit `9cfced66`）

目标：统一 repo / workspace / release artifact 口径。

完成范围：
- iOS Info.plist `CFBundleName` → `papertok_reader`
- macOS `PRODUCT_NAME` → `PaperTok Reader`（原 `Paper Reader`）
- macOS `PRODUCT_COPYRIGHT` 清理（去掉 `com.anxcye`）
- macOS pbxproj 3 处 `TEST_HOST` 指向 `PaperTok Reader.app`
- Linux `BINARY_NAME` → `papertok_reader`
- Linux `APPLICATION_ID` → `ai.papertok.paperreader`
- Windows `project(papertok_reader)` + `BINARY_NAME`
- Windows Runner.rc 全部资源字段（CompanyName / FileDescription / InternalName / OriginalFilename / ProductName / LegalCopyright）

### 4.3 高风险层 ✅（Sub-project A2, 2026-04-14, commit `b0fe7c2b`）

目标：把 Dart package identity 从 `anx_reader` 重命名为 `papertok_reader`。

完成范围：
- `pubspec.yaml` `name: papertok_reader`
- **458 个 Dart 文件**的 `package:anx_reader/...` → `package:papertok_reader/...`
- 原子 single-commit 落地，避免构建在 rename 中途被打断
- Memory 完整测试套件 43/43 通过验证

### 4.4 为什么最终还是做了 A2

原计划把 A2 单独立项、先做 blast radius 评估。实际情况：
- Wave U 做完后，技术底座和对外品牌之间的不一致变得非常刺眼（`pubspec name: anx_reader` 和所有其他都说 PaperTok）
- 458 个文件的 import rename 本质是纯机械文本替换，blast radius 集中在编译期（不在运行时），容易验证
- Memory 功能完整落地后，代码底座已经稳定，是做 A2 的最佳窗口
- 用 sed + `find -print0 | xargs -0` 在一次 subagent run 里全部替换，atomic commit，零残留

## 5. 执行回顾

- **Step 1** ✅ 低风险收口：文档 / App 文案 / 移动端显示名
- **Step 2** ✅ Wave U：桌面 artifact + iOS CFBundleName + 去 `com.anxcye`
- **Step 3** ✅ Sub-project A2：Dart package rename（原本认为要单独立项，最终作为 Memory 完成后的收尾落地）

## 6. 术语真值表（最终版）

| 层 | 值 |
|---|---|
| 对外产品名 | `PaperTok Reader` |
| 仓库 slug | `papertok-reader` |
| Dart package | `papertok_reader` |
| iOS bundle ID | `ai.papertok.paperreader` |
| Android applicationId | `ai.papertok.paperreader` |
| Linux APPLICATION_ID | `ai.papertok.paperreader` |
| Windows BINARY_NAME | `papertok_reader` |
| macOS PRODUCT_NAME | `PaperTok Reader` |
| iOS CFBundleDisplayName | `PaperTok Reader` |
| Android android:label | `PaperTok Reader` |
| 上游来源（历史说明） | `Anx Reader` |

## 7. 结论

2026-04-14 命名收口全部完成：
- **对外文案层** 早已统一
- **中风险 artifact 层**（Wave U）与**高风险 package 层**（A2）在同一天先后完成
- `anx_reader` 仅在 git 历史和 README 的“上游来源”说明中保留
- 后续不再需要命名相关的清理工作

本文档归档为历史记录。
