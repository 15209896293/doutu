/// 色卡模型与加载。
///
/// 色卡 JSON 结构（assets，从 MIT 许可的开源数据整理，见 tools/ 生成脚本）：
/// [{"code": "A01", "hex": "#FAF4C8", "rgb": [250, 244, 200],
///   "source": "官方/实测", "version": "2024-06"}, ...]
///
/// Perler 额外含 "productCode" 与 "name" 字段。
/// source/version 为可选字段（用于色差信任标注）；缺省回落到色卡级元信息。
library;

import 'dart:convert';

import 'color_space.dart';

/// 单个色号条目。
class PaletteEntry {
  final String code;
  final String hex;
  final int r;
  final int g;
  final int b;

  /// 可选：官方产品码（Perler 的 80-XXXXX）。
  final String? productCode;

  /// 可选：颜色名。
  final String? name;

  /// 可选：该色号数据来源（"官方" / "实测" / "社区整理"）。
  final String? source;

  /// 可选：数据版本。
  final String? version;

  PaletteEntry({
    required this.code,
    required this.hex,
    required this.r,
    required this.g,
    required this.b,
    this.productCode,
    this.name,
    this.source,
    this.version,
  });

  LabColor get lab => rgbToLab(r, g, b);

  factory PaletteEntry.fromJson(Map<String, dynamic> json) {
    final rgb = (json['rgb'] as List<dynamic>).cast<int>();
    return PaletteEntry(
      code: json['code'] as String,
      hex: json['hex'] as String,
      r: rgb[0],
      g: rgb[1],
      b: rgb[2],
      productCode: json['productCode'] as String?,
      name: json['name'] as String?,
      source: json['source'] as String?,
      version: json['version'] as String?,
    );
  }

  @override
  String toString() => 'PaletteEntry($code $hex)';
}

/// 色卡。
class Palette {
  final String id;

  /// 显示名，如 "MARD 221"。
  final String displayName;

  /// 数据来源（用于色差信任标注，如 "MARD 官方色卡整理"）。
  final String? source;

  /// 数据版本。
  final String? version;

  final List<PaletteEntry> entries;

  Palette({
    required this.id,
    required this.displayName,
    required this.entries,
    this.source,
    this.version,
  });

  int get length => entries.length;

  PaletteEntry operator [](int i) => entries[i];

  /// 从 JSON 字符串解析色卡。
  factory Palette.fromJsonString(
    String id,
    String displayName,
    String jsonString, {
    String? source,
    String? version,
  }) {
    final list = jsonDecode(jsonString) as List<dynamic>;
    return Palette(
      id: id,
      displayName: displayName,
      source: source,
      version: version,
      entries: list
          .map((e) => PaletteEntry.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
