/// pixel-beads 引擎适配层：img.Image + Palette → PbInput → Pattern。
///
/// 完全沿用原站逻辑：
/// - 目标网格宽高用原站 Mo()（宽度固定、高度按比例、单边 ≤200）
/// - 分析图尺寸用原站 Bo()（analysisPixelsPerCell=4，长边 ≤1024，线性插值）
/// - 采样/背景/选色/抖动/正则化/清理全部走 1:1 移植引擎
/// 外围保留本项目的 W×H 网格、圆形掩码、BOM、色号排除。
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../palette.dart';
import '../pattern_converter.dart';
import '../../models/pattern.dart';
import 'pixelbeads_engine.dart';

/// 用 pixel-beads 引擎转换。
///
/// [targetWidth]：图纸宽度（10~200）；[presetId]：simplified/standard/detailed/legacy。
ConvertResult convertWithPixelBeads(
  img.Image image,
  Palette palette, {
  required int targetWidth,
  required String presetId,
  int? maximumColors,
  String backgroundMode = 'auto',
  String? maskShape,
  List<int>? allowedIndices,
}) {
  // ① 目标网格（原站 Mo）
  final (tw, th) = pbTargetSize(image.width, image.height, targetWidth);
  final preset = kPixelBeadsPresets[presetId] ?? kPixelBeadsPresets['standard']!;

  // ② 分析图（原站 Bo，≤1024，线性插值 —— 与原站 imageSmoothingEnabled=true 一致）
  final (aw, ah) = pbAnalysisSize(image.width, image.height, tw, th, preset);
  final analysis = (aw == image.width && ah == image.height)
      ? image
      : img.copyResize(image, width: aw, height: ah,
          interpolation: img.Interpolation.linear);

  // ③ RGBA 数据
  final data = Uint8List(aw * ah * 4);
  for (var y = 0; y < ah; y++) {
    for (var x = 0; x < aw; x++) {
      final p = analysis.getPixel(x, y);
      final i = (y * aw + x) * 4;
      data[i] = p.r.toInt();
      data[i + 1] = p.g.toInt();
      data[i + 2] = p.b.toInt();
      data[i + 3] = p.a.toInt();
    }
  }

  // ④ 调色板（顺序 = Palette.entries 子集；输出索引需映射回原色卡）
  final indices = allowedIndices ??
      List<int>.generate(palette.length, (i) => i);
  final beads = <BeadColor>[
    for (final i in indices) BeadColor(palette.entries[i].code, palette.entries[i].r, palette.entries[i].g, palette.entries[i].b),
  ];

  // ⑤ 执行引擎
  final result = pbConvert(PbInput(
    data: data,
    width: aw,
    height: ah,
    targetWidth: tw,
    targetHeight: th,
    palette: beads,
    presetId: presetId,
    maximumColors: maximumColors,
    backgroundMode: backgroundMode,
  ));

  // ⑥ 展平为 List<int>（null → -1；子索引 → 原色卡索引）
  final grid = List<int>.filled(tw * th, -1);
  var fg = 0;
  for (var y = 0; y < th; y++) {
    for (var x = 0; x < tw; x++) {
      final v = result.matrix[y][x];
      if (v != null && v >= 0 && v < indices.length) {
        grid[y * tw + x] = indices[v];
        fg++;
      }
    }
  }

  // 外围安全网：原站 Re() 无前景占比把关，主体≈背景色时可能整块吞掉 →
  // 有效格过少时保留背景重转一次（不影响正常图片的原站行为）。
  if (backgroundMode == 'auto' && fg / (tw * th) < 0.05) {
    return convertWithPixelBeads(
      image,
      palette,
      targetWidth: targetWidth,
      presetId: presetId,
      maximumColors: maximumColors,
      backgroundMode: 'keep',
      maskShape: maskShape,
      allowedIndices: allowedIndices,
    );
  }

  // 保留背景后仍几乎无内容（图片本身空白/全透明）→ 友好报错
  if (fg / (tw * th) < 0.02) {
    throw const FormatException(
      '图片中可识别的内容太少（可能整张都是背景或透明）。'
      '请换一张主体清晰、背景简单的图片，或先在裁剪页框出主体。',
    );
  }

  // 外围清理：孤立单格区域并入邻域众数（原站 ye() 后仍有 1 格杂点可能，
  // 这里只清理单格孤岛，不影响原站的大块结构）。
  _mergeIsolatedCells(grid, tw, th);

  // ⑦ 圆形掩码（仅正方形时）
  if (maskShape == 'circle' && tw == th) {
    for (var y = 0; y < th; y++) {
      for (var x = 0; x < tw; x++) {
        if (!_isInsideCircle(x, y, tw)) grid[y * tw + x] = -1;
      }
    }
  }

  // ⑧ BOM
  final usage = <int, int>{};
  for (final idx in grid) {
    if (idx >= 0) usage[idx] = (usage[idx] ?? 0) + 1;
  }
  final entries = usage.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final bom = [
    for (final e in entries)
      BomEntry(
        code: palette.entries[e.key].code,
        count: e.value,
        color: (palette.entries[e.key].r << 16) |
            (palette.entries[e.key].g << 8) |
            palette.entries[e.key].b,
        productCode: palette.entries[e.key].productCode,
        name: palette.entries[e.key].name,
      ),
  ];

  // ⑨ 背景蒙层（矩阵 null 的格子）
  final backgroundCells = List<bool>.generate(tw * th, (i) => grid[i] < 0);

  return ConvertResult(
    pattern: Pattern(
      size: tw,
      height: th,
      grid: grid,
      paletteId: palette.id,
      bom: bom,
    ),
    avgColors: List<int>.filled(tw * th, 0),
    backgroundCells: backgroundCells,
    diagnostics: ConvertDiagnostics(
      backgroundDetected: result.diagnostics.backgroundDetected,
      backgroundConfidence: result.diagnostics.backgroundConfidence,
      meanMappingDistance: result.diagnostics.meanMappingDistance,
      usedColorCount: bom.length,
      rareColorCount: result.diagnostics.rareColorCount,
      singleCellRegionCount: result.diagnostics.singleCellRegionCount,
      spatialChangedCells: result.diagnostics.spatialChangedCells,
      cleanupChangedCells: result.diagnostics.cleanupChangedCells,
      backgroundFallback: false,
    ),
  );
}

