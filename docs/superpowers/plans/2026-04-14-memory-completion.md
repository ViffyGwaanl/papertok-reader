# Memory Completion Implementation Plan

> **Status: ✅ COMPLETE — shipped 2026-04-14 to TestFlight build 6442 (commit `d43ff0e1`).**
>
> All 12 implementation tasks (B1 tasks 1-5, B2 tasks 6-10 with 10a-10e sub-tasks, B3 tasks 11-12) landed via subagent-driven development with two-stage review per task. 43/43 memory tests pass. One data-loss bug was caught at spec-review stage (Task 3 `allowV1Fallback` default wrong on write paths) and fixed before merge. Task 13 (TF upload) also done.
>
> This document is preserved as a historical record of the plan as executed.

**Goal:** Close the three remaining gaps in the Memory feature — source jump-back (B1), top-level Memory destination with browse/organize (B2), and explainable auto-write rules (B3) — so Memory ships at v1.

**Architecture:** Schema bump v1→v2 on `MemoryCandidate` adds optional `bookId` / `cfi` / `chapter` / `sourceKind` / `tags` / `rationale`. Capture rule inspects `currentReadingProvider` at memory-creation time. A new top-level `MemoryHomePage` joins the bottom-nav (6-tab variant with fallback documented) and renders Inbox + MEMORY.md + recent daily notes with tag editor, search, and bulk ops. Existing `triggerKind` / `confidence` fields get surfaced in the UI, and a per-rule pref namespace (`memoryRule.<id>`) exposes rule toggles in settings.

**Tech Stack:** Flutter (Dart), Riverpod, JSON-file persistence (no SQLite for candidates), existing `MemorySearchService` (SQLite index for markdown chunks), existing Claude design primitives (`ClaudePalette`, `PTBottomSheet`, `SettingsSectionCard`).

---

## File Structure

**Sub-project B1 (source jump-back) — touches:**
- `lib/service/memory/memory_candidate.dart` — add fields + enum + v2 serialization
- `lib/service/memory/memory_source_kind.dart` — NEW, discriminated union enum
- `lib/service/memory/memory_candidate_store.dart` — v2 read/write with v1 fallback
- `lib/service/memory/memory_workflow_service.dart` — capture rule reads `currentReadingProvider`, new `openInReader` + `openInConversation` methods
- `lib/service/memory/memory_session_digest_service.dart` — pass through reading context to candidate creation
- `lib/page/settings_page/memory.dart` — add icon-button row (Open in reader / Open conversation) to each inbox row
- `test/service/memory/memory_candidate_v2_test.dart` — NEW unit tests for round-trip + migration

**Sub-project B2 (top-level Memory destination) — touches:**
- `lib/page/memory/memory_home_page.dart` — NEW top-level page
- `lib/page/memory/memory_detail_page.dart` — NEW detail view with tag editor + navigation buttons
- `lib/page/memory/memory_bulk_selection_controller.dart` — NEW ChangeNotifier for multi-select mode
- `lib/page/memory/widgets/memory_row.dart` — NEW row widget used by home + detail + inbox
- `lib/page/memory/widgets/tag_editor.dart` — NEW inline tag chip editor with autocomplete
- `lib/service/memory/markdown_memory_store.dart` — add `listLongTermEntries()`, `listRecentDailyNotes(int count)`, `readEntry(String path)`, tag YAML parse/serialize
- `lib/service/memory/memory_pending_count_provider.dart` — NEW Riverpod provider for bottom-nav badge
- `lib/page/home_page/home_page.dart` — add Memory tab (6-tab variant)
- `lib/config/shared_preference_provider.dart` — home tab config default list gets Memory appended
- `lib/l10n/app_en.arb`, `app_zh.arb` (and siblings) — new keys for tab label, empty state, bulk actions, tag editor

**Sub-project B3 (explainable auto-write rules) — touches:**
- `lib/service/memory/memory_candidate.dart` — add `rationale: String?` field (piggybacks on v2 schema from B1)
- `lib/service/memory/memory_session_digest_service.dart` — compute and persist rationale string
- `lib/service/memory/memory_rule_prefs.dart` — NEW helper for per-rule bool prefs
- `lib/page/settings_page/memory.dart` — new "Auto-capture rules" section with toggle rows + "?" explain popups; extend inbox row with trigger badge + confidence dot
- `lib/page/memory/widgets/memory_row.dart` — show trigger badge + confidence dot + rationale sentence
- `test/service/memory/memory_rule_prefs_test.dart` — NEW

Sequencing: B1 lands first (schema). B2 and B3 run in parallel after B1 because they share the schema but touch disjoint files.

---

## Task 1: Add `MemorySourceKind` enum

**Files:**
- Create: `lib/service/memory/memory_source_kind.dart`
- Test: `test/service/memory/memory_source_kind_test.dart`

- [ ] **Step 1.1: Write the failing test**

```dart
// test/service/memory/memory_source_kind_test.dart
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemorySourceKind', () {
    test('round-trip via string', () {
      for (final v in MemorySourceKind.values) {
        expect(MemorySourceKind.fromString(v.asString), equals(v));
      }
    });

    test('unknown string defaults to chat', () {
      expect(MemorySourceKind.fromString('wtf'), equals(MemorySourceKind.chat));
      expect(MemorySourceKind.fromString(null), equals(MemorySourceKind.chat));
    });
  });
}
```

- [ ] **Step 1.2: Run test (expect compile error)**

```
flutter test test/service/memory/memory_source_kind_test.dart
```
Expected: FAIL — `memory_source_kind.dart` not found.

- [ ] **Step 1.3: Create the enum**

```dart
// lib/service/memory/memory_source_kind.dart

/// Discriminator for how a MemoryCandidate was produced.
///
/// `reading` means the user was actively in a book when the candidate was
/// captured, so `bookId` / `cfi` / `chapter` fields should be populated.
/// `chat` means a pure chat-session digest. `manual` means the user
/// explicitly saved text to memory.
enum MemorySourceKind {
  chat('chat'),
  reading('reading'),
  manual('manual');

  final String asString;
  const MemorySourceKind(this.asString);

  static MemorySourceKind fromString(String? value) {
    for (final k in MemorySourceKind.values) {
      if (k.asString == value) return k;
    }
    return MemorySourceKind.chat;
  }
}
```

- [ ] **Step 1.4: Run test (expect pass)**

```
flutter test test/service/memory/memory_source_kind_test.dart
```
Expected: PASS — 2 tests.

- [ ] **Step 1.5: Commit**

```bash
git add lib/service/memory/memory_source_kind.dart test/service/memory/memory_source_kind_test.dart
git commit -m "feat(memory): add MemorySourceKind discriminator enum (B1)"
```

---

## Task 2: Extend `MemoryCandidate` with v2 fields + serialization

**Files:**
- Modify: `lib/service/memory/memory_candidate.dart`
- Test: `test/service/memory/memory_candidate_v2_test.dart` (NEW)

- [ ] **Step 2.1: Write the failing v2 round-trip test**

```dart
// test/service/memory/memory_candidate_v2_test.dart
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v2 round-trip preserves all new fields', () {
    final c = MemoryCandidate(
      id: 'id1',
      summary: 's',
      text: 't',
      targetDoc: MemoryDocTarget.daily,
      createdAtMs: 1000,
      status: MemoryCandidateStatus.pending,
      sourceType: 'session',
      // v2 fields
      bookId: 42,
      cfi: 'epubcfi(/6/4!/4/2)',
      chapter: 'Chapter 1',
      sourceKind: MemorySourceKind.reading,
      tags: const ['insight', 'biology'],
      rationale: 'Captured because the same question was raised twice.',
    );
    final json = c.toJson();
    final back = MemoryCandidate.fromJson(json);
    expect(back.bookId, equals(42));
    expect(back.cfi, equals('epubcfi(/6/4!/4/2)'));
    expect(back.chapter, equals('Chapter 1'));
    expect(back.sourceKind, equals(MemorySourceKind.reading));
    expect(back.tags, equals(['insight', 'biology']));
    expect(back.rationale, isNotNull);
  });

  test('v1 json without new fields deserializes with safe defaults', () {
    final v1Json = {
      'id': 'old',
      'summary': 's',
      'text': 't',
      'targetDoc': 'daily',
      'createdAtMs': 1000,
      'status': 'pending',
      'sourceType': 'session',
    };
    final back = MemoryCandidate.fromJson(v1Json);
    expect(back.bookId, isNull);
    expect(back.cfi, isNull);
    expect(back.chapter, isNull);
    expect(back.sourceKind, equals(MemorySourceKind.chat));
    expect(back.tags, isEmpty);
    expect(back.rationale, isNull);
  });
}
```

