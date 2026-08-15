/// 跟做进度存储：按图纸内容指纹持久化"已拼格"，拼一半退出后可续拼。
///
/// 内容寻址：相同图纸（同色卡 + 同尺寸 + 同网格）得到相同指纹，
/// 无论是否已保存为作品，进度都能跨重启恢复。跨端（io / web）持久化。
library;

import 'dart:convert';

import '../../models/pattern.dart';
import 'app_storage.dart';

/// 计算图纸的稳定指纹（FNV-1a 32bit，纯 Dart，跨重启稳定）。
String craftFingerprint(Pattern pattern) {
  var h = 0x811c9dc5;
  void mix(int byte) {
    h ^= byte & 0xFF;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }

  void mixInt(int v) {
    mix(v & 0xFF);
    mix((v >> 8) & 0xFF);
    mix((v >> 16) & 0xFF);
    mix((v >> 24) & 0xFF);
  }

  for (final c in pattern.paletteId.codeUnits) {
    mix(c);
  }
  mixInt(pattern.size);
  for (final idx in pattern.grid) {
    mixInt(idx);
  }
  return h.toRadixString(16);
}

/// 进度存储：`{ 指纹: [已拼格下标...] }`。
class CraftProgressStore {
  final AppStorage storage;
  final String path;

  CraftProgressStore(this.storage, this.path);

  Future<Map<String, List<int>>> _load() async {
    final text = await storage.readText(path);
    if (text == null) return {};
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      return json.map(
        (k, v) => MapEntry(k, (v as List<dynamic>).cast<int>()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<Set<int>> load(String fingerprint) async {
    final map = await _load();
    return (map[fingerprint] ?? const <int>[]).toSet();
  }

  Future<void> save(String fingerprint, Set<int> done) async {
    final map = await _load();
    map[fingerprint] = done.toList()..sort();
    await storage.writeText(path, jsonEncode(map));
  }
}
