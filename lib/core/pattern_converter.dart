/// 图片 → 拼豆图纸 主转换管线（v0.8 定稿）。
///
/// 链路：解码 → 分析图降采样 → ①背景检测(像素级双阈值，映射前)
///       → ②每格 dominant-bucket 采样(覆盖度+轮廓检测)
///       → ③选色(贪心最大覆盖 / 聚类吸附) → ④色卡映射(OKLab/CIEDE2000+红色防御)
///       → ⑤抖动(跳过背景/轮廓) → ⑥空间正则化(边缘保护) → ⑦多数表决清理
///       → ⑧板型掩码 → BOM + 诊断数据。
///
/// 依赖 image 包解码，其余全部纯 Dart。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/board_preset.dart';
import '../models/pattern.dart';
import 'background_remover.dart';
import 'beads/pixelbeads_adapter.dart';
import 'color_mapper.dart';
import 'palette.dart';
import 'palette_selector.dart';
import 'post_processor.dart';
import 'sampler.dart';

/// 转换参数（默认 = 标准预设）。
class ConvertOptions {
  /// 使用 pixel-beads 1:1 移植引擎（默认 true，完全复刻原站行为）。
  final bool pixelbeadsEngine;

  /// 预设 id（simplified/standard/detailed/smooth；pixelbeads 引擎映射到原站预设）。
  final String presetId;

  /// 网格宽度（N）。
  final int gridSize;

  /// 网格高度：null = 正方形（== gridSize）；0 = 按原图宽高比自动（pixel-beads
  /// 模式：宽度固定、高度自动、单边 ≤256）；>0 = 显式高度。
  /// 注：pixelbeads 引擎下始终按原图比例（原站 Mo()），该字段用于经典引擎。
  final int? gridHeight;

  /// 输入预滤波：转换前对分析图做保边平滑去噪（照片更干净、色块更净）。
  final bool prefilterSmooth;

  /// 输入增强：在去噪基础上适度提升对比度与饱和度（颜色更鲜明）。
  final bool prefilterEnhance;

  /// 边缘锐化（unsharp mask）：提升边缘清晰度（卡通/描边图更锐利）。
  final bool prefilterSharpen;

  /// 小区域合并阈值：面积 ≤ 该值的连通域并入相邻主色（图纸更干净、利于手工）。
  /// 1 = 仅合并孤立单格；3 = 合并 ≤3 格小色块（pypindou 建议 2~4）。
  final int minRegionSize;

  /// 色数上限（0 = 不限制）。
  final int maxColors;

  /// 是否启用抖动（RGB 蛇形 Floyd–Steinberg，跳过背景/轮廓格）。
  final bool dither;

  /// 是否移除背景。
  final bool removeBackground;

  /// 兼容保留：杂色合并面积阈值（新管线用 cleanupMinimumNeighbors，此字段不再参与主流程）。
  final int minBlockSize;

  /// 板型形状（可选）：'circle' 时应用圆形掩码，圆外格子记为透明。
  final String? maskShape;

  /// 允许参与映射的色号下标（按库存过滤）；null = 全部。
  final List<int>? allowedIndices;

  /// 是否只用手头有的豆子（UI 开关，生成时据此计算 allowedIndices）。
  final bool restrictToOwned;

  /// 色差距离模式（默认 OKLab）。
  final ColorDistance colorDistanceMode;

  /// 每格采样模式（默认 dominant-bucket 众数桶）。
  final CellSamplingMode cellSamplingMode;

  /// 众数桶量化位（null = 4，标准档）。
  final int? colorBucketBits;

  /// 轮廓检测：暗像素亮度阈值（0~1）。
  final double outlineDarkLuminance;

  /// 轮廓检测：暗像素占比阈值。
  final double outlineDarkRatio;

  /// 轮廓检测：亮度跨度阈值（对比度）。
  final double outlineContrast;

  /// 轮廓权重（选色聚合时轮廓格的覆盖度乘数）。
  final double outlineWeight;

  /// 背景种子判定阈值（ΔE，紧）。
  final double backgroundSeedDeltaE;

