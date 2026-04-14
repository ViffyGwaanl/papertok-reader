import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';

class MemoryRow extends StatelessWidget {
  final MemoryEntryRef entry;
  final VoidCallback onTap;

  const MemoryRow({
    super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ClaudePalette.fg(context),
                ),
              ),
              if (entry.preview.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  entry.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: ClaudePalette.secondary(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
