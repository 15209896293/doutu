/// 库存存储：`{ 色卡id: { 色号: 已有颗数 } }`，JSON 文件持久化。
library;

import 'dart:convert';
import 'dart:io';

class InventoryStore {
  final File file;

  InventoryStore(this.file);

  Future<Map<String, Map<String, int>>> load() async {
    if (!await file.exists()) return {};
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final out = <String, Map<String, int>>{};
      json.forEach((paletteId, inner) {
        final m = <String, int>{};
        (inner as Map<String, dynamic>).forEach((code, n) {
          m[code] = (n as num).toInt();
        });
        out[paletteId] = m;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, Map<String, int>> data) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data), flush: true);
  }
}
