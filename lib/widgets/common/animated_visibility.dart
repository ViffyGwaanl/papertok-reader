import 'package:flutter/material.dart';
import '../../theme/app_motion.dart';

class AnimatedVisibility extends StatelessWidget {
  final bool visible;
  final Widget child;
  final Duration duration;
  final Offset slideOffset;

  const AnimatedVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 250),
    this.slideOffset = const Offset(0, -0.05),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeInOut,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: slideOffset, end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      },
      child: visible ? child : const SizedBox.shrink(),
    );
  }
}
