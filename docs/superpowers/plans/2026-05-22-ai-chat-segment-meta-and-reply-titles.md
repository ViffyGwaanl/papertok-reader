# AI Chat Segment Meta + Reply-Based Titles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show per-segment model + token usage at the end of each AI assistant reply (persisted), and derive conversation titles from the first AI reply instead of the user question.

**Architecture:** Store per-segment metadata (`model`, `inputTokens`, `outputTokens`) on each `AiConversationNode` so it serializes with `conversationV2` and survives reload. Capture model at send time and compute per-turn token delta from the session-cumulative `AiUsageTracker` on stream finalize. Render a small muted footer per assistant message; the last assistant message also shows the session cumulative. Title generation (both heuristic fallback and LLM transcript) switches to the first `AIChatMessage`.

**Tech Stack:** Flutter, Dart, Riverpod, langchain_core (`ChatMessage`/`AIChatMessage`), `flutter_test`.

---

## File Structure

- `lib/models/ai_conversation_tree.dart` — add `AiSegmentMeta` value class + `meta` field on `AiConversationNode` (data + serialization).
- `lib/service/ai/ai_usage_tracker.dart` — expose token-count formatter for reuse.
- `lib/providers/ai_chat.dart` — capture model + token snapshot, write `meta` to assistant node on finalize, add `segmentMetaForMessageIndex`.
- `lib/widgets/ai/ai_chat_stream.dart` — render per-segment footer, remove input-box token chip, switch `_deriveTitle` to first AI reply.
- `lib/service/ai/conversation_title_service.dart` — `deriveFallbackTitle` + `_buildTranscript` switch to first AI reply.
- Tests: `test/models/ai_conversation_tree_meta_test.dart` (new), `test/service/conversation_title_service_test.dart` (update).

---

## Task 1: `AiSegmentMeta` data model + node serialization

**Files:**
- Modify: `lib/models/ai_conversation_tree.dart`
- Test: `test/models/ai_conversation_tree_meta_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/models/ai_conversation_tree_meta_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';

void main() {
  group('AiSegmentMeta', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      const meta = AiSegmentMeta(
        model: 'gpt-4o',
        inputTokens: 320,
        outputTokens: 880,
      );
      final restored = AiSegmentMeta.fromJson(meta.toJson());
      expect(restored.model, 'gpt-4o');
      expect(restored.inputTokens, 320);
      expect(restored.outputTokens, 880);
    });

    test('fromJson tolerates missing fields', () {
      final restored = AiSegmentMeta.fromJson(const {'model': 'claude'});
      expect(restored.model, 'claude');
      expect(restored.inputTokens, isNull);
      expect(restored.outputTokens, isNull);
    });

    test('footerText formats model and tokens, omitting null parts', () {
      const full = AiSegmentMeta(
        model: 'gpt-4o',
        inputTokens: 320,
        outputTokens: 880,
      );
      expect(full.footerText(), 'gpt-4o · 1.2K tok (320 in / 880 out)');

      const modelOnly = AiSegmentMeta(model: 'claude');
      expect(modelOnly.footerText(), 'claude');

      const empty = AiSegmentMeta();
      expect(empty.footerText(), '');
    });
  });

  group('AiConversationNode meta serialization', () {
    test('meta survives toJson/fromJson', () {
      const node = AiConversationNode(
        id: 'n1',
        parentId: 'root',
        children: <String>[],
        activeChildId: null,
        message: {'type': 'ai', 'content': 'hi', 'toolCalls': <dynamic>[]},
        createdAt: 1,
        updatedAt: 1,
        meta: AiSegmentMeta(model: 'm', inputTokens: 5, outputTokens: 7),
      );
      final restored =
          AiConversationNode.fromJson('n1', node.toJson());
      expect(restored.meta?.model, 'm');
      expect(restored.meta?.inputTokens, 5);
      expect(restored.meta?.outputTokens, 7);
    });

    test('node without meta deserializes meta as null (backward compatible)', () {
      final restored = AiConversationNode.fromJson('n1', const {
        'parentId': 'root',
        'children': <dynamic>[],
        'activeChildId': null,
        'message': {'type': 'ai', 'content': 'hi', 'toolCalls': <dynamic>[]},
        'createdAt': 1,
        'updatedAt': 1,
      });
      expect(restored.meta, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/ai_conversation_tree_meta_test.dart`
Expected: FAIL — `AiSegmentMeta` undefined and `AiConversationNode` has no `meta` parameter.

