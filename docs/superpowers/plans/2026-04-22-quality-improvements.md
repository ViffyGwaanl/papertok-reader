# 2026-04-22 Quality Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship three independent improvements in a single quality pass — fix the open-book animation flicker, unify settings sub-page theming, and add true in-place book reading on iOS via security-scoped bookmarks.

**Architecture:**
- Task 3 (flicker): change the fade trigger in EpubPlayer from a post-frame timer to WebView `onLoadEnd`. 1 file, surgical.
- Task 2 (theming): replace native `showModalBottomSheet`/`AlertDialog`/`SimpleDialog`/`SwitchListTile`/bare `ListTile` inside 4 named sub-pages with the project's `PTBottomSheet`/`PTPickerRow`/`PTDialog`/`SettingsTile`. Extract `storege.dart`'s inline `TabBar` into its own `SettingsSubpageScaffold`-hosted sub-page.
- Task 1 (in-place reading): new iOS `BookmarkChannel` MethodChannel (`pickInPlace`/`resolveBookmark`/`startAccess`/`stopAccess`), DB migration v7→v8 adding `bookmark_data BLOB` + `source_kind TEXT`, new `ScopedFileAccess` helper wrapping every file-read site, "Link from Files" entry in bookshelf import menu, share-sheet keeps copying, WebDAV sync skips in-place rows, delete never touches the external file.

**Tech Stack:** Flutter / Dart, Swift (iOS native), sqflite, `UIDocumentPickerViewController`, MethodChannel.

**Ship order:** Task A (flicker) → Task B (theming) → Task C (in-place). Each task = one commit. Task C lands behind a new menu entry so it is easy to roll back without disturbing imported books.

---

## Task A — Open-book animation flicker fix

**Files:**
- Modify: `lib/page/book_player/epub_player.dart` (two surgical edits around the `AnimationController` initialization and the `onLoadEnd` JS handler)

### Step A.1: Locate the controller and the onLoadEnd handler

- [ ] Open `lib/page/book_player/epub_player.dart`.
- [ ] Find the `AnimationController` field (around line 1188) — the one whose `Tween(begin: 1.0, end: 0.0)` drives the cover overlay opacity.
- [ ] Find the post-frame callback near lines 1195-1197 that calls `_animationController!.forward()` immediately on first frame.
- [ ] Find the WebView `onLoadEnd` / `onPageFinished` JS callback near lines 713-718.

### Step A.2: Change the AnimationController init to start at 1.0

- [ ] In the `initState` (or wherever the controller is constructed), set `value: 1.0` so the overlay starts fully visible and does NOT auto-advance.
- [ ] Delete or comment out the `WidgetsBinding.instance.addPostFrameCallback((_) { _animationController!.forward(); })` block so the fade no longer fires from a timer. Leave the controller itself alive.

### Step A.3: Fire `_animationController!.forward()` from `onLoadEnd`

- [ ] In the WebView `onLoadEnd` (or the message-channel handler that signals "book content rendered"), after any existing logic, add a guard to fire the fade once:

```dart
if (_animationController != null && !_coverFadeStarted) {
  _coverFadeStarted = true;
  _animationController!.forward();
}
```

- [ ] Add a `bool _coverFadeStarted = false;` field to the state class so the fade only fires once per open.

### Step A.4: Respect `openBookAnimation == false`

- [ ] Verify the existing code path where `Prefs().openBookAnimation == false` skips the overlay entirely. If our edits broke it (e.g. the controller is now never forwarded so the cover stays up indefinitely when animation is disabled), branch: when animation is disabled, set `value: 0.0` instead of `1.0`. This preserves the existing toggle semantics.

### Step A.5: Manual verification

- [ ] Build debug APK or run on simulator: `flutter run`.
- [ ] Tap a book on the bookshelf; confirm: during the Cupertino slide-in, NO rounded rectangle pops over the sliding page. The cover appears at the destination, stays visible while WebView loads, then smoothly fades.
- [ ] Toggle Settings → Appearance → "open book animation" OFF. Re-tap a book. Confirm the cover overlay never shows.
- [ ] Open a large EPUB (force slow `onLoadEnd`): the cover must hold until content is drawn, not time out.

### Step A.6: Commit

```bash
git add lib/page/book_player/epub_player.dart
git commit -m "fix(reader): defer open-book cover fade to WebView onLoadEnd

Previously the cover overlay faded on a 600ms post-frame timer, which
fired during the Cupertino page push, producing a 'flashing rounded
rectangle' mid-transition. The fade now starts when the EPUB content
finishes rendering (onLoadEnd), so the cover holds through the whole
transition and only fades once the book is actually drawn."
```

