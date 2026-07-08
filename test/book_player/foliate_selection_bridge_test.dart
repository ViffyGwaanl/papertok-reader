import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple selection bridge re-emits settled touch selection changes', () {
    final source = File('assets/foliate-js/src/book.js').readAsStringSync();
    final block = _appleSelectionBlock(source);

    expect(block, contains("doc.addEventListener('pointerdown', (e) => {"));
    expect(block, contains("doc.addEventListener('pointerup', (e) => {"));
    expect(block, contains("e.pointerType !== 'mouse'"));
    expect(block, contains('isMouseSelecting = true;'));
    expect(block, contains('isMouseSelecting = false;'));
    expect(block, contains("doc.addEventListener('selectionchange', () => {"));
    expect(block, contains('if (isMouseSelecting) return;'));
    expect(block, contains('clearTimeout(debounceTimerId);'));
    expect(
      RegExp(r'setTimeout\(\(\) => \{[\s\S]*handleSelection\(view, doc, index\);[\s\S]*\}, 5\d\d\);')
          .hasMatch(block),
      isTrue,
    );
  });
}

String _appleSelectionBlock(String source) {
  final start = source.indexOf("if (navigator.platform.includes('Mac')");
  final end = source.indexOf(
    "else if (navigator.platform.includes('Win'))",
    start,
  );
  expect(start, isNot(-1));
  expect(end, isNot(-1));
  return source.substring(start, end);
}
