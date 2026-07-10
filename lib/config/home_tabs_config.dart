import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Home bottom-bar tab configuration: schema migration, normalization and
/// persistence. Extracted from Prefs (E4 batch 2) — Prefs keeps thin
/// delegating members so its public API is unchanged.
///
/// Tab ids mirror the `Prefs.homeTab*` constants (kept there because the
/// whole codebase references them through Prefs).
const int kHomeTabsSchemaVersion = 3;
const String kHomeTabsSchemaVersionKey = 'homeTabsSchemaVersion';
const String kHomeTabsOrderKey = 'homeTabsOrder';
const String kHomeTabsEnabledKey = 'homeTabsEnabled';

const String kHomeTabPapers = 'papers';
const String kHomeTabBookshelf = 'bookshelf';
const String kHomeTabStatistics = 'statistics';
const String kHomeTabAI = 'ai';
const String kHomeTabNotes = 'notes';
const String kHomeTabMemory = 'memory';
const String kHomeTabMine = 'mine';
const String kHomeTabSettings = 'settings';

const List<String> kHomeTabAll = [
  kHomeTabPapers,
  kHomeTabBookshelf,
  kHomeTabStatistics,
  kHomeTabAI,
  kHomeTabNotes,
  kHomeTabMemory,
  kHomeTabMine,
  kHomeTabSettings,
];

const Set<String> kHomeTabMandatory = {
  kHomeTabPapers,
};

// E4 batch 2 default (schema v3): Bookshelf (home) / Discover / AI / Mine.
// Statistics, Notes, Memory, Settings live inside the Mine hub and can be
// re-enabled as first-level tabs from home-navigation settings.
const List<String> kDefaultHomeTabsOrderV3 = [
  kHomeTabBookshelf,
  kHomeTabPapers,
  kHomeTabAI,
  kHomeTabMine,
  kHomeTabStatistics,
  kHomeTabNotes,
  kHomeTabMemory,
  kHomeTabSettings,
];

const Map<String, bool> kDefaultHomeTabsEnabledV3 = {
  kHomeTabBookshelf: true,
  kHomeTabPapers: true,
  kHomeTabAI: true,
  kHomeTabMine: true,
  kHomeTabStatistics: false,
  kHomeTabNotes: false,
  kHomeTabMemory: false,
  kHomeTabSettings: false,
};

void migrateHomeTabsIfNeeded(SharedPreferences prefs) {
  final v = prefs.getInt(kHomeTabsSchemaVersionKey);
  final hasOrder = prefs.getStringList(kHomeTabsOrderKey) != null;
  final hasEnabled = prefs.getString(kHomeTabsEnabledKey) != null;

  if (v == kHomeTabsSchemaVersion && hasOrder && hasEnabled) {
    return;
  }

  // v1/v2 → v3: preserve the user's existing layout untouched; tabs added
  // by newer schemas arrive disabled so existing users are never surprised
  // ('mine' for everyone below v3, 'memory' additionally for v1).
  if ((v == 1 || v == 2) && hasOrder && hasEnabled) {
    final order = List<String>.from(
        prefs.getStringList(kHomeTabsOrderKey) ?? const <String>[]);
    final storedEnabledJson = prefs.getString(kHomeTabsEnabledKey) ?? '{}';
    final decoded = jsonDecode(storedEnabledJson);
    final Map<String, dynamic> rawEnabled =
        decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    final enabled = <String, bool>{
      for (final entry in rawEnabled.entries)
        entry.key: entry.value is bool ? entry.value as bool : true,
    };

    void insertBeforeSettings(String id) {
      if (order.contains(id)) return;
      final settingsIdx = order.indexOf(kHomeTabSettings);
      if (settingsIdx >= 0) {
        order.insert(settingsIdx, id);
      } else {
        order.add(id);
      }
    }

    if (v == 1) {
      insertBeforeSettings(kHomeTabMemory);
      enabled.putIfAbsent(kHomeTabMemory, () => false);
    }
    insertBeforeSettings(kHomeTabMine);
    enabled.putIfAbsent(kHomeTabMine, () => false);

    prefs.setInt(kHomeTabsSchemaVersionKey, kHomeTabsSchemaVersion);
    prefs.setStringList(kHomeTabsOrderKey, order);
    prefs.setString(kHomeTabsEnabledKey, jsonEncode(enabled));
    return;
  }

  // Pre-schema builds carried bottomNavigator* switches: keep their
  // familiar layout (respecting those switches); Mine arrives disabled.
  final hasLegacySwitches =
      prefs.getBool('bottomNavigatorShowStatistics') != null ||
          prefs.getBool('bottomNavigatorShowAI') != null ||
          prefs.getBool('bottomNavigatorShowNote') != null;
  if (hasLegacySwitches) {
    final legacyShowStatistics =
        prefs.getBool('bottomNavigatorShowStatistics') ?? false;
    final legacyShowAI = prefs.getBool('bottomNavigatorShowAI') ?? true;
    final legacyShowNotes = prefs.getBool('bottomNavigatorShowNote') ?? false;

    final legacyOrder = <String>[
      kHomeTabPapers,
      kHomeTabBookshelf,
      kHomeTabStatistics,
      kHomeTabAI,
      kHomeTabNotes,
      kHomeTabMemory,
      kHomeTabMine,
      kHomeTabSettings,
    ];

    final enabled = <String, bool>{
      kHomeTabPapers: true,
      kHomeTabBookshelf: true,
      kHomeTabStatistics: legacyShowStatistics,
      kHomeTabAI: legacyShowAI,
      kHomeTabNotes: legacyShowNotes,
      kHomeTabMemory: false,
      kHomeTabMine: false,
      kHomeTabSettings: true,
    };

    prefs.setInt(kHomeTabsSchemaVersionKey, kHomeTabsSchemaVersion);
    prefs.setStringList(kHomeTabsOrderKey, legacyOrder);
    prefs.setString(kHomeTabsEnabledKey, jsonEncode(enabled));
    return;
  }

  // Fresh install: 4-tab default (E4 batch 2).
  prefs.setInt(kHomeTabsSchemaVersionKey, kHomeTabsSchemaVersion);
  prefs.setStringList(kHomeTabsOrderKey, kDefaultHomeTabsOrderV3);
  prefs.setString(kHomeTabsEnabledKey, jsonEncode(kDefaultHomeTabsEnabledV3));
}

