/// 作品项目：一次"选图→转换→编辑"的完整记录。
library;

import '../core/color_mapper.dart';
import '../core/palette_selector.dart';
import '../core/pattern_converter.dart';
import '../core/sampler.dart';
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
        if (o.gridHeight != null) 'gridHeight': o.gridHeight,
        'maxColors': o.maxColors,
        'dither': o.dither,
        'removeBackground': o.removeBackground,
        'minBlockSize': o.minBlockSize,
        'prefilterSmooth': o.prefilterSmooth,
        'prefilterEnhance': o.prefilterEnhance,
        'prefilterSharpen': o.prefilterSharpen,
        'minRegionSize': o.minRegionSize,
        if (o.maskShape != null) 'maskShape': o.maskShape,
        'colorDistanceMode': o.colorDistanceMode.name,
        'cellSamplingMode': o.cellSamplingMode.name,
        if (o.colorBucketBits != null) 'colorBucketBits': o.colorBucketBits,
        'outlineWeight': o.outlineWeight,
        'backgroundSeedDeltaE': o.backgroundSeedDeltaE,
        'backgroundFillDeltaE': o.backgroundFillDeltaE,
        'backgroundMinimumConfidence': o.backgroundMinimumConfidence,
        'minimumForegroundCoverage': o.minimumForegroundCoverage,
        'cleanupMinimumNeighbors': o.cleanupMinimumNeighbors,
        'spatialRegularizationIterations':
            o.spatialRegularizationIterations,
        'spatialSmoothness': o.spatialSmoothness,
        'spatialEdgeSigma': o.spatialEdgeSigma,
        'paletteSelectionMode': o.paletteSelectionMode.name,
      };

  static ConvertOptions optionsFrom(Map<String, dynamic> p) => ConvertOptions(
        gridSize: p['gridSize'] as int,
        gridHeight: p['gridHeight'] as int?,
        maxColors: p['maxColors'] as int? ?? 0,
        dither: p['dither'] as bool? ?? false,
        removeBackground: p['removeBackground'] as bool? ?? true,
        minBlockSize: p['minBlockSize'] as int? ?? 2,
        prefilterSmooth: p['prefilterSmooth'] as bool? ?? false,
        prefilterEnhance: p['prefilterEnhance'] as bool? ?? false,
        prefilterSharpen: p['prefilterSharpen'] as bool? ?? false,
        minRegionSize: p['minRegionSize'] as int? ?? 3,
        maskShape: p['maskShape'] as String?,
        colorDistanceMode: ColorDistance.values.firstWhere(
          (v) => v.name == p['colorDistanceMode'],
          orElse: () => ColorDistance.oklab,
        ),
        cellSamplingMode: CellSamplingMode.values.firstWhere(
          (v) => v.name == p['cellSamplingMode'],
          orElse: () => CellSamplingMode.dominantBucket,
        ),
        colorBucketBits: p['colorBucketBits'] as int?,
        outlineWeight: (p['outlineWeight'] as num?)?.toDouble() ?? 2.5,
        backgroundSeedDeltaE:
            (p['backgroundSeedDeltaE'] as num?)?.toDouble() ?? 8,
        backgroundFillDeltaE:
            (p['backgroundFillDeltaE'] as num?)?.toDouble() ?? 14,
        backgroundMinimumConfidence:
            (p['backgroundMinimumConfidence'] as num?)?.toDouble() ?? 0.85,
        minimumForegroundCoverage:
            (p['minimumForegroundCoverage'] as num?)?.toDouble() ?? 0.15,
        cleanupMinimumNeighbors: p['cleanupMinimumNeighbors'] as int? ?? 5,
        spatialRegularizationIterations:
            p['spatialRegularizationIterations'] as int? ?? 2,
        spatialSmoothness: (p['spatialSmoothness'] as num?)?.toDouble() ?? 2,
        spatialEdgeSigma: (p['spatialEdgeSigma'] as num?)?.toDouble() ?? 10,
        paletteSelectionMode: PaletteSelectionMode.values.firstWhere(
          (v) => v.name == p['paletteSelectionMode'],
          orElse: () => PaletteSelectionMode.fixedGreedy,
        ),
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
