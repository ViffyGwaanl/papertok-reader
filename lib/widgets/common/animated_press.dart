import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_motion.dart';

class AnimatedPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  const AnimatedPress({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
  });

  @override
  State<AnimatedPress> createState() => _AnimatedPressState();
}

class _AnimatedPressState extends State<AnimatedPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onTap!.call();
            },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: AppMotion.fast,
        curve: AppMotion.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1.0,
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
