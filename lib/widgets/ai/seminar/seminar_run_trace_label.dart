typedef SeminarRoleLabelForId = String Function(String roleId);

String seminarRunTraceLabel(
  String runId, {
  required bool zh,
  SeminarRoleLabelForId? roleLabelForId,
}) {
  final normalized = runId.trim();
  if (normalized.isEmpty) return '';
  final base = zh ? '本场研讨' : 'This seminar';
  final segments = normalized.split(':');
  final roleId = _roleIdFromSegments(segments);
  final roleLabel = roleId == null
      ? null
      : roleLabelForId?.call(roleId) ?? _defaultRoleLabel(roleId, zh: zh);
  final hasTool = segments.any(_isToolSegment) ||
      normalized.contains('tool-call') ||
      normalized.contains(':tool-');
  final hasDirector = segments.any((segment) => segment.startsWith('director'));
  final hasReader = segments.any((segment) => segment.startsWith('reader'));
  final details = <String>[
    if (roleLabel != null) roleLabel,
    if (roleLabel == null && hasDirector) zh ? '主持人' : 'Director',
    if (roleLabel == null && hasReader) zh ? '读者回应' : 'Reader reply',
    if (hasTool) zh ? '工具调用' : 'Tool call',
  ];
  if (details.isEmpty) {
    return normalized.startsWith('seminar-')
        ? base
        : (zh ? '运行记录' : 'Run record');
  }
  return '$base · ${details.join(' · ')}';
}

String? _roleIdFromSegments(List<String> segments) {
  for (final segment in segments) {
    if (!segment.startsWith('role-')) continue;
    return segment.substring(5).replaceFirst(RegExp(r'-[0-9]+$'), '');
  }
  return null;
}

bool _isToolSegment(String segment) =>
    segment.startsWith('tool') || segment == 'current-book';

String _defaultRoleLabel(String roleId, {required bool zh}) {
  return switch (roleId) {
    'critical' => zh ? '批判者' : 'Critical',
    'supportive' => zh ? '支持者' : 'Supportive',
    'synthesizer' => zh ? '综合者' : 'Synthesizer',
    'verifier' => zh ? '核验者' : 'Verifier',
    _ => zh ? '角色 $roleId' : 'Role $roleId',
  };
}
