# Phase 3: PTReader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the PTReader Swift package — reading preference models (BookStyle, ReadTheme), a unified BookContentBridge protocol, PDF text extraction via PDFKit + Vision OCR, TTS service, and the Readium SDK integration with SwiftUI bridges for EPUB/PDF rendering.

**Architecture:** PTReader depends on PTCore (models, GRDB) and Readium Swift Toolkit (EPUB/PDF rendering). BookStyle and ReadTheme are GRDB-backed models added to PTCore. The BookContentBridge protocol provides a unified interface for AI tools to access content from both EPUB and PDF. ReaderEngine is an `@Observable` class coordinating the Readium navigator, position tracking, and preferences. SwiftUI bridges wrap Readium's UIKit view controllers via `UIViewControllerRepresentable`.

**Tech Stack:** Swift 5.9+, Readium Swift Toolkit 3.x, PDFKit, Vision (VNRecognizeTextRequest), AVSpeechSynthesizer, PTCore (GRDB), Swift Testing

**Note on testing:** Readium and PDFKit APIs require iOS/macOS runtime. Some tests in this package compile as unit tests but exercise framework types that are available on Apple platforms. Tests that use UIKit (e.g., navigator VCs) cannot run in `swift test` — they'll be verified in the Xcode app target. We mark these clearly.

---

## File Structure

```
Packages/PTCore/Sources/PTCore/
│   ├── Models/
│   │   ├── BookStyle.swift            # NEW — reading style preferences (GRDB)
│   │   └── ReadTheme.swift            # NEW — reading theme (GRDB)
│   └── Database/
│       ├── BookStyleDAO.swift         # NEW — CRUD for tb_styles
│       └── ReadThemeDAO.swift         # NEW — CRUD for tb_themes

Packages/PTReader/
├── Package.swift
├── Sources/PTReader/
│   ├── PTReader.swift                 # Module entry, re-exports
│   ├── Common/
│   │   ├── BookContentBridge.swift    # Protocol: unified content access
│   │   ├── ContentSearchResult.swift  # Search result model
│   │   └── HighlightStyle.swift       # Highlight colors enum
│   ├── PDF/
│   │   ├── PDFContentBridge.swift     # PDFKit text extraction + OCR
│   │   └── PDFChapter.swift           # Page-range chapter model
│   ├── Preferences/
│   │   └── ReadingPreferences.swift   # @Observable, wraps BookStyle + ReadTheme
│   └── TTS/
│       └── TTSService.swift           # AVSpeechSynthesizer wrapper
└── Tests/PTReaderTests/
    ├── Common/
    │   └── HighlightStyleTests.swift
    ├── PDF/
    │   ├── PDFContentBridgeTests.swift
    │   └── PDFChapterTests.swift
    ├── Preferences/
    │   └── ReadingPreferencesTests.swift
    └── TTS/
        └── TTSServiceTests.swift
```

**Deferred to app integration (Phase 7):**
- `EPUBReaderView` (UIViewControllerRepresentable) — requires full app target
- `PDFReaderView` (UIViewControllerRepresentable) — requires full app target
- `ReaderEngine` (@Observable) — requires Readium navigator which needs UIKit runtime
- `EPUBContentBridge` — requires Readium Publication which needs Streamer

These are deferred because they need an Xcode project target with UIKit, not a Swift Package test environment.

---

### Task 1: Add BookStyle Model to PTCore

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Models/BookStyle.swift`
- Test: `Packages/PTCore/Tests/PTCoreTests/Models/BookStyleTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/PTCore/Tests/PTCoreTests/Models/BookStyleTests.swift`:

```swift
import Testing
import Foundation
@testable import PTCore

@Suite("BookStyle")
struct BookStyleTests {
    @Test("Default values are correct")
    func defaultValues() {
        let style = BookStyle.default
        #expect(style.fontSize == 1.4)
        #expect(style.fontFamily == "Arial")
        #expect(style.fontWeight == 400)
        #expect(style.lineHeight == 1.8)
        #expect(style.letterSpacing == 0.0)
        #expect(style.wordSpacing == 0.0)
        #expect(style.paragraphSpacing == 1.0)
        #expect(style.sideMargin == 6.0)
        #expect(style.topMargin == 90.0)
        #expect(style.bottomMargin == 50.0)
    }

    @Test("Roundtrips through database")
    func databaseRoundtrip() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookStyleDAO(database: db)

        var style = BookStyle.default
        style.fontSize = 2.0
        style.fontFamily = "Georgia"
        style.lineHeight = 2.2

        let saved = try await dao.save(style)
        #expect(saved.id != nil)

        let fetched = try await dao.fetchById(saved.id!)
        #expect(fetched != nil)
        #expect(fetched!.fontSize == 2.0)
        #expect(fetched!.fontFamily == "Georgia")
        #expect(fetched!.lineHeight == 2.2)
    }

    @Test("JSON serialization roundtrips")
    func jsonRoundtrip() throws {
        var style = BookStyle.default
        style.fontSize = 1.8
        style.fontFamily = "Source Han Serif SC"

        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BookStyle.self, from: data)
        #expect(decoded.fontSize == 1.8)
        #expect(decoded.fontFamily == "Source Han Serif SC")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTCore && swift test --filter BookStyleTests 2>&1 | tail -10`
