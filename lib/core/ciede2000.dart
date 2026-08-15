/// CIEDE2000 色差公式（Sharma et al., 2005 标准实现）。
///
/// 参考：G. Sharma, W. Wu, E. N. Dalal, "The CIEDE2000 Color-Difference
/// Formula: Implementation Notes, Supplementary Test Data, and Mathematical
/// Observations", Color Research & Application, 2005.
///
/// 纯 Dart 实现（仅依赖 dart:math），无 Flutter 依赖。
library;

import 'dart:math' as math;

import 'color_space.dart';

/// 计算两个 Lab 颜色的 CIEDE2000 色差 ΔE00。
double ciede2000(LabColor c1, LabColor c2) {
  final l1 = c1.l, a1 = c1.a, b1 = c1.b;
  final l2 = c2.l, a2 = c2.a, b2 = c2.b;

  final c1ab = math.sqrt(a1 * a1 + b1 * b1);
  final c2ab = math.sqrt(a2 * a2 + b2 * b2);
  final cab = (c1ab + c2ab) / 2.0;

  final g = 0.5 *
      (1.0 -
          math.sqrt(math.pow(cab, 7) / (math.pow(cab, 7) + math.pow(25.0, 7))));

  final a1p = (1.0 + g) * a1;
  final a2p = (1.0 + g) * a2;

  final c1p = math.sqrt(a1p * a1p + b1 * b1);
  final c2p = math.sqrt(a2p * a2p + b2 * b2);

  double h1p;
  if (a1p == 0 && b1 == 0) {
    h1p = 0;
  } else {
    h1p = _atan2deg(b1, a1p);
    if (h1p < 0) h1p += 360;
  }

  double h2p;
  if (a2p == 0 && b2 == 0) {
    h2p = 0;
  } else {
    h2p = _atan2deg(b2, a2p);
    if (h2p < 0) h2p += 360;
  }

  final dlp = l2 - l1;
  final dcp = c2p - c1p;

  double dhp;
  if (c1p * c2p == 0) {
    dhp = 0;
  } else if ((h2p - h1p).abs() <= 180) {
    dhp = h2p - h1p;
  } else if (h2p - h1p > 180) {
    dhp = h2p - h1p - 360;
  } else {
    dhp = h2p - h1p + 360;
  }

  final dlhp = 2 * math.sqrt(c1p * c2p) * math.sin(_radians(dhp / 2));

  final lp = (l1 + l2) / 2.0;
  final cp = (c1p + c2p) / 2.0;

  double hpp;
  if (c1p * c2p == 0) {
    hpp = h1p + h2p;
  } else if ((h1p - h2p).abs() <= 180) {
    hpp = (h1p + h2p) / 2.0;
  } else if ((h1p - h2p).abs() > 180 && h1p + h2p < 360) {
    hpp = (h1p + h2p + 360) / 2.0;
  } else {
    hpp = (h1p + h2p - 360) / 2.0;
  }

  final t = 1 -
      0.17 * math.cos(_radians(hpp - 30)) +
      0.24 * math.cos(_radians(2 * hpp)) +
      0.32 * math.cos(_radians(3 * hpp + 6)) -
      0.20 * math.cos(_radians(4 * hpp - 63));

  final dtheta = 30 * math.exp(-math.pow((hpp - 275) / 25, 2));

  final rc = 2 * math.sqrt(math.pow(cp, 7) / (math.pow(cp, 7) + math.pow(25.0, 7)));

  final sl = 1 +
      (0.015 * math.pow(lp - 50, 2)) /
          math.sqrt(20 + math.pow(lp - 50, 2));
  final sc = 1 + 0.045 * cp;
  final sh = 1 + 0.015 * cp * t;

  final rt = -math.sin(_radians(2 * dtheta)) * rc;

  final dl = dlp / sl;
  final dc = dcp / sc;
  final dh = dlhp / sh;

  return math.sqrt(dl * dl + dc * dc + dh * dh + rt * dc * dh);
}

double _radians(double deg) => deg * math.pi / 180.0;

double _atan2deg(double y, double x) => math.atan2(y, x) * 180.0 / math.pi;
