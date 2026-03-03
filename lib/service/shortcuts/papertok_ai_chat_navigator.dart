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

    if (openNew) {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: AiChatPage.routeName),
        builder: (_) => const AiChatPage(),
      );
      nav.push(route);
      return;
    }

    // Reuse mode: do NOT push another chat page (users expect the Home AI tab).
    // Pop to root and request HomePage to switch to the AI tab.
    nav.popUntil((r) => r.isFirst);
    homeTabRequest.value = Prefs.homeTabAI;
  }
}
