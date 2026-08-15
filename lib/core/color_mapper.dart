/// KD-tree 加速的色卡最近邻映射。
///
/// 将 RGB 颜色映射到色卡中最接近（CIEDE2000 ΔE00）的色号。
/// 策略：KD-tree 在 CIELAB 欧氏空间收集 top-K 候选（近似剪枝），
/// 再对候选做精确 ΔE00 终选 —— 兼顾速度与准确性。
library;

import 'ciede2000.dart';
import 'color_space.dart';
import 'palette.dart';

/// Lab 空间 KD-tree 节点。
class _KdNode {
  final LabColor point;
  final int paletteIndex;
  _KdNode? left;
  _KdNode? right;

  _KdNode(this.point, this.paletteIndex);
}

/// 色卡映射器。
class ColorMapper {
  final Palette palette;
  final List<LabColor> _labs;
  late final _KdNode? _root;

  /// 色卡 Lab 值（供后处理/削减等下游使用）。
  List<LabColor> get labs => _labs;

  /// 欧氏候选数：欧氏最近邻不足以代表 ΔE00 最近邻时的兜底宽度。
  /// 32 个候选在 CIEDE2000 与 Lab 欧氏距离的分布差异下足够鲁棒。
  final int candidateCount;

  ColorMapper(this.palette, {this.candidateCount = 64, List<int>? allowedIndices})
      : _labs = [for (final e in palette.entries) e.lab] {
    final indices = List<int>.of(
      allowedIndices ?? List<int>.generate(palette.length, (i) => i),
    );
    _root = _buildRec(indices, 0);
  }

  _KdNode? _buildRec(List<int> indices, int depth) {
    if (indices.isEmpty) return null;
    final axis = depth % 3;
    indices.sort((a, b) => _coord(_labs[a], axis).compareTo(_coord(_labs[b], axis)));
    final mid = indices.length ~/ 2;
    final node = _KdNode(_labs[indices[mid]], indices[mid]);
    node.left = _buildRec(indices.sublist(0, mid), depth + 1);
    node.right = _buildRec(indices.sublist(mid + 1), depth + 1);
    return node;
  }

  static double _coord(LabColor c, int axis) =>
      axis == 0 ? c.l : (axis == 1 ? c.a : c.b);

  /// 最近邻查询：返回色号条目（对候选做精确 ΔE00）。
  PaletteEntry nearest(LabColor query) {
    return palette.entries[nearestIndex(query)];
  }

  /// 最近邻查询：返回色号下标。
  int nearestIndex(LabColor query) {
    if (_root == null) throw StateError('empty palette');
    final candidates = _collectCandidates(query);
    var best = candidates.first;
    var bestDist = double.infinity;
    for (final idx in candidates) {
      final d = ciede2000(_labs[idx], query);
      if (d < bestDist) {
        bestDist = d;
        best = idx;
      }
    }
    return best;
  }

  /// 在欧氏空间收集最多 [candidateCount] 个最近候选（近似）。
  List<int> _collectCandidates(LabColor query) {
    // 最大堆：按欧氏距离平方排序，保留最近 K 个。
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

      // 若到分割平面的距离小于堆中第 K 远，另一侧仍可能有更近点。
      final planeDistSq = (queryCoord - nodeCoord) * (queryCoord - nodeCoord);
      if (planeDistSq < heap.worstDist) {
        search(farther, depth + 1);
      }
    }

    search(_root, 0);
    return heap.indices;
  }

  static double _distSq(LabColor a, LabColor b) {
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
