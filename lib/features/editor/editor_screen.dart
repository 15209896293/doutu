/// 图纸编辑器：画笔 / 橡皮 / 取色 / 填充 / 色号替换，10 步撤销重做。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import '../../core/palette.dart';
import '../../models/pattern.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';

enum EditorTool { pencil, eraser, picker, fill, replace }

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  EditorTool _tool = EditorTool.pencil;
  int _selectedColor = 0;
  final _undoStack = <_EditOp>[];
  final _redoStack = <_EditOp>[];

  /// 当前编辑中的网格。
  late List<int> _grid;
  var _gridInitialized = false;

  /// 是否显示全部色卡色号（否则只显示图纸用到的）。
  bool _showAllColors = false;

  List<int> get _workingGrid {
    final edited = ref.read(conversionProvider).editedGrid;
    if (edited != null) return edited;
    final pattern = ref.read(conversionProvider).pattern;
    return List<int>.of(pattern?.grid ?? const []);
  }

  void _ensureGrid() {
    if (!_gridInitialized) {
      _grid = _workingGrid;
      _gridInitialized = true;
    }
  }

  void _pushGrid(List<int> next) {
    ref.read(conversionProvider.notifier).setEditedGrid(next);
  }

  void _apply(int index, int newValue) {
    _ensureGrid();
    final old = _grid[index];
    if (old == newValue) return;
    _undoStack.add(_EditOp(index, old, newValue));
    if (_undoStack.length > 10) _undoStack.removeAt(0);
    _redoStack.clear();
    _grid = List<int>.of(_grid);
    _grid[index] = newValue;
    _pushGrid(_grid);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _ensureGrid();
    final op = _undoStack.removeLast();
    _redoStack.add(op);
    if (op.gridBefore != null) {
      _grid = List<int>.of(op.gridBefore!);
    } else {
      _grid = List<int>.of(_grid);
      _grid[op.index] = op.oldValue;
    }
    _pushGrid(_grid);
    hapticTap();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _ensureGrid();
    final op = _redoStack.removeLast();
    _undoStack.add(op);
    if (op.gridAfter != null) {
      _grid = List<int>.of(op.gridAfter!);
    } else {
      _grid = List<int>.of(_grid);
      _grid[op.index] = op.newValue;
    }
    _pushGrid(_grid);
    hapticTap();
  }

  /// 镜像翻转（水平）：熨烫「摆反图、烫正图」刚需。
  void _mirrorFlip() {
    _ensureGrid();
    final p = (ref.read(conversionProvider).pattern)!;
    final n = p.size;
    final m = p.height;
    final before = List<int>.of(_grid);
    final next = List<int>.of(_grid);
    for (var y = 0; y < m; y++) {
      for (var x = 0; x < n; x++) {
        next[y * n + x] = before[y * n + (n - 1 - x)];
      }
    }
    _undoStack.add(_EditOp.grid(before, next));
    if (_undoStack.length > 10) _undoStack.removeAt(0);
    _redoStack.clear();
    _grid = next;
    _pushGrid(_grid);
    hapticTap();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(paletteForPatternProvider).valueOrNull;
    final pattern = ref.watch(conversionProvider).pattern;
    if (palette == null || pattern == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('编辑器')),
        body: const CuteEmptyState(emoji: '🤔', title: '没有可编辑的图纸'),
      );
    }
    _ensureGrid();

    final colors = [
      for (final e in palette.entries) (e.r << 16) | (e.g << 8) | e.b,
    ];
    final codes = [for (final e in palette.entries) e.code];

    return Scaffold(
      appBar: AppBar(
        title: const Text('✏️ 编辑器'),
        actions: [
          IconButton(
            tooltip: '镜像翻转（水平）',
            icon: const Icon(Icons.flip_rounded),
            onPressed: _mirrorFlip,
          ),
          IconButton(
            tooltip: '撤销',
            icon: const Icon(Icons.undo_rounded),
            onPressed: _undoStack.isEmpty ? null : _undo,
          ),
          IconButton(
            tooltip: '重做',
            icon: const Icon(Icons.redo_rounded),
            onPressed: _redoStack.isEmpty ? null : _redo,
          ),
          TextButton(
            onPressed: () {
              ref.read(conversionProvider.notifier).commitEdit(palette);
              hapticTap();
              if (context.mounted) context.pop();
            },
            child: const Text('完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildCanvas(colors, codes)),
          _toolBar(colors, codes, pattern),
          _colorBar(palette, pattern),
        ],
      ),
    );
  }

  Widget _buildCanvas(List<int> colors, List<String> codes) {
    final p = (ref.read(conversionProvider).pattern)!;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: _EditorCanvas(
        grid: _grid,
        size: p.size,
        height: p.height,
        colors: colors,
        codes: codes,
        tool: _tool,
        selectedColor: _selectedColor,
        onCell: (index) => _onCell(index, colors),
      ),
    );
  }

  void _onCell(int index, List<int> colors) {
    switch (_tool) {
      case EditorTool.pencil:
        _apply(index, _selectedColor);
      case EditorTool.eraser:
        _apply(index, -1);
      case EditorTool.picker:
        final v = _grid[index];
        if (v >= 0) {
          setState(() {
            _selectedColor = v;
            _tool = EditorTool.pencil;
          });
        }
      case EditorTool.fill:
        _fill(index, _selectedColor);
      case EditorTool.replace:
        final oldColor = _grid[index];
        if (oldColor >= 0) _replaceAll(oldColor, _selectedColor);
    }
  }

  void _fill(int index, int newColor) {
    _ensureGrid();
    final oldColor = _grid[index];
    if (oldColor == newColor) return;
    final p = (ref.read(conversionProvider).pattern)!;
    final size = p.size;
    final height = p.height;
    final visited = List<bool>.filled(_grid.length, false);
    final queue = <int>[index];
    visited[index] = true;
    var head = 0;
    while (head < queue.length) {
      final cur = queue[head++];
      final cx = cur % size;
      final cy = cur ~/ size;
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (nx < 0 || ny < 0 || nx >= size || ny >= height) continue;
        final ni = ny * size + nx;
        if (!visited[ni] && _grid[ni] == oldColor) {
          visited[ni] = true;
          queue.add(ni);
        }
      }
    }
    _undoStack.add(_EditOp.fill(_grid, queue, newColor));
    if (_undoStack.length > 10) _undoStack.removeAt(0);
    _redoStack.clear();
    _grid = List<int>.of(_grid);
    for (final i in queue) {
      _grid[i] = newColor;
    }
    _pushGrid(_grid);
  }

  void _replaceAll(int oldColor, int newColor) {
    _ensureGrid();
    if (oldColor == newColor) return;
    final affected = <int>[];
    for (var i = 0; i < _grid.length; i++) {
      if (_grid[i] == oldColor) affected.add(i);
    }
    if (affected.isEmpty) return;
    _undoStack.add(_EditOp.replaceAll(_grid, affected, oldColor));
    if (_undoStack.length > 10) _undoStack.removeAt(0);
    _redoStack.clear();
    _grid = List<int>.of(_grid);
    for (final i in affected) {
      _grid[i] = newColor;
    }
    _pushGrid(_grid);
  }

  Widget _toolBar(List<int> colors, List<String> codes, Pattern pattern) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _toolButton(EditorTool.pencil, '🖊️', '画笔'),
          _toolButton(EditorTool.eraser, '🧽', '橡皮'),
          _toolButton(EditorTool.picker, '💉', '取色'),
          _toolButton(EditorTool.fill, '🪣', '填充'),
          _toolButton(EditorTool.replace, '🔄', '替换'),
        ],
      ),
    );
  }

  Widget _toolButton(EditorTool tool, String emoji, String label) {
    final selected = _tool == tool;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        hapticTap();
        setState(() => _tool = tool);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorBar(Palette palette, Pattern pattern) {
    // 图纸用到的色号（排序）+ 可展开全部
    final usedIdx = _grid.where((i) => i >= 0).toSet().toList()..sort();
    final shown = _showAllColors
        ? List<int>.generate(palette.length, (i) => i)
        : usedIdx;

    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final idx = shown[i];
                final e = palette.entries[idx];
                final selected = _selectedColor == idx;
                return GestureDetector(
                  onTap: () {
                    hapticTap();
                    setState(() => _selectedColor = idx);
                  },
                  child: Container(
                    width: 40,
                    decoration: BoxDecoration(
                      color: Color(0xFF000000 | (e.r << 16) | (e.g << 8) | e.b),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? AppColors.accentYellow
                            : AppColors.border,
                        width: selected ? 3 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        e.code,
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'JetBrainsMono',
                          color: (Color(0xFF000000 |
                                      (e.r << 16) |
                                      (e.g << 8) |
                                      e.b))
                                  .computeLuminance() >
                              0.5
                              ? AppColors.textMain
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          InkWell(
            onTap: () => setState(() => _showAllColors = !_showAllColors),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                _showAllColors
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单次编辑操作（撤销单元）。
class _EditOp {
  final int index;
  final int oldValue;
  final int newValue;

  /// 批量操作：全部受影响格 + 原色。
  final List<int>? batchIndices;
  final int? batchOldValue;

  /// 整网格操作（镜像翻转）：撤销/重做的完整快照。
  final List<int>? gridBefore;
  final List<int>? gridAfter;

  _EditOp(this.index, this.oldValue, this.newValue)
      : batchIndices = null,
        batchOldValue = null,
        gridBefore = null,
        gridAfter = null;

  _EditOp.fill(List<int> grid, List<int> indices, this.newValue)
      : index = indices.first,
        oldValue = grid[indices.first],
        batchIndices = indices,
        batchOldValue = grid[indices.first],
        gridBefore = null,
        gridAfter = null;

  _EditOp.replaceAll(List<int> grid, List<int> indices, int oldValue)
      : index = indices.first,
        oldValue = oldValue,
        newValue = grid[indices.first],
        batchIndices = indices,
        batchOldValue = oldValue,
        gridBefore = null,
        gridAfter = null;

  _EditOp.grid(this.gridBefore, this.gridAfter)
      : index = 0,
        oldValue = 0,
        newValue = 0,
        batchIndices = null,
        batchOldValue = null;
}

/// 可交互网格画布：InteractiveViewer 缩放 + 点击/拖动映射到格坐标。
class _EditorCanvas extends StatefulWidget {
  final List<int> grid;
  final int size;

  /// 网格高度（非正方形；默认 == size）。
  final int height;

  final List<int> colors;
  final List<String> codes;
  final EditorTool tool;
  final int selectedColor;
  final ValueChanged<int> onCell;

  const _EditorCanvas({
    required this.grid,
    required this.size,
    required this.colors,
    required this.codes,
    required this.tool,
    required this.selectedColor,
    required this.onCell,
    int? height,
  }) : height = height ?? size;

  @override
  State<_EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<_EditorCanvas> {
  final _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details, double cell) {
    final idx = _cellIndex(details.localPosition, cell);
    if (idx >= 0) widget.onCell(idx);
  }

  void _handlePanStart(DragStartDetails details, double cell) {
    final idx = _cellIndex(details.localPosition, cell);
    if (idx >= 0) widget.onCell(idx);
  }

  void _handlePanUpdate(DragUpdateDetails details, double cell) {
    final idx = _cellIndex(details.localPosition, cell);
    if (idx >= 0) widget.onCell(idx);
  }

  int _cellIndex(Offset local, double cell) {
    // 视口坐标 → child 坐标（逆变换）
    final p = MatrixUtils.transformPoint(
      Matrix4.inverted(_controller.value),
      local,
    );
    final x = p.dx ~/ cell;
    final y = p.dy ~/ cell;
    final h = widget.height;
    if (x < 0 || y < 0 || x >= widget.size || y >= h) return -1;
    return y * widget.size + x;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = constraints.maxWidth / widget.size;
        final childW = cell * widget.size;
        final childH = cell * (widget.height);
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            color: Colors.white,
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _controller,
                  minScale: 1,
                  maxScale: 16,
                  panEnabled: false,
                  scaleEnabled: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _handleTapDown(d, cell),
                    onPanStart: (d) => _handlePanStart(d, cell),
                    onPanUpdate: (d) => _handlePanUpdate(d, cell),
                    child: SizedBox(
                      width: childW,
                      height: childH,
                      child: CustomPaint(
                        painter: _EditorPainter(
                          grid: widget.grid,
                          size: widget.size,
                          height: widget.height,
                          colors: widget.colors,
                          codes: widget.codes,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EditorPainter extends CustomPainter {
  final List<int> grid;
  final int size;
  final int height;
  final List<int> colors;
  final List<String> codes;

  _EditorPainter({
    required this.grid,
    required this.size,
    required this.height,
    required this.colors,
    required this.codes,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final cell = canvasSize.width / size;
    final paint = Paint();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < size; x++) {
        final idx = grid[y * size + x];
        final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        if (idx >= 0 && idx < colors.length) {
          paint.color = Color(0xFF000000 | colors[idx]);
          canvas.drawRect(rect, paint);
        } else {
          paint.color = const Color(0x0A000000);
          canvas.drawRect(rect, paint);
        }
      }
    }
    // 网格线：细线 + 每 5 格中粗 + 每 10 格大粗（辅助定位，苹果蓝）
    final fine = Paint()..color = const Color(0x140071E3);
    final mid = Paint()
      ..color = const Color(0x330071E3)
      ..strokeWidth = 1.2;
    final bold = Paint()
      ..color = const Color(0x660071E3)
      ..strokeWidth = 2.0;
    Paint line(int i) => i % 10 == 0 ? bold : (i % 5 == 0 ? mid : fine);
    for (var i = 0; i <= size; i++) {
      canvas.drawLine(
        Offset(i * cell, 0),
        Offset(i * cell, canvasSize.height),
        line(i),
      );
    }
    for (var i = 0; i <= height; i++) {
      canvas.drawLine(
        Offset(0, i * cell),
        Offset(canvasSize.width, i * cell),
        line(i),
      );
    }
  }

  @override
  bool shouldRepaint(_EditorPainter old) =>
      old.grid != grid || old.size != size || old.height != height;
}
