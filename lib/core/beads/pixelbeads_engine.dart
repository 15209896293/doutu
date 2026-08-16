/// pixel-beads.com 转换引擎 —— 1:1 忠实移植（纯 Dart）。
///
/// 来源：pixel-beads.com 前端 Web Worker（`processing.worker-*.js`），
/// 逐函数翻译，参数与原站预设完全一致（simplified/standard/detailed/legacy/zippland）。
/// 不掺入本项目自有的预滤波/多锚点等改动，保证行为对齐原站。
///
/// 输入：RGBA 像素 + 调色板（hex）+ 目标网格宽高；输出：色号矩阵 + 诊断。
library;

import 'dart:math' as math;
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// 基础色彩
// ---------------------------------------------------------------------------

/// sRGB → CIELAB（D65，与原站一致：白点 95.047/100/108.883）。
Lab _rgbToLab(int r, int g, int b) {
  double t(double v) {
    final s = v / 255;
    return s > 0.04045 ? math.pow((s + 0.055) / 1.055, 2.4).toDouble() : s / 12.92;
  }

  final rl = t(r.toDouble()) * 100, gl = t(g.toDouble()) * 100, bl = t(b.toDouble()) * 100;
  final x = rl * 0.4124 + gl * 0.3576 + bl * 0.1805;
  final y = rl * 0.2126 + gl * 0.7152 + bl * 0.0722;
  final z = rl * 0.0193 + gl * 0.1192 + bl * 0.9505;
  double f(double c) {
    final v = c / (c == x ? 95.047 : (c == y ? 100.0 : 108.883));
    return v > 0.008856 ? math.pow(v, 1 / 3).toDouble() : 7.787 * v + 16 / 116;
  }

  final fx = f(x), fy = f(y), fz = f(z);
  return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// OKLab（Björn Ottosson，原站 G()）。
Oklab _rgbToOklab(int r, int g, int b) {
  double lin(int c) {
    final v = c / 255;
    return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final rl = lin(r), gl = lin(g), bl = lin(b);
  final l = 0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl;
  final m = 0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl;
  final s = 0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl;
  final l3 = math.pow(l, 1 / 3).toDouble();
  final m3 = math.pow(m, 1 / 3).toDouble();
  final s3 = math.pow(s, 1 / 3).toDouble();
  return Oklab(
    0.2104542553 * l3 + 0.793617785 * m3 - 0.0040720468 * s3,
    1.9779984951 * l3 - 2.428592205 * m3 + 0.4505937099 * s3,
    0.0259040371 * l3 + 0.7827717662 * m3 - 0.808675766 * s3,
  );
}

class Lab {
  final double l, a, b;
  const Lab(this.l, this.a, this.b);
}

class Oklab {
  final double l, a, b;
  const Oklab(this.l, this.a, this.b);
}

double _labDist(Lab x, Lab y) {
  final dl = x.l - y.l, da = x.a - y.a, db = x.b - y.b;
  return math.sqrt(dl * dl + da * da + db * db);
}

double _oklabDist(Oklab x, Oklab y) {
  final dl = x.l - y.l, da = x.a - y.a, db = x.b - y.b;
  return math.sqrt(dl * dl + da * da + db * db) * 100;
}

double _deg(double r) => r * 180 / math.pi;
double _rad(double d) => d * math.pi / 180;

/// CIEDE2000（原站 Le()）。
double _ciede2000(Lab c1, Lab c2) {
  final l1 = c1.l, a1 = c1.a, b1 = c1.b;
  final l2 = c2.l, a2 = c2.a, b2 = c2.b;
  final c1ab = math.sqrt(a1 * a1 + b1 * b1);
  final c2ab = math.sqrt(a2 * a2 + b2 * b2);
  final cab = (c1ab + c2ab) / 2;
  final g = 0.5 *
      (1 - math.sqrt(math.pow(cab, 7) / (math.pow(cab, 7) + math.pow(25, 7))));
  final a1p = (1 + g) * a1;
  final a2p = (1 + g) * a2;
  final c1p = math.sqrt(a1p * a1p + b1 * b1);
  final c2p = math.sqrt(a2p * a2p + b2 * b2);
  double h1p = c1p == 0 ? 0 : _deg(math.atan2(b1, a1p));
  if (h1p < 0) h1p += 360;
  double h2p = c2p == 0 ? 0 : _deg(math.atan2(b2, a2p));
  if (h2p < 0) h2p += 360;
  final dlp = l2 - l1;
  final dcp = c2p - c1p;
  double dhp;
  if (c1p * c2p == 0) {
    dhp = 0;
  } else if ((h2p - h1p).abs() <= 180) {
    dhp = h2p - h1p;
  } else if (h2p - h1p > 180) {
    dhp = h2p - h1p - 360;
  } else {
    dhp = h2p - h1p + 360;
  }
  final dlhp = 2 * math.sqrt(c1p * c2p) * math.sin(_rad(dhp / 2));
  final lp = (l1 + l2) / 2;
  final cp = (c1p + c2p) / 2;
  double hpp;
  if (c1p * c2p == 0) {
    hpp = h1p + h2p;
  } else if ((h1p - h2p).abs() <= 180) {
    hpp = (h1p + h2p) / 2;
  } else if ((h1p - h2p).abs() > 180 && h1p + h2p < 360) {
    hpp = (h1p + h2p + 360) / 2;
  } else {
    hpp = (h1p + h2p - 360) / 2;
  }
  final tt = 1 -
      0.17 * math.cos(_rad(hpp - 30)) +
      0.24 * math.cos(_rad(2 * hpp)) +
      0.32 * math.cos(_rad(3 * hpp + 6)) -
      0.20 * math.cos(_rad(4 * hpp - 63));
  final dtheta = 30 * math.exp(-math.pow((hpp - 275) / 25, 2));
  final rc = 2 *
      math.sqrt(math.pow(cp, 7) / (math.pow(cp, 7) + math.pow(25, 7)));
  final sl = 1 +
      (0.015 * math.pow(lp - 50, 2)) /
          math.sqrt(20 + math.pow(lp - 50, 2));
  final sc = 1 + 0.045 * cp;
  final sh = 1 + 0.015 * cp * tt;
  final rt = -math.sin(_rad(2 * dtheta)) * rc;
  final dl = dlp / sl;
  final dc = dcp / sc;
  final dh = dlhp / sh;
  return math.sqrt(dl * dl + dc * dc + dh * dh + rt * dc * dh);
}

/// 模式距离（原站 B()）：'ciede2000' → CIEDE2000，否则 OKLab。
double _dist(String mode, int r1, int g1, int b1, int r2, int g2, int b2) {
  return mode == 'ciede2000'
      ? _ciede2000(_rgbToLab(r1, g1, b1), _rgbToLab(r2, g2, b2))
      : _oklabDist(_rgbToOklab(r1, g1, b1), _rgbToOklab(r2, g2, b2));
}

// ---------------------------------------------------------------------------
// 调色板条目
// ---------------------------------------------------------------------------

class BeadColor {
  final String id;
  final int r, g, b;
  const BeadColor(this.id, this.r, this.g, this.b);
}

// ---------------------------------------------------------------------------
// 预设（原站 he 表：zippland/simplified/standard/detailed/legacy）
// ---------------------------------------------------------------------------

class Preset {
  final String id;
  final int? maxColors;
  final int analysisPixelsPerCell;
  final double minimumForegroundCoverage;
  final double outlineDarkLuminance;
  final double outlineDarkRatio;
  final double outlineContrast;
  final double outlineWeight;
  final double backgroundSeedDeltaE;
  final double backgroundFillDeltaE;
  final double backgroundMinimumConfidence;
  final int? cleanupMinimumNeighbors;
  final String cellSamplingMode;
  final int? colorBucketBits;
  final String paletteSelectionMode;
  final String colorDistanceMode;
  final String ditheringMode;
  final int spatialRegularizationIterations;
  final double spatialSmoothness;
  final double spatialEdgeSigma;

  const Preset({
    required this.id,
    this.maxColors,
    required this.analysisPixelsPerCell,
    required this.minimumForegroundCoverage,
    required this.outlineDarkLuminance,
    required this.outlineDarkRatio,
    required this.outlineContrast,
    required this.outlineWeight,
    required this.backgroundSeedDeltaE,
    required this.backgroundFillDeltaE,
    required this.backgroundMinimumConfidence,
    required this.cleanupMinimumNeighbors,
    required this.cellSamplingMode,
    required this.colorBucketBits,
    required this.paletteSelectionMode,
    required this.colorDistanceMode,
    required this.ditheringMode,
    required this.spatialRegularizationIterations,
    required this.spatialSmoothness,
    required this.spatialEdgeSigma,
  });
}

/// 原站预设参数（he 表逐字）。
const kPixelBeadsPresets = <String, Preset>{
  'simplified': Preset(
    id: 'simplified',
    maxColors: 8,
    analysisPixelsPerCell: 4,
    minimumForegroundCoverage: .28,
    outlineDarkLuminance: .34,
    outlineDarkRatio: .22,
    outlineContrast: .18,
    outlineWeight: 3,
    backgroundSeedDeltaE: 8,
    backgroundFillDeltaE: 13,
    backgroundMinimumConfidence: .85,
    cleanupMinimumNeighbors: 4,
    cellSamplingMode: 'dominant-bucket',
    colorBucketBits: 4,
    paletteSelectionMode: 'fixed-palette-greedy',
    colorDistanceMode: 'oklab',
    ditheringMode: 'none',
    spatialRegularizationIterations: 2,
    spatialSmoothness: 3,
    spatialEdgeSigma: 8,
  ),
  'standard': Preset(
    id: 'standard',
    maxColors: 10,
    analysisPixelsPerCell: 4,
    minimumForegroundCoverage: .2,
    outlineDarkLuminance: .32,
    outlineDarkRatio: .2,
    outlineContrast: .16,
    outlineWeight: 2.5,
    backgroundSeedDeltaE: 8,
    backgroundFillDeltaE: 14,
    backgroundMinimumConfidence: .85,
    cleanupMinimumNeighbors: 5,
    cellSamplingMode: 'dominant-bucket',
    colorBucketBits: 4,
    paletteSelectionMode: 'fixed-palette-greedy',
    colorDistanceMode: 'oklab',
    ditheringMode: 'none',
    spatialRegularizationIterations: 2,
    spatialSmoothness: 2,
    spatialEdgeSigma: 10,
  ),
  'detailed': Preset(
    id: 'detailed',
    maxColors: 16,
    analysisPixelsPerCell: 4,
    minimumForegroundCoverage: .12,
    outlineDarkLuminance: .28,
    outlineDarkRatio: .3,
    outlineContrast: .22,
    outlineWeight: 1.5,
    backgroundSeedDeltaE: 8,
    backgroundFillDeltaE: 13,
    backgroundMinimumConfidence: .88,
    cleanupMinimumNeighbors: 7,
    cellSamplingMode: 'dominant-bucket',
    colorBucketBits: 5,
    paletteSelectionMode: 'fixed-palette-greedy',
    colorDistanceMode: 'ciede2000',
    ditheringMode: 'floyd-steinberg',
    spatialRegularizationIterations: 1,
    spatialSmoothness: 1,
    spatialEdgeSigma: 12,
  ),
  'legacy': Preset(
    id: 'legacy',
    maxColors: null,
    analysisPixelsPerCell: 1,
    minimumForegroundCoverage: 0,
    outlineDarkLuminance: 0,
    outlineDarkRatio: 1,
    outlineContrast: 1,
    outlineWeight: 1,
    backgroundSeedDeltaE: 0,
    backgroundFillDeltaE: 0,
    backgroundMinimumConfidence: 1,
    cleanupMinimumNeighbors: null,
    cellSamplingMode: 'average',
    colorBucketBits: null,
    paletteSelectionMode: 'cluster-then-snap',
    colorDistanceMode: 'oklab',
    ditheringMode: 'none',
    spatialRegularizationIterations: 0,
    spatialSmoothness: 0,
    spatialEdgeSigma: 1,
  ),
  'zippland': Preset(
    id: 'zippland',
    maxColors: null,
    analysisPixelsPerCell: 1,
    minimumForegroundCoverage: 0,
    outlineDarkLuminance: 0,
    outlineDarkRatio: 1,
    outlineContrast: 1,
    outlineWeight: 1,
    backgroundSeedDeltaE: 0,
    backgroundFillDeltaE: 0,
    backgroundMinimumConfidence: 1,
    cleanupMinimumNeighbors: null,
    cellSamplingMode: 'average',
    colorBucketBits: null,
    paletteSelectionMode: 'cluster-then-snap',
    colorDistanceMode: 'oklab',
    ditheringMode: 'none',
    spatialRegularizationIterations: 0,
    spatialSmoothness: 0,
    spatialEdgeSigma: 1,
  ),
};

/// 原站 Ht=200 / Mn=10 / Gn=[52,104] 常量。
const int kPbMaxSide = 200;
const int kPbMinSide = 10;

/// 原站 Mo()：目标网格宽高（宽度固定，高度按比例，单边 ≤200）。
(int, int) pbTargetSize(int naturalW, int naturalH, int targetWidth) {
  final i = math.max(kPbMinSide, math.min(kPbMaxSide, targetWidth));
  final c = naturalH / math.max(1, naturalW);
  final h = math.max(1, (i * c).round());
  if (h <= kPbMaxSide) return (i, h);
  final u = math.max(kPbMinSide, (i * (kPbMaxSide / h)).round());
  return (math.min(kPbMaxSide, u), kPbMaxSide);
}

/// 原站 Bo()：分析图尺寸（analysisPixelsPerCell=4，长边 ≤1024）。
(int, int) pbAnalysisSize(
  int naturalW,
  int naturalH,
  int targetW,
  int targetH,
  Preset preset,
) {
  final cells = preset.analysisPixelsPerCell;
  final u = math.max(
    targetW * cells / math.max(1, naturalW),
    targetH * cells / math.max(1, naturalH),
  );
  final m = math.min(
    math.min(1.0, u),
    math.min(1024 / math.max(1, naturalW), 1024 / math.max(1, naturalH)),
  );
  return (math.max(1, (naturalW * m).round()), math.max(1, (naturalH * m).round()));
}

// ---------------------------------------------------------------------------
// 输入模型：RGBA 缓冲 + 目标网格
// ---------------------------------------------------------------------------

class PbInput {
  final Uint8List data; // RGBA，行优先
  final int width;
  final int height;
  final int targetWidth;
  final int targetHeight;
  final List<BeadColor> palette;
  final String presetId;
  final int? maximumColors;
  final String backgroundMode; // 'auto' | 'keep'
  final bool ditherOverride; // generationMethod 定制（原站 ht()）

  const PbInput({
    required this.data,
    required this.width,
    required this.height,
    required this.targetWidth,
    required this.targetHeight,
    required this.palette,
    this.presetId = 'standard',
    this.maximumColors,
    this.backgroundMode = 'auto',
    this.ditherOverride = false,
  });

  int get total => width * height;
}

class PbResult {
  final List<List<int?>> matrix; // 行优先；null = 背景/透明
  final PbDiagnostics diagnostics;

  const PbResult({required this.matrix, required this.diagnostics});
}

class PbDiagnostics {
  final bool backgroundDetected;
  final double backgroundConfidence;
  final int colorsUsed;
  final int transparentCells;
  final int foregroundCells;
  final double meanMappingDistance;
  final int selectedColorCount;
  final int cleanupChangedCells;
  final int spatialChangedCells;
  final int rareColorCount;
  final int singleCellRegionCount;

  const PbDiagnostics({
    required this.backgroundDetected,
    required this.backgroundConfidence,
    required this.colorsUsed,
    required this.transparentCells,
    required this.foregroundCells,
    required this.meanMappingDistance,
    required this.selectedColorCount,
    required this.cleanupChangedCells,
    required this.spatialChangedCells,
    required this.rareColorCount,
    required this.singleCellRegionCount,
  });
}

/// 1:1 移植主入口（原站 Ct()）。
PbResult pbConvert(PbInput input) {
  final n = input.targetWidth;
  final m = input.targetHeight;
  final preset = kPixelBeadsPresets[input.presetId] ?? kPixelBeadsPresets['standard']!;

  // ---- 背景检测（原站 Re()） ----
  final bg = _pbBackground(input, preset);

  // ---- 每格采样（原站 je()） ----
  final cells = _pbSampleCells(input, preset, bg.$1);

  // ---- 色数上限 ----
  final maxColors = input.maximumColors ??
      preset.maxColors ??
      input.palette.length;

  // ---- 选色与映射 ----
  final selection = preset.paletteSelectionMode == 'fixed-palette-greedy'
      ? _pbFixedGreedy(cells, input.palette, maxColors, preset)
      : _pbClusterSnap(cells, input.palette, maxColors, preset);

  var colorIds = selection.$1;
  final selected = selection.$2;
  var meanDist = selection.$3;

  // ---- 抖动（原站 We()） ----
  final ditherOn = preset.ditheringMode == 'floyd-steinberg' || input.ditherOverride;
  if (ditherOn) {
    final selectedPalette = [
      for (final s in selected) input.palette[s],
    ];
    colorIds = _pbDither(cells, input.targetWidth, input.targetHeight,
        selectedPalette, preset.colorDistanceMode);
  }

  // ---- 空间正则化（原站 ft()） ----
  var spatialChanged = 0;
  if (preset.spatialRegularizationIterations > 0) {
    final reg = _pbRegularize(colorIds, cells, input.targetWidth, input.targetHeight,
        input.palette, preset);
    colorIds = reg.$1;
    spatialChanged = reg.$2;
  }

  // ---- 清理（原站 ye()） ----
  var cleanupChanged = 0;
  if (preset.cleanupMinimumNeighbors != null) {
    final before = colorIds;
    colorIds = _pbCleanup(colorIds, cells, input.targetWidth, input.targetHeight, preset);
    for (var i = 0; i < colorIds.length; i++) {
      if (colorIds[i] != before[i]) cleanupChanged++;
    }
  }

  // ---- 诊断（原站 me()） ----
  final usage = <int?, int>{};
  for (final c in colorIds) {
    if (c != null) usage[c] = (usage[c] ?? 0) + 1;
  }
  final rare = usage.values.where((v) => v <= 2).length;
  final single = _pbSingleCellRegions(colorIds, n, m);
  final fg = colorIds.where((c) => c != null).length;

  return PbResult(
    matrix: _pbSlice(colorIds, n),
    diagnostics: PbDiagnostics(
      backgroundDetected: bg.$2,
      backgroundConfidence: bg.$3,
      colorsUsed: usage.length,
      transparentCells: colorIds.length - fg,
      foregroundCells: fg,
      meanMappingDistance: meanDist,
      selectedColorCount: selected.length,
      cleanupChangedCells: cleanupChanged,
      spatialChangedCells: spatialChanged,
      rareColorCount: rare,
      singleCellRegionCount: single,
    ),
  );
}

List<List<int?>> _pbSlice(List<int?> flat, int n) {
  final rows = <List<int?>>[];
  for (var i = 0; i < flat.length; i += n) {
    rows.add(flat.sublist(i, math.min(i + n, flat.length)));
  }
  return rows;
}

// ===========================================================================
// 1. 背景检测（原站 Re() 逐行移植）
// ===========================================================================

typedef _Bg = (Uint8List mask, bool detected, double confidence);

_Bg _pbBackground(PbInput input, Preset preset) {
  final w = input.width, h = input.height;
  final total = input.total;
  final mask = Uint8List(total);
  const z = 16;

  // alpha ≤ 16 → 背景
  for (var i = 0; i < total; i++) {
    if (input.data[i * 4 + 3] <= z) mask[i] = 1;
  }
  if (input.backgroundMode == 'keep') {
    return (mask, false, 0);
  }

  // 边界像素
  final border = <int>[];
  for (var x = 0; x < w; x++) {
    border.add(x);
    border.add((h - 1) * w + x);
  }
  for (var y = 1; y < h - 1; y++) {
    border.add(y * w);
    border.add(y * w + w - 1);
  }
  final borderOpaque = border.where((i) => input.data[i * 4 + 3] > z).toList();
  if (borderOpaque.isEmpty) return (mask, false, 1);

  Lab rgbAt(int i) => _rgbToLab(input.data[i * 4], input.data[i * 4 + 1], input.data[i * 4 + 2]);

  final borderLabs = borderOpaque.map(rgbAt).toList();
  final cornerIdx = [0, w - 1, (h - 1) * w, h * w - 1]
      .where((i) => input.data[i * 4 + 3] > z)
      .toList();
  final cornerLabs = cornerIdx.map(rgbAt).toList();

  final borderMedian = _medianLab(borderLabs);
  var anchor = borderMedian;
  var cornerAgreement = 0.0;
  if (cornerLabs.length >= 3) {
    final cornerMedian = _medianLab(cornerLabs);
    var hit = 0;
    for (final c in cornerLabs) {
      if (_labDist(c, cornerMedian) <= preset.backgroundSeedDeltaE) hit++;
    }
    cornerAgreement = hit / cornerLabs.length;
    if (cornerAgreement >= 0.75) anchor = cornerMedian;
  }

  var borderHit = 0;
  for (final b in borderLabs) {
    if (_labDist(b, anchor) <= preset.backgroundSeedDeltaE) borderHit++;
  }
  final confidence = math.max(borderHit / borderLabs.length, cornerAgreement);

  if (input.backgroundMode == 'auto' && confidence < preset.backgroundMinimumConfidence) {
    return (mask, false, confidence);
  }

  // flood-fill
  final q = <int>[];
  final visited = Uint8List(total);
  void trySeed(int i) {
    if (visited[i] == 1 || mask[i] == 1) return;
    if (input.data[i * 4 + 3] <= z || _labDist(rgbAt(i), anchor) <= preset.backgroundFillDeltaE) {
      visited[i] = 1;
      mask[i] = 1;
      q.add(i);
    }
  }

  for (final b in border) {
    trySeed(b);
  }
  var head = 0;
  while (head < q.length) {
    final cur = q[head++];
    final cx = cur % w;
    final cy = cur ~/ w;
    final neighbors = [
      cx > 0 ? cur - 1 : -1,
      cx < w - 1 ? cur + 1 : -1,
      cy > 0 ? cur - w : -1,
      cy < h - 1 ? cur + w : -1,
    ];
    for (final nb in neighbors) {
      if (nb < 0 || visited[nb] == 1 || mask[nb] == 1) continue;
      if (input.data[nb * 4 + 3] <= z ||
          _labDist(rgbAt(nb), anchor) <= preset.backgroundFillDeltaE) {
        visited[nb] = 1;
        mask[nb] = 1;
        q.add(nb);
      }
    }
  }

  return (mask, true, confidence);
}

Lab _medianLab(List<Lab> labs) {
  final ls = labs.map((c) => c.l).toList()..sort();
  final as = labs.map((c) => c.a).toList()..sort();
  final bs = labs.map((c) => c.b).toList()..sort();
  double mid(List<double> v) {
    final i = v.length ~/ 2;
    return v.length.isOdd ? v[i] : (v[i - 1] + v[i]) / 2;
  }

  return Lab(mid(ls), mid(as), mid(bs));
}

// ===========================================================================
// 2. 每格采样（原站 je() 逐行移植）
// ===========================================================================

class _Cell {
  final int r, g, b;
  final double coverage;
  final double darkRatio;
  final double luminanceRange;
  final bool isOutline;
  const _Cell({
    required this.r,
    required this.g,
    required this.b,
    required this.coverage,
    required this.darkRatio,
    required this.luminanceRange,
    required this.isOutline,
  });
}

double _lum(num r, num g, num b) => (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;

double _overlap(double f, double t, int coord) {
  final a = math.max(f, coord.toDouble());
  final b = math.min(t, (coord + 1).toDouble());
  return math.max(0, b - a);
}

int _bucket(int r, int g, int b, int bits) {
  final sh = 8 - bits;
  return (r >> sh) << (2 * bits) | (g >> sh) << bits | (b >> sh);
}

List<_Cell?> _pbSampleCells(PbInput input, Preset preset, Uint8List bgMask) {
  final w = input.width, h = input.height;
  final n = input.targetWidth, m = input.targetHeight;
  final bits = preset.colorBucketBits;
  final cells = List<_Cell?>.filled(n * m, null);

  for (var gy = 0; gy < m; gy++) {
    final y0f = gy * h / m;
    final y1f = (gy + 1) * h / m;
    final y0 = math.max(0, y0f.floor());
    final y1 = math.min(h, y1f.ceil());
    for (var gx = 0; gx < n; gx++) {
      final x0f = gx * w / n;
      final x1f = (gx + 1) * w / n;
      final x0 = math.max(0, x0f.floor());
      final x1 = math.min(w, x1f.ceil());

      var weight = 0.0, wR = 0.0, wG = 0.0, wB = 0.0;
      var darkW = 0.0, dR = 0.0, dG = 0.0, dB = 0.0;
      var minLum = 1.0, maxLum = 0.0;
      final hist = <int, double>{};
      final sumR = <int, double>{};
      final sumG = <int, double>{};
      final sumB = <int, double>{};

      for (var py = y0; py < y1; py++) {
        final oy = _overlap(y0f, y1f, py);
        if (oy == 0) continue;
        for (var px = x0; px < x1; px++) {
          final idx = py * w + px;
          if (bgMask[idx] == 1) continue;
          final ox = _overlap(x0f, x1f, px);
          final ov = ox * oy;
          if (ov == 0) continue;
          final alpha = input.data[idx * 4 + 3] / 255;
          if (alpha == 0) continue;
          final yw = ov * alpha;
          if (yw == 0) continue;
          final r = input.data[idx * 4];
          final g = input.data[idx * 4 + 1];
          final b = input.data[idx * 4 + 2];

          weight += yw;
          wR += r * yw;
          wG += g * yw;
          wB += b * yw;

          final lum = _lum(r, g, b);
          if (lum < minLum) minLum = lum;
          if (lum > maxLum) maxLum = lum;
          if (lum <= preset.outlineDarkLuminance) {
            darkW += yw;
            dR += r * yw;
            dG += g * yw;
            dB += b * yw;
          }

          if (preset.cellSamplingMode == 'dominant-bucket' && bits != null) {
            final bkt = _bucket(r, g, b, bits);
            hist[bkt] = (hist[bkt] ?? 0) + yw;
            sumR[bkt] = (sumR[bkt] ?? 0) + r * yw;
            sumG[bkt] = (sumG[bkt] ?? 0) + g * yw;
            sumB[bkt] = (sumB[bkt] ?? 0) + b * yw;
          }
        }
      }

      final idx = gy * n + gx;
      final cellArea = (x1f - x0f) * (y1f - y0f);
      final coverage = cellArea > 0 ? weight / cellArea : 0.0;
      if (weight == 0 || coverage < preset.minimumForegroundCoverage) {
        cells[idx] = null;
        continue;
      }

      final darkRatio = darkW / weight;
      final lumRange = maxLum - minLum;
      final meanLum = _lum(wR / weight, wG / weight, wB / weight);
      final isOutline = darkW > 0 &&
          darkRatio >= preset.outlineDarkRatio &&
          (lumRange >= preset.outlineContrast || meanLum <= preset.outlineDarkLuminance);

      int cr, cg, cb;
      if (isOutline) {
        cr = (dR / darkW).round();
        cg = (dG / darkW).round();
        cb = (dB / darkW).round();
      } else if (preset.cellSamplingMode == 'dominant-bucket' && hist.isNotEmpty) {
        var best = 0.0;
        var bestBkt = 0;
        hist.forEach((k, v) {
          if (v > best) {
            best = v;
            bestBkt = k;
          }
        });
        cr = (sumR[bestBkt]! / hist[bestBkt]!).round();
        cg = (sumG[bestBkt]! / hist[bestBkt]!).round();
        cb = (sumB[bestBkt]! / hist[bestBkt]!).round();
      } else {
        cr = (wR / weight).round();
        cg = (wG / weight).round();
        cb = (wB / weight).round();
      }

      cells[idx] = _Cell(
        r: cr,
        g: cg,
        b: cb,
        coverage: coverage,
        darkRatio: darkRatio,
        luminanceRange: lumRange,
        isOutline: isOutline,
      );
    }
  }
  return cells;
}

// ===========================================================================
// 3. 固定色卡贪心（原站 de()/Be()/_e()/Oe()/He() 逐行移植）
// ===========================================================================

typedef _WeightedColor = ({int r, int g, int b, double weight});

List<_WeightedColor> _pbAggregate(List<_Cell?> cells, double outlineWeight) {
  final map = <int, _WeightedColor>{};
  for (final c in cells) {
    if (c == null) continue;
    final key = (c.r << 16) | (c.g << 8) | c.b;
    final w = math.max(0.01, c.coverage) * (c.isOutline ? outlineWeight : 1);
    final prev = map[key];
    map[key] = prev == null
        ? (r: c.r, g: c.g, b: c.b, weight: w)
        : (r: prev.r, g: prev.g, b: prev.b, weight: prev.weight + w);
  }
  return map.values.toList();
}

typedef _Sel = (List<int?> colorIds, List<int> selected, double meanDist);

_Sel _pbFixedGreedy(
  List<_Cell?> cells,
  List<BeadColor> palette,
  int maxColors,
  Preset preset,
) {
  final empty = List<int?>.filled(cells.length, null);
  if (palette.isEmpty) return (empty, const [], 0);

  final agg = _pbAggregate(cells, preset.outlineWeight);
  if (agg.isEmpty) return (empty, const [], 0);

  final mode = preset.colorDistanceMode;
  // 距离²矩阵
  final matrix = List.generate(
    agg.length,
    (i) => Float64List(palette.length),
  );
  for (var i = 0; i < agg.length; i++) {
    final a = agg[i];
    for (var j = 0; j < palette.length; j++) {
      final p = palette[j];
      final d = _dist(mode, a.r, a.g, a.b, p.r, p.g, p.b);
      matrix[i][j] = d * d;
    }
  }

  final k = math.max(1, math.min(maxColors, math.min(palette.length, agg.length)));

  // Oe：加权第一选
  final vote = List<double>.filled(palette.length, 0);
  final acc = List<double>.filled(palette.length, 0);
  for (var i = 0; i < agg.length; i++) {
    var bestJ = 0;
    var bestD = double.infinity;
    for (var j = 0; j < palette.length; j++) {
      if (matrix[i][j] < bestD) {
        bestD = matrix[i][j];
        bestJ = j;
      }
    }
    vote[bestJ] += agg[i].weight;
    acc[bestJ] += matrix[i][bestJ] * agg[i].weight;
  }
  var first = 0;
  for (var j = 1; j < palette.length; j++) {
    if (vote[j] > vote[first] || (vote[j] == vote[first] && acc[j] < acc[first])) {
      first = j;
    }
  }

  // He：贪心最大覆盖
  final selected = <int>[first];
  final selectedSet = <int>{first};
  var best = List<double>.generate(agg.length, (i) => matrix[i][first]);
  while (selected.length < k) {
    var bestJ = -1;
    var bestGain = 0.0;
    for (var j = 0; j < palette.length; j++) {
      if (selectedSet.contains(j)) continue;
      var gain = 0.0;
      for (var i = 0; i < agg.length; i++) {
        final u = best[i] - matrix[i][j];
        if (u > 0) gain += u * agg[i].weight;
      }
      if (gain > bestGain) {
        bestGain = gain;
        bestJ = j;
      }
    }
    if (bestJ < 0 || bestGain <= 1e-9) break;
    selected.add(bestJ);
    selectedSet.add(bestJ);
    for (var i = 0; i < agg.length; i++) {
      if (matrix[i][bestJ] < best[i]) best[i] = matrix[i][bestJ];
    }
  }

  // de：映射到选中色 + 平均距离
  var sum = 0.0;
  var total = 0.0;
  final colorIds = cells.map((c) {
    if (c == null) return null;
    var bestIdx = selected.first;
    var bestD = double.infinity;
    for (final s in selected) {
      final p = palette[s];
      final d = _dist(mode, c.r, c.g, c.b, p.r, p.g, p.b);
      if (d < bestD) {
        bestD = d;
        bestIdx = s;
      }
    }
    final w = math.max(0.01, c.coverage);
    sum += bestD * w;
    total += w;
    return bestIdx;
  }).toList();

  return (colorIds, selected, total > 0 ? sum / total : 0);
}

// ===========================================================================
// 4. 聚类吸附（原站 Ue()/ze()/Xe() 逐行移植）
// ===========================================================================

_Sel _pbClusterSnap(
  List<_Cell?> cells,
  List<BeadColor> palette,
  int maxColors,
  Preset preset,
) {
  final empty = List<int?>.filled(cells.length, null);
  if (palette.isEmpty) return (empty, const [], 0);

  final pts = <({int r, int g, int b, double weight, bool isOutline, int index})>[];
  for (var i = 0; i < cells.length; i++) {
    final c = cells[i];
    if (c == null) continue;
    pts.add((
      r: c.r,
      g: c.g,
      b: c.b,
      weight: math.max(0.01, c.coverage) * (c.isOutline ? preset.outlineWeight : 1),
      isOutline: c.isOutline,
      index: i,
    ));
  }
  if (pts.isEmpty) return (empty, const [], 0);

  final k = math.max(1, math.min(maxColors, math.min(palette.length, pts.length)));

  // Xe：种子（最暗起步 + 最远点采样）
  double labDistSq(Lab a, Lab b) {
    final dl = a.l - b.l, da = a.a - b.a, db = a.b - b.b;
    return dl * dl + da * da + db * db;
  }

  final seeds = <Lab>[];
  final pool = pts.where((p) => p.isOutline).toList();
  final firstPool = pool.isNotEmpty ? pool : pts;
  var firstP = firstPool.first;
  for (final p in firstPool) {
    final lab = _rgbToLab(p.r, p.g, p.b);
    if (lab.l < _rgbToLab(firstP.r, firstP.g, firstP.b).l) firstP = p;
  }
  seeds.add(_rgbToLab(firstP.r, firstP.g, firstP.b));
  while (seeds.length < k) {
    ({int r, int g, int b, double weight, bool isOutline, int index})? pick;
    var bestScore = 0.0;
    for (final p in pts) {
      final lab = _rgbToLab(p.r, p.g, p.b);
      var minD2 = double.infinity;
      for (final s in seeds) {
        final d2 = labDistSq(lab, s);
        if (d2 < minD2) minD2 = d2;
      }
      final score = minD2 * p.weight;
      if (score > bestScore) {
        bestScore = score;
        pick = p;
      }
    }
    if (pick == null || bestScore <= 1e-12) break;
    seeds.add(_rgbToLab(pick.r, pick.g, pick.b));
  }

  // ze：加权 Lloyd（≤12 迭代）
  var centroids = List<Lab>.of(seeds);
  for (var iter = 0; iter < 12; iter++) {
    final accL = List<double>.filled(centroids.length, 0);
    final accA = List<double>.filled(centroids.length, 0);
    final accB = List<double>.filled(centroids.length, 0);
    final accW = List<double>.filled(centroids.length, 0);
    for (final p in pts) {
      final lab = _rgbToLab(p.r, p.g, p.b);
      var j = 0;
      var minD2 = double.infinity;
      for (var c = 0; c < centroids.length; c++) {
        final d2 = labDistSq(lab, centroids[c]);
        if (d2 < minD2) {
          minD2 = d2;
          j = c;
        }
      }
      accL[j] += lab.l * p.weight;
      accA[j] += lab.a * p.weight;
      accB[j] += lab.b * p.weight;
      accW[j] += p.weight;
    }
    var maxShift = 0.0;
    for (var c = 0; c < centroids.length; c++) {
      if (accW[c] == 0) continue;
      final nl = accL[c] / accW[c];
      final na = accA[c] / accW[c];
      final nb = accB[c] / accW[c];
      maxShift = math.max(maxShift, labDistSq(centroids[c], Lab(nl, na, nb)));
      centroids[c] = Lab(nl, na, nb);
    }
    if (maxShift < 1e-4) break;
  }

  // 吸附到色卡
  final snapped = <int>{};
  for (final c in centroids) {
    snapped.add(_pbNearestLab(palette, c, preset.colorDistanceMode));
  }
  if (snapped.isEmpty) return (empty, const [], 0);

  // 最暗被选色
  var darkest = snapped.first;
  for (final s in snapped) {
    if (_rgbToLab(palette[s].r, palette[s].g, palette[s].b).l <
        _rgbToLab(palette[darkest].r, palette[darkest].g, palette[darkest].b).l) {
      darkest = s;
    }
  }

  final colorIds = List<int?>.filled(cells.length, null);
  var sum = 0.0;
  var total = 0.0;
  for (final p in pts) {
    final lab = _rgbToLab(p.r, p.g, p.b);
    final int idx;
    if (p.isOutline) {
      idx = darkest;
    } else {
      var best = snapped.first;
      var bestD = double.infinity;
      for (final s in snapped) {
        final d = labDistSq(lab, _rgbToLab(palette[s].r, palette[s].g, palette[s].b));
        if (d < bestD) {
          bestD = d;
          best = s;
        }
      }
      idx = best;
    }
    colorIds[p.index] = idx;
    final w = math.max(0.01, cells[p.index]!.coverage);
    sum += _dist(preset.colorDistanceMode, p.r, p.g, p.b, palette[idx].r, palette[idx].g, palette[idx].b) * w;
    total += w;
  }

  return (colorIds, snapped.toList(), total > 0 ? sum / total : 0);
}

int _pbNearestLab(List<BeadColor> palette, Lab lab, String mode) {
  var best = 0;
  var bestD = double.infinity;
  for (var j = 0; j < palette.length; j++) {
    final p = palette[j];
    final pl = _rgbToLab(p.r, p.g, p.b);
    final d = mode == 'ciede2000' ? _ciede2000(lab, pl) : _labDist(lab, pl);
    if (d < bestD) {
      bestD = d;
      best = j;
    }
  }
  return best;
}

// ===========================================================================
// 5. 抖动（原站 We() 逐行移植：RGB 蛇形 FS，跳过背景/轮廓）
// ===========================================================================

const _fsKernel = [
  (1, 0, 7 / 16),
  (-1, 1, 3 / 16),
  (0, 1, 5 / 16),
  (1, 1, 1 / 16),
];

int _clamp255(double v) => math.max(0, math.min(255, v.round()));

List<int?> _pbDither(
  List<_Cell?> cells,
  int w,
  int h,
  List<BeadColor> palette,
  String mode,
) {
  if (palette.isEmpty) return cells.map((c) => null).toList();
  final buf = List<({int r, int g, int b})?>.generate(
      cells.length, (i) => cells[i] == null ? null : (r: cells[i]!.r, g: cells[i]!.g, b: cells[i]!.b));
  final out = List<int?>.filled(cells.length, null);

  for (var y = 0; y < h; y++) {
    final ltr = y.isEven;
    for (var k = 0; k < w; k++) {
      final x = ltr ? k : w - 1 - k;
      final i = y * w + x;
      final cell = cells[i];
      final cur = buf[i];
      if (cell == null || cell.isOutline || cur == null) continue;

      var bestIdx = 0;
      var bestD = double.infinity;
      for (var j = 0; j < palette.length; j++) {
        final p = palette[j];
        final d = _dist(mode, cur.r, cur.g, cur.b, p.r, p.g, p.b);
        if (d < bestD) {
          bestD = d;
          bestIdx = j;
        }
      }
      out[i] = bestIdx;

      final target = palette[bestIdx];
      final er = cur.r - target.r;
      final eg = cur.g - target.g;
      final eb = cur.b - target.b;

      for (final (dx, dy, ww) in _fsKernel) {
        final nx = ltr ? x + dx : x - dx;
        final ny = y + dy;
        if (nx < 0 || nx >= w || ny >= h) continue;
        final ni = ny * w + nx;
        final nc = cells[ni];
        final nb = buf[ni];
        if (nc == null || nc.isOutline || nb == null) continue;
        buf[ni] = (
          r: _clamp255(nb.r + er * ww),
          g: _clamp255(nb.g + eg * ww),
          b: _clamp255(nb.b + eb * ww),
        );
      }
    }
  }
  return out;
}

// ===========================================================================
// 6. 空间正则化（原站 ft() 逐行移植）
// ===========================================================================

typedef _Reg = (List<int?> colorIds, int changed);

_Reg _pbRegularize(
  List<int?> colorIds,
  List<_Cell?> cells,
  int w,
  int h,
  List<BeadColor> palette,
  Preset preset,
) {
  var cur = List<int?>.of(colorIds);
  var totalChanged = 0;
  for (var iter = 0; iter < preset.spatialRegularizationIterations; iter++) {
    final next = List<int?>.of(cur);
    var changed = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final cell = cells[i];
        final self = cur[i];
        if (cell == null || cell.isOutline || self == null) continue;
        final candidates = <int>{self};
        final neighbors = <({int r, int g, int b, int colorId})>[];
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final ni = ny * w + nx;
          final nc = cells[ni];
          final ci = cur[ni];
          if (nc == null || ci == null) continue;
          candidates.add(ci);
          neighbors.add((r: nc.r, g: nc.g, b: nc.b, colorId: ci));
        }
        if (candidates.length == 1) continue;

        var best = self;
        var bestScore = double.infinity;
        for (final k in candidates) {
          final pk = palette[k];
          var score = _dist(preset.colorDistanceMode, cell.r, cell.g, cell.b, pk.r, pk.g, pk.b);
          for (final nb in neighbors) {
            if (nb.colorId == k) continue;
            final d = _dist(preset.colorDistanceMode, cell.r, cell.g, cell.b, nb.r, nb.g, nb.b);
            score += preset.spatialSmoothness *
                math.exp(-d / math.max(0.01, preset.spatialEdgeSigma));
          }
          if (score < bestScore) {
            bestScore = score;
            best = k;
          }
        }
        if (best != self) {
          next[i] = best;
          changed++;
        }
      }
    }
    cur = next;
    totalChanged += changed;
    if (changed == 0) break;
  }
  return (cur, totalChanged);
}

