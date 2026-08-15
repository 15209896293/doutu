/// web 存储实现：localStorage（浏览器）。
///
/// 仅用于 Web 编译；字节按 base64 编码存储。
library;

import 'dart:convert';

import 'package:web/web.dart' as web;

import 'app_storage.dart';

class WebAppStorage implements AppStorage {
  static const _prefix = 'doutu:';

  web.Storage get _storage => web.window.localStorage;

  String _key(String path) => '$_prefix$path';

  @override
  Future<String?> readText(String path) async => _storage.getItem(_key(path));

  @override
  Future<void> writeText(String path, String content) async =>
      _storage.setItem(_key(path), content);

  @override
  Future<List<int>?> readBytes(String path) async {
    final s = _storage.getItem(_key(path));
    if (s == null) return null;
    return base64Decode(s);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async =>
      _storage.setItem(_key(path), base64Encode(bytes));

  @override
  Future<bool> exists(String path) async =>
      _storage.getItem(_key(path)) != null;

  @override
  Future<void> delete(String path) async => _storage.removeItem(_key(path));

  @override
  Future<List<String>> list(String prefix) async {
    final out = <String>[];
    for (var i = 0; i < _storage.length; i++) {
      final k = _storage.key(i);
      if (k != null && k.startsWith(_prefix) && k.contains(prefix)) {
        out.add(k.substring(_prefix.length));
      }
    }
    return out;
  }
}
