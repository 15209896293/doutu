import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doutu/core/palette.dart';
import 'package:doutu/core/pattern_converter.dart';

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
}