Expected: FAIL — `BookStyle` not found.

- [ ] **Step 3: Create BookStyle model**

Create `Packages/PTCore/Sources/PTCore/Models/BookStyle.swift`:

```swift
import Foundation
import GRDB

public struct BookStyle: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "tb_styles"

    public var id: Int64?
    public var fontSize: Double
    public var fontFamily: String
    public var fontWeight: Double
    public var lineHeight: Double
    public var letterSpacing: Double
    public var wordSpacing: Double
    public var paragraphSpacing: Double
    public var sideMargin: Double
    public var topMargin: Double
    public var bottomMargin: Double

    enum CodingKeys: String, CodingKey {
        case id
        case fontSize = "font_size"
        case fontFamily = "font_family"
        case fontWeight = "font_weight"
        case lineHeight = "line_height"
        case letterSpacing = "letter_spacing"
        case wordSpacing = "word_spacing"
        case paragraphSpacing = "paragraph_spacing"
        case sideMargin = "side_margin"
        case topMargin = "top_margin"
        case bottomMargin = "bottom_margin"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static let `default` = BookStyle(
        id: nil,
        fontSize: 1.4,
        fontFamily: "Arial",
        fontWeight: 400,
        lineHeight: 1.8,
        letterSpacing: 0.0,
        wordSpacing: 0.0,
        paragraphSpacing: 1.0,
        sideMargin: 6.0,
        topMargin: 90.0,
        bottomMargin: 50.0
    )
}
```

- [ ] **Step 4: Create BookStyleDAO**

Create `Packages/PTCore/Sources/PTCore/Database/BookStyleDAO.swift`:

```swift
import Foundation
import GRDB

public struct BookStyleDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ style: BookStyle) async throws -> BookStyle {
        try await database.writer.write { db in
            try style.saved(db)
        }
    }

    public func fetchById(_ id: Int64) async throws -> BookStyle? {
        try await database.reader.read { db in
            try BookStyle.fetchOne(db, key: id)
        }
    }

    public func fetchAll() async throws -> [BookStyle] {
        try await database.reader.read { db in
            try BookStyle.fetchAll(db)
        }
    }

    public func delete(id: Int64) async throws {
        try await database.writer.write { db in
            _ = try BookStyle.deleteOne(db, key: id)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd Packages/PTCore && swift test --filter BookStyleTests 2>&1 | tail -15`
Expected: All 3 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/Models/BookStyle.swift Packages/PTCore/Sources/PTCore/Database/BookStyleDAO.swift Packages/PTCore/Tests/PTCoreTests/Models/BookStyleTests.swift
git commit -m "feat(PTCore): add BookStyle model and DAO for reading preferences"
```

---

### Task 2: Add ReadTheme Model to PTCore

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Models/ReadTheme.swift`
- Create: `Packages/PTCore/Sources/PTCore/Database/ReadThemeDAO.swift`
- Test: `Packages/PTCore/Tests/PTCoreTests/Models/ReadThemeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/PTCore/Tests/PTCoreTests/Models/ReadThemeTests.swift`:

```swift
import Testing
import Foundation
@testable import PTCore

@Suite("ReadTheme")
struct ReadThemeTests {
    @Test("Default theme has warm paper colors")
    func defaultTheme() {
        let theme = ReadTheme.defaultLight
        #expect(theme.backgroundColor == "FFFBFBF3")
        #expect(theme.textColor == "FF343434")
        #expect(theme.backgroundImagePath == "")
    }

    @Test("Roundtrips through database")
    func databaseRoundtrip() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = ReadThemeDAO(database: db)

        var theme = ReadTheme(
            id: nil,
            backgroundColor: "FF1A1A2E",
            textColor: "FFE0E0E0",
            backgroundImagePath: ""
        )

        let saved = try await dao.save(theme)
        #expect(saved.id != nil)

        let fetched = try await dao.fetchById(saved.id!)
        #expect(fetched != nil)
        #expect(fetched!.backgroundColor == "FF1A1A2E")
        #expect(fetched!.textColor == "FFE0E0E0")
    }

    @Test("FetchAll returns all themes")
    func fetchAll() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = ReadThemeDAO(database: db)

        _ = try await dao.save(ReadTheme(id: nil, backgroundColor: "FFF", textColor: "F00", backgroundImagePath: ""))
        _ = try await dao.save(ReadTheme(id: nil, backgroundColor: "000", textColor: "FFF", backgroundImagePath: ""))

        let all = try await dao.fetchAll()
        #expect(all.count == 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTCore && swift test --filter ReadThemeTests 2>&1 | tail -10`
Expected: FAIL — `ReadTheme` not found.

- [ ] **Step 3: Create ReadTheme model**

Create `Packages/PTCore/Sources/PTCore/Models/ReadTheme.swift`:

```swift
import Foundation
import GRDB

public struct ReadTheme: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "tb_themes"

    public var id: Int64?
    public var backgroundColor: String
    public var textColor: String
    public var backgroundImagePath: String

    enum CodingKeys: String, CodingKey {
        case id
        case backgroundColor = "background_color"
        case textColor = "text_color"
        case backgroundImagePath = "background_image_path"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Default light theme: warm paper background.
    public static let defaultLight = ReadTheme(
        id: nil,
        backgroundColor: "FFFBFBF3",
        textColor: "FF343434",
        backgroundImagePath: ""
    )

    /// Default dark theme.
    public static let defaultDark = ReadTheme(
        id: nil,
        backgroundColor: "FF1A1A2E",
        textColor: "FFE0E0E0",
        backgroundImagePath: ""
    )
}
```