  /// 背景 flood-fill 传播阈值（ΔE，松）。
  final double backgroundFillDeltaE;

  /// 背景置信度门槛（0~1）。
  final double backgroundMinimumConfidence;

  /// 前景覆盖度门槛：低于该值的格子记背景（0~1）。
  final double minimumForegroundCoverage;

  /// 多数表决清理：8 邻域同色数 ≥ 该值才替换（0 = 关闭）。
  final int cleanupMinimumNeighbors;

  /// 空间正则化迭代次数（0 = 关闭）。
  final int spatialRegularizationIterations;

  /// 空间正则化平滑强度。
  final double spatialSmoothness;

  /// 空间正则化边缘保护 sigma。
  final double spatialEdgeSigma;

  /// 红色主导防御。
  final bool redDefense;

  /// 选色策略。
  final PaletteSelectionMode paletteSelectionMode;

  const ConvertOptions({
    required this.gridSize,
    this.pixelbeadsEngine = true,
    this.presetId = 'standard',
    this.gridHeight,
    this.maxColors = 0,
    this.dither = false,
    this.removeBackground = true,
    this.minBlockSize = 2,
    this.prefilterSmooth = false,
    this.prefilterEnhance = false,
    this.prefilterSharpen = false,
    this.minRegionSize = 3,
    this.maskShape,
    this.allowedIndices,
    this.restrictToOwned = false,
    this.colorDistanceMode = ColorDistance.oklab,
    this.cellSamplingMode = CellSamplingMode.dominantBucket,
    this.colorBucketBits,
    this.outlineDarkLuminance = 0.32,
    this.outlineDarkRatio = 0.20,
    this.outlineContrast = 0.16,
    this.outlineWeight = 2.5,
    this.backgroundSeedDeltaE = 8.0,
    this.backgroundFillDeltaE = 14.0,
    this.backgroundMinimumConfidence = 0.85,
    this.minimumForegroundCoverage = 0.15,
    this.cleanupMinimumNeighbors = 4,
    this.spatialRegularizationIterations = 2,
    this.spatialSmoothness = 2.0,
    this.spatialEdgeSigma = 10.0,
    this.redDefense = true,
    this.paletteSelectionMode = PaletteSelectionMode.fixedGreedy,
  });

