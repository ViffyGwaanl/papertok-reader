import 'package:flutter/widgets.dart';

class SeminarFullWidthSection extends StatelessWidget {
  const SeminarFullWidthSection({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: child,
    );
  }
}
