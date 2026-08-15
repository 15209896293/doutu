import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/shared/storage/inventory_store.dart';

void main() {
  test('库存保存与读取往返', () async {
    final dir = await Directory.systemTemp.createTemp('doutu_inv_test');
    try {
      final store = InventoryStore(
        File('${dir.path}${Platform.pathSeparator}inventory.json'),
      );
      await store.save({
        'mard_221': {'A01': 12, 'H07': 3},
      });
      final loaded = await store.load();
      expect(loaded['mard_221']!['A01'], 12);
      expect(loaded['mard_221']!['H07'], 3);
      expect(await store.load(), isNotEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