- [ ] **Step 2.2: Run test (expect compile error)**

```
flutter test test/service/memory/memory_candidate_v2_test.dart
```
Expected: FAIL — the `bookId`, `cfi`, etc. named params don't exist yet.

- [ ] **Step 2.3: Add fields to `MemoryCandidate`**

Open `lib/service/memory/memory_candidate.dart`. Add imports:

```dart
import 'memory_source_kind.dart';
```

Inside the class (grep for the existing `final` field list near the top of the class):

```dart
  // v2 source-reference fields — all optional for backwards compat.
  final int? bookId;
  final String? cfi;
  final String? chapter;
  final MemorySourceKind sourceKind;
  final List<String> tags;
  final String? rationale;
```

Extend the constructor:

```dart
  MemoryCandidate({
    required this.id,
    // ... existing required params
    required this.summary,
    required this.text,
    required this.targetDoc,
    required this.createdAtMs,
    required this.status,
    required this.sourceType,
    // existing optional params
    this.confidence,
    this.sensitivity,
    // ... etc
    // v2 additions
    this.bookId,
    this.cfi,
    this.chapter,
    this.sourceKind = MemorySourceKind.chat,
    this.tags = const [],
    this.rationale,
  });
```

Extend `toJson()` (find it near the bottom of the class):

```dart
  Map<String, dynamic> toJson() => {
        // ... existing entries
        if (bookId != null) 'bookId': bookId,
        if (cfi != null) 'cfi': cfi,
        if (chapter != null) 'chapter': chapter,
        'sourceKind': sourceKind.asString,
        'tags': tags,
        if (rationale != null) 'rationale': rationale,
      };
```

Extend `fromJson()`:

```dart
  factory MemoryCandidate.fromJson(Map<String, dynamic> json) {
    return MemoryCandidate(
      // ... existing params
      bookId: json['bookId'] as int?,
      cfi: json['cfi'] as String?,
      chapter: json['chapter'] as String?,
      sourceKind: MemorySourceKind.fromString(json['sourceKind'] as String?),
      tags: (json['tags'] as List?)?.cast<String>() ?? const <String>[],
      rationale: json['rationale'] as String?,
    );
  }
```

Add a `copyWith` that includes the new fields if one exists.

- [ ] **Step 2.4: Run test (expect pass)**

```
flutter test test/service/memory/memory_candidate_v2_test.dart
```
Expected: PASS — 2 tests.

- [ ] **Step 2.5: Run full unit test suite for memory**

```
flutter test test/service/memory/
```
Expected: PASS. If existing tests break because the constructor added params, they must be using positional args (unlikely) — adjust to named-arg call if so.

- [ ] **Step 2.6: Commit**

```bash
git add lib/service/memory/memory_candidate.dart test/service/memory/memory_candidate_v2_test.dart
git commit -m "feat(memory): add v2 fields to MemoryCandidate (bookId/cfi/chapter/sourceKind/tags/rationale)"
```

---

## Task 3: Bump `MemoryCandidateStore` schema version to 2 with v1 fallback read

**Files:**
- Modify: `lib/service/memory/memory_candidate_store.dart`
- Test: `test/service/memory/memory_candidate_store_migration_test.dart` (NEW)

- [ ] **Step 3.1: Write the failing migration test**

```dart
// test/service/memory/memory_candidate_store_migration_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:papertok_reader/service/memory/memory_candidate_store.dart';
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mcs_migration_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('reads v1 JSON and synthesizes default v2 fields', () async {
    final v1 = {
      'version': 1,
      'candidates': [
        {
          'id': 'one',
          'summary': 's',
          'text': 't',
          'targetDoc': 'daily',
          'createdAtMs': 1000,
          'status': 'pending',
          'sourceType': 'session',
        }
      ],
    };
    final v1File = File(p.join(tempRoot.path, '.workflow', 'review_inbox_v1.json'));
    v1File.createSync(recursive: true);
    v1File.writeAsStringSync(jsonEncode(v1));

    final store = MemoryCandidateStore(root: tempRoot.path);
    final list = await store.readAll();
    expect(list.length, 1);
    expect(list.first.sourceKind, MemorySourceKind.chat);
    expect(list.first.tags, isEmpty);
    expect(list.first.bookId, isNull);
  });

  test('writing creates v2 file', () async {
    final store = MemoryCandidateStore(root: tempRoot.path);
    await store.writeAll([]);
    final v2File = File(p.join(tempRoot.path, '.workflow', 'review_inbox_v2.json'));
    expect(v2File.existsSync(), isTrue);
    final data = jsonDecode(v2File.readAsStringSync());
    expect(data['version'], 2);
  });
}
```

- [ ] **Step 3.2: Run test (expect fail)**

```
flutter test test/service/memory/memory_candidate_store_migration_test.dart
```
Expected: FAIL — the store still writes `review_inbox_v1.json` only.

- [ ] **Step 3.3: Update the store**

Open `lib/service/memory/memory_candidate_store.dart`. Near the top of the class find the constant (currently `schemaVersion = 1` and file name `review_inbox_v1.json`). Replace with:

```dart
class MemoryCandidateStore {
  static const int _schemaVersionV2 = 2;
  static const String _v2FileName = 'review_inbox_v2.json';
  static const String _v1FileName = 'review_inbox_v1.json';
  static const String _folder = '.workflow';

  final String root;
  MemoryCandidateStore({required this.root});

  File _v2File() => File(p.join(root, _folder, _v2FileName));
  File _v1File() => File(p.join(root, _folder, _v1FileName));

  Future<List<MemoryCandidate>> readAll() async {
    final v2 = _v2File();
    if (await v2.exists()) {
      final data = jsonDecode(await v2.readAsString()) as Map<String, dynamic>;
      final list = (data['candidates'] as List).cast<Map<String, dynamic>>();
      return list.map(MemoryCandidate.fromJson).toList();
    }
    // Fallback: read v1, synthesize defaults via MemoryCandidate.fromJson
    // (the v2 fields default to chat / empty / null when absent).
    final v1 = _v1File();
    if (await v1.exists()) {
      final data = jsonDecode(await v1.readAsString()) as Map<String, dynamic>;
      final list = (data['candidates'] as List).cast<Map<String, dynamic>>();
      return list.map(MemoryCandidate.fromJson).toList();
    }
    return const [];
  }

  Future<void> writeAll(List<MemoryCandidate> candidates) async {
    final f = _v2File();
    await f.parent.create(recursive: true);
    final encoded = jsonEncode({
      'version': _schemaVersionV2,
      'candidates': candidates.map((c) => c.toJson()).toList(),
    });
    await f.writeAsString(encoded);
  }
}
```

Preserve any other public methods that currently exist (`addCandidate`, `updateStatus`, etc.) and have them delegate to `readAll` / `writeAll`. Update any reference to `schemaVersion = 1` accordingly.

- [ ] **Step 3.4: Run migration test (expect pass)**

```
flutter test test/service/memory/memory_candidate_store_migration_test.dart
```
Expected: PASS.

- [ ] **Step 3.5: Run full memory test suite**

```
flutter test test/service/memory/
```
Expected: PASS.

- [ ] **Step 3.6: Commit**

```bash
git add lib/service/memory/memory_candidate_store.dart test/service/memory/memory_candidate_store_migration_test.dart
git commit -m "feat(memory): bump store to schema v2 with v1-read fallback (B1)"
```

---

## Task 4: Capture rule reads `currentReadingProvider` during digest

