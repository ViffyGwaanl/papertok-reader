# Phase 1: Project Foundation + PTCore — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the orphan branch `swift-native`, initialize the Xcode Multiplatform project with SwiftUI, and build the PTCore Swift Package (models, database with GRDB, configuration, enums, utilities).

**Architecture:** Modular Swift Package monorepo. PTCore is the foundation layer with zero UI dependencies — only GRDB.swift for SQLite. All other packages will depend on PTCore. The database schema is identical to the existing Flutter SQLite schema (version 7) for zero-cost data migration.

**Tech Stack:** Swift 5.9+, SwiftUI, GRDB.swift 7.x, Xcode 15+, iOS 17.0 / macOS 14.0

---

## Phased Plan Overview

This is **Phase 1 of 7**. Each phase produces a buildable, testable artifact:

| Phase | Package/Scope | Depends On |
|-------|--------------|------------|
| **1 (this)** | Foundation + PTCore | — |
| 2 | PTNetworking | PTCore |
| 3 | PTReader (Readium) | PTCore |
| 4 | PTUI (components + Morandi theme) | PTCore |
| 5 | PTAIServices | PTCore + PTNetworking |
| 6 | PTFeatures (all screens) | All packages |
| 7 | App integration (nav, platform, l10n) | PTFeatures |

---

## File Structure (Phase 1)

```
PaperTokReader/
├── PaperTokReader.xcodeproj/          # Xcode project (Multiplatform)
├── App/
│   ├── PaperTokReaderApp.swift        # @main entry (minimal)
│   └── ContentView.swift              # Placeholder
├── Packages/
│   └── PTCore/
│       ├── Package.swift
│       ├── Sources/PTCore/
│       │   ├── Models/
│       │   │   ├── Book.swift
│       │   │   ├── BookNote.swift
│       │   │   ├── ReadingTime.swift
│       │   │   ├── Tag.swift
│       │   │   ├── BookTag.swift
│       │   │   └── TbGroup.swift
│       │   ├── Database/
│       │   │   ├── AppDatabase.swift       # GRDB setup + migrations
│       │   │   ├── BookDAO.swift
│       │   │   ├── BookNoteDAO.swift
│       │   │   ├── ReadingTimeDAO.swift
│       │   │   ├── TagDAO.swift
│       │   │   └── GroupDAO.swift
│       │   ├── Config/
│       │   │   ├── AppConfig.swift
│       │   │   └── KeychainService.swift
│       │   └── Utils/
│       │       └── DateFormatting.swift
│       └── Tests/PTCoreTests/
│           ├── Models/
│           │   ├── BookTests.swift
│           │   └── BookNoteTests.swift
│           ├── Database/
│           │   ├── AppDatabaseTests.swift
│           │   ├── BookDAOTests.swift
│           │   ├── BookNoteDAOTests.swift
│           │   ├── ReadingTimeDAOTests.swift
│           │   ├── TagDAOTests.swift
│           │   └── GroupDAOTests.swift
│           └── Config/
│               └── AppConfigTests.swift
```

---

### Task 1: Create Orphan Branch and Xcode Project

**Files:**
- Create: `PaperTokReader.xcodeproj/` (via Xcode CLI)
- Create: `App/PaperTokReaderApp.swift`
- Create: `App/ContentView.swift`

- [ ] **Step 1: Create orphan branch**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
git checkout --orphan swift-native
git rm -rf .
git clean -fd
```

- [ ] **Step 2: Create Xcode Multiplatform App project structure**

Create the directory layout manually (we'll add Xcode project via `swift package init` for packages and manual project setup):

```bash
mkdir -p App
mkdir -p Packages/PTCore/Sources/PTCore/{Models,Database,Config,Utils}
mkdir -p Packages/PTCore/Tests/PTCoreTests/{Models,Database,Config}
```

- [ ] **Step 3: Write the App entry point**

`App/PaperTokReaderApp.swift`:
```swift
import SwiftUI

@main
struct PaperTokReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`App/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("PaperTok Reader")
            .font(.largeTitle)
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 4: Create PTCore Package.swift**

`Packages/PTCore/Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PTCore", targets: ["PTCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "PTCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "PTCoreTests",
            dependencies: ["PTCore"]
        )
    ]
)
```

- [ ] **Step 5: Create placeholder source so package compiles**

`Packages/PTCore/Sources/PTCore/PTCore.swift`:
```swift
// PTCore — Foundation layer for PaperTok Reader
// Models, Database (GRDB), Configuration, Utilities
public enum PTCore {
    public static let version = "1.0.0"
}
```

- [ ] **Step 6: Verify PTCore package resolves and builds**

```bash
cd Packages/PTCore
swift package resolve
swift build
```

Expected: Build succeeds with no errors.

- [ ] **Step 7: Initial commit**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
git add -A
git commit -m "feat: initialize swift-native branch with Xcode project and PTCore package

Orphan branch for native Swift iOS/macOS rewrite.
- Multiplatform SwiftUI app entry point
- PTCore Swift Package with GRDB.swift dependency
- iOS 17.0 / macOS 14.0 minimum targets"
```

---

### Task 2: Book Model

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Models/Book.swift`
- Create: `Packages/PTCore/Tests/PTCoreTests/Models/BookTests.swift`

- [ ] **Step 1: Write the failing test**

`Packages/PTCore/Tests/PTCoreTests/Models/BookTests.swift`:
```swift
import Testing
import GRDB
@testable import PTCore