// ===========================================================================
// 7. 清理（原站 ye() 逐行移植：8 邻域多数表决，跳过轮廓）
// ===========================================================================

List<int?> _pbCleanup(
  List<int?> grid,
  List<_Cell?> cells,
  int w,
  int h,
  Preset preset,
) {
  final minNeighbors = preset.cleanupMinimumNeighbors;
  if (minNeighbors == null) return grid;
  final out = List<int?>.of(grid);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final cell = cells[i];
      final self = grid[i];
      if (self == null || cell == null || cell.isOutline) continue;
      final counts = <int, int>{};
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final ni = ny * w + nx;
          final v = grid[ni];
          if (v != null) counts[v] = (counts[v] ?? 0) + 1;
        }
      }
      var majority = self;
      var maxCount = 0;
      counts.forEach((k, v) {
        if (v > maxCount) {
          maxCount = v;
          majority = k;
        }
      });
      if (majority != self && maxCount >= minNeighbors) {
        out[i] = majority;
      }
    }
  }
  return out;
}

// ===========================================================================
// 8. 诊断：孤立单格连通域数（原站 me() 口径）
// ===========================================================================

int _pbSingleCellRegions(List<int?> grid, int w, int h) {
  final labels = List<int>.filled(grid.length, 0);
  var nextLabel = 1;
  var single = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (labels[i] != 0 || grid[i] == null) continue;
      final color = grid[i];
      final q = <int>[i];
      labels[i] = nextLabel;
      var head = 0;
      var count = 0;
      while (head < q.length) {
        final cur = q[head++];
        count++;
        final cx = cur % w;
        final cy = cur ~/ w;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = cx + dx, ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final ni = ny * w + nx;
          if (labels[ni] == 0 && grid[ni] == color) {
            labels[ni] = nextLabel;
            q.add(ni);
          }
        }
      }
      if (count == 1) single++;
      nextLabel++;
    }
  }
  return single;
}