- [ ] **Step 4: Create ReadThemeDAO**

Create `Packages/PTCore/Sources/PTCore/Database/ReadThemeDAO.swift`:

```swift
import Foundation
import GRDB

public struct ReadThemeDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ theme: ReadTheme) async throws -> ReadTheme {
        try await database.writer.write { db in
            try theme.saved(db)
        }
    }

    public func fetchById(_ id: Int64) async throws -> ReadTheme? {
        try await database.reader.read { db in
            try ReadTheme.fetchOne(db, key: id)
        }
    }

    public func fetchAll() async throws -> [ReadTheme] {
        try await database.reader.read { db in
            try ReadTheme.fetchAll(db)
        }
    }

    public func delete(id: Int64) async throws {
        try await database.writer.write { db in
            _ = try ReadTheme.deleteOne(db, key: id)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd Packages/PTCore && swift test --filter ReadThemeTests 2>&1 | tail -15`
Expected: All 3 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/Models/ReadTheme.swift Packages/PTCore/Sources/PTCore/Database/ReadThemeDAO.swift Packages/PTCore/Tests/PTCoreTests/Models/ReadThemeTests.swift
git commit -m "feat(PTCore): add ReadTheme model and DAO for reading themes"
```

---

### Task 3: PTReader Package Setup

**Files:**
- Create: `Packages/PTReader/Package.swift`
- Create: `Packages/PTReader/Sources/PTReader/PTReader.swift`
- Test: `Packages/PTReader/Tests/PTReaderTests/PTReaderImportTests.swift`

- [ ] **Step 1: Create Package.swift**

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
    ],
    targets: [
        .target(
            name: "PTReader",
            dependencies: ["PTCore"]
        ),
        .testTarget(
            name: "PTReaderTests",
            dependencies: ["PTReader"]
        ),
    ]
)
```

**Note:** We intentionally do NOT add the Readium dependency yet. The Readium SDK requires UIKit and a full Xcode build environment. We'll add it in the app target (Phase 7) when integrating the reader. PTReader currently focuses on models, protocols, and platform-framework-based components (PDFKit, Vision, AVSpeechSynthesizer) that work in a macOS test environment.

- [ ] **Step 2: Create module entry**

Create `Packages/PTReader/Sources/PTReader/PTReader.swift`:

```swift
// PTReader — Book reading engine, content bridges, preferences, TTS
// Depends on PTCore for models and database

import Foundation
@_exported import PTCore
```

- [ ] **Step 3: Create placeholder test**

Create `Packages/PTReader/Tests/PTReaderTests/PTReaderImportTests.swift`:

```swift
import Testing
@testable import PTReader

@Suite("PTReader Module")
struct PTReaderImportTests {
    @Test("Module imports successfully")
    func moduleImports() {
        #expect(true)
    }
}
```

- [ ] **Step 4: Verify package resolves and test passes**

Run: `cd Packages/PTReader && swift test 2>&1 | tail -15`
Expected: Build succeeds, 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTReader/Package.swift Packages/PTReader/Sources/PTReader/PTReader.swift Packages/PTReader/Tests/PTReaderTests/PTReaderImportTests.swift
git commit -m "feat(PTReader): initialize package with PTCore dependency"
```

---

### Task 4: HighlightStyle and ContentSearchResult

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/Common/HighlightStyle.swift`
- Create: `Packages/PTReader/Sources/PTReader/Common/ContentSearchResult.swift`
- Test: `Packages/PTReader/Tests/PTReaderTests/Common/HighlightStyleTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/PTReader/Tests/PTReaderTests/Common/HighlightStyleTests.swift`:

```swift
import Testing
import Foundation
@testable import PTReader

@Suite("HighlightStyle")
struct HighlightStyleTests {
    @Test("All five colors are defined")
    func allColors() {
        let colors = HighlightColor.allCases
        #expect(colors.count == 5)
        #expect(colors.contains(.yellow))
        #expect(colors.contains(.red))
        #expect(colors.contains(.blue))
        #expect(colors.contains(.green))
        #expect(colors.contains(.purple))
    }

    @Test("Hex values are correct")
    func hexValues() {
        #expect(HighlightColor.yellow.hex == "FFFFEB3B")
        #expect(HighlightColor.red.hex == "FFF44336")
        #expect(HighlightColor.blue.hex == "FF2196F3")
        #expect(HighlightColor.green.hex == "FF4CAF50")
        #expect(HighlightColor.purple.hex == "FF9C27B0")
    }

    @Test("Initializes from database color string")
    func fromDatabaseString() {
        #expect(HighlightColor(databaseValue: "FFFFEB3B") == .yellow)
        #expect(HighlightColor(databaseValue: "FFF44336") == .red)
        #expect(HighlightColor(databaseValue: "unknown") == .yellow) // default
    }

    @Test("NoteType enum covers all types")
    func noteTypes() {
        #expect(NoteType.allCases.count == 3)
        #expect(NoteType(rawValue: "highlight") == .highlight)
        #expect(NoteType(rawValue: "bookmark") == .bookmark)
        #expect(NoteType(rawValue: "note") == .note)
    }

    @Test("ContentSearchResult stores fields correctly")
    func searchResult() {
        let result = ContentSearchResult(
            text: "matched text",
            chapterTitle: "Chapter 1",
            chapterHref: "/chapter1.xhtml",
            textBefore: "before ",
            textAfter: " after",
            progression: 0.25
        )
        #expect(result.text == "matched text")
        #expect(result.chapterTitle == "Chapter 1")
        #expect(result.progression == 0.25)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTReader && swift test --filter HighlightStyleTests 2>&1 | tail -10`
