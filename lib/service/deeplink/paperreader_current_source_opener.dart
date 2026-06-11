import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';

class PaperReaderCurrentSourceOpener {
  const PaperReaderCurrentSourceOpener._();

  static bool tryOpen({
    required Uri uri,
    required int currentBookId,
    required void Function(String cfi) goToCfi,
    required void Function(String href) goToHref,
    void Function()? beforeOpen,
  }) {
    final intent = PaperReaderReaderIntent.tryParse(uri);
    if (intent == null || intent.bookId != currentBookId) return false;

    final cfi = intent.cfi?.trim();
    if (cfi != null && cfi.isNotEmpty) {
      beforeOpen?.call();
      goToCfi(cfi);
      return true;
    }

    final href = intent.href?.trim();
    if (href != null && href.isNotEmpty) {
      beforeOpen?.call();
      goToHref(href);
      return true;
    }

    return false;
  }
}
