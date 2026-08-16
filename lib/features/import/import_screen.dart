/// 首页：选择图片 / 拍照 + 最近作品 + 首次启动新手引导（苹果官网风格）。
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

  /// 引导覆盖层是否正在显示。
  bool _tourVisible = false;

  /// 新手引导锚点（coach marks 目标）。
  final _keyPickGallery = GlobalKey();
  final _keyPickCamera = GlobalKey();
  final _keyRecent = GlobalKey();
  final _keyInventory = GlobalKey();
  final _keyHistory = GlobalKey();
  final _keySettings = GlobalKey();

  List<CoachStep> get _homeSteps => [
        CoachStep(
          targetKey: _keyPickGallery,
          icon: '🖼️',
          title: '选一张图',
          body: '从相册选一张照片，豆图会自动算出每个格子的色号与用量，全程本地处理。',
        ),
        CoachStep(
          targetKey: _keyPickCamera,
          icon: '📷',
          title: '也可以拍一张',
          body: '直接拍照，同样能转成拼豆图纸。',
        ),
        CoachStep(
          targetKey: _keyRecent,
          icon: '🍬',
          title: '最近作品',
          body: '保存过的作品会显示在这里，点开就能接着拼。',
        ),
        CoachStep(
          targetKey: _keyInventory,
          icon: '📦',
          title: '我的豆子库存',
          body: '先录入你手头的豆子，生成图纸时会提醒你还缺哪些色、缺几颗。',
        ),
        CoachStep(
          targetKey: _keyHistory,
          icon: '🕘',
          title: '历史记录',
          body: '所有作品都在这里，可以回看或删除。',
        ),
        CoachStep(
          targetKey: _keySettings,
          icon: '⚙️',
          title: '设置',
          body: '默认色卡与板型、再看一遍引导，都在这里。',
        ),
      ];

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

  /// 引导完成：隐藏覆盖层，并标记"已看过"。
  void _onTourFinished() {
    setState(() => _tourVisible = false);
    _markTourSeen();
  }

  Future<void> _markTourSeen() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || settings.tourSeen) return;
    try {
      await ref
          .read(settingsProvider.notifier)
          .saveSettings(settings.copyWith(tourSeen: true));
    } catch (_) {
      // 持久化失败不影响使用（下次启动会再次引导）。
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
        if (mounted) setState(() => _tourVisible = true);
      });
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('豆图 · 拼豆图纸转化器'),
            actions: [
              IconButton(
                key: _keyInventory,
                tooltip: '我的豆子库存',
                icon: const Icon(Icons.inventory_2_rounded),
                onPressed: () => context.push(Routes.inventory),
              ),
              IconButton(
                key: _keyHistory,
                tooltip: '历史记录',
                icon: const Icon(Icons.history_rounded),
                onPressed: () => context.push(Routes.history),
              ),
              IconButton(
                key: _keySettings,
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
                const SizedBox(height: 28),
                // 苹果式 hero 大标题
                Text('把照片变成拼豆图纸', style: kDisplayTextStyle),
                const SizedBox(height: 10),
                const Text(
                  '选一张图，豆图帮你算出每个格子的色号',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.sectionBg,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      _bigButton(
                        key: _keyPickGallery,
                        emoji: '🖼️',
                        label: '从相册选图',
                        filled: true,
                        onTap: () => _pick(ref, context, ImageSource.gallery),
                      ),
                      const SizedBox(height: 12),
                      _bigButton(
                        key: _keyPickCamera,
                        emoji: '📷',
                        label: '拍一张',
                        filled: false,
                        onTap: () => _pick(ref, context, ImageSource.camera),
                      ),
                    ],
                  ),
                ),
                // 可选：选图后自动框出主体（默认关）。
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  dense: true,
                  title: const Text('✨ 选图后自动框出主体',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMain,
                      )),
                  subtitle: const Text('可选步骤：进裁剪页时自动框选主体',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      )),
                  value: settings?.autoFrameSubject ?? false,
                  onChanged: (v) {
                    final s = settings;
                    if (s == null) return;
                    ref
                        .read(settingsProvider.notifier)
                        .saveSettings(s.copyWith(autoFrameSubject: v));
                  },
                ),
                const SizedBox(height: 36),
                Row(
                  key: _keyRecent,
                  children: const [
                    Text('🕘 最近作品',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: AppColors.textMain,
                        )),
                  ],
                ),
                const SizedBox(height: 14),
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
        ),
        if (_tourVisible)
          Positioned.fill(
            child: CoachTour(steps: _homeSteps, onFinished: _onTourFinished),
          ),
      ],
    );
  }

  Widget _bigButton({
    Key? key,
    required String emoji,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: filled
          ? ElevatedButton.icon(
              key: key,
              onPressed: onTap,
              icon: Text(emoji, style: const TextStyle(fontSize: 19)),
              label: Text(label),
            )
          : ElevatedButton.icon(
              key: key,
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8F1FC),
                foregroundColor: AppColors.primary,
              ),
              icon: Text(emoji, style: const TextStyle(fontSize: 19)),
              label: Text(label),
            ),
    );
  }

  Widget _recentList(BuildContext context, WidgetRef ref, List projects) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: projects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
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
        width: 136,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MiniPattern(
                size: project.pattern.size,
                height: project.pattern.height,
                grid: project.pattern.grid,
                paletteId: project.pattern.paletteId,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.textMain,
              ),
            ),
            Text(
              '${project.pattern.size}×${project.pattern.height} · '
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

  /// 网格高度（非正方形；默认 == size）。
  final int height;

  final List<int> grid;
  final String paletteId;

  const _MiniPattern({
    required this.size,
    required this.grid,
    required this.paletteId,
    int? height,
  }) : height = height ?? size;

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
          painter: _MiniPainter(
            grid: grid,
            size: size,
            height: height,
            colors: colors,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _MiniPainter extends CustomPainter {
  final List<int> grid;
  final int size;
  final int height;
  final List<int> colors;

  _MiniPainter({
    required this.grid,
    required this.size,
    required this.height,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / this.size;
    final paint = Paint();
    for (var y = 0; y < height; y++) {
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
      old.grid != grid ||
      old.size != size ||
      old.height != height ||
      old.colors != colors;
}
