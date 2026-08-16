/// 后处理：连通域杂色合并 + 背景 flood fill 移除 + 空间正则化 + 多数表决清理。
///
/// 输入：色号索引矩阵（N×N，行优先）。
/// 输出：去杂矩阵（小连通块并入相邻主色）+ 背景透明标记（-1）。
library;

import 'dart:math' as math;

import 'ciede2000.dart';
import 'color_mapper.dart';
import 'color_space.dart';
import 'oklab.dart';
import 'palette.dart';
import 'sampler.dart';

/// 后处理参数。
class PostProcessOptions {
  /// 面积（格数）小于该阈值的连通块视为杂色，并入相邻最大块。
  /// plan 验收标准：输出不含 <2 格孤立杂色，默认 2 即合并所有 1 格孤立点。
  final int minBlockSize;

  /// 是否启用背景移除。
  final bool removeBackground;

  /// 背景 flood fill 的相近判定阈值（ΔE00）。
  /// 从边界格颜色出发，色差 < 阈值视为同背景。
  final double backgroundDeltaE;

  const PostProcessOptions({
    this.minBlockSize = 2,
    this.removeBackground = true,
    this.backgroundDeltaE = 4.0,
  });
}

/// 后处理结果。
class PostProcessResult {
  final int size;

  /// 行优先色号索引矩阵；-1 表示透明（背景已移除）。
  final List<int> grid;

  PostProcessResult({required this.size, required this.grid});

  int at(int x, int y) => grid[y * size + x];
}

/// 执行后处理。
///
/// 顺序：先杂色合并（消除孤立块），再背景移除（移除大块背景）。
/// 纯色/近纯色背景下两个顺序等价；渐变背景先合并更稳（不挖出锯齿边）。
///
/// [grid]：色号索引矩阵；[labs]：色卡 Lab 值（背景相近判定用）。
PostProcessResult postProcess(
  List<int> grid,
  int size,
  PostProcessOptions options, {
  List<LabColor>? labs,
}) {
  var result = List<int>.of(grid);

  // ① 杂色合并：面积 < minBlockSize 的连通块并入相邻最大块
  result = _mergeSpeckles(result, size, options.minBlockSize);

  // ② 背景移除：边界 flood fill
  if (options.removeBackground && labs != null) {
    result = _removeBackground(result, size, options, labs);
  }

  return PostProcessResult(size: size, grid: result);
}

/// 连通域标记（四邻域）。返回每个格子的块 id（从 1 开始；透明格为 0）。
List<int> _labelComponents(List<int> grid, int size) {
  final labels = List<int>.filled(grid.length, 0);
  var nextLabel = 1;

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = y * size + x;
      if (labels[i] != 0 || grid[i] < 0) continue;
      final color = grid[i];

      // BFS
      final queue = <int>[i];
      labels[i] = nextLabel;
      var head = 0;
      while (head < queue.length) {
        final cur = queue[head++];
        final cx = cur % size;
        final cy = cur ~/ size;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = cx + dx;
          final ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= size || ny >= size) continue;
          final ni = ny * size + nx;
          if (labels[ni] == 0 && grid[ni] == color) {
            labels[ni] = nextLabel;
            queue.add(ni);
          }
        }
      }
      nextLabel++;
    }
  }
  return labels;
}

List<int> _mergeSpeckles(List<int> grid, int size, int minSize) {
  if (minSize <= 1) return grid;
  final labels = _labelComponents(grid, size);

  // 块面积统计
  final area = <int, int>{};
  for (final l in labels) {
    area[l] = (area[l] ?? 0) + 1;
  }

  // 找出每个小块的所有相邻块（含小块）及面积
  final neighbors = <int, Map<int, int>>{};
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = y * size + x;
      final l = labels[i];
      if (l == 0 || grid[i] < 0) continue;
      if (area[l]! >= minSize) continue; // 只关心小块
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= size || ny >= size) continue;
        final ni = ny * size + nx;
        if (grid[ni] < 0) continue; // 透明格不参与
        final nl = labels[ni];
        if (nl == 0 || nl == l) continue;
        neighbors.putIfAbsent(l, () => {})[nl] = area[nl]!;
      }
    }
  }

  // 每个块的代表色
  final blockColor = <int, int>{};
  for (var i = 0; i < grid.length; i++) {
    blockColor.putIfAbsent(labels[i], () => grid[i]);
  }

  // 小块的并入目标：相邻面积最大的块（含小块间的传递解析）
  final mergeTo = <int, int>{};
  for (final entry in neighbors.entries) {
    var bestLabel = -1;
    var bestArea = -1;
    for (final nl in entry.value.entries) {
      if (nl.value > bestArea) {
        bestArea = nl.value;
        bestLabel = nl.key;
      }
    }
    if (bestLabel > 0) mergeTo[entry.key] = bestLabel;
  }

  // 解析合并链（小块的邻居也可能被合并）
  int resolveColor(int l, Set<int> seen) {
    final target = mergeTo[l];
    if (target == null) return blockColor[l]!;
    if (seen.contains(l)) return blockColor[l]!; // 防环兜底
    seen.add(l);
    return resolveColor(target, seen);
  }

  if (mergeTo.isEmpty) return grid;
  final out = List<int>.of(grid);
  for (var i = 0; i < grid.length; i++) {
    final l = labels[i];
    if (mergeTo.containsKey(l)) {
      out[i] = resolveColor(l, <int>{});
    }
  }
  return out;
}