@Suite("Book Model")
struct BookTests {
    @Test("Book round-trips through database columns")
    func bookDatabaseRoundTrip() throws {
        let book = Book(
            id: 1,
            title: "Test Book",
            coverPath: "/covers/test.jpg",
            filePath: "/books/test.epub",
            lastReadPosition: "epubcfi(/6/4!/4/2/1:0)",
            readingPercentage: 0.42,
            author: "Test Author",
            isDeleted: false,
            description: "A test book",
            rating: 4.5,
            groupId: 0,
            md5: "abc123",
            createTime: Date(timeIntervalSince1970: 1700000000),
            updateTime: Date(timeIntervalSince1970: 1700000000)
        )

        // Verify it conforms to required GRDB protocols
        let row = try book.encode(to: Row())
        let decoded = try Book(row: row)

        #expect(decoded.title == "Test Book")
        #expect(decoded.readingPercentage == 0.42)
        #expect(decoded.isDeleted == false)
        #expect(decoded.md5 == "abc123")
    }

    @Test("Book table name matches Flutter schema")
    func bookTableName() {
        #expect(Book.databaseTableName == "tb_books")
    }

    @Test("Book default values")
    func bookDefaults() {
        let book = Book.placeholder(title: "Untitled", filePath: "/books/x.epub")
        #expect(book.readingPercentage == 0)
        #expect(book.isDeleted == false)
        #expect(book.rating == 0)
        #expect(book.groupId == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Packages/PTCore
swift test --filter BookTests 2>&1
```

Expected: FAIL — `Book` type not found.

- [ ] **Step 3: Write Book model**

`Packages/PTCore/Sources/PTCore/Models/Book.swift`:
```swift
import Foundation
import GRDB

/// Book model — maps to `tb_books` table (Flutter schema v7)
public struct Book: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: Int64?
    public var title: String
    public var coverPath: String
    public var filePath: String
    public var lastReadPosition: String
    public var readingPercentage: Double
    public var author: String
    public var isDeleted: Bool
    public var description: String?
    public var rating: Double
    public var groupId: Int64
    public var md5: String?
    public var createTime: Date
    public var updateTime: Date

    public static let databaseTableName = "tb_books"

    // Column mapping to match Flutter snake_case schema
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case coverPath = "cover_path"
        case filePath = "file_path"
        case lastReadPosition = "last_read_position"
        case readingPercentage = "reading_percentage"
        case author
        case isDeleted = "is_deleted"
        case description
        case rating
        case groupId = "group_id"
        case md5 = "file_md5"
        case createTime = "create_time"
        case updateTime = "update_time"
    }

