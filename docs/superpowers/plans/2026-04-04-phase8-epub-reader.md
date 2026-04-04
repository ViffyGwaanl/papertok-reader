# Phase 8：EPUB 阅读器实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 为 PTReader 包集成 Readium Swift SDK，实现完整 EPUB 阅读功能，包括章节导航、CFI 定位、高亮/书签/注释、AI 工具内容访问，以及 iOS/macOS 双平台适配。

**架构：** PTReader 包中新增 EPUB 子模块。`EPUBContentBridge` 实现已有的 `BookContentBridge` 协议，供 AI 工具无缝访问内容。`EPUBReaderView` 用 `UIViewControllerRepresentable`（iOS）和 `NSViewControllerRepresentable`（macOS）包装 Readium Navigator ViewController。高亮/注释通过 Readium Decorator API 写回，同时持久化到 PTCore 的 `tb_notes` 表。

**技术栈：** Swift 5.9+, Readium Swift Toolkit 3.x (ReadiumShared, ReadiumStreamer, ReadiumNavigator), UIKit/AppKit bridge, PTCore (BookNote, BookDAO), Swift Testing

**前置依赖：** Phase 1 PTCore ✅, Phase 3 PTReader 基础完成（BookContentBridge 协议、PDFContentBridge 已实现）

**参考 Flutter 文件：**
- `lib/page/book_player/epub_player.dart` — EPUB 播放器主页面
- `lib/service/epub/` — EPUB 服务层（CFI 解析、高亮管理）

---

## 文件结构

```
Packages/PTReader/
├── Package.swift                                        # 修改：添加 Readium 依赖
├── Sources/PTReader/
│   ├── EPUB/
│   │   ├── EPUBContentBridge.swift                     # 新建：BookContentBridge 实现
│   │   ├── EPUBPublicationOpener.swift                 # 新建：打开 .epub 文件 → Publication
│   │   ├── EPUBNavigatorCoordinator.swift              # 新建：导航状态、定位、翻页
│   │   ├── EPUBReaderView.swift                        # 新建：UIViewControllerRepresentable
│   │   ├── EPUBAnnotationBridge.swift                  # 新建：Decorator → BookNote 映射
│   │   └── EPUBTOCMapper.swift                         # 新建：ReadiumLink → ChapterEntry
│   └── Common/
│       └── BookContentBridge.swift                     # 已存在，无需修改
└── Tests/PTReaderTests/
    └── EPUB/
        ├── EPUBContentBridgeTests.swift                # 新建
        ├── EPUBTOCMapperTests.swift                    # 新建
        └── EPUBAnnotationBridgeTests.swift             # 新建
```

---

### Task 1：更新 Package.swift，添加 Readium 依赖

**Files:**
- Modify: `Packages/PTReader/Package.swift`

- [ ] **Step 1：更新 Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTReader",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PTReader", targets: ["PTReader"]),
    ],
    dependencies: [
        .package(path: "../PTCore"),
        .package(
            url: "https://github.com/readium/swift-toolkit.git",
            from: "3.0.0"
        ),
    ],
    targets: [
        .target(
            name: "PTReader",
            dependencies: [
                "PTCore",
                .product(name: "ReadiumShared", package: "swift-toolkit"),
                .product(name: "ReadiumStreamer", package: "swift-toolkit"),
                .product(name: "ReadiumNavigator", package: "swift-toolkit"),
            ]
        ),
        .testTarget(
            name: "PTReaderTests",
            dependencies: ["PTReader"]
        ),
    ]
)
```

- [ ] **Step 2：解析依赖，验证编译**

运行: `cd Packages/PTReader && swift package resolve`
预期: 下载 Readium 包，无报错

- [ ] **Step 3：提交**

```bash
git add Packages/PTReader/Package.swift
git commit -m "feat(PTReader): add Readium Swift SDK dependency"
```

---

### Task 2：EPUBTOCMapper — ReadiumLink → ChapterEntry

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/EPUB/EPUBTOCMapper.swift`
- Create: `Packages/PTReader/Tests/PTReaderTests/EPUB/EPUBTOCMapperTests.swift`

- [ ] **Step 1：编写失败测试**

