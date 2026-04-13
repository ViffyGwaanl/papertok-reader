import 'package:flutter/material.dart';
import '../theme/app_motion.dart';

/// Slide-from-right page route matching iOS NavigationStack feel.
class CupertinoStyleRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  CupertinoStyleRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondary) => page,
          transitionsBuilder: (context, animation, secondary, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            final tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: Curves.easeOutCubic),
            );

            // Outgoing: fade + slight slide left
            final fade = Tween<double>(begin: 0.0, end: 1.0).animate(animation);

            return SlideTransition(
              position: animation.drive(tween),
              child: FadeTransition(opacity: fade, child: child),
            );
          },
          transitionDuration: AppMotion.medium,
          reverseTransitionDuration: AppMotion.medium,
        );
}

/// Fade-only modal transition for sheets and dialogs.
class FadeRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadeRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondary) => page,
          transitionsBuilder: (context, animation, secondary, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: AppMotion.fast,
        );
}
