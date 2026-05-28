import 'package:papertok_reader/models/toc_item.dart';

class AiIndexChapter {
  const AiIndexChapter({
    required this.href,
    required this.title,
    required this.chapterOrder,
    required this.tocLevel,
    required this.tocPath,
  });

  final String href;
  final String title;
  final int chapterOrder;
  final int tocLevel;
  final String tocPath;
}

class AiIndexChapterPlan {
  const AiIndexChapterPlan._();

  static List<AiIndexChapter> flattenToc(List<TocItem> toc) {
    final out = <AiIndexChapter>[];
    final seen = <String>{};

    void walk(TocItem item, List<String> parentPath) {
      final label = item.label.trim();
      final path = [
        ...parentPath,
        if (label.isNotEmpty) label,
      ];
      final href = item.href.trim();

      if (href.isNotEmpty && seen.add(href)) {
        out.add(
          AiIndexChapter(
            href: href,
            title: label,
            chapterOrder: out.length,
            tocLevel: item.level,
            tocPath: path.join(' / '),
          ),
        );
      }

      for (final sub in item.subitems) {
        walk(sub, path);
      }
    }

    for (final item in toc) {
      walk(item, const []);
    }

    return List.unmodifiable(out);
  }
}
