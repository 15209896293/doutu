/// KD-tree 加速的色卡最近邻映射（可选手感色差空间 + 红色主导防御）。
///
/// 策略：在所选工作空间（CIELAB 或 OKLab）建 KD-tree，欧氏收集 top-K 候选，
/// 再对候选做精确色差终选 —— 兼顾速度与准确性。
///
/// - `ColorDistance.oklab`：OKLab 欧氏（感知均匀、便宜，默认转换档）
/// - `ColorDistance.ciede2000`：CIEDE2000（最准，细腻档）
/// - 红色主导防御：对强红像素给非红卡条目按 G/B 值加罚分，避免红色漂移
///   （参考鸿蒙侧实践：红色匹配准确率 92% → 99.5%）。
library;

import 'dart:math' as math;

import 'ciede2000.dart';
import 'color_space.dart';
import 'oklab.dart';
import 'palette.dart';

/// 色差距离模式。
enum ColorDistance {
  /// OKLab 欧氏距离（感知均匀、计算快；默认）。
  oklab,

  /// CIEDE2000（CIELAB 空间，最精确但较慢）。
  ciede2000,
}

/// 工作空间坐标（3D 点，供 KD-tree 使用）。
class _WorkPoint {
  final double l;
  final double a;
  final double b;
  const _WorkPoint(this.l, this.a, this.b);
}

/// 工作空间 KD-tree 节点。
class _KdNode {
  final _WorkPoint point;
  final int paletteIndex;
  _KdNode? left;
  _KdNode? right;

  _KdNode(this.point, this.paletteIndex);
}

/// 色卡映射器。
class ColorMapper {
  final Palette palette;
  final ColorDistance distance;

  /// 是否启用红色主导防御（仅对 RGB 查询生效）。
  final bool redDefense;

  /// 欧氏候选数：欧氏最近邻不足以代表精确色差最近邻时的兜底宽度。
  final int candidateCount;

  /// 工作空间坐标（按 [distance] 选择：oklab→OKLab，ciede2000→CIELAB）。
  final List<_WorkPoint> _points;

  /// 色卡 CIELAB 值（供后处理/削减等下游使用）。
  final List<LabColor> _labs;

  /// 色卡 OKLab 值（供贪心选色等下游使用）。
  final List<OklabColor> _oklabs;

  late final _KdNode? _root;

  List<LabColor> get labs => _labs;
  List<OklabColor> get oklabs => _oklabs;

  ColorMapper(
    this.palette, {
    this.distance = ColorDistance.ciede2000,
    this.candidateCount = 64,
    this.redDefense = true,
    List<int>? allowedIndices,
  })  : _labs = [for (final e in palette.entries) e.lab],
        _oklabs = [
          for (final e in palette.entries) srgbToOklab(e.r, e.g, e.b),
        ],
        _points = [
          for (final e in palette.entries)
            switch (distance) {
              ColorDistance.oklab => _okWork(e.r, e.g, e.b),
              ColorDistance.ciede2000 => _labWork(e.r, e.g, e.b),
            },
        ] {
    final indices = List<int>.of(
      allowedIndices ?? List<int>.generate(palette.length, (i) => i),
    );
    _root = _buildRec(indices, 0);
  }

  /// 按模式取工作空间点：oklab→OKLab，ciede2000→CIELAB。
  _WorkPoint _rgbWork(int rgb) {
    final r = (rgb >> 16) & 0xFF;
    final g = (rgb >> 8) & 0xFF;
    final b = rgb & 0xFF;
    return switch (distance) {
      ColorDistance.oklab => _okWork(r, g, b),
      ColorDistance.ciede2000 => _labWork(r, g, b),
    };
  }

  static _WorkPoint _okWork(int r, int g, int b) {
    final ok = srgbToOklab(r, g, b);
    return _WorkPoint(ok.l, ok.a, ok.b);
  }

  static _WorkPoint _labWork(int r, int g, int b) {
    final lab = rgbToLab(r, g, b);
    return _WorkPoint(lab.l, lab.a, lab.b);
  }

  _KdNode? _buildRec(List<int> indices, int depth) {
    if (indices.isEmpty) return null;
    final axis = depth % 3;
    indices.sort(
      (a, b) => _coord(_points[a], axis).compareTo(_coord(_points[b], axis)),
    );
    final mid = indices.length ~/ 2;
    final node = _KdNode(_points[indices[mid]], indices[mid]);
    node.left = _buildRec(indices.sublist(0, mid), depth + 1);
    node.right = _buildRec(indices.sublist(mid + 1), depth + 1);
    return node;
  }

  static double _coord(_WorkPoint c, int axis) =>
      axis == 0 ? c.l : (axis == 1 ? c.a : c.b);

