/// 跟做模式 · 数字填色（反馈⑥重构）。
///
/// 数字填色：每格标注色号编号，底部图例「编号↔色号↔进度」，
/// 点格子打勾标记已拼，点图例高亮该色剩余格。像填色书一样直观。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../shared/storage/craft_progress_store.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';

class CraftScreen extends ConsumerStatefulWidget {
  const CraftScreen({super.key});

  @override
  ConsumerState<CraftScreen> createState() => _CraftScreenState();
}

/// 图纸实际用到的颜色（按 BOM 顺序）。
class _UsedColor {
  final int index; // palette 下标
  final String code;
  final int count;
  final int color; // 0xRRGGBB

  const _UsedColor(this.index, this.code, this.count, this.color);
}

class _CraftScreenState extends ConsumerState<CraftScreen> {
  /// 已拼好的格（下标）。
  final Set<int> _done = {};

  /// 当前选中高亮的色（palette 下标）。
  int? _selectedIndex;

  /// 当前图纸指纹（用于进度持久化）。
  String? _fingerprint;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final pattern = ref.read(conversionProvider).pattern;
    if (pattern == null) return;
    final fp = craftFingerprint(pattern);
    _fingerprint = fp;
    try {
      final store = await ref.read(craftProgressStoreProvider.future);
      final done = await store.load(fp);
      if (mounted && _fingerprint == fp) {
        setState(() => _done
          ..clear()
          ..addAll(done));
      }
    } catch (_) {
      // 读取失败不影响使用。
    }
  }

  Future<void> _saveProgress() async {
    final fp = _fingerprint;
    if (fp == null) return;
    try {
      final store = await ref.read(craftProgressStoreProvider.future);
      await store.save(fp, _done);
    } catch (_) {
      // 写入失败不影响使用。
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(paletteForPatternProvider).valueOrNull;
    final pattern = ref.watch(conversionProvider).pattern;
    if (palette == null || pattern == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('跟做 · 数字填色')),
        body: const CuteEmptyState(emoji: '🧵', title: '没有可跟做的图纸'),
      );
    }

    final colors = [
      for (final e in palette.entries) (e.r << 16) | (e.g << 8) | e.b,
    ];

    // code → palette 下标
    final codeIndex = <String, int>{};
    for (var i = 0; i < palette.entries.length; i++) {
      codeIndex[palette.entries[i].code] = i;
    }
    final used = <_UsedColor>[
      for (final e in pattern.bom)
        if (codeIndex.containsKey(e.code))
          _UsedColor(codeIndex[e.code]!, e.code, e.count, e.color),
    ];

    // 编号：1..K
    final numberByIndex = <int, int>{};
    for (var k = 0; k < used.length; k++) {
      numberByIndex[used[k].index] = k + 1;
    }

    // 每格编号（透明格 = 0）
    final labels = List<int>.filled(pattern.grid.length, 0);
    for (var i = 0; i < pattern.grid.length; i++) {
      final idx = pattern.grid[i];
      if (idx >= 0) labels[i] = numberByIndex[idx] ?? 0;
    }

    // 各色已完成颗数
    final doneByIndex = <int, int>{};
    for (final i in _done) {
      final idx = pattern.grid[i];
      if (idx >= 0) doneByIndex[idx] = (doneByIndex[idx] ?? 0) + 1;
    }

    // 选中色的剩余格（高亮）
    final highlight = <int>{};
    if (_selectedIndex != null) {
      for (var i = 0; i < pattern.grid.length; i++) {
        if (pattern.grid[i] == _selectedIndex && !_done.contains(i)) {
          highlight.add(i);
        }
      }
    }

    final total = pattern.totalBeads;
    final progress = total == 0 ? 1.0 : _done.length / total;
    final completedColors = used
        .where((u) => (doneByIndex[u.index] ?? 0) >= u.count)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🧵 跟做 · 数字填色'),
        actions: [
          if (_done.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(_done.clear);
                _saveProgress();
              },
              child: const Text('重置'),
            ),
        ],
      ),
      body: Column(
        children: [
          _progressBar(progress, _done.length, total, completedColors, used.length),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _CraftCanvas(
                grid: pattern.grid,
                size: pattern.size,
                height: pattern.height,
                colors: colors,
                labels: labels,
                doneCells: _done,
                highlightCells: highlight,
                onCellTap: (i) {
                  if (pattern.grid[i] < 0) return;
                  hapticTap();
                  setState(() {
                    if (!_done.add(i)) _done.remove(i);
                  });
                  _saveProgress();
                },
              ),
            ),
          ),
          _legend(used, doneByIndex),
        ],
      ),
    );
  }

  Widget _progressBar(
    double progress,
    int done,
    int total,
    int completedColors,
    int totalColors,
  ) {
    final allDone = done >= total && total > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: AppColors.fill,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            allDone
                ? '🎉 全部完成 · 共 $total 颗 · $totalColors 色'
                : '已完成 $done / $total 颗 · 完成 $completedColors / $totalColors 色（${(progress * 100).round()}%）',
            style: TextStyle(
              fontSize: 12,
              fontWeight: allDone ? FontWeight.w700 : FontWeight.w400,
              color: allDone ? AppColors.success : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(List<_UsedColor> used, Map<int, int> doneByIndex) {
    return Container(
      height: 104,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: used.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final u = used[i];
          final number = i + 1;
          final selected = _selectedIndex == u.index;
          final bg = Color(0xFF000000 | u.color);
          final fg =
              bg.computeLuminance() > 0.5 ? AppColors.textMain : Colors.white;
          final doneCount = doneByIndex[u.index] ?? 0;
          final isComplete = doneCount >= u.count;
          final frac = u.count == 0
              ? 0.0
              : (doneCount / u.count).clamp(0.0, 1.0).toDouble();
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              hapticTap();
              setState(() => _selectedIndex = selected ? null : u.index);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : null,
                borderRadius: BorderRadius.circular(12),
                border: selected
                    ? Border.all(color: AppColors.primary, width: 1.5)
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 44,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          u.code,
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ),
                      Positioned(
                        left: -5,
                        top: -5,
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isComplete
                                ? AppColors.success
                                : AppColors.textMain,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$number',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isComplete ? '✅ 完成' : '$doneCount/${u.count}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isComplete
                          ? AppColors.success
                          : AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 44,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 4,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation(
                          isComplete ? AppColors.success : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 可点格的数字填色画布：InteractiveViewer 缩放 + 点击映射到格。
class _CraftCanvas extends StatefulWidget {
  final List<int> grid;
  final int size;

  /// 网格高度（非正方形；默认 == size）。
  final int height;

  final List<int> colors;
  final List<int> labels;
  final Set<int> doneCells;
  final Set<int> highlightCells;
  final ValueChanged<int> onCellTap;

  const _CraftCanvas({
    required this.grid,
    required this.size,
    required this.colors,
    required this.labels,
    required this.doneCells,
    required this.highlightCells,
    required this.onCellTap,
    int? height,
  }) : height = height ?? size;

  @override
  State<_CraftCanvas> createState() => _CraftCanvasState();
}

class _CraftCanvasState extends State<_CraftCanvas> {
  final _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _cellIndex(Offset local, double cell) {
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
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 1,
              maxScale: 16,
              panEnabled: false,
              scaleEnabled: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final i = _cellIndex(d.localPosition, cell);
                  if (i >= 0) widget.onCellTap(i);
                },
                child: SizedBox(
                  width: childW,
                  height: childH,
                  child: CustomPaint(
                    painter: _CraftPainter(
                      grid: widget.grid,
                      size: widget.size,
                      height: widget.height,
                      colors: widget.colors,
                      labels: widget.labels,
                      doneCells: widget.doneCells,
                      highlightCells: widget.highlightCells,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CraftPainter extends CustomPainter {
  final List<int> grid;
  final int size;
  final int height;
  final List<int> colors;
  final List<int> labels;
  final Set<int> doneCells;
  final Set<int> highlightCells;

  _CraftPainter({
    required this.grid,
    required this.size,
    required this.height,
    required this.colors,
    required this.labels,
    required this.doneCells,
    required this.highlightCells,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final cell = canvasSize.width / size;
    final paint = Paint();

    // 色块 / 透明格
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        final idx = grid[i];
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

    // 高亮描边（选中色剩余格）
    if (highlightCells.isNotEmpty) {
      final hp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.primary;
      for (final i in highlightCells) {
        final x = i % size;
        final y = i ~/ size;
        canvas.drawRect(
          Rect.fromLTWH(x * cell + 1, y * cell + 1, cell - 2, cell - 2),
          hp,
        );
      }
    }

    // 数字编号
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        final label = labels[i];
        if (label <= 0) continue;
        final idx = grid[i];
        final bg = idx >= 0 && idx < colors.length
            ? Color(0xFF000000 | colors[idx])
            : Colors.white;
        tp.text = TextSpan(
          text: '$label',
          style: TextStyle(
            fontSize: cell * 0.4,
            fontFamily: 'JetBrainsMono',
            fontWeight: FontWeight.w700,
            color: bg.computeLuminance() > 0.5
                ? AppColors.textMain
                : Colors.white,
          ),
        );
        tp.layout(maxWidth: cell);
        tp.paint(
          canvas,
          Offset(x * cell + (cell - tp.width) / 2, y * cell + (cell - tp.height) / 2),
        );
      }
    }

    // 已完成：遮罩 + 勾
    if (doneCells.isNotEmpty) {
      final ov = Paint()..color = Colors.white.withValues(alpha: 0.6);
      final check = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      for (final i in doneCells) {
        final x = i % size;
        final y = i ~/ size;
        final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        canvas.drawRect(rect, ov);
        check.text = TextSpan(
          text: '✓',
          style: TextStyle(
            fontSize: cell * 0.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF34C759),
          ),
        );
        check.layout(maxWidth: cell);
        check.paint(
          canvas,
          Offset(x * cell + (cell - check.width) / 2, y * cell + (cell - check.height) / 2),
        );
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
  bool shouldRepaint(_CraftPainter old) => true;
}
