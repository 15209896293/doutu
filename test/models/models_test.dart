import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/core/pattern_converter.dart';
import 'package:doutu/models/board_preset.dart';
import 'package:doutu/models/pattern.dart';
import 'package:doutu/models/project.dart';
import 'package:doutu/shared/storage/app_settings.dart';

void main() {
  group('BoardPreset', () {
    test('预设包含圆形板', () {
      expect(BoardPreset.presets.any((p) => p.shape == BoardShape.circle), isTrue);
    });

    test('29 圆形板掩码：中心在内、四角在外', () {
      // 29×29 圆板，中心 (14,14)
      expect(BoardPreset.isInsideCircle(14, 14, 29), isTrue);
      expect(BoardPreset.isInsideCircle(0, 0, 29), isFalse);
      expect(BoardPreset.isInsideCircle(28, 0, 29), isFalse);
      expect(BoardPreset.isInsideCircle(0, 28, 29), isFalse);
      expect(BoardPreset.isInsideCircle(28, 28, 29), isFalse);
      // 顶部中点应在圆内（半径 14，y=0 距中心 14）
      expect(BoardPreset.isInsideCircle(14, 0, 29), isTrue);
    });

    test('圆形板格数约为 πr²（π×14² ≈ 616，容差 ±8%）', () {
      var count = 0;
      for (var y = 0; y < 29; y++) {
        for (var x = 0; x < 29; x++) {
          if (BoardPreset.isInsideCircle(x, y, 29)) count++;
        }
      }
      expect(count, closeTo(616, 616 * 0.08));
    });
  });

  group('Pattern 序列化', () {
    test('JSON 往返', () {
      final pattern = Pattern(
        size: 4,
        grid: [0, 1, -1, 2, 1, 1, 0, -1, -1, 2, 2, 0, 0, -1, 1, 1],
        paletteId: 'mard_221',
        bom: [
          const BomEntry(code: 'H02', count: 5, color: 0xFFFFFF),
          const BomEntry(code: 'H07', count: 3, color: 0x000000),
        ],
      );
      final json = jsonDecode(jsonEncode(pattern.toJson()));
      final restored = Pattern.fromJson(json as Map<String, dynamic>);
      expect(restored.size, 4);
      expect(restored.grid, pattern.grid);
      expect(restored.totalBeads, 12);
      expect(restored.bom.length, 2);
      expect(restored.bom[0].code, 'H02');
      expect(restored.bom[1].count, 3);
    });
  });

  group('Project 序列化', () {
    test('参数 JSON 往返（含圆形掩码）', () {
      const options = ConvertOptions(
        gridSize: 29,
        maxColors: 16,
        dither: true,
        removeBackground: false,
        maskShape: 'circle',
      );
      final params = Project.paramsFrom(options);
      expect(params['maskShape'], 'circle');
      final restored = Project.optionsFrom(params);
      expect(restored.gridSize, 29);
      expect(restored.maxColors, 16);
      expect(restored.dither, true);
      expect(restored.removeBackground, false);
      expect(restored.maskShape, 'circle');
    });

    test('无掩码参数往返', () {
      const options = ConvertOptions(gridSize: 52);
      final restored = Project.optionsFrom(Project.paramsFrom(options));
      expect(restored.maskShape, isNull);
    });
  });

  group('AppSettings', () {
    test('默认值', () {
      const s = AppSettings();
      expect(s.paletteId, 'mard_221');
      expect(s.boardId, '81');
      expect(s.tourSeen, false);
      expect(s.cropTourSeen, false);
      expect(s.autoFrameSubject, false);
      expect(s.dither, false);
      expect(s.maxColors, 10);
      expect(s.presetId, 'standard');
      expect(s.colorDistanceMode, 'oklab');
    });

    test('JSON 往返', () {
      const s = AppSettings(
        paletteId: 'perler',
        boardId: '29c',
        maxColors: 8,
        dither: true,
      );
      final json = jsonDecode(jsonEncode(s.toJson()));
      final restored = AppSettings.fromJson(json as Map<String, dynamic>);
      expect(restored.paletteId, 'perler');
      expect(restored.boardId, '29c');
      expect(restored.maxColors, 8);
      expect(restored.dither, true);
    });

    test('损坏 JSON 回退默认', () {
      final restored = AppSettings.fromJson(const {'bad': 'data'});
      expect(restored.paletteId, 'mard_221');
    });
  });
}