  static LabColor _rgbLab(int rgb) =>
      rgbToLab((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);

  /// RGB 查询 → 精确色差（不含红色防御）。
  double distanceRgbToIndex(int rgb, int paletteIndex) {
    switch (distance) {
      case ColorDistance.oklab:
        final q = srgbToOklab(
          (rgb >> 16) & 0xFF,
          (rgb >> 8) & 0xFF,
          rgb & 0xFF,
        );
        return oklabDistance(q, _oklabs[paletteIndex]);
      case ColorDistance.ciede2000:
        return ciede2000(_rgbLab(rgb), _labs[paletteIndex]);
    }
  }

  /// RGB 查询 → 最近色号下标（启用红色防御则叠加罚分）。
  int nearestIndexForRgb(int rgb) {
    if (_root == null) throw StateError('empty palette');
    final candidates = _collectCandidates(_rgbWork(rgb));
    var best = candidates.first;
    var bestDist = double.infinity;
    for (final idx in candidates) {
      final d = distanceRgbToIndex(rgb, idx) +
          (redDefense ? _redPenalty(rgb, idx) : 0.0);
      if (d < bestDist) {
        bestDist = d;
        best = idx;
      }
    }
    return best;
  }

  /// 在 [indices] 子集中找 RGB 查询的最近色号（可选红色防御）。
  int nearestAmongRgb(int rgb, List<int> indices,
      {bool applyRedDefense = true}) {
    var best = indices.first;
    var bestDist = double.infinity;
    for (final idx in indices) {
      final d = distanceRgbToIndex(rgb, idx) +
          (applyRedDefense && redDefense ? _redPenalty(rgb, idx) : 0.0);
      if (d < bestDist) {
        bestDist = d;
        best = idx;
      }
    }
    return best;
  }

  /// 最近邻查询（Lab 输入）：返回色号条目。
  PaletteEntry nearest(LabColor query) {
    return palette.entries[nearestIndex(query)];
  }

  /// 最近邻查询（Lab 输入）：返回色号下标。
  int nearestIndex(LabColor query) {
    if (_root == null) throw StateError('empty palette');
    final q = switch (distance) {
      ColorDistance.oklab => _okWorkFromLab(query),
      ColorDistance.ciede2000 => _WorkPoint(query.l, query.a, query.b),
    };
    final candidates = _collectCandidates(q);
    var best = candidates.first;
    var bestDist = double.infinity;
    for (final idx in candidates) {
      final d = switch (distance) {
        ColorDistance.oklab => oklabDistance(labToOklab(query), _oklabs[idx]),
        ColorDistance.ciede2000 => ciede2000(_labs[idx], query),
      };
      if (d < bestDist) {
        bestDist = d;
        best = idx;
      }
    }
    return best;
  }

  static _WorkPoint _okWorkFromLab(LabColor lab) {
    final ok = labToOklab(lab);
    return _WorkPoint(ok.l, ok.a, ok.b);
  }

  /// 红色主导防御罚分：对强红查询，非红卡条目按 G/B 值加罚（0 起）。
  /// 强红判定：L>30 且 a*>50 且彩度≈a*（C < a*×1.1）。
  double _redPenalty(int rgb, int paletteIndex) {
    final lab = _rgbLab(rgb);
    final chroma = math.sqrt(lab.a * lab.a + lab.b * lab.b);
    final isStrongRed = lab.l > 30 && lab.a > 50 && chroma < lab.a * 1.1;
    if (!isStrongRed) return 0.0;

    final pg = palette.entries[paletteIndex].g;
    final pb = palette.entries[paletteIndex].b;
    var penalty = 0.0;
    if (pg > 80) penalty += (pg - 30) * (pg - 30) * 0.02;
    if (pb > 80) penalty += (pb - 30) * (pb - 30) * 0.02;
    return penalty;
  }

  /// 在欧氏空间收集最多 [candidateCount] 个最近候选（近似）。
  List<int> _collectCandidates(_WorkPoint query) {
    final heap = _MaxHeap(candidateCount);

    void search(_KdNode? node, int depth) {
      if (node == null) return;
      final dist = _distSq(node.point, query);
      heap.add(node.paletteIndex, dist);

      final axis = depth % 3;
      final nodeCoord = _coord(node.point, axis);
      final queryCoord = _coord(query, axis);

      final nearer = queryCoord < nodeCoord ? node.left : node.right;
      final farther = queryCoord < nodeCoord ? node.right : node.left;

      search(nearer, depth + 1);

      final planeDistSq = (queryCoord - nodeCoord) * (queryCoord - nodeCoord);
      if (planeDistSq < heap.worstDist) {
        search(farther, depth + 1);
      }
    }

    search(_root, 0);
    return heap.indices;
  }

  static double _distSq(_WorkPoint a, _WorkPoint b) {
    final dl = a.l - b.l;
    final da = a.a - b.a;
    final db = a.b - b.b;
    return dl * dl + da * da + db * db;
  }
}

/// 固定容量的最大堆（按距离排序，丢弃更远的）。
class _MaxHeap {
  final int capacity;
  final List<(int, double)> _items = [];

  _MaxHeap(this.capacity);

  double get worstDist => _items.isEmpty ? double.infinity : _items.first.$2;

  List<int> get indices => [for (final it in _items) it.$1];

  void add(int index, double dist) {
    if (_items.length < capacity) {
      _items.add((index, dist));
      if (_items.length == capacity) _heapifyAll();
    } else if (dist < _items.first.$2) {
      _items[0] = (index, dist);
      _siftDown(0);
    }
  }

  void _heapifyAll() {
    for (var i = _items.length ~/ 2 - 1; i >= 0; i--) {
      _siftDown(i);
    }
  }

  void _siftDown(int i) {
    while (true) {
      var largest = i;
      final l = 2 * i + 1;
      final r = 2 * i + 2;
      if (l < _items.length && _items[l].$2 > _items[largest].$2) largest = l;
      if (r < _items.length && _items[r].$2 > _items[largest].$2) largest = r;
      if (largest == i) break;
      final tmp = _items[i];
      _items[i] = _items[largest];
      _items[largest] = tmp;
      i = largest;
    }
  }
}
