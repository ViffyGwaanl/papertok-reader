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
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: child,
    );
  }
}
