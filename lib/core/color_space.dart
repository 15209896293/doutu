/// 色彩空间转换：sRGB ⇄ XYZ(D65) ⇄ CIELAB。
///
/// 纯 Dart 实现（仅依赖 dart:math 核心库），无 Flutter 依赖，可独立单元测试。
library;

import 'dart:math' as math;

/// CIE L*a*b* 颜色（D65 白点）。
class LabColor {
  final double l;
  final double a;
  final double b;

  const LabColor(this.l, this.a, this.b);

  @override
  String toString() =>
      'Lab(${l.toStringAsFixed(3)}, ${a.toStringAsFixed(3)}, ${b.toStringAsFixed(3)})';
}

/// 将 sRGB 字节分量（0-255）线性化到 [0,1]。
double _srgbToLinear(int c) {
  final v = c / 255.0;
  if (v <= 0.04045) {
    return v / 12.92;
  }
  return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

/// sRGB（8bit 分量）→ CIELAB（D65）。
LabColor rgbToLab(int r, int g, int b) {
  final rl = _srgbToLinear(r);
  final gl = _srgbToLinear(g);
  final bl = _srgbToLinear(b);

  // sRGB → XYZ (D65)
  final x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375;
  final y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750;
  final z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041;

  return xyzToLab(x, y, z);
}

/// XYZ (D65) → CIELAB。
LabColor xyzToLab(double x, double y, double z) {
  // 白点 D65
  const xn = 0.95047;
  const yn = 1.00000;
  const zn = 1.08883;

  final fx = _fLab(x / xn);
  final fy = _fLab(y / yn);
  final fz = _fLab(z / zn);

  return LabColor(
    116.0 * fy - 16.0,
    500.0 * (fx - fy),
    200.0 * (fy - fz),
  );
}

double _fLab(double t) {
  const delta = 6.0 / 29.0;
  if (t > delta * delta * delta) {
    return math.pow(t, 1.0 / 3.0).toDouble();
  }
  return t / (3 * delta * delta) + 4.0 / 29.0;
}
