import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/core/color_space.dart' show rgbToLab;
import 'package:doutu/core/oklab.dart';

void main() {
  group('OKLab 转换与距离', () {
    test('同色距离为 0', () {
      for (final (r, g, b) in [
        (0, 0, 0),
        (255, 255, 255),
        (255, 0, 0),
        (0, 0, 255),
        (128, 128, 128),
      ]) {
        final c = srgbToOklab(r, g, b);
        expect(oklabDistance(c, c), 0, reason: '($r,$g,$b)');
      }
    });

    test('黑/白端点合理（OKLab 官方性质：白 L≈1，黑 L≈0）', () {
      final white = srgbToOklab(255, 255, 255);
      expect(white.l, closeTo(1.0, 0.02));
      expect(white.a, closeTo(0.0, 0.01));
      expect(white.b, closeTo(0.0, 0.01));
      final black = srgbToOklab(0, 0, 0);
      expect(black.l, closeTo(0.0, 0.02));
    });

    test('感知距离：红色到相近红 < 红色到蓝色', () {
      final red = srgbToOklab(255, 0, 0);
      final orange = srgbToOklab(255, 120, 0);
      final blue = srgbToOklab(0, 0, 255);
      expect(oklabDistance(red, orange), lessThan(oklabDistance(red, blue)));
    });

    test('Lab→OKLab 往返不抛错且接近 RGB 直转', () {
      final fromRgb = srgbToOklab(100, 150, 200);
      final fromLab = labToOklab(rgbToLab(100, 150, 200));
      expect(oklabDistance(fromRgb, fromLab), lessThan(0.5));
    });
  });
}
