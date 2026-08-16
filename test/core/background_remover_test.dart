import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doutu/core/background_remover.dart';

void main() {
  group('背景检测（像素级双阈值 + 多锚点）', () {
    test('纯色背景 + 居中主体 → 检测并移除背景', () {
      final image = img.Image(width: 60, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 60; x++) {
          final p = image.getPixel(x, y);
          final inside = (x - 30).abs() < 10 && (y - 30).abs() < 10;
          if (inside) {
            p.r = 200;
            p.g = 40;
            p.b = 40;
          } else {
            p.r = 245;
            p.g = 243;
            p.b = 238; // 米白背景
          }
        }
      }
      final result = detectBackground(image);
      expect(result.detected, isTrue, reason: '纯色背景应被检测');
      expect(result.confidence, greaterThanOrEqualTo(0.85));
      // 角落应为背景
      expect(result.mask[0], 1);
      expect(result.mask[60 * 60 - 1], 1);
      // 中心主体不应是背景
      expect(result.mask[30 * 60 + 30], 0);
    });

    test('双色背景（上浅蓝下米白）→ 多锚点整块移除', () {
      final image = img.Image(width: 60, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 60; x++) {
          final p = image.getPixel(x, y);
          final inside = (x - 30).abs() < 8 && (y - 30).abs() < 8;
          if (inside) {
            p.r = 80;
            p.g = 60;
            p.b = 50;
          } else if (y < 30) {
            p.r = 200;
            p.g = 225;
            p.b = 240; // 浅蓝
          } else {
            p.r = 245;
            p.g = 240;
            p.b = 228; // 米白
          }
        }
      }
      final result = detectBackground(image);
      expect(result.detected, isTrue, reason: '双色背景应被检测');
      expect(result.mask[0], 1, reason: '左上浅蓝为背景');
      expect(result.mask[59 * 60 + 0], 1, reason: '左下米白为背景');
      expect(result.mask[59 * 60 + 59], 1, reason: '右下米白为背景');
      expect(result.mask[30 * 60 + 30], 0, reason: '主体保留');
    });

    test('渐变背景 → 整块移除', () {
      final image = img.Image(width: 60, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 60; x++) {
          final p = image.getPixel(x, y);
          final inside = (x - 30).abs() < 10 && (y - 30).abs() < 10;
          if (inside) {
            p.r = 220;
            p.g = 110;
            p.b = 30;
          } else {
            final base = 235 + (y / 60) * 20; // 明度渐变
            p.r = base.round();
            p.g = (base - 6).round();
            p.b = (base - 14).round();
          }
        }
      }
      final result = detectBackground(image);
      expect(result.detected, isTrue, reason: '渐变背景应被检测');
      expect(result.mask[0], 1);
      expect(result.mask[59 * 60 + 59], 1);
      expect(result.mask[30 * 60 + 30], 0);
    });

    test('主体铺满画面 → 不误判背景', () {
      final image = img.Image(width: 60, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 60; x++) {
          final p = image.getPixel(x, y);
          p.r = (x * 4).clamp(0, 255);
          p.g = (y * 4).clamp(0, 255);
          p.b = ((x + y) * 2).clamp(0, 255);
        }
      }
      final result = detectBackground(image);
      expect(result.detected, isFalse, reason: '无单一背景色的图不应误判');
    });

    test('全透明图 → alpha 掩码生效', () {
      final image = img.Image(width: 20, height: 20, numChannels: 4);
      for (final p in image) {
        p.a = 0;
      }
      final result = detectBackground(image);
      expect(result.mask.every((v) => v == 1), isTrue,
          reason: '全透明像素应全为背景');
    });

    test('主体颜色接近背景（白主体+米白背景）→ 放弃移除，避免吞掉主体', () {
      final image = img.Image(width: 60, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 60; x++) {
          final p = image.getPixel(x, y);
          final inside = (x - 30).abs() < 15 && (y - 30).abs() < 15;
          if (inside) {
            p.r = 255;
            p.g = 255;
            p.b = 255; // 白主体
          } else {
            p.r = 245;
            p.g = 243;
            p.b = 238; // 米白背景
          }
        }
      }
      final result = detectBackground(image);
      expect(result.detected, isFalse,
          reason: '主体与背景色差过小，应放弃移除而非吞掉主体');
      expect(result.mask.where((m) => m == 0).length, greaterThan(2000),
          reason: '前景（主体）应保留');
    });

    test('纯色图（全背景无主体）→ 放弃移除，不误删', () {
      final image = img.Image(width: 40, height: 40);
      for (final p in image) {
        p.r = 250;
        p.g = 248;
        p.b = 240;
      }
      final result = detectBackground(image);
      expect(result.detected, isFalse,
          reason: '无主体的纯色图不应全标记为背景');
    });
  });
}