---

## Task B — Settings sub-page theming consistency

**Shared conventions:**
- Use `PTBottomSheet.show` + `PTPickerRow` for single-choice pickers. Definition: `lib/widgets/common/pt_bottom_sheet.dart`.
- Use `PTDialog.show` with `content` + `actions: [PTDialogAction(...)]` for confirm/text-input dialogs. Definition: `lib/widgets/common/pt_dialog.dart`.
- Use `SettingsTile.simple` / `SettingsTile.navigation` / `SettingsTile.switchTile` for rows inside `settingsSections(...)`. Definition: `lib/widgets/settings/settings_tile.dart`.
- For any `SwitchListTile` that cannot be replaced (e.g. inside a custom dialog body), set `activeColor: ClaudePalette.accent(context)` so the switch matches the theme accent.
- Examples to copy from: `lib/page/settings_page/reading.dart`, `lib/page/settings_page/appearance.dart`, `lib/page/settings_page/ai_tools.dart:_pickApprovalPolicy` (44-86) (already correct).

### Step B.1: Convert `ai_image_analysis.dart` pickers

**File:** `lib/page/settings_page/ai_image_analysis.dart`

- [ ] Convert `_pickProvider` (lines 43-78): replace the `showModalBottomSheet(builder: (_) => ListView(children: options.map(ListTile...)))` body with `PTBottomSheet.show(context, title: L10n.of(context).aiProvider, builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [for (final p in providers) PTPickerRow<String>(value: p.id, groupValue: currentId, title: p.name, leading: Icons.extension_outlined, onChanged: (v) { Navigator.pop(ctx); /* setState+persist */ })]))`.
- [ ] Convert `_pickImageOpenMode` (lines 80-110): replace `showDialog(builder: (_) => SimpleDialog(...RadioListTile))` with the same `PTBottomSheet.show` + `PTPickerRow<ImageOpenMode>` shape.
- [ ] Convert `_pickModel` (lines 199-342): outer `showModalBottomSheet` body → `PTBottomSheet.show` + `PTPickerRow<String>`. The inner `AlertDialog` for custom model name (around line 265-291) → `PTDialog.show(context, title: ..., content: TextField(...), actions: [PTDialogAction(label: L10n.of(context).commonCancel, onPressed: ...), PTDialogAction(label: L10n.of(context).commonOk, onPressed: ...)])`.
- [ ] Convert `_editPrompt` (lines 119-185): `AlertDialog` → `PTDialog.show`.
- [ ] Preserve all `setState(() {}) ` / `Prefs()....=` writes.
- [ ] Test: tap each picker/dialog, confirm the warm cream/dark background and 12-radius style — matches `reading.dart`.

### Step B.2: Convert `ai_tools.dart` pickers

**File:** `lib/page/settings_page/ai_tools.dart`

- [ ] `_editShortcutsCallbackTimeoutSec` (151-228): raw `showModalBottomSheet` + `Padding`+`Column` → `PTBottomSheet.show(context, title: ..., subtitle: ..., builder: (ctx) => ...)`. Keep the number-input widget as-is; just move it into the `PTBottomSheet` builder.
- [ ] `_editShortcutsSendMessageTimeoutSec` (230-307): same conversion as above.
- [ ] `_pickShortcutsSendMessagePresentation` (316-359): raw `showModalBottomSheet` + `ListView` of `ListTile` → `PTBottomSheet.show` + `PTPickerRow<...>`.
- [ ] `_pickShortcutsWaitMode` (370-446): same conversion as above.
- [ ] Leave `_pickApprovalPolicy` (44-86) untouched — already correct.

### Step B.3: Convert `sync.dart`

**File:** `lib/page/settings_page/sync.dart`

- [ ] `_showDataDialog` (144-153): `SimpleDialog` → `PTDialog.show`. Keep the same action buttons but render them as `PTDialogAction`.
- [ ] The `SwitchListTile` rows inside the export/import dialogs (175-211, 648-668): these live inside a `PTDialog` body, so replacing them wholesale is overkill. Minimum fix: add `activeColor: ClaudePalette.accent(context)` + `activeTrackColor: ClaudePalette.accent(context).withValues(alpha: 0.4)` so the switch colour matches the theme.
- [ ] Preserve all `mounted` guards (around lines 116, 297).
- [ ] Do NOT restructure `SmartDialog.show(...)` calls.

### Step B.4: Convert `storege.dart` ListTiles to SettingsTile

**File:** `lib/page/settings_page/storege.dart`

