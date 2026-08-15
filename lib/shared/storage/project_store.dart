/// 作品历史存储：JSON 文件 + PNG 缩略图。
///
/// 替代 dev-plan 的 sqflite 方案：仅存最近 20 个作品、无查询需求，
/// 文件存储零额外依赖、包体更小、可在纯 Dart 测试中注入临时目录。
library;

import 'dart:convert';
import 'dart:io';

import '../../models/project.dart';

/// 存储抽象（便于测试注入目录）。
class ProjectStore {
  /// 存储目录（App 运行时的文件系统路径）。
  final Directory dir;

  /// 最大保存数量（dev-plan：最近 20 个作品）。
  final int maxProjects;

  ProjectStore(this.dir, {this.maxProjects = 20});

  File _fileFor(String id) => File('${dir.path}${Platform.pathSeparator}$id.json');

  File _thumbFor(String id) => File('${dir.path}${Platform.pathSeparator}$id.png');

  /// 列出全部作品（按更新时间倒序）。
  Future<List<Project>> list() async {
    if (!await dir.exists()) return const [];
    final projects = <Project>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        projects.add(Project.fromJson(json));
      } catch (_) {
        // 损坏文件跳过
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  /// 保存作品（超出上限时删除最旧的）。
  Future<void> save(Project project) async {
    await dir.create(recursive: true);
    await _fileFor(project.id)
        .writeAsString(jsonEncode(project.toJson()), flush: true);
    await _trim();
  }

  /// 读取单个作品。
  Future<Project?> load(String id) async {
    final file = _fileFor(id);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return Project.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// 删除作品（含缩略图）。
  Future<void> delete(String id) async {
    final f = _fileFor(id);
    if (await f.exists()) await f.delete();
    final t = _thumbFor(id);
    if (await t.exists()) await t.delete();
  }

  /// 保存缩略图 PNG 字节。
  Future<void> saveThumbnail(String id, List<int> pngBytes) async {
    await dir.create(recursive: true);
    await _thumbFor(id).writeAsBytes(pngBytes, flush: true);
  }

  /// 读取缩略图字节；不存在返回 null。
  Future<List<int>?> thumbnail(String id) async {
    final t = _thumbFor(id);
    if (!await t.exists()) return null;
    return t.readAsBytes();
  }

  Future<void> _trim() async {
    final all = await list();
    if (all.length <= maxProjects) return;
    for (final old in all.skip(maxProjects)) {
      await delete(old.id);
    }
  }
}
