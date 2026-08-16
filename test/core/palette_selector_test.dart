import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/core/color_mapper.dart';
import 'package:doutu/core/palette.dart';
import 'package:doutu/core/palette_selector.dart';
import 'package:doutu/core/sampler.dart';

// 6 色简化色卡：0 白 1 黑 2 红 3 蓝 4 绿 5 黄
final _palette = Palette(
  id: 'tiny',
  displayName: 'Tiny',
  entries: [
    PaletteEntry(code: 'W', hex: '#FFFFFF', r: 255, g: 255, b: 255),
    PaletteEntry(code: 'K', hex: '#000000', r: 0, g: 0, b: 0),
    PaletteEntry(code: 'R', hex: '#FF0000', r: 255, g: 0, b: 0),
    PaletteEntry(code: 'B', hex: '#0000FF', r: 0, g: 0, b: 255),
    PaletteEntry(code: 'G', hex: '#00FF00', r: 0, g: 255, b: 0),
    PaletteEntry(code: 'Y', hex: '#FFFF00', r: 255, g: 255, b: 0),
  ],
);

SampleCell _cell(int rgb, {double coverage = 1, bool outline = false}) =>
    SampleCell(
      rgb: rgb,
      coverage: coverage,
      darkRatio: outline ? 0.8 : 0,
      luminanceRange: outline ? 0.5 : 0,
      isOutline: outline,
    );

void main() {
  group('贪心最大覆盖选色', () {
    test('色数上限生效：红蓝各半 → 2 色内', () {
      final cells = <SampleCell?>[
        ...List.generate(8, (_) => _cell(0xFFFF0000)), // 红
        ...List.generate(8, (_) => _cell(0xFF0000FF)), // 蓝
      ];
      final mapper = ColorMapper(_palette, distance: ColorDistance.oklab);
      final sel = PaletteSelector(_palette, mapper).selectAndMap(
        cells,
        gridSize: 4,
        maxColors: 2,
      );
      expect(sel.selectedIndices.length, lessThanOrEqualTo(2));
      expect(sel.grid.where((i) => i == 2).length, 8, reason: '红 → R');
      expect(sel.grid.where((i) => i == 3).length, 8, reason: '蓝 → B');
    });

    test('平均映射色差非负且有限', () {
      final cells = <SampleCell?>[
        _cell(0xFF123456),
        _cell(0xFF654321),
        _cell(0xFFAABBCC),
      ];
      final mapper = ColorMapper(_palette, distance: ColorDistance.oklab);
      final sel = PaletteSelector(_palette, mapper).selectAndMap(
        cells,
        gridSize: 2,
        maxColors: 0,
      );
      expect(sel.meanMappingDistance, greaterThanOrEqualTo(0));
      expect(sel.meanMappingDistance.isFinite, isTrue);
      expect(sel.grid.where((i) => i >= 0).length, 3);
    });

    test('allowedIndices 限制候选', () {
      final cells = <SampleCell?>[
        _cell(0xFFFF0000),
        _cell(0xFFFF0000),
        _cell(0xFFFF0000),
        _cell(0xFFFF0000),
      ];
      final mapper = ColorMapper(_palette, distance: ColorDistance.oklab);
      final sel = PaletteSelector(_palette, mapper).selectAndMap(
        cells,
        gridSize: 2,
        maxColors: 1,
        allowedIndices: const [4], // 只有绿
      );
      expect(sel.grid.every((i) => i == 4), isTrue);
    });
  });

  group('聚类吸附（cluster-then-snap）', () {
    test('色数 ≤ 上限且轮廓格映射到最暗被选色', () {
      // 白底 6 格 + 黑轮廓 2 格
      final cells = <SampleCell?>[
        ...List.generate(6, (_) => _cell(0xFFFFFFFF)),
        _cell(0xFF000000, outline: true),
        _cell(0xFF111111, outline: true),
      ];
      final mapper = ColorMapper(_palette, distance: ColorDistance.oklab);
      final sel = PaletteSelector(_palette, mapper).selectAndMap(
        cells,
        gridSize: 3,
        maxColors: 2,
        outlineWeight: 3,
        mode: PaletteSelectionMode.clusterSnap,
      );
      expect(sel.selectedIndices.length, lessThanOrEqualTo(2));
      // 轮廓格 → 最暗（黑 1）
      expect(sel.grid[6], 1);
      expect(sel.grid[7], 1);
      // 白格 → 白 0
      expect(sel.grid[0], 0);
    });
  });
}
