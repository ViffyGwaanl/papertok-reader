import 'package:papertok_reader/theme/morandi_palette.dart';
import 'package:papertok_reader/widgets/common/pt_collapsible_card.dart';
import 'package:flutter/material.dart';

/// Chat-friendly collapsible section used for "thinking" traces and tool-call
/// panels. Thin wrapper over [PTCollapsibleCard] so existing call sites keep
/// working while adopting the Wave 1 Morandi card design.
class AiCollapsibleSection extends StatelessWidget {
  const AiCollapsibleSection({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconTint,
    this.initiallyExpanded = false,
    required this.child,
    @Deprecated('Replaced by icon/iconTint') this.leading,
    @Deprecated('No longer rendered') this.preview,
    @Deprecated('No longer rendered') this.copyText,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconTint;
  final bool initiallyExpanded;
  final Widget child;

  // Legacy, unused — kept to avoid breaking older call sites.
  final Widget? leading;
  final String? preview;
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    return PTCollapsibleCard(
      icon: icon ?? Icons.notes_outlined,
      title: title,
      subtitle: subtitle,
      iconTint: iconTint ?? MorandiPalette.taupe(context),
      initiallyExpanded: initiallyExpanded,
      body: child,
    );
  }
}
