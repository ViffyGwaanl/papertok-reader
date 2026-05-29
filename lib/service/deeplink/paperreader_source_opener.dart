import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_deeplink_handler.dart';

typedef PaperReaderSourceOpener = Future<void> Function(WidgetRef ref, Uri uri);

Future<void> openPaperReaderSource(WidgetRef ref, Uri uri) {
  return PaperReaderDeepLinkHandler.handleIncomingUri(ref, uri);
}

String paperReaderSourceUnavailableMessage(
  Iterable<SourceRef> sourceRefs, {
  required String fallbackMessage,
}) {
  for (final ref in sourceRefs) {
    final reason = ref.unavailableReason?.trim();
    if (reason != null && reason.isNotEmpty) {
      return reason;
    }
  }
  return fallbackMessage;
}

void showPaperReaderSourceUnavailable(
  BuildContext context,
  Iterable<SourceRef> sourceRefs,
  String fallbackMessage,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        paperReaderSourceUnavailableMessage(
          sourceRefs,
          fallbackMessage: fallbackMessage,
        ),
      ),
    ),
  );
}
