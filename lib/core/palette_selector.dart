/// 色卡选色与映射：fixed-palette-greedy（贪心最大覆盖） / cluster-then-snap。
///
/// 参考 pixel-beads.com 的 `de()/He()/Oe()` 与 `Ue()/ze()/Xe()`：
///
/// A. `fixed-palette-greedy`：把格内不同颜色按覆盖度（轮廓格 × outlineWeight）加权聚合，
///    然后贪心挑选 ≤maxColors 个色卡色——每次选「能覆盖最多未覆盖权重」的色，
///    最后每个格子映射到【被选中的色】中距离最近者。
///    比「按用量留 top-K」强：保留的是最能代表整图的色，色数受控的同时平均色差更小。
///
/// B. `cluster-then-snap`：加权 k-means（CIELAB，12 迭代）聚类出 ≤maxColors 个簇，
///    簇中心吸附到色卡最近色；轮廓格映射到最暗的被选色（治毛边）。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'color_mapper.dart';
import 'color_space.dart';
import 'palette.dart';
import 'sampler.dart';

/// 选色策略。
enum PaletteSelectionMode {
  /// 固定色卡贪心最大覆盖（默认，标准/精简/细腻档）。
  fixedGreedy,

  /// 先聚类再吸附（平滑自然档）。
  clusterSnap,
}

/// 选色 + 映射结果。
class PaletteSelection {
  /// 行优先色号索引矩阵；-1 = 背景/透明。
  final List<int> grid;

  /// 最终选用的色号下标集合。
  final List<int> selectedIndices;

  /// 平均映射色差（按覆盖度加权，供诊断展示）。
  final double meanMappingDistance;

  const PaletteSelection({
    required this.grid,
    required this.selectedIndices,
    required this.meanMappingDistance,
  });
}

/// 色卡选色器。
class PaletteSelector {
  final Palette palette;
  final ColorMapper mapper;

  PaletteSelector(this.palette, this.mapper);

  /// 将采样格子映射到色卡。
  ///
  /// [cells]：行优先，null = 背景；[maxColors]：0 = 不限。
  PaletteSelection selectAndMap(
    List<SampleCell?> cells, {
    required int gridSize,
    int maxColors = 0,
    double outlineWeight = 2.5,
    PaletteSelectionMode mode = PaletteSelectionMode.fixedGreedy,
    List<int>? allowedIndices,
  }) {
    final n = gridSize;
    if (mode == PaletteSelectionMode.clusterSnap) {
      return _clusterThenSnap(
        cells,
        n: n,
        maxColors: maxColors,
        outlineWeight: outlineWeight,
        allowedIndices: allowedIndices,
      );
    }
    return _fixedGreedy(
      cells,
      n: n,
      maxColors: maxColors,
      outlineWeight: outlineWeight,
      allowedIndices: allowedIndices,
    );
  }

  // -------------------------------------------------------------------------
  // A. fixed-palette-greedy
  // -------------------------------------------------------------------------

  PaletteSelection _fixedGreedy(
    List<SampleCell?> cells, {
    required int n,
    required int maxColors,
    required double outlineWeight,
    List<int>? allowedIndices,
  }) {
    final palIdx = allowedIndices ??
        List<int>.generate(palette.length, (i) => i);
    final grid = List<int>.filled(cells.length, -1);
    if (palIdx.isEmpty) {
      return PaletteSelection(grid: grid, selectedIndices: const [], meanMappingDistance: 0);
    }

    // ① 有效格子 + 按 RGB 聚合（覆盖度加权，轮廓 ×outlineWeight）
    final weightByRgb = <int, double>{};
    final cellByRgb = <int, int>{}; // rgb → 首个格下标（映射用）
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      if (c == null) continue;
      final w = c.coverage * (c.isOutline ? outlineWeight : 1.0);
      weightByRgb[c.rgb] = (weightByRgb[c.rgb] ?? 0.0) + w;
      cellByRgb.putIfAbsent(c.rgb, () => i);
    }
    if (weightByRgb.isEmpty) {
      return PaletteSelection(grid: grid, selectedIndices: const [], meanMappingDistance: 0);
    }

    final distinct = weightByRgb.keys.toList();
    final weights = [for (final k in distinct) weightByRgb[k]!];