- [ ] "Storage Info" section (174-228): the `CustomSettingsTile(child: Column(children: [ListTile, ListTile, ...]))` → a list of `SettingsTile.simple(title: ..., trailing: Text(...))` entries. Each row's padding/typography will then match its neighbours.
- [ ] "Custom storage location" section (238-330): convert the path rows to `SettingsTile.simple`. Keep the action-button `Padding(...AnxButton...)` block wrapped in a `CustomSettingsTile` (it's genuinely custom).

### Step B.5: Extract the TabBar from `storege.dart` into its own sub-page

**Files:**
- Create: `lib/page/settings_page/storage_data_files_page.dart`
- Modify: `lib/page/settings_page/storege.dart`

- [ ] Create `storage_data_files_page.dart` as a `ConsumerStatefulWidget` with `SingleTickerProviderStateMixin`. It owns `late TabController _tabController` (length 3) and disposes it in `dispose`. Its `build` returns `SettingsSubpageScaffold(title: L10n.of(context).settingsStorageDataFilesTitle /* or reuse existing key */, child: Column(children: [TabBar(..., labelColor: ClaudePalette.fg(context), indicatorColor: ClaudePalette.accent(context), unselectedLabelColor: ClaudePalette.secondary(context), tabs: [...]), Expanded(child: TabBarView(controller: _tabController, children: [DataFilesDetailTab(...), ...]))]))`.
- [ ] Import/move `DataFilesDetailTab` (existing 427-504 in `storege.dart`) into the new file or keep its definition in place and import it.
- [ ] In `storege.dart`: remove the inline `TabBar`/`TabBarView` block (335-422). Remove `with SingleTickerProviderStateMixin` from `_StorageSettingsState`. Remove the `TabController` field + init + dispose.
- [ ] In its place, add a single `SettingsTile.navigation(title: L10n.of(context).settingsStorageDataFilesTitle, leading: Icons.folder_outlined, onTap: () => Navigator.push(context, CupertinoPageRoute(builder: (_) => const StorageDataFilesPage())))`.

### Step B.6: Manual verification + commit

- [ ] Launch the app, navigate Settings → each of the 5 sub-pages. Tap every picker/dialog/switch. Confirm backgrounds, card corners, typography match `reading.dart`.

```bash
git add lib/page/settings_page/ai_image_analysis.dart \
        lib/page/settings_page/ai_tools.dart \
        lib/page/settings_page/sync.dart \
        lib/page/settings_page/storege.dart \
        lib/page/settings_page/storage_data_files_page.dart
git commit -m "refactor(settings): unify sub-page theming

Replace native Material pickers/dialogs/switches inside ai_image_analysis,
ai_tools, sync, and storege with the project's PTBottomSheet / PTPickerRow
/ PTDialog / SettingsTile widgets so sub-pages visually match the rest of
settings. Extract storage data-files TabBar into its own sub-page."
```

---

## Task C — In-place book reading on iOS (security-scoped bookmarks)

Decomposed into 10 sub-tasks, each independently testable.

### Step C.1: Create the iOS `BookmarkChannel.swift` plugin

**Files:**
- Create: `ios/Runner/BookmarkChannel.swift`
- Modify: `ios/Runner/AppDelegate.swift` (register the channel)

- [ ] Create `ios/Runner/BookmarkChannel.swift`:

```swift
import Flutter
import UIKit
import UniformTypeIdentifiers

/// MethodChannel bridge for iOS security-scoped bookmarks.
/// Channel name: `ai.papertok.paperreader/bookmark`.
final class BookmarkChannel: NSObject, UIDocumentPickerDelegate {
  private static let channelName = "ai.papertok.paperreader/bookmark"

  private var channel: FlutterMethodChannel?
  private weak var hostController: UIViewController?
  private var pendingPickResult: FlutterResult?

  /// Active scope handles keyed by opaque token.
  /// - Note: each URL is held in a strong reference so ARC doesn't drop it;
  ///   calling `stopAccessingSecurityScopedResource` relies on the same URL
  ///   instance that `startAccessingSecurityScopedResource` was called on.
  private var activeScopes: [String: URL] = [:]

  func register(with controller: FlutterViewController) {
    self.hostController = controller
    let ch = FlutterMethodChannel(
      name: BookmarkChannel.channelName,
      binaryMessenger: controller.binaryMessenger
    )
    self.channel = ch
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickInPlace":
      pickInPlace(args: call.arguments as? [String: Any] ?? [:], result: result)
    case "resolveBookmark":
      resolveBookmark(args: call.arguments as? [String: Any] ?? [:], result: result)
    case "startAccess":
      startAccess(args: call.arguments as? [String: Any] ?? [:], result: result)
    case "stopAccess":
      stopAccess(args: call.arguments as? [String: Any] ?? [:], result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - pickInPlace

  private func pickInPlace(args: [String: Any], result: @escaping FlutterResult) {
    guard pendingPickResult == nil, let host = hostController else {
      result(FlutterError(code: "busy", message: "Picker already active", details: nil))
      return
    }
    let allowedExt = (args["allowedExt"] as? [String]) ?? ["pdf", "epub"]
    var types: [UTType] = []
    for e in allowedExt {
      if let t = UTType(filenameExtension: e) { types.append(t) }
    }
    if types.isEmpty {
      types = [UTType.pdf, UTType.epub]
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pendingPickResult = result
    host.present(picker, animated: true, completion: nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController,
                      didPickDocumentsAt urls: [URL]) {
    let r = pendingPickResult
    pendingPickResult = nil
    guard let url = urls.first else {
      r?(nil)
      return
    }
    let started = url.startAccessingSecurityScopedResource()
    defer { if started { url.stopAccessingSecurityScopedResource() } }
    do {
      let blob = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      var size: Int64 = 0
      var mtime: Double = 0
      if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
        size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if let d = attrs[.modificationDate] as? Date {
          mtime = d.timeIntervalSince1970
        }
      }
      r?([
        "bookmark": blob.base64EncodedString(),
        "name": url.lastPathComponent,
        "size": size,
        "mtime": mtime,
        "ext": url.pathExtension.lowercased(),
        "displayPath": url.path,
      ])
    } catch {
      r?(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let r = pendingPickResult
    pendingPickResult = nil
    r?(nil)
  }

  // MARK: - resolveBookmark

  private func resolveBookmark(args: [String: Any], result: @escaping FlutterResult) {
    guard let blobB64 = args["bookmark"] as? String,
          let blob = Data(base64Encoded: blobB64) else {
      result(FlutterError(code: "invalid_args", message: "bookmark missing", details: nil))
      return
    }
    var isStale: Bool = false
    do {
      let url = try URL(resolvingBookmarkData: blob, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
      var out: [String: Any] = [
        "path": url.path,
        "isStale": isStale,
      ]
      if isStale {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
          out["freshBookmark"] = fresh.base64EncodedString()
        }
      }
      result(out)
    } catch {
      result([
        "path": NSNull(),
        "isStale": false,
        "error": error.localizedDescription,
      ])
    }
  }

  // MARK: - startAccess / stopAccess

  private func startAccess(args: [String: Any], result: @escaping FlutterResult) {
    guard let blobB64 = args["bookmark"] as? String,
          let blob = Data(base64Encoded: blobB64) else {
      result(FlutterError(code: "invalid_args", message: "bookmark missing", details: nil))
      return
    }
    var isStale: Bool = false
    do {
      let url = try URL(resolvingBookmarkData: blob, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
      let ok = url.startAccessingSecurityScopedResource()
      if !ok {
        result(FlutterError(code: "access_denied", message: "startAccessingSecurityScopedResource failed", details: nil))
        return
      }
      let token = UUID().uuidString
      activeScopes[token] = url
      var out: [String: Any] = ["token": token, "path": url.path, "isStale": isStale]
      if isStale {
        if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
          out["freshBookmark"] = fresh.base64EncodedString()
        }
      }
      result(out)
    } catch {
      result(FlutterError(code: "resolve_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func stopAccess(args: [String: Any], result: @escaping FlutterResult) {
    guard let token = args["token"] as? String,
          let url = activeScopes[token] else {
      result(nil)
      return
    }
    url.stopAccessingSecurityScopedResource()
    activeScopes.removeValue(forKey: token)
    result(nil)
  }
}
```

- [ ] Modify `ios/Runner/AppDelegate.swift` — add `private let bookmarkChannel = BookmarkChannel()` and call `bookmarkChannel.register(with: controller)` next to the existing registrations:

```swift
if let controller = window?.rootViewController as? FlutterViewController {
  remindersChannel.register(with: controller)
  calendarEventKitChannel.register(with: controller)
  PapertokPendingAskBridge.register(with: controller)
  bookmarkChannel.register(with: controller)  // NEW
}
```

- [ ] Add `BookmarkChannel.swift` to the Xcode project (the file in `ios/Runner/`; Xcode auto-detects via file-system sync on next build, or add manually through `project.pbxproj`).

### Step C.2: Create the Dart `BookmarkChannel` wrapper

**File:**
- Create: `lib/service/bookmark/bookmark_channel.dart`

- [ ] Create the file with this content:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Dart-side wrapper over the iOS `ai.papertok.paperreader/bookmark` channel.
class BookmarkChannel {
  BookmarkChannel._internal();

  static final BookmarkChannel instance = BookmarkChannel._internal();

  static const _channel =
      MethodChannel('ai.papertok.paperreader/bookmark');

  /// Presents the iOS document picker in non-copy mode. Returns null on cancel.
  Future<PickedBookmark?> pickInPlace({
    List<String> allowedExt = const ['pdf', 'epub'],
  }) async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('pickInPlace', {
      'allowedExt': allowedExt,
    });
    if (result == null) return null;
    final m = Map<String, Object?>.from(result);
    return PickedBookmark.fromMap(m);
  }

  /// Resolves a bookmark blob to its current path (without starting scope).
  Future<ResolvedBookmark> resolveBookmark(Uint8List blob) async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('resolveBookmark', {
      'bookmark': base64Encode(blob),
    });
    return ResolvedBookmark.fromMap(Map<String, Object?>.from(result!));
  }

  /// Starts security-scoped access. Returns a token that must be passed to
  /// [stopAccess] when the caller is done reading the file.
  Future<ScopedAccess> startAccess(Uint8List blob) async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('startAccess', {
      'bookmark': base64Encode(blob),
    });
    return ScopedAccess.fromMap(Map<String, Object?>.from(result!));
  }

  Future<void> stopAccess(String token) async {
    await _channel.invokeMethod<void>('stopAccess', {'token': token});
  }
}

