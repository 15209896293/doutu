/// 网格化采样：每格 dominant-bucket 主色 + 前景覆盖度 + 轮廓检测。
///
/// 参考 pixel-beads.com 的 `je()` 实现思路：
/// - 每格按「重叠面积 × alpha」加权聚合像素；
/// - dominant-bucket：把格内像素按 colorBucketBits 位量化成桶，取权重最大桶的加权均值
///   （众数优先，避免「均值把深色+浅色混成灰」导致的灰色毛边）；
/// - 前景覆盖度：有效像素权重 / 格面积，低于 minimumForegroundCoverage 的格子记 null（背景）；
/// - 轮廓检测：暗像素占比 ≥ outlineDarkRatio 且（亮度跨度 ≥ outlineContrast 或
///   平均亮度 ≤ outlineDarkLuminance）的格子打 isOutline 标记，颜色取暗像素均值
///   （治主体边缘发灰/毛边：边缘格不再混入亮色）。
///
/// 依赖 image 包（纯 Dart 解码），不依赖 Flutter。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 每格采样模式。
enum CellSamplingMode {
  /// 众数桶主色（默认，治毛边）。
  dominantBucket,

  /// 区域均值（平滑自然档，保留渐变过渡）。
  average,
}

/// 单个网格格子的采样结果。
class SampleCell {
  /// 代表色 0xRRGGBB。
  final int rgb;

  /// 前景覆盖度（有效像素权重 / 格面积，0~1）。
  final double coverage;

  /// 暗像素占比（亮度 ≤ outlineDarkLuminance 的像素权重占比）。
  final double darkRatio;

  /// 格内亮度跨度（maxLuma - minLuma）。
  final double luminanceRange;

  /// 是否为轮廓格（边缘格：暗占比高且对比/亮度符合轮廓特征）。
  final bool isOutline;

  const SampleCell({
    required this.rgb,
    required this.coverage,
    required this.darkRatio,
    required this.luminanceRange,
    required this.isOutline,
  });
}

/// 采样结果：N×N 的 RGB 矩阵（行优先）。
class SampledGrid {
  final int size;

  /// 行优先存储的 RGB 值（0xRRGGBB）；背景/空格为 0。
  final List<int> colors;

  /// 每格区域平均色（含背景像素，用于"原图对比"视图）。
  final List<int> avgColors;

  /// 每格采样详情；null = 背景/透明/覆盖不足（映射时记为透明 -1）。
  final List<SampleCell?> cells;

  SampledGrid({
    required this.size,
    required this.colors,
    required this.avgColors,
    required this.cells,
  });

  int colorAt(int x, int y) => colors[y * size + x];
}

/// 采样参数。
class SamplerOptions {
  /// 目标网格宽度（N）。
  final int gridSize;

  /// 目标网格高度（M）；null = 正方形（== gridSize）。
  /// 支持按原图宽高比的非正方形网格。
  final int? gridHeight;

  /// 采样模式。
  final CellSamplingMode cellSamplingMode;

  /// dominant-bucket 的量化位数（每通道 2^bits 级；4~5 与 pixel-beads 一致）。
  /// null = 由 [histogramStep] 推导（step=8→5bit，step=16→4bit）。
  final int? colorBucketBits;

  /// 直方图量化步长（旧参数；默认 8 → 5bit 桶）。保留以兼容旧调用。
  final int histogramStep;

  /// 轮廓检测：暗像素亮度阈值（相对 1.0）。
  final double outlineDarkLuminance;

  /// 轮廓检测：暗像素占比阈值。
  final double outlineDarkRatio;

  /// 轮廓检测：亮度跨度阈值（对比度）。
  final double outlineContrast;

  /// 前景覆盖度门槛：低于该值记 null（背景）。
  final double minimumForegroundCoverage;

  const SamplerOptions({
    required this.gridSize,
    this.gridHeight,
    this.cellSamplingMode = CellSamplingMode.dominantBucket,
    this.colorBucketBits,
    this.histogramStep = 8,
    this.outlineDarkLuminance = 0.32,
    this.outlineDarkRatio = 0.20,
    this.outlineContrast = 0.16,
    this.minimumForegroundCoverage = 0.15,
  });

  int get effectiveBucketBits =>
      colorBucketBits ?? (math.log(256 / histogramStep) / math.ln2).round();
}