    /// Convenience initializer with defaults
    public static func placeholder(title: String, filePath: String) -> Book {
        Book(
            id: nil,
            title: title,
            coverPath: "",
            filePath: filePath,
            lastReadPosition: "",
            readingPercentage: 0,
            author: "",
            isDeleted: false,
            description: nil,
            rating: 0,
            groupId: 0,
            md5: nil,
            createTime: Date(),
            updateTime: Date()
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd Packages/PTCore
swift test --filter BookTests 2>&1
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/Models/Book.swift Packages/PTCore/Tests/PTCoreTests/Models/BookTests.swift
git commit -m "feat(PTCore): add Book model with GRDB persistence"
```

---

### Task 3: BookNote Model

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Models/BookNote.swift`
- Create: `Packages/PTCore/Tests/PTCoreTests/Models/BookNoteTests.swift`

- [ ] **Step 1: Write the failing test**

`Packages/PTCore/Tests/PTCoreTests/Models/BookNoteTests.swift`:
```swift
import Testing
import GRDB
@testable import PTCore

@Suite("BookNote Model")
struct BookNoteTests {
    @Test("BookNote table name matches Flutter schema")
    func tableNameMatches() {
        #expect(BookNote.databaseTableName == "tb_notes")
    }

    @Test("BookNote round-trips through database columns")
    func roundTrip() throws {
        let note = BookNote(
            id: 1,
            bookId: 42,
            content: "Important passage",
            cfi: "epubcfi(/6/4!/4/2/1:0)",
            chapter: "Chapter 1",
            type: "highlight",
            color: "FFD700",
            readerNote: "My thoughts on this",
            createTime: Date(timeIntervalSince1970: 1700000000),
            updateTime: Date(timeIntervalSince1970: 1700000000)
        )

        let row = try note.encode(to: Row())
        let decoded = try BookNote(row: row)

        #expect(decoded.bookId == 42)
        #expect(decoded.content == "Important passage")
        #expect(decoded.type == "highlight")
        #expect(decoded.readerNote == "My thoughts on this")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Packages/PTCore
swift test --filter BookNoteTests 2>&1
```

Expected: FAIL — `BookNote` type not found.

- [ ] **Step 3: Write BookNote model**

`Packages/PTCore/Sources/PTCore/Models/BookNote.swift`:
```swift
import Foundation
import GRDB

/// BookNote model — maps to `tb_notes` table (Flutter schema v7)
public struct BookNote: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: Int64?
    public var bookId: Int64
    public var content: String
    public var cfi: String
    public var chapter: String
    public var type: String
    public var color: String
    public var readerNote: String?
    public var createTime: Date?
    public var updateTime: Date

    public static let databaseTableName = "tb_notes"

    enum CodingKeys: String, CodingKey {
        case id
        case bookId = "book_id"
        case content
        case cfi
        case chapter
        case type
        case color
        case readerNote = "reader_note"
        case createTime = "create_time"
        case updateTime = "update_time"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd Packages/PTCore
swift test --filter BookNoteTests 2>&1
```

Expected: All 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/Models/BookNote.swift Packages/PTCore/Tests/PTCoreTests/Models/BookNoteTests.swift
git commit -m "feat(PTCore): add BookNote model with GRDB persistence"
```

---

### Task 4: Remaining Core Models (ReadingTime, Tag, BookTag, TbGroup)

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Models/ReadingTime.swift`
- Create: `Packages/PTCore/Sources/PTCore/Models/Tag.swift`
- Create: `Packages/PTCore/Sources/PTCore/Models/BookTag.swift`
- Create: `Packages/PTCore/Sources/PTCore/Models/TbGroup.swift`
- Create: `Packages/PTCore/Tests/PTCoreTests/Models/RemainingModelsTests.swift`

- [ ] **Step 1: Write the failing tests**

`Packages/PTCore/Tests/PTCoreTests/Models/RemainingModelsTests.swift`:
```swift
import Testing
import GRDB
@testable import PTCore

@Suite("Remaining Core Models")
struct RemainingModelsTests {
    @Test("ReadingTime table name")
    func readingTimeTableName() {
        #expect(ReadingTime.databaseTableName == "tb_reading_time")
    }

    @Test("ReadingTime round-trip")
    func readingTimeRoundTrip() throws {
        let rt = ReadingTime(id: 1, bookId: 42, date: "2026-04-03", readingTime: 3600)
        let row = try rt.encode(to: Row())
        let decoded = try ReadingTime(row: row)
        #expect(decoded.bookId == 42)
        #expect(decoded.readingTime == 3600)
    }

    @Test("Tag table name uses tb_styles sentinel")
    func tagTableName() {
        // Tags are stored in tb_styles with sentinel values in Flutter
        // In Swift we use a dedicated table for cleanliness
        #expect(Tag.databaseTableName == "tb_tags")
    }

    @Test("Tag round-trip")
    func tagRoundTrip() throws {
        let tag = Tag(id: 1, name: "Science", colorHex: "FF5733")
        let row = try tag.encode(to: Row())
        let decoded = try Tag(row: row)
        #expect(decoded.name == "Science")
        #expect(decoded.colorHex == "FF5733")
    }

    @Test("BookTag round-trip")
    func bookTagRoundTrip() throws {
        let bt = BookTag(id: 1, bookId: 42, tagId: 7)
        let row = try bt.encode(to: Row())
        let decoded = try BookTag(row: row)
        #expect(decoded.bookId == 42)
        #expect(decoded.tagId == 7)
    }

    @Test("TbGroup table name")
    func tbGroupTableName() {
        #expect(TbGroup.databaseTableName == "tb_groups")
    }

    @Test("TbGroup supports hierarchy")
    func tbGroupHierarchy() throws {
        let group = TbGroup(id: 1, name: "Folder A", parentId: nil, isDeleted: false, createTime: Date(), updateTime: Date())
        let child = TbGroup(id: 2, name: "Subfolder", parentId: 1, isDeleted: false, createTime: Date(), updateTime: Date())

        #expect(group.parentId == nil)
        #expect(child.parentId == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Packages/PTCore
swift test --filter RemainingModelsTests 2>&1
```

Expected: FAIL — types not found.

- [ ] **Step 3: Write ReadingTime model**

`Packages/PTCore/Sources/PTCore/Models/ReadingTime.swift`:
```swift
import Foundation
import GRDB

/// ReadingTime model — maps to `tb_reading_time` table
public struct ReadingTime: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: Int64?
    public var bookId: Int64
    public var date: String?
    public var readingTime: Int

    public static let databaseTableName = "tb_reading_time"

    enum CodingKeys: String, CodingKey {
        case id
        case bookId = "book_id"
        case date
        case readingTime = "reading_time"
    }
}
```

- [ ] **Step 4: Write Tag model**

`Packages/PTCore/Sources/PTCore/Models/Tag.swift`:
```swift
import Foundation
import GRDB

/// Tag model — stored as dedicated table (migrated from Flutter's tb_styles sentinel pattern)
public struct Tag: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: Int64?
    public var name: String
    public var colorHex: String?

    public static let databaseTableName = "tb_tags"

    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color"
    }
}
```

- [ ] **Step 5: Write BookTag model**

`Packages/PTCore/Sources/PTCore/Models/BookTag.swift`:
```swift
import Foundation
import GRDB

/// BookTag join model — links books to tags
public struct BookTag: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: Int64?
    public var bookId: Int64
    public var tagId: Int64

    public static let databaseTableName = "tb_book_tags"

    enum CodingKeys: String, CodingKey {
        case id
        case bookId = "book_id"
        case tagId = "tag_id"
    }
}
```

- [ ] **Step 6: Write TbGroup model**

`Packages/PTCore/Sources/PTCore/Models/TbGroup.swift`:
```swift
import Foundation
import GRDB

/// TbGroup model — maps to `tb_groups` table (hierarchical bookshelf folders)
public struct TbGroup: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: Int64?
    public var name: String
    public var parentId: Int64?
    public var isDeleted: Bool
    public var createTime: Date
    public var updateTime: Date

    public static let databaseTableName = "tb_groups"

    enum CodingKeys: String, CodingKey {
        case id, name
        case parentId = "parent_id"
        case isDeleted = "is_deleted"
        case createTime = "create_time"
        case updateTime = "update_time"
    }
}
```

- [ ] **Step 7: Run tests to verify all pass**

```bash
cd Packages/PTCore
swift test --filter RemainingModelsTests 2>&1
```

Expected: All 7 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/Models/ Packages/PTCore/Tests/PTCoreTests/Models/
git commit -m "feat(PTCore): add ReadingTime, Tag, BookTag, TbGroup models"
```

---

### Task 5: AppDatabase — GRDB Setup and Migrations

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Database/AppDatabase.swift`
- Create: `Packages/PTCore/Tests/PTCoreTests/Database/AppDatabaseTests.swift`

- [ ] **Step 1: Write the failing test**

`Packages/PTCore/Tests/PTCoreTests/Database/AppDatabaseTests.swift`:
```swift
import Testing
import GRDB
@testable import PTCore

@Suite("AppDatabase")
struct AppDatabaseTests {
    @Test("Creates all tables on fresh database")
    func freshDatabaseCreatesAllTables() throws {
        let db = try AppDatabase.makeInMemory()

        try db.reader.read { db in
            // Verify all tables exist
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            #expect(tables.contains("tb_books"))
            #expect(tables.contains("tb_notes"))
            #expect(tables.contains("tb_themes"))
            #expect(tables.contains("tb_styles"))
            #expect(tables.contains("tb_reading_time"))
            #expect(tables.contains("tb_groups"))
            #expect(tables.contains("tb_tags"))
            #expect(tables.contains("tb_book_tags"))
        }
    }

    @Test("Schema version is 7")
    func schemaVersion() throws {
        let db = try AppDatabase.makeInMemory()
        try db.reader.read { db in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version")
            #expect(version == 7)
        }
    }

    @Test("tb_books has all expected columns")
    func booksTableColumns() throws {
        let db = try AppDatabase.makeInMemory()
        try db.reader.read { db in
            let columns = try db.columns(in: "tb_books").map(\.name)
            #expect(columns.contains("id"))
            #expect(columns.contains("title"))
            #expect(columns.contains("cover_path"))
            #expect(columns.contains("file_path"))
            #expect(columns.contains("last_read_position"))
            #expect(columns.contains("reading_percentage"))
            #expect(columns.contains("author"))
            #expect(columns.contains("is_deleted"))
            #expect(columns.contains("description"))
            #expect(columns.contains("rating"))
            #expect(columns.contains("group_id"))
            #expect(columns.contains("file_md5"))
            #expect(columns.contains("create_time"))
            #expect(columns.contains("update_time"))
        }
    }

    @Test("Can insert and fetch a Book")
    func insertAndFetchBook() throws {
        let db = try AppDatabase.makeInMemory()
        var book = Book.placeholder(title: "Test", filePath: "/test.epub")

        try db.writer.write { db in
            try book.insert(db)
        }

        let fetched = try db.reader.read { db in
            try Book.fetchOne(db, key: book.id)
        }

        #expect(fetched?.title == "Test")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Packages/PTCore
swift test --filter AppDatabaseTests 2>&1
```

Expected: FAIL — `AppDatabase` not found.

- [ ] **Step 3: Write AppDatabase**

`Packages/PTCore/Sources/PTCore/Database/AppDatabase.swift`:
```swift
import Foundation
import GRDB

/// Central database manager for PaperTok Reader.
/// Schema version 7 — identical to Flutter's sqflite schema for migration compatibility.
public final class AppDatabase: Sendable {
    public let writer: DatabasePool
    public var reader: DatabaseReader { writer }

    public init(_ writer: DatabasePool) throws {
        self.writer = writer
        try migrator.migrate(writer)
    }

    /// In-memory database for testing
    public static func makeInMemory() throws -> AppDatabase {
        let writer = try DatabasePool(path: ":memory:")
        return try AppDatabase(writer)
    }

    /// On-disk database at specified path
    public static func make(at path: String) throws -> AppDatabase {
        let writer = try DatabasePool(path: path)
        return try AppDatabase(writer)
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v0-initial") { db in
            // tb_books
            try db.create(table: "tb_books") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text)
                t.column("cover_path", .text)
                t.column("file_path", .text)
                t.column("last_read_position", .text)
                t.column("reading_percentage", .double).defaults(to: 0)
                t.column("author", .text)
                t.column("is_deleted", .integer).defaults(to: 0)
                t.column("description", .text)
                t.column("rating", .double).defaults(to: 0)
                t.column("group_id", .integer).defaults(to: 0)
                t.column("file_md5", .text)
                t.column("create_time", .text)
                t.column("update_time", .text)
            }

            // tb_notes
            try db.create(table: "tb_notes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("book_id", .integer)
                t.column("content", .text)
                t.column("cfi", .text)
                t.column("chapter", .text)
                t.column("type", .text)
                t.column("color", .text)
                t.column("reader_note", .text)
                t.column("create_time", .text)
                t.column("update_time", .text)
            }

            // tb_themes
            try db.create(table: "tb_themes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("background_color", .text)
                t.column("text_color", .text)
                t.column("background_image_path", .text)
            }

            // tb_styles
            try db.create(table: "tb_styles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("font_size", .double)
                t.column("font_family", .text)
                t.column("line_height", .double)
                t.column("letter_spacing", .double)
                t.column("word_spacing", .double)
                t.column("paragraph_spacing", .double)
                t.column("side_margin", .double)
                t.column("top_margin", .double)
                t.column("bottom_margin", .double)
            }

            // tb_reading_time
            try db.create(table: "tb_reading_time") { t in
                t.primaryKey("id", .integer)
                t.column("book_id", .integer)
                t.column("date", .text)
                t.column("reading_time", .integer)
            }

            // tb_groups
            try db.create(table: "tb_groups") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text)
                t.column("parent_id", .integer)
                    .references("tb_groups", onDelete: .setNull)
                t.column("is_deleted", .integer).defaults(to: 0)
                t.column("create_time", .text)
                t.column("update_time", .text)
            }

            // tb_tags (new in Swift — migrated from Flutter's tb_styles sentinel pattern)
            try db.create(table: "tb_tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("color", .text)
            }

            // tb_book_tags (new in Swift — migrated from Flutter's tb_styles sentinel pattern)
            try db.create(table: "tb_book_tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("book_id", .integer).notNull()
                t.column("tag_id", .integer).notNull()
            }

            // Set schema version
            try db.execute(sql: "PRAGMA user_version = 7")
        }

        return migrator
    }
}
```

- [ ] **Step 4: Run tests to verify all pass**

```bash
cd Packages/PTCore
swift test --filter AppDatabaseTests 2>&1
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/Database/AppDatabase.swift Packages/PTCore/Tests/PTCoreTests/Database/AppDatabaseTests.swift
git commit -m "feat(PTCore): add AppDatabase with GRDB migrations (schema v7)"
```

---

### Task 6: BookDAO

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Database/BookDAO.swift`
- Create: `Packages/PTCore/Tests/PTCoreTests/Database/BookDAOTests.swift`

- [ ] **Step 1: Write the failing test**

`Packages/PTCore/Tests/PTCoreTests/Database/BookDAOTests.swift`:
```swift
import Testing
import GRDB
@testable import PTCore

@Suite("BookDAO")
struct BookDAOTests {
    private func makeDAO() throws -> (BookDAO, AppDatabase) {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        return (dao, db)
    }

    @Test("Insert and fetch book")
    func insertAndFetch() async throws {
        let (dao, _) = try makeDAO()
        var book = Book.placeholder(title: "Swift Programming", filePath: "/books/swift.epub")
        book.author = "Apple"

        let saved = try await dao.save(book)
        #expect(saved.id != nil)

        let fetched = try await dao.fetchById(saved.id!)
        #expect(fetched?.title == "Swift Programming")
        #expect(fetched?.author == "Apple")
    }

    @Test("Fetch all non-deleted books")
    func fetchAllNonDeleted() async throws {
        let (dao, _) = try makeDAO()

        var book1 = Book.placeholder(title: "Book 1", filePath: "/a.epub")
        var book2 = Book.placeholder(title: "Book 2", filePath: "/b.epub")
        book2.isDeleted = true

        _ = try await dao.save(book1)
        _ = try await dao.save(book2)

        let books = try await dao.fetchAll()
        #expect(books.count == 1)
        #expect(books[0].title == "Book 1")
    }

    @Test("Update book reading percentage")
    func updateReadingPercentage() async throws {
        let (dao, _) = try makeDAO()
        var book = Book.placeholder(title: "Test", filePath: "/x.epub")
        book = try await dao.save(book)

        book.readingPercentage = 0.75
        _ = try await dao.save(book)

        let fetched = try await dao.fetchById(book.id!)
        #expect(fetched?.readingPercentage == 0.75)
    }

    @Test("Search books by title")
    func searchByTitle() async throws {
        let (dao, _) = try makeDAO()
        _ = try await dao.save(Book.placeholder(title: "Swift Programming", filePath: "/a.epub"))
        _ = try await dao.save(Book.placeholder(title: "Kotlin Guide", filePath: "/b.epub"))

        let results = try await dao.search(query: "swift")
        #expect(results.count == 1)
        #expect(results[0].title == "Swift Programming")
    }

    @Test("Soft delete book")
    func softDelete() async throws {
        let (dao, _) = try makeDAO()
        var book = Book.placeholder(title: "Delete Me", filePath: "/x.epub")
        book = try await dao.save(book)

        try await dao.softDelete(id: book.id!)

        let fetched = try await dao.fetchById(book.id!)
        #expect(fetched?.isDeleted == true)

        let all = try await dao.fetchAll()
        #expect(all.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Packages/PTCore
swift test --filter BookDAOTests 2>&1
```

Expected: FAIL — `BookDAO` not found.

- [ ] **Step 3: Write BookDAO**

`Packages/PTCore/Sources/PTCore/Database/BookDAO.swift`:
```swift
import Foundation
import GRDB

/// Data access object for Book operations
public struct BookDAO: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Insert or update a book. Returns the saved book with id populated.
    @discardableResult
    public func save(_ book: Book) async throws -> Book {
        try await database.writer.write { db in
            var mutable = book
            try mutable.save(db)
            return mutable
        }
    }

    /// Fetch a book by id
    public func fetchById(_ id: Int64) async throws -> Book? {
        try await database.reader.read { db in
            try Book.fetchOne(db, key: id)
        }
    }

    /// Fetch all non-deleted books
    public func fetchAll() async throws -> [Book] {
        try await database.reader.read { db in
            try Book
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
        }
    }

    /// Search books by title or author (case-insensitive)
    public func search(query: String) async throws -> [Book] {
        try await database.reader.read { db in
            let pattern = "%\(query)%"
            return try Book
                .filter(Column("is_deleted") == false)
                .filter(
                    Column("title").like(pattern) ||
                    Column("author").like(pattern)
                )
                .fetchAll(db)
        }
    }

    /// Soft delete a book by id
    public func softDelete(id: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE tb_books SET is_deleted = 1, update_time = ? WHERE id = ?",
                arguments: [Date().formatted(.iso8601), id]
            )
        }
    }
}
```

- [ ] **Step 4: Run tests to verify all pass**

```bash
cd Packages/PTCore
swift test --filter BookDAOTests 2>&1
```

Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/Database/BookDAO.swift Packages/PTCore/Tests/PTCoreTests/Database/BookDAOTests.swift
git commit -m "feat(PTCore): add BookDAO with CRUD, search, soft delete"
```

---

### Task 7: BookNoteDAO

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Database/BookNoteDAO.swift`
- Create: `Packages/PTCore/Tests/PTCoreTests/Database/BookNoteDAOTests.swift`

- [ ] **Step 1: Write the failing test**

`Packages/PTCore/Tests/PTCoreTests/Database/BookNoteDAOTests.swift`:
```swift
import Testing
import GRDB
@testable import PTCore

@Suite("BookNoteDAO")
struct BookNoteDAOTests {
    private func makeDAO() throws -> (BookNoteDAO, AppDatabase) {
        let db = try AppDatabase.makeInMemory()
        let dao = BookNoteDAO(database: db)
        return (dao, db)
    }

    @Test("Insert and fetch notes by book")
    func insertAndFetchByBook() async throws {
        let (dao, _) = try makeDAO()

        let note = BookNote(
            id: nil, bookId: 1, content: "Highlighted text",
            cfi: "epubcfi(/6/4)", chapter: "Ch 1",
            type: "highlight", color: "FFD700",
            readerNote: nil, createTime: Date(), updateTime: Date()
        )
        _ = try await dao.save(note)

        let notes = try await dao.fetchByBookId(1)
        #expect(notes.count == 1)
        #expect(notes[0].content == "Highlighted text")
    }

    @Test("Delete note by id")
    func deleteById() async throws {
        let (dao, _) = try makeDAO()

        let note = BookNote(
            id: nil, bookId: 1, content: "Delete me",
            cfi: "epubcfi(/6/4)", chapter: "Ch 1",
            type: "highlight", color: "FFD700",
            readerNote: nil, createTime: Date(), updateTime: Date()
        )
        let saved = try await dao.save(note)
        try await dao.delete(id: saved.id!)

        let notes = try await dao.fetchByBookId(1)
        #expect(notes.isEmpty)
    }

    @Test("Count notes and books with notes")
    func countNotesAndBooks() async throws {
        let (dao, _) = try makeDAO()

        for bookId in [1, 1, 2] as [Int64] {
            let note = BookNote(
                id: nil, bookId: bookId, content: "Note",
                cfi: "epubcfi(/6/4)", chapter: "Ch",
                type: "highlight", color: "FFD700",
                readerNote: nil, createTime: Date(), updateTime: Date()
            )
            _ = try await dao.save(note)
        }

        let (noteCount, bookCount) = try await dao.countNotesAndBooks()
        #expect(noteCount == 3)
        #expect(bookCount == 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Packages/PTCore
swift test --filter BookNoteDAOTests 2>&1
```

Expected: FAIL — `BookNoteDAO` not found.

- [ ] **Step 3: Write BookNoteDAO**

`Packages/PTCore/Sources/PTCore/Database/BookNoteDAO.swift`:
```swift
import Foundation
import GRDB

/// Data access object for BookNote operations
public struct BookNoteDAO: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    @discardableResult
    public func save(_ note: BookNote) async throws -> BookNote {
        try await database.writer.write { db in
            var mutable = note
            try mutable.save(db)
            return mutable
        }
    }

    public func fetchByBookId(_ bookId: Int64) async throws -> [BookNote] {
        try await database.reader.read { db in
            try BookNote
                .filter(Column("book_id") == bookId)
                .order(Column("create_time").desc)
                .fetchAll(db)
        }
    }

    public func delete(id: Int64) async throws {
        try await database.writer.write { db in
            _ = try BookNote.deleteOne(db, key: id)
        }
    }

    /// Returns (totalNotes, booksWithNotes)
    public func countNotesAndBooks() async throws -> (Int, Int) {
        try await database.reader.read { db in
            let noteCount = try BookNote.fetchCount(db)
            let bookCount = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT book_id) FROM tb_notes") ?? 0
            return (noteCount, bookCount)
        }
    }

    public func search(keyword: String, bookId: Int64? = nil) async throws -> [BookNote] {
        try await database.reader.read { db in
            var query = BookNote.all()
            if let bookId {
                query = query.filter(Column("book_id") == bookId)
            }
            let pattern = "%\(keyword)%"
            query = query.filter(
                Column("content").like(pattern) ||
                Column("chapter").like(pattern) ||
                Column("reader_note").like(pattern)
            )
            return try query.fetchAll(db)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify all pass**

```bash
cd Packages/PTCore
swift test --filter BookNoteDAOTests 2>&1
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/Database/BookNoteDAO.swift Packages/PTCore/Tests/PTCoreTests/Database/BookNoteDAOTests.swift
git commit -m "feat(PTCore): add BookNoteDAO with CRUD and search"
```

---

### Task 8: ReadingTimeDAO, TagDAO, GroupDAO

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Database/ReadingTimeDAO.swift`
- Create: `Packages/PTCore/Sources/PTCore/Database/TagDAO.swift`
- Create: `Packages/PTCore/Sources/PTCore/Database/GroupDAO.swift`
- Create: `Packages/PTCore/Tests/PTCoreTests/Database/ReadingTimeDAOTests.swift`
- Create: `Packages/PTCore/Tests/PTCoreTests/Database/TagDAOTests.swift`
- Create: `Packages/PTCore/Tests/PTCoreTests/Database/GroupDAOTests.swift`

- [ ] **Step 1: Write all failing tests**

`Packages/PTCore/Tests/PTCoreTests/Database/ReadingTimeDAOTests.swift`:
```swift
import Testing
import GRDB
@testable import PTCore

@Suite("ReadingTimeDAO")
struct ReadingTimeDAOTests {
    @Test("Insert and fetch reading time")
    func insertAndFetch() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = ReadingTimeDAO(database: db)

        let rt = ReadingTime(id: nil, bookId: 1, date: "2026-04-03", readingTime: 1800)
        _ = try await dao.save(rt)

        let total = try await dao.totalReadingTime(bookId: 1)
        #expect(total == 1800)
    }

    @Test("Total reading time across all books")
    func totalAcrossBooks() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = ReadingTimeDAO(database: db)

        _ = try await dao.save(ReadingTime(id: nil, bookId: 1, date: "2026-04-03", readingTime: 600))
        _ = try await dao.save(ReadingTime(id: nil, bookId: 2, date: "2026-04-03", readingTime: 900))

        let total = try await dao.totalReadingTimeAllBooks()
        #expect(total == 1500)
    }
}
```

`Packages/PTCore/Tests/PTCoreTests/Database/TagDAOTests.swift`:
```swift
import Testing
import GRDB
@testable import PTCore

@Suite("TagDAO")
struct TagDAOTests {
    @Test("CRUD tags")
    func crudTags() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = TagDAO(database: db)

        // Create
        var tag = Tag(id: nil, name: "Science", colorHex: "FF5733")
        tag = try await dao.save(tag)
        #expect(tag.id != nil)

        // Read
        let all = try await dao.fetchAll()
        #expect(all.count == 1)

        // Update
        tag.name = "Physics"
        _ = try await dao.save(tag)
        let fetched = try await dao.fetchAll()
        #expect(fetched[0].name == "Physics")

        // Delete
        try await dao.delete(id: tag.id!)
        let empty = try await dao.fetchAll()
        #expect(empty.isEmpty)
    }

    @Test("Attach and detach book tags")
    func bookTagRelations() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = TagDAO(database: db)

        let tag = try await dao.save(Tag(id: nil, name: "AI", colorHex: nil))
        try await dao.attachTag(tagId: tag.id!, toBookId: 42)

        let tagIds = try await dao.fetchTagIds(forBookId: 42)
        #expect(tagIds == [tag.id!])

        try await dao.detachTag(tagId: tag.id!, fromBookId: 42)
        let empty = try await dao.fetchTagIds(forBookId: 42)
        #expect(empty.isEmpty)
    }
}
```

`Packages/PTCore/Tests/PTCoreTests/Database/GroupDAOTests.swift`:
```swift
import Testing
import GRDB
@testable import PTCore

@Suite("GroupDAO")
struct GroupDAOTests {
    @Test("Create and fetch groups")
    func createAndFetch() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = GroupDAO(database: db)

