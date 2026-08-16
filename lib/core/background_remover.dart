/// 背景检测：边界主色聚类锚点 + 置信度门槛 + 多锚点双阈值 flood-fill。
///
/// 参考 pixel-beads.com 的 `Re()` 实现思路，并针对「多色调背景」与
/// 「主体颜色接近背景」两个失败场景增强：
/// ① 四边不透明像素 → 量化聚类出最多 3 个背景候选色（锚点）；
/// ② 每个锚点的置信度 = 边界中与该锚点 ΔE ≤ seedDeltaE 的像素占比；
///    总置信度 = 各锚点覆盖的边界像素并集占比；低于 minimumConfidence → 放弃去背景；
/// ③ 从边界 flood-fill：种子锚点紧判（seedDeltaE），向邻域松传播（fillDeltaE），
///    支持多锚点并行扩散 → 渐变/双色背景也能整块移除；
/// ④ **前景占比把关**：flood 后前景（非背景）像素占比低于 minimumForegroundCoverage
///    （说明主体可能被吞或图中没有主体）→ 用紧档 fillDeltaE（÷1.6）重试一次；
///    仍不足 → 放弃背景检测（detected=false），避免「主体颜色接近背景时被整块吞掉
///    导致输出大片空白」；
/// ⑤ alpha ≤ 阈值视为透明背景。
///
/// 纯 Dart（仅依赖 image 解码 + 色彩空间），无 Flutter 依赖。
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'ciede2000.dart';
import 'color_space.dart';

/// 背景检测结果。
class BackgroundResult {
  /// 与输入图片同尺寸的掩码：1 = 背景，0 = 前景。
  final Uint8List mask;

  /// 是否检测到并执行了背景移除。
  final bool detected;

  /// 背景置信度（0~1，供 UI 展示）。
  final double confidence;

  const BackgroundResult({
    required this.mask,
    required this.detected,
    required this.confidence,
  });
}

/// 背景检测参数（默认值对齐 pixel-beads standard 预设）。
class BackgroundOptions {
  /// 种子判定阈值（紧）：边界像素与背景锚点的 ΔE 门槛。
  final double seedDeltaE;

  /// 传播阈值（松）：flood-fill 向外扩散的 ΔE 门槛。
  final double fillDeltaE;

  /// 置信度门槛：低于则不认为存在可去背景。
  final double minimumConfidence;

  /// 前景占比门槛：flood 后非背景像素占比低于该值（图几乎全被吞/无主体）→
  /// 紧档重试，仍不足则放弃。注意这是像素级兜底，只拦截「几乎全空白」的异常
  /// （如主体颜色与背景色差 < fillDeltaE 被整块吞掉）；小主体+大背景属正常场景。
  final double minimumForegroundCoverage;

  /// 边界背景候选色最大数量（多色调背景支持）。
  final int maxAnchorColors;

  /// alpha 阈值：alpha ≤ 该值视为透明背景。
  final int alphaThreshold;

  const BackgroundOptions({
    this.seedDeltaE = 8.0,
    this.fillDeltaE = 14.0,
    this.minimumConfidence = 0.85,
    this.minimumForegroundCoverage = 0.05,
    this.maxAnchorColors = 3,
    this.alphaThreshold = 16,
  });
}

/// 检测背景。
///
/// [image] 建议为降采样后的分析图（≤1024px，速度与精度平衡）。
BackgroundResult detectBackground(
  img.Image image, {
  BackgroundOptions options = const BackgroundOptions(),
}) {
  final w = image.width;
  final h = image.height;
  final total = w * h;

  // ① alpha ≤ 阈值 → 直接视为背景（同时作为"放弃时的兜底掩码"）
  final alphaMask = Uint8List(total);
  for (var i = 0; i < total; i++) {
    if (image.getPixel(i % w, i ~/ w).a.toInt() <= options.alphaThreshold) {
      alphaMask[i] = 1;
    }
  }

  // ② 边界不透明像素 → 聚类出背景锚点
  final borderRgb = <int>[];
  for (var x = 0; x < w; x++) {
    _pushOpaque(borderRgb, image, alphaMask, x, 0, w);
    _pushOpaque(borderRgb, image, alphaMask, x, h - 1, w);
  }
  for (var y = 1; y < h - 1; y++) {
    _pushOpaque(borderRgb, image, alphaMask, 0, y, w);
    _pushOpaque(borderRgb, image, alphaMask, w - 1, y, w);
  }

  if (borderRgb.isEmpty) {
    return BackgroundResult(mask: alphaMask, detected: false, confidence: 1.0);
  }

  final anchors = _clusterBorderColors(borderRgb, options.maxAnchorColors);
  if (anchors.isEmpty) {
    return BackgroundResult(mask: alphaMask, detected: false, confidence: 0);
  }
  final anchorLabs = [for (final rgb in anchors) _rgbToLab(rgb)];

  // ③ 置信度：边界像素被任一锚点覆盖的并集占比
  var covered = 0;
  for (final rgb in borderRgb) {
    final lab = _rgbToLab(rgb);
    for (final a in anchorLabs) {
      if (ciede2000(lab, a) <= options.seedDeltaE) {
        covered++;
        break;
      }
    }
  }
  final confidence = covered / borderRgb.length;

  if (confidence < options.minimumConfidence) {
    return BackgroundResult(
      mask: alphaMask,
      detected: false,
      confidence: confidence,
    );
  }

  // ④ 松档 flood-fill → 前景占比把关
  var (mask, fgRatio) = _floodFill(
    image,
    w,
    h,
    alphaMask,
    anchorLabs,
    options.seedDeltaE,
    options.fillDeltaE,
    options.alphaThreshold,
  );

  // ⑤ 前景太少（主体被吞 / 图中无主体）→ 紧档重试一次
  if (fgRatio < options.minimumForegroundCoverage) {
    final tightFill = options.fillDeltaE / 1.6;
    final (tightMask, tightRatio) = _floodFill(
      image,
      w,
      h,
      alphaMask,
      anchorLabs,
      options.seedDeltaE,
      tightFill,
      options.alphaThreshold,
    );
    if (tightRatio >= options.minimumForegroundCoverage) {
      mask = tightMask;
      fgRatio = tightRatio;
    } else {
      // 仍不足 → 放弃（保留 alpha 掩码，不去背景），避免输出大片空白
      return BackgroundResult(
        mask: alphaMask,
        detected: false,
        confidence: confidence,
      );
    }
  }

  return BackgroundResult(mask: mask, detected: true, confidence: confidence);
}

