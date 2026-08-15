/// 后处理：连通域杂色合并 + 背景 flood fill 移除。
///
/// 输入：色号索引矩阵（N×N，行优先）。
/// 输出：去杂矩阵（小连通块并入相邻主色）+ 背景透明标记（-1）。
library;

import 'ciede2000.dart';
import 'color_space.dart';

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
