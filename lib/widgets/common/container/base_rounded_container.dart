import 'package:flutter/material.dart';

import '../../../theme/app_elevation.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_spacing.dart';

abstract class BaseRoundedContainer extends StatelessWidget {
  const BaseRoundedContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.radius,
    this.constraints,
    this.animationDuration = AppMotion.medium,
    this.animationCurve = Curves.easeInOut,
    this.elevation,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;
  final BoxConstraints? constraints;
  final Duration animationDuration;
  final Curve animationCurve;

  /// Optional shadow elevation level (1-4). Picks from [AppElevation].
  /// When null, no drop shadow is applied by the base container.
  final int? elevation;

  BorderRadiusGeometry get _borderRadius =>
      BorderRadiusGeometry.circular(radius ?? AppSpacing.cornerRadius);

  List<BoxShadow>? _resolveShadows(BuildContext context) {
    switch (elevation) {
      case 1:
        return AppElevation.level1(context);
      case 2:
        return AppElevation.level2(context);
      case 3:
        return AppElevation.level3(context);
      case 4:
        return AppElevation.level4(context);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadiusGeometry borderRadius = _borderRadius;
    final shadows = _resolveShadows(context);

    final animated = AnimatedContainer(
      duration: animationDuration,
      curve: animationCurve,
      margin: margin?.add(const EdgeInsets.all(1)) ?? const EdgeInsets.all(1),
      width: width,
      height: height,
      constraints: constraints,
      decoration: decoration(context, borderRadius),
      child: ClipRSuperellipse(
        borderRadius: borderRadius,
        child: Container(
          padding: padding,
          child: child,
        ),
      ),
    );

    if (shadows == null) {
      return animated;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius:
            borderRadius.resolve(Directionality.of(context)),
        boxShadow: shadows,
      ),
      child: animated,
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
