import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/core/color_reducer.dart';
import 'package:doutu/core/color_space.dart';

// 4 色简化色卡
final _labs = [
  rgbToLab(255, 255, 255),
  rgbToLab(0, 0, 0),
  rgbToLab(255, 0, 0),
  rgbToLab(0, 0, 255),
];

void main() {
  group('色数削减', () {
    test('色数 ≤ 上限时不改动', () {
      final grid = <int>[0, 0, 1, 1];
      final result = reduceColorCount(grid, _labs, 4);
      expect(result.grid, grid);
      expect(result.usedColors, {0, 1});
    });

    test('超过上限时削减到上限', () {
      // 3 种色 → 限 2 色
      final grid = <int>[0, 0, 0, 1, 1, 2];
      final result = reduceColorCount(grid, _labs, 2);
      expect(result.usedColors.length, lessThanOrEqualTo(2));
      expect(result.grid.length, 6);
    });

    test('保留用量最大的色号', () {
      // 色 0 出现 50 次、色 1 出现 30 次、色 2 出现 20 次 → 限 2 保留 0 和 1
      final grid = <int>[
        ...List.filled(50, 0),
        ...List.filled(30, 1),
        ...List.filled(20, 2),
      ];
      final result = reduceColorCount(grid, _labs, 2);
      expect(result.usedColors, {0, 1});
    });

    test('透明格（-1）保持透明', () {
      final grid = <int>[0, -1, 2, 2];
      final result = reduceColorCount(grid, _labs, 1);
      expect(result.grid[1], -1);
      expect(result.usedColors.length, 1);
    });

    test('被淘汰色映射到 ΔE00 最近的保留色', () {
      // 色 0 白、色 1 黑、色 3 蓝。限 2 色：白 3 格、黑 3 格、蓝 1 格
      // 蓝（1 格）被淘汰，应映射到更近的黑（ΔE00(蓝,黑) < ΔE00(蓝,白)）
      final grid = <int>[0, 0, 0, 1, 1, 1, 3];
      final result = reduceColorCount(grid, _labs, 2);
      expect(result.usedColors, {0, 1});
      expect(result.grid[6], 1, reason: '蓝色应并入更近的黑色');
    });
  });
}
