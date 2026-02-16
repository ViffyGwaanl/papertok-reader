import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

class PapersPage extends StatelessWidget {
  const PapersPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(L10n.of(context).navBarPapers),
      ),
    );
  }
}
