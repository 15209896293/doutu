/// 图片主体提取：边界背景色聚类 + 容差 flood-fill，返回主体包围盒。
///
/// v0.5 零依赖纯 Dart 启发式方案：针对"背景非纯色/有杂物导致转换不准"，
/// 先识别背景、再框出主体，供裁剪页「自动提取主体」一键框选。
/// 仅依赖 image 包解码与 CIEDE2000 色差，不引入任何 ML/原生依赖。
library;

import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'ciede2000.dart';
import 'color_space.dart';

/// 主体区域（原图像素坐标）。
class SubjectRegion {
  final int x;
  final int y;
  final int width;
  final int height;
  final double confidence; // 0~1

  const SubjectRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });
}

/// 提取图片主体；无法可靠识别时返回 null。
///
/// 思路：
/// ① 降采样到 ≤180px（提速）
/// ② 采样四边像素 → 众数聚类出 1~2 个背景候选色
/// ③ 从边界 flood-fill：与任一背景色 ΔE < [deltaE] 的像素标记为背景
/// ④ 非背景像素的包围盒即主体，映射回原图坐标
SubjectRegion? detectSubject(img.Image src, {double deltaE = 12}) {
  try {
    // ① 降采样
    const maxSide = 180;
    final img.Image image;
    if (src.width <= maxSide && src.height <= maxSide) {
      image = src;
    } else {
      final scale = math.min(maxSide / src.width, maxSide / src.height);
      image = img.copyResize(
        src,
        width: math.max(1, (src.width * scale).round()),
        height: math.max(1, (src.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
    }

    final w = image.width;
    final h = image.height;

    // ② 边界采样 → 背景候选色（众数聚类，最多 2 个）
    final borderColors = <List<int>>[];
    for (var x = 0; x < w; x++) {
      borderColors.add(_rgb(image, x, 0));
      borderColors.add(_rgb(image, x, h - 1));
    }
    for (var y = 0; y < h; y++) {
      borderColors.add(_rgb(image, 0, y));
      borderColors.add(_rgb(image, w - 1, y));
    }
    final bgColors = _dominantColors(borderColors, maxColors: 2);
    if (bgColors.isEmpty) return null;
    final bgLabs = [for (final c in bgColors) rgbToLab(c[0], c[1], c[2])];

    // ③ 边界 flood-fill 标记背景
    final bg = List<bool>.filled(w * h, false);
    final q = <int>[];
    for (var x = 0; x < w; x++) {
      _seed(image, bg, q, x, 0, bgLabs, deltaE);
      _seed(image, bg, q, x, h - 1, bgLabs, deltaE);
    }
    for (var y = 0; y < h; y++) {
      _seed(image, bg, q, 0, y, bgLabs, deltaE);
      _seed(image, bg, q, w - 1, y, bgLabs, deltaE);
    }
    var head = 0;
    while (head < q.length) {
      final cur = q[head++];
      final x = cur % w;
      final y = cur ~/ w;
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        _seed(image, bg, q, nx, ny, bgLabs, deltaE);
      }
    }

    // ④ 找前景连通域。截图式动漫图常含气泡、字幕、水印；直接取全部
    // 非背景像素会把裁剪框拉到错误位置。优先选面积最大且靠近画面中心的主体，
    // 再合并贴近主体的小部件（发梢、配饰等）。
    final components = _foregroundComponents(bg, w, h);
    if (components.isEmpty) return null;
    final main = _chooseMainComponent(components, w, h);
    final merged = _mergeNearbyComponents(main, components, w, h);
    final minX = merged.minX;
    final minY = merged.minY;
    final maxX = merged.maxX;
    final maxY = merged.maxY;
    final count = merged.count;
    final total = w * h;

    final foregroundCount = components.fold<int>(0, (sum, c) => sum + c.count);
    final bgRatio = (total - foregroundCount) / total;
    // 无背景（主体铺满）或几乎全背景 → 不适用
    if (count == 0 || bgRatio < 0.12 || bgRatio > 0.97) return null;

    // ⑤ 映射回原图坐标
    final scaleX = src.width / w;
    final scaleY = src.height / h;
    // 给主体留出约 7% 呼吸空间，避免头发/轮廓紧贴裁剪边缘。
    final pad = (math.max(maxX - minX + 1, maxY - minY + 1) * 0.07).ceil();
    final left = math.max(0, minX - pad);
    final top = math.max(0, minY - pad);
    final right = math.min(w - 1, maxX + pad);
    final bottom = math.min(h - 1, maxY + pad);
    final bx = (left * scaleX).floor();
    final by = (top * scaleY).floor();
    final bw = ((right + 1) * scaleX).ceil() - bx;
    final bh = ((bottom + 1) * scaleY).ceil() - by;

    // ⑥ 置信度：主体占比接近 0.55 时框选最舒服；离群时降低
    final subjectRatio = count / total;
    final confidence = (subjectRatio / 0.55).clamp(0.3, 1.0);

    return SubjectRegion(
      x: bx,
      y: by,
      width: bw,
      height: bh,
      confidence: confidence.toDouble(),
    );
  } catch (_) {
    return null;
  }
}

class _ForegroundComponent {
  int minX;
  int minY;
  int maxX;
  int maxY;
  int count;

  _ForegroundComponent({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.count,
  });

  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;

  void include(_ForegroundComponent other) {
    minX = math.min(minX, other.minX);
    minY = math.min(minY, other.minY);
    maxX = math.max(maxX, other.maxX);
    maxY = math.max(maxY, other.maxY);
    count += other.count;
  }
}

List<_ForegroundComponent> _foregroundComponents(List<bool> background, int w, int h) {
  final visited = List<bool>.filled(w * h, false);
  final components = <_ForegroundComponent>[];
  const neighbors = <(int, int)>[
    (-1, -1), (0, -1), (1, -1),
    (-1, 0),            (1, 0),
    (-1, 1),  (0, 1),   (1, 1),
  ];

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final start = y * w + x;
      if (background[start] || visited[start]) continue;
      visited[start] = true;
      final queue = <int>[start];
      var head = 0;
      var minX = x, minY = y, maxX = x, maxY = y, count = 0;
      while (head < queue.length) {
        final current = queue[head++];
        final cx = current % w;
        final cy = current ~/ w;
        count++;
        minX = math.min(minX, cx);
        minY = math.min(minY, cy);
        maxX = math.max(maxX, cx);
        maxY = math.max(maxY, cy);
        for (final (dx, dy) in neighbors) {
          final nx = cx + dx;
          final ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final ni = ny * w + nx;
          if (background[ni] || visited[ni]) continue;
          visited[ni] = true;
          queue.add(ni);
        }
      }
      components.add(_ForegroundComponent(
        minX: minX,
        minY: minY,
        maxX: maxX,
        maxY: maxY,
        count: count,
      ));
    }
  }
  return components;
}