  ConvertOptions copyWith({
    int? gridSize,
    bool? pixelbeadsEngine,
    String? presetId,
    int? gridHeight,
    int? maxColors,
    bool? dither,
    bool? removeBackground,
    int? minBlockSize,
    bool? prefilterSmooth,
    bool? prefilterEnhance,
    bool? prefilterSharpen,
    int? minRegionSize,
    String? maskShape,
    List<int>? allowedIndices,
    bool? restrictToOwned,
    ColorDistance? colorDistanceMode,
    CellSamplingMode? cellSamplingMode,
    int? colorBucketBits,
    double? outlineDarkLuminance,
    double? outlineDarkRatio,
    double? outlineContrast,
    double? outlineWeight,
    double? backgroundSeedDeltaE,
    double? backgroundFillDeltaE,
    double? backgroundMinimumConfidence,
    double? minimumForegroundCoverage,
    int? cleanupMinimumNeighbors,
    int? spatialRegularizationIterations,
    double? spatialSmoothness,
    double? spatialEdgeSigma,
    bool? redDefense,
    PaletteSelectionMode? paletteSelectionMode,
    bool clearGridHeight = false,
  }) {
    return ConvertOptions(
      gridSize: gridSize ?? this.gridSize,
      pixelbeadsEngine: pixelbeadsEngine ?? this.pixelbeadsEngine,
      presetId: presetId ?? this.presetId,
      gridHeight: clearGridHeight ? null : (gridHeight ?? this.gridHeight),
      maxColors: maxColors ?? this.maxColors,
      dither: dither ?? this.dither,
      removeBackground: removeBackground ?? this.removeBackground,
      minBlockSize: minBlockSize ?? this.minBlockSize,
      prefilterSmooth: prefilterSmooth ?? this.prefilterSmooth,
      prefilterEnhance: prefilterEnhance ?? this.prefilterEnhance,
      prefilterSharpen: prefilterSharpen ?? this.prefilterSharpen,
      minRegionSize: minRegionSize ?? this.minRegionSize,
      maskShape: maskShape ?? this.maskShape,
      allowedIndices: allowedIndices ?? this.allowedIndices,
      restrictToOwned: restrictToOwned ?? this.restrictToOwned,
      colorDistanceMode: colorDistanceMode ?? this.colorDistanceMode,
      cellSamplingMode: cellSamplingMode ?? this.cellSamplingMode,
      colorBucketBits: colorBucketBits ?? this.colorBucketBits,
      outlineDarkLuminance: outlineDarkLuminance ?? this.outlineDarkLuminance,
      outlineDarkRatio: outlineDarkRatio ?? this.outlineDarkRatio,
      outlineContrast: outlineContrast ?? this.outlineContrast,
      outlineWeight: outlineWeight ?? this.outlineWeight,
      backgroundSeedDeltaE: backgroundSeedDeltaE ?? this.backgroundSeedDeltaE,
      backgroundFillDeltaE: backgroundFillDeltaE ?? this.backgroundFillDeltaE,
      backgroundMinimumConfidence:
          backgroundMinimumConfidence ?? this.backgroundMinimumConfidence,
      minimumForegroundCoverage:
          minimumForegroundCoverage ?? this.minimumForegroundCoverage,
      cleanupMinimumNeighbors:
          cleanupMinimumNeighbors ?? this.cleanupMinimumNeighbors,
      spatialRegularizationIterations: spatialRegularizationIterations ??
          this.spatialRegularizationIterations,
      spatialSmoothness: spatialSmoothness ?? this.spatialSmoothness,
      spatialEdgeSigma: spatialEdgeSigma ?? this.spatialEdgeSigma,
      redDefense: redDefense ?? this.redDefense,
      paletteSelectionMode: paletteSelectionMode ?? this.paletteSelectionMode,
    );
  }
}

/// 转换诊断数据（供 UI 展示，对齐 pixel-beads 的 diagnostics）。
class ConvertDiagnostics {
  /// 是否检测并移除了背景。
  final bool backgroundDetected;

  /// 背景置信度（0~1）。
  final double backgroundConfidence;

  /// 平均映射色差（按覆盖度加权）。
  final double meanMappingDistance;

  /// 使用色号数。
  final int usedColorCount;

  /// 稀有色数（用量 ≤ 2 的色号）。
  final int rareColorCount;

  /// 孤立单格连通域数。
  final int singleCellRegionCount;

  /// 空间正则化变更格数。
  final int spatialChangedCells;

  /// 清理变更格数。
  final int cleanupChangedCells;

  /// 是否因背景检测过度触发兜底（去掉背景重采样，保留原图）。
  final bool backgroundFallback;

  const ConvertDiagnostics({
    required this.backgroundDetected,
    required this.backgroundConfidence,
    required this.meanMappingDistance,
    required this.usedColorCount,
    required this.rareColorCount,
    required this.singleCellRegionCount,
    required this.spatialChangedCells,
    required this.cleanupChangedCells,
    this.backgroundFallback = false,
  });
}

/// 转换结果。
class ConvertResult {
  final Pattern pattern;

  /// 每个格子的区域平均色（0xRRGGBB），用于"原图对比"视图。
  final List<int> avgColors;

  /// 每个格子是否为背景格（映射为透明），用于"背景蒙层"预览。
  final List<bool> backgroundCells;

  /// 诊断数据。
  final ConvertDiagnostics diagnostics;

  ConvertResult({
    required this.pattern,
    required this.avgColors,
    required this.backgroundCells,
    required this.diagnostics,
  });
}

/// 图片 → 图纸转换器（可跨 Isolate 传输：持有纯数据）。
class PatternConverter {
  final Palette palette;

  PatternConverter(this.palette);

