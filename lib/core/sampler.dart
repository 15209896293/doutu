/// 网格化区域主色采样。
///
/// 将原图划分为 N×N 网格，每格对覆盖区域统计 RGB 直方图，
/// 取频率最高的颜色作为该格主色（优于单像素最近邻，避免颜色过碎）。
///
/// 依赖 image 包（纯 Dart 解码），不依赖 Flutter。
library;

import 'package:image/image.dart' as img;

/// 采样结果：N×N 的 RGB 矩阵（行优先）。
class SampledGrid {
  final int size;

  /// 行优先存储的 RGB 值（0xRRGGBB）。
  final List<int> colors;

  /// 可选：与每格对应的原图区域平均色（用于参考/对比显示）。
  final List<int> avgColors;

  SampledGrid({
    required this.size,
    required this.colors,
    required this.avgColors,
  });

  int colorAt(int x, int y) => colors[y * size + x];
}

/// 采样参数。
class SamplerOptions {
  /// 目标网格边长（N×N）。
  final int gridSize;

  /// 区域主色的直方图量化步长（把 0-255 压到 step 粒度再投票）。
  /// 值越大越抗噪、主色越"钝"；默认 16。
  final int histogramStep;

  /// 采样前是否先将图片缩放到与网格成整数倍（提高区域统计精度）。
  final bool preScale;

  const SamplerOptions({
    required this.gridSize,
    this.histogramStep = 8,
    this.preScale = true,
  });
}

/// 对已解码图片执行区域主色采样。
///
/// 该函数开销为 O(W×H)，>128×128 网格时建议放入 Isolate 执行。
SampledGrid sampleDominantColors(img.Image image, SamplerOptions options) {
  final n = options.gridSize;
  final w = image.width;
  final h = image.height;

  // 预缩放：使每个格覆盖区域为整数像素，避免边缘像素重复/遗漏。
  img.Image scaled;
  if (options.preScale && (w % n != 0 || h % n != 0)) {
    final sw = ((w + n - 1) ~/ n) * n;
    final sh = ((h + n - 1) ~/ n) * n;
    scaled = img.copyResize(image, width: sw, height: sh,
        interpolation: img.Interpolation.linear);
  } else {
    scaled = image;
  }

  final cellW = scaled.width ~/ n;
  final cellH = scaled.height ~/ n;
  final step = options.histogramStep;

  // 每通道量化级数（step=16 → 16 级 → 4096 桶）
  final qn = (256 + step - 1) ~/ step;

  final colors = List<int>.filled(n * n, 0);
  final avgColors = List<int>.filled(n * n, 0);

  final hist = List<int>.filled(qn * qn * qn + 1, 0);
  // 桶内 RGB 累加（主色取桶内均值，比桶中心更准）
  final sumR = List<int>.filled(qn * qn * qn + 1, 0);
  final sumG = List<int>.filled(qn * qn * qn + 1, 0);
  final sumB = List<int>.filled(qn * qn * qn + 1, 0);

  for (var gy = 0; gy < n; gy++) {
    for (var gx = 0; gx < n; gx++) {
      final x0 = gx * cellW;
      final y0 = gy * cellH;

      // 懒重置：记录本次触碰的桶
      final touched = <int>[];
      var avgR = 0, avgG = 0, avgB = 0;
      var count = 0;

      for (var py = y0; py < y0 + cellH; py++) {
        for (var px = x0; px < x0 + cellW; px++) {
          final p = scaled.getPixel(px, py);
          final r = p.r.toInt();
          final g = p.g.toInt();
          final b = p.b.toInt();
          avgR += r;
          avgG += g;
          avgB += b;
          count++;

          final qr = r ~/ step;
          final qg = g ~/ step;
          final qb = b ~/ step;
          final bucket = qr * qn * qn + qg * qn + qb;
          if (hist[bucket] == 0) touched.add(bucket);
          hist[bucket]++;
          sumR[bucket] += r;
          sumG[bucket] += g;
          sumB[bucket] += b;
        }
      }

      // 主色桶（先记录桶均值，再复位）
      var bestBucket = touched.first;
      var bestCount = -1;
      for (final bucket in touched) {
        if (hist[bucket] > bestCount) {
          bestCount = hist[bucket];
          bestBucket = bucket;
        }
      }
      final cr = (sumR[bestBucket] ~/ bestCount).clamp(0, 255);
      final cg = (sumG[bestBucket] ~/ bestCount).clamp(0, 255);
      final cb = (sumB[bestBucket] ~/ bestCount).clamp(0, 255);
      for (final bucket in touched) {
        hist[bucket] = 0;
        sumR[bucket] = 0;
        sumG[bucket] = 0;
        sumB[bucket] = 0;
      }

      // 主色 = 桶内像素均值（比桶中心色更接近真实主色）
      final idx = gy * n + gx;
      colors[idx] = (cr << 16) | (cg << 8) | cb;
      avgColors[idx] =
          ((avgR ~/ count) << 16) | ((avgG ~/ count) << 8) | (avgB ~/ count);
    }
  }

  return SampledGrid(size: n, colors: colors, avgColors: avgColors);
}