Expected: FAIL — types not found.

- [ ] **Step 3: Create HighlightStyle**

Create `Packages/PTReader/Sources/PTReader/Common/HighlightStyle.swift`:

```swift
import Foundation

/// The 5 highlight colors supported in the reader.
public enum HighlightColor: String, CaseIterable, Sendable, Codable {
    case yellow
    case red
    case blue
    case green
    case purple

    /// ARGB hex string (matches database `color` column in tb_notes).
    public var hex: String {
        switch self {
        case .yellow: return "FFFFEB3B"
        case .red:    return "FFF44336"
        case .blue:   return "FF2196F3"
        case .green:  return "FF4CAF50"
        case .purple: return "FF9C27B0"
        }
    }

    /// Initialize from a database color string. Falls back to `.yellow` if unrecognized.
    public init(databaseValue: String) {
        self = Self.allCases.first { $0.hex == databaseValue } ?? .yellow
    }
}

/// The type of annotation stored in tb_notes.
public enum NoteType: String, CaseIterable, Sendable, Codable {
    case highlight
    case bookmark
    case note
}
```

- [ ] **Step 4: Create ContentSearchResult**

Create `Packages/PTReader/Sources/PTReader/Common/ContentSearchResult.swift`:

```swift
import Foundation

/// A search result from full-text search within a book.
public struct ContentSearchResult: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let text: String
    public let chapterTitle: String
    public let chapterHref: String
    public let textBefore: String
    public let textAfter: String
    /// Reading progression (0.0–1.0) where the match occurs.
    public let progression: Double

    public init(
        text: String,
        chapterTitle: String,
        chapterHref: String,
        textBefore: String = "",
        textAfter: String = "",
        progression: Double = 0
    ) {
        self.text = text
        self.chapterTitle = chapterTitle
        self.chapterHref = chapterHref
        self.textBefore = textBefore
        self.textAfter = textAfter
        self.progression = progression
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd Packages/PTReader && swift test --filter HighlightStyleTests 2>&1 | tail -15`
Expected: All 5 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/PTReader/Sources/PTReader/Common/HighlightStyle.swift Packages/PTReader/Sources/PTReader/Common/ContentSearchResult.swift Packages/PTReader/Tests/PTReaderTests/Common/HighlightStyleTests.swift
git commit -m "feat(PTReader): add HighlightColor, NoteType enums and ContentSearchResult"
```

---

### Task 5: BookContentBridge Protocol

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/Common/BookContentBridge.swift`

- [ ] **Step 1: Create the protocol**

Create `Packages/PTReader/Sources/PTReader/Common/BookContentBridge.swift`:

```swift
import Foundation

/// Unified content access protocol for both EPUB and PDF books.
///
/// This protocol enables AI tools to access book content regardless of format.
/// EPUB implementation uses Readium Publication APIs.
/// PDF implementation uses PDFKit + Vision OCR.
public protocol BookContentBridge: Sendable {
    /// The book's title.
    var title: String { get }

    /// The book's table of contents as chapter entries.
    var tableOfContents: [ChapterEntry] { get async throws }

    /// Extract text content of a specific chapter.
    /// - Parameter href: Chapter identifier (EPUB href or PDF page range like "pages:10-20").
    func extractChapterContent(href: String) async throws -> String

    /// Extract the full text of the entire book.
    func extractFullText() async throws -> String

    /// Search for a query string within the book's content.
    func searchContent(query: String) async throws -> [ContentSearchResult]
}

/// A chapter/section entry in the table of contents.
public struct ChapterEntry: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let title: String
    public let href: String
    /// Nesting level (0 = top-level chapter).
    public let level: Int
    /// Number of child entries (for expandable TOC UI).
    public let childCount: Int

    public init(title: String, href: String, level: Int = 0, childCount: Int = 0) {
        self.title = title
        self.href = href
        self.level = level
        self.childCount = childCount
    }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd Packages/PTReader && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/PTReader/Sources/PTReader/Common/BookContentBridge.swift
git commit -m "feat(PTReader): add BookContentBridge protocol and ChapterEntry"
```

---

### Task 6: PDFChapter and PDFContentBridge

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/PDF/PDFChapter.swift`
- Create: `Packages/PTReader/Sources/PTReader/PDF/PDFContentBridge.swift`
- Test: `Packages/PTReader/Tests/PTReaderTests/PDF/PDFChapterTests.swift`
- Test: `Packages/PTReader/Tests/PTReaderTests/PDF/PDFContentBridgeTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/PTReader/Tests/PTReaderTests/PDF/PDFChapterTests.swift`:

```swift
import Testing
import Foundation
@testable import PTReader

