/// OKLab 色彩空间（Björn Ottosson, 2020）。
///
/// OKLab 是感知均匀、计算便宜的色彩空间，接近人眼对颜色差异的感受，
/// 且对红色/蓝色跨区匹配比 CIELAB 更稳。用作默认色差距离（可选 CIEDE2000）。
///
/// 纯 Dart 实现（仅依赖 dart:math），无 Flutter 依赖。
library;

import 'dart:math' as math;

import 'color_space.dart';

/// OKLab 颜色（L 0~1，a/b 约 -0.4~0.4）。
class OklabColor {
  final double l;
  final double a;
  final double b;

  const OklabColor(this.l, this.a, this.b);

  @override
  String toString() =>
      'Oklab(${l.toStringAsFixed(4)}, ${a.toStringAsFixed(4)}, ${b.toStringAsFixed(4)})';
}

/// sRGB 线性化（同 color_space.dart 内部函数）。
double _srgbToLinear(int c) {
  final v = c / 255.0;
  if (v <= 0.04045) {
    return v / 12.92;
  }
  return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

/// sRGB（8bit 分量）→ OKLab。
OklabColor srgbToOklab(int r, int g, int b) {
  final rl = _srgbToLinear(r);
  final gl = _srgbToLinear(g);
  final bl = _srgbToLinear(b);

  // sRGB 线性 → LMS
  final l = 0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl;
  final m = 0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl;
  final s = 0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl;

  final l_ = math.pow(l, 1.0 / 3.0).toDouble();
  final m_ = math.pow(m, 1.0 / 3.0).toDouble();
  final s_ = math.pow(s, 1.0 / 3.0).toDouble();

  return OklabColor(
    0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
  );
}

/// CIELAB（D65）→ OKLab（经由 XYZ → 线性 sRGB → OKLab）。
OklabColor labToOklab(LabColor lab) {
  // Lab → XYZ (D65)
  final fy = (lab.l + 16.0) / 116.0;
  final fx = fy + lab.a / 500.0;
  final fz = fy - lab.b / 200.0;

  double fInv(double t) {
    final d = 6.0 / 29.0;
    if (t > d) {
      return t * t * t;
    }
    return 3 * d * d * (t - 4.0 / 29.0);
  }

  const xn = 0.95047;
  const yn = 1.00000;
  const zn = 1.08883;

  final x = xn * fInv(fx);
  final y = yn * fInv(fy);
  final z = zn * fInv(fz);

  // XYZ → 线性 sRGB（D65）
  final rl = x * 3.2404542 - y * 1.5371385 - z * 0.4985314;
  final gl = -x * 0.9692660 + y * 1.8760108 + z * 0.0415560;
  final bl = x * 0.0556434 - y * 0.2040259 + z * 1.0572252;

  double toSrgb(double v) {
    final c = v.clamp(0.0, 1.0);
    if (c <= 0.0031308) {
      return c * 12.92;
    }
    return 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
  }

  final r8 = (toSrgb(rl) * 255).round().clamp(0, 255);
  final g8 = (toSrgb(gl) * 255).round().clamp(0, 255);
  final b8 = (toSrgb(bl) * 255).round().clamp(0, 255);
  return srgbToOklab(r8, g8, b8);
}

/// OKLab 欧氏距离 ×100（放大到与 ΔE 同级量纲，便于比较与展示）。
double oklabDistance(OklabColor a, OklabColor b) {
  final dl = a.l - b.l;
  final da = a.a - b.a;
  final db = a.b - b.b;
  return math.sqrt(dl * dl + da * da + db * db) * 100.0;
}
