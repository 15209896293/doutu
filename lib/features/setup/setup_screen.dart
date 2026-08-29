/// 画布与色卡设置页：板型选择 + 色卡切换 + 高级参数 + 生成。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../app_providers.dart';
import '../../core/color_mapper.dart';
import '../../core/palette.dart';
import '../../core/pattern_converter.dart';
import '../../core/sampler.dart';
import '../../models/board_preset.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    final conv = ref.watch(conversionProvider);
    final palettes = ref.watch(palettesProvider);
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('画布与色卡'),
        leading: IconButton(
          tooltip: '返回上一步',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.crop),
        ),
        actions: [
          TextButton(
            onPressed: () => context.go(Routes.home),
            child: const Text('重选图'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionTitle('📐 板型', '选一块拼豆板'),
            _boardSelector(conv),
            const SizedBox(height: 24),
            _sectionTitle('📏 图纸比例', '保持原图比例，不再压成正方形'),
            _ratioSelector(conv),
            const SizedBox(height: 24),
            _sectionTitle('🎨 色卡', '选你手头的豆子品牌'),
            palettes.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: BeadLoader()),
              ),
              error: (e, _) => Text('色卡加载失败：$e'),
              data: (map) => _paletteSelector(map),
            ),
            const SizedBox(height: 24),
            _sectionTitle('✨ 图案细节', '一键切换转换风格，可再微调高级参数'),
            _presetSelector(conv),
            const SizedBox(height: 24),
            _sectionTitle('🛠️ 高级参数', '点击展开微调'),
            Card(
              child: Column(
                children: [
                  InkWell(
                    onTap: () => setState(() => _advancedOpen = !_advancedOpen),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Text(
                            '色数上限 · 抖动 · 去背景 · 色差',
                            style: TextStyle(fontSize: 14),
                          ),
                          const Spacer(),
                          Icon(
                            _advancedOpen
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_advancedOpen) _advancedParams(conv),
                ],
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed:
                  conv.status == ConversionStatus.converting ||
                      conv.imageBytes == null
                  ? null
                  : () => _generate(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                conv.status == ConversionStatus.converting ? '生成中…' : '✨ 生成图纸',
                style: const TextStyle(fontSize: 17),
              ),
            ),
            const SizedBox(height: 12),
            if (conv.status == ConversionStatus.error)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _friendlyError(conv.error),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.accentOrange),
                ),
              ),
            settingsAsync.maybeWhen(
              error: (e, _) =>
                  Text('设置加载失败：$e', style: const TextStyle(fontSize: 11)),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                '豆图 · 纯本地处理，图片不上传 🍃',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 图纸比例：保持原图比例（宽度固定、高度自动）或正方形板型。
  Widget _ratioSelector(ConversionState conv) {
    final keepAspect = conv.options.gridHeight == 0;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            dense: true,
            title: const Text('保持原图比例', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '4:3 / 16:9 / 竖图都不变形',
              style: TextStyle(fontSize: 11),
            ),
            value: keepAspect,
            onChanged: (v) {
              final next = v
                  ? conv.options.copyWith(gridHeight: 0)
                  : conv.options.copyWith(clearGridHeight: true);
              _updateOptions(next);
              _persistSettings();
            },
          ),
          if (keepAspect)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: _sliderRow(
                label: '图纸宽度',
                value: (conv.options.gridSize / 10).toDouble(),
                min: 1,
                max: 26,
                divisions: 25,
                display: '${conv.options.gridSize}',
                onChanged: (v) {
                  final w = (v * 10).round().clamp(10, 256);
                  _updateOptions(conv.options.copyWith(gridSize: w));
                  _persistSettings();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String emoji, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            emoji,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 19,
              color: AppColors.textMain,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 图案细节预设：默认动漫增强，另保留照片/像素风的传统档位。
  Widget _presetSelector(ConversionState conv) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final current = settings?.presetId ?? 'anime';
    const presets = <(String, String, String)>[
      ('anime', '✦ 动漫增强', '线稿五官 · 默认推荐'),
      ('simplified', '⚡ 精简', '8 色内 · 干净利落'),
      ('standard', '✨ 标准', '均衡 · 默认推荐'),
      ('detailed', '🔬 细腻', 'CIEDE2000 最准'),
      ('smooth', '🌊 平滑', '渐变过渡自然'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (id, label, sub) in presets)
          GestureDetector(
            onTap: () {
              hapticTap();
              _applyPreset(id);
            },
            child: Container(
              width: (MediaQuery.of(context).size.width - 56) / 2,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: current == id ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: current == id ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: current == id ? Colors.white : AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 11,
                      color: current == id
                          ? Colors.white.withValues(alpha: 0.9)
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 应用预设（保留用户已选的板型掩码与库存过滤）。
  void _applyPreset(String id) {
    final conv = ref.read(conversionProvider);
    final preset = ConvertPresets.fromId(
      id,
      gridSize: conv.board.size,
      maskShape: conv.board.shape == BoardShape.circle ? 'circle' : null,
      allowedIndices: conv.options.allowedIndices,
    );
    ref
        .read(conversionProvider.notifier)
        .setOptions(
          preset.copyWith(restrictToOwned: conv.options.restrictToOwned),
        );
    _persistSettings();
  }

  Widget _boardSelector(ConversionState conv) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final preset in BoardPreset.presets) _boardCard(conv, preset),
        _customBoardCard(conv),
      ],
    );
  }

  Widget _boardCard(ConversionState conv, BoardPreset preset) {
    final selected = conv.board.id == preset.id;
    return GestureDetector(
      onTap: () {
        hapticTap();
        ref.read(conversionProvider.notifier).setBoard(preset);
        _persistSettings();
      },
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            _BoardGlyph(
              size: preset.size,
              shape: preset.shape,
              selected: selected,
            ),
            const SizedBox(height: 8),
            Text(
              preset.label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? Colors.white : AppColors.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customBoardCard(ConversionState conv) {
    final selected = conv.board.id == 'custom';
    final size = conv.board.id == 'custom' ? conv.board.size : 40;
    return GestureDetector(
      onTap: () {
        hapticTap();
        final current = conv.board;
        final base = current.id == 'custom'
            ? current
            : const BoardPreset(id: 'custom', label: '自定义', size: 40);
        ref.read(conversionProvider.notifier).setBoard(base);
        _editCustomSize(base.size);
      },
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Text(
              '$size',
              style: TextStyle(
                fontFamily: 'WorkSans',
                fontWeight: FontWeight.w700,
                fontSize: 24,
                color: selected ? Colors.white : AppColors.textMain,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '自定义',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? Colors.white : AppColors.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCustomSize(int current) async {
    final controller = TextEditingController(text: '$current');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义板型边长'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText:
                '${BoardPreset.minCustomSize}–${BoardPreset.maxCustomSize}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final clamped = result.clamp(
      BoardPreset.minCustomSize,
      BoardPreset.maxCustomSize,
    );
    ref
        .read(conversionProvider.notifier)
        .setBoard(BoardPreset(id: 'custom', label: '自定义', size: clamped));
    _persistSettings();
  }

  Widget _paletteSelector(Map<String, dynamic> palettes) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final selectedId = settings?.paletteId ?? 'mard_221';
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final id in palettes.keys)
          _paletteCard(palettes[id], id, id == selectedId),
      ],
    );
  }

  Widget _paletteCard(Palette palette, String id, bool selected) {
    return GestureDetector(
      onTap: () async {
        hapticTap();
        final settings = ref.read(settingsProvider).valueOrNull;
        if (settings != null) {
          await ref
              .read(settingsProvider.notifier)
              .saveSettings(settings.copyWith(paletteId: id));
        }
      },
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            _PaletteSwatch(entries: palette.entries),
            const SizedBox(height: 8),
            Text(
              palette.displayName,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? Colors.white : AppColors.textMain,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              palette.source ?? '${palette.length} 色',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: selected
                    ? Colors.white.withValues(alpha: 0.85)
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${palette.length} 色',
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? Colors.white.withValues(alpha: 0.9)
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedParams(ConversionState conv) {
    final options = conv.options;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        children: [
          _sliderRow(
            label: '色数上限',
            value: options.maxColors == 0
                ? 0
                : (options.maxColors / 8).toDouble(),
            min: 0,
            max: 8,
            divisions: 8,
            display: options.maxColors == 0 ? '不限' : '${options.maxColors}',
            onChanged: (v) => _updateOptions(
              options.copyWith(maxColors: v == 0 ? 0 : (v * 8).round()),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('抖动（照片渐变更自然）', style: TextStyle(fontSize: 14)),
            value: options.dither,
            onChanged: (v) => _updateOptions(options.copyWith(dither: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('自动去除背景', style: TextStyle(fontSize: 14)),
            value: options.removeBackground,
            onChanged: (v) =>
                _updateOptions(options.copyWith(removeBackground: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('照片去噪', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '照片噪点/灰蒙蒙时开启，色块更干净',
              style: TextStyle(fontSize: 11),
            ),
            value: options.prefilterSmooth,
            onChanged: (v) =>
                _updateOptions(options.copyWith(prefilterSmooth: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('边缘锐化', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '卡通/描边图更清晰，边缘不糊',
              style: TextStyle(fontSize: 11),
            ),
            value: options.prefilterSharpen,
            onChanged: (v) =>
                _updateOptions(options.copyWith(prefilterSharpen: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('输入增强（颜色更鲜明）', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '提升对比度与饱和度，适合偏灰的照片',
              style: TextStyle(fontSize: 11),
            ),
            value: options.prefilterEnhance,
            onChanged: (v) =>
                _updateOptions(options.copyWith(prefilterEnhance: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('只用手头有的豆子', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '需先在「我的豆子库存」录入',
              style: TextStyle(fontSize: 11),
            ),
            value: options.restrictToOwned,
            onChanged: (v) =>
                _updateOptions(options.copyWith(restrictToOwned: v)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Text('色差档位', style: TextStyle(fontSize: 14)),
                const Spacer(),
                SegmentedButton<ColorDistance>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: ColorDistance.oklab,
                      label: Text('OKLab 感知最快', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: ColorDistance.ciede2000,
                      label: Text(
                        'CIEDE2000 最准',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                  selected: {options.colorDistanceMode},
                  onSelectionChanged: (s) => _updateOptions(
                    options.copyWith(colorDistanceMode: s.first),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: display,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: kMonoTextStyle.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }

  void _updateOptions(ConvertOptions next) {
    ref.read(conversionProvider.notifier).setOptions(next);
  }

  /// 把转换错误转成用户能看懂的话（反馈①：无法分析时给出明确提示）。
  String _friendlyError(String? raw) {
    final e = raw ?? '未知错误';
    if (e.contains('OutOfMemory') ||
        e.contains('内存') ||
        e.contains('too large')) {
      return '图片过大，无法完成分析。请返回重选一张更小的图片，'
          '或裁剪到需要区域后再生成。';
    }
    if (e.contains('解码') ||
        e.contains('FormatException') ||
        e.contains('format')) {
      return '无法识别这张图片的格式（支持 JPG / PNG / HEIC）。'
          '请换一张图片试试。';
    }
    return '生成失败：$e';
  }

  /// 把当前板型与参数回写到用户设置（下次自动记忆）。
  Future<void> _persistSettings() async {
    final conv = ref.read(conversionProvider);
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;
    try {
      await ref
          .read(settingsProvider.notifier)
          .saveSettings(
            settings.copyWith(
              boardId: conv.board.id,
              customBoardSize: conv.board.id == 'custom'
                  ? conv.board.size
                  : settings.customBoardSize,
              maxColors: conv.options.maxColors,
              dither: conv.options.dither,
              removeBackground: conv.options.removeBackground,
              presetId: _presetIdFor(conv),
              colorDistanceMode: conv.options.colorDistanceMode.name,
            ),
          );
    } catch (_) {
      // 持久化失败不影响生成。
    }
  }

  /// 由当前参数反推预设 id（供偏好记忆；未知组合回退 standard）。
  String _presetIdFor(ConversionState conv) {
    final o = conv.options;
    if (o.cellSamplingMode == CellSamplingMode.average) return 'smooth';
    if (o.colorDistanceMode == ColorDistance.ciede2000) return 'detailed';
    if (o.maxColors > 0 && o.maxColors <= 8) return 'simplified';
    return 'standard';
  }

  Future<void> _generate(BuildContext context) async {
    final palette = ref.read(activePaletteProvider).valueOrNull;
    if (palette == null) return;
    await _persistSettings();
    List<int>? allowedIndices;
    final options = ref.read(conversionProvider).options;
    if (options.restrictToOwned) {
      final inventory = ref.read(inventoryProvider).valueOrNull;
      final owned = inventory?[palette.id];
      allowedIndices = [
        for (var i = 0; i < palette.entries.length; i++)
          if ((owned?[palette.entries[i].code] ?? 0) > 0) i,
      ];
      if (allowedIndices.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('你还没有录入库存，请先到「我的豆子库存」录入后再试')),
          );
        }
        return;
      }
    }
    await ref
        .read(conversionProvider.notifier)
        .convert(palette, allowedIndices: allowedIndices);
    if (!context.mounted) return;
    final status = ref.read(conversionProvider).status;
    if (status == ConversionStatus.done) {
      hapticTap();
      context.push(Routes.preview);
    }
  }
}

/// 板型小图（方/圆）。
class _BoardGlyph extends StatelessWidget {
  final int size;
  final BoardShape shape;

  /// 是否选中（选中时格子画白色，便于在蓝色卡片上显示）。
  final bool selected;

  const _BoardGlyph({
    required this.size,
    required this.shape,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(44, 44),
      painter: _BoardGlyphPainter(size: size, shape: shape, selected: selected),
    );
  }
}

class _BoardGlyphPainter extends CustomPainter {
  final int size;
  final BoardShape shape;
  final bool selected;

  _BoardGlyphPainter({
    required this.size,
    required this.shape,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    // 缩略图最多画 32×32 格：128 板若画满 1.6 万格会导致页面卡顿
    const maxCells = 32;
    final int step;
    final int n;
    if (size <= maxCells) {
      step = 1;
      n = size;
    } else {
      step = (size / maxCells).ceil();
      n = (size / step).ceil();
    }
    final cell = canvasSize.width / n;
    final paint = Paint()
      ..color = selected ? Colors.white : AppColors.accentBlue;
    for (var gy = 0; gy < n; gy++) {
      for (var gx = 0; gx < n; gx++) {
        final x = gx * step;
        final y = gy * step;
        if (shape == BoardShape.circle &&
            !BoardPreset.isInsideCircle(x, y, size)) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(gx * cell, gy * cell, cell + 0.3, cell + 0.3),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BoardGlyphPainter old) =>
      old.size != size || old.shape != shape || old.selected != selected;
}

/// 色卡色板预览（取间隔色）。
class _PaletteSwatch extends StatelessWidget {
  final List entries;

  const _PaletteSwatch({required this.entries});

  @override
  Widget build(BuildContext context) {
    final step = (entries.length / 8).ceil().clamp(1, 100);
    final sample = <Color>[
      for (var i = 0; i < entries.length; i += step)
        Color(
          0xFF000000 |
              (entries[i].r << 16) |
              (entries[i].g << 8) |
              entries[i].b,
        ),
    ];
    return SizedBox(
      width: 44,
      height: 16,
      child: Row(
        children: [
          for (final c in sample.take(8))
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c,
                  border: Border.all(color: Colors.white, width: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
