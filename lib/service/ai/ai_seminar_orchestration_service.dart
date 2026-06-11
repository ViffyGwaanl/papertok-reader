import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/service/ai/agent_tool_call_event.dart';

typedef AiSeminarEvidenceFetcher = Future<AiSeminarEvidenceBundle> Function(
  AiSeminarSessionContract session,
);

typedef AiSeminarRoleExecutor = Future<AiSeminarRoleTurn> Function(
  AiSeminarRoleInvocation invocation,
);

typedef AiSeminarClock = int Function();

class AiSeminarRoleInvocation {
  const AiSeminarRoleInvocation({
    required this.session,
    required this.role,
    required this.evidenceBundle,
    required this.priorTurns,
    required this.prompt,
    this.toolCallObserver,
  });

  final AiSeminarSessionContract session;
  final AiSeminarRole role;
  final AiSeminarEvidenceBundle evidenceBundle;
  final List<AiSeminarRoleTurn> priorTurns;
  final String prompt;
  final AgentToolCallObserver? toolCallObserver;
}

class AiSeminarOrchestrationService {
  const AiSeminarOrchestrationService({
    required AiSeminarEvidenceFetcher fetchEvidence,
    required AiSeminarRoleExecutor executeRole,
    AiSeminarClock? now,
  })  : _fetchEvidence = fetchEvidence,
        _executeRole = executeRole,
        _now = now;

  final AiSeminarEvidenceFetcher _fetchEvidence;
  final AiSeminarRoleExecutor _executeRole;
  final AiSeminarClock? _now;

  Future<AiSeminarRun> run(AiSeminarSessionContract session) async {
    final startedAt = _nowMs();
    final evidenceBundle = await _fetchEvidence(session);

    if (evidenceBundle.evidence.isEmpty ||
        !evidenceBundle.allEvidenceTraceable) {
      return AiSeminarRun(
        session: session,
        status: AiSeminarRunStatus.needsEvidence,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        completedAt: _nowMs(),
        message: 'AI Seminar requires traceable current-source evidence.',
      );
    }

    final turns = <AiSeminarRoleTurn>[];
    for (final role in executionOrder(session.roles)) {
      try {
        final roleEvidenceBundle = evidenceBundleForRole(
          session: session,
          role: role,
          evidenceBundle: evidenceBundle,
        );
        final roleTraceableEvidenceIds =
            _traceableEvidenceIds(roleEvidenceBundle);
        final turn = await _executeRole(
          AiSeminarRoleInvocation(
            session: session,
            role: role,
            evidenceBundle: roleEvidenceBundle,
            priorTurns: List.unmodifiable(turns),
            prompt: promptForRole(
              session: session,
              role: role,
              evidenceBundle: roleEvidenceBundle,
              priorTurns: turns,
            ),
          ),
        );
        if (turn.role != role) {
          return AiSeminarRun(
            session: session,
            status: AiSeminarRunStatus.failed,
            evidenceBundle: evidenceBundle,
            turns: List.unmodifiable(turns),
            startedAt: startedAt,
            completedAt: _nowMs(),
            message:
                'AI Seminar executor returned ${turn.role.asString} for ${role.asString}.',
          );
        }
        if (turn.isFailed) {
          return AiSeminarRun(
            session: session,
            status: AiSeminarRunStatus.failed,
            evidenceBundle: evidenceBundle,
            turns: List.unmodifiable([...turns, turn]),
            startedAt: startedAt,
            completedAt: _nowMs(),
            message: turn.error,
          );
        }
        if (!turn.hasTraceableEvidence(roleTraceableEvidenceIds)) {
          return AiSeminarRun(
            session: session,
            status: AiSeminarRunStatus.needsEvidence,
            evidenceBundle: evidenceBundle,
            turns: List.unmodifiable(turns),
            startedAt: startedAt,
            completedAt: _nowMs(),
            message:
                'AI Seminar role ${role.asString} cited missing or untraceable evidence.',
          );
        }
        turns.add(turn);
      } catch (error) {
        return AiSeminarRun(
          session: session,
          status: AiSeminarRunStatus.failed,
          evidenceBundle: evidenceBundle,
          turns: List.unmodifiable(turns),
          startedAt: startedAt,
          completedAt: _nowMs(),
          message: error.toString(),
        );
      }
    }

    final synthesis = synthesize(
      session: session,
      evidenceBundle: evidenceBundle,
      turns: turns,
    );
    return AiSeminarRun(
      session: session,
      status: synthesis.hasTraceableHandoff
          ? AiSeminarRunStatus.completed
          : AiSeminarRunStatus.needsEvidence,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      synthesis: synthesis,
      startedAt: startedAt,
      completedAt: _nowMs(),
    );
  }

  static List<AiSeminarRole> executionOrder(List<AiSeminarRole> roles) {
    if (roles.isEmpty) {
      return AiSeminarRole.defaultRoles;
    }
    final out = <AiSeminarRole>[];
    for (final role in roles) {
      if (role != AiSeminarRole.synthesizer && !out.contains(role)) {
        out.add(role);
      }
    }
    out.remove(AiSeminarRole.synthesizer);
    out.add(AiSeminarRole.synthesizer);
    return List.unmodifiable(out);
  }