```swift
import Testing
@testable import PTReader
import ReadiumShared

@Suite("EPUBTOCMapper")
struct EPUBTOCMapperTests {
    @Test("平坦链接列表映射为 level-0 ChapterEntry")
    func flatLinks() {
        let links = [
            Link(href: "ch1.xhtml", title: "第一章"),
            Link(href: "ch2.xhtml", title: "第二章"),
        ]
        let entries = EPUBTOCMapper.map(links: links)
        #expect(entries.count == 2)
        #expect(entries[0].href == "ch1.xhtml")
        #expect(entries[0].title == "第一章")
        #expect(entries[0].level == 0)
    }

    @Test("嵌套链接正确映射 level")
    func nestedLinks() {
        let child = Link(href: "ch1-1.xhtml", title: "第一节")
        let parent = Link(href: "ch1.xhtml", title: "第一章", children: [child])
        let entries = EPUBTOCMapper.map(links: [parent])
        #expect(entries.count == 2)
        #expect(entries[0].level == 0)
        #expect(entries[0].childCount == 1)
        #expect(entries[1].level == 1)
    }
}
```

- [ ] **Step 2：运行，确认失败**

运行: `cd Packages/PTReader && swift test --filter EPUBTOCMapperTests`
预期: FAIL — EPUBTOCMapper not found

- [ ] **Step 3：实现 EPUBTOCMapper**

```swift
import Foundation
import ReadiumShared
import PTReader

public enum EPUBTOCMapper {
    /// Recursively flatten a Readium TOC link tree into ordered ChapterEntry list.
    public static func map(links: [Link], level: Int = 0) -> [ChapterEntry] {
        var result: [ChapterEntry] = []
        for link in links {
            let children = link.children ?? []
            result.append(ChapterEntry(
                title: link.title ?? link.href,
                href: link.href,
                level: level,
                childCount: children.count
            ))
            result.append(contentsOf: map(links: children, level: level + 1))
        }
        return result
    }
}
```

- [ ] **Step 4：运行测试**

运行: `cd Packages/PTReader && swift test --filter EPUBTOCMapperTests`
预期: PASS（2 tests）

- [ ] **Step 5：提交**

```bash
git add Packages/PTReader/Sources/PTReader/EPUB/EPUBTOCMapper.swift \
        Packages/PTReader/Tests/PTReaderTests/EPUB/EPUBTOCMapperTests.swift
git commit -m "feat(PTReader): add EPUBTOCMapper for Readium link tree"
```

---

### Task 3：EPUBPublicationOpener — 打开 .epub 文件

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/EPUB/EPUBPublicationOpener.swift`

- [ ] **Step 1：实现 EPUBPublicationOpener**

```swift
import Foundation
import ReadiumShared
import ReadiumStreamer

/// Opens an .epub file from disk and returns a Readium Publication.
public final class EPUBPublicationOpener: Sendable {
    private let streamer: Streamer

    public init() {
        self.streamer = Streamer()
    }

    /// Open an EPUB file at the given URL.
    /// - Returns: A ready-to-use `Publication`.
    /// - Throws: `EPUBOpenError` if the file cannot be opened.
    public func open(at url: URL) async throws -> Publication {
        let asset = FileAsset(url: url)
        let result = await streamer.open(asset: asset, allowUserInteraction: false)
        switch result {
        case .success(let pub):
            return pub
        case .failure(let error):
            throw EPUBOpenError.streamerError(error.localizedDescription)
        }
    }
}

public enum EPUBOpenError: Error, LocalizedError {
    case streamerError(String)
    public var errorDescription: String? {
        switch self { case .streamerError(let msg): return "EPUB open failed: \(msg)" }
    }
}
```

- [ ] **Step 2：编译验证**

运行: `cd Packages/PTReader && swift build`
预期: Build succeeded

- [ ] **Step 3：提交**

```bash
git add Packages/PTReader/Sources/PTReader/EPUB/EPUBPublicationOpener.swift
git commit -m "feat(PTReader): add EPUBPublicationOpener using Readium Streamer"
```

---

### Task 4：EPUBContentBridge — 实现 BookContentBridge 协议

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/EPUB/EPUBContentBridge.swift`
- Create: `Packages/PTReader/Tests/PTReaderTests/EPUB/EPUBContentBridgeTests.swift`

- [ ] **Step 1：编写失败测试（基于 mock Publication）**

