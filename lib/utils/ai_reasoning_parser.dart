class ParsedReasoning {
  const ParsedReasoning({
    required this.timeline,
    required this.answer,
  });

  final List<ParsedReasoningEntry> timeline;
  final String answer;

  bool get hasThink => timeline.any((entry) => entry.isThink);

  bool get hasAnswer => answer.trim().isNotEmpty;

  bool get hasToolSteps => timeline.any((entry) => entry.isToolStep);

  List<ParsedToolStep> get toolSteps => timeline
      .where((entry) => entry.isToolStep)
      .map((entry) => entry.toolStep!)
      .toList(growable: false);

  String get think => timeline
      .where((entry) => entry.isThink)
      .map((entry) => entry.text!.trim())
      .where((text) => text.isNotEmpty)
      .join('\n\n');
}

class ParsedReasoningEntry {
  const ParsedReasoningEntry.think(this.text)
      : toolStep = null,
        isThink = true,
        isToolStep = false;

  const ParsedReasoningEntry.tool(this.toolStep)
      : text = null,
        isThink = false,
        isToolStep = true;

  final String? text;
  final ParsedToolStep? toolStep;
  final bool isThink;
  final bool isToolStep;
}

class ParsedToolStep {
  const ParsedToolStep({
    required this.name,
    required this.status,
    this.input,
    this.output,
    this.error,
  });

  final String name;
  final String status;
  final String? input;
  final String? output;
  final String? error;
}

ParsedReasoning parseReasoningContent(String content) {
  String think = '';
  String remaining = content;

  final thinkStart = content.indexOf('<think>');
  final thinkEnd = content.indexOf('</think>');
  if (thinkStart != -1 && thinkEnd != -1 && thinkEnd > thinkStart) {
    think = content.substring(thinkStart + '<think>'.length, thinkEnd);
    remaining = content.substring(thinkEnd + '</think>'.length);
  }

  final timeline = <ParsedReasoningEntry>[];
  _parseTimeline(think, timeline);

  // Backward compatibility: handle tool tags outside <think></think>
  final toolRegex = RegExp(r'<tool-step\s+([\s\S]*?)\s*/>');
  remaining = remaining.replaceAllMapped(toolRegex, (match) {
    final attrs = _parseAttributes(match.group(1)!);
    timeline.add(
      ParsedReasoningEntry.tool(
        ParsedToolStep(
          name: _unescapeAttr(attrs['name'] ?? ''),
          status: (attrs['status'] ?? 'pending').toLowerCase(),
          input: attrs['input'] != null ? _unescapeAttr(attrs['input']!) : null,
          output:
              attrs['output'] != null ? _unescapeAttr(attrs['output']!) : null,
          error:
              attrs['error'] != null ? _unescapeAttr(attrs['error']!) : null,
        ),
      ),
    );
    return '';
  }).trim();

  return ParsedReasoning(
    timeline: timeline,
    answer: remaining.trim(),
  );
}

Map<String, String> _parseAttributes(String raw) {
  final attrs = <String, String>{};
  final attrRegex = RegExp(r"(\w+)='([^']*)'");
  for (final match in attrRegex.allMatches(raw)) {
    attrs[match.group(1)!] = match.group(2)!;
  }
  return attrs;
}

String _unescapeAttr(String value) {
  return Uri.decodeComponent(value);
}

void _parseTimeline(String source, List<ParsedReasoningEntry> timeline) {
  if (source.trim().isEmpty) {
    return;
  }

  final tagRegex = RegExp(r'<(think-block|tool-step)\s+([^/>]+?)\s*/>');
  var currentIndex = 0;
  for (final match in tagRegex.allMatches(source)) {
    final preceding = source.substring(currentIndex, match.start);
    _appendThinkIfNeeded(preceding, timeline);

    final tagName = match.group(1)!;
    final attrs = _parseAttributes(match.group(2)!);

    if (tagName == 'think-block') {
      final text = _unescapeAttr(attrs['text'] ?? '');
      _appendThinkIfNeeded(text, timeline);
    } else {
      timeline.add(
        ParsedReasoningEntry.tool(
          ParsedToolStep(
            name: _unescapeAttr(attrs['name'] ?? ''),
            status: (attrs['status'] ?? 'pending').toLowerCase(),
            input: attrs['input'] != null ? _unescapeAttr(attrs['input']!) : null,
            output: attrs['output'] != null
                ? _unescapeAttr(attrs['output']!)
                : null,
            error: attrs['error'] != null
                ? _unescapeAttr(attrs['error']!)
                : null,
          ),
        ),
      );
    }

    currentIndex = match.end;
  }

  final trailing = source.substring(currentIndex);
  _appendThinkIfNeeded(trailing, timeline);
}

void _appendThinkIfNeeded(String text, List<ParsedReasoningEntry> timeline) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return;
  }
  final sanitized = _sanitizeThinkText(trimmed);
  if (sanitized.isEmpty) {
    return;
  }
  timeline.add(ParsedReasoningEntry.think(sanitized));
}

String _sanitizeThinkText(String text) {
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !_shouldDropThinkLine(line))
      .toList(growable: false);

  return lines.join('\n').trim();
}

bool _shouldDropThinkLine(String line) {
  final normalized = line.toLowerCase();
  return normalized.contains('invoking:') ||
      normalized.contains('responded:') ||
      normalized.contains('observation:') ||
      normalized.contains('tool call:') ||
      normalized.contains('tool input:') ||
      normalized.contains('tool output:');
}
