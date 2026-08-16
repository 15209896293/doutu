import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/core/color_mapper.dart';
import 'package:doutu/core/color_space.dart';
import 'package:doutu/core/palette.dart';
import 'package:doutu/core/post_processor.dart';
import 'package:doutu/core/sampler.dart';

// 简化色卡 Lab（4 色：0 白 1 黑 2 红 3 蓝）
final _labs = [
  rgbToLab(255, 255, 255),
  rgbToLab(0, 0, 0),
  rgbToLab(255, 0, 0),
  rgbToLab(0, 0, 255),
];

// 简化色卡（后处理用）
final _palette = Palette(
  id: 'tiny',
  displayName: 'Tiny',
  entries: [
    PaletteEntry(code: 'W', hex: '#FFFFFF', r: 255, g: 255, b: 255),
    PaletteEntry(code: 'K', hex: '#000000', r: 0, g: 0, b: 0),
    PaletteEntry(code: 'R', hex: '#FF0000', r: 255, g: 0, b: 0),
    PaletteEntry(code: 'B', hex: '#0000FF', r: 0, g: 0, b: 255),
  ],
);

SampleCell _cell(int rgb, {bool outline = false}) => SampleCell(
      rgb: rgb,
      coverage: 1,
      darkRatio: outline ? 0.8 : 0,
      luminanceRange: outline ? 0.5 : 0,
      isOutline: outline,
    );