  /// 从图片字节转换。
  ConvertResult convert(Uint8List imageBytes, ConvertOptions options) {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw const FormatException('无法解码图片（支持 JPG/PNG/HEIC）');
    }
    return convertImage(image, options);
  }

  /// 从已解码图片转换。
  ConvertResult convertImage(img.Image image, ConvertOptions options) {
    // pixel-beads 1:1 引擎（完全复刻原站行为）
    if (options.pixelbeadsEngine) {
      return convertWithPixelBeads(
        image,
        palette,
        targetWidth: options.gridSize,
        presetId: pixelBeadsPresetFor(options.presetId),
        maximumColors: options.maxColors == 0 ? null : options.maxColors,
        backgroundMode: options.removeBackground ? 'auto' : 'keep',
        maskShape: options.maskShape,
        allowedIndices: options.allowedIndices,
      );
    }

    // 网格宽高：gridHeight == null → 正方形；== 0 → 按原图比例自动；>0 → 显式
    var n = options.gridSize;
    final int m;
    if (options.gridHeight == null) {
      m = n;
    } else if (options.gridHeight == 0) {
      const maxSide = 256;
      var h = (n * image.height / image.width).round();
      if (h > maxSide) {
        // 高度封顶，宽度按比例回缩（pixel-beads 同款逻辑）
        n = (n * maxSide / h).round().clamp(10, maxSide);
        h = maxSide;
      }
      m = h.clamp(10, maxSide);
    } else {
      m = options.gridHeight!;
    }

    // 防御：极端尺寸先降采样到安全上限，避免解码/内存溢出。
    var src = image;
    const maxSide = 4096;
    if (image.width > maxSide || image.height > maxSide) {
      final scale = math.min(maxSide / image.width, maxSide / image.height);
      src = img.copyResize(
        image,
        width: math.max(1, (image.width * scale).round()),
        height: math.max(1, (image.height * scale).round()),
        interpolation: img.Interpolation.linear,
      );
    }

    // ① 分析图：单边 = clamp(网格长边*4, 64, 1024)（每格约 4 个分析像素，参考 pixel-beads）。
    final analysis0 = _analysisImage(src, n, m);

    // ①′ 输入预滤波：保边平滑去噪 / 对比度饱和度增强 / 边缘锐化（unsharp）
    var analysis = analysis0;
    if (options.prefilterSmooth || options.prefilterEnhance || options.prefilterSharpen) {
      if (options.prefilterSmooth) {
        analysis = img.smooth(analysis, weight: 3);
      }
      if (options.prefilterEnhance) {
        analysis = img.adjustColor(
          analysis,
          contrast: 1.08,
          saturation: 1.05,
        );
      }
      if (options.prefilterSharpen) {
        analysis = _unsharpMask(analysis, amount: 0.45);
      }
    }

    final mapper = ColorMapper(
      palette,
      distance: options.colorDistanceMode,
      allowedIndices: options.allowedIndices,
      redDefense: options.redDefense,
    );

    // ② 背景检测（像素级，映射前）
    var bg = options.removeBackground
        ? detectBackground(
            analysis,
            options: BackgroundOptions(
              seedDeltaE: options.backgroundSeedDeltaE,
              fillDeltaE: options.backgroundFillDeltaE,
              minimumConfidence: options.backgroundMinimumConfidence,
            ),
          )
        : BackgroundResult(
            mask: Uint8List(analysis.width * analysis.height),
            detected: false,
            confidence: 0,
          );

    // ③ 每格采样（dominant-bucket + 覆盖度 + 轮廓检测）
    final total = n * m;
    final samplerOpts = SamplerOptions(
      gridSize: n,
      gridHeight: m,
      cellSamplingMode: options.cellSamplingMode,
      colorBucketBits: options.colorBucketBits ?? 4,
      outlineDarkLuminance: options.outlineDarkLuminance,
      outlineDarkRatio: options.outlineDarkRatio,
      outlineContrast: options.outlineContrast,
      minimumForegroundCoverage: options.minimumForegroundCoverage,
    );
    var sampled = sampleDominantColors(
      analysis,
      samplerOpts,
      backgroundMask: bg.mask,
    );
    var cells = sampled.cells;
    var fgCount = cells.where((c) => c != null).length;

    // 兜底①：背景检测疑似吞掉主体（有效格过少）→ 去掉背景重新采样，绝不输出空白
    var backgroundFallback = false;
    if (options.removeBackground && fgCount / total < 0.05) {
      sampled = sampleDominantColors(analysis, samplerOpts, backgroundMask: null);
      cells = sampled.cells;
      fgCount = cells.where((c) => c != null).length;
      bg = BackgroundResult(
        mask: Uint8List(analysis.width * analysis.height),
        detected: false,
        confidence: 0,
      );
      backgroundFallback = true;
    }

    // 兜底②：去掉背景后仍几乎无内容（图片本身空白/全透明）→ 友好报错
    if (fgCount == 0 || fgCount / total < 0.02) {
      throw const FormatException(
        '图片中可识别的内容太少（可能整张都是背景或透明）。'
        '请换一张主体清晰、背景简单的图片，或先在裁剪页框出主体。',
      );
    }

    final backgroundCells = List<bool>.generate(
      total,
      (i) => cells[i] == null,
      growable: false,
    );

    // ④ 选色 + 映射
    final selector = PaletteSelector(palette, mapper);
    final sel = selector.selectAndMap(
      cells,
      gridSize: n,
      maxColors: options.maxColors,
      outlineWeight: options.outlineWeight,
      mode: options.paletteSelectionMode,
      allowedIndices: options.allowedIndices,
    );
    var grid = sel.grid;

    // ⑤ 抖动（RGB 蛇形 FS，跳过背景/轮廓）
    if (options.dither) {
      grid = _ditherCells(
        cells,
        grid,
        n,
        m,
        palette,
        mapper,
        sel.selectedIndices,
        options.colorDistanceMode,
      );
    }

    // ⑥ 空间正则化（边缘保护）
    var spatialChanged = 0;
    if (options.spatialRegularizationIterations > 0) {
      final r = regularizeGrid(
        grid,
        cells,
        n,
        palette,
        height: m,
        iterations: options.spatialRegularizationIterations,
        smoothness: options.spatialSmoothness,
        edgeSigma: options.spatialEdgeSigma,
        distance: options.colorDistanceMode,
      );
      grid = r.grid;
      spatialChanged = r.changed;
    }

    // ⑦ 多数表决清理 + 孤立单格区域移除（保证无 <2 格孤立杂色）
    var cleanupChanged = 0;
    if (options.cleanupMinimumNeighbors > 0) {
      final before = grid;
      grid = cleanupByMajority(
        grid,
        cells,
        n,
        height: m,
        minNeighbors: options.cleanupMinimumNeighbors,
      );
      for (var i = 0; i < grid.length; i++) {
        if (grid[i] != before[i]) cleanupChanged++;
      }
    }
    if (options.cleanupMinimumNeighbors > 0) {
      final before = grid;
      grid = removeSingleCellRegions(grid, cells, n,
          height: m, minRegionSize: options.minRegionSize);
      for (var i = 0; i < grid.length; i++) {
        if (grid[i] != before[i]) cleanupChanged++;
      }
    }

    // ⑧ 板型掩码（仅正方形圆形板：圆外格子透明）
    if (options.maskShape == 'circle' && n == m) {
      grid = _applyCircleMask(grid, n);
    }

    // ⑨ BOM + 诊断
    final bom = _buildBom(grid, palette);
    final (rare, single) = _noiseDiagnostics(grid, n, m);

    return ConvertResult(
      pattern: Pattern(
        size: n,
        height: m,
        grid: grid,
        paletteId: palette.id,
        bom: bom,
      ),
      avgColors: sampled.avgColors,
      backgroundCells: backgroundCells,
      diagnostics: ConvertDiagnostics(
        backgroundDetected: bg.detected,
        backgroundConfidence: bg.confidence,
        meanMappingDistance: sel.meanMappingDistance,
        usedColorCount: bom.length,
        rareColorCount: rare,
        singleCellRegionCount: single,
        spatialChangedCells: spatialChanged,
        cleanupChangedCells: cleanupChanged,
        backgroundFallback: backgroundFallback,
      ),
    );
  }

  /// 分析图：保持宽高比缩放到长边 ≤ clamp(网格长边*4, 64, 1024)。
  static img.Image _analysisImage(img.Image src, int n, int m) {
    final target = (math.max(n, m) * 4).clamp(64, 1024);
    if (src.width <= target && src.height <= target) return src;
    final scale = math.min(target / src.width, target / src.height);
    return img.copyResize(
      src,
      width: math.max(1, (src.width * scale).round()),
      height: math.max(1, (src.height * scale).round()),
      interpolation: img.Interpolation.linear,
    );
  }

  /// Unsharp mask 边缘锐化：原图 + amount ×（原图 - 均值模糊）。
  static img.Image _unsharpMask(img.Image src, {double amount = 0.45}) {
    final blurred = img.smooth(src, weight: 1);
    final out = img.Image.from(src);
    for (final p in out) {
      final b = blurred.getPixel(p.x, p.y);
      p
        ..r = (p.r + amount * (p.r - b.r.toInt())).round().clamp(0, 255)
        ..g = (p.g + amount * (p.g - b.g.toInt())).round().clamp(0, 255)
        ..b = (p.b + amount * (p.b - b.b.toInt())).round().clamp(0, 255);
    }
    return out;
  }

  /// RGB 蛇形 Floyd–Steinberg 抖动（跳过背景格与轮廓格，误差 clamp 0~255）。
  static List<int> _ditherCells(
    List<SampleCell?> cells,
    List<int> grid,
    int n,
    int m,
    Palette palette,
    ColorMapper mapper,
    List<int> selected,
    ColorDistance distance,
  ) {
    if (selected.isEmpty) return grid;
    final buf = List<int?>.generate(cells.length, (i) => cells[i]?.rgb);
    final out = List<int>.of(grid);
    final paletteRgb = <int>[
      for (final e in palette.entries) (e.r << 16) | (e.g << 8) | e.b,
    ];

    int clampAdd(int v, double e) => (v + e).round().clamp(0, 255);

    for (var y = 0; y < m; y++) {
      final ltr = y.isEven;
      for (var k = 0; k < n; k++) {
        final x = ltr ? k : n - 1 - k;
        final i = y * n + x;
        final cell = cells[i];
        final cur = buf[i];
        if (cell == null || cell.isOutline || cur == null) continue;

        final idx = mapper.nearestAmongRgb(cur, selected,
            applyRedDefense: false);
        out[i] = idx;

        final target = paletteRgb[idx];
        final er = ((cur >> 16) & 0xFF) - ((target >> 16) & 0xFF);
        final eg = ((cur >> 8) & 0xFF) - ((target >> 8) & 0xFF);
        final eb = (cur & 0xFF) - (target & 0xFF);

        void diffuse(int nx, int ny, double w) {
          if (nx < 0 || ny < 0 || nx >= n || ny >= m) return;
          final ni = ny * n + nx;
          final nc = cells[ni];
          final nb = buf[ni];
          if (nc == null || nc.isOutline || nb == null) return;
          buf[ni] = (clampAdd((nb >> 16) & 0xFF, er * w) << 16) |
              (clampAdd((nb >> 8) & 0xFF, eg * w) << 8) |
              clampAdd(nb & 0xFF, eb * w);
        }

        if (ltr) {
          diffuse(x + 1, y, 7 / 16);
          diffuse(x - 1, y + 1, 3 / 16);
          diffuse(x, y + 1, 5 / 16);
          diffuse(x + 1, y + 1, 1 / 16);
        } else {
          diffuse(x - 1, y, 7 / 16);
          diffuse(x + 1, y + 1, 3 / 16);
          diffuse(x, y + 1, 5 / 16);
          diffuse(x - 1, y + 1, 1 / 16);
        }
      }
    }
    return out;
  }

  /// 圆形掩码：圆外格子设为透明（-1）。
  static List<int> _applyCircleMask(List<int> grid, int size) {
    final out = List<int>.of(grid);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (!BoardPreset.isInsideCircle(x, y, size)) {
          out[y * size + x] = -1;
        }
      }
    }
    return out;
  }

  /// 诊断：稀有色数（用量 ≤ 2）与孤立单格连通域数。
  static (int, int) _noiseDiagnostics(List<int> grid, int size, int height) {
    final usage = <int, int>{};
    for (final idx in grid) {
      if (idx < 0) continue;
      usage[idx] = (usage[idx] ?? 0) + 1;
    }
    final rare = usage.values.where((v) => v <= 2).length;

    // 连通域（四邻域），统计面积为 1 的块数
    final labels = List<int>.filled(grid.length, 0);
    var single = 0;
    var nextLabel = 1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        if (labels[i] != 0 || grid[i] < 0) continue;
        final color = grid[i];
        final queue = <int>[i];
        labels[i] = nextLabel;
        var head = 0;
        var count = 0;
        while (head < queue.length) {
          final cur = queue[head++];
          count++;
          final cx = cur % size;
          final cy = cur ~/ size;
          for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final nx = cx + dx;
            final ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= size || ny >= height) continue;
            final ni = ny * size + nx;
            if (labels[ni] == 0 && grid[ni] == color) {
              labels[ni] = nextLabel;
              queue.add(ni);
            }
          }
        }
        if (count == 1) single++;
        nextLabel++;
      }
    }
    return (rare, single);
  }

  List<BomEntry> _buildBom(List<int> grid, Palette palette) {
    final usage = <int, int>{};
    for (final idx in grid) {
      if (idx < 0) continue;
      usage[idx] = (usage[idx] ?? 0) + 1;
    }
    final entries = usage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in entries)
        BomEntry(
          code: palette.entries[e.key].code,
          count: e.value,
          color: (palette.entries[e.key].r << 16) |
              (palette.entries[e.key].g << 8) |
              palette.entries[e.key].b,
          productCode: palette.entries[e.key].productCode,
          name: palette.entries[e.key].name,
        ),
    ];
  }
}

