import 'dart:convert';

import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/service/ai/tools/start_seminar_tool.dart';
import 'package:papertok_reader/utils/ai_reasoning_parser.dart';

class StartSeminarToolBridge {
  final Set<String> _handledKeys = <String>{};

  List<StartSeminarToolRequest> takeNewRequests(List<ChatMessage> messages) {
    final requests = <StartSeminarToolRequest>[];
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      if (message is! AIChatMessage) continue;
      final parsed = parseReasoningContent(message.contentAsString);
      for (final step in parsed.toolSteps) {
        final request = _requestFromStep(index, step);
        if (request != null && _handledKeys.add(request.key)) {
          requests.add(request);
        }
      }
    }
    return requests;
  }

  StartSeminarToolLaunch buildLaunch({
    required StartSeminarToolRequest request,
    required int? bookId,
    required List<AiSeminarRoleProfile> defaultRoleProfiles,
    required bool includeVerifier,
    required int createdAt,
  }) {
    final overrideProfiles = _scopeOverrideProfiles(
      request.input,
      defaultRoleProfiles,
    );
    final effectiveProfiles = overrideProfiles ?? defaultRoleProfiles;
    final roleIds = _roleIdsFor(effectiveProfiles, includeVerifier);
    return StartSeminarToolLaunch(
      roleProfilesForAppend: overrideProfiles,
      includeVerifier: includeVerifier,
      card: AiSeminarRunCardMeta(
        question: request.input.question,
        sessionId: request.sessionId,
        bookId: bookId,
        status: 'ready',
        roleIds: roleIds,
        evidenceScopeIds: _evidenceScopeIdsFor(effectiveProfiles),
        sourceRefCount: 0,
        maxRounds: 2,
        roleProfiles: effectiveProfiles,
        createdAt: createdAt,
      ),
    );
  }

  StartSeminarToolRequest? _requestFromStep(
    int messageIndex,
    ParsedToolStep step,
  ) {
    if (step.name.trim() != 'start_seminar') return null;
    if (step.status.trim() != 'success') return null;
    final rawInput = step.input?.trim();
    if (rawInput == null || rawInput.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawInput);
      if (decoded is! Map) return null;
      final input = StartSeminarInput.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      final callId = step.callId?.trim();
      final fallbackKey = '$messageIndex:${jsonEncode(input.toJson())}';
      final key = callId == null || callId.isEmpty ? fallbackKey : callId;
      return StartSeminarToolRequest(
        key: key,
        sessionId: _sessionIdFor(key),
        input: input,
      );
    } catch (_) {
      return null;
    }
  }

  List<AiSeminarRoleProfile>? _scopeOverrideProfiles(
    StartSeminarInput input,
    List<AiSeminarRoleProfile> defaultRoleProfiles,
  ) {
    if (input.evidenceScopes.isEmpty) return null;
    final defaults = <AiSeminarRole, AiSeminarRoleProfile>{
      for (final profile in defaultRoleProfiles) profile.role: profile,
    };
    return AiSeminarRole.values
        .map((role) {
          final existing = defaults[role];
          return AiSeminarRoleProfile(
            role: role,
            name: existing?.name,
            customPrompt: existing?.customPrompt,
            enabled: existing?.enabled ?? true,
            evidenceScopes: input.evidenceScopes,
            allowedToolIds: existing?.allowedToolIds ?? const <String>[],
          );
        })
        .where((profile) => profile.hasOverrides)
        .toList(growable: false);
  }

  List<String> _roleIdsFor(
    List<AiSeminarRoleProfile> profiles,
    bool includeVerifier,
  ) {
    AiSeminarRoleProfile? profileFor(AiSeminarRole role) {
      for (final profile in profiles) {
        if (profile.role == role) return profile;
      }
      return null;
    }

    final roles = <AiSeminarRole>[
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      if (includeVerifier) AiSeminarRole.verifier,
      AiSeminarRole.synthesizer,
    ].where((role) => profileFor(role)?.enabled != false).toList();
    return (roles.isEmpty ? const [AiSeminarRole.synthesizer] : roles)
        .map((role) => role.asString)
        .toList(growable: false);
  }

  List<String> _evidenceScopeIdsFor(List<AiSeminarRoleProfile> profiles) {
    final scopes = <AiSeminarEvidenceScope>[AiSeminarEvidenceScope.currentBook];
    for (final profile in profiles) {
      if (!profile.enabled) continue;
      for (final scope in profile.evidenceScopes) {
        if (!scopes.contains(scope)) scopes.add(scope);
      }
    }
    return scopes.map((scope) => scope.asString).toList(growable: false);
  }

  String _sessionIdFor(String key) {
    final normalized =
        key.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-').replaceAll(
              RegExp(r'-+'),
              '-',
            );
    final segment = normalized.trim().isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : normalized;
    final safeSegment =
        segment.length <= 80 ? segment : segment.substring(0, 80);
    return 'seminar-tool-$safeSegment';
  }
}

class StartSeminarToolRequest {
  const StartSeminarToolRequest({
    required this.key,
    required this.sessionId,
    required this.input,
  });

  final String key;
  final String sessionId;
  final StartSeminarInput input;
}

class StartSeminarToolLaunch {
  const StartSeminarToolLaunch({
    required this.card,
    required this.roleProfilesForAppend,
    required this.includeVerifier,
  });

  final AiSeminarRunCardMeta card;
  final List<AiSeminarRoleProfile>? roleProfilesForAppend;
  final bool includeVerifier;
}
