import 'package:flutter/material.dart';

abstract class BaseRoundedContainer extends StatelessWidget {
  const BaseRoundedContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.radius,
    this.animationDuration = const Duration(milliseconds: 250),
    this.animationCurve = Curves.easeInOut,
  });

  static const double _defaultRadius = 30;

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;
  final Duration animationDuration;
  final Curve animationCurve;

  BorderRadiusGeometry get _borderRadius =>
      BorderRadiusGeometry.circular(radius ?? _defaultRadius);

  @override
  Widget build(BuildContext context) {
    final BorderRadiusGeometry borderRadius = _borderRadius;

    return ClipRSuperellipse(
      borderRadius: borderRadius,
      child: AnimatedContainer(
        duration: animationDuration,
        curve: animationCurve,
        margin: margin,
        padding: padding,
        width: width,
        height: height,
        decoration: decoration(context, borderRadius),
        child: child,
      ),
    );
  }

  ShapeDecoration decoration(
    BuildContext context,
    BorderRadiusGeometry borderRadius,
  );

  @protected
  ShapeDecoration buildShapeDecoration({
    Color? color,
    required BorderSide borderSide,
    required BorderRadiusGeometry borderRadius,
  }) {
    return ShapeDecoration(
      color: color,
      shape: RoundedSuperellipseBorder(
        borderRadius: borderRadius,
        side: borderSide,
      ),
    );
  }
}