class PickedBookmark {
  final Uint8List bookmark;
  final String name;
  final int size;
  final double mtime;
  final String ext;
  final String displayPath;

  const PickedBookmark({
    required this.bookmark,
    required this.name,
    required this.size,
    required this.mtime,
    required this.ext,
    required this.displayPath,
  });

  factory PickedBookmark.fromMap(Map<String, Object?> m) {
    return PickedBookmark(
      bookmark: base64Decode(m['bookmark'] as String),
      name: m['name'] as String? ?? '',
      size: (m['size'] as num?)?.toInt() ?? 0,
      mtime: (m['mtime'] as num?)?.toDouble() ?? 0,
      ext: m['ext'] as String? ?? '',
      displayPath: m['displayPath'] as String? ?? '',
    );
  }
}

class ResolvedBookmark {
  final String? path;
  final bool isStale;
  final Uint8List? freshBookmark;
  final String? error;

  const ResolvedBookmark({
    required this.path,
    required this.isStale,
    this.freshBookmark,
    this.error,
  });

  factory ResolvedBookmark.fromMap(Map<String, Object?> m) {
    final fresh = m['freshBookmark'] as String?;
    return ResolvedBookmark(
      path: m['path'] as String?,
      isStale: m['isStale'] as bool? ?? false,
      freshBookmark: fresh != null ? base64Decode(fresh) : null,
      error: m['error'] as String?,
    );
  }
}

