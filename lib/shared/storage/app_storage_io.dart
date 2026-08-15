/// io 存储实现：文件系统（移动端 / 桌面）。
library;

import 'dart:io';

import 'app_storage.dart';

class IoAppStorage implements AppStorage {
  final Directory root;

  IoAppStorage(this.root);

  String _path(String p) => '${root.path}${Platform.pathSeparator}$p';

  @override
  Future<String?> readText(String path) async {
    final f = File(_path(path));
    if (!await f.exists()) return null;
    try {
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeText(String path, String content) async {
    final f = File(_path(path));
    await f.parent.create(recursive: true);
    await f.writeAsString(content, flush: true);
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    final f = File(_path(path));
    if (!await f.exists()) return null;
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final f = File(_path(path));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<bool> exists(String path) async => File(_path(path)).exists();

  @override
  Future<void> delete(String path) async {
    final f = File(_path(path));
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<String>> list(String prefix) async {
    if (!await root.exists()) return const [];
    final out = <String>[];
    await for (final e in root.list(recursive: true)) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (!name.contains(prefix)) continue;
      final rel = e.path
          .substring(root.path.length + 1)
          .replaceAll('\\', '/');
      out.add(rel);
    }
    return out;
  }
}
