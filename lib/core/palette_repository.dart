/// 色卡仓库：加载内置色卡 JSON（assets）。
library;

import 'dart:io';

import 'palette.dart';

/// 内置色卡元信息。
class PaletteMeta {
  final String id;
  final String displayName;
  final String assetPath;

  const PaletteMeta({
    required this.id,
    required this.displayName,
    required this.assetPath,
  });
}

/// 内置色卡清单（默认 MARD 221）。
const kPaletteMetas = <PaletteMeta>[
  PaletteMeta(
    id: 'mard_221',
    displayName: 'MARD 221',
    assetPath: 'lib/core/palettes/mard_221.json',
  ),
  PaletteMeta(
    id: 'mard_291',
    displayName: 'MARD 291',
    assetPath: 'lib/core/palettes/mard_291.json',
  ),
  PaletteMeta(
    id: 'perler',
    displayName: 'Perler',
    assetPath: 'lib/core/palettes/perler.json',
  ),
  PaletteMeta(
    id: 'hama',
    displayName: 'Hama',
    assetPath: 'lib/core/palettes/hama.json',
  ),
];

PaletteMeta? paletteMetaById(String id) {
  for (final m in kPaletteMetas) {
    if (m.id == id) return m;
  }
  return null;
}

/// 从 JSON 字符串构建色卡。
Palette paletteFromJson(String id, String displayName, String json) =>
    Palette.fromJsonString(id, displayName, json);

/// 从文件系统加载色卡（测试 / 桌面调试用）。
Future<Palette> loadPaletteFromFile(PaletteMeta meta) async {
  final json = await File(meta.assetPath).readAsString();
  return paletteFromJson(meta.id, meta.displayName, json);
}

/// 从任意 JSON 字符串加载。
Palette loadPaletteFromString(PaletteMeta meta, String json) =>
    paletteFromJson(meta.id, meta.displayName, json);
