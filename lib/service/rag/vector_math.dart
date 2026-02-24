import 'dart:math' as math;

class VectorMath {
  const VectorMath._();

  static double l2Norm(List<double> v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    return math.sqrt(sum);
  }

  static double dot(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  static double cosineSimilarity(
    List<double> a,
    List<double> b, {
    double? aNorm,
    double? bNorm,
  }) {
    final an = aNorm ?? l2Norm(a);
    final bn = bNorm ?? l2Norm(b);
    if (an == 0 || bn == 0) return 0;
    return dot(a, b) / (an * bn);
  }
}
