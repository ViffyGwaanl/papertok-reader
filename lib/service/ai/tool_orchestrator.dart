import 'dart:async';

import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:langchain/langchain.dart';

/// Result of a single tool execution within the orchestrator.
class OrchestratedToolResult {
  const OrchestratedToolResult({
    required this.action,
    required this.observation,
    required this.isError,
    required this.durationMs,
  });

  final AgentAction action;
  final String observation;
  final bool isError;
  final int durationMs;
}

/// Executes a batch of tool calls with concurrency-aware scheduling.
///
/// Inspired by Claude Code's `toolOrchestration.ts`:
/// - Consecutive concurrency-safe tools run in parallel.
/// - Non-concurrent-safe tools run one at a time.
/// - Results are yielded in original order regardless of completion order.
///
/// Maximum concurrency is capped at [maxConcurrency].
class ToolOrchestrator {
  const ToolOrchestrator({this.maxConcurrency = 5});

  final int maxConcurrency;

  /// Execute [actions] using tools from [toolMap], respecting concurrency.
  ///
  /// Yields [OrchestratedToolResult] in the original order of [actions].
  Stream<OrchestratedToolResult> execute(
    List<AgentAction> actions,
    Map<String, Tool> toolMap,
    Future<String> Function(AgentAction action, Tool tool) executeSingle,
  ) async* {
    if (actions.isEmpty) return;

    // Partition into batches: consecutive concurrency-safe tools form one
    // parallel batch; each non-concurrent-safe tool gets its own serial batch.
    final batches = _partition(actions);

    for (final batch in batches) {
      if (batch.length == 1 || !batch.first.isConcurrencySafe) {
        // Serial execution
        for (final entry in batch) {
          yield await _executeSingle(entry.action, toolMap, executeSingle);
        }
      } else {
        // Parallel execution with concurrency limit
        final futures = <Future<OrchestratedToolResult>>[];
        final semaphore = _Semaphore(maxConcurrency);

        for (final entry in batch) {
          futures.add(
            semaphore.run(
              () => _executeSingle(entry.action, toolMap, executeSingle),
            ),
          );
        }

        final results = await Future.wait(futures);
        for (final result in results) {
          yield result;
        }
      }
    }
  }

  List<List<_BatchEntry>> _partition(List<AgentAction> actions) {
    final batches = <List<_BatchEntry>>[];
    List<_BatchEntry>? currentBatch;
    bool? currentIsConcurrent;

    for (final action in actions) {
      final isSafe = AiToolRegistry.isConcurrencySafeForId(action.tool);

      if (currentBatch == null ||
          currentIsConcurrent != isSafe ||
          !isSafe) {
        // Start a new batch when:
        // - first action
        // - concurrency type changed
        // - current action is non-concurrent (each gets its own batch)
        currentBatch = [];
        batches.add(currentBatch);
        currentIsConcurrent = isSafe;
      }

      currentBatch.add(_BatchEntry(action: action, isConcurrencySafe: isSafe));
    }

    return batches;
  }

  Future<OrchestratedToolResult> _executeSingle(
    AgentAction action,
    Map<String, Tool> toolMap,
    Future<String> Function(AgentAction action, Tool tool) executeSingle,
  ) async {
    final tool = toolMap[action.tool];
    if (tool == null) {
      return OrchestratedToolResult(
        action: action,
        observation: 'Error: Unknown tool "${action.tool}"',
        isError: true,
        durationMs: 0,
      );
    }

    final sw = Stopwatch()..start();
    try {
      final result = await executeSingle(action, tool);
      sw.stop();
      AnxLog.info(
        'ToolOrchestrator: ${action.tool} completed in ${sw.elapsedMilliseconds}ms',
      );
      return OrchestratedToolResult(
        action: action,
        observation: result,
        isError: false,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (error) {
      sw.stop();
      AnxLog.severe('ToolOrchestrator: ${action.tool} failed: $error');
      return OrchestratedToolResult(
        action: action,
        observation: 'Error: $error',
        isError: true,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }
}

class _BatchEntry {
  const _BatchEntry({required this.action, required this.isConcurrencySafe});
  final AgentAction action;
  final bool isConcurrencySafe;
}

/// Simple counting semaphore for limiting concurrency.
class _Semaphore {
  _Semaphore(this._maxCount);

  final int _maxCount;
  int _currentCount = 0;
  final _waitQueue = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_currentCount < _maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void _release() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      next.complete();
    } else {
      _currentCount--;
    }
  }
}