List<int> _removeBackground(
  List<int> grid,
  int size,
  PostProcessOptions options,
  List<LabColor> labs,
) {
  final visited = List<bool>.filled(grid.length, false);
  final background = List<bool>.filled(grid.length, false);
  final deltaE = options.backgroundDeltaE;

  // 种子：四条边的格子
  final seeds = <int>[];
  for (var x = 0; x < size; x++) {
    seeds.add(x); // 顶边
    seeds.add((size - 1) * size + x); // 底边
  }
  for (var y = 0; y < size; y++) {
    seeds.add(y * size); // 左边
    seeds.add(y * size + size - 1); // 右边
  }

  for (final seed in seeds) {
    if (visited[seed] || grid[seed] < 0) continue;
    final seedLab = labs[grid[seed]];

    final q = <int>[seed];
    visited[seed] = true;
    background[seed] = true;
    var head = 0;
    while (head < q.length) {
      final cur = q[head++];
      final cx = cur % size;
      final cy = cur ~/ size;
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (nx < 0 || ny < 0 || nx >= size || ny >= size) continue;
        final ni = ny * size + nx;
        if (visited[ni] || grid[ni] < 0) continue;
        if (ciede2000(labs[grid[ni]], seedLab) < deltaE) {
          visited[ni] = true;
          background[ni] = true;
          q.add(ni);
        }
      }
    }
  }

  final out = List<int>.of(grid);
  for (var i = 0; i < out.length; i++) {
    if (background[i]) out[i] = -1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// 空间正则化（边缘保护平滑） + 多数表决清理
// ---------------------------------------------------------------------------

/// 两个 RGB 的感知色差（按 [distance] 模式）。
double colorDistanceRgb(int a, int b, ColorDistance distance) {
  final ar = (a >> 16) & 0xFF;
  final ag = (a >> 8) & 0xFF;
  final ab = a & 0xFF;
  final br = (b >> 16) & 0xFF;
  final bg = (b >> 8) & 0xFF;
  final bb = b & 0xFF;
  switch (distance) {
    case ColorDistance.oklab:
      return oklabDistance(srgbToOklab(ar, ag, ab), srgbToOklab(br, bg, bb));
    case ColorDistance.ciede2000:
      return ciede2000(rgbToLab(ar, ag, ab), rgbToLab(br, bg, bb));
  }
}

/// 空间正则化结果。
class RegularizeResult {
  final List<int> grid;

  /// 变更格数（供诊断展示）。
  final int changed;

  RegularizeResult({required this.grid, required this.changed});
}

/// 边缘保护的空间正则化（参考 pixel-beads `ft()`）：
/// 对每个非背景、非轮廓格，评估候选色 = 自身 + 四邻域色号；
/// 代价 = 该格原始采样色到候选色的色差 + smoothness × Σ(exp(-邻域色差/edgeSigma))，
/// 取代价最小的候选；迭代 [iterations] 次。轮廓格不参与 → 轮廓不被抹糊。
/// [height] 支持非正方形网格（默认 == size）。
RegularizeResult regularizeGrid(
  List<int> grid,
  List<SampleCell?> cells,
  int size,
  Palette palette, {
  int? height,
  required int iterations,
  required double smoothness,
  required double edgeSigma,
  required ColorDistance distance,
}) {
  final n = size;
  final m = height ?? n;
  final paletteRgb = <int>[
    for (final e in palette.entries) (e.r << 16) | (e.g << 8) | e.b,
  ];
  var cur = List<int>.of(grid);
  var totalChanged = 0;

  for (var it = 0; it < iterations; it++) {
    final next = List<int>.of(cur);
    var changed = 0;
    for (var y = 0; y < m; y++) {
      for (var x = 0; x < n; x++) {
        final i = y * n + x;
        final cell = cells[i];
        if (cell == null || cell.isOutline) continue;
        final self = cur[i];
        final candidates = <int>{self};
        final neighbors = <(int rgb, int colorId)>[];
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= n || ny >= m) continue;
          final ni = ny * n + nx;
          final nc = cells[ni];
          if (nc == null) continue;
          candidates.add(cur[ni]);
          neighbors.add((nc.rgb, cur[ni]));
        }
        if (candidates.length == 1) continue;

        var best = self;
        var bestScore = double.infinity;
        for (final k in candidates) {
          final pk = paletteRgb[k];
          var score = colorDistanceRgb(cell.rgb, pk, distance);
          for (final (nbRgb, nbId) in neighbors) {
            if (nbId == k) continue;
            final d = colorDistanceRgb(cell.rgb, nbRgb, distance);
            score += smoothness * math.exp(-d / math.max(0.01, edgeSigma));
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

  return RegularizeResult(grid: cur, changed: totalChanged);
}

/// 8 邻域多数表决清理（参考 pixel-beads `ye()`）：
/// 邻域中数量最多的色号 ≥ [minNeighbors] 且与自身不同 → 替换。
/// 跳过背景格与轮廓格。[height] 支持非正方形网格（默认 == size）。
List<int> cleanupByMajority(
  List<int> grid,
  List<SampleCell?> cells,
  int size, {
  int? height,
  required int minNeighbors,
}) {
  final n = size;
  final m = height ?? n;
  final out = List<int>.of(grid);
  for (var y = 0; y < m; y++) {
    for (var x = 0; x < n; x++) {
      final i = y * n + x;
      final cell = cells[i];
      if (cell == null || cell.isOutline) continue;
      final counts = <int, int>{};
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= n || ny >= m) continue;
          final ni = ny * n + nx;
          if (cells[ni] == null) continue;
          counts[grid[ni]] = (counts[grid[ni]] ?? 0) + 1;
        }
      }
      var majority = grid[i];
      var maxCount = 0;
      counts.forEach((k, v) {
        if (v > maxCount) {
          maxCount = v;
          majority = k;
        }
      });
      if (majority != grid[i] && maxCount >= minNeighbors) {
        out[i] = majority;
      }
    }
  }
  return out;
}

/// 小区域合并：把面积 ≤ [minRegionSize] 的连通域替换为 8 邻域中出现最多的色号。
/// 保证「输出不含小面积孤立杂色」的验收标准，同时不侵蚀更大的细节块。
/// 迭代到收敛（替换可能产生新的小区域）；跳过背景格。
/// [height] 支持非正方形网格（默认 == size）。
List<int> removeSingleCellRegions(
  List<int> grid,
  List<SampleCell?> cells,
  int size, {
  int? height,
  int minRegionSize = 1,
}) {
  var cur = List<int>.of(grid);
  for (var pass = 0; pass < 16; pass++) {
    final out = _removeSingleCellPass(cur, cells, size,
        height: height, minRegionSize: minRegionSize);
    if (out == cur) break;
    cur = out;
  }
  return cur;
}

List<int> _removeSingleCellPass(
  List<int> grid,
  List<SampleCell?> cells,
  int size, {
  int? height,
  int minRegionSize = 1,
}) {
  final n = size;
  final m = height ?? n;
  // 连通域标记（四邻域）
  final labels = List<int>.filled(grid.length, 0);
  final area = <int, int>{};
  var nextLabel = 1;
  for (var y = 0; y < m; y++) {
    for (var x = 0; x < n; x++) {
      final i = y * n + x;
      if (labels[i] != 0 || grid[i] < 0) continue;
      final color = grid[i];
      final queue = <int>[i];
      labels[i] = nextLabel;
      var head = 0;
      var count = 0;
      while (head < queue.length) {
        final cur = queue[head++];
        count++;
        final cx = cur % n;
        final cy = cur ~/ n;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = cx + dx;
          final ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= n || ny >= m) continue;
          final ni = ny * n + nx;
          if (labels[ni] == 0 && grid[ni] == color) {
            labels[ni] = nextLabel;
            queue.add(ni);
          }
        }
      }
      area[nextLabel] = count;
      nextLabel++;
    }
  }

  var changed = false;
  final out = List<int>.of(grid);
  for (var y = 0; y < m; y++) {
    for (var x = 0; x < n; x++) {
      final i = y * n + x;
      if (cells[i] == null) continue;
      final a = area[labels[i]];
      if (a == null || a > minRegionSize) continue;
      // 8 邻域众数（排除背景格）
      final counts = <int, int>{};
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= n || ny >= m) continue;
          final ni = ny * n + nx;
          if (cells[ni] == null || grid[ni] < 0) continue;
          counts[grid[ni]] = (counts[grid[ni]] ?? 0) + 1;
        }
      }
      if (counts.isEmpty) continue;
      var best = 0;
      var bestCount = 0;
      counts.forEach((k, v) {
        if (v > bestCount) {
          bestCount = v;
          best = k;
        }
      });
      if (best != grid[i]) {
        out[i] = best;
        changed = true;
      }
    }
  }
  return changed ? out : grid;
}
