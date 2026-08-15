import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doutu/core/sampler.dart';

void main() {
  group('区域主色采样', () {
    test('纯色图 → 全部格子为该色', () {
      // 40×40 纯蓝图，10×10 网格
      final image = img.Image(width: 40, height: 40);
      for (final p in image) {
        p.r = 0;
        p.g = 100;
        p.b = 200;
      }
      final sampled = sampleDominantColors(
        image,
        const SamplerOptions(gridSize: 10, histogramStep: 16),
      );
      expect(sampled.size, 10);
      for (final c in sampled.colors) {
        expect(c & 0xFF, 200); // b 分量（桶中心）
      }
    });

    test('半红半蓝图 → 对应格子分别为红/蓝主色', () {
      final image = img.Image(width: 40, height: 40);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          final p = image.getPixel(x, y);
          if (x < 20) {
            p.r = 255;
            p.g = 0;
            p.b = 0;
          } else {
            p.r = 0;
            p.g = 0;
            p.b = 255;
          }
        }
      }
      final sampled = sampleDominantColors(
        image,
        const SamplerOptions(gridSize: 4, histogramStep: 16),
      );
      // 4×4 网格，左 2 列红、右 2 列蓝
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          final c = sampled.colorAt(x, y);
          final r = (c >> 16) & 0xFF;
          final b = c & 0xFF;
          if (x < 2) {
            expect(r, greaterThan(b), reason: '($x,$y) 应为红主色');
          } else {
            expect(b, greaterThan(r), reason: '($x,$y) 应为蓝主色');
          }
        }
      }
    });

    test('多色混入 → 主色为占比最高色', () {
      // 20×20 图：70% 红 + 30% 蓝，1×1 网格
      final image = img.Image(width: 20, height: 20);
      var i = 0;
      for (final p in image) {
        if (i < 280) {
          p.r = 255;
          p.g = 0;
          p.b = 0;
        } else {
          p.r = 0;
          p.g = 0;
          p.b = 255;
        }
        i++;
      }
      final sampled = sampleDominantColors(
        image,
        const SamplerOptions(gridSize: 1, histogramStep: 16),
      );
      final c = sampled.colors[0];
      expect((c >> 16) & 0xFF, greaterThan(c & 0xFF));
    });

    test('平均色记录正确（纯色图平均=主色）', () {
      final image = img.Image(width: 16, height: 16);
      for (final p in image) {
        p.r = 128;
        p.g = 64;
        p.b = 32;
      }
      final sampled = sampleDominantColors(
        image,
        const SamplerOptions(gridSize: 4, histogramStep: 16),
      );
      final avg = sampled.avgColors[0];
      expect((avg >> 16) & 0xFF, 128);
      expect((avg >> 8) & 0xFF, 64);
      expect(avg & 0xFF, 32);
    });
  });
}
