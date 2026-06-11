import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';

class AiSeminarRolePartialThrottle {
  AiSeminarRolePartialThrottle._();

  static const Duration minInterval = Duration(milliseconds: 100);
  static final Map<String, DateTime> _lastUiUpdates = <String, DateTime>{};

  static bool shouldApply(AiSeminarRuntimeEvent event) {
    if (event.partialText == null) return false;
    final roleId = event.activeRole?.asString ?? 'unknown';
    final key = '${event.session.id}:$roleId';
    final now = DateTime.now();
    final last = _lastUiUpdates[key];
    if (last != null && now.difference(last) < minInterval) return false;
    _lastUiUpdates[key] = now;
    return true;
  }
}