class ScopedAccess {
  final String token;
  final String path;
  final bool isStale;
  final Uint8List? freshBookmark;

  const ScopedAccess({
    required this.token,
    required this.path,
    required this.isStale,
    this.freshBookmark,
  });

  factory ScopedAccess.fromMap(Map<String, Object?> m) {
    final fresh = m['freshBookmark'] as String?;
    return ScopedAccess(
      token: m['token'] as String,
      path: m['path'] as String,
      isStale: m['isStale'] as bool? ?? false,
      freshBookmark: fresh != null ? base64Decode(fresh) : null,
    );
  }
}
```

### Step C.3: DB schema migration v7 → v8

**File:**
- Modify: `lib/dao/database.dart`

- [ ] Bump `const int currentDbVersion = 7;` to `= 8;`.
- [ ] Update `createBookSQL` to include the new columns at the bottom:

```sql
CREATE TABLE tb_books (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT,
  cover_path TEXT,
  file_path TEXT,
  last_read_position TEXT,
  reading_percentage REAL,
  author TEXT,
  is_deleted INTEGER,
  description TEXT,
  create_time TEXT,
  update_time TEXT,
  rating REAL,
  group_id INTEGER,
  file_md5 TEXT,
  bookmark_data BLOB,
  source_kind TEXT DEFAULT 'imported'
)
```

- [ ] In `onUpgradeDatabase` add `case 7:` before the closing brace of the switch:

```dart
case7:
case 7:
  await db.execute("ALTER TABLE tb_books ADD COLUMN bookmark_data BLOB");
  await db.execute("ALTER TABLE tb_books ADD COLUMN source_kind TEXT DEFAULT 'imported'");
  await db.execute("UPDATE tb_books SET source_kind = 'imported' WHERE source_kind IS NULL");
