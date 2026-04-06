# Phase 6: PTFeatures Implementation Plan

> **状态：Tasks 1–6 ✅ 已完成（2026-04-03）。书籍导入 + PDF 阅读器 ✅ 已完成（2026-04-04）。Notes / Statistics / AIChat / Settings UI ⏳ 在 worktree 中已完成，待合并至 swift-native。**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the PTFeatures Swift package — ViewModels for all major screens (Bookshelf, Notes, Statistics, AI Chat, Settings), navigation routing, and core feature logic. SwiftUI views are stubs that will be fleshed out during Phase 7 app integration.

**Architecture:** PTFeatures depends on all other packages (PTCore, PTNetworking, PTReader, PTUI, PTAIServices). It contains @Observable ViewModels with business logic and stub SwiftUI views. The actual UI will be refined in Phase 7 when we have a full Xcode project target.

**Tech Stack:** Swift 5.9+, SwiftUI, Observation framework, all PT packages, Swift Testing

---

## File Structure

```
Packages/PTFeatures/
├── Package.swift
├── Sources/PTFeatures/
│   ├── PTFeatures.swift               # Module entry
│   ├── Navigation/
│   │   └── AppTab.swift               # Tab enum for navigation
│   ├── Bookshelf/
│   │   └── BookshelfViewModel.swift   # Library management
│   ├── Notes/
│   │   └── NotesViewModel.swift       # Notes list + search
│   ├── Statistics/
│   │   └── StatisticsViewModel.swift  # Reading stats
│   ├── AIChat/
│   │   └── AIChatViewModel.swift      # Chat with streaming
│   └── Settings/
│       └── SettingsViewModel.swift    # App settings
└── Tests/PTFeaturesTests/
    ├── Navigation/
    │   └── AppTabTests.swift
    ├── Bookshelf/
    │   └── BookshelfViewModelTests.swift
    └── PTFeaturesImportTests.swift
```

---

### Task 1: Package Setup

- [x] Create `Packages/PTFeatures/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTFeatures",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PTFeatures", targets: ["PTFeatures"])],
    dependencies: [
        .package(path: "../PTCore"),
        .package(path: "../PTNetworking"),
        .package(path: "../PTReader"),
        .package(path: "../PTUI"),
        .package(path: "../PTAIServices"),
    ],
    targets: [
        .target(name: "PTFeatures", dependencies: ["PTCore", "PTNetworking", "PTReader", "PTUI", "PTAIServices"]),
        .testTarget(name: "PTFeaturesTests", dependencies: ["PTFeatures"]),
    ]
)
```

- [x] Create module entry + import test, verify, commit.

---

### Task 2: AppTab Navigation

- [x] Create `Navigation/AppTab.swift` — tab enum with 6 tabs (Papers, Bookshelf, Notes, Statistics, AI, Settings), SF Symbol icons, localized titles.
- [x] Test: verify all 6 cases, icon names, ordering.
- [x] Commit.

---

### Task 3: BookshelfViewModel

- [x] Create `Bookshelf/BookshelfViewModel.swift` — @Observable class with loadBooks(), search(), sort(), deleteBook(), BookDAO dependency.
- [x] Test: verify load, search, sort with in-memory DB.
- [x] Commit.

---

### Task 4: NotesViewModel + StatisticsViewModel

- [x] Create `Notes/NotesViewModel.swift` — search notes, filter by book.
- [x] Create `Statistics/StatisticsViewModel.swift` — total reading time, book count, notes count.
- [x] Commit.

---

### Task 5: AIChatViewModel + SettingsViewModel

- [x] Create `AIChat/AIChatViewModel.swift` — manages ConversationTree, send message stub.
- [x] Create `Settings/SettingsViewModel.swift` — loads/saves AppConfig values.
- [x] Commit.

---

### Task 6: Full Test Suite + Push

- [x] Run all 6 packages. Push.

---

## 实现进度（更新于 2026-04-06）

### ✅ 已完成并合并至 swift-native

| 组件 | 文件 | 提交 |
|------|------|------|
| Package 初始化 | `Package.swift`, `PTFeatures.swift` | `b518e647` |
| AppTab 导航枚举 | `Navigation/AppTab.swift` | `5d569855` |
| BookshelfViewModel（加载/搜索/排序/删除） | `Bookshelf/BookshelfViewModel.swift` | `59894ff5` |
| NotesViewModel | `Notes/NotesViewModel.swift` | `640ebda0` |
| StatisticsViewModel | `Statistics/StatisticsViewModel.swift` | `640ebda0` |
| AIChatViewModel | `AIChat/AIChatViewModel.swift` | `7d8a38da` |
| SettingsViewModel | `Settings/SettingsViewModel.swift` | `7d8a38da` |
| **BookImportService** | `Bookshelf/BookImportService.swift` | `41e7d919` |
| **BookshelfViewModel.importBook** | `Bookshelf/BookshelfViewModel.swift` | `41e7d919` |
| **ReaderViewModel**（加载/目录/翻页/进度） | `Reader/ReaderViewModel.swift` | `c2e2811c` |
| **PDFReaderView**（PDFKit 封装） | `Reader/PDFReaderView.swift` | `d2b4cd84` |
| **书架导入按钮 + 阅读器跳转** | `App/ContentView.swift` | `706ea5d5` |

测试覆盖：PTCore 45 个 ✅ | PTFeatures 12 个 ✅

### ⏳ 待合并至 swift-native（已在 worktree 中完成）

以下功能已在各自的 claude/ worktree 分支中实现，尚未合并到 swift-native：

| 功能 | 状态 | 说明 |
|------|------|------|
| Notes UI（完整 SwiftUI 视图） | ⏳ 待合并 | NotesViewModel 已在 swift-native，View 层在 worktree |
| Statistics UI（仪表盘、热力图） | ⏳ 待合并 | StatisticsViewModel 已在 swift-native，View 层在 worktree |
| Settings UI（全部设置子页面） | ⏳ 待合并 | SettingsViewModel 已在 swift-native，View 层在 worktree |
| AIChat UI（聊天界面） | ⏳ 待合并 | AIChatViewModel 已在 swift-native，View 层在 worktree |
