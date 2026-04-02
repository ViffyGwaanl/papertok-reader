/// Attempts to repair malformed JSON strings from LLM outputs.
///
/// LLMs (especially Gemini Flash, some OpenRouter models) frequently produce
/// truncated or slightly malformed JSON in structured outputs. Rather than
/// failing the entire tool call, this repair layer fixes common issues:
///
/// - Unclosed strings
/// - Unclosed arrays / objects
/// - Trailing commas
/// - Missing closing brackets
///
/// Inspired by OpenMAIC's `json-repair.ts`.
String repairJson(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;

  // Strip markdown code fences if present
  if (s.startsWith('```')) {
    final firstNewline = s.indexOf('\n');
    if (firstNewline > 0) {
      s = s.substring(firstNewline + 1);
    }
    if (s.endsWith('```')) {
      s = s.substring(0, s.length - 3).trimRight();
    }
  }

  // Remove trailing commas before closing brackets
  s = s.replaceAll(RegExp(r',\s*(\]|\})'), r'$1');

  // Count brackets to find mismatches
  var openBraces = 0;
  var openBrackets = 0;
  var inString = false;
  var escaped = false;

  for (var i = 0; i < s.length; i++) {
    final c = s[i];

    if (escaped) {
      escaped = false;
      continue;
    }

    if (c == r'\') {
      escaped = true;
      continue;
    }

    if (c == '"') {
      inString = !inString;
      continue;
    }

    if (inString) continue;

    switch (c) {
      case '{':
        openBraces++;
      case '}':
        openBraces--;
      case '[':
        openBrackets++;
      case ']':
        openBrackets--;
    }
  }

  // Close unclosed string
  if (inString) {
    s += '"';
  }

  // Remove trailing comma after closing the string
  s = s.replaceAll(RegExp(r',\s*$'), '');

  // Close unclosed brackets/braces
  for (var i = 0; i < openBrackets; i++) {
    s += ']';
  }
  for (var i = 0; i < openBraces; i++) {
    s += '}';
  }

  return s;
}