/// 转换预设（对齐 pixel-beads「图案细节」四档；参数组见 v0.8 §1.3）。
class ConvertPresets {
  /// 精简：色数少、干净、适合纯色画/卡通。
  static ConvertOptions simplified({
    required int gridSize,
    String? maskShape,
    List<int>? allowedIndices,
  }) {
    return ConvertOptions(
      gridSize: gridSize,
      maskShape: maskShape,
      allowedIndices: allowedIndices,
      presetId: 'simplified',
      maxColors: 8,
      dither: false,
      removeBackground: true,
      colorDistanceMode: ColorDistance.oklab,
      cellSamplingMode: CellSamplingMode.dominantBucket,
      colorBucketBits: 4,
      outlineDarkLuminance: 0.34,
      outlineDarkRatio: 0.22,
      outlineContrast: 0.18,
      outlineWeight: 3.0,
      backgroundSeedDeltaE: 8,
      backgroundFillDeltaE: 13,
      backgroundMinimumConfidence: 0.85,
      minimumForegroundCoverage: 0.28,
      cleanupMinimumNeighbors: 4,
      spatialRegularizationIterations: 2,
      spatialSmoothness: 3.0,
      spatialEdgeSigma: 8.0,
      redDefense: true,
      paletteSelectionMode: PaletteSelectionMode.fixedGreedy,
    );
  }

