import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/models/pattern.dart';
import 'package:doutu/shared/storage/app_storage_io.dart';
import 'package:doutu/shared/storage/craft_progress_store.dart';

Pattern _pattern(List<int> grid) => Pattern(
      size: 2,
      grid: grid,
      paletteId: 'mard_221',
      bom: const [BomEntry(code: 'A01', count: 3, color: 0xFFFFFF)],
    );

void main() {
  test('相同图纸指纹一致，不同网格指纹不同', () {
    final a = craftFingerprint(_pattern(const [0, 1, 1, -1]));
    final b = craftFingerprint(_pattern(const [0, 1, 1, -1]));
    final c = craftFingerprint(_pattern(const [0, 1, 1, 0]));
    expect(a, b);
    expect(a, isNot(c));
  });

  test('进度保存与读取往返', () async {
    final dir = await Directory.systemTemp.createTemp('doutu_craft_test');
    try {
      final store = CraftProgressStore(IoAppStorage(dir), 'progress.json');
      final fp = craftFingerprint(_pattern(const [0, 1, 1, -1]));
      await store.save(fp, {0, 2});
      expect(await store.load(fp), {0, 2});
      expect(await store.load('deadbeef'), isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