- [ ] **Step 3: Add `AiSegmentMeta` class**

In `lib/models/ai_conversation_tree.dart`, after the `AiConversationNode` class (end of file, after line 356), add:

```dart
/// Per-segment metadata captured for a single assistant turn.
///
/// Stored on the assistant [AiConversationNode] so it persists with the
/// conversation tree. All fields are optional for backward compatibility.
@immutable
class AiSegmentMeta {
  const AiSegmentMeta({
    this.model,
    this.inputTokens,
    this.outputTokens,
  });

  /// The model name used for this turn (e.g. `gpt-4o`).
  final String? model;

  /// Input tokens consumed by this turn (delta of the session tracker).
  final int? inputTokens;

  /// Output tokens produced by this turn (delta of the session tracker).
  final int? outputTokens;

  bool get isEmpty =>
      (model == null || model!.isEmpty) &&
      inputTokens == null &&
      outputTokens == null;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (model != null && model!.isNotEmpty) map['model'] = model;
    if (inputTokens != null) map['inputTokens'] = inputTokens;
    if (outputTokens != null) map['outputTokens'] = outputTokens;
    return map;
  }

  factory AiSegmentMeta.fromJson(Map<String, dynamic> json) {
    final rawIn = json['inputTokens'];
    final rawOut = json['outputTokens'];
    return AiSegmentMeta(
      model: json['model']?.toString(),
      inputTokens: rawIn is int ? rawIn : (rawIn is num ? rawIn.toInt() : null),
      outputTokens:
          rawOut is int ? rawOut : (rawOut is num ? rawOut.toInt() : null),
    );
  }

  /// One-line label for the per-segment footer. Returns '' when nothing to show.
  String footerText() {
    final parts = <String>[];
    if (model != null && model!.isNotEmpty) {
      parts.add(model!);
    }
    if (inputTokens != null || outputTokens != null) {
      final total = (inputTokens ?? 0) + (outputTokens ?? 0);
      final detail = StringBuffer('${_formatTokenCount(total)} tok');
      if (inputTokens != null && outputTokens != null) {
        detail.write(' ($inputTokens in / $outputTokens out)');
      }
      parts.add(detail.toString());
    }
    return parts.join(' · ');
  }

  static String _formatTokenCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}
```

- [ ] **Step 4: Add `meta` to `AiConversationNode`**

In the same file, modify `AiConversationNode` (lines 268-356):

Add to the constructor (after `required this.updatedAt,`):
```dart
    this.meta,
```

Add the field (after `final int updatedAt;`, around line 289):
```dart
  /// Per-segment metadata (model + token usage). Null for non-assistant nodes
  /// and legacy data created before this field existed.
  final AiSegmentMeta? meta;
```

In `toJson()` (lines 297-306), add before the closing `};`:
```dart
      if (meta != null) 'meta': meta!.toJson(),
```

In `fromJson` (lines 308-336), before the `return AiConversationNode(`:
```dart
    final rawMeta = json['meta'];
    AiSegmentMeta? meta;
    if (rawMeta is Map) {
      meta = AiSegmentMeta.fromJson(
        rawMeta.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
```
and add `meta: meta,` inside the returned constructor.

In `copyWith` (lines 338-355): add parameter `AiSegmentMeta? meta,` and `meta: meta ?? this.meta,` in the returned constructor.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/models/ai_conversation_tree_meta_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/models/ai_conversation_tree.dart test/models/ai_conversation_tree_meta_test.dart
git commit -m "feat(ai): add AiSegmentMeta to conversation tree nodes"
```

---

## Task 2: Capture model + token delta on finalize; expose `segmentMetaForMessageIndex`

**Files:**
- Modify: `lib/service/ai/ai_usage_tracker.dart`
- Modify: `lib/providers/ai_chat.dart`

- [ ] **Step 1: Expose token formatter on `AiUsageTracker`**

In `lib/service/ai/ai_usage_tracker.dart`, rename the private static `_formatTokenCount` (line 102) to a public `formatTokenCount` and update the two call sites (lines 76, 79). Replace lines 74-110:

```dart
  /// Short format for UI status bar.
  String toShortSummary() {
    if (_estimatedCostUsd > 0) {
      return '${formatTokenCount(totalTokens)} tokens · '
          '\$${_estimatedCostUsd.toStringAsFixed(3)}';
    }
    return '${formatTokenCount(totalTokens)} tokens';
  }

  double _calculateCost({
    required int inputTokens,
    required int outputTokens,
    required int cacheReadTokens,
    required int cacheWriteTokens,
    required AiModelPricing pricing,
  }) {
    final inputCost =
        (inputTokens - cacheReadTokens - cacheWriteTokens) *
            pricing.inputPerMillionTokens /
            1e6;
    final outputCost =
        outputTokens * pricing.outputPerMillionTokens / 1e6;
    final cacheReadCost =
        cacheReadTokens * pricing.cacheReadPerMillionTokens / 1e6;
    final cacheWriteCost =
        cacheWriteTokens * pricing.cacheWritePerMillionTokens / 1e6;
    return inputCost + outputCost + cacheReadCost + cacheWriteCost;
  }

  static String formatTokenCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