```

- [ ] Add a `continue case7;` at the end of `case 6:` (right before the ALTER TABLE that currently ends that branch) so fresh installs fall through correctly. Verify the fall-through pattern used elsewhere (`continue case1;` etc.) — match it.

### Step C.4: Update `Book` model with `bookmarkData` and `sourceKind`

**File:**
- Modify: `lib/models/book.dart`

- [ ] Add two new fields:

```dart
Uint8List? bookmarkData;
String sourceKind; // 'imported' | 'inplace'
```

- [ ] Add `'import 'dart:typed_data';'` at the top if not present.
- [ ] Update the constructor, `toMap`, `fromDb`, `copyWith`, and `Book.mock()` accordingly. Defaults: `bookmarkData: null`, `sourceKind: 'imported'`.
- [ ] `toMap` additions:

```dart
'bookmark_data': bookmarkData,
'source_kind': sourceKind,
```

- [ ] `fromDb` additions:

```dart
bookmarkData: map['bookmark_data'] as Uint8List?,
sourceKind: map['source_kind'] as String? ?? 'imported',
```

- [ ] `fileFullPath` MUST remain usable for copied books. Add a helper `bool get isInPlace => sourceKind == 'inplace';` — consumers branch on this rather than touching `filePath` directly for in-place books.

### Step C.5: Create `ScopedFileAccess` helper

**File:**
- Create: `lib/service/bookmark/scoped_file_access.dart`

- [ ] Create:

```dart
import 'dart:io';

import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/service/bookmark/bookmark_channel.dart';
import 'package:papertok_reader/dao/book.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:papertok_reader/utils/toast/common.dart';

/// One-stop access helper for book file bytes.
///
/// - For legacy ("imported") books it returns a bare [File] backed by
///   [Book.fileFullPath].
/// - For "inplace" books it resolves the security-scoped bookmark, calls
///   `startAccessingSecurityScopedResource`, persists any refreshed
///   bookmark back to the DB, and releases the scope on [dispose].
class ScopedFileAccess {
  ScopedFileAccess._(this.path, this.book, this._token);

  final String path;
  final Book book;
  final String? _token;

  /// The resolved file. Callers should NOT retain it past [dispose].
  File get file => File(path);

  /// Releases the security-scoped access (no-op for imported books).
  Future<void> dispose() async {
    if (_token != null) {
      try {
        await BookmarkChannel.instance.stopAccess(_token);
      } catch (e) {
        AnxLog.warning('ScopedFileAccess.dispose: $e');
      }
    }
  }

  static Future<ScopedFileAccess> open(Book book) async {
    if (book.sourceKind != 'inplace' || book.bookmarkData == null) {
      return ScopedFileAccess._(book.fileFullPath, book, null);
    }
    final scope = await BookmarkChannel.instance.startAccess(book.bookmarkData!);
    // Persist a refreshed bookmark if the OS said the old one was stale.
    if (scope.isStale && scope.freshBookmark != null) {
      book.bookmarkData = scope.freshBookmark;
      await bookDao.updateBook(book);
    }
    return ScopedFileAccess._(scope.path, book, scope.token);
  }

