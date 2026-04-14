import 'package:anx_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';

/// A thin wrapper to give settings subpages a consistent Material Scaffold +
/// AppBar (similar to Home Navigation / Provider Center pages).
///
/// Many legacy settings subpages only return a ListView body.
class SettingsSubpageScaffold extends StatelessWidget {
  const SettingsSubpageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClaudePalette.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: ClaudePalette.fg(context),
          ),
        ),
        iconTheme: IconThemeData(color: ClaudePalette.fg(context)),
        actions: actions,
      ),
      body: child,
    );
  }
}
