/// 首页：选择图片 / 拍照 + 最近作品 + 首次启动新手引导。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../app_providers.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/widgets/product_tour.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  /// 引导是否已触发（避免重复弹出）。
  bool _tourShown = false;

  /// 轻量预检：读取图片尺寸与文件大小，判断是否可能无法分析。
  /// 返回 null 表示正常，否则返回给用户的提示语。
  String? _probeImage(Uint8List bytes) {
    const maxBytes = 25 * 1024 * 1024; // 25MB
    const maxPixels = 24 * 1000 * 1000; // 2400 万像素
    int? w;
    int? h;
    try {
      final decoder = img.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      w = info?.width;
      h = info?.height;
    } catch (_) {
      // 读取头信息失败时不阻塞，交给后续生成兜底。
    }
    if (bytes.length > maxBytes) {
      final sizeMb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      return '文件约 $sizeMb MB，偏大可能无法分析。建议先压缩图片，或裁剪到需要区域后再生成。';
    }
    if (w != null && h != null && (w * h) > maxPixels) {
      final mp = (w * h / 1000000).toStringAsFixed(0);
      return '图片分辨率 $w×$h（约 $mp 百万像素），偏大可能无法分析。建议裁剪到需要区域后再生成。';
    }
    return null;
  }

  /// 弹出新手引导；[markSeen] 为 true 时结束即写 tourSeen。
  Future<void> _launchTour({bool markSeen = false}) async {
    await ProductTour.show(context);
    if (!markSeen || !mounted) return;
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings != null && !settings.tourSeen) {
      try {
        await ref
            .read(settingsProvider.notifier)
            .saveSettings(settings.copyWith(tourSeen: true));
      } catch (_) {
        // 持久化失败不影响使用（下次启动会再次引导）。
      }
    }
  }

  Future<void> _pick(WidgetRef ref, BuildContext context, ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 4000,
        maxHeight: 4000,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final settings = ref.read(settingsProvider).valueOrNull;
      ref.read(conversionProvider.notifier).setImage(bytes, settings: settings);
      final warning = _probeImage(bytes);
      if (!context.mounted) return;
      if (warning != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('图片较大 ⚠️'),
            content: Text(warning),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了，继续裁剪'),
              ),
            ],
          ),
        );
      }
      if (context.mounted) context.push(Routes.crop);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取图片失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;

    // 首次启动自动播放新手引导（只在第一次）。
    if (settings != null && !settings.tourSeen && !_tourShown) {
      _tourShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _launchTour(markSeen: true);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('豆图 · 拼豆图纸转化器'),
        actions: [
          IconButton(
            tooltip: '我的豆子库存',
            icon: const Icon(Icons.inventory_2_rounded),
            onPressed: () => context.push(Routes.inventory),
          ),
          IconButton(
            tooltip: '历史记录',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push(Routes.history),
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 24),
            Text('🧸 把照片变成拼豆图纸', style: kDisplayTextStyle),
            const SizedBox(height: 8),
            const Text(
              '选一张图，豆图帮你算出每个格子的色号',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _bigButton(
                      emoji: '🖼️',
                      label: '从相册选图',
                      color: AppColors.primary,
                      onTap: () => _pick(ref, context, ImageSource.gallery),
                    ),
                    const SizedBox(height: 14),
                    _bigButton(
                      emoji: '📷',
                      label: '拍一张',
                      color: AppColors.secondary,
                      onTap: () => _pick(ref, context, ImageSource.camera),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: const [
                Text('🕘 最近作品',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            history.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => CuteEmptyState(
                emoji: '😵',
                title: '读取失败',
                subtitle: e.toString(),
              ),
              data: (projects) => projects.isEmpty
                  ? const CuteEmptyState(
                      emoji: '🍬',
                      title: '还没有作品',
                      subtitle: '选一张图片开始你的第一幅拼豆图纸吧',
                    )
                  : _recentList(context, ref, projects),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigButton({
    required String emoji,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(backgroundColor: color),
        icon: Text(emoji, style: const TextStyle(fontSize: 20)),
        label: Text(label),
      ),
    );
  }

  Widget _recentList(BuildContext context, WidgetRef ref, List projects) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: projects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final p = projects[i];
          return _recentCard(context, ref, p);
        },
      ),
    );
  }

  Widget _recentCard(BuildContext context, WidgetRef ref, project) {
    return GestureDetector(
      onTap: () {
        ref.read(conversionProvider.notifier).openProject(project);
        context.push(Routes.preview, extra: project);
      },
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MiniPattern(
                size: project.pattern.size,
                grid: project.pattern.grid,
                paletteId: project.pattern.paletteId,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              '${project.pattern.size}×${project.pattern.size} · '
              '${project.pattern.colorCount} 色',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 缩略图（迷你网格）。
class _MiniPattern extends ConsumerWidget {
  final int size;
  final List<int> grid;
  final String paletteId;

  const _MiniPattern({
    required this.size,
    required this.grid,
    required this.paletteId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palettes = ref.watch(palettesProvider);
    return palettes.when(
      loading: () => const Center(child: SizedBox()),
      error: (_, __) => const Center(child: SizedBox()),
      data: (map) {
        final palette = map[paletteId] ?? map.values.first;
        final colors = [
          for (final e in palette.entries) (e.r << 16) | (e.g << 8) | e.b,
        ];
        return CustomPaint(
          painter: _MiniPainter(grid: grid, size: size, colors: colors),
          size: Size.infinite,
        );
      },
    );
  }
}

class _MiniPainter extends CustomPainter {
  final List<int> grid;
  final int size;
  final List<int> colors;

  _MiniPainter({required this.grid, required this.size, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / this.size;
    final paint = Paint();
    for (var y = 0; y < this.size; y++) {
      for (var x = 0; x < this.size; x++) {
        final idx = grid[y * this.size + x];
        if (idx < 0 || idx >= colors.length) continue;
        paint.color = Color(0xFF000000 | colors[idx]);
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell + 0.3, cell + 0.3),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MiniPainter old) =>
      old.grid != grid || old.size != size || old.colors != colors;
}