```swift
import Testing
@testable import PTReader

@Suite("EPUBContentBridge")
struct EPUBContentBridgeTests {
    @Test("title 返回 Publication metadata 标题")
    func titleFromMetadata() async throws {
        // 使用本地 fixture EPUB（放置于 Tests/Fixtures/minimal.epub）
        let fixtureURL = Bundle.module.url(forResource: "minimal", withExtension: "epub")!
        let opener = EPUBPublicationOpener()
        let pub = try await opener.open(at: fixtureURL)
        let bridge = EPUBContentBridge(publication: pub)
        #expect(!bridge.title.isEmpty)
    }

    @Test("tableOfContents 返回非空列表")
    func tocNotEmpty() async throws {
        let fixtureURL = Bundle.module.url(forResource: "minimal", withExtension: "epub")!
        let opener = EPUBPublicationOpener()
        let pub = try await opener.open(at: fixtureURL)
        let bridge = EPUBContentBridge(publication: pub)
        let toc = try await bridge.tableOfContents
        #expect(!toc.isEmpty)
    }
}
```

- [ ] **Step 2：实现 EPUBContentBridge**

```swift
import Foundation
import ReadiumShared
import ReadiumNavigator

/// BookContentBridge implementation for EPUB publications using Readium.
public final class EPUBContentBridge: BookContentBridge, Sendable {
    private let publication: Publication

    public init(publication: Publication) {
        self.publication = publication
    }

    public var title: String {
        publication.metadata.title ?? "Unknown"
    }

    public var tableOfContents: [ChapterEntry] {
        get async throws {
            EPUBTOCMapper.map(links: publication.tableOfContents)
        }
    }

    public func extractChapterContent(href: String) async throws -> String {
        guard let resource = publication.get(Link(href: href)) else {
            throw EPUBOpenError.streamerError("Chapter not found: \(href)")
        }
        let data = try await resource.read().get()
        let html = String(data: data, encoding: .utf8) ?? ""
        return stripHTML(html)
    }

    public func extractFullText() async throws -> String {
        let toc = try await tableOfContents
        var parts: [String] = []
        for entry in toc where entry.level == 0 {
            let text = try await extractChapterContent(href: entry.href)
            parts.append(text)
        }
        return parts.joined(separator: "\n\n")
    }

    public func searchContent(query: String) async throws -> [ContentSearchResult] {
        let toc = try await tableOfContents
        var results: [ContentSearchResult] = []
        let lowerQuery = query.lowercased()
        for entry in toc where entry.level == 0 {
            let text = try await extractChapterContent(href: entry.href)
            let lowerText = text.lowercased()
            var searchPos = lowerText.startIndex
            while let range = lowerText.range(of: lowerQuery, range: searchPos..<lowerText.endIndex) {
                let snippetStart = lowerText.index(range.lowerBound, offsetBy: -60, limitedBy: lowerText.startIndex) ?? lowerText.startIndex
                let snippetEnd = lowerText.index(range.upperBound, offsetBy: 60, limitedBy: lowerText.endIndex) ?? lowerText.endIndex
                let snippet = String(text[snippetStart..<snippetEnd])
                results.append(ContentSearchResult(chapterHref: entry.href, chapterTitle: entry.title, snippet: snippet, query: query))
                searchPos = range.upperBound
            }
        }
        return results
    }

    // MARK: Private

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 3：运行测试**

运行: `cd Packages/PTReader && swift test --filter EPUBContentBridgeTests`
预期: PASS（需要 Tests/Fixtures/minimal.epub fixture 文件）

- [ ] **Step 4：提交**

```bash
git add Packages/PTReader/Sources/PTReader/EPUB/EPUBContentBridge.swift \
        Packages/PTReader/Tests/PTReaderTests/EPUB/EPUBContentBridgeTests.swift
git commit -m "feat(PTReader): implement EPUBContentBridge with full-text and search"
```

---

### Task 5：EPUBAnnotationBridge — 高亮/书签写入 Readium Decorator

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/EPUB/EPUBAnnotationBridge.swift`
- Create: `Packages/PTReader/Tests/PTReaderTests/EPUB/EPUBAnnotationBridgeTests.swift`

- [ ] **Step 1：编写失败测试**

```swift
import Testing
@testable import PTReader
import PTCore

@Suite("EPUBAnnotationBridge")
struct EPUBAnnotationBridgeTests {
    @Test("BookNote 转 DecoratorStyle 映射颜色")
    func noteToDecoratorStyle() {
        let note = BookNote(
            bookId: 1,
            content: "重点段落",
            cfi: "epubcfi(/6/2[c01]!/4/2/1:0)",
            color: "#FF0000",
            type: .highlight
        )
        let style = EPUBAnnotationBridge.decoratorStyle(for: note)
        #expect(style.tint == "#FF0000")
    }
}
```