```

- [ ] **Step 2: Add draft capture fields**

In `lib/providers/ai_chat.dart`, after line 47 (`String? _draftAssistantNodeId;`) add:

```dart
  String _draftModel = '';
  int _draftTokenInSnapshot = 0;
  int _draftTokenOutSnapshot = 0;
```

- [ ] **Step 3: Snapshot model + tokens at generation start**

In `startStreaming`, just before `ref.read(aiChatStreamingProvider.notifier).setStreaming(true);` (line 290), add:

```dart
    _draftModel = model;
    final startTracker = getUsageTracker(sessionId);
    _draftTokenInSnapshot = startTracker?.inputTokens ?? 0;
    _draftTokenOutSnapshot = startTracker?.outputTokens ?? 0;
```

- [ ] **Step 4: Write `meta` to the assistant node in `_finalizeStreaming`**

In `_finalizeStreaming` (lines 343-372), replace the block from line 350 (`// Update token usage summary...`) through the `historyNotifier.upsert(finalEntry)` call (line 366) with:

```dart
    // Update token usage summary for UI display.
    final tracker = getUsageTracker(_currentSessionId);
    if (tracker != null && tracker.totalTokens > 0) {
      ref.read(aiChatUsageSummaryProvider.notifier).state =
          tracker.toShortSummary();
    }

    // Persist per-segment meta (model + this-turn token delta) on the
    // assistant node so it survives reload.
    final assistantId = _draftAssistantNodeId;
    if (assistantId != null && _tree.nodes.containsKey(assistantId)) {
      final node = _tree.nodes[assistantId]!;
      int? deltaIn;
      int? deltaOut;
      if (tracker != null) {
        final di = tracker.inputTokens - _draftTokenInSnapshot;
        final dout = tracker.outputTokens - _draftTokenOutSnapshot;
        deltaIn = di > 0 ? di : null;
        deltaOut = dout > 0 ? dout : null;
      }
      final meta = AiSegmentMeta(
        model: _draftModel.isEmpty ? null : _draftModel,
        inputTokens: deltaIn,
        outputTokens: deltaOut,
      );
      if (!meta.isEmpty) {
        _tree = _tree.copyWithNode(assistantId, node.copyWith(meta: meta));
      }
    }

    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    final draftEntry = _draftEntry;
    if (draftEntry != null) {
      final finalEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? const <ChatMessage>[]),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: completed,
        conversationV2: _tree.toJson(),
      );
      historyNotifier.upsert(finalEntry).catchError((_) {});
      unawaited(_refreshGeneratedTitle(finalEntry, historyNotifier));
    }
```

Note: this removes the now-duplicated `historyNotifier`/`draftEntry` declaration that previously followed (lines 357-368); the replacement above already includes them. Keep the trailing `_draftEntry = null; _draftAssistantNodeId = null;` lines (371-372).

- [ ] **Step 5: Add `segmentMetaForMessageIndex` to the notifier**

In `lib/providers/ai_chat.dart`, after `selectedVariantIndexForMessageIndex` (ends around line 600), add:

```dart
  /// Returns the persisted per-segment meta for the message at [messageIndex]
  /// on the active path, or null if none.
  AiSegmentMeta? segmentMetaForMessageIndex(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _activeNodeIds.length) {
      return null;
    }
    return _tree.nodes[_activeNodeIds[messageIndex]]?.meta;
  }
```

