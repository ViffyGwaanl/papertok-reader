import 'dart:async';
import 'dart:collection';

import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/models/inline_fulltext_translation_progress.dart';
import 'package:anx_reader/service/translate/fulltext_translate_runtime.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class InlineFullTextTranslateBlock {
  const InlineFullTextTranslateBlock({required this.id, required this.text});

  final String id;
  final String text;

  static List<InlineFullTextTranslateBlock> parseList(Object? raw) {
    if (raw is! List) return const [];
    final out = <InlineFullTextTranslateBlock>[];
    for (final item in raw) {
      if (item is Map) {
        final id = item['id']?.toString() ?? '';
        final text = item['text']?.toString() ?? '';
        if (id.isEmpty || text.trim().isEmpty) continue;
        out.add(InlineFullTextTranslateBlock(id: id, text: text));
      }
    }
    return out;
  }
}

class InlineFullTextTranslateEngine {
  InlineFullTextTranslateEngine({
    required this.progress,
    required this.maxConcurrency,
  });

  final ValueNotifier<InlineFullTextTranslationProgress> progress;
  final int maxConcurrency;

  int _generation = 0;
  bool _disposed = false;

  int _inflight = 0;

  Future<void> submit({
    required InAppWebViewController webViewController,
    required int bookId,
    required TranslateService service,
    required LangListEnum from,
    required LangListEnum to,
    required List<InlineFullTextTranslateBlock> blocks,
  }) async {
    if (_disposed) return;
    if (blocks.isEmpty) return;

    final gen = ++_generation;

    // Reset progress for this viewport batch.
    progress.value = InlineFullTextTranslationProgress(
      active: true,
      total: blocks.length,
      pending: blocks.length,
      inflight: 0,
      done: 0,
      failed: 0,
      generation: gen,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final sem = _Semaphore(maxConcurrency);

    // Fire tasks; no need to await them here.
    // ignore: discarded_futures
    () async {
      for (final block in blocks) {
        if (_disposed || gen != _generation) {
          // generation moved; stop scheduling further tasks.
          break;
        }

        // ignore: discarded_futures
        sem.withPermit(() async {
          if (_disposed || gen != _generation) return;

          _inflight++;
          _update(gen, pendingDelta: -1, inflightDelta: 1);

          try {
            final translated = await FullTextTranslateRuntime.instance.translate(
              service,
              block.text,
              from,
              to,
              bookId: bookId,
            );

            // Treat known error strings as failures (do not display in text).
            final t = translated.trim();
            final isError = t.toLowerCase().startsWith('error:') ||
                t.contains('AI service not configured') ||
                t.contains('AI 服务未配置') ||
                t.contains('Authentication failed');

            if (!isError && t.isNotEmpty && !_disposed && gen == _generation) {
              final js = '''
try {
  if (typeof reader !== 'undefined' && reader.view && reader.view.applyFullTextTranslation) {
    reader.view.applyFullTextTranslation(${_jsString(block.id)}, ${_jsString(translated)});
  }
} catch (e) {}
''';
              await webViewController.evaluateJavascript(source: js);
              _update(gen, doneDelta: 1);
            } else {
              _update(gen, failedDelta: 1);
            }
          } catch (_) {
            if (!_disposed && gen == _generation) {
              _update(gen, failedDelta: 1);
            }
          } finally {
            _inflight--;
            if (!_disposed && gen == _generation) {
              _update(gen, inflightDelta: -1);
            }
          }
        });
      }

      // When queue drained for current gen, mark inactive.
      // Wait a tiny bit for inflight completions.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!_disposed && gen == _generation) {
        final p = progress.value;
        if (p.pending <= 0 && p.inflight <= 0) {
          progress.value = p.copyWith(active: false);
        }
      }
    }();
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }

  void _update(
    int gen, {
    int pendingDelta = 0,
    int inflightDelta = 0,
    int doneDelta = 0,
    int failedDelta = 0,
  }) {
    if (_disposed) return;
    if (gen != _generation) return;

    final p = progress.value;
    progress.value = p.copyWith(
      pending: (p.pending + pendingDelta).clamp(0, 1 << 30),
      inflight: (p.inflight + inflightDelta).clamp(0, 1 << 30),
      done: (p.done + doneDelta).clamp(0, 1 << 30),
      failed: (p.failed + failedDelta).clamp(0, 1 << 30),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

String _jsString(String s) {
  // Minimal JS string literal escaping using JSON rules.
  // We embed it directly into JS source as a string literal.
  final escaped = s
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t')
      .replaceAll('"', r'\"')
      .replaceAll("'", r"\\'");
  return '"$escaped"';
}

class _Semaphore {
  _Semaphore(this._max);

  final int _max;
  int _current = 0;
  final Queue<Completer<void>> _queue = Queue();

  Future<T> withPermit<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_current < _max) {
      _current++;
      return Future.value();
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future.then((_) {
      _current++;
    });
  }

  void _release() {
    _current--;
    if (_current < 0) _current = 0;
    if (_queue.isNotEmpty && _current < _max) {
      final next = _queue.removeFirst();
      if (!next.isCompleted) next.complete();
    }
  }
}
