/// 图纸预览页：网格图纸 / 原图对比 / 成品模拟 + BOM 面板。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../app_providers.dart';
import '../../core/color_mapper.dart';
import '../../core/pattern_converter.dart';
import '../../models/inventory.dart';
import '../../models/pattern.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/widgets/pattern_canvas.dart';

enum PreviewView { grid, compare, mock }

class PreviewScreen extends ConsumerStatefulWidget {
  const PreviewScreen({super.key});

  @override
  ConsumerState<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends ConsumerState<PreviewScreen> {
  PreviewView _view = PreviewView.grid;
  bool _showCodes = true;
  bool _showBom = true;

  /// 已排除的色号（点掉后自动重映射；空 = 恢复原图）。
  final Set<String> _excludedCodes = {};

  /// 首次排除前快照的原始网格（恢复用）。
  List<int>? _originalGrid;

  @override
  Widget build(BuildContext context) {
    final conv = ref.watch(conversionProvider);
    final palette = ref.watch(paletteForPatternProvider).valueOrNull;
    final pattern = conv.pattern;

    if (pattern == null || palette == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('图纸预览')),
        body: const CuteEmptyState(
          emoji: '🤔',
          title: '还没有生成图纸',
          subtitle: '请先选择图片并生成',
        ),
      );
    }

    final colors = [
      for (final e in palette.entries) (e.r << 16) | (e.g << 8) | e.b,
    ];
    final codes = [for (final e in palette.entries) e.code];

