/// 新手引导（product tour）：磨砂玻璃质感 · 透明背景卡片（反馈⑦）。
///
/// 全屏覆盖当前页面：BackdropFilter 磨砂模糊底层内容，中央玻璃卡片
/// 分步讲解完整使用流程。纯覆盖层实现，不改变路由、不影响 App 逻辑；
/// 首次启动自动播放（首页触发），设置页可随时重看。
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 引导步骤。
class TourStep {
  final String icon;
  final String title;
  final String body;

  const TourStep(this.icon, this.title, this.body);
}

/// 磨砂玻璃新手引导覆盖层。
class ProductTour extends StatefulWidget {
  const ProductTour({super.key});

  /// 在当前页面上弹出引导覆盖层。
  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '新手引导',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, __) => const ProductTour(),
    );
  }

  @override
  State<ProductTour> createState() => _ProductTourState();
}

class _ProductTourState extends State<ProductTour> {
  int _step = 0;

  static const _steps = <TourStep>[
    TourStep('🖼️', '把照片变成拼豆图纸',
        '选一张图，豆图自动算出每个格子的色号与用量。\n图片全程本地处理，不上传任何服务器。'),
    TourStep('✂️', '裁剪到想要的区域',
        '框出你想拼的部分，支持 1:1、4:3、3:4 与自由比例。\n大图会先提醒你裁剪，避免分析失败。'),
    TourStep('📐', '选板型与色卡',
        '挑一块拼豆板（29 / 52 / 81 / 128）和你手头的豆子品牌，\n出图更贴合实际材料。'),
    TourStep('✨', '一键生成图纸',
        '区域采样 + CIEDE2000 精准映射 + 误差扩散渐变优化 + 去杂色，\n大图纸在后台计算，不卡界面。'),
    TourStep('🔍', '预览与用量清单',
        '默认显示每个格子的色号数字，图纸下方是图例式用量清单，\n点右上角图标可随时隐藏。'),
    TourStep('🧵', '数字填色跟做',
        '每格标注编号，点格子打勾记录进度；\n点底部图例可高亮该色剩余格子，照着拼就行。'),
    TourStep('📤', '导出与保存',
        '导出高清 PNG / PDF、分享给好友，\n或保存到作品库，随时回看继续编辑。'),
  ];

  void _finish() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final s = _steps[_step];
    final isLast = _step == _steps.length - 1;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 磨砂玻璃背景：模糊 + 半透明白
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(color: const Color(0x2EFFFFFF)),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: _glassCard(s, isLast),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard(TourStep s, bool isLast) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.4,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 32,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.icon, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 14),
          Text(
            s.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'WorkSans',
              fontWeight: FontWeight.w700,
              fontSize: 19,
              color: AppColors.textMain,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            s.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _steps.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _step ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _step ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: _finish,
                child: const Text('跳过'),
              ),
              const Spacer(),
              if (_step > 0) ...[
                TextButton(
                  onPressed: () => setState(() => _step--),
                  child: const Text('上一步'),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton(
                onPressed: isLast ? _finish : () => setState(() => _step++),
                child: Text(isLast ? '完成 🎉' : '下一步'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
