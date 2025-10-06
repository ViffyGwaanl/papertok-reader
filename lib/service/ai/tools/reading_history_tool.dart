import 'dart:async';

import 'package:anx_reader/service/ai/repository/reading_history_repository.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';

import 'base_tool.dart';

class _ReadingHistoryInput {
  _ReadingHistoryInput({
    this.bookId,
    this.from,
    this.to,
    this.limit,
  });

  final int? bookId;
  final DateTime? from;
  final DateTime? to;
  final int? limit;

  factory _ReadingHistoryInput.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      return int.tryParse(value.toString());
    }

    return _ReadingHistoryInput(
      bookId: parseInt(json['book_id'] ?? json['bookId']),
      from: parseDate(json['from']),
      to: parseDate(json['to']),
      limit: parseInt(json['limit']),
    );
  }

  int resolvedLimit([int fallback = 20]) => (limit ?? fallback).clamp(1, 100);
}

class ReadingHistoryTool
    extends RepositoryTool<_ReadingHistoryInput, Map<String, dynamic>> {
  ReadingHistoryTool(this._repository)
      : super(
          name: 'reading_history',
          description:
              'Fetch reading history entries. Optional filters: book_id, from/to (ISO date), limit.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'book_id': {
                'type': 'integer',
                'description': 'Filter by book identifier.',
              },
              'from': {
                'type': 'string',
                'description': 'Include entries on/after this ISO date.',
              },
              'to': {
                'type': 'string',
                'description': 'Include entries on/before this ISO date.',
              },
              'limit': {
                'type': 'integer',
                'description': 'Max number of records to return (1-100).',
              },
            },
          },
          timeout: const Duration(seconds: 4),
        );

  final ReadingHistoryRepository _repository;

  @override
  _ReadingHistoryInput parseInput(Map<String, dynamic> json) {
    return _ReadingHistoryInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(_ReadingHistoryInput input) async {
    final records = await _repository.fetchHistory(
      bookId: input.bookId,
      from: input.from,
      to: input.to,
      limit: input.resolvedLimit(),
    );

    final totalSeconds = records.fold<int>(0, (sum, item) => sum + item.entry.readingTime);

    return {
      'bookId': input.bookId,
      'from': input.from?.toIso8601String(),
      'to': input.to?.toIso8601String(),
      'totalEntries': records.length,
      'totalReadingDuration': convertSeconds(totalSeconds),
      'records': records.map((record) => record.toMap()).toList(),
    };
  }

  @override
  bool shouldLogError(Object error) {
    return error is! TimeoutException;
  }
}

final readingHistoryTool = ReadingHistoryTool(const ReadingHistoryRepository()).tool;
