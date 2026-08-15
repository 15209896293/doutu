/// 库存存储：`{ 色卡id: { 色号: 已有颗数 } }`，跨端持久化。
library;

import 'dart:convert';

import 'app_storage.dart';

class InventoryStore {
  final AppStorage storage;
  final String path;

  InventoryStore(this.storage, this.path);

  Future<Map<String, Map<String, int>>> load() async {
    final text = await storage.readText(path);
    if (text == null) return {};
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
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
    await storage.writeText(path, jsonEncode(data));
  }
}