  /// Convenience: open, run [body] inside the scope, always dispose.
  static Future<T> run<T>(Book book, Future<T> Function(File file) body) async {
    final handle = await open(book);
    try {
      return await body(handle.file);
    } finally {
      await handle.dispose();
    }
  }
}
```

- [ ] Add a unit test `test/service/bookmark/scoped_file_access_test.dart` that constructs an "imported" `Book` and verifies `open` returns the legacy path with no channel call. (Mock `BookmarkChannel.instance` via a testable override — or make the channel field public-settable-in-tests.)

### Step C.6: Add "Link from Files" entry to bookshelf import menu

**Files:**
- Modify: `lib/page/home_page/bookshelf_page.dart`
- Modify: `lib/service/book.dart` (add `importInPlaceBook`)

- [ ] In `lib/service/book.dart`, add:

```dart
Future<void> importInPlaceBook(PickedBookmark picked, WidgetRef ref) async {
  // Start scope long enough to extract metadata, MD5, and cover.
  final scope = await BookmarkChannel.instance.startAccess(picked.bookmark);
  try {
    final file = File(scope.path);
    final md5 = await MD5Service.calculateFileMd5(file.path);
    final existing = md5 == null ? null : await bookDao.getBookByMd5(md5);
    if (existing != null && !existing.isDeleted) {
      AnxToast.show(L10n.of(navigatorKey.currentContext!).bookAlreadyImported);
      return;
    }
    // Metadata extraction + cover save — pass `copyFile: false` signal so
    // the existing saveBook path skips the file.copy step. (Implementation
    // detail: add a new private `_saveBookInPlace` that parallels saveBook
    // but writes bookmark_data+source_kind='inplace' and leaves file_path
    // as the original display path for debug only.)
    await _saveBookInPlace(file: file, picked: picked, md5: md5);
  } finally {
    await BookmarkChannel.instance.stopAccess(scope.token);
  }
  ref.read(bookListProvider.notifier).refresh();
}
```

- [ ] Implement `_saveBookInPlace` alongside `saveBook` (around line 529). It:
  - Calls `getBookMetadata`-equivalent logic against the scoped file to extract title/author/cover.
  - Persists the cover under the existing `cover/<name>` convention (cover is small — we copy it locally).
  - Writes a Book row with `sourceKind: 'inplace'`, `bookmarkData: picked.bookmark`, `filePath: picked.displayPath` (for UI debug only; never used for reads).
- [ ] In `lib/page/home_page/bookshelf_page.dart`, locate the import entry (the FAB / menu item that calls `_importBook`). Add a second item "Link from Files" (or existing l10n key `bookshelfLinkFromFiles`; add if missing):

```dart
if (Platform.isIOS) ...[
  PTPickerRow(
    title: L10n.of(context).bookshelfLinkFromFiles,
    leading: Icons.folder_shared_outlined,
    onChanged: (_) async {
      Navigator.pop(ctx);
      final picked = await BookmarkChannel.instance.pickInPlace();
      if (picked == null) return;
      await importInPlaceBook(picked, ref);
    },
  ),
]
```

- [ ] Add l10n key `bookshelfLinkFromFiles` to `app_zh.arb` ("从 Files 链接") + `app_en.arb` ("Link from Files") + all other 14 locale files with English fallback. Regenerate via `flutter gen-l10n`.

### Step C.7: Wrap reader path with `ScopedFileAccess`

**Files:**
- Modify: `lib/page/book_player/epub_player.dart`
- Modify: `lib/service/book_player/book_player_server.dart`

- [ ] In `EpubPlayer`'s state class, add:

```dart
ScopedFileAccess? _scopedAccess;
```

- [ ] In `initState`, schedule the open:

```dart
ScopedFileAccess.open(widget.book).then((h) {
  if (!mounted) { h.dispose(); return; }
  setState(() => _scopedAccess = h);
});
```

- [ ] In `dispose`, release it:

```dart
_scopedAccess?.dispose();
```

- [ ] Replace all places where `widget.book.fileFullPath` is fed to the local HTTP server with `_scopedAccess!.path` (guard against null; show a small loading spinner while `_scopedAccess == null`).
- [ ] In `book_player_server.dart`, modify the `_isAllowed` (or equivalent) check so it additionally accepts any path registered via `ScopedFileAccess`. Easiest: expose a static `Set<String> _allowedScopedPaths` on `ScopedFileAccess` (insert on `open`, remove on `dispose`), and consult it from `_isAllowed`.

### Step C.8: Wrap other file-access sites

**Files:**
- Modify: `lib/service/md5_service.dart` (callers — `calculateFileMd5` already takes a path; OK)
- Modify: `lib/widgets/bookshelf/book_bottom_sheet.dart` (share/export — use `ScopedFileAccess.run`)
- Modify: `lib/service/book_content_search_repository.dart` (wrap opens)
- Modify: `lib/service/ai/headless_book/ai_headless_reader_bridge.dart` (wrap opens)

- [ ] Grep for all usages of `book.fileFullPath` and audit each. Rule:
  - If the usage only displays the path → safe, leave alone.
  - If the usage reads bytes → wrap with `ScopedFileAccess.run(book, (file) async { ... })`.
- [ ] Each converted callsite keeps its existing logic inside the `run` callback; only the file-open line changes.

### Step C.9: WebDAV sync + delete integration

**Files:**
- Modify: `lib/providers/sync.dart`
- Modify: `lib/service/book.dart` (delete path)

- [ ] In `sync.dart`, wherever the provider iterates books to upload/compare, skip rows with `book.sourceKind == 'inplace'`. Count skipped rows and expose via a getter so the sync page can show a one-time toast: "N book(s) linked from Files are not synced."
- [ ] In the delete path (find `bookDao.softDeleteBook` / `deleteBook` — usually in `lib/service/book.dart` around `deleteBook`), branch: for `inplace` books, just mark `isDeleted = true` in the DB — NEVER call `File(fileFullPath).delete()`. Update the existing delete-confirm dialog to use a different message for `inplace`:

```dart
book.isInPlace
  ? L10n.of(context).bookDeleteInPlaceConfirm  // "Remove from library? (file will not be deleted)"
  : L10n.of(context).bookDeleteConfirm
