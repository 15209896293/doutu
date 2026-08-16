/// 共享小部件：跳动拼豆加载动画、空状态、BOM 面板（苹果官网风格）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../../models/pattern.dart';

/// 跳动的小拼豆加载动画（苹果风格配色：蓝 / 黑 / 灰）。
class BeadLoader extends StatefulWidget {
  final String? message;
  const BeadLoader({super.key, this.message});

  @override
  State<BeadLoader> createState() => _BeadLoaderState();
}

class _BeadLoaderState extends State<BeadLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  static const _colors = [
    AppColors.primary,
    AppColors.secondary,
    Color(0xFF86868B),
    AppColors.primary,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: _bead(i),
                  ),
              ],
            );
          },
        ),
        if (widget.message != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.message!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bead(int i) {
    // 相位差跳动
    final t = (_controller.value * 4 + i) % 4;
    final dy = t < 1 ? -10.0 * (1 - (t - 1).abs()) : 0.0;
    return Transform.translate(
      offset: Offset(0, dy),
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: _colors[i],
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 简洁空状态（苹果风格：大图标 + 加粗标题 + 灰色说明）。
class CuteEmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  final Widget? action;

  const CuteEmptyState({
    super.key,
    required this.emoji,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              emoji,
              style: const TextStyle(
                fontSize: 52,
                shadows: [
                  Shadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'WorkSans',
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: AppColors.textMain,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 用量清单（BOM）面板：色块 + 色号 + 数量。
class BomPanel extends StatelessWidget {
  final List<BomEntry> bom;
  final int totalBeads;
  final void Function(BomEntry entry)? onTap;

  const BomPanel({
    super.key,
    required this.bom,
    required this.totalBeads,
    this.onTap,
  });

  /// 将 BOM 复制为文本（dev-plan 4.3：可复制为文本）。
  static String bomAsText(List<BomEntry> bom, int total) {
    final buffer = StringBuffer('拼豆用量清单\n');
    buffer.writeln('共 $total 颗 · ${bom.length} 色');
    buffer.writeln('--------------------------');
    for (final e in bom) {
      buffer.writeln('${e.code}\t${e.count} 颗');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '🛒 用量清单',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.textMain,
                ),
              ),
              const Spacer(),
              Text(
                '共 $totalBeads 颗 · ${bom.length} 色',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: bom.length,
              itemBuilder: (context, i) {
                final e = bom[i];
                return InkWell(
                  onTap: onTap == null ? null : () => onTap!(e),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Color(0xFF000000 | e.color),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          e.code,
                          style: kMonoTextStyle.copyWith(fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.name ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${e.count}',
                          style: kMonoTextStyle.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 图例式用量清单：图纸下方横向色卡图例，每色色块下方标注颗数。
/// 支持色号排除/恢复（对齐 pixel-beads：点掉不要的色 → 自动重映射）。
class BomLegend extends StatelessWidget {
  final List<BomEntry> bom;
  final int totalBeads;

  /// 已排除的色号集合（显示为置灰 + 斜线）。
  final Set<String> excludedCodes;

  /// 点击色号时回调（null = 不支持排除）。
  final void Function(String code)? onToggleExclude;

  const BomLegend({
    super.key,
    required this.bom,
    required this.totalBeads,
    this.excludedCodes = const {},
    this.onToggleExclude,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: bom.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == 0) return _totalCard();
          return _chip(bom[i - 1]);
        },
      ),
    );
  }

  Widget _totalCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🛒', style: TextStyle(fontSize: 17)),
          const SizedBox(height: 4),
          Text(
            '共 $totalBeads 颗',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: AppColors.textMain,
            ),
          ),
          Text(
            '${bom.length} 色',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BomEntry e) {
    final excluded = excludedCodes.contains(e.code);
    final bg = Color(0xFF000000 | e.color);
    final fg = bg.computeLuminance() > 0.5 ? AppColors.textMain : Colors.white;
    return GestureDetector(
      onTap: onToggleExclude == null ? null : () => onToggleExclude!(e.code),
      child: Opacity(
        opacity: excluded ? 0.35 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 46,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: excluded
                          ? AppColors.accentOrange
                          : AppColors.border,
                      width: excluded ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    e.code,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      decoration:
                          excluded ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (excluded)
                  const Icon(Icons.block_rounded,
                      size: 16, color: AppColors.accentOrange),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              excluded ? '已排除' : '${e.count}颗',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: excluded
                    ? AppColors.accentOrange
                    : AppColors.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 触觉反馈封装（dev-plan 3.5：轻震动）。
Future<void> hapticTap() async {
  await HapticFeedback.lightImpact();
}