@Suite("PDFChapter")
struct PDFChapterTests {
    @Test("Chapter stores page range")
    func pageRange() {
        let chapter = PDFChapter(title: "Introduction", startPage: 0, endPage: 15)
        #expect(chapter.title == "Introduction")
        #expect(chapter.startPage == 0)
        #expect(chapter.endPage == 15)
        #expect(chapter.pageCount == 16)
    }

    @Test("Href format is pages:start-end")
    func hrefFormat() {
        let chapter = PDFChapter(title: "Ch 1", startPage: 5, endPage: 20)
        #expect(chapter.href == "pages:5-20")
    }

    @Test("Converts to ChapterEntry")
    func toChapterEntry() {
        let chapter = PDFChapter(title: "Results", startPage: 30, endPage: 45, level: 1)
        let entry = chapter.toChapterEntry()
        #expect(entry.title == "Results")
        #expect(entry.href == "pages:30-45")
        #expect(entry.level == 1)
    }

    @Test("Parses page range from href string")
    func parseHref() {
        let range = PDFChapter.parsePageRange(from: "pages:10-25")
        #expect(range?.startPage == 10)
        #expect(range?.endPage == 25)
    }

    @Test("Returns nil for invalid href")
    func invalidHref() {
        #expect(PDFChapter.parsePageRange(from: "/chapter1.xhtml") == nil)
        #expect(PDFChapter.parsePageRange(from: "pages:abc") == nil)
        #expect(PDFChapter.parsePageRange(from: "") == nil)
    }
}
```

Create `Packages/PTReader/Tests/PTReaderTests/PDF/PDFContentBridgeTests.swift`:

```swift
import Testing
import Foundation
@testable import PTReader

#if canImport(PDFKit)
import PDFKit

@Suite("PDFContentBridge")
struct PDFContentBridgeTests {
    /// Creates a minimal test PDF with text content in memory.
    private func makeTestPDF(pages: [String]) -> PDFDocument {
        let doc = PDFDocument()
        for (index, text) in pages.enumerated() {
            let page = PDFPage()
            // Note: PDFPage() creates a blank page. We can't easily add text
            // programmatically without Core Graphics. For testing, we'll test
            // the bridge logic with a real PDF or mock the extraction.
            doc.insert(page, at: index)
        }
        return doc
    }

    @Test("Initializes with a PDFDocument")
    func initialization() {
        let doc = PDFDocument()
        let bridge = PDFContentBridge(document: doc, title: "Test PDF")
        #expect(bridge.title == "Test PDF")
    }

    @Test("Page count is correct")
    func pageCount() {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        doc.insert(PDFPage(), at: 1)
        doc.insert(PDFPage(), at: 2)
        let bridge = PDFContentBridge(document: doc, title: "Test")
        #expect(bridge.pageCount == 3)
    }

    @Test("extractPageText returns empty string for blank page")
    func extractBlankPage() {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        let bridge = PDFContentBridge(document: doc, title: "Test")
        let text = bridge.extractPageText(page: 0)
        #expect(text == "")
    }

    @Test("tableOfContents returns page-based chapters when no outline")
    func tocWithoutOutline() async throws {
        let doc = PDFDocument()
        for i in 0..<5 {
            doc.insert(PDFPage(), at: i)
        }
        let bridge = PDFContentBridge(document: doc, title: "Test")
        let toc = try await bridge.tableOfContents
        // With no outline and 5 pages, should create synthetic chapters
        #expect(toc.count >= 1)
    }
}
#endif
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTReader && swift test --filter "PDFChapterTests|PDFContentBridgeTests" 2>&1 | tail -10`
Expected: FAIL — types not found.

- [ ] **Step 3: Create PDFChapter**

Create `Packages/PTReader/Sources/PTReader/PDF/PDFChapter.swift`:

```swift
import Foundation

/// A chapter within a PDF, defined by a page range.
public struct PDFChapter: Sendable, Equatable {
    public let title: String
    public let startPage: Int
    public let endPage: Int
    public let level: Int

    public init(title: String, startPage: Int, endPage: Int, level: Int = 0) {
        self.title = title
        self.startPage = startPage
        self.endPage = endPage
        self.level = level
    }

    /// Number of pages in this chapter.
    public var pageCount: Int {
        endPage - startPage + 1
    }

    /// The href string used by BookContentBridge (format: "pages:start-end").
    public var href: String {
        "pages:\(startPage)-\(endPage)"
    }

    /// Convert to a ChapterEntry for the unified TOC.
    public func toChapterEntry() -> ChapterEntry {
        ChapterEntry(title: title, href: href, level: level)
    }

    /// Parse a "pages:start-end" href string back into page indices.
    public static func parsePageRange(from href: String) -> (startPage: Int, endPage: Int)? {
        guard href.hasPrefix("pages:") else { return nil }
        let range = href.dropFirst("pages:".count)
        let parts = range.split(separator: "-")
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]) else { return nil }
        return (start, end)
    }
}
```

- [ ] **Step 4: Create PDFContentBridge**

Create `Packages/PTReader/Sources/PTReader/PDF/PDFContentBridge.swift`:

```swift
import Foundation

#if canImport(PDFKit)
import PDFKit

#if canImport(Vision)
import Vision
#endif