        let group = try await dao.save(TbGroup(id: nil, name: "Folder A", parentId: nil, isDeleted: false, createTime: Date(), updateTime: Date()))
        #expect(group.id != nil)

        let all = try await dao.fetchAll()
        #expect(all.count == 1)
    }

    @Test("Fetch child groups")
    func fetchChildren() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = GroupDAO(database: db)

        let parent = try await dao.save(TbGroup(id: nil, name: "Parent", parentId: nil, isDeleted: false, createTime: Date(), updateTime: Date()))
        _ = try await dao.save(TbGroup(id: nil, name: "Child", parentId: parent.id, isDeleted: false, createTime: Date(), updateTime: Date()))

        let children = try await dao.fetchChildren(parentId: parent.id!)
        #expect(children.count == 1)
        #expect(children[0].name == "Child")
    }

    @Test("Soft delete group")
    func softDelete() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = GroupDAO(database: db)

        let group = try await dao.save(TbGroup(id: nil, name: "Delete Me", parentId: nil, isDeleted: false, createTime: Date(), updateTime: Date()))
        try await dao.softDelete(id: group.id!)

        let all = try await dao.fetchAll()
        #expect(all.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd Packages/PTCore
swift test --filter "ReadingTimeDAOTests|TagDAOTests|GroupDAOTests" 2>&1
```

Expected: FAIL — DAO types not found.

- [ ] **Step 3: Write ReadingTimeDAO**

`Packages/PTCore/Sources/PTCore/Database/ReadingTimeDAO.swift`:
```swift
import Foundation
import GRDB

