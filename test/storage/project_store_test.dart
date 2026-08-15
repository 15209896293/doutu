import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/models/pattern.dart';
import 'package:doutu/models/project.dart';
import 'package:doutu/shared/storage/project_store.dart';

Project _makeProject(String id, String name, {int ageMinutes = 0}) {
  return Project(
    id: id,
    name: name,
    createdAt: DateTime(2026, 8, 14, 12, 0).subtract(Duration(minutes: ageMinutes)),
    updatedAt: DateTime(2026, 8, 14, 12, 0).subtract(Duration(minutes: ageMinutes)),
    convertParams: const {'gridSize': 52},
    pattern: Pattern(
      size: 2,
      grid: const [0, 1, 1, -1],
      paletteId: 'mard_221',
      bom: const [
        BomEntry(code: 'A01', count: 1, color: 0xFFFFFF),
        BomEntry(code: 'H07', count: 2, color: 0x000000),
      ],
    ),
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('doutu_store_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ProjectStore', () {
    test('保存与读取往返', () async {
      final store = ProjectStore(tempDir);
      final project = _makeProject('p1', '测试作品');
      await store.save(project);

      final loaded = await store.load('p1');
      expect(loaded, isNotNull);
      expect(loaded!.name, '测试作品');
      expect(loaded.pattern.size, 2);
      expect(loaded.pattern.bom.length, 2);
    });

    test('列表按更新时间倒序', () async {
      final store = ProjectStore(tempDir);
      await store.save(_makeProject('p1', '旧', ageMinutes: 60));
      await store.save(_makeProject('p2', '新', ageMinutes: 0));
      await store.save(_makeProject('p3', '中', ageMinutes: 30));

      final list = await store.list();
      expect(list.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);
    });

    test('超过上限时裁剪最旧作品', () async {
      final store = ProjectStore(tempDir, maxProjects: 2);
      for (var i = 0; i < 5; i++) {
        await store.save(_makeProject('p$i', '作品$i', ageMinutes: i * 10));
      }
      final list = await store.list();
      expect(list.length, 2);
      // 最新两个保留
      expect(list.map((p) => p.id).toSet(), {'p0', 'p1'});
    });

    test('删除作品', () async {
      final store = ProjectStore(tempDir);
      await store.save(_makeProject('p1', 'x'));
      await store.delete('p1');
      expect(await store.load('p1'), isNull);
      expect(await store.list(), isEmpty);
    });

    test('损坏 JSON 文件被跳过', () async {
      final store = ProjectStore(tempDir);
      await File('${tempDir.path}${Platform.pathSeparator}broken.json')
          .writeAsString('{not valid json');
      final list = await store.list();
      expect(list, isEmpty);
    });

    test('缩略图保存与读取', () async {
      final store = ProjectStore(tempDir);
      final bytes = List<int>.generate(100, (i) => i % 256);
      await store.saveThumbnail('p1', bytes);
      final loaded = await store.thumbnail('p1');
      expect(loaded, bytes);
      // 不存在时返回 null
      expect(await store.thumbnail('nope'), isNull);
    });
  });
}
