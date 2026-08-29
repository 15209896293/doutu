import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doutu/core/palette.dart';
import 'package:doutu/core/pattern_converter.dart';
import 'package:doutu/models/pattern.dart' as bead;

void main() {
  late Palette palette;

  setUpAll(() async {
    final file = File('lib/core/palettes/mard_221.json');
    final json = await file.readAsString();
    palette = Palette.fromJsonString('mard_221', 'MARD 221', json);
  });

  group('端到端转换', () {
    test('白色圆在黑色背景 → BOM 含白黑两色、背景被移除', () {
      // 80×80 图：黑色背景，中心 40×40 白色方块
      final image = img.Image(width: 80, height: 80);
      for (var y = 0; y < 80; y++) {
        for (var x = 0; x < 80; x++) {
          final p = image.getPixel(x, y);
          final inside = x >= 20 && x < 60 && y >= 20 && y < 60;
          if (inside) {
            p.r = 255;
            p.g = 255;
            p.b = 255;
          } else {
            p.r = 0;
            p.g = 0;
            p.b = 0;
          }
        }
      }

      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(gridSize: 20, removeBackground: true),
      );

      final pattern = result.pattern;
      expect(pattern.size, 20);
      // 背景（黑）应被 flood fill 移除
      expect(pattern.at(0, 0), -1, reason: '黑色背景应透明');
      // 中心应为白色块
      expect(pattern.at(10, 10), greaterThanOrEqualTo(0));
      // BOM 有效格子 ≈ 10×10（白色块区域）
      expect(pattern.totalBeads, inInclusiveRange(90, 110));
      // BOM 与网格一致
      final bomTotal = pattern.bom.fold<int>(0, (s, e) => s + e.count);
      expect(bomTotal, pattern.totalBeads);
    });

    test('色数上限生效：maxColors=4 时 BOM 色数 ≤ 4', () {
      // 渐变图（多色）
      final image = img.Image(width: 60, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 60; x++) {
          final p = image.getPixel(x, y);
          p.r = (x * 4).clamp(0, 255);
          p.g = (y * 4).clamp(0, 255);
          p.b = ((x + y) * 2).clamp(0, 255);
        }
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(
          gridSize: 30,
          maxColors: 4,
          removeBackground: false,
        ),
      );
      expect(result.pattern.colorCount, lessThanOrEqualTo(4));
    });

    test('BOM 按数量降序', () {
      final image = img.Image(width: 40, height: 40);
      for (final p in image) {
        p.r = 255;
        p.g = 0;
        p.b = 0;
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(gridSize: 10, removeBackground: false),
      );
      for (var i = 0; i < result.pattern.bom.length - 1; i++) {
        expect(
          result.pattern.bom[i].count >= result.pattern.bom[i + 1].count,
          isTrue,
        );
      }
    });

    test('allowedIndices 限制映射到指定色号', () {
      final image = img.Image(width: 20, height: 20);
      for (final p in image) {
        p.r = 255;
        p.g = 0;
        p.b = 0;
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(
          gridSize: 10,
          removeBackground: false,
          allowedIndices: [0],
        ),
      );
      for (final idx in result.pattern.grid) {
        expect(idx, 0);
      }
    });

    test('无效字节抛 FormatException', () {
      final converter = PatternConverter(palette);
      expect(
        () => converter.convert(
          Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
          const ConvertOptions(gridSize: 10),
        ),
        throwsFormatException,
      );
    });
  });

  group('v0.8 管线', () {
    test('标准预设：渐变背景被前置移除、诊断数据齐全', () {
      // 60×60：渐变背景 + 居中深色主体（高对比，避免背景误淹主体）
      final image = img.Image(width: 60, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 60; x++) {
          final p = image.getPixel(x, y);
          final inside = (x - 30).abs() < 12 && (y - 30).abs() < 12;
          if (inside) {
            p.r = 90;
            p.g = 60;
            p.b = 40;
          } else {
            final base = 235 + (y / 60) * 20;
            p.r = base.round();
            p.g = (base - 6).round();
            p.b = (base - 14).round();
          }
        }
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        ConvertPresets.standard(gridSize: 30),
      );
      final d = result.diagnostics;
      expect(result.pattern.at(0, 0), -1, reason: '渐变背景应被移除');
      expect(result.pattern.at(15, 15), greaterThanOrEqualTo(0),
          reason: '主体保留');
      expect(d.backgroundDetected, isTrue);
      expect(d.backgroundConfidence, greaterThanOrEqualTo(0.85));
      expect(d.meanMappingDistance, greaterThanOrEqualTo(0));
      expect(d.usedColorCount, result.pattern.bom.length);
      // 背景蒙层：角落格标记为背景
      expect(result.backgroundCells[0], isTrue);
      expect(result.backgroundCells[15 * 30 + 15], isFalse);
    });

    test('细腻预设：CIEDE2000 + 色数 ≤ 16', () {
      final image = img.Image(width: 60, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 60; x++) {
          final p = image.getPixel(x, y);
          p.r = (x * 4).clamp(0, 255);
          p.g = (y * 4).clamp(0, 255);
          p.b = ((x + y) * 2).clamp(0, 255);
        }
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        ConvertPresets.detailed(gridSize: 30),
      );
      expect(result.pattern.colorCount, lessThanOrEqualTo(16));
      expect(result.diagnostics.usedColorCount, result.pattern.colorCount);
    });

    test('精简预设：色数 ≤ 8', () {
      final image = img.Image(width: 40, height: 40);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          final p = image.getPixel(x, y);
          p.r = (x * 6).clamp(0, 255);
          p.g = (y * 6).clamp(0, 255);
          p.b = 100;
        }
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        ConvertPresets.simplified(gridSize: 20),
      );
      expect(result.pattern.colorCount, lessThanOrEqualTo(8));
    });

    test('OKLab 与 CIEDE2000 映射结果均为有效色号', () {
      final image = img.Image(width: 32, height: 32);
      for (final p in image) {
        p.r = 180;
        p.g = 90;
        p.b = 40;
      }
      final converter = PatternConverter(palette);
      for (final preset in [
        ConvertPresets.standard(gridSize: 16),
        ConvertPresets.detailed(gridSize: 16),
      ]) {
        final result = converter.convertImage(image, preset);
        expect(
          result.pattern.grid.every((i) => i == -1 || (i >= 0 && i < palette.length)),
          isTrue,
        );
      }
    });
  });

  group('空白兜底（主体≈背景色 / 无主体图不输出大片空白）', () {
    test('白主体 + 米白背景 → 不输出空白（回退保留背景）', () {
      final image = img.Image(width: 120, height: 120);
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 120; x++) {
          final p = image.getPixel(x, y);
          final inside = (x - 60).abs() < 35 && (y - 60).abs() < 35;
          if (inside) {
            p.r = 255;
            p.g = 255;
            p.b = 255;
          } else {
            p.r = 245;
            p.g = 243;
            p.b = 238;
          }
        }
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        ConvertPresets.standard(gridSize: 40),
      );
      final n = result.pattern.size;
      expect(result.pattern.totalBeads / (n * n), greaterThan(0.5),
          reason: '不应输出大片空白');
    });

    test('纯色图（无主体）→ 保留背景输出，不报错不空白', () {
      final image = img.Image(width: 80, height: 80);
      for (final p in image) {
        p.r = 250;
        p.g = 248;
        p.b = 240;
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        ConvertPresets.standard(gridSize: 20),
      );
      expect(result.pattern.totalBeads, greaterThan(0),
          reason: '纯色图应输出整块颜色而非空白');
    });

    test('全透明图 → 抛友好 FormatException', () {
      final image = img.Image(width: 40, height: 40, numChannels: 4);
      for (final p in image) {
        p.a = 0;
      }
      final converter = PatternConverter(palette);
      expect(
        () => converter.convertImage(
          image,
          ConvertPresets.standard(gridSize: 10),
        ),
        throwsFormatException,
      );
    });
  });

  group('非正方形网格（保持原图比例）', () {
    test('4:3 横图 + gridHeight=0 → 图纸为 4:3 矩形', () {
      final image = img.Image(width: 400, height: 300);
      for (final p in image) {
        p.r = 120;
        p.g = 80;
        p.b = 40;
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(gridSize: 40, gridHeight: 0, removeBackground: false),
      );
      expect(result.pattern.size, 40, reason: '宽度固定');
      expect(result.pattern.height, 30, reason: '高度按 400:300 比例 = 30');
      expect(result.pattern.grid.length, 40 * 30);
    });

    test('16:9 横图 → 宽高比 16:9', () {
      final image = img.Image(width: 1600, height: 900);
      for (final p in image) {
        p.r = 200;
        p.g = 100;
        p.b = 50;
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(gridSize: 160, gridHeight: 0, removeBackground: false),
      );
      expect(result.pattern.height, 90);
      expect(result.pattern.grid.length, 160 * 90);
    });

    test('竖图 → 高度大于宽度', () {
      final image = img.Image(width: 300, height: 600);
      for (final p in image) {
        p.r = 60;
        p.g = 120;
        p.b = 180;
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(gridSize: 40, gridHeight: 0, removeBackground: false),
      );
      expect(result.pattern.height, 80);
      expect(result.pattern.height, greaterThan(result.pattern.size));
    });

    test('高度超上限 → 宽度按比例回缩（经典引擎 256 上限）', () {
      // 宽度 60 的 1:8 长图 → 高度 480 > 256 → 封顶 256，宽度回缩
      final image = img.Image(width: 100, height: 800);
      for (final p in image) {
        p.r = 100;
        p.g = 100;
        p.b = 100;
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(
            gridSize: 60,
            gridHeight: 0,
            removeBackground: false,
            pixelbeadsEngine: false),
      );
      expect(result.pattern.height, 256);
      expect(result.pattern.grid.length,
          result.pattern.size * result.pattern.height);
      // 比例保持：w/h ≈ 100/800
      final ratio = result.pattern.size / result.pattern.height;
      expect(ratio, closeTo(0.125, 0.02));
    });

    test('pixelbeads 引擎：单边上限 200（原站 Mo 行为）', () {
      final image = img.Image(width: 100, height: 1000);
      for (final p in image) {
        p.r = 120;
        p.g = 120;
        p.b = 120;
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(
          gridSize: 60,
          removeBackground: false,
          pixelbeadsEngine: true,
        ),
      );
      expect(result.pattern.height, 200, reason: '原站单边上限 200');
      expect(result.pattern.size, lessThanOrEqualTo(200));
    });

    test('gridHeight=null → 正方形（经典引擎原行为不变）', () {
      final image = img.Image(width: 400, height: 300);
      for (final p in image) {
        p.r = 200;
        p.g = 50;
        p.b = 50;
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(
            gridSize: 40, removeBackground: false, pixelbeadsEngine: false),
      );
      expect(result.pattern.height, 40);
      expect(result.pattern.grid.length, 40 * 40);
    });

    test('矩形图纸 BOM 与网格一致', () {
      final image = img.Image(width: 200, height: 150);
      for (final p in image) {
        p.r = 30;
        p.g = 150;
        p.b = 90;
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(gridSize: 20, gridHeight: 0, removeBackground: false),
      );
      final bomTotal =
          result.pattern.bom.fold<int>(0, (s, e) => s + e.count);
      expect(bomTotal, result.pattern.totalBeads);
    });

    test('Pattern height JSON 往返（非正方形）', () {
      final p = bead.Pattern(
        size: 40,
        height: 30,
        grid: List<int>.filled(1200, 0),
        paletteId: 'mard_221',
        bom: const [],
      );
      final restored = bead.Pattern.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(restored.size, 40);
      expect(restored.height, 30);
    });
  });

  group('输入预滤波（质量提升）', () {
    test('预滤波不改网格尺寸与有效格数', () {
      final image = img.Image(width: 200, height: 200);
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 200; x++) {
          final p = image.getPixel(x, y);
          if ((x - 100).abs() < 50 && (y - 100).abs() < 50) {
            p.r = 220;
            p.g = 60;
            p.b = 40;
          } else {
            p.r = 240;
            p.g = 238;
            p.b = 232;
          }
        }
      }
      final converter = PatternConverter(palette);
      final a = converter.convertImage(
        image,
        const ConvertOptions(
            gridSize: 20, removeBackground: false, prefilterSmooth: false),
      );
      final b = converter.convertImage(
        image,
        const ConvertOptions(
            gridSize: 20, removeBackground: false, prefilterSmooth: true),
      );
      expect(a.pattern.size, b.pattern.size);
      expect(a.pattern.grid.length, b.pattern.grid.length);
      expect(a.pattern.totalBeads, greaterThan(0));
      expect(b.pattern.totalBeads, greaterThan(0));
    });

    test('带噪点照片：预滤波后色数不膨胀', () {
      // 40×40：半红半蓝 + 2% 随机噪点
      final image = img.Image(width: 40, height: 40);
      final rng = math.Random(3);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          final p = image.getPixel(x, y);
          if (x < 20) {
            p.r = 200;
            p.g = 40;
            p.b = 40;
          } else {
            p.r = 40;
            p.g = 60;
            p.b = 200;
          }
          if (rng.nextInt(50) == 0) {
            final n = rng.nextInt(60);
            p.r = (p.r + n).clamp(0, 255);
            p.g = (p.g + n).clamp(0, 255);
            p.b = (p.b + n).clamp(0, 255);
          }
        }
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(
            gridSize: 20, removeBackground: false, prefilterSmooth: true),
      );
      expect(result.pattern.colorCount, lessThanOrEqualTo(6),
          reason: '去噪后色数不应膨胀（半红半蓝各映射 1-2 色）');
    });

    test('边缘锐化：网格尺寸不变、有效格正常', () {
      // 黑白块 + 平滑过渡边界（锐化应让边界更清晰）
      final image = img.Image(width: 60, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 60; x++) {
          final p = image.getPixel(x, y);
          final dist = (x - 30).abs() + (y - 30).abs();
          final t = (dist / 20).clamp(0.0, 1.0);
          p.r = (30 + t * 200).round();
          p.g = (30 + t * 200).round();
          p.b = (30 + t * 200).round();
        }
      }
      final converter = PatternConverter(palette);
      final result = converter.convertImage(
        image,
        const ConvertOptions(
            gridSize: 20, removeBackground: false, prefilterSharpen: true),
      );
      expect(result.pattern.size, 20);
      expect(result.pattern.grid.length, 20 * 20);
      expect(result.pattern.totalBeads, greaterThan(0));
    });
  });
}
