import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';

import 'base_tool.dart';

class StartSeminarInput {
  const StartSeminarInput({
    required this.question,
    this.evidenceScopes = const <AiSeminarEvidenceScope>[],
  });

  factory StartSeminarInput.fromJson(Map<String, dynamic> json) {
    final question = (json['question'] ?? '').toString().trim();
    if (question.isEmpty) {
      throw ArgumentError('question is required');
    }
    return StartSeminarInput(
      question: question,
      evidenceScopes: _parseEvidenceScopes(json),
    );
  }

  final String question;
  final List<AiSeminarEvidenceScope> evidenceScopes;

  List<String> get scopeIds =>
      evidenceScopes.map((scope) => scope.asString).toList(growable: false);

  Map<String, dynamic> toJson() => {
        'question': question,
        if (scopeIds.isNotEmpty) 'scopeIds': scopeIds,
      };

  static List<AiSeminarEvidenceScope> _parseEvidenceScopes(
    Map<String, dynamic> json,
  ) {
    final raw = <Object?>[
      json['scope'],
      json['evidenceScope'],
      if (json['scopes'] is Iterable) ...(json['scopes'] as Iterable),
      if (json['evidenceScopes'] is Iterable)
        ...(json['evidenceScopes'] as Iterable),
    ];
    final scopes = <AiSeminarEvidenceScope>[];
    for (final item in raw) {
      final scope = AiSeminarEvidenceScope.fromString(item?.toString().trim());
      if (scope != null && !scopes.contains(scope)) {
        scopes.add(scope);
      }
    }
    return List.unmodifiable(scopes);
  }
}

class StartSeminarTool
    extends RepositoryTool<StartSeminarInput, Map<String, dynamic>> {
  StartSeminarTool()
      : super(
          name: 'start_seminar',
          description:
              'Start a native AI Seminar in the current chat. Creates a '
              'Seminar run card using the user Settings defaults and starts '
              'it immediately.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'question': {
                'type': 'string',
                'description':
                    'Required. The question or topic the Seminar should discuss.',
              },
              'scope': {
                'type': 'string',
                'description':
                    'Optional. Evidence scope override for this run.',
                'enum': [
                  'current-chapter',
                  'current-book',
                  'library',
                  'notes',
                  'memory',
                  'concept-graph',
                ],
              },
              'scopes': {
                'type': 'array',
                'items': {
                  'type': 'string',
                  'enum': [
                    'current-chapter',
                    'current-book',
                    'library',
                    'notes',
                    'memory',
                    'concept-graph',
                  ],
                },
                'description':
                    'Optional. Multiple evidence scope overrides for this run.',
              },
            },
            'required': ['question'],
          },
          timeout: const Duration(seconds: 1),
        );

  @override
  StartSeminarInput parseInput(Map<String, dynamic> json) =>
      StartSeminarInput.fromJson(json);

  @override
  Future<Map<String, dynamic>> run(StartSeminarInput input) async {
    return {
      'ok': true,
      'messageKey': 'aiToolStartSeminarLaunched',
      'message': 'Seminar started.',
      'question': input.question,
      'scopeIds': input.scopeIds,
    };
  }
}

final AiToolDefinition startSeminarToolDefinition = AiToolDefinition(
  id: 'start_seminar',
  displayNameBuilder: (L10n l10n) => l10n.aiToolStartSeminarName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolStartSeminarDescription,
  build: (_) => StartSeminarTool().tool,
);