    final inventory = ref.watch(inventoryProvider).valueOrNull;
    final ownedForPalette = inventory?[pattern.paletteId];
    final missing = computeMissing(pattern.bom, ownedForPalette);
    final hasInventory = ownedForPalette != null && ownedForPalette.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('图纸预览 · ${pattern.size}×${pattern.height}'),
        leading: IconButton(
          tooltip: '返回上一步',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
        ),
        actions: [
          IconButton(
            tooltip: '显示色号',
            icon: Icon(
              _showCodes ? Icons.pin_rounded : Icons.pin_outlined,
              color: _showCodes ? AppColors.primary : AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _showCodes = !_showCodes),
          ),
          IconButton(
            tooltip: '用量清单',
            icon: Icon(
              _showBom ? Icons.list_alt_rounded : Icons.list_alt_outlined,
              color: _showBom ? AppColors.primary : AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _showBom = !_showBom),
          ),
        ],
      ),
      body: Column(
        children: [
          _viewSelector(),
          _diagnosticsBanner(conv.diagnostics),
          _inventoryBanner(missing, hasInventory),
          Expanded(child: _buildView(pattern, colors, codes, conv)),
          if (_showBom)
            BomLegend(
              bom: pattern.bom,
              totalBeads: pattern.totalBeads,
              excludedCodes: _excludedCodes,
              onToggleExclude: _toggleExclude,
            ),
        ],
      ),
      bottomNavigationBar: _bottomBar(pattern),
    );
  }

  /// 诊断信息横幅（背景置信度 / 平均映射色差 / 杂色提示）。
  Widget _diagnosticsBanner(ConvertDiagnostics? d) {
    if (d == null) return const SizedBox.shrink();
    final parts = <String>[];
    if (d.backgroundFallback) {
      parts.add('⚠️ 背景与主体颜色相近，已保留原图');
      parts.add('可返回关闭「自动去除背景」或裁剪后再试');
    } else if (d.backgroundDetected) {
      parts.add('🟢 背景已移除（置信度 ${(d.backgroundConfidence * 100).round()}%）');
    } else {
      parts.add('⚪ 未检测到背景');
    }
    parts.add('ΔE ${d.meanMappingDistance.toStringAsFixed(1)}');
    if (d.rareColorCount > 0 || d.singleCellRegionCount > 0) {
      parts.add(
        '杂色 ${d.rareColorCount} 色 / 孤立单格 ${d.singleCellRegionCount}',
      );
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: d.backgroundFallback
            ? AppColors.accentOrange.withValues(alpha: 0.12)
            : AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: d.backgroundFallback
              ? AppColors.accentOrange
              : AppColors.border,
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        children: [
          for (final p in parts)
            Text(
              p,
              style: TextStyle(
                fontSize: 11,
                color: d.backgroundFallback
                    ? AppColors.accentOrange
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  /// 色号排除/恢复：排除后重映射到「已存在且未排除」的最近色。
  void _toggleExclude(String code) {
    final conv = ref.read(conversionProvider);
    final palette = ref.read(paletteForPatternProvider).valueOrNull;
    final pattern = conv.pattern;
    if (palette == null || pattern == null) return;

    setState(() {
      if (!_excludedCodes.add(code)) {
        _excludedCodes.remove(code);
      }
      if (_excludedCodes.isEmpty) {
        // 全部恢复 → 还原原始网格
        if (_originalGrid != null) {
          ref
              .read(conversionProvider.notifier)
              .applyGrid(_originalGrid!, palette);
        }
        _originalGrid = null;
        return;
      }
      // 首次排除：快照原始网格
      _originalGrid ??= List<int>.of(pattern.grid);

      final excludeIdx = <int>{
        for (final c in _excludedCodes)
          for (var i = 0; i < palette.entries.length; i++)
            if (palette.entries[i].code == c) i,
      };
      // 已存在色号（含被排除的）→ 重映射候选 = 已存在 - 已排除
      final used = <int>{
        for (final idx in pattern.grid)
          if (idx >= 0) idx,
      };
      final keep = used.difference(excludeIdx).toList();
      if (keep.isEmpty) {
        _excludedCodes.remove(code);
        return; // 全部排除会导致无色可用，阻止
      }
      final mapper = ColorMapper(
        palette,
        distance: conv.options.colorDistanceMode,
        redDefense: false,
      );
      final keepMap = <int, int>{};
      final newGrid = [
        for (final idx in pattern.grid)
          if (idx < 0)
            -1
          else if (keep.contains(idx))
            idx
          else
            keepMap.putIfAbsent(idx, () {
              final rgb = (palette.entries[idx].r << 16) |
                  (palette.entries[idx].g << 8) |
                  palette.entries[idx].b;
              return mapper.nearestAmongRgb(rgb, keep, applyRedDefense: false);
            }),
      ];
      ref.read(conversionProvider.notifier).applyGrid(newGrid, palette);
    });
  }

  Widget _viewSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _viewChip(PreviewView.grid, '🧩 图纸'),
          _viewChip(PreviewView.compare, '🔄 对比'),
          _viewChip(PreviewView.mock, '✨ 成品模拟'),
        ],
      ),
    );
  }

  Widget _viewChip(PreviewView v, String label) {
    final selected = _view == v;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _view = v),
      ),
    );
  }

  Widget _buildView(
    Pattern pattern,
    List<int> colors,
    List<String> codes,
    ConversionState conv,
  ) {
    final canvasData = PatternCanvasData(
      grid: pattern.grid,
      size: pattern.size,
      height: pattern.height,
      colors: colors,
      codes: codes,
      showCodes: _showCodes,
      mode: _view == PreviewView.mock ? GridRenderMode.round : GridRenderMode.flat,
    );

    switch (_view) {
      case PreviewView.grid:
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: PatternCanvas(data: canvasData, maxScale: 8),
          ),
        );
      case PreviewView.mock:
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: PatternCanvas(data: canvasData, maxScale: 6),
          ),
        );
      case PreviewView.compare:
        return _compareView(pattern, colors, codes, conv);
    }
  }

  /// 原图对比：左右并排（左：原图区域色重建 / 右：图纸）。
  Widget _compareView(
    Pattern pattern,
    List<int> colors,
    List<String> codes,
    ConversionState conv,
  ) {
    if (conv.avgColors.isEmpty) {
      return const CuteEmptyState(
        emoji: '🖼️',
        title: '该作品未保存原图对比',
        subtitle: '已保存的作品仅含图纸，不含原图',
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('原图',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _AvgColorsView(
                      avgColors: conv.avgColors,
                      size: pattern.size,
                      height: pattern.height,
                      backgroundCells: conv.backgroundCells.isEmpty
                          ? null
                          : conv.backgroundCells,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: AppColors.primary.withValues(alpha: 0.4),
          ),
          Expanded(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('图纸',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: PatternCanvas(
                    data: PatternCanvasData(
                      grid: pattern.grid,
                      size: pattern.size,
                      height: pattern.height,
                      colors: colors,
                      codes: codes,
                    ),
                    maxScale: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inventoryBanner(List<MissingBead> missing, bool hasInventory) {
    String emoji;
    String text;
    Color color;
    if (!hasInventory) {
      emoji = '📦';
      text = '录入库存后，可看缺豆提醒';
      color = AppColors.textSecondary;
    } else if (missing.isEmpty) {
      emoji = '✅';
      text = '库存充足，可以开拼';
      color = AppColors.success;
    } else {
      final total = missing.fold<int>(0, (s, m) => s + m.missing);
      emoji = '🛒';
      text = '还缺 ${missing.length} 色 · $total 颗豆子';
      color = AppColors.accentOrange;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: hasInventory && missing.isNotEmpty
            ? () => _showMissingSheet(missing)
            : () => context.push(Routes.inventory),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _showMissingSheet(List<MissingBead> missing) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('🛒 缺豆清单',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: missing.length,
                itemBuilder: (context, i) {
                  final m = missing[i];
                  final bg = Color(0xFF000000 | m.color);
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                    ),
                    title: Text(m.code, style: kMonoTextStyle.copyWith(fontSize: 13)),
                    subtitle: m.name == null
                        ? null
                        : Text(m.name!, style: const TextStyle(fontSize: 12)),
                    trailing: Text(
                      '缺 ${m.missing} 颗',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.accentOrange),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(Pattern pattern) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.push(Routes.editor),
                child: const Text('✏️ 编辑'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.push(Routes.craft),
                child: const Text('🧵 跟做'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () => context.push(Routes.export),
                child: const Text('📤 导出/分享'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 区域平均色重建图（对比视图左半；背景格画棋盘格蒙层）。
class _AvgColorsView extends StatelessWidget {
  final List<int> avgColors;
  final int size;

  /// 网格高度（非正方形；默认 == size）。
  final int height;

  /// 每格是否背景（null = 不显示蒙层）。
  final List<bool>? backgroundCells;

  const _AvgColorsView({
    required this.avgColors,
    required this.size,
    int? height,
    this.backgroundCells,
  }) : height = height ?? size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AvgPainter(
        avgColors: avgColors,
        size: size,
        height: height,
        backgroundCells: backgroundCells,
      ),
      size: Size.infinite,
    );
  }
}

class _AvgPainter extends CustomPainter {
  final List<int> avgColors;
  final int size;
  final int height;
  final List<bool>? backgroundCells;

  _AvgPainter({
    required this.avgColors,
    required this.size,
    required this.height,
    this.backgroundCells,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (avgColors.isEmpty) return;
    final cell = canvasSize.width / size;
    final paint = Paint();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        if (i >= avgColors.length) return;
        final isBg = backgroundCells != null && i < backgroundCells!.length
            ? backgroundCells![i]
            : false;
        if (isBg) {
          // 棋盘格蒙层：将被移除的背景画成半透明棋盘（苹果蓝）
          final dark = (x + y).isEven;
          paint.color = dark
              ? const Color(0x330071E3)
              : const Color(0x110071E3);
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.3, cell + 0.3),
            paint,
          );
          continue;
        }
        paint.color = Color(0xFF000000 | avgColors[i]);
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell + 0.3, cell + 0.3),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_AvgPainter old) =>
      old.avgColors != avgColors ||
      old.size != size ||
      old.height != height ||
      old.backgroundCells != backgroundCells;
}