  /// 标准（默认）：照片/卡通均衡（对齐 pixel-beads：限 10 色，干净大块、观感最佳）。
  static ConvertOptions standard({
    required int gridSize,
    String? maskShape,
    List<int>? allowedIndices,
  }) {
    return ConvertOptions(
      gridSize: gridSize,
      maskShape: maskShape,
      allowedIndices: allowedIndices,
      maxColors: 10,
      presetId: 'standard',
      dither: false,
      removeBackground: true,
      colorDistanceMode: ColorDistance.oklab,
      cellSamplingMode: CellSamplingMode.dominantBucket,
      colorBucketBits: 4,
      outlineDarkLuminance: 0.32,
      outlineDarkRatio: 0.20,
      outlineContrast: 0.16,
      outlineWeight: 2.5,
      backgroundSeedDeltaE: 8,
      backgroundFillDeltaE: 14,
      backgroundMinimumConfidence: 0.85,
      minimumForegroundCoverage: 0.15,
      cleanupMinimumNeighbors: 4,
      spatialRegularizationIterations: 2,
      spatialSmoothness: 2.0,
      spatialEdgeSigma: 10.0,
      redDefense: true,
      paletteSelectionMode: PaletteSelectionMode.fixedGreedy,
    );
  }

  /// 细腻：色差最准、细节最多（CIEDE2000 + 抖动）。
  static ConvertOptions detailed({
    required int gridSize,
    String? maskShape,
    List<int>? allowedIndices,
  }) {
    return ConvertOptions(
      gridSize: gridSize,
      maskShape: maskShape,
      allowedIndices: allowedIndices,
      maxColors: 16,
      presetId: 'detailed',
      dither: true,
      removeBackground: true,
      colorDistanceMode: ColorDistance.ciede2000,
      cellSamplingMode: CellSamplingMode.dominantBucket,
      colorBucketBits: 5,
      outlineDarkLuminance: 0.28,
      outlineDarkRatio: 0.30,
      outlineContrast: 0.22,
      outlineWeight: 1.5,
      backgroundSeedDeltaE: 8,
      backgroundFillDeltaE: 13,
      backgroundMinimumConfidence: 0.88,
      minimumForegroundCoverage: 0.12,
      cleanupMinimumNeighbors: 7,
      spatialRegularizationIterations: 1,
      spatialSmoothness: 1.0,
      spatialEdgeSigma: 12.0,
      redDefense: true,
      paletteSelectionMode: PaletteSelectionMode.fixedGreedy,
    );
  }

