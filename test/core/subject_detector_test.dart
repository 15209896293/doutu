import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doutu/core/subject_detector.dart';

void main() {
  test('纯白背景 + 居中红块 → 框出红块区域', () {
    final image = img.Image(width: 100, height: 100);
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 100; x++) {
        final p = image.getPixel(x, y);
        final inside = x >= 30 && x < 70 && y >= 30 && y < 70;
        p.r = inside ? 220 : 250;
        p.g = inside ? 30 : 250;
        p.b = inside ? 30 : 250;
      }
    }
    final region = detectSubject(image);
    expect(region, isNotNull);
    // 主体包围盒大致覆盖中心红块（含少量容差）
    expect(region!.x, lessThanOrEqualTo(35));
    expect(region.y, lessThanOrEqualTo(35));
    expect(region.x + region.width, greaterThanOrEqualTo(65));
    expect(region.y + region.height, greaterThanOrEqualTo(65));
  });

  test('无背景（主体铺满）→ 返回 null', () {
    final image = img.Image(width: 40, height: 40);
    for (final p in image) {
      p.r = 200;
      p.g = 100;
      p.b = 50;
    }
    expect(detectSubject(image), isNull);
  });

  test('主体旁有小型字幕时优先框选中心主体', () {
    final image = img.Image(width: 160, height: 120);
    for (final p in image) {
      p
        ..r = 250
        ..g = 250
        ..b = 250;
    }
    // 居中大主体。
    for (var y = 35; y < 105; y++) {
      for (var x = 55; x < 125; x++) {
        final p = image.getPixel(x, y);
        p
          ..r = 45
          ..g = 85
          ..b = 180;
      }
    }
    // 左上角独立气泡/字幕。
    for (var y = 6; y < 24; y++) {
      for (var x = 6; x < 42; x++) {
        final p = image.getPixel(x, y);
        p
          ..r = 20
          ..g = 20
          ..b = 20;
      }
    }
    final region = detectSubject(image);
    expect(region, isNotNull);
    expect(region!.x, greaterThan(35), reason: '不应把左上字幕纳入主裁剪框');
    expect(region.y, greaterThan(20));
  });
}
