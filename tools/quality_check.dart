// 算法质量验收脚本（dev-plan 7.3 验收指标）。
//
// 运行：dart run tools/quality_check.dart
//
// 生成拼豆风格合成测试图 → 走完整转换管线 → 输出质量指标 + 图纸 PNG。
//
// ignore_for_file: avoid_print, implementation_imports, depend_on_referenced_packages
library;

// 工具脚本从 lib 导入（与包内代码同源验证，避免复制实现）。
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../lib/core/ciede2000.dart';
import '../lib/core/color_mapper.dart';
import '../lib/core/color_space.dart';
import '../lib/core/palette.dart';
import '../lib/core/pattern_converter.dart';
import '../lib/models/pattern.dart' as bead;

void main() async {
  final sw = Stopwatch()..start();
  final paletteJson =
      File('lib/core/palettes/mard_221.json').readAsStringSync();
  final palette =
      Palette.fromJsonString('mard_221', 'MARD 221', paletteJson);
  final converter = PatternConverter(palette);

  // ① 生成合成测试图：渐变背景 + 红球主体 + 噪点
  final image = img.Image(width: 600, height: 600);
  final rng = math.Random(7);
  for (var y = 0; y < 600; y++) {
    for (var x = 0; x < 600; x++) {
      final p = image.getPixel(x, y);
      final dx = x - 300.0;
      final dy = y - 280.0;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 130) {
        // 红球：径向明暗渐变
        final shade = (1.0 - dist / 130) * 60;
        p.r = (200 + shade).clamp(0, 255);
        p.g = (40 + shade * 0.4).clamp(0, 255);
        p.b = (40 + shade * 0.4).clamp(0, 255);
      } else {
        // 近纯色背景（浅米白 + 10% 明度渐变，模拟实拍照片背景）
        final base = 235 + (y / 600) * 20;
        p.r = base.clamp(0, 255);
        p.g = (base - 6).clamp(0, 255);
        p.b = (base - 14).clamp(0, 255);
        // 噪点（2%）
        if (rng.nextInt(50) == 0) {
          final n = rng.nextInt(60);
          p.r = (p.r + n).clamp(0, 255);
          p.g = (p.g + n).clamp(0, 255);
          p.b = (p.b + n).clamp(0, 255);
        }
      }
    }
  }
  final srcBytes = Uint8List.fromList(img.encodeJpg(image, quality: 92));
  print('测试图：600×600 合成图（渐变背景 + 红球 + 2% 噪点）');

  // ② 转换（52×52 与 81×81 各一次，记录耗时）
  for (final (label, size) in [('52×52', 52), ('81×81', 81)]) {
    final t = Stopwatch()..start();
    final result = converter.convert(
      srcBytes,
      ConvertOptions(gridSize: size, removeBackground: true, maxColors: 32, dither: false),
    );
    t.stop();
    final pattern = result.pattern;

    // ③ 指标
    final total = pattern.totalBeads;
    final usedColors = pattern.bom.length;
    final isolated = _countIsolated(pattern.grid, size);
    final avgDeltaE = _avgDeltaE(ColorMapper(palette), pattern, result.avgColors);

    print('');
    print('== $label 转换结果 ==');
    print('耗时：${t.elapsedMilliseconds} ms（验收 ≤ 2s）');
    print('总豆数：$total · 使用色号：$usedColors（上限 32）');
    print('孤立 1 格杂色块：$isolated（验收 = 0）');
    print('平均映射色差 ΔE00：${avgDeltaE.toStringAsFixed(2)}（验收 ≤ 4）');
    print('BOM 前 8：');
    for (final e in pattern.bom.take(8)) {
      print('  ${e.code} × ${e.count}');
    }

    // ④ 输出图纸 PNG（色块 + 色号）
    _renderPng(pattern, palette, 'output/quality_$size.png', cell: 12);
    print('图纸 PNG：output/quality_$size.png');
  }

  sw.stop();
  print('');
  print('总耗时（含两次转换+渲染）：${sw.elapsedMilliseconds} ms');
}

/// 统计面积 < 2 格的孤立杂色块（连通域标记，与 post_processor 口径一致）。
int _countIsolated(List<int> grid, int size) {
  final labels = List<int>.filled(grid.length, 0);
  var nextLabel = 1;
  final area = <int, int>{};
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = y * size + x;
      if (labels[i] != 0 || grid[i] < 0) continue;
      final color = grid[i];
      final queue = <int>[i];
      labels[i] = nextLabel;
      var head = 0;
      var count = 0;
      while (head < queue.length) {
        final cur = queue[head++];
        count++;
        final cx = cur % size;
        final cy = cur ~/ size;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = cx + dx;
          final ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= size || ny >= size) continue;
          final ni = ny * size + nx;
          if (labels[ni] == 0 && grid[ni] == color) {
            labels[ni] = nextLabel;
            queue.add(ni);
          }
        }
      }
      area[nextLabel] = count;
      nextLabel++;
    }
  }
  return area.values.where((a) => a < 2).length;
}

/// 平均 ΔE00（原图区域平均色 vs 映射后的色号色）。
double _avgDeltaE(ColorMapper mapper, bead.Pattern pattern, List<int> avgColors) {
  var sum = 0.0;
  var n = 0;
  for (var i = 0; i < avgColors.length && i < pattern.grid.length; i++) {
    if (pattern.grid[i] < 0) continue;
    final c = avgColors[i];
    final lab = rgbToLab((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF);
    final mapped = mapper.labs[pattern.grid[i]];
    sum += ciede2000(lab, mapped);
    n++;
  }
  return n == 0 ? 0 : sum / n;
}

/// 渲染图纸 PNG（色块 + 色号文字）。
void _renderPng(bead.Pattern pattern, Palette palette, String path, {required int cell}) {
  final n = pattern.size;
  final total = n * cell;
  final out = img.Image(width: total, height: total);
  img.fill(out, color: img.ColorRgb8(255, 255, 255));

  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final idx = pattern.grid[y * n + x];
      if (idx < 0) continue;
      final e = palette.entries[idx];
      img.fillRect(
        out,
        x1: x * cell,
        y1: y * cell,
        x2: x * cell + cell - 1,
        y2: y * cell + cell - 1,
        color: img.ColorRgb8(e.r, e.g, e.b),
      );
    }
  }

  // 网格线
  for (var i = 0; i <= n; i++) {
    img.drawLine(
      out,
      x1: i * cell,
      y1: 0,
      x2: i * cell,
      y2: total - 1,
      color: img.ColorRgb8(255, 107, 157),
      thickness: 1,
    );
    img.drawLine(
      out,
      x1: 0,
      y1: i * cell,
      x2: total - 1,
      y2: i * cell,
      color: img.ColorRgb8(255, 107, 157),
      thickness: 1,
    );
  }

  Directory('output').createSync(recursive: true);
  File(path).writeAsBytesSync(img.encodePng(out));
}
