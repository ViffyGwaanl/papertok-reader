import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/ai/tools/base_tool.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_search_service.dart';

DateTime? _parseLocalDate(String? yyyyMmDd) {
  if (yyyyMmDd == null) return null;
  final s = yyyyMmDd.trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final y = int.tryParse(m.group(1)!);
  final mo = int.tryParse(m.group(2)!);
  final d = int.tryParse(m.group(3)!);
  if (y == null || mo == null || d == null) return null;
  return DateTime(y, mo, d);
}

bool _isLongTermDoc(String? doc) {
  final d = (doc ?? '').trim().toLowerCase();
  return d == 'memory' || d == 'mem' || d == 'long_term' || d == 'longterm';
}

class MemoryReadTool
    extends RepositoryTool<Map<String, dynamic>, Map<String, dynamic>> {
  MemoryReadTool(this._store)
      : super(
          name: 'memory_read',
          description:
              'Read the user\'s local markdown memory files. Use doc="memory" for long-term MEMORY.md, or doc="daily" for a daily note (YYYY-MM-DD.md).',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'doc': {
                'type': 'string',
                'description':
                    'Which memory doc to read: "memory" (MEMORY.md) or "daily" (YYYY-MM-DD.md). Defaults to "memory".',
              },
              'date': {
                'type': 'string',
                'description':
                    'For doc="daily" only. Local date string in YYYY-MM-DD. Defaults to today.',
              },
              'max_chars': {
                'type': 'integer',
                'description':
                    'Optional. Maximum characters to return (range 100-50000). Defaults to 8000.',
              },
            },
          },
          timeout: const Duration(seconds: 4),
        );

  final MarkdownMemoryStore _store;

  @override
  Map<String, dynamic> parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(Map<String, dynamic> input) async {
    final doc = (input['doc'] as String?)?.trim();
    final isLongTerm = doc == null || doc.isEmpty || _isLongTermDoc(doc);
    final date = _parseLocalDate(input['date'] as String?);

    final maxCharsRaw = input['max_chars'];
    final maxChars =
        (maxCharsRaw is num ? maxCharsRaw.toInt() : 8000).clamp(100, 50000);

    final content = await _store.read(longTerm: isLongTerm, date: date);
    final truncated = content.length > maxChars;
    final text = truncated ? content.substring(0, maxChars) : content;

    return {
      'doc': isLongTerm ? 'memory' : 'daily',
      'date': isLongTerm ? null : _store.dateString(date ?? DateTime.now()),
      'truncated': truncated,
      'maxChars': maxChars,
      'content': text,
    };
  }

  @override
  bool shouldLogError(Object error) => error is! TimeoutException;
}

class MemorySearchTool
    extends RepositoryTool<Map<String, dynamic>, Map<String, dynamic>> {
  MemorySearchTool(this._store)
      : super(
          name: 'memory_search',
          description:
              'Search through the user\'s local markdown memory files (MEMORY.md and daily notes). Returns matching snippets with file name and line number.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Text to search for.',
              },
              'limit': {
                'type': 'integer',
                'description':
                    'Optional. Maximum number of hits (range 1-100). Defaults to 20.',
              },
              'include_long_term': {
                'type': 'boolean',
                'description': 'Optional. Search MEMORY.md (default true).',
              },
              'include_daily': {
                'type': 'boolean',
                'description': 'Optional. Search daily notes (default true).',
              },
            },
            'required': ['query'],
          },
          timeout: const Duration(seconds: 8),
        );

  final MarkdownMemoryStore _store;

  @override
  Map<String, dynamic> parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(Map<String, dynamic> input) async {
    final query = (input['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      throw ArgumentError('query is required');
    }

    final limitRaw = input['limit'];
    final limit = (limitRaw is num ? limitRaw.toInt() : 20).clamp(1, 100);

    final includeLongTerm = (input['include_long_term'] as bool?) ?? true;
    final includeDaily = (input['include_daily'] as bool?) ?? true;

    final prefs = Prefs();

    final semanticEnabled = prefs.memorySemanticSearchEnabledEffective;
    final providerId = prefs.aiLibraryIndexProviderIdEffective;
    final embeddingModel = prefs.aiLibraryIndexEmbeddingModelEffective;

    final service = MemorySearchService(
      store: _store,
      semanticEnabled: semanticEnabled,
      embeddingProviderId: providerId,
      embeddingModel: embeddingModel,
      embeddingsTimeoutSeconds: prefs.aiLibraryIndexEmbeddingsTimeoutSeconds,
    );

    final hits = await service.search(
      query,
      limit: limit,
      includeLongTerm: includeLongTerm,
      includeDaily: includeDaily,
    );

    return {
      'query': query,
      'limit': limit,
      'hits': hits,
    };
  }

  @override
  bool shouldLogError(Object error) => error is! TimeoutException;
}

