import 'package:flutter/material.dart';

class SeminarExpandableText extends StatefulWidget {
  const SeminarExpandableText({
    super.key,
    required this.text,
    required this.expandLabel,
    required this.collapseLabel,
    this.collapsedMaxLines = 3,
    this.expandedMaxHeight = 220,
    this.style,
    this.textAlign,
  });

  final String text;
  final String expandLabel;
  final String collapseLabel;
  final int collapsedMaxLines;
  final double expandedMaxHeight;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  State<SeminarExpandableText> createState() => _SeminarExpandableTextState();
}

class _SeminarExpandableTextState extends State<SeminarExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final label = _expanded ? widget.collapseLabel : widget.expandLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_expanded)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.expandedMaxHeight),
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                textAlign: widget.textAlign,
                style: widget.style,
              ),
            ),
          )
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Text(
              text,
              maxLines: widget.collapsedMaxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: widget.textAlign,
              style: widget.style,
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _toggle,
            icon: Icon(
              _expanded
                  ? Icons.unfold_less_outlined
                  : Icons.unfold_more_outlined,
              size: 16,
            ),
            label: Text(label),
          ),
        ),
      ],
    );
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
    });
  }
}
