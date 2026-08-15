/// 色数上限削减。
///
/// dev-plan 的"色数上限（8–64）"参数与"直接色卡映射"存在矛盾：
/// 最近邻映射不保证色数 ≤ 上限。本模块实现贪心削减：
/// 按使用量（格数）排序保留 top-K 色号，其余色号的格子
/// 逐个重新映射到保留色号中 ΔE00 最近者（自底向上：从最小色开始）。
library;

import 'ciede2000.dart';
import 'color_space.dart';

/// 削减结果。
class ReduceResult {
  /// 行优先色号索引矩阵（-1 保持 -1 透明）。
  final List<int> grid;

  /// 最终使用的色号集合（下标）。
  final Set<int> usedColors;

  ReduceResult({required this.grid, required this.usedColors});
}

/// 将 [grid] 使用的色号削减到不超过 [maxColors] 种。
///
/// [grid]：色号索引矩阵（-1 = 透明，不参与统计）；[labs]：色卡 Lab。
ReduceResult reduceColorCount(
  List<int> grid,
  List<LabColor> labs,
  int maxColors,
) {
  // 用量统计（按色号）
  final usage = <int, int>{};
  for (final idx in grid) {
    if (idx < 0) continue;
    usage[idx] = (usage[idx] ?? 0) + 1;
  }

  if (usage.length <= maxColors) {
    return ReduceResult(grid: List<int>.of(grid), usedColors: usage.keys.toSet());
  }

  // 保留用量最大的 top-K
  final sorted = usage.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final keep = <int>{for (final e in sorted.take(maxColors)) e.key};

  // 被淘汰色号 → 映射到保留色号中 ΔE00 最近者
  final replacement = <int, int>{};
  for (final entry in usage.entries) {
    if (keep.contains(entry.key)) continue;
    var best = keep.first;
    var bestDist = double.infinity;
    for (final k in keep) {
      final d = ciede2000(labs[entry.key], labs[k]);
      if (d < bestDist) {
        bestDist = d;
        best = k;
      }
    }
    replacement[entry.key] = best;
  }

  final out = List<int>.of(grid);
  for (var i = 0; i < out.length; i++) {
    final idx = out[i];
    if (idx < 0) continue;
    final rep = replacement[idx];
    if (rep != null) out[i] = rep;
  }

  return ReduceResult(grid: out, usedColors: keep);
}
