final RegExp _seminarEvidenceNumberPattern =
    RegExp(r'^(?:(?:current|evidence)-(\d+)|e-?(\d+))$', caseSensitive: false);

int? seminarEvidenceNumberFromId(String? id) {
  final normalized = id?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  final match = _seminarEvidenceNumberPattern.firstMatch(normalized);
  if (match == null) return null;
  final value = int.tryParse(match.group(1) ?? match.group(2) ?? '');
  if (value == null || value <= 0) return null;
  return value;
}

String? seminarEvidenceLabel({
  required String? id,
  required bool zh,
  int? fallbackIndex,
}) {
  final number = seminarEvidenceNumberFromId(id) ?? fallbackIndex;
  if (number == null || number <= 0) return null;
  return zh ? '证据$number' : 'Evidence $number';
}