  static AiSeminarEvidenceBundle evidenceBundleForRole({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required AiSeminarEvidenceBundle evidenceBundle,
  }) {
    final profile = session.roleProfileFor(role);
    final scopes = profile?.evidenceScopes ?? const <AiSeminarEvidenceScope>[];
    if (scopes.isEmpty) return evidenceBundle;
    final evidence = evidenceBundle.evidence
        .where((item) => _scopeAllowsEvidence(scopes, item.scope))
        .toList(growable: false);
    return AiSeminarEvidenceBundle(
      query: evidenceBundle.query,
      evidence: List.unmodifiable(evidence),
    );
  }

  static String promptForRole({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required AiSeminarEvidenceBundle evidenceBundle,
    required List<AiSeminarRoleTurn> priorTurns,
  }) {
    final profile = session.roleProfileFor(role);
    return [
      'PaperTok AI Seminar role: ${role.asString}',
      if (profile?.name != null) 'Configured role name: ${profile!.name}',
      if (profile?.evidenceScopes.isNotEmpty == true)
        'Session evidence hints from role profile: ${profile!.evidenceScopes.map((scope) => scope.asString).join(', ')}',
      if (profile?.allowedToolIds.isNotEmpty == true)
        'Allowed read-only tools: ${profile!.allowedToolIds.join(', ')}',
      'Question: ${session.question}',
      'Evidence ids: ${evidenceBundle.evidence.map((e) => e.id).join(', ')}',
      if (priorTurns.isNotEmpty)
        'Prior roles: ${priorTurns.map((turn) => turn.role.asString).join(', ')}',
      if (profile?.customPrompt != null) ...[
        'Configured role instructions:',
        profile!.customPrompt!,
      ],
      'Use only the supplied evidence ids when making claims.',
    ].join('\n');
  }

  static String promptForUserInterventionRole({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required AiSeminarEvidenceBundle evidenceBundle,
    required List<AiSeminarRoleTurn> priorTurns,
    required AiSeminarUserIntervention intervention,
  }) {
    final interventionText = intervention.text.trim();
    return [
      promptForRole(
        session: session,
        role: role,
        evidenceBundle: evidenceBundle,
        priorTurns: priorTurns,
      ),
      if (interventionText.isNotEmpty)
        'Reader intervention: $interventionText'
      else
        'Reader selected this role to continue without extra text.',
      'Respond directly to the reader intervention before updating the shared discussion.',
    ].join('\n');
  }

  static AiSeminarSynthesis synthesize({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
    required List<AiSeminarRoleTurn> turns,
  }) {
    final byRole = <AiSeminarRole, AiSeminarRoleTurn>{
      for (final turn in turns) turn.role: turn,
    };
    final entries =
        turns.expand((turn) => turn.whiteboardEntries).toList(growable: false);
    final evidenceIds = <String>{
      for (final turn in turns) ...turn.evidenceRefIds,
      for (final entry in entries) ...entry.evidenceRefIds,
    };

    return AiSeminarSynthesis(
      summary:
          byRole[AiSeminarRole.synthesizer]?.responseText.trim().isNotEmpty ==
                  true
              ? byRole[AiSeminarRole.synthesizer]!.responseText
              : 'No synthesis produced.',
      supportiveView: byRole[AiSeminarRole.supportive]?.responseText ?? '',
      criticalView: byRole[AiSeminarRole.critical]?.responseText ?? '',
      disagreements: entries
          .where((entry) => entry.kind == AiSeminarWhiteboardKind.disagreement)
          .map((entry) => entry.text)
          .toList(growable: false),
      openQuestions: entries
          .where((entry) => entry.kind == AiSeminarWhiteboardKind.openQuestion)
          .map((entry) => entry.text)
          .toList(growable: false),
      candidateReviewQuestions: entries
          .where(
              (entry) => entry.kind == AiSeminarWhiteboardKind.reviewSuggestion)
          .map((entry) => entry.text.trim())
          .where((text) => text.isNotEmpty)
          .toList(growable: false),
      candidateCards: entries
          .where((entry) => entry.kind == AiSeminarWhiteboardKind.candidateCard)
          .toList(growable: false),
      evidenceRefIds: evidenceIds.toList(growable: false),
      evidence: evidenceBundle.evidence,
      readyForReview: true,
    );
  }

  int _nowMs() => _now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  static Set<String> _traceableEvidenceIds(AiSeminarEvidenceBundle bundle) {
    return bundle.evidence
        .where((item) => item.isTraceable)
        .map((item) => item.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static bool _scopeAllowsEvidence(
    List<AiSeminarEvidenceScope> allowedScopes,
    AiSeminarEvidenceScope evidenceScope,
  ) {
    if (allowedScopes.contains(evidenceScope)) return true;
    return evidenceScope == AiSeminarEvidenceScope.currentBook &&
        allowedScopes.contains(AiSeminarEvidenceScope.currentChapter);
  }
}