_ForegroundComponent _chooseMainComponent(
    List<_ForegroundComponent> components, int w, int h) {
  final cx = (w - 1) / 2;
  final cy = (h - 1) / 2;
  final diagonal = math.sqrt(w * w + h * h);
  return components.reduce((best, candidate) {
    double score(_ForegroundComponent c) {
      final distance = math.sqrt(
          (c.centerX - cx) * (c.centerX - cx) + (c.centerY - cy) * (c.centerY - cy));
      // 面积是主信号，中心度负责从字幕/水印中挑出角色。
      return c.count / (w * h) * 0.82 + (1 - distance / diagonal).clamp(0.0, 1.0) * 0.18;
    }
    return score(candidate) > score(best) ? candidate : best;
  });
}

_ForegroundComponent _mergeNearbyComponents(
  _ForegroundComponent main,
  List<_ForegroundComponent> components,
  int w,
  int h,
) {
  final merged = _ForegroundComponent(
    minX: main.minX,
    minY: main.minY,
    maxX: main.maxX,
    maxY: main.maxY,
    count: main.count,
  );
  final minArea = w * h * 0.002;
  final maxGap = math.max(w, h) * 0.045;
  for (final c in components) {
    if (identical(c, main) || c.count < minArea) continue;
    final gapX = math.max(0, math.max(merged.minX - c.maxX - 1, c.minX - merged.maxX - 1));
    final gapY = math.max(0, math.max(merged.minY - c.maxY - 1, c.minY - merged.maxY - 1));
    if (math.sqrt(gapX * gapX + gapY * gapY) <= maxGap) merged.include(c);
  }
  return merged;
}

void _seed(
  img.Image image,
  List<bool> bg,
  List<int> q,
  int x,
  int y,
  List<LabColor> bgLabs,
  double deltaE,
) {
  final i = y * image.width + x;
  if (bg[i]) return;
  final p = image.getPixel(x, y);
  final lab = rgbToLab(p.r.toInt(), p.g.toInt(), p.b.toInt());
  for (final b in bgLabs) {
    if (ciede2000(lab, b) < deltaE) {
      bg[i] = true;
      q.add(i);
      return;
    }
  }
}

List<int> _rgb(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
}

/// 众数聚类：按量化桶统计频率，取频率最高的至多 [maxColors] 个桶的均值色。
List<List<int>> _dominantColors(List<List<int>> colors,
    {required int maxColors}) {
  const step = 24;
  final qn = (256 + step - 1) ~/ step;
  final count = <int, int>{};
  final sumR = <int, int>{};
  final sumG = <int, int>{};
  final sumB = <int, int>{};
  for (final c in colors) {
    final bucket =
        (c[0] ~/ step) * qn * qn + (c[1] ~/ step) * qn + (c[2] ~/ step);
    count[bucket] = (count[bucket] ?? 0) + 1;
    sumR[bucket] = (sumR[bucket] ?? 0) + c[0];
    sumG[bucket] = (sumG[bucket] ?? 0) + c[1];
    sumB[bucket] = (sumB[bucket] ?? 0) + c[2];
  }
  final sorted = count.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final out = <List<int>>[];
  for (final e in sorted) {
    final n = e.value;
    out.add([
      (sumR[e.key]! / n).round(),
      (sumG[e.key]! / n).round(),
      (sumB[e.key]! / n).round(),
    ]);
    if (out.length >= maxColors) break;
  }
  return out;
}
