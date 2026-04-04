# Phase 11：Papers 学术论文流实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 在 PTFeatures 包中实现完整的 Papers（学术论文流）SwiftUI 视图层，1:1 对标 Flutter 版 `lib/page/home_page/papers_page.dart`，包括垂直卡片流、无限滚动加载、点赞收藏、日期筛选、搜索、论文详情页和 PDF/EPUB 下载。

**架构：** PTFeatures/Papers 目录下新增 `PapersViewModel`（@Observable）和 SwiftUI 视图。`PaperTokAPI`（PTNetworking 已实现）负责数据请求。本地收藏持久化到 UserDefaults（对标 Flutter 的 Prefs）。下载进度通过 URLSession.downloadTask 跟踪。

**技术栈：** Swift 5.9+, SwiftUI, PTNetworking (PaperTokAPI, PaperTokCard, PaperTokDetail), PTUI (Morandi 色系), Observation 框架

**前置依赖：** Phase 2 PTNetworking ✅ (PaperTokAPI, PaperTokCard, PaperTokDetail), Phase 4 PTUI ✅, Phase 6 PTFeatures 基础结构 ✅

**参考 Flutter 文件：**
- `lib/page/home_page/papers_page.dart` — 主论文流页面（500+ 行）
- `lib/page/papers/paper_detail_page.dart` — 论文详情页
- `lib/service/papertok/papertok_api.dart` — API 客户端
- `lib/service/papertok/models.dart` — 数据模型

---

## 文件结构

```
Packages/PTFeatures/Sources/PTFeatures/Papers/
├── PapersViewModel.swift                # 新建：@Observable 状态管理
├── PapersView.swift                     # 新建：主论文流 + 筛选 + 搜索
├── PaperCardView.swift                  # 新建：单张卡片（图片轮播 + 标题 + 摘要）
├── PaperDetailView.swift                # 新建：论文详情底部弹窗
├── PapersFilterBar.swift                # 新建：日期筛选 + 收藏筛选 + 搜索栏
└── PaperDownloadButton.swift           # 新建：下载进度按钮

Packages/PTFeatures/Tests/PTFeaturesTests/Papers/
├── PapersViewModelTests.swift           # 新建
└── PaperDownloadButtonTests.swift       # 新建
```

---

### Task 1：PapersViewModel — 数据加载、筛选、收藏

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/Papers/PapersViewModel.swift`
- Create: `Packages/PTFeatures/Tests/PTFeaturesTests/Papers/PapersViewModelTests.swift`

- [ ] **Step 1：编写失败测试**

```swift
import Testing
@testable import PTFeatures
import PTNetworking

@Suite("PapersViewModel")
struct PapersViewModelTests {
    @Test("初始状态：cards 为空，未加载")
    func initialState() {
        let vm = PapersViewModel(api: MockPaperTokAPI())
        #expect(vm.cards.isEmpty)
        #expect(!vm.isLoading)
        #expect(vm.error == nil)
    }

    @Test("toggleLike 切换收藏状态")
    func toggleLike() {
        let vm = PapersViewModel(api: MockPaperTokAPI())
        let card = PaperTokCard.fixture(id: 42)
        vm.cards = [card]
        vm.toggleLike(card)
        #expect(vm.likedIds.contains(42))
        vm.toggleLike(card)
        #expect(!vm.likedIds.contains(42))
    }

    @Test("searchQuery 过滤 visibleCards")
    func searchFilter() {
        let vm = PapersViewModel(api: MockPaperTokAPI())
        vm.cards = [
            PaperTokCard.fixture(id: 1, title: "Swift Programming"),
            PaperTokCard.fixture(id: 2, title: "Python ML"),
        ]
        vm.searchQuery = "swift"
        #expect(vm.visibleCards.count == 1)
        #expect(vm.visibleCards.first?.id == 1)
    }