  /// 平滑自然：保留渐变过渡（平均采样 + 聚类吸附，无抖动）。
  static ConvertOptions smooth({
    required int gridSize,
    String? maskShape,
    List<int>? allowedIndices,
  }) {
    return ConvertOptions(
      gridSize: gridSize,
      maskShape: maskShape,
      allowedIndices: allowedIndices,
      maxColors: 0,
      dither: false,
      presetId: 'smooth',
      removeBackground: true,
      colorDistanceMode: ColorDistance.oklab,
      cellSamplingMode: CellSamplingMode.average,
      colorBucketBits: 4,
      outlineDarkLuminance: 0.32,
      outlineDarkRatio: 0.20,
      outlineContrast: 0.16,
      outlineWeight: 2.5,
      backgroundSeedDeltaE: 8,
      backgroundFillDeltaE: 14,
      backgroundMinimumConfidence: 0.85,
      minimumForegroundCoverage: 0.15,
      cleanupMinimumNeighbors: 0,
      spatialRegularizationIterations: 0,
      spatialSmoothness: 0,
      spatialEdgeSigma: 10,
      redDefense: true,
      minRegionSize: 1, // 平滑档保留渐变小细节
      paletteSelectionMode: PaletteSelectionMode.clusterSnap,
    );
  }

  /// 按 id 取预设（未知 id 回退标准）。
  static ConvertOptions fromId(
    String id, {
    required int gridSize,
    String? maskShape,
    List<int>? allowedIndices,
  }) {
    switch (id) {
      case 'simplified':
        return simplified(
            gridSize: gridSize,
            maskShape: maskShape,
            allowedIndices: allowedIndices);
      case 'detailed':
        return detailed(
            gridSize: gridSize,
            maskShape: maskShape,
            allowedIndices: allowedIndices);
      case 'smooth':
        return smooth(
            gridSize: gridSize,
            maskShape: maskShape,
            allowedIndices: allowedIndices);
      case 'standard':
      default:
        return standard(
            gridSize: gridSize,
            maskShape: maskShape,
            allowedIndices: allowedIndices);
    }
  }
}
