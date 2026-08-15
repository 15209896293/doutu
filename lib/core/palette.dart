/// 色卡模型与加载。
///
/// 色卡 JSON 结构（assets，从 MIT 许可的开源数据整理，见 tools/ 生成脚本）：
/// [{"code": "A01", "hex": "#FAF4C8", "rgb": [250, 244, 200]}, ...]
///
/// Perler 额外含 "productCode" 与 "name" 字段。
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

  PaletteEntry({
    required this.code,
    required this.hex,
    required this.r,
    required this.g,
    required this.b,
    this.productCode,
    this.name,
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
  final List<PaletteEntry> entries;

  Palette({
    required this.id,
    required this.displayName,
    required this.entries,
  });

  int get length => entries.length;

  PaletteEntry operator [](int i) => entries[i];

  /// 从 JSON 字符串解析色卡。
  factory Palette.fromJsonString(
    String id,
    String displayName,
    String jsonString,
  ) {
    final list = jsonDecode(jsonString) as List<dynamic>;
    return Palette(
      id: id,
      displayName: displayName,
      entries: list
          .map((e) => PaletteEntry.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
