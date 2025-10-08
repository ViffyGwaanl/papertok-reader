import 'dart:async';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/ai/tools/input/bookshelf_organize_input.dart';
import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/groups_repository.dart';

import 'base_tool.dart';

class BookshelfOrganizeTool
    extends RepositoryTool<BookshelfOrganizeInput, Map<String, dynamic>> {
  BookshelfOrganizeTool(
    this._booksRepository,
    this._groupsRepository,
  ) : super(
          name: 'bookshelf_organize',
          description:
              'Propose bookshelf regrouping plans. Provide target groups with their book IDs and optional names. Returns a plan that requires user confirmation before applying.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'groups': {
                'type': 'array',
                'description': 'Desired bookshelf groups with target members.',
                'minItems': 1,
                'items': {
                  'type': 'object',
                  'properties': {
                    'groupId': {
                      'type': 'integer',
                      'description':
                          'Target group identifier (use an existing group, or reuse one of the book IDs for a new group).',
                    },
                    'bookIds': {
                      'type': 'array',
                      'items': {'type': 'integer'},
                      'description':
                          'Books that should belong to this group after organizing.',
                      'minItems': 1,
                    },
                    'name': {
                      'type': 'string',
                      'description': 'Desired group name.',
                    },
                    'renameTo': {
                      'type': 'string',
                      'description': 'Optional new name for an existing group.',
                    },
                    'createNew': {
                      'type': 'boolean',
                      'description':
                          'Set true when creating a brand new group.',
                    },
                  },
                },
              },
              'ungroupedBookIds': {
                'type': 'array',
                'items': {'type': 'integer'},
                'description':
                    'Books that should be removed from any group (become ungrouped).',
                'minItems': 1,
              },
              'cleanupGroupIds': {
                'type': 'array',
                'items': {'type': 'integer'},
                'description':
                    'Groups to delete after the re-organization (e.g. empty folders).',
                'minItems': 1,
              },
              'summary': {
                'type': 'string',
                'description': 'Optional human readable summary of the plan.',
              },
            },
          },
          timeout: const Duration(seconds: 8),
        );

  final BooksRepository _booksRepository;
  final GroupsRepository _groupsRepository;

  @override
  BookshelfOrganizeInput parseInput(Map<String, dynamic> json) {
    return BookshelfOrganizeInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(BookshelfOrganizeInput input) async {
    if (input.isEmpty) {
      throw ArgumentError('No bookshelf changes were provided.');
    }

    final allBookIds = input.allBookIds().toList(growable: false);
    if (allBookIds.isEmpty) {
      throw ArgumentError('Book IDs cannot be empty.');
    }

    final uniqueBookIds = allBookIds.toSet();
    if (uniqueBookIds.length != allBookIds.length) {
      throw ArgumentError(
        'Each book ID must appear in only one target group or ungrouped list.',
      );
    }

    final bookMap = await _booksRepository.fetchByIds(uniqueBookIds);
    final missingBooks = uniqueBookIds.where((id) => !bookMap.containsKey(id));
    if (missingBooks.isNotEmpty) {
      throw ArgumentError('Unknown book IDs: ${missingBooks.join(', ')}');
    }

    final deletedBooks = bookMap.values.where((book) => book.isDeleted);
    if (deletedBooks.isNotEmpty) {
      final ids = deletedBooks.map((book) => book.id).join(', ');
      throw ArgumentError('Cannot organize deleted books (ids: $ids).');
    }

    final allGroupIds = {
      ...input.groups.map((group) => group.groupId),
      ...input.cleanupGroupIds,
    }..removeWhere((id) => id <= 0);
    final existingGroups = await _groupsRepository.fetchByIds(allGroupIds);

    final groupsPlan = <Map<String, dynamic>>[];
    final newGroupIds = <int>{};

    for (final group in input.groups) {
      final books = group.bookIds.map((id) => bookMap[id]!).toList();
      final existing = existingGroups[group.groupId];
      final createNew = group.createNew ?? existing == null;

      if (createNew && books.isEmpty) {
        throw ArgumentError(
          'New group ${group.groupId} must include at least one book.',
        );
      }

      if (createNew && !books.any((book) => book.id == group.groupId)) {
        throw ArgumentError(
          'For a new group, use a book ID from its members as groupId to stay consistent with the app.',
        );
      }

      if (!createNew && existing == null) {
        throw ArgumentError(
          'Group ${group.groupId} does not exist. Set create_new=true to create it.',
        );
      }

      if (createNew && newGroupIds.contains(group.groupId)) {
        throw ArgumentError('Duplicate new group identifier ${group.groupId}.');
      }
      if (createNew) {
        newGroupIds.add(group.groupId);
      }

      final targetName = group.renameTo ?? group.name ?? existing?.name;
      groupsPlan.add({
        'groupId': group.groupId,
        'createNew': createNew,
        'currentName': existing?.name,
        'proposedName': targetName,
        'books': books.map(_serializeBook).toList(),
      });
    }

    final ungrouped = input.ungroupedBookIds
        .map((id) => bookMap[id]!)
        .map(_serializeBook)
        .toList(growable: false);

    final cleanupGroupIds = input.cleanupGroupIds
        .where((id) => id > 0)
        .where((id) => !input.groups.any((group) => group.groupId == id))
        .toSet()
        .toList()
      ..sort();

    final generatedSummary = input.summary ??
        _buildSummary(
          groupsPlan,
          ungrouped,
        );

    return {
      'requiresConfirmation': true,
      'plan': {
        'summary': generatedSummary,
        'groups': groupsPlan,
        'ungroupedBooks': ungrouped,
        'cleanupGroupIds': cleanupGroupIds,
        'stats': {
          'groups': groupsPlan.length,
          'movedBooks': groupsPlan.fold<int>(
            0,
            (acc, group) => acc + (group['books'] as List).length,
          ),
          'ungroupedBooks': ungrouped.length,
        },
      },
    };
  }

  Map<String, dynamic> _serializeBook(Book book) {
    return {
      'bookId': book.id,
      'title': book.title,
      if (book.author.trim().isNotEmpty) 'author': book.author,
      'previousGroupId': book.groupId,
    };
  }

  String _buildSummary(
    List<Map<String, dynamic>> groups,
    List<Map<String, dynamic>> ungrouped,
  ) {
    final movedCount = groups.fold<int>(
      0,
      (sum, group) => sum + (group['books'] as List).length,
    );
    final groupCount = groups.length;
    final ungroupedCount = ungrouped.length;
    final parts = <String>[];

    if (movedCount > 0) {
      parts.add(
        '$movedCount book${movedCount == 1 ? '' : 's'} assigned to $groupCount group${groupCount == 1 ? '' : 's'}.',
      );
    }
    if (ungroupedCount > 0) {
      parts.add(
        '$ungroupedCount book${ungroupedCount == 1 ? '' : 's'} left ungrouped.',
      );
    }
    if (parts.isEmpty) {
      parts.add('No bookshelf changes detected.');
    }
    return parts.join(' ');
  }
}