- [ ] **Step 2：实现 EPUBAnnotationBridge**

```swift
import Foundation
import ReadiumNavigator
import ReadiumShared
import PTCore

/// Converts PTCore BookNote annotations to/from Readium Decorator decorations.
public enum EPUBAnnotationBridge {
    public struct DecoratorStyle: Sendable {
        public let tint: String
        public let style: String   // "highlight" | "underline" | "strikethrough"
        public init(tint: String, style: String = "highlight") {
            self.tint = tint; self.style = style
        }
    }

    /// Map a BookNote to a Readium decorator style.
    public static func decoratorStyle(for note: BookNote) -> DecoratorStyle {
        DecoratorStyle(
            tint: note.color ?? "#FFEB3B",
            style: note.type == .underline ? "underline" : "highlight"
        )
    }

    /// Build a Readium Locator from an EPUB CFI string.
    /// Returns nil if the CFI cannot be parsed.
    public static func locator(fromCFI cfi: String, publication: Publication) -> Locator? {
        // Readium accepts CFI strings directly via Locator(cfi:)
        return Locator(cfi: cfi, publication: publication)
    }

    /// Convert a Readium Locator back to a CFI string for storage in tb_notes.
    public static func cfi(from locator: Locator) -> String? {
        locator.locations.cfi
    }
}
```

- [ ] **Step 3：运行测试**

运行: `cd Packages/PTReader && swift test --filter EPUBAnnotationBridgeTests`
预期: PASS（1 test）

- [ ] **Step 4：提交**

```bash
git add Packages/PTReader/Sources/PTReader/EPUB/EPUBAnnotationBridge.swift \
        Packages/PTReader/Tests/PTReaderTests/EPUB/EPUBAnnotationBridgeTests.swift
git commit -m "feat(PTReader): add EPUBAnnotationBridge for Readium Decorator mapping"
```

---

### Task 6：EPUBNavigatorCoordinator — 导航状态管理

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/EPUB/EPUBNavigatorCoordinator.swift`

- [ ] **Step 1：实现 EPUBNavigatorCoordinator**

```swift
import Foundation
import Observation
import ReadiumNavigator
import ReadiumShared
import PTCore

/// @Observable coordinator that bridges EPUBNavigatorViewController state to SwiftUI.
///
/// Manages current locator (chapter + position), pending annotation creation,
/// and user navigation events (tap to flip page, TOC jump).
@Observable
public final class EPUBNavigatorCoordinator: NSObject, Sendable {
    // MARK: Published state
    public private(set) var currentLocator: Locator?
    public private(set) var currentChapterTitle: String = ""
    public private(set) var readingProgress: Double = 0     // 0.0–1.0

    // MARK: Pending selection (for annotation creation)
    public var selectedText: String = ""
    public var selectedLocator: Locator?

    // MARK: Delegate callbacks
    public var onLocatorChange: ((Locator) -> Void)?
    public var onHighlightRequest: ((Locator, String) -> Void)?   // locator, selectedText

    // MARK: Internal
    weak var navigatorViewController: EPUBNavigatorViewController?

    public func navigate(to locator: Locator) {
        navigatorViewController?.go(to: locator)
    }

    public func goToNextChapter() {
        navigatorViewController?.goForward(animated: true)
    }

    public func goToPreviousChapter() {
        navigatorViewController?.goBackward(animated: true)
    }
}

// MARK: EPUBNavigatorDelegate
extension EPUBNavigatorCoordinator: EPUBNavigatorDelegate {
    public func navigator(_ navigator: any Navigator, locationDidChange locator: Locator) {
        currentLocator = locator
        currentChapterTitle = locator.title ?? ""
        readingProgress = locator.locations.progression ?? 0
        onLocatorChange?(locator)
    }
}
```

- [ ] **Step 2：编译验证**

运行: `cd Packages/PTReader && swift build`
预期: Build succeeded

- [ ] **Step 3：提交**

```bash
git add Packages/PTReader/Sources/PTReader/EPUB/EPUBNavigatorCoordinator.swift
git commit -m "feat(PTReader): add EPUBNavigatorCoordinator bridging Readium delegate to @Observable"
```

---

### Task 7：EPUBReaderView — SwiftUI 包装器

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/EPUB/EPUBReaderView.swift`

