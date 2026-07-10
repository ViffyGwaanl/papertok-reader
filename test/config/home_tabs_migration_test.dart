import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh install defaults to 4 tabs with Bookshelf first', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    final order = Prefs().homeTabsOrder;
    final enabled = Prefs().homeTabsEnabled;

    expect(order.first, Prefs.homeTabBookshelf);
    expect(
      order.take(4).toList(),
      [
        Prefs.homeTabBookshelf,
        Prefs.homeTabPapers,
        Prefs.homeTabAI,
        Prefs.homeTabMine,
      ],
    );
    for (final id in [
      Prefs.homeTabBookshelf,
      Prefs.homeTabPapers,
      Prefs.homeTabAI,
      Prefs.homeTabMine,
    ]) {
      expect(enabled[id], isTrue, reason: '$id should be on by default');
    }
    for (final id in [
      Prefs.homeTabStatistics,
      Prefs.homeTabNotes,
      Prefs.homeTabMemory,
      Prefs.homeTabSettings,
    ]) {
      expect(enabled[id], isFalse, reason: '$id should live inside Mine');
    }
  });

  test('existing v2 user keeps their layout; Mine arrives disabled', () async {
    SharedPreferences.setMockInitialValues({
      'homeTabsSchemaVersion': 2,
      'homeTabsOrder': [
        'papers',
        'bookshelf',
        'statistics',
        'ai',
        'notes',
        'memory',
        'settings',
      ],
      'homeTabsEnabled': jsonEncode({
        'papers': true,
        'bookshelf': true,
        'statistics': true,
        'ai': true,
        'notes': true,
        'memory': false,
        'settings': true,
      }),
    });
    await Prefs().initPrefs();

    final order = Prefs().homeTabsOrder;
    final enabled = Prefs().homeTabsEnabled;

    // Layout untouched: papers still first, settings still enabled.
    expect(order.first, Prefs.homeTabPapers);
    expect(enabled[Prefs.homeTabStatistics], isTrue);
    expect(enabled[Prefs.homeTabSettings], isTrue);
    // Mine exists in the order but stays off — no surprises.
    expect(order.contains(Prefs.homeTabMine), isTrue);
    expect(enabled[Prefs.homeTabMine], isFalse);
  });

  test('settings stays reachable: disabling both settings and mine forces mine',
      () async {
    SharedPreferences.setMockInitialValues({
      'homeTabsSchemaVersion': 3,
      'homeTabsOrder': [
        'bookshelf',
        'papers',
        'ai',
        'mine',
        'statistics',
        'notes',
        'memory',
        'settings',
      ],
      'homeTabsEnabled': jsonEncode({
        'bookshelf': true,
        'papers': true,
        'ai': true,
        'mine': false,
        'statistics': false,
        'notes': false,
        'memory': false,
        'settings': false,
      }),
    });
    await Prefs().initPrefs();

    final enabled = Prefs().homeTabsEnabled;
    expect(enabled[Prefs.homeTabMine], isTrue,
        reason: 'settings entry must stay reachable through the Mine hub');
  });
}
