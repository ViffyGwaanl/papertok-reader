typedef SeminarEvidenceLabelBuilder = String Function(String number);

final _escapedNewlinePattern = RegExp(r'\\r\\n|\\n|\\r');
final _internalEvidenceIdPattern = RegExp(
  r'\(?\b(?:current|selection|library)-([0-9]+)\)?',
  caseSensitive: false,
);

String normalizeSeminarDisplayText(
  String value, {
  SeminarEvidenceLabelBuilder? evidenceLabelBuilder,
}) {
  final labelBuilder = evidenceLabelBuilder ?? (number) => 'Evidence $number';
  final withNewlines = value.replaceAll(_escapedNewlinePattern, '\n');
  final withEvidenceLabels = withNewlines.replaceAllMapped(
    _internalEvidenceIdPattern,
    (match) => labelBuilder(match.group(1) ?? ''),
  );
  return withEvidenceLabels
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();
}

String? seminarEvidenceLabelFromInternalId(
  String value, {
  SeminarEvidenceLabelBuilder? evidenceLabelBuilder,
}) {
  final match = RegExp(
    r'^(?:current|selection|library)-([0-9]+)$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) return null;
  final labelBuilder = evidenceLabelBuilder ?? (number) => 'Evidence $number';
  return labelBuilder(match.group(1) ?? '');
}