public struct ReadingTimeDAO: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    @discardableResult
    public func save(_ record: ReadingTime) async throws -> ReadingTime {
        try await database.writer.write { db in
            var mutable = record
            try mutable.save(db)
            return mutable
        }
    }

    public func totalReadingTime(bookId: Int64) async throws -> Int {
        try await database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(reading_time), 0) FROM tb_reading_time WHERE book_id = ?", arguments: [bookId]) ?? 0
        }
    }

    public func totalReadingTimeAllBooks() async throws -> Int {
        try await database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(reading_time), 0) FROM tb_reading_time") ?? 0
        }
    }

    public func fetchByDate(_ date: String) async throws -> [ReadingTime] {
        try await database.reader.read { db in
            try ReadingTime.filter(Column("date") == date).fetchAll(db)
        }
    }
}
```

- [ ] **Step 4: Write TagDAO**

`Packages/PTCore/Sources/PTCore/Database/TagDAO.swift`:
```swift
import Foundation
import GRDB

public struct TagDAO: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    @discardableResult
    public func save(_ tag: Tag) async throws -> Tag {
        try await database.writer.write { db in
            var mutable = tag
            try mutable.save(db)
            return mutable
        }
    }

    public func fetchAll() async throws -> [Tag] {
        try await database.reader.read { db in
            try Tag.fetchAll(db)
        }
    }

    public func delete(id: Int64) async throws {
        try await database.writer.write { db in
            _ = try Tag.deleteOne(db, key: id)
            // Also remove all book-tag relations
            try db.execute(sql: "DELETE FROM tb_book_tags WHERE tag_id = ?", arguments: [id])
        }
    }

    public func attachTag(tagId: Int64, toBookId bookId: Int64) async throws {
        try await database.writer.write { db in
            var relation = BookTag(id: nil, bookId: bookId, tagId: tagId)
            try relation.insert(db)
        }
    }

    public func detachTag(tagId: Int64, fromBookId bookId: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM tb_book_tags WHERE book_id = ? AND tag_id = ?",
                arguments: [bookId, tagId]
            )
        }
    }

    public func fetchTagIds(forBookId bookId: Int64) async throws -> [Int64] {
        try await database.reader.read { db in
            try Int64.fetchAll(db, sql: "SELECT tag_id FROM tb_book_tags WHERE book_id = ?", arguments: [bookId])
        }
    }
}
```

- [ ] **Step 5: Write GroupDAO**

`Packages/PTCore/Sources/PTCore/Database/GroupDAO.swift`:
```swift
import Foundation
import GRDB