- [ ] **Step 6: Run codegen + analyze (no behavior tests at provider level)**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter analyze lib/providers/ai_chat.dart lib/service/ai/ai_usage_tracker.dart lib/models/ai_conversation_tree.dart`
Expected: no analyzer errors. (Token-delta math is covered indirectly; the pure formatting is tested in Task 1.)

- [ ] **Step 7: Commit**

```bash
git add lib/providers/ai_chat.dart lib/service/ai/ai_usage_tracker.dart
git commit -m "feat(ai): capture per-segment model and token delta on finalize"
```

---

## Task 3: Per-segment footer UI + remove input-box token chip

**Files:**
- Modify: `lib/widgets/ai/ai_chat_stream.dart`

- [ ] **Step 1: Add import for `AiSegmentMeta`/`AiUsageTracker` if missing**

Ensure these imports exist at the top of `lib/widgets/ai/ai_chat_stream.dart` (add if absent):
```dart
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/service/ai/ai_usage_tracker.dart';
```

- [ ] **Step 2: Render the footer in `_buildLinearMessageItem`**

In `_buildLinearMessageItem` (starts line 3220), inside the assistant branch (`!isUser`), after the message content/bubble and near the existing action row, add a footer line. Compute the per-segment meta and whether this is the last assistant message:

Within the method, before building the assistant column children, add:
```dart
    final notifier = ref.read(aiChatProvider.notifier);
    final segMeta = isUser ? null : notifier.segmentMetaForMessageIndex(index);
    final isLastAssistant = !isUser &&
        index == allMessages.lastIndexWhere((m) => m is AIChatMessage);
    final usageSummary = ref.watch(aiChatUsageSummaryProvider);
```

Then build the footer widget (place it directly under the assistant bubble content, above or alongside the existing copy/regenerate row):
```dart
    Widget? footer;
    if (!isUser) {
      final segText = segMeta?.footerText() ?? '';
      final cumulative = isLastAssistant && (usageSummary ?? '').trim().isNotEmpty
          ? '会话累计 $usageSummary'
          : '';
      final pieces = [segText, cumulative].where((s) => s.isNotEmpty).toList();
      if (pieces.isNotEmpty) {
        footer = Padding(
          padding: const EdgeInsets.only(top: 2, left: 2),
          child: Text(
            pieces.join('  ·  '),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        );
      }
    }
```

Insert the footer as the last child of the `Column` at line 3264 (which holds `_buildScaledMessageContent(...)` then the action `Row`). After the action `Row(...)` closing `),` (line 3314), add:
```dart
                  if (footer != null) footer,