List<String> normalizeHomeTabsOrder(List<String> raw) {
  final out = <String>[];
  final seen = <String>{};

  for (final id in raw) {
    if (!kHomeTabAll.contains(id)) continue;
    if (seen.contains(id)) continue;
    seen.add(id);
    out.add(id);
  }

  // Ensure critical tabs exist in the order even if the config is
  // corrupted (enabled-state decides visibility separately).
  if (!seen.contains(kHomeTabPapers)) {
    out.insert(0, kHomeTabPapers);
    seen.add(kHomeTabPapers);
  }
  if (!seen.contains(kHomeTabSettings)) {
    out.add(kHomeTabSettings);
    seen.add(kHomeTabSettings);
  }
  if (!seen.contains(kHomeTabMine)) {
    out.add(kHomeTabMine);
    seen.add(kHomeTabMine);
  }

  // Append any newly added tabs.
  for (final id in kHomeTabAll) {
    if (!seen.contains(id)) out.add(id);
  }

  return out;
}

Map<String, bool> normalizeHomeTabsEnabled(Map<String, bool> raw) {
  final out = <String, bool>{};
  for (final id in kHomeTabAll) {
    out[id] = raw[id] ?? true;
  }
  // Mandatory tabs cannot be disabled.
  for (final id in kHomeTabMandatory) {
    out[id] = true;
  }
  // Settings must stay reachable: either the Settings tab itself or the
  // Mine hub (which contains the Settings entry) has to be enabled.
  if (out[kHomeTabSettings] != true && out[kHomeTabMine] != true) {
    out[kHomeTabMine] = true;
  }
  return out;
}

Map<String, bool> readHomeTabsEnabled(SharedPreferences prefs) {
  final enabledStr = prefs.getString(kHomeTabsEnabledKey);
  Map<String, bool> enabled;
  if (enabledStr == null || enabledStr.trim().isEmpty) {
    enabled = <String, bool>{};
  } else {
    try {
      final dynamic decoded = jsonDecode(enabledStr);
      if (decoded is Map) {
        enabled = decoded
            .map((key, value) => MapEntry(key.toString(), value == true));
      } else {
        enabled = <String, bool>{};
      }
    } catch (_) {
      enabled = <String, bool>{};
    }
  }
  return normalizeHomeTabsEnabled(enabled);
}

List<String> readHomeTabsOrder(SharedPreferences prefs) {
  return normalizeHomeTabsOrder(
      prefs.getStringList(kHomeTabsOrderKey) ?? const []);
}

void normalizeAndPersistHomeTabsConfig(SharedPreferences prefs) {
  final order = readHomeTabsOrder(prefs);
  final enabledNormalized = readHomeTabsEnabled(prefs);

  prefs.setInt(kHomeTabsSchemaVersionKey, kHomeTabsSchemaVersion);
  prefs.setStringList(kHomeTabsOrderKey, order);
  prefs.setString(kHomeTabsEnabledKey, jsonEncode(enabledNormalized));
}

void writeHomeTabsOrder(SharedPreferences prefs, List<String> order) {
  prefs.setStringList(kHomeTabsOrderKey, normalizeHomeTabsOrder(order));
}

void writeHomeTabEnabled(SharedPreferences prefs, String tabId, bool enabled) {
  final map0 = Map<String, bool>.from(readHomeTabsEnabled(prefs));
  if (kHomeTabMandatory.contains(tabId)) {
    map0[tabId] = true;
  } else {
    map0[tabId] = enabled;
  }
  prefs.setString(
      kHomeTabsEnabledKey, jsonEncode(normalizeHomeTabsEnabled(map0)));
}

void resetHomeTabsToDefault(SharedPreferences prefs) {
  prefs.setInt(kHomeTabsSchemaVersionKey, kHomeTabsSchemaVersion);
  prefs.setStringList(kHomeTabsOrderKey, kDefaultHomeTabsOrderV3);
  prefs.setString(
      kHomeTabsEnabledKey,
      jsonEncode(normalizeHomeTabsEnabled(
          Map<String, bool>.from(kDefaultHomeTabsEnabledV3))));
}