    @Test("likedOnly 为 true 时只显示收藏")
    func likedOnlyFilter() {
        let vm = PapersViewModel(api: MockPaperTokAPI())
        vm.cards = [
            PaperTokCard.fixture(id: 1, title: "Paper A"),
            PaperTokCard.fixture(id: 2, title: "Paper B"),
        ]
        vm.likedIds = [1]
        vm.likedOnly = true
        #expect(vm.visibleCards.count == 1)
        #expect(vm.visibleCards.first?.id == 1)
    }
}

// Mock API for tests
struct MockPaperTokAPI: PaperTokAPIProtocol {
    func fetchRandomPapers(limit: Int, language: String, day: String?) async throws -> [PaperTokCard] { [] }
    func fetchPaperDetail(id: Int, language: String) async throws -> PaperTokDetail {
        throw URLError(.notConnectedToInternet)
    }
}

extension PaperTokCard {
    static func fixture(id: Int, title: String = "Test Paper") -> PaperTokCard {
        PaperTokCard(id: id, titles: [title], extract: "Abstract...", day: "2024-01-01", images: [])
    }
}
```

- [ ] **Step 2：运行，确认失败**

运行: `cd Packages/PTFeatures && swift test --filter PapersViewModelTests`
预期: FAIL — PapersViewModel not found

- [ ] **Step 3：实现 PapersViewModel**

```swift
import Foundation
import Observation
import PTNetworking

/// Protocol for PaperTok API to enable mock injection in tests.
public protocol PaperTokAPIProtocol: Sendable {
    func fetchRandomPapers(limit: Int, language: String, day: String?) async throws -> [PaperTokCard]
    func fetchPaperDetail(id: Int, language: String) async throws -> PaperTokDetail
}

extension PaperTokAPI: PaperTokAPIProtocol {}

@Observable
public final class PapersViewModel: @unchecked Sendable {
    // MARK: State
    public private(set) var cards: [PaperTokCard] = []
    public private(set) var isLoading = false
    public private(set) var error: String? = nil
    public var likedIds: Set<Int> = []
    public var likedOnly = false
    public var searchQuery = ""
    public var dayFilter = "all"    // "all" | "latest" | "YYYY-MM-DD"

    // MARK: Download state: paper ID → 0.0-1.0 progress, or nil if not downloading
    public var downloadProgress: [Int: Double] = [:]

    // MARK: Dependencies
    private let api: any PaperTokAPIProtocol
    private let language: String

    public init(api: any PaperTokAPIProtocol = PaperTokAPI(), language: String = "zh") {
        self.api = api
        self.language = language
        // Restore liked IDs from UserDefaults
        if let saved = UserDefaults.standard.array(forKey: "papertok_liked_ids") as? [Int] {
            self.likedIds = Set(saved)
        }
    }

    // MARK: Computed

