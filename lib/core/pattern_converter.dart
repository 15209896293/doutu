/// 图片 → 拼豆图纸 主转换管线。
///
/// 链路：解码 → 网格区域采样 → CIEDE2000 色卡映射 → 后处理
///       （杂色合并 + 背景移除）→ 色数削减 → Pattern + BOM。
///
/// 依赖 image 包解码，其余全部纯 Dart。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/board_preset.dart';
import '../models/pattern.dart';
import 'color_mapper.dart';
import 'color_reducer.dart';
import 'color_space.dart';
import 'palette.dart';
import 'post_processor.dart';
import 'sampler.dart';

/// 转换参数。
class ConvertOptions {
  /// 网格边长。
  final int gridSize;

  /// 色数上限（0 = 不限制）。
  final int maxColors;

  /// 是否启用抖动。当前版本抖动在采样后对主色做 ±step 扰动，
  /// 以保留渐变过渡（照片类图片更自然）。
  final bool dither;

  /// 是否移除背景。
  final bool removeBackground;

  /// 杂色合并阈值：面积 < 该值的连通块并入相邻主色。
  final int minBlockSize;

  /// 板型形状（可选）：'circle' 时应用圆形掩码，圆外格子记为透明。
  final String? maskShape;

  /// 允许参与映射的色号下标（按库存过滤）；null = 全部。
  final List<int>? allowedIndices;

  /// 是否只用手头有的豆子（UI 开关，生成时据此计算 allowedIndices）。
  final bool restrictToOwned;

  const ConvertOptions({
    required this.gridSize,
    this.maxColors = 0,
    this.dither = true,
    this.removeBackground = true,
    this.minBlockSize = 2,
    this.maskShape,
    this.allowedIndices,
    this.restrictToOwned = false,
  });

  ConvertOptions copyWith({
    int? gridSize,
    int? maxColors,
    bool? dither,
    bool? removeBackground,
    int? minBlockSize,
    String? maskShape,
    List<int>? allowedIndices,
    bool? restrictToOwned,
  }) {
    return ConvertOptions(
      gridSize: gridSize ?? this.gridSize,
      maxColors: maxColors ?? this.maxColors,
      dither: dither ?? this.dither,
      removeBackground: removeBackground ?? this.removeBackground,
      minBlockSize: minBlockSize ?? this.minBlockSize,
      maskShape: maskShape ?? this.maskShape,
      allowedIndices: allowedIndices ?? this.allowedIndices,
      restrictToOwned: restrictToOwned ?? this.restrictToOwned,
    );
  }
}

/// 转换结果。
class ConvertResult {
  final Pattern pattern;

  /// 每个格子的区域平均色（0xRRGGBB），用于"原图对比"视图。
  final List<int> avgColors;

  ConvertResult({required this.pattern, required this.avgColors});
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
    final mapper = ColorMapper(palette, allowedIndices: options.allowedIndices);
    // 防御：极端尺寸先降采样到安全上限，避免解码/内存溢出。
    // 正常流程由「选图预检」把守，这里仅兜底（如绕过预检的分享图）。
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

    // ① 网格化采样：区域平均色作为映射源（比单点/众数更保真、少糊细节）。
    final sampled = sampleDominantColors(
      src,
      SamplerOptions(gridSize: options.gridSize),
    );

    final n = options.gridSize;
    final grid = List<int>.filled(n * n, 0);

    // 映射源：区域平均色 → Lab 工作缓冲。
    final labBuffer = <LabColor>[
      for (final c in sampled.avgColors)
        rgbToLab((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF),
    ];

    // ② 色卡映射（CIEDE2000）；dither 时用 Floyd–Steinberg 误差扩散，
    //    在 Lab 空间传播量化误差，显著减轻渐变断层、提升整体色准。
    if (options.dither) {
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final i = y * n + x;
          final idx = mapper.nearestIndex(labBuffer[i]);
          grid[i] = idx;
          final chosen = mapper.labs[idx];
          _diffuseError(
            labBuffer,
            n,
            x,
            y,
            labBuffer[i].l - chosen.l,
            labBuffer[i].a - chosen.a,
            labBuffer[i].b - chosen.b,
          );
        }
      }
    } else {
      for (var i = 0; i < n * n; i++) {
        grid[i] = mapper.nearestIndex(labBuffer[i]);
      }
    }

    // ③ 后处理：杂色合并 + 背景移除。
    //    抖动开启时保留细颗粒（关闭杂色合并），否则抖动细节会被抹掉。
    final processed = postProcess(
      grid,
      n,
      PostProcessOptions(
        minBlockSize: options.dither ? 1 : options.minBlockSize,
        removeBackground: options.removeBackground,
      ),
      labs: mapper.labs,
    );

    var finalGrid = processed.grid;

    // ④ 板型掩码（圆形板：圆外格子透明）
    if (options.maskShape == 'circle') {
      finalGrid = _applyCircleMask(finalGrid, n);
    }

    // ⑤ 色数上限削减
    if (options.maxColors > 0) {
      final reduced = reduceColorCount(finalGrid, mapper.labs, options.maxColors);
      finalGrid = reduced.grid;
    }

    // ⑥ BOM 统计
    final bom = _buildBom(finalGrid, palette);

    return ConvertResult(
      pattern: Pattern(
        size: n,
        grid: finalGrid,
        paletteId: palette.id,
        bom: bom,
      ),
      avgColors: sampled.avgColors,
    );
  }

  /// Floyd–Steinberg 误差扩散：把当前格的量化误差按标准权重扩散到
  /// 右侧/下侧邻居（Lab 空间，感知更均匀）。
  static void _diffuseError(
    List<LabColor> buf,
    int n,
    int x,
    int y,
    double el,
    double ea,
    double eb,
  ) {
    void add(int nx, int ny, double w) {
      if (nx < 0 || ny < 0 || nx >= n || ny >= n) return;
      final i = ny * n + nx;
      buf[i] = LabColor(
        (buf[i].l + el * w).clamp(0.0, 100.0).toDouble(),
        (buf[i].a + ea * w).clamp(-128.0, 127.0).toDouble(),
        (buf[i].b + eb * w).clamp(-128.0, 127.0).toDouble(),
      );
    }

    add(x + 1, y, 7 / 16);
    add(x - 1, y + 1, 3 / 16);
    add(x, y + 1, 5 / 16);
    add(x + 1, y + 1, 1 / 16);
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
