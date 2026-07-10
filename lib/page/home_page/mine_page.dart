import 'package:flutter/material.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/home_page/notes_page.dart';
import 'package:papertok_reader/page/home_page/settings_page.dart';
import 'package:papertok_reader/page/home_page/statistics_page.dart';
import 'package:papertok_reader/page/memory/memory_home_page.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/theme/claude_palette.dart';

/// "Mine" hub tab (E4 batch 2): aggregates the pages removed from the
/// default bottom bar. Pure navigation — reuses the existing pages
/// unchanged; each can still be promoted back to a first-level tab from
/// home-navigation settings.
class MinePage extends StatelessWidget {
  const MinePage({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  void _pushWrapped(BuildContext context, String title, Widget page) {
    _push(
      context,
      SettingsSubpageScaffold(title: title, child: page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final entries = <_MineEntry>[
      _MineEntry(
        icon: Icons.show_chart,
        label: l10n.navBarStatistics,
        onTap: () => _pushWrapped(
            context, l10n.navBarStatistics, const StatisticPage()),
      ),
      _MineEntry(
        icon: Icons.note_outlined,
        label: l10n.navBarNotes,
        onTap: () => _pushWrapped(context, l10n.navBarNotes, const NotesPage()),
      ),
      _MineEntry(
        icon: Icons.psychology_outlined,
        label: l10n.navBarMemory,
        // MemoryHomePage has its own Scaffold/AppBar (back button appears
        // automatically when pushed).
        onTap: () => _push(context, const MemoryHomePage()),
      ),
      _MineEntry(
        icon: Icons.settings_outlined,
        label: l10n.navBarSettings,
        onTap: () =>
            _pushWrapped(context, l10n.navBarSettings, const SettingsPage()),
      ),
    ];

    return Scaffold(
      backgroundColor: ClaudePalette.bg(context),
      appBar: AppBar(
        title: Text(l10n.navBarMine),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return ListTile(
              leading: Icon(entry.icon),
              title: Text(entry.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: entry.onTap,
            );
          },
        ),
      ),
    );
  }
}

class _MineEntry {
  const _MineEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}
