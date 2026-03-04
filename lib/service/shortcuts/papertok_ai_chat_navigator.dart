import 'package:anx_reader/app/app_globals.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/settings_page/subpage/ai_chat_page.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';

class PapertokAiChatNavigator {
  PapertokAiChatNavigator._();

  static const _homeAiTimeout = Duration(milliseconds: 650);

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
      _pushAiChatPage(nav);
      return;
    }

    // Default: land on Home AI tab (best UX), but keep a reliable fallback.
    final ok = await _tryShowHomeAiTab(nav);
    if (ok) return;

    AnxLog.warning(
        'shortcuts: home AI tab not ready; falling back to AiChatPage');
    _pushAiChatPage(nav);
  }

  static void _pushAiChatPage(NavigatorState nav) {
    if (AiChatPage.isTop) return;

    final route = MaterialPageRoute(
      settings: const RouteSettings(name: AiChatPage.routeName),
      builder: (_) => const AiChatPage(),
    );
    nav.push(route);
  }

  static Future<bool> _tryShowHomeAiTab(NavigatorState nav) async {
    nav.popUntil((r) => r.isFirst);
    homeTabRequest.value = Prefs.homeTabAI;

    final deadline = DateTime.now().add(_homeAiTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (homeTabCurrent.value == Prefs.homeTabAI) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    return false;
  }
}