public struct GroupDAO: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    @discardableResult
    public func save(_ group: TbGroup) async throws -> TbGroup {
        try await database.writer.write { db in
            var mutable = group
            try mutable.save(db)
            return mutable
        }
    }

    public func fetchAll() async throws -> [TbGroup] {
        try await database.reader.read { db in
            try TbGroup.filter(Column("is_deleted") == false).fetchAll(db)
        }
    }

    public func fetchChildren(parentId: Int64) async throws -> [TbGroup] {
        try await database.reader.read { db in
            try TbGroup
                .filter(Column("parent_id") == parentId)
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
        }
    }

    public func softDelete(id: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE tb_groups SET is_deleted = 1, update_time = ? WHERE id = ?",
                arguments: [Date().formatted(.iso8601), id]
            )
        }
    }
}
```

- [ ] **Step 6: Run all tests to verify they pass**

```bash
cd Packages/PTCore
swift test 2>&1
```

Expected: ALL tests PASS (BookTests + BookNoteTests + RemainingModelsTests + AppDatabaseTests + BookDAOTests + BookNoteDAOTests + ReadingTimeDAOTests + TagDAOTests + GroupDAOTests).

- [ ] **Step 7: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/Database/ Packages/PTCore/Tests/PTCoreTests/Database/
git commit -m "feat(PTCore): add ReadingTimeDAO, TagDAO, GroupDAO with full CRUD"
```

