import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Chip-based free-form tag editor used by the Memory detail page and the
/// bulk-add-tag bottom sheet. Selected tags render in accent-tinted pills;
/// unselected suggestion chips render in ghost style so tapping either
/// adds (suggestion → selected) or removes (selected → suggestion).
///
/// Free-form input: typing a new tag and hitting "done" adds it.
/// Duplicate tags are silently ignored.
class TagEditor extends StatefulWidget {
  final List<String> initial;
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;

  const TagEditor({
    super.key,
    required this.initial,
    required this.suggestions,
    required this.onChanged,
  });

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  late List<String> _tags = List<String>.from(widget.initial);
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty) {
      _controller.clear();
      return;
    }
    if (_tags.contains(tag)) {
      _controller.clear();
      return; // duplicates are a no-op
    }
    setState(() {
      _tags = [..._tags, tag];
      _controller.clear();
    });
    widget.onChanged(_tags);
  }

  void _remove(String tag) {
    if (!_tags.contains(tag)) return;
    setState(() {
      _tags = _tags.where((t) => t != tag).toList(growable: false);
    });
    widget.onChanged(_tags);
  }

  @override
  Widget build(BuildContext context) {
    final suggestionChips = widget.suggestions
        .where((s) => !_tags.contains(s))
        .take(6)
        .toList(growable: false);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final tag in _tags) _chip(context, tag, selected: true),
        SizedBox(
          width: 140,
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            onSubmitted: _add,
            style: TextStyle(
              fontSize: 13,
              color: ClaudePalette.fg(context),
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add tag…',
              hintStyle: TextStyle(
                fontSize: 13,
                color: ClaudePalette.tertiary(context),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        for (final suggestion in suggestionChips)
          _chip(context, suggestion, selected: false),
      ],
    );
  }

  Widget _chip(BuildContext context, String tag, {required bool selected}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          if (selected) {
            _remove(tag);
          } else {
            _add(tag);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? ClaudePalette.accentTint(context)
                : ClaudePalette.bg(context).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? ClaudePalette.accent(context).withValues(alpha: 0.35)
                  : ClaudePalette.divider(context),
              width: 0.5,
            ),
          ),
          child: Text(
            tag,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected
                  ? ClaudePalette.accent(context)
                  : ClaudePalette.secondary(context),
            ),
          ),
        ),
      ),
    );
  }
}
