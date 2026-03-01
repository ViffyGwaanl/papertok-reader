import 'dart:async';
import 'dart:isolate';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_channel.dart';
import 'package:flutter/widgets.dart';

/// Headless entrypoint used by iOS App Intents.
///
/// Swift starts a dedicated FlutterEngine with this entrypoint, then calls the
/// `papertok_reader/shortcuts` MethodChannel.
@pragma('vm:entry-point')
Future<void> papertokShortcutsMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure prefs are ready (Prefs constructor kicks this off, but we want to
  // await it deterministically in a headless context).
  await Prefs().initPrefs();

  PapertokShortcutsChannel.register();

  // Keep the isolate alive for subsequent invocations (engine caching).
  // The engine may still be terminated by iOS at any time; this is best-effort.
  final port = ReceivePort();
  await port.first;
}
