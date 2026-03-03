import 'package:flutter/widgets.dart';

/// Global navigator key for app-wide navigation.
///
/// Kept outside of `main.dart` to avoid circular imports between app services
/// and the app entry point.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Best-effort home tab switching.
///
/// The HomePage holds its tab state internally; this is a lightweight bridge
/// for external callers (e.g. iOS Shortcuts) to request a tab switch.
final ValueNotifier<String?> homeTabRequest = ValueNotifier<String?>(null);

/// Observability: what tab HomePage last reported being on.
final ValueNotifier<String?> homeTabCurrent = ValueNotifier<String?>(null);