---

### Task 9: AppConfig and KeychainService

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Config/AppConfig.swift`
- Create: `Packages/PTCore/Sources/PTCore/Config/KeychainService.swift`
- Create: `Packages/PTCore/Tests/PTCoreTests/Config/AppConfigTests.swift`

- [ ] **Step 1: Write the failing test**

`Packages/PTCore/Tests/PTCoreTests/Config/AppConfigTests.swift`:
```swift
import Testing
@testable import PTCore

@Suite("AppConfig")
struct AppConfigTests {
    @Test("App Group suite name is correct")
    func appGroupSuiteName() {
        #expect(AppConfig.suiteName == "group.ai.papertok.paperreader")
    }

    @Test("Default values are set")
    func defaultValues() {
        // Verify defaults don't crash
        #expect(AppConfig.Defaults.defaultFontSize == 18.0)
        #expect(AppConfig.Defaults.defaultPageTurnMode == "swipe")
    }
}

@Suite("KeychainService")
struct KeychainServiceTests {
    @Test("Save and load from keychain")
    func saveAndLoad() throws {
        let testKey = "test_api_key_\(UUID().uuidString)"
        try KeychainService.save(key: testKey, value: "sk-test-123")

        let loaded = try KeychainService.load(key: testKey)
        #expect(loaded == "sk-test-123")

        // Cleanup
        try KeychainService.delete(key: testKey)
        let deleted = try KeychainService.load(key: testKey)
        #expect(deleted == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Packages/PTCore
swift test --filter "AppConfigTests|KeychainServiceTests" 2>&1
```

Expected: FAIL — types not found.

- [ ] **Step 3: Write AppConfig**

`Packages/PTCore/Sources/PTCore/Config/AppConfig.swift`:
```swift
import Foundation

/// App-wide configuration constants and UserDefaults wrapper
public enum AppConfig {
    public static let suiteName = "group.ai.papertok.paperreader"
    public static let bundleId = "ai.papertok.paperreader"
    public static let urlScheme = "paperreader"

    public static var groupDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Default values for configuration
    public enum Defaults {
        public static let defaultFontSize: Double = 18.0
        public static let defaultPageTurnMode = "swipe"
        public static let defaultThemeMode = "system"
        public static let maxAttachmentImages = 4
        public static let maxAttachmentTextFiles = 3
        public static let maxPromptLength = 20_000
    }
}
```

- [ ] **Step 4: Write KeychainService**

`Packages/PTCore/Sources/PTCore/Config/KeychainService.swift`:
```swift
import Foundation
import Security

/// Keychain wrapper for storing API keys securely
public enum KeychainService {
    private static let service = AppConfig.bundleId

    public static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    public static func load(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    public enum KeychainError: Error {
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case deleteFailed(OSStatus)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd Packages/PTCore
swift test --filter "AppConfigTests|KeychainServiceTests" 2>&1
```

Expected: All tests PASS. (Note: KeychainService tests may only pass on macOS or device, not in CI without keychain access. Mark as conditional if needed.)

- [ ] **Step 6: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/Config/ Packages/PTCore/Tests/PTCoreTests/Config/
git commit -m "feat(PTCore): add AppConfig and KeychainService"
```

---

### Task 10: DateFormatting Utility and Final Cleanup

**Files:**
- Create: `Packages/PTCore/Sources/PTCore/Utils/DateFormatting.swift`
- Modify: `Packages/PTCore/Sources/PTCore/PTCore.swift` (remove placeholder, add public exports)

- [ ] **Step 1: Write DateFormatting utility**

`Packages/PTCore/Sources/PTCore/Utils/DateFormatting.swift`:
```swift
import Foundation

/// Date formatting utilities shared across the app
public enum DateFormatting {
    /// ISO-8601 formatter matching Flutter's date string format
    public static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Date-only string (YYYY-MM-DD) for reading time records
    public static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Format seconds into human-readable duration (e.g., "2h 15m")
    public static func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
```

- [ ] **Step 2: Update PTCore.swift to re-export public API**

Replace `Packages/PTCore/Sources/PTCore/PTCore.swift`:
```swift
// PTCore — Foundation layer for PaperTok Reader
// Models, Database (GRDB), Configuration, Utilities

// Re-export GRDB so downstream packages don't need direct dependency
@_exported import GRDB
```

- [ ] **Step 3: Run full test suite**

```bash
cd Packages/PTCore
swift test 2>&1
```

Expected: ALL tests PASS.

- [ ] **Step 4: Commit**

```bash
git add Packages/PTCore/Sources/PTCore/
git commit -m "feat(PTCore): add DateFormatting utility, finalize public API exports"
```

---

## Phase 1 Completion Criteria

- [ ] Orphan branch `swift-native` created
- [ ] PTCore Swift Package builds on iOS 17 and macOS 14
- [ ] 6 models: Book, BookNote, ReadingTime, Tag, BookTag, TbGroup
- [ ] AppDatabase with GRDB migrations (schema v7)
- [ ] 5 DAOs: BookDAO, BookNoteDAO, ReadingTimeDAO, TagDAO, GroupDAO
- [ ] AppConfig + KeychainService
- [ ] DateFormatting utility
- [ ] All tests pass (`swift test` in Packages/PTCore)
- [ ] ~20+ unit tests covering models, database, DAOs, config