```

- [ ] Add `bookDeleteInPlaceConfirm` l10n key to all 16 arb files.

### Step C.10: Relink UX for stale / missing files

**Files:**
- Modify: `lib/widgets/bookshelf/book_item.dart` (cover badge)
- Modify: `lib/service/book.dart` (add `relinkBook(book) -> Future<bool>`)

- [ ] When `ScopedFileAccess.open` throws or `resolveBookmark` returns `path == null`, mark the book row with a flag (reuse `description` or add a transient provider — simplest: a `Set<int> _brokenInPlaceIds` in memory maintained by the reader-open error handler).
- [ ] In `BookItem` (the bookshelf cover widget), if the id is in the broken set, overlay a small "⟲ Relink" chip on the cover.
- [ ] Tapping the chip calls `relinkBook(book)`: presents the picker via `BookmarkChannel.instance.pickInPlace()`, updates `book.bookmarkData = picked.bookmark` and `book.filePath = picked.displayPath`, clears the broken flag, refreshes the list.

### Step C.11: Commit Task C

- [ ] Stage + commit:

```bash
git add ios/Runner/BookmarkChannel.swift \
        ios/Runner/AppDelegate.swift \
        lib/service/bookmark/ \
        lib/dao/database.dart \
        lib/models/book.dart \
        lib/page/home_page/bookshelf_page.dart \
        lib/service/book.dart \
        lib/page/book_player/epub_player.dart \
        lib/service/book_player/book_player_server.dart \
        lib/widgets/bookshelf/book_bottom_sheet.dart \
        lib/service/book_content_search_repository.dart \
        lib/service/ai/headless_book/ai_headless_reader_bridge.dart \
        lib/providers/sync.dart \
        lib/widgets/bookshelf/book_item.dart \
        lib/l10n/ \
        test/service/bookmark/
git commit -m "feat(ios): in-place book reading via security-scoped bookmarks

Adds a 'Link from Files' import entry that avoids copying the book into
the app sandbox. Books picked via UIDocumentPicker(asCopy:false) are
persisted as bookmark blobs in tb_books (new columns bookmark_data BLOB,
source_kind TEXT default 'imported'). A ScopedFileAccess helper wraps
every read site (reader, HTTP server, MD5, share, search, AI headless
reader) to call startAccessingSecurityScopedResource. WebDAV sync skips
'inplace' rows; delete removes only the DB row, never the external
file. Android unchanged (continues to copy). Share-sheet imports also
continue to copy (App Group files have no scope)."
```

### Step C.12: Manual verification smoke

- [ ] iOS simulator or device: Settings → iCloud Drive enabled with an EPUB placed there.
- [ ] Bookshelf → "Link from Files" → pick the EPUB. Confirm: **no** file appears under `Application Support/file/`. Cover is generated (small cover file is OK to copy). DB has a row with `source_kind='inplace'` and `bookmark_data` non-null.
- [ ] Open the book. Confirm it reads fine.
- [ ] Kill the app. Reopen. Tap the book. Confirm it still reads (bookmark persistence).
- [ ] Enable WebDAV sync. Confirm in-place row is skipped and toast shows.
- [ ] Swipe-delete the book. Confirm the confirm text says "file will not be deleted" and the original file in iCloud Drive is untouched.
- [ ] Move the source file in the Files app to a new folder. Tap the book → expect a "Relink" chip; tap → picker → select new location → reads fine again.

---

## Self-review checklist (run before handoff)

- [ ] Spec Task 1 — all 10 points (iOS channel, schema, model, helper, reader wrap, HTTP server, share-sheet unchanged, sync skip, delete safe, relink) are represented in C.1–C.10 above.
- [ ] Spec Task 2 — all 5 named pages covered in B.1–B.5; `storege.dart` TabBar extraction explicit.
- [ ] Spec Task 3 — covered in A.1–A.6.
- [ ] No "TODO", no "similar to Task N".
- [ ] Type/field names consistent: `bookmarkData`, `sourceKind`, `'inplace'`/`'imported'`, `ScopedFileAccess.open/run/dispose`, channel `ai.papertok.paperreader/bookmark`, methods `pickInPlace`/`resolveBookmark`/`startAccess`/`stopAccess`.
- [ ] Every code block compiles in principle (types imported, classes exist or are created in the same task).