```
Since the footer is only built for `!isUser`, user messages are unaffected.

- [ ] **Step 3: Remove the token chip from the input box**

In the input-box area (lines 2616-2653), change the condition so only `contextNotice` controls the box, and drop the usage portion. Replace lines 2616-2653 with:

```dart
              if ((contextNotice ?? '').trim().isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    contextNotice!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
```

(The `usageSummary` variable read at line 2327 may now be unused in this scope; leave it only if still referenced, otherwise remove that local read to satisfy the analyzer.)

- [ ] **Step 4: Analyze + manual verification**

Run: `flutter analyze lib/widgets/ai/ai_chat_stream.dart`
Expected: no errors (resolve any unused-variable warning from the removed chip).

Manual (run app — see Step 6): send a turn; confirm a small grey line `模型名 · 1.2K tok (320 in / 880 out)` appears under each assistant reply, the last one also shows `会话累计 ...`, and the input box no longer shows a token chip (context notice still appears when trimming).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/ai/ai_chat_stream.dart
git commit -m "feat(ai): show per-segment model/token footer; move token stat off input bar"
```

- [ ] **Step 6: Run the app to verify (golden + edge paths)**

Run: `flutter run -d macos` (or an attached device). Verify: (a) fresh turn shows footer; (b) reopen the conversation from history → footer persists; (c) a legacy conversation (no meta) shows no footer and does not crash.

---

## Task 4: Title from first AI reply (service)

**Files:**
- Modify: `lib/service/ai/conversation_title_service.dart`
- Test: `test/service/conversation_title_service_test.dart`

- [ ] **Step 1: Update + add failing tests**

Replace the body of `test/service/conversation_title_service_test.dart` `main()` tests (lines 18-41) with:

```dart
  test('deriveFallbackTitle uses first AI reply line, not the question', () {
    const service = ConversationTitleService();
    final title = service.deriveFallbackTitle(const [
      HumanChatMessage(
        content: ChatMessageContentText(text: '怎么做 Memory workflow？'),
      ),
      AIChatMessage(content: 'Memory workflow 分三步。\n第二行'),
    ]);

    expect(title, 'Memory workflow 分三步');
  });

  test('deriveFallbackTitle returns Conversation when no AI reply', () {
    const service = ConversationTitleService();
    final title = service.deriveFallbackTitle(const [
      HumanChatMessage(
        content: ChatMessageContentText(text: '只有提问'),
      ),
    ]);

    expect(title, 'Conversation');
  });

  test('generateTitle falls back to first AI reply when disabled', () async {
    const service = ConversationTitleService();
    final title = await service.generateTitle(const [
      HumanChatMessage(
        content: ChatMessageContentText(text: '给这段对话起一个标题'),
      ),
      AIChatMessage(content: '好的，这是关于 RAG 的讨论'),
    ]);

    expect(title, '好的，这是关于 RAG 的讨论');
  });
```

Note: the disabled-title test seeds `aiTitleMaxCharsV1: 16`; `'好的，这是关于 RAG 的讨论'` is 15 chars, within the limit. Keep the existing `setUp` block.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/service/conversation_title_service_test.dart`
Expected: FAIL — current `deriveFallbackTitle` returns the human question.

- [ ] **Step 3: Switch `deriveFallbackTitle` to first AI reply**

In `lib/service/ai/conversation_title_service.dart`, replace `deriveFallbackTitle` (lines 73-88) with:

```dart
  String deriveFallbackTitle(List<ChatMessage> messages) {
    for (final message in messages) {
      if (message is! AIChatMessage) {
        continue;
      }
      final text = message.contentAsString.trim();
      if (text.isEmpty) {
        continue;
      }
      final firstLine = text.split('\n').first.trim();
      if (firstLine.isNotEmpty) {
        return _sanitizeTitle(firstLine, Prefs().aiTitleMaxChars);
      }
    }
    return 'Conversation';
  }
```

- [ ] **Step 4: Focus the LLM transcript on the first AI reply**

Replace `_buildTranscript` (lines 90-117) with:

```dart
  String _buildTranscript(List<ChatMessage> messages) {
    for (final message in messages) {
      if (message is! AIChatMessage) {
        continue;
      }
      final text = message.contentAsString.trim();
      if (text.isEmpty) continue;
      return text.length <= 1600 ? text : text.substring(0, 1600);
    }
    return '';
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/service/conversation_title_service_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/service/ai/conversation_title_service.dart test/service/conversation_title_service_test.dart
git commit -m "feat(ai): derive conversation title from first AI reply"
```

---

## Task 5: UI title fallback (`_deriveTitle`) → first AI reply

**Files:**
- Modify: `lib/widgets/ai/ai_chat_stream.dart`

- [ ] **Step 1: Switch `_deriveTitle` to first AI reply**

In `lib/widgets/ai/ai_chat_stream.dart`, replace `_deriveTitle` (lines 1051-1069) entirely with (keeps the `stored` short-circuit and the exact original final return literals, only the fallback loop switches from first `HumanChatMessage` to first `AIChatMessage`):

```dart
  String _deriveTitle(AiChatHistoryEntry entry) {
    final stored = (entry.title ?? '').trim();
    if (stored.isNotEmpty) {
      return stored;
    }
    for (final message in entry.messages) {
      if (message is AIChatMessage) {
        final content = message.contentAsString.trim();
        if (content.isNotEmpty) {
          final firstLine = content.split('\n').first.trim();
          return firstLine;
        }
      }
    }
    if (entry.messages.isNotEmpty) {
      return 'Conversation';
    }
    return 'Empty conversation';
  }
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/widgets/ai/ai_chat_stream.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/ai/ai_chat_stream.dart
git commit -m "feat(ai): UI title fallback uses first AI reply"
```

---

## Final Verification

- [ ] Run full affected tests: `flutter test test/models/ai_conversation_tree_meta_test.dart test/service/conversation_title_service_test.dart`
- [ ] Run analyzer on all touched files: `flutter analyze lib/models/ai_conversation_tree.dart lib/service/ai/ai_usage_tracker.dart lib/providers/ai_chat.dart lib/widgets/ai/ai_chat_stream.dart lib/service/ai/conversation_title_service.dart`
- [ ] Manual app run: new conversation → footer per segment + cumulative on last; reopen → persists; legacy conversation → no footer, no crash; title reflects first AI reply with LLM title gen both on and off; input bar has no token chip but still shows context-trim notice.