    // ② 距离²矩阵（distinct × 可选色卡）
    final matrix = List.generate(
      distinct.length,
      (i) => Float64List(palIdx.length),
    );
    for (var i = 0; i < distinct.length; i++) {
      for (var j = 0; j < palIdx.length; j++) {
        final d = mapper.distanceRgbToIndex(distinct[i], palIdx[j]);
        matrix[i][j] = d * d;
      }
    }

    // ③ 贪心选色：首个 = 加权最近邻投票最多者；其后 = 最大覆盖增益
    final k = maxColors <= 0
        ? palIdx.length
        : math.min(maxColors, math.min(palIdx.length, distinct.length));

    final firstPick = _weightedFirstPick(matrix, weights, palIdx);
    final selected = <int>[palIdx[firstPick]];
    final selectedSet = <int>{palIdx[firstPick]};
    var best = List<double>.generate(distinct.length, (i) => matrix[i][firstPick]);

    while (selected.length < k) {
      var bestJ = -1;
      var bestGain = 0.0;
      for (var j = 0; j < palIdx.length; j++) {
        if (selectedSet.contains(palIdx[j])) continue;
        var gain = 0.0;
        for (var i = 0; i < distinct.length; i++) {
          final u = best[i] - matrix[i][j];
          if (u > 0) gain += u * weights[i];
        }
        if (gain > bestGain) {
          bestGain = gain;
          bestJ = j;
        }
      }
      if (bestJ < 0 || bestGain <= 1e-9) break;
      selected.add(palIdx[bestJ]);
      selectedSet.add(palIdx[bestJ]);
      for (var i = 0; i < distinct.length; i++) {
        if (matrix[i][bestJ] < best[i]) best[i] = matrix[i][bestJ];
      }
    }

