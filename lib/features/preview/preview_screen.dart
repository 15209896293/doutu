/// 图纸预览页：网格图纸 / 原图对比 / 成品模拟 + BOM 面板。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../app_providers.dart';
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
        title: Text('图纸预览 · ${pattern.size}×${pattern.size}'),
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
          _inventoryBanner(missing, hasInventory),
          Expanded(child: _buildView(pattern, colors, codes, conv)),
          if (_showBom)
            BomLegend(bom: pattern.bom, totalBeads: pattern.totalBeads),
        ],
      ),
      bottomNavigationBar: _bottomBar(pattern),
    );
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
      color = AppColors.secondary;
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

/// 区域平均色重建图（对比视图左半）。
class _AvgColorsView extends StatelessWidget {
  final List<int> avgColors;
  final int size;

  const _AvgColorsView({required this.avgColors, required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AvgPainter(avgColors: avgColors, size: size),
      size: Size.infinite,
    );
  }
}

class _AvgPainter extends CustomPainter {
  final List<int> avgColors;
  final int size;

  _AvgPainter({required this.avgColors, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (avgColors.isEmpty) return;
    final cell = canvasSize.width / size;
    final paint = Paint();
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        if (i >= avgColors.length) return;
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
      old.avgColors != avgColors || old.size != size;
}
