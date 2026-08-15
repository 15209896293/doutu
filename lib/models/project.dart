/// 作品项目：一次"选图→转换→编辑"的完整记录。
library;

import '../core/pattern_converter.dart';
import 'pattern.dart';

/// 项目状态。
class Project {
  final String id;

  /// 作品名（可编辑）。
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 转换参数（用于"重新生成"）。
  final Map<String, dynamic> convertParams;

  /// 图纸数据。
  final Pattern pattern;

  Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.convertParams,
    required this.pattern,
  });

  Project copyWith({
    String? name,
    Pattern? pattern,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      convertParams: convertParams,
      pattern: pattern ?? this.pattern,
    );
  }

  /// 从 ConvertOptions 提取参数。
  static Map<String, dynamic> paramsFrom(ConvertOptions o) => {
        'gridSize': o.gridSize,
        'maxColors': o.maxColors,
        'dither': o.dither,
        'removeBackground': o.removeBackground,
        'minBlockSize': o.minBlockSize,
        if (o.maskShape != null) 'maskShape': o.maskShape,
      };

  static ConvertOptions optionsFrom(Map<String, dynamic> p) => ConvertOptions(
        gridSize: p['gridSize'] as int,
        maxColors: p['maxColors'] as int? ?? 0,
        dither: p['dither'] as bool? ?? false,
        removeBackground: p['removeBackground'] as bool? ?? true,
        minBlockSize: p['minBlockSize'] as int? ?? 2,
        maskShape: p['maskShape'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'convertParams': convertParams,
        'pattern': pattern.toJson(),
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        convertParams:
            (json['convertParams'] as Map<String, dynamic>?) ?? const {},
        pattern:
            Pattern.fromJson(json['pattern'] as Map<String, dynamic>),
      );
}