    // ④ 映射：每格 → 选中色中最近者（红色防御）
    var sum = 0.0;
    var total = 0.0;
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      if (c == null) continue;
      final idx = mapper.nearestAmongRgb(c.rgb, selected);
      grid[i] = idx;
      final w = math.max(0.01, c.coverage);
      sum += mapper.distanceRgbToIndex(c.rgb, idx) * w;
      total += w;
    }

    return PaletteSelection(
      grid: grid,
      selectedIndices: selected,
      meanMappingDistance: total > 0 ? sum / total : 0,
    );
  }

  /// 加权第一选（参考 pixel-beads `Oe()`）：
  /// 每个不同色 → 其最近色卡下标，按权重投票；平票取累计距离小者。
  int _weightedFirstPick(List<Float64List> matrix, List<double> weights, List<int> palIdx) {
    final vote = List<double>.filled(palIdx.length, 0);
    final acc = List<double>.filled(palIdx.length, 0);
    for (var i = 0; i < matrix.length; i++) {
      var bestJ = 0;
      var bestD = double.infinity;
      for (var j = 0; j < palIdx.length; j++) {
        if (matrix[i][j] < bestD) {
          bestD = matrix[i][j];
          bestJ = j;
        }
      }
      vote[bestJ] += weights[i];
      acc[bestJ] += matrix[i][bestJ] * weights[i];
    }
    var best = 0;
    for (var j = 1; j < palIdx.length; j++) {
      if (vote[j] > vote[best] ||
          (vote[j] == vote[best] && acc[j] < acc[best])) {
        best = j;
      }
    }
    return best;
  }

  // -------------------------------------------------------------------------
  // B. cluster-then-snap（加权 k-means → 吸附色卡）
  // -------------------------------------------------------------------------

  PaletteSelection _clusterThenSnap(
    List<SampleCell?> cells, {
    required int n,
    required int maxColors,
    required double outlineWeight,
    List<int>? allowedIndices,
  }) {
    final grid = List<int>.filled(cells.length, -1);
    final palIdx = allowedIndices ??
        List<int>.generate(palette.length, (i) => i);
    if (palIdx.isEmpty) {
      return PaletteSelection(grid: grid, selectedIndices: const [], meanMappingDistance: 0);
    }

    final pts = <_ClusterPoint>[];
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      if (c == null) continue;
      pts.add(_ClusterPoint(
        index: i,
        lab: rgbToLab((c.rgb >> 16) & 0xFF, (c.rgb >> 8) & 0xFF, c.rgb & 0xFF),
        weight: math.max(0.01, c.coverage) * (c.isOutline ? outlineWeight : 1.0),
        isOutline: c.isOutline,
      ));
    }
    if (pts.isEmpty) {
      return PaletteSelection(grid: grid, selectedIndices: const [], meanMappingDistance: 0);
    }

    final k = maxColors <= 0
        ? palIdx.length
        : math.min(maxColors, math.min(palIdx.length, pts.length));

    // 种子：最暗（轮廓优先）起步，随后最远点采样（加权）
    final seeds = <LabColor>[];
    final pool = pts.where((p) => p.isOutline).toList();
    final firstPool = pool.isNotEmpty ? pool : pts;
    var first = firstPool.first;
    for (final p in firstPool) {
      if (p.lab.l < first.lab.l) first = p;
    }
    seeds.add(first.lab);
    while (seeds.length < k) {
      _ClusterPoint? pick;
      var bestScore = 0.0;
      for (final p in pts) {
        var minD2 = double.infinity;
        for (final s in seeds) {
          final d2 = _distSq(p.lab, s);
          if (d2 < minD2) minD2 = d2;
        }
        final score = minD2 * p.weight;
        if (score > bestScore) {
          bestScore = score;
          pick = p;
        }
      }
      if (pick == null || bestScore <= 1e-12) break;
      seeds.add(pick.lab);
    }

    // 加权 Lloyd（≤12 迭代）
    final centroids = List<LabColor>.of(seeds);
    for (var iter = 0; iter < 12; iter++) {
      final accL = List<double>.filled(centroids.length, 0);
      final accA = List<double>.filled(centroids.length, 0);
      final accB = List<double>.filled(centroids.length, 0);
      final accW = List<double>.filled(centroids.length, 0);
      for (final p in pts) {
        var j = 0;
        var minD2 = double.infinity;
        for (var c = 0; c < centroids.length; c++) {
          final d2 = _distSq(p.lab, centroids[c]);
          if (d2 < minD2) {
            minD2 = d2;
            j = c;
          }
        }
        accL[j] += p.lab.l * p.weight;
        accA[j] += p.lab.a * p.weight;
        accB[j] += p.lab.b * p.weight;
        accW[j] += p.weight;
      }
      var maxShift = 0.0;
      for (var c = 0; c < centroids.length; c++) {
        if (accW[c] == 0) continue;
        final nl = accL[c] / accW[c];
        final na = accA[c] / accW[c];
        final nb = accB[c] / accW[c];
        maxShift = math.max(maxShift, _distSq(centroids[c], LabColor(nl, na, nb)));
        centroids[c] = LabColor(nl, na, nb);
      }
      if (maxShift < 1e-4) break;
    }

    // 簇中心 → 色卡吸附（仅限可选色）
    final snapped = <int>[];
    final snappedSet = <int>{};
    for (final c in centroids) {
      final idx = mapper.nearestIndex(c);
      if (snappedSet.add(idx)) snapped.add(idx);
    }
    if (snapped.isEmpty) {
      return PaletteSelection(grid: grid, selectedIndices: const [], meanMappingDistance: 0);
    }

    // 轮廓格 → 最暗的被选色
    var darkest = snapped.first;
    for (final s in snapped) {
      if (palette.entries[s].lab.l < palette.entries[darkest].lab.l) {
        darkest = s;
      }
    }

    var sum = 0.0;
    var total = 0.0;
    for (final p in pts) {
      final int idx;
      if (p.isOutline) {
        idx = darkest;
      } else {
        var j = 0;
        var minD2 = double.infinity;
        for (var c = 0; c < snapped.length; c++) {
          final d2 = _distSq(p.lab, palette.entries[snapped[c]].lab);
          if (d2 < minD2) {
            minD2 = d2;
            j = c;
          }
        }
        idx = snapped[j];
      }
      grid[p.index] = idx;
      final w = math.max(0.01, cells[p.index]!.coverage);
      sum += mapper.distanceRgbToIndex(
            cells[p.index]!.rgb,
            idx,
          ) * w;
      total += w;
    }

    return PaletteSelection(
      grid: grid,
      selectedIndices: snapped,
      meanMappingDistance: total > 0 ? sum / total : 0,
    );
  }

  static double _distSq(LabColor a, LabColor b) {
    final dl = a.l - b.l;
    final da = a.a - b.a;
    final db = a.b - b.b;
    return dl * dl + da * da + db * db;
  }
}

class _ClusterPoint {
  final int index;
  final LabColor lab;
  final double weight;
  final bool isOutline;

  const _ClusterPoint({
    required this.index,
    required this.lab,
    required this.weight,
    required this.isOutline,
  });
}
