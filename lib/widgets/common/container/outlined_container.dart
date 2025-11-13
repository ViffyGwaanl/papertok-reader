import 'package:anx_reader/widgets/common/container/base_rounded_container.dart';
import 'package:flutter/material.dart';

class OutlinedContainer extends BaseRoundedContainer {
  const OutlinedContainer({
    super.key,
    required super.child,
    super.width,
    super.height,
    super.padding,
    super.margin,
    super.radius,
    super.constraints,
    super.animationDuration,
    super.animationCurve,
  });

  @override
  ShapeDecoration decoration(
    BuildContext context,
    BorderRadiusGeometry borderRadius,
  ) {
    return buildShapeDecoration(
      color: Colors.transparent,
      borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
          strokeAlign: BorderSide.strokeAlignOutside),
      borderRadius: borderRadius,
    );
  }
}