class MemoryAppendTool
    extends RepositoryTool<Map<String, dynamic>, Map<String, dynamic>> {
  MemoryAppendTool(this._store)
      : super(
          name: 'memory_append',
          description:
              'Append markdown text to the user\'s local memory files. This is a write operation and requires user approval.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'doc': {
                'type': 'string',
                'description':
                    'Target doc: "memory" for MEMORY.md, or "daily" for YYYY-MM-DD.md. Defaults to "daily".',
              },
              'date': {
                'type': 'string',
                'description':
                    'For doc="daily" only. Local date in YYYY-MM-DD. Defaults to today.',
              },
              'text': {
                'type': 'string',
                'description': 'Markdown text to append.',
              },
            },
            'required': ['text'],
          },
          timeout: const Duration(seconds: 6),
        );

  final MarkdownMemoryStore _store;

  @override
  Map<String, dynamic> parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(Map<String, dynamic> input) async {
    final doc = (input['doc'] as String?)?.trim();
    final isLongTerm = _isLongTermDoc(doc);
    final date = _parseLocalDate(input['date'] as String?);
    final text = (input['text'] as String?) ?? '';

    if (text.trim().isEmpty) {
      throw ArgumentError('text is required');
    }

    await _store.append(longTerm: isLongTerm, date: date, text: text);

    return {
      'doc': isLongTerm ? 'memory' : 'daily',
      'date': isLongTerm ? null : _store.dateString(date ?? DateTime.now()),
      'appendedChars': text.length,
    };
  }

  @override
  bool shouldLogError(Object error) => error is! TimeoutException;
}

class MemoryReplaceTool
    extends RepositoryTool<Map<String, dynamic>, Map<String, dynamic>> {
  MemoryReplaceTool(this._store)
      : super(
          name: 'memory_replace',
          description:
              'Replace the entire content of a local memory markdown file. This is a write operation and requires user approval.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'doc': {
                'type': 'string',
                'description':
                    'Target doc: "memory" for MEMORY.md, or "daily" for YYYY-MM-DD.md. Defaults to "daily".',
              },
              'date': {
                'type': 'string',
                'description':
                    'For doc="daily" only. Local date in YYYY-MM-DD. Defaults to today.',
              },
              'text': {
                'type': 'string',
                'description': 'New markdown text for the file.',
              },
            },
            'required': ['text'],
          },
          timeout: const Duration(seconds: 6),
        );

  final MarkdownMemoryStore _store;

  @override
  Map<String, dynamic> parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(Map<String, dynamic> input) async {
    final doc = (input['doc'] as String?)?.trim();
    final isLongTerm = _isLongTermDoc(doc);
    final date = _parseLocalDate(input['date'] as String?);
    final text = (input['text'] as String?) ?? '';

    await _store.replace(longTerm: isLongTerm, date: date, text: text);

    return {
      'doc': isLongTerm ? 'memory' : 'daily',
      'date': isLongTerm ? null : _store.dateString(date ?? DateTime.now()),
      'newChars': text.length,
    };
  }

  @override
  bool shouldLogError(Object error) => error is! TimeoutException;
}

final AiToolDefinition memoryReadToolDefinition = AiToolDefinition(
  id: 'memory_read',
  displayNameBuilder: (L10n l10n) => l10n.aiToolMemoryReadName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolMemoryReadDescription,
  build: (_) => MemoryReadTool(MarkdownMemoryStore()).tool,
);

final AiToolDefinition memorySearchToolDefinition = AiToolDefinition(
  id: 'memory_search',
  displayNameBuilder: (L10n l10n) => l10n.aiToolMemorySearchName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolMemorySearchDescription,
  build: (_) => MemorySearchTool(MarkdownMemoryStore()).tool,
);

final AiToolDefinition memoryAppendToolDefinition = AiToolDefinition(
  id: 'memory_append',
  displayNameBuilder: (L10n l10n) => l10n.aiToolMemoryAppendName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolMemoryAppendDescription,
  build: (_) => MemoryAppendTool(MarkdownMemoryStore()).tool,
  riskLevel: AiToolRiskLevel.write,
  alwaysRequireApproval: true,
);

final AiToolDefinition memoryReplaceToolDefinition = AiToolDefinition(
  id: 'memory_replace',
  displayNameBuilder: (L10n l10n) => l10n.aiToolMemoryReplaceName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolMemoryReplaceDescription,
  build: (_) => MemoryReplaceTool(MarkdownMemoryStore()).tool,
  riskLevel: AiToolRiskLevel.write,
  alwaysRequireApproval: true,
);