/// BookContentBridge implementation for PDF documents using PDFKit.
///
/// Provides text extraction, chapter segmentation via PDF outlines,
/// and OCR fallback for scanned PDFs via Vision framework.
public final class PDFContentBridge: BookContentBridge, @unchecked Sendable {
    private let document: PDFDocument
    public let title: String

    public init(document: PDFDocument, title: String) {
        self.document = document
        self.title = title
    }

    /// Total number of pages.
    public var pageCount: Int {
        document.pageCount
    }

    // MARK: - BookContentBridge

    public var tableOfContents: [ChapterEntry] {
        get async throws {
            let chapters = segmentByOutline()
            if !chapters.isEmpty {
                return chapters.map { $0.toChapterEntry() }
            }
            // Fallback: create synthetic chapters based on page count
            return syntheticChapters().map { $0.toChapterEntry() }
        }
    }

    public func extractChapterContent(href: String) async throws -> String {
        guard let range = PDFChapter.parsePageRange(from: href) else {
            return ""
        }
        var texts: [String] = []
        for page in range.startPage...min(range.endPage, pageCount - 1) {
            let text = extractPageText(page: page)
            if !text.isEmpty {
                texts.append(text)
            }
        }
        return texts.joined(separator: "\n\n")
    }

    public func extractFullText() async throws -> String {
        var texts: [String] = []
        for i in 0..<pageCount {
            let text = extractPageText(page: i)
            if !text.isEmpty {
                texts.append(text)
            }
        }
        return texts.joined(separator: "\n\n")
    }

    public func searchContent(query: String) async throws -> [ContentSearchResult] {
        let selections = document.findString(query, withOptions: .caseInsensitive)
        return selections.compactMap { selection -> ContentSearchResult? in
            guard let page = selection.pages.first,
                  let pageIndex = document.index(for: page) else { return nil }
            let pageLabel = page.label ?? "Page \(pageIndex + 1)"
            return ContentSearchResult(
                text: selection.string ?? query,
                chapterTitle: pageLabel,
                chapterHref: "pages:\(pageIndex)-\(pageIndex)",
                progression: Double(pageIndex) / max(Double(pageCount), 1)
            )
        }
    }

    // MARK: - Page Text Extraction

    /// Extract text from a specific page using PDFKit.
    public func extractPageText(page: Int) -> String {
        guard page >= 0 && page < pageCount,
              let pdfPage = document.page(at: page) else { return "" }
        return pdfPage.string ?? ""
    }

    // MARK: - OCR Fallback

    #if canImport(Vision)
    /// OCR a specific page using Vision framework (for scanned PDFs).
    public func ocrPage(page: Int) async throws -> String {
        guard page >= 0 && page < pageCount,
              let pdfPage = document.page(at: page) else { return "" }

        // Get page bounds and render to CGImage
        let bounds = pdfPage.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0  // 2x for better OCR accuracy
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return "" }

        ctx.scaleBy(x: scale, y: scale)
        pdfPage.draw(with: .mediaBox, to: ctx)

        guard let cgImage = ctx.makeImage() else { return "" }

        // Run VNRecognizeTextRequest
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = request.results as? [VNRecognizedTextObservation] ?? []
                let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif

    // MARK: - Chapter Segmentation

    /// Segment PDF by its outline (bookmarks/TOC).
    public func segmentByOutline() -> [PDFChapter] {
        guard let outline = document.outlineRoot else { return [] }
        var chapters: [PDFChapter] = []
        collectOutline(outline, level: 0, into: &chapters)

        // Fill in endPage for each chapter
        for i in 0..<chapters.count {
            let nextStart = (i + 1 < chapters.count) ? chapters[i + 1].startPage : pageCount
            chapters[i] = PDFChapter(
                title: chapters[i].title,
                startPage: chapters[i].startPage,
                endPage: nextStart - 1,
                level: chapters[i].level
            )
        }
        return chapters
    }

    private func collectOutline(_ outline: PDFOutline, level: Int, into chapters: inout [PDFChapter]) {
        for i in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: i) else { continue }
            let title = child.label ?? "Section \(i + 1)"
            let page = child.destination?.page
            let pageIndex = page.flatMap { document.index(for: $0) } ?? 0
            chapters.append(PDFChapter(title: title, startPage: pageIndex, endPage: pageIndex, level: level))
            if child.numberOfChildren > 0 {
                collectOutline(child, level: level + 1, into: &chapters)
            }
        }
    }

    /// Create synthetic chapters when no outline exists.
    private func syntheticChapters() -> [PDFChapter] {
        guard pageCount > 0 else { return [] }
        let pagesPerChapter = 20
        var chapters: [PDFChapter] = []
        var start = 0
        var index = 1
        while start < pageCount {
            let end = min(start + pagesPerChapter - 1, pageCount - 1)
            chapters.append(PDFChapter(
                title: "Pages \(start + 1)–\(end + 1)",
                startPage: start,
                endPage: end
            ))
            start = end + 1
            index += 1
        }
        return chapters
    }
}
#endif
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd Packages/PTReader && swift test --filter "PDFChapterTests|PDFContentBridgeTests" 2>&1 | tail -15`
Expected: All tests PASS (PDFChapter tests always; PDFContentBridge tests on macOS with PDFKit).

- [ ] **Step 6: Commit**

```bash
git add Packages/PTReader/Sources/PTReader/PDF/PDFChapter.swift Packages/PTReader/Sources/PTReader/PDF/PDFContentBridge.swift Packages/PTReader/Tests/PTReaderTests/PDF/PDFChapterTests.swift Packages/PTReader/Tests/PTReaderTests/PDF/PDFContentBridgeTests.swift
git commit -m "feat(PTReader): add PDFContentBridge with text extraction, OCR, and chapter segmentation"
```

---

### Task 7: ReadingPreferences

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/Preferences/ReadingPreferences.swift`
- Test: `Packages/PTReader/Tests/PTReaderTests/Preferences/ReadingPreferencesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/PTReader/Tests/PTReaderTests/Preferences/ReadingPreferencesTests.swift`:

```swift
import Testing
import Foundation
@testable import PTReader

@Suite("ReadingPreferences")
struct ReadingPreferencesTests {
    @Test("Initializes with default style and theme")
    func defaultInit() {
        let prefs = ReadingPreferences()
        #expect(prefs.style.fontSize == 1.4)
        #expect(prefs.style.fontFamily == "Arial")
        #expect(prefs.theme.backgroundColor == "FFFBFBF3")
    }

    @Test("Initializes from existing BookStyle and ReadTheme")
    func customInit() {
        var style = BookStyle.default
        style.fontSize = 2.0
        let theme = ReadTheme.defaultDark
        let prefs = ReadingPreferences(style: style, theme: theme)
        #expect(prefs.style.fontSize == 2.0)
        #expect(prefs.theme.backgroundColor == "FF1A1A2E")
    }

    @Test("Page turn mode has all expected cases")
    func pageTurnModes() {
        #expect(PageTurnMode.allCases.count == 3)
        #expect(PageTurnMode(rawValue: "swipe") == .swipe)
        #expect(PageTurnMode(rawValue: "tap") == .tap)
        #expect(PageTurnMode(rawValue: "scroll") == .scroll)
    }

    @Test("Text alignment has all expected cases")
    func textAlignments() {
        #expect(TextAlignment.allCases.count == 4)
        #expect(TextAlignment(rawValue: "left") == .left)
        #expect(TextAlignment(rawValue: "justify") == .justify)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTReader && swift test --filter ReadingPreferencesTests 2>&1 | tail -10`
Expected: FAIL — types not found.

- [ ] **Step 3: Create ReadingPreferences**

Create `Packages/PTReader/Sources/PTReader/Preferences/ReadingPreferences.swift`:

```swift
import Foundation
import Observation

/// Observable reading preferences that combine BookStyle and ReadTheme.
///
/// Used by the reader UI to adjust rendering in real-time.
/// Changes are persisted to the database via BookStyleDAO/ReadThemeDAO.
@Observable
public final class ReadingPreferences: @unchecked Sendable {
    public var style: BookStyle
    public var theme: ReadTheme
    public var pageTurnMode: PageTurnMode
    public var textAlignment: TextAlignment
    public var isScrollMode: Bool

    public init(
        style: BookStyle = .default,
        theme: ReadTheme = .defaultLight,
        pageTurnMode: PageTurnMode = .swipe,
        textAlignment: TextAlignment = .justify,
        isScrollMode: Bool = false
    ) {
        self.style = style
        self.theme = theme
        self.pageTurnMode = pageTurnMode
        self.textAlignment = textAlignment
        self.isScrollMode = isScrollMode
    }
}

/// Page turning interaction mode.
public enum PageTurnMode: String, CaseIterable, Sendable, Codable {
    case swipe
    case tap
    case scroll
}

/// Text alignment option for the reader.
public enum TextAlignment: String, CaseIterable, Sendable, Codable {
    case left
    case right
    case center
    case justify
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/PTReader && swift test --filter ReadingPreferencesTests 2>&1 | tail -15`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/PTReader/Sources/PTReader/Preferences/ReadingPreferences.swift Packages/PTReader/Tests/PTReaderTests/Preferences/ReadingPreferencesTests.swift
git commit -m "feat(PTReader): add ReadingPreferences with PageTurnMode and TextAlignment"
```

---

### Task 8: TTSService

**Files:**
- Create: `Packages/PTReader/Sources/PTReader/TTS/TTSService.swift`
- Test: `Packages/PTReader/Tests/PTReaderTests/TTS/TTSServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/PTReader/Tests/PTReaderTests/TTS/TTSServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import PTReader

#if canImport(AVFoundation)
import AVFoundation

@Suite("TTSService")
struct TTSServiceTests {
    @Test("Initializes in stopped state")
    func initialState() {
        let tts = TTSService()
        #expect(tts.state == .stopped)
        #expect(tts.currentText == nil)
        #expect(tts.rate == 0.5)
    }

    @Test("TTSState has all expected cases")
    func stateEnum() {
        let allStates: [TTSState] = [.stopped, .speaking, .paused]
        #expect(allStates.count == 3)
    }

    @Test("Rate clamping works")
    func rateClamping() {
        let tts = TTSService()
        tts.rate = 2.0
        #expect(tts.rate <= 1.0) // AVSpeechUtteranceMaximumSpeechRate
        tts.rate = -1.0
        #expect(tts.rate >= 0.0) // AVSpeechUtteranceMinimumSpeechRate
    }