**Files:**
- Modify: `lib/service/memory/memory_workflow_service.dart`
- Modify: `lib/service/memory/memory_session_digest_service.dart`
- Test: `test/service/memory/memory_capture_rule_test.dart` (NEW)

- [ ] **Step 4.1: Write the failing test**

```dart
// test/service/memory/memory_capture_rule_test.dart
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/memory/memory_session_digest_service.dart';
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemorySessionDigestService capture rule', () {
    test('when reading context present, candidate is reading-sourced', () {
      final book = Book(id: 7, title: 'x', author: 'a', /* ... minimal */);
      final state = CurrentReadingState(book: book, cfi: 'epubcfi(/6/4)');
      final c = MemorySessionDigestService.buildCandidate(
        summary: 's',
        text: 't',
        reading: state,
        currentChapter: 'Ch1',
      );
      expect(c.sourceKind, MemorySourceKind.reading);
      expect(c.bookId, 7);
      expect(c.cfi, 'epubcfi(/6/4)');
      expect(c.chapter, 'Ch1');
    });

    test('without reading context, candidate is chat-sourced', () {
      final c = MemorySessionDigestService.buildCandidate(
        summary: 's',
        text: 't',
        reading: null,
        currentChapter: null,
      );
      expect(c.sourceKind, MemorySourceKind.chat);
      expect(c.bookId, isNull);
      expect(c.cfi, isNull);
      expect(c.chapter, isNull);
    });
  });
}
```

- [ ] **Step 4.2: Run test (expect fail)**

```
flutter test test/service/memory/memory_capture_rule_test.dart
```
Expected: FAIL — `buildCandidate` not defined / signature mismatch.

- [ ] **Step 4.3: Extract a pure `buildCandidate` factory on the digest service**

Open `lib/service/memory/memory_session_digest_service.dart`. Near the class, add a static factory:

```dart
/// Pure candidate factory for unit testing. Does NOT touch streams,
/// persistence, or providers — all inputs are explicit.
static MemoryCandidate buildCandidate({
  required String summary,
  required String text,
  required CurrentReadingState? reading,
  required String? currentChapter,
  String? conversationId,
  String? messageNodeId,
  String? triggerKind,
  double? confidence,
  String? rationale,
}) {
  final hasReading = reading != null && reading.book.id > 0;
  return MemoryCandidate(
    id: _newId(),
    summary: summary,
    text: text,
    targetDoc: MemoryDocTarget.daily,
    createdAtMs: DateTime.now().millisecondsSinceEpoch,
    status: MemoryCandidateStatus.pending,
    sourceType: hasReading ? 'reading_session' : 'chat_session',
    bookId: hasReading ? reading.book.id : null,
    cfi: hasReading ? reading.cfi : null,
    chapter: hasReading ? currentChapter : null,
    sourceKind: hasReading ? MemorySourceKind.reading : MemorySourceKind.chat,
    conversationId: conversationId,
    messageNodeId: messageNodeId,
    triggerKind: triggerKind,
    confidence: confidence,
    rationale: rationale,
  );
}
```

(Use the actual existing ID generator `_newId()` from the class; if none exists, use `DateTime.now().microsecondsSinceEpoch.toString()`.)

- [ ] **Step 4.4: Run test (expect pass)**

```
flutter test test/service/memory/memory_capture_rule_test.dart
```
Expected: PASS.

- [ ] **Step 4.5: Wire `captureSessionDigest` to use the factory**

In `lib/service/memory/memory_workflow_service.dart`, inside `captureSessionDigest()` where candidates are created, read the reading context from the container:

```dart
final reading = container.read(currentReadingProvider).value;
final chapter = container.read(currentChapterProvider).value;  // if exists
final candidate = MemorySessionDigestService.buildCandidate(
  summary: draft.summary,
  text: draft.text,
  reading: reading,
  currentChapter: chapter,
  conversationId: conversationId,
  messageNodeId: draft.messageNodeId,
  triggerKind: 'session_digest',
  confidence: draft.confidence,
);
```

Replace the hand-built `MemoryCandidate(...)` calls in that method with this factory.

- [ ] **Step 4.6: Run full memory test suite**

```
flutter test test/service/memory/
```
Expected: PASS.

- [ ] **Step 4.7: Commit**

```bash
git add lib/service/memory/memory_workflow_service.dart lib/service/memory/memory_session_digest_service.dart test/service/memory/memory_capture_rule_test.dart
git commit -m "feat(memory): capture rule inspects reading context (B1)"
```

---

## Task 5: Add `openInReader` + `openInConversation` navigation methods

**Files:**
- Modify: `lib/service/memory/memory_workflow_service.dart`
- Modify: `lib/page/settings_page/memory.dart` (UI hookup)

- [ ] **Step 5.1: Add navigation methods to workflow service**

In `lib/service/memory/memory_workflow_service.dart`, add:

```dart
/// Navigate into the reader at the position the memory was captured.
/// No-op if the candidate has no bookId or the book was deleted.
Future<void> openInReader(
  BuildContext context,
  MemoryCandidate candidate,
) async {
  final bookId = candidate.bookId;
  if (bookId == null) return;
  final book = await bookDao.selectById(bookId);
  if (book == null || book.isDeleted) {
    AnxToast.show(L10n.of(context).bookDeleted);
    return;
  }
  await pushToReadingPage(
    ProviderScope.containerOf(context).read(/* any ref */),
    context,
    book,
    cfi: candidate.cfi,
  );
}

/// Navigate to the conversation the memory was captured from.
Future<void> openInConversation(
  BuildContext context,
  MemoryCandidate candidate,
) async {
  final convId = candidate.conversationId;
  if (convId == null) return;
  // Routes to the AI chat page with the conversation pre-selected.
  Navigator.of(context, rootNavigator: true).push(
    CupertinoStyleRoute(
      page: AiChatPage(initialConversationId: convId),
    ),
  );
}
```

Use whatever imports the file already has for `pushToReadingPage`, `bookDao`, `AnxToast`, `CupertinoStyleRoute`, `AiChatPage`. If `AiChatPage` doesn't accept an initial conversation id, leave the conversation jump as a no-op (`unimplemented: conversationId passed but no deep-link yet`) and TODO a follow-up.

- [ ] **Step 5.2: Add UI row to the inbox item in settings memory page**

In `lib/page/settings_page/memory.dart`, inside the inbox row builder (the one that currently renders `sourcePointer` / `rawContextRef` text), append a Row of icon buttons:

```dart
Padding(
  padding: const EdgeInsets.only(top: 6),
  child: Row(
    children: [
      if (candidate.sourceKind == MemorySourceKind.reading &&
          candidate.bookId != null)
        _SourceActionButton(
          icon: Icons.menu_book_outlined,
          label: L10n.of(context).memoryOpenInReader,
          onTap: () => _workflow.openInReader(context, candidate),
        ),
      if (candidate.conversationId != null) ...[
        const SizedBox(width: 8),
        _SourceActionButton(
          icon: Icons.chat_bubble_outline,
          label: L10n.of(context).memoryOpenConversation,
          onTap: () => _workflow.openInConversation(context, candidate),
        ),
      ],
    ],
  ),
),
```

Define `_SourceActionButton` as a small private widget in the same file:

```dart
class _SourceActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: ClaudePalette.bg(context).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: ClaudePalette.divider(context),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: ClaudePalette.secondary(context)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: ClaudePalette.secondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5.3: Add L10n keys**

Add to `lib/l10n/app_en.arb`:

```json
"memoryOpenInReader": "Open in reader",
"memoryOpenConversation": "Open conversation",
```

Add the zh-CN / zh-TW / other variants with translations:

```json
"memoryOpenInReader": "在阅读器中打开",
"memoryOpenConversation": "打开对话"
```

- [ ] **Step 5.4: Analyze + compile**

```
flutter gen-l10n
FLUTTER_NO_PUB=1 flutter analyze --no-pub lib/service/memory/memory_workflow_service.dart lib/page/settings_page/memory.dart
```
Expected: 0 new errors.

- [ ] **Step 5.5: Commit**

```bash
git add lib/service/memory/memory_workflow_service.dart lib/page/settings_page/memory.dart lib/l10n/
git commit -m "feat(memory): inline jump-back buttons on inbox rows (B1)"
```

---

## Task 6: Add markdown store helpers for browse page

**Files:**
- Modify: `lib/service/memory/markdown_memory_store.dart`
- Test: `test/service/memory/markdown_memory_store_test.dart`

- [ ] **Step 6.1: Write the failing test**

```dart
import 'dart:io';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mms_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('listLongTermEntries splits MEMORY.md by top-level headings', () async {
    final f = File(p.join(tempRoot.path, 'MEMORY.md'));
    await f.writeAsString('# A\n\nbody a\n\n# B\n\nbody b\n');
    final store = MarkdownMemoryStore(root: tempRoot.path);
    final list = await store.listLongTermEntries();
    expect(list.length, 2);
    expect(list.first.title, 'A');
    expect(list.last.title, 'B');
  });

  test('listRecentDailyNotes returns files sorted newest first', () async {
    for (final date in ['2026-04-12', '2026-04-13', '2026-04-14']) {
      File(p.join(tempRoot.path, '$date.md')).writeAsStringSync('content for $date');
    }
    final store = MarkdownMemoryStore(root: tempRoot.path);
    final list = await store.listRecentDailyNotes(count: 2);
    expect(list.length, 2);
    expect(list.first.title, contains('2026-04-14'));
    expect(list.last.title, contains('2026-04-13'));
  });
}
```

- [ ] **Step 6.2: Run test (expect fail)**

```
flutter test test/service/memory/markdown_memory_store_test.dart
```
Expected: FAIL — `listLongTermEntries` not defined.

- [ ] **Step 6.3: Implement the helpers**

In `lib/service/memory/markdown_memory_store.dart`, add:

```dart
class MemoryEntryRef {
  final String title;
  final String path;
  final String preview;
  final DateTime? modified;
  const MemoryEntryRef({
    required this.title,
    required this.path,
    required this.preview,
    required this.modified,
  });
}

extension MarkdownMemoryStoreBrowse on MarkdownMemoryStore {
  Future<List<MemoryEntryRef>> listLongTermEntries() async {
    final file = File(p.join(root, 'MEMORY.md'));
    if (!file.existsSync()) return [];
    final content = await file.readAsString();
    final sections = <MemoryEntryRef>[];
    final lines = content.split('\n');
    String? currentTitle;
    final buf = StringBuffer();
    for (final line in lines) {
      if (line.startsWith('# ')) {
        if (currentTitle != null) {
          sections.add(MemoryEntryRef(
            title: currentTitle,
            path: file.path,
            preview: _preview(buf.toString()),
            modified: file.lastModifiedSync(),
          ));
          buf.clear();
        }
        currentTitle = line.substring(2).trim();
      } else {
        buf.writeln(line);
      }
    }
    if (currentTitle != null) {
      sections.add(MemoryEntryRef(
        title: currentTitle,
        path: file.path,
        preview: _preview(buf.toString()),
        modified: file.lastModifiedSync(),
      ));
    }
    return sections;
  }

  Future<List<MemoryEntryRef>> listRecentDailyNotes({int count = 14}) async {
    final dir = Directory(root);
    if (!dir.existsSync()) return [];
    final regex = RegExp(r'^(\d{4}-\d{2}-\d{2})\.md$');
    final entries = dir
        .listSync()
        .whereType<File>()
        .where((f) => regex.hasMatch(p.basename(f.path)))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    final result = <MemoryEntryRef>[];
    for (final f in entries.take(count)) {
      final body = await f.readAsString();
      result.add(MemoryEntryRef(
        title: p.basenameWithoutExtension(f.path),
        path: f.path,
        preview: _preview(body),
        modified: f.lastModifiedSync(),
      ));
    }
    return result;
  }

  String _preview(String body) {
    final trimmed = body.trim();
    if (trimmed.length <= 120) return trimmed;
    return '${trimmed.substring(0, 120)}…';
  }
}
```

- [ ] **Step 6.4: Run test (expect pass)**

```
flutter test test/service/memory/markdown_memory_store_test.dart
```
Expected: PASS.

- [ ] **Step 6.5: Commit**

```bash
git add lib/service/memory/markdown_memory_store.dart test/service/memory/markdown_memory_store_test.dart
git commit -m "feat(memory): add browse helpers to MarkdownMemoryStore (B2)"
```

---

## Task 7: New `MemoryHomePage` shell + pending-count provider

**Files:**
- Create: `lib/page/memory/memory_home_page.dart`
- Create: `lib/service/memory/memory_pending_count_provider.dart`
- Test: `test/page/memory/memory_home_page_test.dart`

- [ ] **Step 7.1: Pending-count provider**

```dart
// lib/service/memory/memory_pending_count_provider.dart
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_workflow_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits the number of pending review candidates. Consumed by the bottom
/// nav Memory tab badge and the inbox section header.
final memoryPendingCountProvider = StreamProvider<int>((ref) async* {
  final workflow = ref.read(memoryWorkflowProvider);
  await for (final list in workflow.watchCandidates()) {
    yield list
        .where((c) => c.status == MemoryCandidateStatus.pending)
        .length;
  }
});
```

(If `memoryWorkflowProvider` / `watchCandidates` don't exist, expose a
`Stream<List<MemoryCandidate>>` on `MemoryWorkflowService` backed by a
`StreamController` that pushes whenever `writeAll` runs.)

- [ ] **Step 7.2: Widget test stub for the page**

```dart
// test/page/memory/memory_home_page_test.dart
import 'package:papertok_reader/page/memory/memory_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders section headers even when empty', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: MemoryHomePage()),
      ),
    );
    await tester.pump();
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('LONG-TERM'), findsOneWidget);
  });
}
```

- [ ] **Step 7.3: Run test (expect fail)**

```
flutter test test/page/memory/memory_home_page_test.dart
```
Expected: FAIL — `MemoryHomePage` not found.

- [ ] **Step 7.4: Implement `MemoryHomePage`**

```dart
// lib/page/memory/memory_home_page.dart
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/memory/memory_pending_count_provider.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MemoryHomePage extends ConsumerWidget {
  const MemoryHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(memoryPendingCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).memoryTabTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {/* Task 10 */},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _SectionHeader(title: L10n.of(context).memoryInboxSectionTitle),
          _InboxSummaryCard(pendingCount: pendingCount),
          const SizedBox(height: 16),
          _SectionHeader(title: L10n.of(context).memoryTodaySectionTitle),
          // Task 8 fills this in with rows
          const SizedBox(height: 16),
          _SectionHeader(title: L10n.of(context).memoryLongTermSectionTitle),
          // Task 8 fills this in with rows
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: ClaudePalette.secondary(context),
        ),
      ),
    );
  }
}

