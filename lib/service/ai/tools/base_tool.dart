import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/utils/log/common.dart';
import 'package:langchain_core/tools.dart';

typedef JsonMap = Map<String, dynamic>;

abstract class RepositoryTool<I extends Object, O> {
  RepositoryTool({
    required this.name,
    required this.description,
    required this.inputJsonSchema,
    this.timeout,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputJsonSchema;
  final Duration? timeout;

  late final Tool _tool = Tool.fromFunction<I, String>(
    name: name,
    description: description,
    inputJsonSchema: inputJsonSchema,
    func: (input) async => _execute(input),
    getInputFromJson: parseInput,
  );

  Tool get tool => _tool;

  I parseInput(Map<String, dynamic> json);

  FutureOr<O> run(I input);

  Map<String, dynamic> serializeSuccess(O output) {
    return {
      'status': 'ok',
      'name': name,
      'data': output,
    };
  }

  Map<String, dynamic> serializeError(Object error) {
    return {
      'status': 'error',
      'name': name,
      'message': error.toString(),
    };
  }

  bool shouldLogError(Object error) => true;

  Object _sanitizeForLog(Object value) {
    if (!name.startsWith('memory_')) return value;

    if (value is Map) {
      final out = <String, dynamic>{};
      for (final e in value.entries) {
        final k = e.key.toString();
        final v = e.value;

        if (k == 'text' || k == 'content') {
          final s = v?.toString() ?? '';
          out[k] = '<redacted:${s.length} chars>';
          continue;
        }

        if (k == 'data' && v is Map) {
          out[k] = _sanitizeForLog(v);
          continue;
        }

        if (k == 'data' && v is List) {
          out[k] = '<redacted:list>'; // conservative
          continue;
        }

        out[k] = v;
      }
      return out;
    }

    if (value is List) {
      return '<redacted:list>';
    }

    return value;
  }

  Future<String> _execute(I input) async {
    try {
      AnxLog.info(
        'AiTool: Executing tool $name with input: ${jsonEncode(_sanitizeForLog(input))}',
      );
      final result = await _runWithTimeout(() => run(input));
      final serialized = serializeSuccess(result);
      final resultJson = jsonEncode(serialized);
      AnxLog.info(
        'AiTool: Tool $name completed with result: ${jsonEncode(_sanitizeForLog(serialized))}',
      );
      return resultJson;
    } catch (error, stack) {
      if (shouldLogError(error)) {
        AnxLog.severe('Tool $name failed: $error\n$stack');
      }
      final serialized = serializeError(error);
      return jsonEncode(serialized);
    }
  }

  Future<O> _runWithTimeout(FutureOr<O> Function() action) {
    final future = Future<O>.sync(action);
    if (timeout == null) {
      return future;
    }
    return future.timeout(timeout!);
  }
}
