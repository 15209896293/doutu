/// 作品历史存储：跨端（io 文件 / web localStorage），仅存最近 20 个作品。
library;

import 'dart:convert';

import '../../models/project.dart';
import 'app_storage.dart';

class ProjectStore {
  final AppStorage storage;

  /// 存储目录/命名空间（如 'projects'）。
  final String folder;

  /// 最大保存数量（dev-plan：最近 20 个作品）。
  final int maxProjects;

  ProjectStore(this.storage, this.folder, {this.maxProjects = 20});

  String _jsonPath(String id) => '$folder/$id.json';

  String _thumbPath(String id) => '$folder/$id.png';

  /// 列出全部作品（按更新时间倒序）。
  Future<List<Project>> list() async {
    final projects = <Project>[];
    // list 返回完整相对路径（如 projects/p1.json）
    final paths = await storage.list('.json');
    for (final path in paths) {
      final text = await storage.readText(path);
      if (text == null) continue;
      try {
        projects.add(
          Project.fromJson(jsonDecode(text) as Map<String, dynamic>),
        );
      } catch (_) {
        // 损坏文件跳过
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  /// 保存作品（超出上限时删除最旧的）。
  Future<void> save(Project project) async {
    await storage.writeText(_jsonPath(project.id), jsonEncode(project.toJson()));
    await _trim();
  }

  /// 读取单个作品。
  Future<Project?> load(String id) async {
    final text = await storage.readText(_jsonPath(id));
    if (text == null) return null;
    try {
      return Project.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 删除作品（含缩略图）。
  Future<void> delete(String id) async {
    await storage.delete(_jsonPath(id));
    await storage.delete(_thumbPath(id));
  }

  /// 保存缩略图 PNG 字节。
  Future<void> saveThumbnail(String id, List<int> pngBytes) async {
    await storage.writeBytes(_thumbPath(id), pngBytes);
  }

  /// 读取缩略图字节；不存在返回 null。
  Future<List<int>?> thumbnail(String id) async =>
      storage.readBytes(_thumbPath(id));

  Future<void> _trim() async {
    final all = await list();
    if (all.length <= maxProjects) return;
    for (final old in all.skip(maxProjects)) {
      await delete(old.id);
    }
  }
}
