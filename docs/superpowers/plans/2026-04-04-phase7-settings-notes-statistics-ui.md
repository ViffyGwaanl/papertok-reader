# Phase 7：Settings / Notes / Statistics 页面 UI 实现

> **状态：⏳ 待合并** — 代码已在 worktree `condescending-bouman`（分支 `claude/condescending-bouman`，commit `3b23100b`）完成实现，尚未合并到 `swift-native`。

**目标：** 为 Settings、Notes、Statistics 三个页面实现真正的 SwiftUI View，替换 `ContentView.swift` 中的 `*PlaceholderView` 占位符。

**架构：** 所有 ViewModel（`SettingsViewModel`、`NotesViewModel`、`StatisticsViewModel`）在 Phase 6 已完整实现，本阶段仅补齐 View 层。全部使用 MorandiPalette、AppTypography、AppSpacing 设计系统。

**技术栈：** Swift 5.9+、SwiftUI、Observation framework、PTCore、PTFeatures、PTUI

---

## 已实现内容（commit `3b23100b`）

### SettingsScreen

- [x] Apple HIG `Form`/`Section` 布局
- [x] 外观设置：主题选择器（浅色 / 深色 / 跟随系统）
- [x] 外观设置：OLED 深色模式开关
- [x] 外观设置：Morandi 强调色网格选择器（6 色）
- [x] 阅读设置：默认字号滑块
- [x] 阅读设置：翻页模式选择器（滚动 / 翻页）
- [x] About 区块（版本号、开源协议链接）
- [x] 绑定 `SettingsViewModel.save()` 持久化到 `UserDefaults`

### NotesScreen

- [x] 按书籍分组展示笔记（`groupedNotes` 计算属性）
- [x] 每条笔记显示：高亮色条、笔记内容、章节上下文
- [x] 搜索栏（`.searchable`）+ 无结果空态
- [x] 左滑删除（`.swipeActions`）
- [x] 加载状态 `ProgressView`
- [x] 绑定 `NotesViewModel`（加载、搜索、删除）

### StatisticsScreen

- [x] 三张统计卡片：总阅读时长、书籍数、笔记数
- [x] 91 天阅读热力图（`LazyVGrid`，每格颜色按阅读分钟数深浅）
- [x] 热力图图例
- [x] `StatisticsViewModel` 新增 `dailyReadingData: [String: Int]`，从 `ReadingTimeDAO` 加载

### ContentView.swift 路由更新

- [x] `.notes` → `NotesScreen(database: database)`
- [x] `.statistics` → `StatisticsScreen(database: database)`
- [x] `.settings` → `SettingsScreen()`

---

## 文件变更（待合并）

```
App/ContentView.swift                              MODIFY — 替换3个占位符，新增3个Screen实现（+417行）
Packages/PTFeatures/Sources/PTFeatures/
  Statistics/StatisticsViewModel.swift             MODIFY — 新增 dailyReadingData 属性（+13行）
```

---

## 合并步骤

合并前确认：

```bash
# 查看 worktree 与 swift-native 的差异
cd /Users/gwaanl/GitHub/papertok-reader
git diff swift-native...claude/condescending-bouman --stat
```

合并方式（cherry-pick 单条 commit）：

```bash
cd /Users/gwaanl/GitHub/papertok-reader
git cherry-pick 3b23100b
```

或直接合并分支：

```bash
git merge --no-ff claude/condescending-bouman -m "feat(app): merge Settings, Notes, Statistics screens from Phase 7"
```

---

## 合并后验证

- [ ] 编译通过（`xcodebuild` 或 Xcode）
- [ ] Settings 页面显示正常，修改后持久化到 UserDefaults
- [ ] Notes 页面能加载、搜索、删除笔记
- [ ] Statistics 页面热力图正常渲染
- [ ] 三个页面不再显示 "coming soon" 占位

---

## 依赖关系

- 依赖 Phase 6（`PTFeatures` ViewModel 层）：✅ 已完成
- 依赖 Phase 5（`PTAIServices`、`PTCore` 数据库）：✅ 已完成
- Papers 页面（Phase 11）：独立，不阻塞本阶段
- AI Chat 页面（Phase 9）：独立，不阻塞本阶段
