import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/claude_palette.dart';
import '../../theme/morandi_palette.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_motion.dart';

/// Claude/Apple-style expandable card used for AI "thinking" traces and
/// tool-call panels in the chat stream. A warm neutral surface, a hairline
/// border, a single-line header with an animated chevron, and body content
/// that slides/fades in on expand.
class PTCollapsibleCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget body;
  final bool initiallyExpanded;
  final Color? iconTint;

  const PTCollapsibleCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.body,
    this.initiallyExpanded = false,
    this.iconTint,
  });

  @override
  State<PTCollapsibleCard> createState() => _PTCollapsibleCardState();
}

class _PTCollapsibleCardState extends State<PTCollapsibleCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final tint = widget.iconTint ?? MorandiPalette.taupe(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: ClaudePalette.elevated(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
        border: Border.all(
          color: ClaudePalette.divider(context),
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !_expanded);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Icon(widget.icon, size: 13, color: tint),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ClaudePalette.fg(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.subtitle != null &&
                              widget.subtitle!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                widget.subtitle!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: ClaudePalette.secondary(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      duration: AppMotion.fast,
                      curve: AppMotion.easeOut,
                      turns: _expanded ? 0.25 : 0.0,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: ClaudePalette.secondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: AppMotion.medium,
              sizeCurve: AppMotion.easeInOut,
              firstCurve: AppMotion.easeOut,
              secondCurve: AppMotion.easeOut,
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    fontFamily: 'monospace',
                    color: ClaudePalette.secondary(context),
                  ),
                  child: widget.body,
                ),
              ),
              secondChild: const SizedBox(
                width: double.infinity,
                height: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
