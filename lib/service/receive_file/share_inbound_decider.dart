import 'package:anx_reader/service/receive_file/share_routing_models.dart';

/// Pure routing decisions for inbound share payload.
///
/// This is intentionally side-effect-free and testable.
class ShareInboundDecider {
  ShareInboundDecider._();

  /// Policy: mixed share should NOT auto-import bookshelf files; only show cards.
  static const bool mixedPolicyB = true;

  static ShareDecision decide({
    required SharePanelMode mode,
    required ShareInboundPayload payload,
  }) {
    switch (mode) {
      case SharePanelMode.ask:
        return ShareDecision.askUser();

      case SharePanelMode.aiChat:
        // Always route to AI chat; bookshelf candidates become optional cards.
        return ShareDecision.aiChat(bookshelfFileCards: payload.bookshelfFiles);

      case SharePanelMode.bookshelf:
        // Force bookshelf: import what we can; if nothing is importable, fallback to AI.
        final importable = payload.bookshelfFiles;
        if (importable.isEmpty) {
          return ShareDecision.aiChat(bookshelfFileCards: const []);
        }
        return ShareDecision.bookshelf(
          importFiles: importable.map((e) => e.path).toList(),
        );

      case SharePanelMode.auto:
        // If payload contains ONLY importable bookshelf files, import them.
        if (payload.hasOnlyBookshelfFiles) {
          return ShareDecision.bookshelf(
            importFiles: payload.bookshelfFiles.map((e) => e.path).toList(),
          );
        }

        // Otherwise route to AI.
        // Mixed share policy B: do not auto-import; show cards.
        return ShareDecision.aiChat(
          bookshelfFileCards: mixedPolicyB ? payload.bookshelfFiles : const [],
        );
    }
  }
}
