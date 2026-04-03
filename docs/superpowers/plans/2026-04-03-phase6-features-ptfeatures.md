# Phase 6: PTFeatures Implementation Plan

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

- [ ] Create `Packages/PTFeatures/Package.swift`:

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

- [ ] Create module entry + import test, verify, commit.

---

### Task 2: AppTab Navigation

- [ ] Create `Navigation/AppTab.swift` — tab enum with 6 tabs (Papers, Bookshelf, Notes, Statistics, AI, Settings), SF Symbol icons, localized titles.
- [ ] Test: verify all 6 cases, icon names, ordering.
- [ ] Commit.

---

### Task 3: BookshelfViewModel

- [ ] Create `Bookshelf/BookshelfViewModel.swift` — @Observable class with loadBooks(), search(), sort(), deleteBook(), BookDAO dependency.
- [ ] Test: verify load, search, sort with in-memory DB.
- [ ] Commit.

---

### Task 4: NotesViewModel + StatisticsViewModel

- [ ] Create `Notes/NotesViewModel.swift` — search notes, filter by book.
- [ ] Create `Statistics/StatisticsViewModel.swift` — total reading time, book count, notes count.
- [ ] Commit.

---

### Task 5: AIChatViewModel + SettingsViewModel

- [ ] Create `AIChat/AIChatViewModel.swift` — manages ConversationTree, send message stub.
- [ ] Create `Settings/SettingsViewModel.swift` — loads/saves AppConfig values.
- [ ] Commit.

---

### Task 6: Full Test Suite + Push

- [ ] Run all 6 packages. Push.
