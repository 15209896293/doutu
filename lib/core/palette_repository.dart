/// 色卡仓库：加载内置色卡 JSON（assets）。
library;

import 'palette.dart';

/// 内置色卡元信息。
class PaletteMeta {
  final String id;
  final String displayName;
  final String assetPath;

  /// 数据来源（色差信任标注）。
  final String source;

  /// 数据版本。
  final String version;

  const PaletteMeta({
    required this.id,
    required this.displayName,
    required this.assetPath,
    required this.source,
    required this.version,
  });
}

/// 内置色卡清单（默认 MARD 221）。
/// 来源说明：
/// - MARD：pindou-color-data 国内核对版 mard-221-alfonse-doudou
///   （Alfonse + 豆豆工坊，宣称 MARD 官方，市场评级 S），MIT。
/// - Perler / Hama：官方产品色号 + maxcleme/beadcolors 社区实测 RGB（MIT）。
const kPaletteMetas = <PaletteMeta>[
  PaletteMeta(
    id: 'mard_221',
    displayName: 'MARD 221',
    assetPath: 'lib/core/palettes/mard_221.json',
    source: 'MARD 国内核对版（Alfonse + 豆豆工坊）',
    version: '2026-05',
  ),
  PaletteMeta(
    id: 'mard_291',
    displayName: 'MARD 291',
    assetPath: 'lib/core/palettes/mard_291.json',
    source: 'MARD 国内核对版（221）+ 扩展色',
    version: '2026-05',
  ),
  PaletteMeta(
    id: 'perler',
    displayName: 'Perler',
    assetPath: 'lib/core/palettes/perler.json',
    source: 'Perler 官方产品色 + 社区实测',
    version: '2024',
  ),
  PaletteMeta(
    id: 'hama',
    displayName: 'Hama',
    assetPath: 'lib/core/palettes/hama.json',
    source: 'Hama 官方产品色 + 社区实测',
    version: '2024',
  ),
];

PaletteMeta? paletteMetaById(String id) {
  for (final m in kPaletteMetas) {
    if (m.id == id) return m;
  }
  return null;
}

/// 从 JSON 字符串构建色卡。
Palette paletteFromJson(String id, String displayName, String json,
        {String? source, String? version}) =>
    Palette.fromJsonString(id, displayName, json,
        source: source, version: version);

/// 从任意 JSON 字符串加载。
Palette loadPaletteFromString(PaletteMeta meta, String json) =>
    paletteFromJson(meta.id, meta.displayName, json,
        source: meta.source, version: meta.version);
