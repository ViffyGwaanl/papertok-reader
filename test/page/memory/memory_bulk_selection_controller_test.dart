// test/page/memory/memory_bulk_selection_controller_test.dart
import 'package:anx_reader/page/memory/memory_bulk_selection_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts out of selection mode and empty', () {
    final c = MemoryBulkSelectionController();
    expect(c.inSelectionMode, isFalse);
    expect(c.selected, isEmpty);
    expect(c.selectionCount, 0);
  });

  test('enter + toggle tracks ids and fires notifications', () {
    final c = MemoryBulkSelectionController();
    var notifications = 0;
    c.addListener(() => notifications++);

    c.enter(seedId: 'a');
    expect(c.inSelectionMode, isTrue);
    expect(c.selected, {'a'});

    c.toggle('b');
    expect(c.selected, {'a', 'b'});

    c.toggle('a');
    expect(c.selected, {'b'});
    expect(c.inSelectionMode, isTrue);
    expect(notifications, greaterThanOrEqualTo(3));
  });

  test('toggle down to zero stays in selection mode', () {
    final c = MemoryBulkSelectionController();
    c.enter(seedId: 'only');
    c.toggle('only');
    expect(c.selected, isEmpty);
    expect(c.inSelectionMode, isTrue); // caller must explicitly clear
  });

  test('clear exits selection mode and empties set', () {
    final c = MemoryBulkSelectionController();
    c.enter(seedId: 'a');
    c.toggle('b');
    c.clear();
    expect(c.inSelectionMode, isFalse);
    expect(c.selected, isEmpty);
  });

  test('selectAll merges ids and enters mode', () {
    final c = MemoryBulkSelectionController();
    c.selectAll(['b', 'c']);
    expect(c.inSelectionMode, isTrue);
    expect(c.selected, {'b', 'c'});

    c.selectAll(['c', 'd']);
    expect(c.selected, {'b', 'c', 'd'});
  });

  test('enter without seedId still activates mode', () {
    final c = MemoryBulkSelectionController();
    c.enter();
    expect(c.inSelectionMode, isTrue);
    expect(c.selected, isEmpty);
  });
}