/// 对已解码图片执行网格采样。
///
/// [backgroundMask]（可选）：与图片同尺寸的 1=背景 掩码，背景像素不参与统计。
/// 该函数开销为 O(W×H)，>128×128 网格时建议放入 Isolate 执行。
SampledGrid sampleDominantColors(
  img.Image image,
  SamplerOptions options, {
  Uint8List? backgroundMask,
}) {
  final n = options.gridSize;
  final m = options.gridHeight ?? n;
  final w = image.width;
  final h = image.height;
  final total = n * m;

  final colors = List<int>.filled(total, 0);
  final avgColors = List<int>.filled(total, 0);
  final cells = List<SampleCell?>.filled(total, null);

  final bits = options.effectiveBucketBits;
  final bucketCount = 1 << (3 * bits); // 3 通道
  final shift = 8 - bits;

  // dominant-bucket 直方图（懒重置，按格复用）
  final hist = List<int>.filled(bucketCount, 0);
  final sumR = List<int>.filled(bucketCount, 0);
  final sumG = List<int>.filled(bucketCount, 0);
  final sumB = List<int>.filled(bucketCount, 0);
  final touched = <int>[];

  final avg = List<double>.filled(3, 0);

  for (var gy = 0; gy < m; gy++) {
    final y0f = gy * h / m;
    final y1f = (gy + 1) * h / m;
    final y0 = math.max(0, y0f.floor());
    final y1 = math.min(h, y1f.ceil());

    for (var gx = 0; gx < n; gx++) {
      final x0f = gx * w / n;
      final x1f = (gx + 1) * w / n;
      final x0 = math.max(0, x0f.floor());
      final x1 = math.min(w, x1f.ceil());

      var weight = 0.0; // 有效像素总权重（重叠×alpha）
      var wR = 0.0, wG = 0.0, wB = 0.0; // 加权 RGB 和
      var darkW = 0.0, dR = 0.0, dG = 0.0, dB = 0.0; // 暗像素
      var minLum = 1.0, maxLum = 0.0;
      touched.clear();

      for (var py = y0; py < y1; py++) {
        final overlapY = _overlap(y0f, y1f, py);
        if (overlapY == 0) continue;
        final row = py * w;
        for (var px = x0; px < x1; px++) {
          if (backgroundMask != null && backgroundMask[row + px] == 1) continue;
          final overlapX = _overlap(x0f, x1f, px);
          final ov = overlapX * overlapY;
          if (ov == 0) continue;

          final p = image.getPixel(px, py);
          final a = p.a.toInt();
          if (a == 0) continue;
          final alpha = a / 255.0;
          final yw = ov * alpha;
          if (yw == 0) continue;

          final r = p.r.toInt();
          final g = p.g.toInt();
          final b = p.b.toInt();

          weight += yw;
          wR += r * yw;
          wG += g * yw;
          wB += b * yw;

          final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
          if (lum < minLum) minLum = lum;
          if (lum > maxLum) maxLum = lum;
          if (lum <= options.outlineDarkLuminance) {
            darkW += yw;
            dR += r * yw;
            dG += g * yw;
            dB += b * yw;
          }

          if (options.cellSamplingMode == CellSamplingMode.dominantBucket) {
            final bucket = ((r >> shift) << (2 * bits)) |
                ((g >> shift) << bits) |
                (b >> shift);
            if (hist[bucket] == 0) touched.add(bucket);
            hist[bucket]++;
            sumR[bucket] += r;
            sumG[bucket] += g;
            sumB[bucket] += b;
          }
        }
      }

      final idx = gy * n + gx;
      final cellArea = (x1f - x0f) * (y1f - y0f);
      final coverage = cellArea > 0 ? weight / cellArea : 0.0;

      // 平均色（含背景，供对比视图）
      if (weight > 0) {
        avg[0] = wR / weight;
        avg[1] = wG / weight;
        avg[2] = wB / weight;
      } else {
        avg[0] = 0;
        avg[1] = 0;
        avg[2] = 0;
      }
      avgColors[idx] =
          ((avg[0].round().clamp(0, 255)) << 16) |
              ((avg[1].round().clamp(0, 255)) << 8) |
              (avg[2].round().clamp(0, 255));

      // 背景/覆盖不足 → null
      if (weight <= 0 || coverage < options.minimumForegroundCoverage) {
        colors[idx] = 0;
        cells[idx] = null;
        continue;
      }

      // 轮廓检测
      final darkRatio = darkW / weight;
      final lumRange = maxLum - minLum;
      final meanLum = (0.2126 * wR + 0.7152 * wG + 0.0722 * wB) / weight / 255.0;
      final isOutline = darkW > 0 &&
          darkRatio >= options.outlineDarkRatio &&
          (lumRange >= options.outlineContrast ||
              meanLum <= options.outlineDarkLuminance);

      // 代表色：轮廓格 → 暗像素均值；否则 → dominant bucket 均值 / 区域均值
      final int cr, cg, cb;
      if (isOutline) {
        cr = (dR / darkW).round().clamp(0, 255);
        cg = (dG / darkW).round().clamp(0, 255);
        cb = (dB / darkW).round().clamp(0, 255);
      } else if (options.cellSamplingMode == CellSamplingMode.dominantBucket &&
          touched.isNotEmpty) {
        var bestBucket = touched.first;
        var bestCount = -1;
        for (final bkt in touched) {
          if (hist[bkt] > bestCount) {
            bestCount = hist[bkt];
            bestBucket = bkt;
          }
        }
        cr = (sumR[bestBucket] / bestCount).round().clamp(0, 255);
        cg = (sumG[bestBucket] / bestCount).round().clamp(0, 255);
        cb = (sumB[bestBucket] / bestCount).round().clamp(0, 255);
      } else {
        cr = (wR / weight).round().clamp(0, 255);
        cg = (wG / weight).round().clamp(0, 255);
        cb = (wB / weight).round().clamp(0, 255);
      }

      colors[idx] = (cr << 16) | (cg << 8) | cb;
      cells[idx] = SampleCell(
        rgb: (cr << 16) | (cg << 8) | cb,
        coverage: coverage,
        darkRatio: darkRatio,
        luminanceRange: lumRange,
        isOutline: isOutline,
      );

      // 复位直方图
      for (final bkt in touched) {
        hist[bkt] = 0;
        sumR[bkt] = 0;
        sumG[bkt] = 0;
        sumB[bkt] = 0;
      }
    }
  }

  return SampledGrid(size: n, colors: colors, avgColors: avgColors, cells: cells);
}

/// 像素行/列与区间 [f, t) 的重叠比例（0~1）。
double _overlap(double f, double t, int coord) {
  final a = math.max(f, coord.toDouble());
  final b = math.min(t, (coord + 1).toDouble());
  final v = b - a;
  return v > 0 ? v : 0.0;
}