void main() {
  group('杂色合并', () {
    test('1 格孤立杂色被并入相邻主色', () {
      // 5×5 全 0（白），中心 1 格为 1（黑）
      final grid = List<int>.filled(25, 0);
      grid[12] = 1;
      final result = postProcess(
        grid,
        5,
        const PostProcessOptions(minBlockSize: 2, removeBackground: false),
        labs: _labs,
      );
      expect(result.at(2, 2), 0, reason: '孤立黑格应并入白色');
      expect(result.grid.where((i) => i == 1), isEmpty);
    });

    test('2 格连通块（>= 阈值）保留', () {
      final grid = List<int>.filled(25, 0);
      grid[12] = 1;
      grid[13] = 1;
      final result = postProcess(
        grid,
        5,
        const PostProcessOptions(minBlockSize: 2, removeBackground: false),
        labs: _labs,
      );
      expect(result.at(2, 2), 1);
      expect(result.at(3, 2), 1);
    });

    test('孤立杂色在角落（边界）也能被合并', () {
      final grid = List<int>.filled(25, 0);
      grid[0] = 1; // 左上角
      final result = postProcess(
        grid,
        5,
        const PostProcessOptions(minBlockSize: 2, removeBackground: false),
        labs: _labs,
      );
      expect(result.at(0, 0), 0);
    });

    test('两个孤立杂色相邻时合并后颜色一致', () {
      final grid = List<int>.filled(25, 0);
      grid[12] = 1;
      grid[17] = 2; // 中心与正下方，互为邻居
      final result = postProcess(
        grid,
        5,
        const PostProcessOptions(minBlockSize: 2, removeBackground: false),
        labs: _labs,
      );
      // 两块都是 1 格孤立块，应合并为同一种颜色（较大邻块的颜色 = 白色 0）
      expect(result.at(2, 2), result.at(2, 3));
    });
  });

  group('背景移除', () {
    test('纯色边界 flood fill：整个纯色图被移除（无主体）', () {
      final grid = List<int>.filled(25, 0);
      final result = postProcess(
        grid,
        5,
        const PostProcessOptions(minBlockSize: 2, removeBackground: true),
        labs: _labs,
      );
      expect(result.grid.where((i) => i >= 0), isEmpty);
    });

    test('白底黑主体：白色背景移除，黑色主体保留', () {
      // 7×7 白底，中间 3×3 黑色块
      final grid = List<int>.filled(49, 0);
      for (var y = 2; y < 5; y++) {
        for (var x = 2; x < 5; x++) {
          grid[y * 7 + x] = 1;
        }
      }
      final result = postProcess(
        grid,
        7,
        const PostProcessOptions(minBlockSize: 2, removeBackground: true),
        labs: _labs,
      );
      expect(result.at(0, 0), -1, reason: '白背景应透明');
      expect(result.at(3, 3), 1, reason: '黑主体保留');
      // 主体面积 9
      expect(result.grid.where((i) => i == 1).length, 9);
    });

    test('背景色差大于阈值的不被移除', () {
      // 5×5 全红（色 2），中心 1 格白（0）。红与白 ΔE 大，背景只移除红
      final grid = List<int>.filled(25, 2);
      grid[12] = 0;
      final result = postProcess(
        grid,
        5,
        const PostProcessOptions(minBlockSize: 1, removeBackground: true),
        labs: _labs,
      );
      // 红背景（四边连通）被移除；中心白保留
      expect(result.at(0, 0), -1);
      expect(result.at(2, 2), 0);
    });

    test('关闭背景移除时不产生透明格', () {
      final grid = List<int>.filled(25, 0);
      final result = postProcess(
        grid,
        5,
        const PostProcessOptions(minBlockSize: 1, removeBackground: false),
        labs: _labs,
      );
      expect(result.grid.where((i) => i < 0), isEmpty);
    });
  });

  group('空间正则化', () {
    test('孤点被并入邻域主色（边缘保护生效）', () {
      // 5×5 全红(2)，中心 1 格蓝(3)：蓝为孤点
      final grid = List<int>.filled(25, 2);
      grid[12] = 3;
      final cells = List<SampleCell?>.filled(25, _cell(0xFFFF0000));
      final r = regularizeGrid(
        grid,
        cells,
        5,
        _palette,
        iterations: 2,
        smoothness: 2,
        edgeSigma: 10,
        distance: ColorDistance.oklab,
      );
      expect(r.grid[12], 2, reason: '孤立蓝点应并入红色');
    });

    test('轮廓格不参与正则化（不抹糊边缘）', () {
      final grid = List<int>.filled(25, 2);
      grid[12] = 1; // 黑轮廓格
      final cells = List<SampleCell?>.filled(25, _cell(0xFFFF0000));
      cells[12] = _cell(0xFF000000, outline: true);
      final r = regularizeGrid(
        grid,
        cells,
        5,
        _palette,
        iterations: 2,
        smoothness: 3,
        edgeSigma: 10,
        distance: ColorDistance.oklab,
      );
      expect(r.grid[12], 1, reason: '轮廓格保持不变');
    });
  });

  group('孤立单格区域移除', () {
    test('1 格孤岛并入邻域众数；2×2 块保留', () {
      // 7×7 全白(0)，中心 1 格黑(1) 孤岛，另有一 2×2 黑块
      final grid = List<int>.filled(49, 0);
      grid[3 * 7 + 3] = 1; // 单格孤岛
      grid[5 * 7 + 5] = 1; // 2×2 块
      grid[5 * 7 + 6] = 1;
      grid[6 * 7 + 5] = 1;
      grid[6 * 7 + 6] = 1;
      final cells = List<SampleCell?>.filled(49, _cell(0xFFFFFFFF));
      final out = removeSingleCellRegions(grid, cells, 7);
      expect(out[3 * 7 + 3], 0, reason: '单格孤岛应移除');
      expect(out[5 * 7 + 5], 1, reason: '2×2 块保留');
      expect(out[6 * 7 + 6], 1);
    });

    test('minRegionSize=3：≤3 格小色块并入相邻主色，4 格块保留', () {
      // 9×9 全白(0)；L 形 3 格黑块(1) + 2×2 黑块(1) + 2×2 红块(2)
      final grid = List<int>.filled(81, 0);
      // L 形 3 格黑块（面积 3 ≤ 3 应并入白色）
      grid[2 * 9 + 2] = 1;
      grid[2 * 9 + 3] = 1;
      grid[3 * 9 + 2] = 1;
      // 2×2 黑块（面积 4 > 3 保留）
      grid[5 * 9 + 5] = 1;
      grid[5 * 9 + 6] = 1;
      grid[6 * 9 + 5] = 1;
      grid[6 * 9 + 6] = 1;
      // 2×2 红块（面积 4 > 3 保留）
      grid[7 * 9 + 7] = 2;
      grid[7 * 9 + 8] = 2;
      grid[8 * 9 + 7] = 2;
      grid[8 * 9 + 8] = 2;
      final cells = List<SampleCell?>.filled(81, _cell(0xFFFFFFFF));
      final out = removeSingleCellRegions(grid, cells, 9, minRegionSize: 3);
      // L 形黑块被并入白色（邻域众数为白）
      expect(out[2 * 9 + 2], 0, reason: '3 格黑块应并入白色');
      expect(out[2 * 9 + 3], 0);
      expect(out[3 * 9 + 2], 0);
      // 2×2 黑块保留
      expect(out[5 * 9 + 5], 1);
      expect(out[6 * 9 + 6], 1);
      // 2×2 红块保留
      expect(out[7 * 9 + 7], 2);
      expect(out[8 * 9 + 8], 2);
    });
  });
}
