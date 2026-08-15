import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/core/color_space.dart';
import 'package:doutu/core/post_processor.dart';

// 简化色卡 Lab（4 色：0 白 1 黑 2 红 3 蓝）
final _labs = [
  rgbToLab(255, 255, 255),
  rgbToLab(0, 0, 0),
  rgbToLab(255, 0, 0),
  rgbToLab(0, 0, 255),
];

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
}