    public var visibleCards: [PaperTokCard] {
        let source = likedOnly ? cards.filter { likedIds.contains($0.id) } : cards
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return source }
        return source.filter { card in
            [card.bestTitle, card.extract ?? "", card.day ?? ""]
                .joined(separator: " ").lowercased().contains(q)
        }
    }

    public func isLiked(_ card: PaperTokCard) -> Bool { likedIds.contains(card.id) }

    // MARK: Actions

    public func loadMore(reset: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        if reset { cards = [] }
        do {
            var fetched = try await api.fetchRandomPapers(limit: 20, language: language, day: dayFilter)
            if reset && fetched.isEmpty && dayFilter == "latest" {
                fetched = try await api.fetchRandomPapers(limit: 20, language: language, day: "all")
            }
            cards.append(contentsOf: fetched)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    public func toggleLike(_ card: PaperTokCard) {
        if likedIds.contains(card.id) {
            likedIds.remove(card.id)
        } else {
            likedIds.insert(card.id)
        }
        UserDefaults.standard.set(Array(likedIds), forKey: "papertok_liked_ids")
    }

    public func applyDayFilter(_ filter: String) async {
        dayFilter = filter
        await loadMore(reset: true)
    }
}
```

- [ ] **Step 4：运行测试**

运行: `cd Packages/PTFeatures && swift test --filter PapersViewModelTests`
预期: PASS（4 tests）

- [ ] **Step 5：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/Papers/PapersViewModel.swift \
        Packages/PTFeatures/Tests/PTFeaturesTests/Papers/PapersViewModelTests.swift
git commit -m "feat(PTFeatures): add PapersViewModel with filtering, pagination, likes"
```

---

### Task 2：PaperCardView — 单张论文卡片

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/Papers/PaperCardView.swift`

- [ ] **Step 1：实现 PaperCardView**

对标 Flutter papers_page.dart 的卡片布局：全屏高度、图片轮播带指示点、渐变文字遮罩、标题+摘要+日期。

```swift
import SwiftUI
import PTNetworking
import PTUI

/// Full-height paper card with image carousel, title, abstract, and date.
///
/// Matches Flutter PapersPage card layout: 100% screen height card with
/// image carousel at top, gradient overlay, and text content at bottom.
struct PaperCardView: View {
    let card: PaperTokCard
    let isLiked: Bool
    let onLike: () -> Void
    let onTap: () -> Void

    @State private var currentImageIndex = 0
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Image carousel
                if !card.images.isEmpty {
                    TabView(selection: $currentImageIndex) {
                        ForEach(card.images.indices, id: \.self) { i in
                            AsyncImage(url: URL(string: card.images[i])) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                case .empty, .failure:
                                    Color(.secondarySystemBackground)
                                        .overlay(Image(systemName: "doc.text.image").font(.largeTitle).foregroundStyle(.tertiary))
                                @unknown default:
                                    Color(.secondarySystemBackground)
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: geo.size.height)
                } else {
                    // No images: gradient background
                    LinearGradient(
                        colors: [Color.morandiAccent.opacity(0.3), Color(.systemBackground)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: geo.size.height)
                }

                // Gradient overlay for text readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .center, endPoint: .bottom
                )
                .frame(height: geo.size.height * 0.55)

                // Text content + actions
                VStack(alignment: .leading, spacing: 8) {
                    Spacer()

                    // Image indicators
                    if card.images.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(card.images.indices, id: \.self) { i in
                                Circle()
                                    .fill(i == currentImageIndex ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }

                    Text(card.bestTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    if let extract = card.extract, !extract.isEmpty {
                        Text(extract)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(4)
                    }

                    HStack {
                        if let day = card.day {
                            Text(day)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        // Like button
                        Button(action: onLike) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.title3)
                                .foregroundStyle(isLiked ? .red : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .onTapGesture { onTap() }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
```

- [ ] **Step 2：编译验证**

运行: `cd Packages/PTFeatures && swift build`
预期: Build succeeded

- [ ] **Step 3：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/Papers/PaperCardView.swift
git commit -m "feat(PTFeatures): add PaperCardView with image carousel and gradient overlay"
```

---

### Task 3：PapersFilterBar — 日期筛选 + 搜索

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/Papers/PapersFilterBar.swift`

- [ ] **Step 1：实现 PapersFilterBar**

对标 Flutter papers_page.dart 的 `_dayFilter` 选择和搜索功能：

```swift
import SwiftUI

/// Filter bar for Papers page: date filter chips + search field + liked-only toggle.
struct PapersFilterBar: View {
    @Binding var searchQuery: String
    @Binding var likedOnly: Bool
    @Binding var dayFilter: String
    let onRefresh: () -> Void

    private let dayOptions: [(label: String, value: String)] = [
        ("最新", "latest"),
        ("全部", "all"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索论文标题、摘要…", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Filter chips row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Liked-only toggle
                    FilterChip(
                        label: "已收藏",
                        icon: "heart.fill",
                        isSelected: likedOnly
                    ) { likedOnly.toggle() }

                    Divider().frame(height: 20)

                    // Day filter chips
                    ForEach(dayOptions, id: \.value) { option in
                        FilterChip(
                            label: option.label,
                            isSelected: dayFilter == option.value
                        ) { dayFilter = option.value }
                    }

                    Spacer(minLength: 4)

                    // Refresh button
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.caption)
                }
                Text(label).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.morandiAccent : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/Papers/PapersFilterBar.swift
git commit -m "feat(PTFeatures): add PapersFilterBar with search, date filters, liked toggle"
```

---

### Task 4：PaperDetailView — 论文详情

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDetailView.swift`
- Create: `Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDownloadButton.swift`

- [ ] **Step 1：实现 PaperDownloadButton**

```swift
import SwiftUI
import PTNetworking

/// Download button showing progress, cancel, and completion states.
///
/// Matches Flutter papers_page download indicator behavior.
public struct PaperDownloadButton: View {
    let paper: PaperTokDetail
    @Binding var progress: Double?   // nil=idle, 0.0–1.0=downloading, 1.0=done
    let onDownload: () -> Void
    let onCancel: () -> Void

    public var body: some View {
        Group {
            if let p = progress {
                if p >= 1.0 {
                    Label("已导入", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        ProgressView(value: p)
                            .frame(width: 80)
                        Text("\(Int(p * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if paper.pdfURL != nil {
                        Button {
                            onDownload()
                        } label: {
                            Label("下载 PDF", systemImage: "arrow.down.circle")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.morandiAccent)
                    }
                    if let link = paper.arxivURL ?? paper.conferenceURL {
                        Link(destination: URL(string: link)!) {
                            Label("查看原文", systemImage: "safari")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2：实现 PaperDetailView**

```swift
import SwiftUI
import PTNetworking
import PTUI

/// Bottom sheet showing full paper detail: images, title, abstract, authors, download.
struct PaperDetailView: View {
    let paperId: Int
    @State private var detail: PaperTokDetail? = nil
    @State private var isLoading = true
    @State private var downloadProgress: Double? = nil
    @Environment(\.dismiss) private var dismiss

    private let api = PaperTokAPI()

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView("加载中…")
                        .padding(40)
                        .frame(maxWidth: .infinity)
                } else if let detail {
                    detailContent(detail)
                } else {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle")
                        .padding(40)
                }
            }
            .navigationTitle("论文详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await loadDetail() }
    }

    @ViewBuilder
    private func detailContent(_ detail: PaperTokDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Images carousel
            if !detail.images.isEmpty {
                TabView {
                    ForEach(detail.images, id: \.self) { imageURL in
                        AsyncImage(url: URL(string: imageURL)) { img in
                            img.resizable().scaledToFit()
                        } placeholder: {
                            Color(.secondarySystemBackground)
                        }
                        .frame(maxHeight: 200)
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Title
            Text(detail.bestTitle)
                .font(.title3.weight(.semibold))

            // Date + authors
            if let day = detail.day {
                Text(day).font(.caption).foregroundStyle(.secondary)
            }

            // Abstract
            if let abstract = detail.extract {
                VStack(alignment: .leading, spacing: 4) {
                    Text("摘要").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(abstract).font(.body)
                }
            }

            // Download button
            PaperDownloadButton(
                paper: detail,
                progress: $downloadProgress,
                onDownload: { Task { await startDownload(detail) } },
                onCancel: { downloadProgress = nil }
            )
        }
        .padding(20)
    }

    private func loadDetail() async {
        isLoading = true
        detail = try? await api.fetchPaperDetail(id: paperId, language: "zh")
        isLoading = false
    }

    private func startDownload(_ detail: PaperTokDetail) async {
        guard let urlString = detail.pdfURL, let url = URL(string: urlString) else { return }
        downloadProgress = 0.0
        do {
            let (localURL, _) = try await URLSession.shared.download(from: url)
            // TODO: Phase 12 — import localURL to bookshelf via BookService
            downloadProgress = 1.0
        } catch {
            downloadProgress = nil
        }
    }
}
```

- [ ] **Step 3：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDetailView.swift \
        Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDownloadButton.swift
git commit -m "feat(PTFeatures): add PaperDetailView + PaperDownloadButton with download progress"
```

---

### Task 5：PapersView — 主视图集成

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/Papers/PapersView.swift`

- [ ] **Step 1：实现 PapersView**

对标 Flutter `PapersPage`：垂直分页卡片流（`TabView(.page)`），距底部 3 张时触发加载更多。

```swift
import SwiftUI
import PTNetworking
import PTUI

/// Main Papers tab view — vertical paged card feed of academic papers.
///
/// Matches Flutter PapersPage behavior:
/// - Vertical TabView paging through full-screen cards
/// - Auto-loads more when 3 cards from the end
/// - Filter bar at top (collapsible on scroll)
public struct PapersView: View {
    @State private var viewModel = PapersViewModel()
    @State private var selectedPaperId: Int? = nil
    @State private var currentIndex = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PapersFilterBar(
                    searchQuery: $viewModel.searchQuery,
                    likedOnly: $viewModel.likedOnly,
                    dayFilter: Binding(
                        get: { viewModel.dayFilter },
                        set: { newValue in Task { await viewModel.applyDayFilter(newValue) } }
                    ),
                    onRefresh: { Task { await viewModel.loadMore(reset: true) } }
                )
                .padding(.horizontal, 16)

                if viewModel.visibleCards.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    cardFeed
                }
            }
            .navigationTitle("论文")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await viewModel.loadMore(reset: true) }
        .sheet(item: Binding(
            get: { selectedPaperId.map { id in id } },
            set: { _ in selectedPaperId = nil }
        )) { id in
            PaperDetailView(paperId: id)
        }
    }

    // MARK: Card feed

    private var cardFeed: some View {
        GeometryReader { geo in
            TabView(selection: $currentIndex) {
                ForEach(viewModel.visibleCards.indices, id: \.self) { i in
                    let card = viewModel.visibleCards[i]
                    PaperCardView(
                        card: card,
                        isLiked: viewModel.isLiked(card),
                        onLike: { viewModel.toggleLike(card) },
                        onTap: { selectedPaperId = card.id }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .tag(i)
                    .onAppear {
                        // Trigger load more when 3 cards from end
                        if i == viewModel.visibleCards.count - 3 {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }

                // Loading indicator card
                if viewModel.isLoading {
                    VStack {
                        ProgressView()
                        Text("加载中…").font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(viewModel.visibleCards.count)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: geo.size.height)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text(viewModel.error != nil ? "加载失败" : "暂无论文")
                .font(.title3)
                .foregroundStyle(.secondary)
            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button("重试") { Task { await viewModel.loadMore(reset: true) } }
                .buttonStyle(.bordered)
            Spacer()
        }
    }
}
```

- [ ] **Step 2：运行全部 PTFeatures 测试**

运行: `cd Packages/PTFeatures && swift test`
预期: All tests pass

- [ ] **Step 3：提交并推送**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/Papers/
git commit -m "feat(PTFeatures): add PapersView with paged card feed, filters, and detail sheet"
git push origin swift-native
```

---

## 工作量估算

| 任务 | 估算天数 |
|------|----------|
| Task 1：PapersViewModel | 1 天 |
| Task 2：PaperCardView（图片轮播） | 1 天 |
| Task 3：PapersFilterBar | 0.5 天 |
| Task 4：PaperDetailView + DownloadButton | 1.5 天 |
| Task 5：PapersView 集成 | 1 天 |
| **合计** | **~5 天** |

## 风险点

1. **PaperTokCard/PaperTokDetail API**：PTNetworking 中的 `PaperTokCard` 字段需与 Flutter 版 `models.dart` 完全对应，特别是 `bestTitle`（多语言标题取最佳）和 `images` 字段。
2. **TabView 垂直分页**：iOS 17 `TabView(.page)` 垂直方向在横屏 iPad 上可能出现布局问题，需测试。
3. **图片懒加载**：`AsyncImage` 在快速滑动时会频繁取消/重启请求，如流畅度不足，可引入 SDWebImageSwiftUI 缓存。
4. **下载进度**：`URLSession.download` 不内建进度回调，需用 `URLSessionDownloadDelegate` 或 `.downloadProgress` modifier 实现真实进度。
5. **书架导入**：下载完成后导入书架的逻辑（BookService.importBook）在 Phase 12 App 集成时实现，此处为 TODO。