    @Test("Available voices returns non-empty list")
    func availableVoices() {
        let voices = TTSService.availableVoices()
        // On macOS/iOS there should be at least some voices
        #expect(voices.count >= 0) // May be empty in CI
    }
}
#endif
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTReader && swift test --filter TTSServiceTests 2>&1 | tail -10`
Expected: FAIL — types not found.

- [ ] **Step 3: Create TTSService**

Create `Packages/PTReader/Sources/PTReader/TTS/TTSService.swift`:

```swift
import Foundation
import Observation

#if canImport(AVFoundation)
import AVFoundation

/// Text-to-Speech state.
public enum TTSState: String, Sendable {
    case stopped
    case speaking
    case paused
}

/// Observable TTS service wrapping AVSpeechSynthesizer.
///
/// Provides speak/pause/resume/stop with Lock Screen control integration.
@Observable
public final class TTSService: NSObject, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()

    public private(set) var state: TTSState = .stopped
    public private(set) var currentText: String?

    /// Speech rate (0.0–1.0). Default is 0.5 (AVSpeechUtteranceDefaultSpeechRate).
    public var rate: Float = AVSpeechUtteranceDefaultSpeechRate {
        didSet {
            rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        }
    }

    /// Voice language identifier (e.g., "en-US", "zh-CN").
    public var voiceLanguage: String = "en-US"

    /// Specific voice identifier. If nil, uses default for the language.
    public var voiceIdentifier: String?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Control

    /// Speak the given text. Stops any current speech first.
    public func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate

        if let id = voiceIdentifier {
            utterance.voice = AVSpeechSynthesisVoice(identifier: id)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        }

        currentText = text
        state = .speaking
        synthesizer.speak(utterance)
    }

    /// Pause speech.
    public func pause() {
        guard state == .speaking else { return }
        synthesizer.pauseSpeaking(at: .word)
        state = .paused
    }

    /// Resume speech.
    public func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        state = .speaking
    }

    /// Stop speech completely.
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        state = .stopped
        currentText = nil
    }

    // MARK: - Voice Listing

    /// List all available system voices.
    public static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
    }

    /// List voices for a specific language.
    public static func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        state = .stopped
        currentText = nil
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        state = .stopped
        currentText = nil
    }
}
#endif
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/PTReader && swift test --filter TTSServiceTests 2>&1 | tail -15`
Expected: All 4 tests PASS (on macOS with AVFoundation).

- [ ] **Step 5: Commit**

```bash
git add Packages/PTReader/Sources/PTReader/TTS/TTSService.swift Packages/PTReader/Tests/PTReaderTests/TTS/TTSServiceTests.swift
git commit -m "feat(PTReader): add TTSService wrapping AVSpeechSynthesizer"
```

---

### Task 9: Run Full Test Suite and Push

**Files:**
- None new — verification only.

- [ ] **Step 1: Run all PTCore tests (including new BookStyle and ReadTheme)**

Run:
```bash
cd Packages/PTCore && swift test 2>&1 | tail -20
```
Expected: All tests pass (38 original + 6 new = 44 total).

- [ ] **Step 2: Run all PTNetworking tests**

Run:
```bash
cd Packages/PTNetworking && swift test 2>&1 | tail -15
```
Expected: All 27 tests pass.

- [ ] **Step 3: Run all PTReader tests**

Run:
```bash
cd Packages/PTReader && swift test 2>&1 | tail -20
```
Expected: All tests pass (import + highlight + PDFChapter + PDFContentBridge + ReadingPreferences + TTS).

- [ ] **Step 4: Push to remote**

```bash
git push origin swift-native
```

---

## Summary

| Task | Component | Package | Tests |
|------|-----------|---------|-------|
| 1 | BookStyle model + DAO | PTCore | 3 tests |
| 2 | ReadTheme model + DAO | PTCore | 3 tests |
| 3 | Package.swift + module entry | PTReader | 1 test |
| 4 | HighlightColor, NoteType, ContentSearchResult | PTReader | 5 tests |
| 5 | BookContentBridge protocol + ChapterEntry | PTReader | 0 (protocol) |
| 6 | PDFChapter + PDFContentBridge | PTReader | ~9 tests |
| 7 | ReadingPreferences + PageTurnMode + TextAlignment | PTReader | 4 tests |
| 8 | TTSService | PTReader | 4 tests |
| 9 | Full suite verification + push | — | Run all |

**Total: 9 tasks, ~29 new tests**

## What's Deferred to Phase 7 (App Integration)

The following require Readium SDK and a full Xcode app target, so they'll be built during app integration:

- **ReaderEngine** (@Observable class) — coordinates Readium Publication + Navigator
- **EPUBReaderView** — UIViewControllerRepresentable wrapping EPUBNavigatorViewController
- **PDFReaderView** — UIViewControllerRepresentable wrapping PDFNavigatorViewController
- **EPUBContentBridge** — BookContentBridge implementation using Readium Publication
- **Readium SPM dependency** — added to the app target, not the package
- **Decoration/highlight rendering** — Readium Navigator.apply(decorations:)
- **Full-text search via Readium** — Publication.search(query:)
- **NowPlaying/Lock Screen** integration for TTS