- [ ] **Step 1：实现 EPUBReaderView（iOS）**

```swift
#if canImport(UIKit)
import SwiftUI
import UIKit
import ReadiumNavigator
import ReadiumShared

/// SwiftUI wrapper for Readium EPUBNavigatorViewController.
///
/// Usage:
/// ```swift
/// EPUBReaderView(publication: pub, coordinator: coordinator)
/// ```
public struct EPUBReaderView: UIViewControllerRepresentable {
    public let publication: Publication
    public let initialLocator: Locator?
    @Bindable public var coordinator: EPUBNavigatorCoordinator

    public init(
        publication: Publication,
        coordinator: EPUBNavigatorCoordinator,
        initialLocator: Locator? = nil
    ) {
        self.publication = publication
        self.coordinator = coordinator
        self.initialLocator = initialLocator
    }

    public func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        let config = EPUBNavigatorViewController.Configuration()
        let vc = EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocator,
            config: config
        )
        vc.delegate = coordinator
        coordinator.navigatorViewController = vc
        return vc
    }

    public func updateUIViewController(_ vc: EPUBNavigatorViewController, context: Context) {
        // Locator navigation handled via coordinator.navigate(to:)
    }
}
#endif

#if canImport(AppKit)
import SwiftUI
import AppKit
import ReadiumNavigator
import ReadiumShared

/// macOS NSViewControllerRepresentable wrapper for Readium EPUB navigator.
public struct EPUBReaderView: NSViewControllerRepresentable {
    public let publication: Publication
    public let initialLocator: Locator?
    @Bindable public var coordinator: EPUBNavigatorCoordinator

    public init(
        publication: Publication,
        coordinator: EPUBNavigatorCoordinator,
        initialLocator: Locator? = nil
    ) {
        self.publication = publication
        self.coordinator = coordinator
        self.initialLocator = initialLocator
    }

    public func makeNSViewController(context: Context) -> EPUBNavigatorViewController {
        let config = EPUBNavigatorViewController.Configuration()
        let vc = EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocator,
            config: config
        )
        vc.delegate = coordinator
        coordinator.navigatorViewController = vc
        return vc
    }

    public func updateNSViewController(_ vc: EPUBNavigatorViewController, context: Context) {}
}
#endif
```

- [ ] **Step 2：编译验证**

运行: `cd Packages/PTReader && swift build`
预期: Build succeeded（iOS 和 macOS 均通过）

- [ ] **Step 3：提交**

```bash
git add Packages/PTReader/Sources/PTReader/EPUB/EPUBReaderView.swift
git commit -m "feat(PTReader): add EPUBReaderView UIViewControllerRepresentable for iOS/macOS"
```

---

### Task 8：完整测试套件 + 推送

- [ ] **Step 1：运行全部 PTReader 测试**

运行: `cd Packages/PTReader && swift test`
预期: All tests pass

- [ ] **Step 2：推送到 swift-native**

```bash
git push origin swift-native
```

---

## 工作量估算

| 任务 | 估算天数 |
|------|----------|
| Task 1：Readium 依赖配置 | 0.5 天 |
| Task 2：TOC 映射 | 0.5 天 |
| Task 3：PublicationOpener | 0.5 天 |
| Task 4：ContentBridge（含全文提取） | 1 天 |
| Task 5：AnnotationBridge | 1 天 |
| Task 6：NavigatorCoordinator | 1 天 |
| Task 7：ReaderView iOS/macOS | 1 天 |
| 集成测试 + 修复 | 1 天 |
| **合计** | **~6.5 天** |

## 风险点

1. **Readium macOS 兼容性**：EPUBNavigatorViewController 在 macOS 下可能需要额外配置，需测试实际构建产物。
2. **CFI 解析**：Readium 3.x 对 CFI 的 API 接口可能与 2.x 不同，需确认 `Locator(cfi:publication:)` 方法签名。
3. **HTML 剥离质量**：正则 stripHTML 对复杂 MathML/SVG 内容效果有限，如需高质量文本提取可改用 SwiftSoup。
4. **Fixture EPUB**：测试需要一个最小化的合法 .epub 文件，需准备并放置于 `Tests/Fixtures/`。
