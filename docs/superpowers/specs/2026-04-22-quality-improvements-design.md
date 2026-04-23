# 2026-04-22 Quality Improvements — Design

Three independent improvements bundled into one quality pass:

1. **In-place book reading on iOS** (no-copy via security-scoped bookmarks).
2. **Settings sub-page theming consistency** (replace raw Material widgets with project's PT* widgets).
3. **Open-book animation flicker fix** (defer the cover overlay's fade until WebView content is loaded).

Each task is independently shippable. They will be implemented as separate branches/commits so any one can be rolled back without affecting the others.

---

## Task 1 — In-place book reading on iOS

### Goal

Allow the user to import a book from the iOS Files app **without copying it into the app sandbox**. The book record stores a security-scoped bookmark blob; whenever the reader needs the file, it resolves the bookmark, calls `startAccessingSecurityScopedResource`, reads, and calls `stopAccessingSecurityScopedResource`. Books picked from outside iCloud Drive / Files (e.g. share-sheet, network downloads, paper PDFs from the PaperTok API) continue to use the existing copy-on-import flow.

### Non-goals

- Android in-place reading (different API — Storage Access Framework). Out of scope; Android continues to copy.
- Migrating already-imported (copied) books to in-place. The new column defaults to `'imported'` (legacy); only newly picked books opt into `'inplace'`.
- Cloud sync (WebDAV) of in-place books — they have no sandbox file to upload. The sync code skips them; the user gets a one-time toast explaining why.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Dart layer                                                 │
│                                                             │
│  bookshelf_page.dart ──► BookmarkChannel.pickInPlace()      │
│                            (MethodChannel)                  │
│                                  │                          │
│                                  ▼                          │
│  service/book.dart  ─►  importInPlaceBook(bookmark, meta)   │
│                          - skips file.copy(...)             │
│                          - stores bookmark+meta in tb_books │
│                          - generates cover (using a scoped  │
│                            access window)                   │
│                                                             │
│  ScopedFileAccess (new helper)                              │
│    .open(book) → Future<ScopedHandle>                       │
│      - if source_kind == 'imported': returns plain path     │
│      - if source_kind == 'inplace':                         │
│          1. resolveBookmark(blob) via channel               │
│          2. startAccess(blob)                               │
│          3. on stale: persist refreshed bookmark            │
│          4. caller `await handle.use(...)` then dispose →   │
│             stopAccess                                      │
│                                                             │
│  Reader / HTTP server / MD5 / metadata extraction call      │
│  ScopedFileAccess.open(book) instead of File(fileFullPath). │
└─────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────┐
│  iOS native (ios/Runner/BookmarkChannel.swift)              │
│                                                             │
│  pickInPlace(allowedTypes) →                                │
│    UIDocumentPickerViewController(forOpeningContentTypes:,  │
│                                    asCopy: false)           │
│    didPickDocumentsAt:                                      │
│      url.startAccessingSecurityScopedResource()             │
│      let blob = url.bookmarkData(options: [],...)           │
│      url.stopAccessingSecurityScopedResource()              │
│      return {bookmark: base64, name, size, mtime, ext, url} │
│                                                             │
│  resolveBookmark(blob) → {path, isStale, freshBookmark?}    │
│  startAccess(blob) → token                                  │
│  stopAccess(token)                                          │
└─────────────────────────────────────────────────────────────┘
```

### iOS plugin contract

New file: `ios/Runner/BookmarkChannel.swift` — registered from `AppDelegate.swift` as channel `ai.papertok.paperreader/bookmark`.

| Method | Args | Returns | Notes |
|---|---|---|---|
| `pickInPlace` | `{allowedExt: ["pdf","epub"]}` | `{bookmark: String (b64), name, size, mtime, ext, displayPath}` or `null` if cancelled | Presents `UIDocumentPickerViewController(forOpeningContentTypes:, asCopy:false)`. Wraps with `start/stopAccess` only long enough to compute the bookmark. |
| `resolveBookmark` | `{bookmark: String}` | `{path, isStale, freshBookmark?: String}` | If `isStale` true, the resolved URL is re-bookmarked and returned in `freshBookmark`. Caller must persist. |
| `startAccess` | `{bookmark: String}` | `{token: String}` | Resolves the bookmark, calls `startAccessingSecurityScopedResource`, stores the URL keyed by a fresh UUID `token`. |
| `stopAccess` | `{token: String}` | `null` | Looks up the URL by token, calls `stopAccessingSecurityScopedResource`, drops the token. |

iOS gotcha already noted by the agent: `.withSecurityScope` and `.minimalBookmark` are macOS-only. On iOS, plain `bookmarkData(options: [])` on a URL returned by the document picker already encodes the scope.

### Schema migration

Bump `currentDbVersion` from 7 → 8. Add a `case 7` to the upgrade switch:

```dart
await db.execute("ALTER TABLE tb_books ADD COLUMN bookmark_data BLOB");
await db.execute("ALTER TABLE tb_books ADD COLUMN source_kind TEXT DEFAULT 'imported'");
await db.execute("UPDATE tb_books SET source_kind = 'imported' WHERE source_kind IS NULL");
```

`Book` model gains `Uint8List? bookmarkData` and `String sourceKind` (default `'imported'`). `Book.fromDb` / `toMap` updated.

### Touchpoints

The "everything that reads `book.fileFullPath`" surface area is large. Each must be wrapped through `ScopedFileAccess`:

- `lib/page/book_player/epub_player.dart` — opens a `ScopedFileAccess` handle in `initState` and disposes it in `dispose()`. The handle's lifetime brackets the local HTTP server's serving window. `book_player_server.dart`'s `_isAllowed` check (currently restricting paths to the sandbox base dir) gains an additional allow rule: "path matches the absolute path of any currently-active scope handle." Reads otherwise stay byte-identical to today.
- `lib/service/md5_service.dart` — needs scoped access to compute MD5 of newly picked in-place books.
- `lib/service/book.dart` — `getBookMetadata`, cover generation, MD5.
- `lib/widgets/bookshelf/book_bottom_sheet.dart` — operations that read the file (open externally, share, delete).
- `lib/service/book_content_search_repository.dart` — content search reads file.
- `lib/service/ai/headless_book/ai_headless_reader_bridge.dart` — AI tools that ingest the book.
- Note import / export, kairos hint generation — anything that touches file bytes.

All of these gain a single helper:

```dart
final handle = await ScopedFileAccess.open(book);
try {
  // Use handle.path or handle.openRead()
} finally {
  await handle.dispose();
}
```

### Share-sheet, sync, delete

- **Share-sheet imports**: `lib/service/receive_file/share_safe_import.dart` continues to copy. Files arriving in the App Group container have no scoped URL to bookmark.
- **WebDAV sync** (`lib/providers/sync.dart`): when iterating books to upload, skip rows where `source_kind == 'inplace'`. Show a one-time toast on the sync page: "X book(s) are linked from Files and won't be synced."
- **Delete**: removes the DB row only; never touches the original file. Confirm dialog says "Remove from library (file will not be deleted)".

### Re-link prompt

If `resolveBookmark` returns `path == null` (file was moved/deleted), the bookshelf shows a "Relink" badge on the cover. Tapping it opens the picker; on success, the existing book row is updated with the new bookmark and `mtime`.

### Error handling

- Picker cancellation: `null` propagates as a no-op.
- `startAccess` failure: surface a toast "Cannot access file. Tap to relink." and mark the book as needing relink.
- Stale bookmarks: handled inline by `resolveBookmark` — the freshBookmark is persisted before any read.
- iCloud not-yet-downloaded files: iOS returns the URL but `startAccessingSecurityScopedResource` succeeds before bytes exist. Reads will fail with EOF; surface "File not downloaded yet — open it in Files first" toast.

### Testing

- Unit: `ScopedFileAccess` with a mocked `BookmarkChannel`.
- Manual smoke (TestFlight): import EPUB from iCloud Drive → close app → relaunch → re-open the book → verify no copy under `Application Support/`. Sync test: enable WebDAV, verify in-place books are skipped with the toast.

---

## Task 2 — Settings sub-page theming consistency

### Goal

The 5 named sub-pages (`ai.dart`, `ai_image_analysis.dart`, `ai_tools.dart`, `sync.dart`, `storege.dart`) visually match the rest of the settings sub-pages.

### Diagnosis (from research)

The outer scaffold is already correct (`SettingsSubpageScaffold`). The mismatch lives **inside** the pages: raw `showModalBottomSheet`, `AlertDialog`, `SimpleDialog`, `SwitchListTile`, and bare `ListTile` — instead of the project's `PTBottomSheet` + `PTPickerRow`, `PTDialog`, and `SettingsTile`.

### Concrete edits per file

**`lib/page/settings_page/ai_image_analysis.dart`**
- `_pickProvider` (lines 43-78) → `PTBottomSheet.show` + `PTPickerRow`.
- `_pickImageOpenMode` (lines 80-110) → `PTBottomSheet.show` + `PTPickerRow`.
- `_pickModel` (lines 199-342) → `PTBottomSheet.show` (and inner `AlertDialog` for custom name → `PTDialog.show`).
- `_editPrompt` (lines 119-185) → `PTDialog.show`.

**`lib/page/settings_page/ai_tools.dart`**
- `_editShortcutsCallbackTimeoutSec` (151-228) → `PTBottomSheet.show`.
- `_editShortcutsSendMessageTimeoutSec` (230-307) → `PTBottomSheet.show`.
- `_pickShortcutsSendMessagePresentation` (316-359) → `PTBottomSheet.show` + `PTPickerRow`.
- `_pickShortcutsWaitMode` (370-446) → `PTBottomSheet.show` + `PTPickerRow`.

**`lib/page/settings_page/sync.dart`**
- `_showDataDialog` (144-153) `SimpleDialog` → `PTDialog.show`.
- `SwitchListTile` rows (175-211, 648-668) → wrap in `SettingsTile.switchTile` (or set `activeColor: ClaudePalette.accent(context)`).

**`lib/page/settings_page/storege.dart`**
- "Storage Info" raw `ListTile`s (174-228) → `SettingsTile.simple`.
- Custom storage location rows (238-330) → `SettingsTile`.
- "Storage Data File Details" `TabBar` + `TabBarView` (335-422) → extract to a new sub-page hosted in `SettingsSubpageScaffold` (move the `TabController` ownership with it). Replace the inline block with a `SettingsTile.navigation` row that pushes to the new page.

**`lib/page/settings_page/ai.dart`**
- The `CupertinoStyleRoute` push of `AiToolsSettingsPage` (287-297) is functionally fine — leave it unless it visibly differs. Defer this micro-fix unless the user reports a difference.

### Risk handling

- `storege.dart` `_StorageSettingsState` has `SingleTickerProviderStateMixin` + `late TabController _tabController`. When extracting the TabBar to a new sub-page, that page also owns the controller (`SingleTickerProviderStateMixin` + dispose). Old state in `storege.dart` drops the `with SingleTickerProviderStateMixin` and the controller field.
- All other edits are mechanical. Preserve any `setState(() {})` calls after `Prefs()....=` writes.

### Verification

Visual smoke: open settings → for each of the 5 pages, tap each picker / switch / dialog and confirm warm cream/dark background + 12-radius PT* widgets, identical to neighbors like `lib/page/settings_page/reading.dart`.

---

## Task 3 — Open-book animation flicker fix

### Diagnosis

`lib/page/book_player/epub_player.dart:1188-1198` starts a 600ms fade on the cover overlay via a post-frame callback (timer-driven). The Cupertino page push is still in flight when the fade starts, so the cover briefly appears over the sliding-in page and then fades — looks like "a rounded rectangle flashing."

### Fix

Two-part change in `lib/page/book_player/epub_player.dart`:

1. **Stop firing the fade from the post-frame callback.** Initialize the `AnimationController` with `value: 1.0` (cover fully visible).
2. **Fire `_animationController!.forward()` from the existing `onLoadEnd` JS callback** (around line 713-718, after the EPUB content has finished rendering). The cover then holds steady through the entire page transition and only fades once the WebView has actually drawn the book.

### Verification

- Tap a book; during the Cupertino slide-in, no rounded box appears on top of the sliding page — the user sees only the destination cover, then it fades to reveal the EPUB content.
- Toggle Settings → Appearance → "open book animation" off — confirm flicker is gone (regression check).
- Open a large EPUB so `onLoadEnd` is delayed by ~1s — the cover should remain visible the whole time, then fade.

---

## Rollout / sequencing

Three independent branches/commits, in order of risk:

1. **Task 3** (flicker fix) — smallest, lowest risk. Ship first.
2. **Task 2** (settings theming) — mechanical, contained. Ship after a quick visual sweep.
3. **Task 1** (in-place reading) — landed behind a soft-launch entry point: a new "Link from Files" option in the bookshelf import menu (the existing "Import from device" stays the primary path). Ship after manual TestFlight smoke against iCloud Drive + on-device Files, confirming sync skip + delete safety.

Each ships as its own commit so any one can be rolled back without disturbing the others.