bool _isInsideCircle(int x, int y, int size) {
  final c = (size - 1) / 2.0;
  final dx = x - c;
  final dy = y - c;
  return dx * dx + dy * dy <= c * c + 0.1;
}

/// 迭代清理面积 = 1 的连通域（并入 8 邻域众数）。跳过透明格。
void _mergeIsolatedCells(List<int> grid, int w, int h) {
  for (var pass = 0; pass < 16; pass++) {
    var changed = false;
    final labels = List<int>.filled(grid.length, 0);
    final area = <int, int>{};
    var nextLabel = 1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (labels[i] != 0 || grid[i] < 0) continue;
        final color = grid[i];
        final q = <int>[i];
        labels[i] = nextLabel;
        var head = 0;
        var count = 0;
        while (head < q.length) {
          final cur = q[head++];
          count++;
          final cx = cur % w;
          final cy = cur ~/ w;
          for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final nx = cx + dx, ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final ni = ny * w + nx;
            if (labels[ni] == 0 && grid[ni] == color) {
              labels[ni] = nextLabel;
              q.add(ni);
            }
          }
        }
        area[nextLabel] = count;
        nextLabel++;
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (grid[i] < 0) continue;
        final a = area[labels[i]];
        if (a == null || a != 1) continue;
        final counts = <int, int>{};
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final ni = ny * w + nx;
            if (grid[ni] >= 0) counts[grid[ni]] = (counts[grid[ni]] ?? 0) + 1;
          }
        }
        if (counts.isEmpty) continue;
        var best = 0;
        var bestCount = 0;
        counts.forEach((k, v) {
          if (v > bestCount) {
            bestCount = v;
            best = k;
          }
        });
        if (best != grid[i]) {
          grid[i] = best;
          changed = true;
        }
      }
    }
    if (!changed) break;
  }
}

/// 本预设 id → pixel-beads 预设 id。
String pixelBeadsPresetFor(String presetId) {
  switch (presetId) {
    case 'simplified':
      return 'simplified';
    case 'detailed':
      return 'detailed';
    case 'smooth':
      return 'legacy';
    case 'standard':
    default:
      return 'standard';
  }
}