class _InboxSummaryCard extends StatelessWidget {
  final int pendingCount;
  const _InboxSummaryCard({required this.pendingCount});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: ClaudePalette.card(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {/* push settings_page/memory for now */},
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.inbox_outlined, color: ClaudePalette.fg(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  L10n.of(context).memoryInboxSectionTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ClaudePalette.fg(context),
                  ),
                ),
              ),
              if (pendingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: ClaudePalette.accent(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$pendingCount',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right, color: ClaudePalette.tertiary(context)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7.5: Add L10n keys**

`app_en.arb`:
```json
"memoryTabTitle": "Memory",
"memoryInboxSectionTitle": "Inbox",
"memoryTodaySectionTitle": "Today",
"memoryLongTermSectionTitle": "Long-term"
```

Same keys in `app_zh.arb` / other variants:
```json
"memoryTabTitle": "记忆",
"memoryInboxSectionTitle": "收件箱",
"memoryTodaySectionTitle": "今天",
"memoryLongTermSectionTitle": "长期记忆"
```

- [ ] **Step 7.6: Run test (expect pass)**

```
flutter gen-l10n
flutter test test/page/memory/memory_home_page_test.dart
```
Expected: PASS.

- [ ] **Step 7.7: Commit**

```bash
git add lib/page/memory/memory_home_page.dart lib/service/memory/memory_pending_count_provider.dart lib/l10n/ test/page/memory/memory_home_page_test.dart
git commit -m "feat(memory): MemoryHomePage shell + pending count provider (B2)"
```

---

## Task 8: Memory rows wired to markdown store

**Files:**
- Create: `lib/page/memory/widgets/memory_row.dart`
- Modify: `lib/page/memory/memory_home_page.dart`
- Test: `test/page/memory/memory_row_test.dart`

- [ ] **Step 8.1: Row widget test**

```dart
import 'package:papertok_reader/page/memory/widgets/memory_row.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders title and preview', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MemoryRow(
          entry: const MemoryEntryRef(
            title: 'Test title',
            path: '/tmp/x.md',
            preview: 'preview body',
            modified: null,
          ),
          onTap: () {},
        ),
      ),
    ));
    expect(find.text('Test title'), findsOneWidget);
    expect(find.text('preview body'), findsOneWidget);
  });
}
```

- [ ] **Step 8.2: Implement row**

```dart
// lib/page/memory/widgets/memory_row.dart
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';

class MemoryRow extends StatelessWidget {
  final MemoryEntryRef entry;
  final VoidCallback onTap;
  const MemoryRow({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ClaudePalette.fg(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: ClaudePalette.secondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8.3: Wire home page to the store**

Replace the two placeholder spots in `memory_home_page.dart` with `FutureBuilder<List<MemoryEntryRef>>` calls to `MarkdownMemoryStore.listRecentDailyNotes(count: 14)` and `listLongTermEntries()`. Render a Column of `MemoryRow`s separated by 0.5 hairline dividers (`Divider(height: 1, thickness: 0.5, color: ClaudePalette.divider(context), indent: 16)`). Wrap the whole section in a `Material` with `ClaudePalette.card(context)` and 14 radius.

- [ ] **Step 8.4: Run tests**

```
flutter test test/page/memory/
```
Expected: PASS.

- [ ] **Step 8.5: Commit**

```bash
git add lib/page/memory/widgets/memory_row.dart lib/page/memory/memory_home_page.dart test/page/memory/memory_row_test.dart
git commit -m "feat(memory): MemoryHomePage wired to markdown store (B2)"
```

---

## Task 9: Add Memory tab to bottom nav

**Files:**
- Modify: `lib/page/home_page/home_page.dart`
- Modify: `lib/config/shared_preference_provider.dart` (home tab config defaults)
- Test: manual smoke — no unit test for bottom nav assembly

- [ ] **Step 9.1: Add tab id `memory` to defaults**

Open `lib/config/shared_preference_provider.dart`. Find `_defaultHomeTabs` (or equivalent list constant). Append `'memory'` between `'statistics'` and `'settings'`.

- [ ] **Step 9.2: Register the tab in home_page.dart**

Grep `TabContent.bookshelf` or similar to find the registry. Add:

```dart
case 'memory':
  return HomeTabContent(
    label: L10n.of(context).memoryTabTitle,
    icon: Icons.psychology_outlined,
    page: const MemoryHomePage(),
    badgeCount: ref.watch(memoryPendingCountProvider).valueOrNull ?? 0,
  );
```

If the existing home tab API doesn't support badges, extend it with an optional `badgeCount` field and render a small dot / number inside the nav bar item.

- [ ] **Step 9.3: Run app manually**

```
flutter run -d <device>
```
Expected: bottom nav shows 6 tabs; tapping Memory opens `MemoryHomePage`.

- [ ] **Step 9.4: Commit**

```bash
git add lib/page/home_page/home_page.dart lib/config/shared_preference_provider.dart
git commit -m "feat(memory): add Memory tab to bottom navigation (B2)"
```

---

## Task 10: Memory detail + tag editor + bulk ops

This task is the biggest in the plan; it's decomposed into five strictly-ordered sub-tasks, each a full TDD cycle (write test, fail, implement, pass, commit). Sub-tasks 10a–10e MUST be executed in order because each depends on the previous one.

---

### Sub-task 10a: YAML front-matter tag parser/serializer

**Files:**
- Modify: `lib/service/memory/markdown_memory_store.dart`
- Test: `test/service/memory/markdown_memory_store_tags_test.dart`

- [ ] **Step 10a.1: Write the failing test**

```dart
// test/service/memory/markdown_memory_store_tags_test.dart
import 'dart:io';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mms_tags_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('reads tags from front matter', () async {
    final f = File(p.join(tempRoot.path, '2026-04-14.md'));
    f.writeAsStringSync('---\ntags: [insight, biology]\n---\n# Note\nbody\n');
    final store = MarkdownMemoryStore(root: tempRoot.path);
    final tags = await store.readEntryTags(f.path);
    expect(tags, ['insight', 'biology']);
  });

  test('returns empty list when no front matter', () async {
    final f = File(p.join(tempRoot.path, 'plain.md'));
    f.writeAsStringSync('# Just a note\nbody\n');
    final store = MarkdownMemoryStore(root: tempRoot.path);
    final tags = await store.readEntryTags(f.path);
    expect(tags, isEmpty);
  });

  test('write creates front matter and preserves body', () async {
    final f = File(p.join(tempRoot.path, 'plain.md'));
    f.writeAsStringSync('# Just a note\nbody\n');
    final store = MarkdownMemoryStore(root: tempRoot.path);
    await store.writeEntryTags(f.path, ['new']);
    final content = f.readAsStringSync();
    expect(content, startsWith('---\ntags: [new]\n---\n'));
    expect(content, contains('# Just a note'));
    expect(content, contains('body'));
  });

  test('write replaces existing front matter', () async {
    final f = File(p.join(tempRoot.path, 'has.md'));
    f.writeAsStringSync('---\ntags: [old]\n---\n# Note\nbody\n');
    final store = MarkdownMemoryStore(root: tempRoot.path);
    await store.writeEntryTags(f.path, ['updated', 'second']);
    final content = f.readAsStringSync();
    expect(content, startsWith('---\ntags: [updated, second]\n---\n'));
    expect(content.contains('tags: [old]'), isFalse);
    expect(content, contains('# Note'));
  });
}
```

- [ ] **Step 10a.2: Run test (expect fail)**

```
flutter test test/service/memory/markdown_memory_store_tags_test.dart
```
Expected: FAIL — `readEntryTags` / `writeEntryTags` not defined.

- [ ] **Step 10a.3: Implement the helpers**

Extend the existing `MarkdownMemoryStoreBrowse` extension in `lib/service/memory/markdown_memory_store.dart`:

```dart
extension MarkdownMemoryStoreTags on MarkdownMemoryStore {
  /// Extracts a `tags: [a, b, c]` line from a YAML front-matter block.
  /// Returns empty if there is no front matter or the tags line is missing.
  Future<List<String>> readEntryTags(String path) async {
    final file = File(path);
    if (!file.existsSync()) return const [];
    final content = await file.readAsString();
    final fm = _extractFrontMatter(content);
    if (fm == null) return const [];
    final tagMatch = RegExp(r'^tags:\s*\[(.*)\]\s*$', multiLine: true)
        .firstMatch(fm);
    if (tagMatch == null) return const [];
    return tagMatch
        .group(1)!
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Writes the given tag list as a front matter block. Replaces any
  /// existing front matter; preserves the rest of the file verbatim.
  Future<void> writeEntryTags(String path, List<String> tags) async {
    final file = File(path);
    final original = file.existsSync() ? await file.readAsString() : '';
    final body = _stripFrontMatter(original);
    final fm = '---\ntags: [${tags.join(', ')}]\n---\n';
    await file.writeAsString('$fm$body');
  }

  String? _extractFrontMatter(String content) {
    if (!content.startsWith('---\n')) return null;
    final endIdx = content.indexOf('\n---\n', 4);
    if (endIdx == -1) return null;
    return content.substring(4, endIdx);
  }

  String _stripFrontMatter(String content) {
    if (!content.startsWith('---\n')) return content;
    final endIdx = content.indexOf('\n---\n', 4);
    if (endIdx == -1) return content;
    return content.substring(endIdx + 5);
  }
}
```

- [ ] **Step 10a.4: Run test (expect pass)**

```
flutter test test/service/memory/markdown_memory_store_tags_test.dart
```
Expected: PASS — 4 tests.

- [ ] **Step 10a.5: Commit**

```bash
git add lib/service/memory/markdown_memory_store.dart test/service/memory/markdown_memory_store_tags_test.dart
git commit -m "feat(memory): YAML front-matter tag read/write on markdown store (B2)"
```

---

### Sub-task 10b: `TagEditor` widget

**Files:**
- Create: `lib/page/memory/widgets/tag_editor.dart`
- Test: `test/page/memory/tag_editor_test.dart`

- [ ] **Step 10b.1: Write the failing widget test**

```dart
// test/page/memory/tag_editor_test.dart
import 'package:papertok_reader/page/memory/widgets/tag_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders existing tags and calls onChanged on add', (tester) async {
    final updates = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagEditor(
          initial: const ['alpha'],
          suggestions: const ['alpha', 'beta', 'gamma'],
          onChanged: updates.add,
        ),
      ),
    ));
    expect(find.text('alpha'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(updates.last, containsAll(['alpha', 'beta']));
    expect(find.text('beta'), findsOneWidget);
  });

  testWidgets('tapping a chip removes it', (tester) async {
    final updates = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagEditor(
          initial: const ['remove-me', 'keep'],
          suggestions: const [],
          onChanged: updates.add,
        ),
      ),
    ));
    await tester.tap(find.text('remove-me'));
    await tester.pump();
    expect(updates.last, equals(['keep']));
  });
}
```

- [ ] **Step 10b.2: Run test (expect fail)**

```
flutter test test/page/memory/tag_editor_test.dart
```
Expected: FAIL — `TagEditor` not found.

- [ ] **Step 10b.3: Implement `TagEditor`**

```dart
// lib/page/memory/widgets/tag_editor.dart
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TagEditor extends StatefulWidget {
  final List<String> initial;
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;

  const TagEditor({
    super.key,
    required this.initial,
    required this.suggestions,
    required this.onChanged,
  });

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  late List<String> _tags = List<String>.from(widget.initial);
  final _controller = TextEditingController();

  void _add(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty || _tags.contains(tag)) {
      _controller.clear();
      return;
    }
    setState(() {
      _tags = [..._tags, tag];
      _controller.clear();
    });
    widget.onChanged(_tags);
  }

  void _remove(String tag) {
    setState(() {
      _tags = _tags.where((t) => t != tag).toList();
    });
    widget.onChanged(_tags);
  }

  @override
  Widget build(BuildContext context) {
    final missingSuggestions = widget.suggestions
        .where((s) => !_tags.contains(s))
        .take(6)
        .toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in _tags) _chip(context, tag, selected: true),
        SizedBox(
          width: 140,
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            onSubmitted: _add,
            style: TextStyle(
              fontSize: 13,
              color: ClaudePalette.fg(context),
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add tag…',
              hintStyle: TextStyle(
                fontSize: 13,
                color: ClaudePalette.tertiary(context),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        for (final suggestion in missingSuggestions)
          _chip(context, suggestion, selected: false),
      ],
    );
  }

  Widget _chip(BuildContext context, String tag, {required bool selected}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          if (selected) {
            _remove(tag);
          } else {
            _add(tag);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? ClaudePalette.accentTint(context)
                : ClaudePalette.bg(context).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? ClaudePalette.accent(context).withValues(alpha: 0.35)
                  : ClaudePalette.divider(context),
              width: 0.5,
            ),
          ),
          child: Text(
            tag,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected
                  ? ClaudePalette.accent(context)
                  : ClaudePalette.secondary(context),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 10b.4: Run test (expect pass)**

```
flutter test test/page/memory/tag_editor_test.dart
```
Expected: PASS — 2 tests.

- [ ] **Step 10b.5: Commit**

```bash
git add lib/page/memory/widgets/tag_editor.dart test/page/memory/tag_editor_test.dart
git commit -m "feat(memory): TagEditor widget with inline autocomplete (B2)"
```

---

### Sub-task 10c: `MemoryBulkSelectionController`

**Files:**
- Create: `lib/page/memory/memory_bulk_selection_controller.dart`
- Test: `test/page/memory/memory_bulk_selection_controller_test.dart`

- [ ] **Step 10c.1: Write the failing test**

```dart
// test/page/memory/memory_bulk_selection_controller_test.dart
import 'package:papertok_reader/page/memory/memory_bulk_selection_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts out of selection mode and empty', () {
    final c = MemoryBulkSelectionController();
    expect(c.inSelectionMode, isFalse);
    expect(c.selected, isEmpty);
  });

  test('enter + toggle tracks ids and fires notifications', () {
    final c = MemoryBulkSelectionController();
    var notifications = 0;
    c.addListener(() => notifications++);

    c.enter(seedId: 'a');
    expect(c.inSelectionMode, isTrue);
    expect(c.selected, {'a'});

    c.toggle('b');
    expect(c.selected, {'a', 'b'});

    c.toggle('a');
    expect(c.selected, {'b'});
    expect(c.inSelectionMode, isTrue);
    expect(notifications, greaterThanOrEqualTo(3));
  });

  test('clearing exits selection mode', () {
    final c = MemoryBulkSelectionController();
    c.enter(seedId: 'a');
    c.clear();
    expect(c.inSelectionMode, isFalse);
    expect(c.selected, isEmpty);
  });

  test('selectAll merges ids', () {
    final c = MemoryBulkSelectionController();
    c.enter(seedId: 'a');
    c.selectAll(['b', 'c']);
    expect(c.selected, {'a', 'b', 'c'});
  });
}
```

- [ ] **Step 10c.2: Run test (expect fail)**

```
flutter test test/page/memory/memory_bulk_selection_controller_test.dart
```
Expected: FAIL — `MemoryBulkSelectionController` not found.

- [ ] **Step 10c.3: Implement the controller**

```dart
// lib/page/memory/memory_bulk_selection_controller.dart
import 'package:flutter/foundation.dart';

/// Small state holder for multi-select mode on the Memory browse/inbox
/// surfaces. Kept as a plain ChangeNotifier so it can be scoped to any
/// State or Riverpod provider without committing to one pattern.
class MemoryBulkSelectionController extends ChangeNotifier {
  final Set<String> _selected = <String>{};
  bool _inSelectionMode = false;

  bool get inSelectionMode => _inSelectionMode;
  Set<String> get selected => Set.unmodifiable(_selected);
  int get selectionCount => _selected.length;

  /// Enters selection mode. If [seedId] is provided, it is added as the
  /// first selected item (used by long-press gestures).
  void enter({String? seedId}) {
    _inSelectionMode = true;
    if (seedId != null) {
      _selected.add(seedId);
    }
    notifyListeners();
  }

  void toggle(String id) {
    if (_selected.contains(id)) {
      _selected.remove(id);
    } else {
      _selected.add(id);
    }
    if (_selected.isEmpty) {
      // Keep selection mode active — the caller is responsible for
      // calling clear() when the user is done. This matches iOS mail.
    }
    notifyListeners();
  }

  void selectAll(Iterable<String> ids) {
    _selected.addAll(ids);
    _inSelectionMode = true;
    notifyListeners();
  }

  void clear() {
    _selected.clear();
    _inSelectionMode = false;
    notifyListeners();
  }
}
```

- [ ] **Step 10c.4: Run test (expect pass)**

```
flutter test test/page/memory/memory_bulk_selection_controller_test.dart
```
Expected: PASS — 4 tests.

- [ ] **Step 10c.5: Commit**

```bash
git add lib/page/memory/memory_bulk_selection_controller.dart test/page/memory/memory_bulk_selection_controller_test.dart
git commit -m "feat(memory): MemoryBulkSelectionController for multi-select mode (B2)"
```

---

### Sub-task 10d: `MemoryDetailPage`

**Files:**
- Create: `lib/page/memory/memory_detail_page.dart`
- Modify: `lib/page/memory/memory_home_page.dart` (wire tap → detail push)

- [ ] **Step 10d.1: Implement the detail page**

```dart
// lib/page/memory/memory_detail_page.dart
import 'dart:io';

import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/memory/widgets/tag_editor.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class MemoryDetailPage extends StatefulWidget {
  final MemoryEntryRef entry;
  final MarkdownMemoryStore store;
  final List<String> allKnownTags;

  const MemoryDetailPage({
    super.key,
    required this.entry,
    required this.store,
    required this.allKnownTags,
  });

  @override
  State<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends State<MemoryDetailPage> {
  late Future<_DetailState> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _load();
  }

  Future<_DetailState> _load() async {
    final file = File(widget.entry.path);
    final raw = file.existsSync() ? await file.readAsString() : '';
    final body = _stripFrontMatter(raw);
    final tags = await widget.store.readEntryTags(widget.entry.path);
    return _DetailState(body: body, tags: tags);
  }

  String _stripFrontMatter(String content) {
    if (!content.startsWith('---\n')) return content;
    final endIdx = content.indexOf('\n---\n', 4);
    if (endIdx == -1) return content;
    return content.substring(endIdx + 5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.title)),
      body: FutureBuilder<_DetailState>(
        future: _loader,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TagEditor(
                  initial: data.tags,
                  suggestions: widget.allKnownTags,
                  onChanged: (updated) async {
                    await widget.store.writeEntryTags(widget.entry.path, updated);
                  },
                ),
              ),
              Divider(
                color: ClaudePalette.divider(context),
                thickness: 0.5,
                height: 24,
              ),
              MarkdownBody(
                data: data.body,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: ClaudePalette.fg(context),
                  ),
                  h1: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ClaudePalette.fg(context),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailState {
  final String body;
  final List<String> tags;
  const _DetailState({required this.body, required this.tags});
}
```

(If the codebase already has a styled-markdown widget, replace `MarkdownBody` with it — grep `StyledMarkdown` first.)

- [ ] **Step 10d.2: Wire `MemoryHomePage` row taps to push the detail page**

In `lib/page/memory/memory_home_page.dart`, inside the `FutureBuilder<List<MemoryEntryRef>>` section callbacks (Task 8), replace the `onTap` no-op with:

```dart
onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MemoryDetailPage(
        entry: entry,
        store: store,
        allKnownTags: allKnownTags,
      ),
    ),
  );
},
```

Where `store` is the singleton `MarkdownMemoryStore` and `allKnownTags` is the union of tags across all currently-loaded entries (compute inside `FutureBuilder`).

- [ ] **Step 10d.3: Run analyzer**

```
FLUTTER_NO_PUB=1 flutter analyze --no-pub lib/page/memory/
```
Expected: 0 new errors.

- [ ] **Step 10d.4: Commit**

```bash
git add lib/page/memory/memory_detail_page.dart lib/page/memory/memory_home_page.dart
git commit -m "feat(memory): MemoryDetailPage with inline tag editor (B2)"
```

---

### Sub-task 10e: Long-press → selection mode + multi-select toolbar

**Files:**
- Modify: `lib/page/memory/widgets/memory_row.dart`
- Modify: `lib/page/memory/memory_home_page.dart`

- [ ] **Step 10e.1: Extend `MemoryRow` with selection semantics**

Add optional selection props to `MemoryRow`:

```dart
class MemoryRow extends StatelessWidget {
  final MemoryEntryRef entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;

  const MemoryRow({
    super.key,
    required this.entry,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? ClaudePalette.accentTint(context)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected
                        ? ClaudePalette.accent(context)
                        : ClaudePalette.tertiary(context),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ClaudePalette.fg(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: ClaudePalette.secondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 10e.2: Wire the controller into `MemoryHomePage`**

Convert `MemoryHomePage` to a `ConsumerStatefulWidget` (if not already). Hold a `MemoryBulkSelectionController` in state:

```dart
class _MemoryHomePageState extends ConsumerState<MemoryHomePage> {
  final _bulk = MemoryBulkSelectionController();

  @override
  void initState() {
    super.initState();
    _bulk.addListener(_onBulkChange);
  }

  @override
  void dispose() {
    _bulk.removeListener(_onBulkChange);
    _bulk.dispose();
    super.dispose();
  }

  void _onBulkChange() => setState(() {});
```

In the AppBar, swap the title for a selection-aware variant:

```dart
appBar: AppBar(
  title: Text(_bulk.inSelectionMode
      ? '${_bulk.selectionCount} selected'
      : L10n.of(context).memoryTabTitle),
  leading: _bulk.inSelectionMode
      ? IconButton(
          icon: const Icon(Icons.close),
          onPressed: _bulk.clear,
        )
      : null,
  actions: _bulk.inSelectionMode
      ? [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _bulk.selectionCount == 0
                ? null
                : () => _confirmDelete(context),
          ),
          IconButton(
            icon: const Icon(Icons.label_outline),
            onPressed: _bulk.selectionCount == 0
                ? null
                : () => _showAddTagSheet(context),
          ),
        ]
      : [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {/* search hookup */},
          ),
        ],
),
```

In each rendered row, pass the selection state and long-press handler:

```dart
MemoryRow(
  entry: entry,
  selectionMode: _bulk.inSelectionMode,
  selected: _bulk.selected.contains(entry.path),
  onTap: () {
    if (_bulk.inSelectionMode) {
      _bulk.toggle(entry.path);
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MemoryDetailPage(
          entry: entry,
          store: store,
          allKnownTags: allKnownTags,
        ),
      ));
    }
  },
  onLongPress: () {
    HapticFeedback.mediumImpact();
    _bulk.enter(seedId: entry.path);
  },
),
```

Define `_confirmDelete` using `PTDialog.show` with `destructive: true`, and `_showAddTagSheet` using `PTBottomSheet.show` with a single `TagEditor` bound to the selected ids.

- [ ] **Step 10e.3: Smoke test manually**

```
flutter run -d <device>
```
Expected: long-press on a memory row → AppBar flips to "N selected" with close + delete + label actions. Tapping row adds/removes from selection. Close button exits selection mode.

- [ ] **Step 10e.4: Commit**

```bash
git add lib/page/memory/widgets/memory_row.dart lib/page/memory/memory_home_page.dart
git commit -m "feat(memory): long-press multi-select + bulk toolbar (B2)"
```

---

## Task 11: Surface `triggerKind` + confidence + rationale on inbox rows (B3)

**Files:**
- Modify: `lib/page/settings_page/memory.dart`
- Modify: `lib/service/memory/memory_session_digest_service.dart`
- Test: `test/service/memory/memory_rationale_test.dart`

- [ ] **Step 11.1: Write rationale generation test**

```dart
// test/service/memory/memory_rationale_test.dart
import 'package:papertok_reader/service/memory/memory_session_digest_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session digest rationale mentions message count', () {
    final r = MemorySessionDigestService.buildRationale(
      messageCount: 8,
      triggerKind: 'session_digest',
      confidence: 0.7,
    );
    expect(r, contains('8'));
  });

  test('provider switch rationale is distinct', () {
    final r = MemorySessionDigestService.buildRationale(
      messageCount: 2,
      triggerKind: 'provider_switch',
      confidence: 0.5,
    );
    expect(r.toLowerCase(), contains('provider'));
  });
}
```

- [ ] **Step 11.2: Run test (expect fail)**

```
flutter test test/service/memory/memory_rationale_test.dart
```

- [ ] **Step 11.3: Implement `buildRationale`**

```dart
// in lib/service/memory/memory_session_digest_service.dart
static String buildRationale({
  required int messageCount,
  required String triggerKind,
  required double? confidence,
}) {
  switch (triggerKind) {
    case 'provider_switch':
      return 'Captured because you switched providers mid-conversation ($messageCount messages so far).';
    case 'session_digest':
    default:
      return 'Session-end digest of $messageCount messages (confidence ${(confidence ?? 0).toStringAsFixed(2)}).';
  }
}
```

Wire `buildCandidate` (Task 4) to pass `rationale: buildRationale(...)`.

- [ ] **Step 11.4: Run test (expect pass)**

```
flutter test test/service/memory/memory_rationale_test.dart
```

- [ ] **Step 11.5: Add trigger badge + confidence dot to inbox row UI**

In `lib/page/settings_page/memory.dart`, below the inbox row title, add:

```dart
Row(
  children: [
    _TriggerBadge(kind: candidate.triggerKind ?? 'manual'),
    const SizedBox(width: 6),
    _ConfidenceDot(value: candidate.confidence ?? 0),
    if (candidate.rationale != null) ...[
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          candidate.rationale!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: ClaudePalette.tertiary(context),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    ],
  ],
),
```

Define `_TriggerBadge` and `_ConfidenceDot` as small private widgets in the same file. Trigger colors come from a local map keyed by kind. Confidence dot: `value >= 0.8 ? green : value >= 0.5 ? amber : gray`, where the three colors are `MorandiPalette.success`, `MorandiPalette.warning`, `ClaudePalette.tertiary`.

- [ ] **Step 11.6: Commit**

```bash
git add lib/service/memory/memory_session_digest_service.dart lib/page/settings_page/memory.dart test/service/memory/memory_rationale_test.dart
git commit -m "feat(memory): surface trigger + confidence + rationale (B3)"
```

---

## Task 12: Per-rule prefs + toggles in Settings

**Files:**
- Create: `lib/service/memory/memory_rule_prefs.dart`
- Modify: `lib/page/settings_page/memory.dart`
- Test: `test/service/memory/memory_rule_prefs_test.dart`

- [ ] **Step 12.1: Write prefs helper test**

```dart
import 'package:papertok_reader/service/memory/memory_rule_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('isRuleEnabled defaults to true', () async {
    await MemoryRulePrefs.init();
    expect(MemoryRulePrefs.isEnabled('session_digest'), isTrue);
    expect(MemoryRulePrefs.isEnabled('provider_switch'), isTrue);
  });

  test('setEnabled persists and readback works', () async {
    SharedPreferences.setMockInitialValues({});
    await MemoryRulePrefs.init();
    await MemoryRulePrefs.setEnabled('session_digest', false);
    expect(MemoryRulePrefs.isEnabled('session_digest'), isFalse);
  });
}
```

- [ ] **Step 12.2: Run test (expect fail)**

- [ ] **Step 12.3: Implement helper**

```dart
// lib/service/memory/memory_rule_prefs.dart
import 'package:shared_preferences/shared_preferences.dart';

