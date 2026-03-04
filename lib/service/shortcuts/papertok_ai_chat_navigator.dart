import 'package:anx_reader/app/app_globals.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/settings_page/subpage/ai_chat_page.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';

class PapertokAiChatNavigator {
  PapertokAiChatNavigator._();

  static Future<void> show({bool? forceNewWindow}) async {
    final ctx = navigatorKey.currentContext;
    final nav = navigatorKey.currentState;

    if (ctx == null || nav == null) {
      AnxLog.warning('shortcuts: navigator not ready');
      return;
    }

    final presentation = Prefs().shortcutsSendMessagePresentationV1;
    final openNew = forceNewWindow ?? (presentation == 'new');

    final route = MaterialPageRoute(
      settings: const RouteSettings(name: AiChatPage.routeName),
      builder: (_) => const AiChatPage(),
    );

    if (openNew) {
      nav.push(route);
      return;
    }

    // Reuse mode: ensure we end up with a single AiChatPage on top.
    // This is more reliable than Home tab switching for cold-start Shortcuts.
    if (AiChatPage.isTop) {
      return;
    }

    if (AiChatPage.isInStack) {
      nav.popUntil((r) => r.settings.name == AiChatPage.routeName);
      return;
    }

    nav.push(route);
  }
}
