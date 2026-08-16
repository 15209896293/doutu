import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/core/ciede2000.dart';
import 'package:doutu/core/color_mapper.dart';
import 'package:doutu/core/color_space.dart';
import 'package:doutu/core/palette.dart';

void main() {
  late Palette palette;
  late ColorMapper mapper;

  setUpAll(() async {
    final file = File('lib/core/palettes/mard_221.json');
    final json = await file.readAsString();
    palette = Palette.fromJsonString('mard_221', 'MARD 221', json);
    mapper = ColorMapper(palette);
  });

  group('KD-tree 映射器', () {
    test('色卡规模 = 221', () {
      expect(palette.length, 221);
    });

    test('纯白色映射到 H01（MARD 纯白，核对版数据）', () {
      final entry = mapper.nearest(rgbToLab(255, 255, 255));
      expect(entry.code, 'H01');
    });

    test('纯黑色映射到 H07（MARD 黑色）', () {
      final entry = mapper.nearest(rgbToLab(0, 0, 0));
      expect(entry.code, 'H07');
    });

    test('色卡自身颜色映射回自身（前 50 色）', () {
      for (var i = 0; i < 50; i++) {
        final e = palette.entries[i];
        final mapped = mapper.nearest(e.lab);
        expect(mapped.code, e.code,
            reason: 'palette color ${e.code} mapped to ${mapped.code}');
      }
    });

    test('与暴力 ΔE00 扫描一致（500 个真实 sRGB 随机查询）', () {
      // 查询色来自真实 sRGB 空间（与生产场景一致）：
      // 随机 RGB + 色卡色微扰，覆盖照片中可能出现的全部颜色。
      final rng = math.Random(42);
      for (var t = 0; t < 500; t++) {
        final LabColor query;
        if (t < 250) {
          query = rgbToLab(
            rng.nextInt(256),
            rng.nextInt(256),
            rng.nextInt(256),
          );
        } else {
          final base = palette.entries[rng.nextInt(palette.length)].lab;
          query = LabColor(
            (base.l + (rng.nextDouble() - 0.5) * 10).clamp(0, 100),
            (base.a + (rng.nextDouble() - 0.5) * 20).clamp(-128, 128),
            (base.b + (rng.nextDouble() - 0.5) * 20).clamp(-128, 128),
          );
        }
        final kdIdx = mapper.nearestIndex(query);
        final bfIdx = _bruteNearest(mapper.labs, query);
        expect(kdIdx, bfIdx,
            reason: 'query $query: kd=$kdIdx bf=$bfIdx');
      }
    });
  });

  group('空色卡防护', () {
    test('空色卡 nearest 抛出 StateError', () {
      final empty = ColorMapper(
        Palette(id: 'x', displayName: 'x', entries: const []),
      );
      expect(() => empty.nearest(LabColor(50, 0, 0)), throwsStateError);
    });
  });
}

int _bruteNearest(List<LabColor> labs, LabColor query) {
  var best = 0;
  var bestDist = double.infinity;
  for (var i = 0; i < labs.length; i++) {
    final d = ciede2000(labs[i], query);
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}