/// 多锚点双阈值 flood-fill：返回 (掩码, 前景占比)。
/// 掩码基于 [baseMask]（alpha 掩码）累加；前景占比 = 非掩码像素 / 总数。
(Uint8List, double) _floodFill(
  img.Image image,
  int w,
  int h,
  Uint8List baseMask,
  List<LabColor> anchorLabs,
  double seedDeltaE,
  double fillDeltaE,
  int alphaThreshold,
) {
  final mask = Uint8List.fromList(baseMask);
  final total = w * h;
  final visited = Uint8List(total);
  final q = <int>[];

  void trySeed(int x, int y) {
    final i = y * w + x;
    if (visited[i] == 1 || mask[i] == 1) return;
    final p = image.getPixel(x, y);
    if (p.a.toInt() <= alphaThreshold) {
      visited[i] = 1;
      mask[i] = 1;
      q.add(i);
      return;
    }
    final lab = _pixelLab(image, x, y);
    for (final a in anchorLabs) {
      if (ciede2000(lab, a) <= seedDeltaE) {
        visited[i] = 1;
        mask[i] = 1;
        q.add(i);
        return;
      }
    }
  }

  for (var x = 0; x < w; x++) {
    trySeed(x, 0);
    trySeed(x, h - 1);
  }
  for (var y = 1; y < h - 1; y++) {
    trySeed(0, y);
    trySeed(w - 1, y);
  }

  var head = 0;
  while (head < q.length) {
    final cur = q[head++];
    final cx = cur % w;
    final cy = cur ~/ w;
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = cx + dx;
      final ny = cy + dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final ni = ny * w + nx;
      if (visited[ni] == 1 || mask[ni] == 1) continue;
      final p = image.getPixel(nx, ny);
      if (p.a.toInt() <= alphaThreshold) {
        visited[ni] = 1;
        mask[ni] = 1;
        q.add(ni);
        continue;
      }
      final lab = _pixelLab(image, nx, ny);
      for (final a in anchorLabs) {
        if (ciede2000(lab, a) <= fillDeltaE) {
          visited[ni] = 1;
          mask[ni] = 1;
          q.add(ni);
          break;
        }
      }
    }
  }

  var fg = 0;
  for (final m in mask) {
    if (m == 0) fg++;
  }
  return (mask, fg / total);
}

void _pushOpaque(List<int> out, img.Image image, Uint8List mask, int x, int y,
    int w) {
  final i = y * w + x;
  if (mask[i] == 1) return;
  final p = image.getPixel(x, y);
  out.add((p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt());
}

LabColor _pixelLab(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return rgbToLab(p.r.toInt(), p.g.toInt(), p.b.toInt());
}

LabColor _rgbToLab(int rgb) =>
    rgbToLab((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);

/// 边界颜色聚类：按量化桶统计频率，取频率最高的至多 [maxColors] 个桶的均值色。
List<int> _clusterBorderColors(List<int> colors, int maxColors) {
  const step = 24;
  final qn = (256 + step - 1) ~/ step;
  final count = <int, int>{};
  final sumR = <int, int>{};
  final sumG = <int, int>{};
  final sumB = <int, int>{};
  for (final c in colors) {
    final bucket = ((c >> 16) & 0xFF) ~/ step * qn * qn +
        (((c >> 8) & 0xFF) ~/ step) * qn +
        ((c & 0xFF) ~/ step);
    count[bucket] = (count[bucket] ?? 0) + 1;
    sumR[bucket] = (sumR[bucket] ?? 0) + ((c >> 16) & 0xFF);
    sumG[bucket] = (sumG[bucket] ?? 0) + ((c >> 8) & 0xFF);
    sumB[bucket] = (sumB[bucket] ?? 0) + (c & 0xFF);
  }
  final sorted = count.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final out = <int>[];
  for (final e in sorted) {
    final n = e.value;
    out.add((((sumR[e.key]! / n).round()) << 16) |
        (((sumG[e.key]! / n).round()) << 8) |
        ((sumB[e.key]! / n).round()));
    if (out.length >= maxColors) break;
  }
  // 合并相近锚点（ΔE ≤ seed 阈值的一半）
  final merged = <int>[];
  for (final c in out) {
    var dup = false;
    final lab = _rgbToLab(c);
    for (final m in merged) {
      if (ciede2000(lab, _rgbToLab(m)) <= 4.0) {
        dup = true;
        break;
      }
    }
    if (!dup) merged.add(c);
  }
  return merged.isEmpty ? out : merged;
}
