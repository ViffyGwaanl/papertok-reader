import 'package:anx_reader/app/app_route_observer.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  static const routeName = '/ai_chat';

  static int _openCount = 0;
  static bool _isTop = false;

  static bool get isInStack => _openCount > 0;
  static bool get isTop => _isTop;

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> with RouteAware {
  @override
  void initState() {
    super.initState();
    AiChatPage._openCount++;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() {
    AiChatPage._isTop = true;
  }

  @override
  void didPopNext() {
    AiChatPage._isTop = true;
  }

  @override
  void didPushNext() {
    AiChatPage._isTop = false;
  }

  @override
  void didPop() {
    AiChatPage._isTop = false;
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    AiChatPage._openCount--;
    if (AiChatPage._openCount <= 0) {
      AiChatPage._isTop = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).aiChat),
      ),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: AiChatStream(),
        ),
      ),
    );
  }
}
