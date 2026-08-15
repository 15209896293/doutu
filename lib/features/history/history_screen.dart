/// 历史记录页：最近作品列表，可回看 / 再编辑 / 删除。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../app_providers.dart';
import '../../models/project.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('🕘 历史记录')),
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: BeadLoader()),
          error: (e, _) => CuteEmptyState(
            emoji: '😵',
            title: '读取失败',
            subtitle: e.toString(),
          ),
          data: (projects) => projects.isEmpty
              ? const CuteEmptyState(
                  emoji: '🍬',
                  title: '还没有作品',
                  subtitle: '生成图纸后在导出页点「保存到作品库」',
                )
              : _grid(context, ref, projects),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, WidgetRef ref, List<Project> projects) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: projects.length,
      itemBuilder: (context, i) => _card(context, ref, projects[i]),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, Project project) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ref.read(conversionProvider.notifier).openProject(project);
          context.push(Routes.preview, extra: project);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Thumb(project: project),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${project.pattern.size}×${project.pattern.size} · '
                    '${project.pattern.totalBeads} 颗 · '
                    '${project.pattern.colorCount} 色',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  final Project project;

  const _Thumb({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palettes = ref.watch(palettesProvider);
    return palettes.when(
      loading: () => const Center(child: SizedBox()),
      error: (_, __) => const Center(child: SizedBox()),
      data: (map) {
        final palette = map[project.pattern.paletteId] ?? map.values.first;
        final colors = [
          for (final e in palette.entries) (e.r << 16) | (e.g << 8) | e.b,
        ];
        return CustomPaint(
          painter: _ThumbPainter(
            grid: project.pattern.grid,
            size: project.pattern.size,
            colors: colors,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _ThumbPainter extends CustomPainter {
  final List<int> grid;
  final int size;
  final List<int> colors;

  _ThumbPainter({required this.grid, required this.size, required this.colors});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final cell = canvasSize.width / size;
    final paint = Paint();
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final idx = grid[y * size + x];
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
  bool shouldRepaint(_ThumbPainter old) =>
      old.grid != grid || old.size != size || old.colors != colors;
}