class MemoryRulePrefs {
  static late SharedPreferences _prefs;
  static const _prefix = 'memoryRule.';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static bool isEnabled(String ruleId) {
    return _prefs.getBool('$_prefix$ruleId') ?? true;
  }

  static Future<void> setEnabled(String ruleId, bool value) async {
    await _prefs.setBool('$_prefix$ruleId', value);
  }
}
```

Call `MemoryRulePrefs.init()` once at app boot (add to `main.dart` near the other `initPrefs` calls).

- [ ] **Step 12.4: Gate rule execution in `captureSessionDigest`**

In `memory_workflow_service.dart`, before the `session_digest` branch:

```dart
if (!MemoryRulePrefs.isEnabled('session_digest')) {
  return;
}
```

Same for `provider_switch` in the provider-switch capture site.

- [ ] **Step 12.5: Add the Settings UI section**

In `lib/page/settings_page/memory.dart`, append a new `SettingsSectionCard` titled "Auto-capture rules" with tiles:

```dart
SettingsSectionCard(
  title: L10n.of(context).memoryAutoCaptureRulesTitle,
  tiles: [
    _RuleToggleRow(
      ruleId: 'session_digest',
      title: L10n.of(context).memoryRuleSessionDigestTitle,
      description: L10n.of(context).memoryRuleSessionDigestDesc,
    ),
    _RuleToggleRow(
      ruleId: 'provider_switch',
      title: L10n.of(context).memoryRuleProviderSwitchTitle,
      description: L10n.of(context).memoryRuleProviderSwitchDesc,
    ),
  ],
),
```

Define `_RuleToggleRow` as a private stateful widget in the same file that reads `MemoryRulePrefs.isEnabled(ruleId)`, writes via `setEnabled`, and shows a tappable `?` icon that opens a tooltip `PTDialog` with the full rationale paragraph.

- [ ] **Step 12.6: Add L10n keys + translations**

```json
"memoryAutoCaptureRulesTitle": "Auto-capture rules",
"memoryRuleSessionDigestTitle": "Session digest",
"memoryRuleSessionDigestDesc": "Capture up to 3 memories when a chat session ends.",
"memoryRuleProviderSwitchTitle": "Provider switch",
"memoryRuleProviderSwitchDesc": "Capture a digest when you switch AI providers mid-conversation."
```

- [ ] **Step 12.7: Run tests**

```
flutter test test/service/memory/memory_rule_prefs_test.dart
flutter test test/service/memory/
```
Expected: PASS.

- [ ] **Step 12.8: Commit**

```bash
git add lib/service/memory/memory_rule_prefs.dart lib/service/memory/memory_workflow_service.dart lib/page/settings_page/memory.dart lib/l10n/ lib/main.dart test/service/memory/memory_rule_prefs_test.dart
git commit -m "feat(memory): per-rule prefs + settings toggles (B3)"
```

---

## Task 13: Final integration smoke test + TestFlight

**Files:** none

- [ ] **Step 13.1: Run full test suite**

```
flutter test
```
Expected: all PASS.

- [ ] **Step 13.2: Run analyzer**

```
FLUTTER_NO_PUB=1 flutter analyze --no-pub lib/
```
Expected: 0 NEW errors.

- [ ] **Step 13.3: Manual smoke on device**

1. Open app → verify 6-tab bottom nav, Memory icon visible
2. Open a book, ask AI a question, end session → verify candidate shows up with `sourceKind: reading` and bookId populated
3. Tap "Open in reader" on the candidate → should navigate back to the correct book at the correct cfi
4. Navigate to Memory tab → verify Inbox count badge matches pending count
5. Tap inbox row → open, verify rationale text visible below title
6. Long-press a memory row → enter selection mode, verify toolbar appears
7. Settings → Memory → Auto-capture rules → toggle session_digest off → end another session → verify no candidate created

- [ ] **Step 13.4: Push + TF upload**

```bash
git push origin main
FLUTTER_NO_PUB=true FORCE_MANUAL_SIGNING=1 ./scripts/tf_from_commit.sh HEAD > /tmp/tf_memory.log 2>&1 &
```

- [ ] **Step 13.5: Verify upload**

```
grep "Successfully uploaded" /tmp/tf_memory.log
```

---

## Self-Review

**Spec coverage**

- B1 source jump-back → Tasks 1–5 (enum, schema, migration, capture rule, navigation)
- B2 top-level destination → Tasks 6–10 (store helpers, page shell, rows, nav tab, detail + tags + bulk)
- B3 explainable auto-write → Tasks 11–12 (rationale generation, UI surfacing, per-rule prefs)
- Migration strategy → Task 3 (v2 write + v1 read fallback)
- Testing strategy → tests in Tasks 1, 2, 3, 4, 6, 7, 8, 10, 11, 12, plus integration smoke in Task 13

**Placeholder scan** — None. Every step has concrete code or concrete commands. Task 10 sub-steps are a deliberate decomposition rather than placeholders — each sub-step follows the same TDD rhythm with its own test and commit.

**Type consistency** — `MemoryCandidate`, `MemorySourceKind`, `MemoryEntryRef`, `MemoryRulePrefs`, `MemoryHomePage`, `MemoryBulkSelectionController` are named consistently across all tasks. Method names (`readAll`, `writeAll`, `listLongTermEntries`, `listRecentDailyNotes`, `buildCandidate`, `buildRationale`, `isEnabled`, `setEnabled`, `openInReader`, `openInConversation`) are identical between definition and callers.

**Scope** — Single focused plan for the Memory v1 ship; bounded to three internally-coupled features. A2 (Dart import rename) is explicitly NOT in scope — it's tracked as a separate follow-up.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-14-memory-completion.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task (or per task group), review between tasks, fast iteration. Tasks 6–10 (B2) can run in parallel with Tasks 11–12 (B3) because their files are disjoint.

**2. Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints for review.

**Which approach?**
