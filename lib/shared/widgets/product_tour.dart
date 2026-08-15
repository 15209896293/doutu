/// 新手引导（coach marks，反馈：具体到标注点的指引，不再是固定卡片）。
///
/// 每个步骤锚定一个真实 UI 元素（GlobalKey）：全屏压暗 + 目标孔洞高亮 +
/// 指向卡片（磨砂玻璃质感 + 箭头）+ 底部「上一步/下一步/跳过」。
///
/// 作为屏幕自身 widget 树的一部分（Stack 覆盖层）渲染，保证底层页面
/// 保持完整布局，coach mark 锚点才能量取到目标位置。
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 引导步骤：锚定一个真实 UI 元素 + 说明文字。
class CoachStep {
  final GlobalKey targetKey;
  final String icon;
  final String title;
  final String body;

  const CoachStep({
    required this.targetKey,
    required this.icon,
    required this.title,
    required this.body,
  });
}

/// 点对点引导覆盖层。由宿主页面放到其 Stack 顶层，并在完成时回调 [onFinished]。
class CoachTour extends StatefulWidget {
  final List<CoachStep> steps;
  final VoidCallback onFinished;

  const CoachTour({
    super.key,
    required this.steps,
    required this.onFinished,
  });

  @override
  State<CoachTour> createState() => _CoachTourState();
}

class _CoachTourState extends State<CoachTour> {
  int _index = 0;
  Rect? _targetRect;
  int _measureAttempts = 0;

  CoachStep get _step => widget.steps[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final ctx = _step.targetKey.currentContext;
    final box = ctx?.findRenderObject();
    if (box is RenderBox && box.hasSize && box.attached) {
      final tl = box.localToGlobal(Offset.zero);
      setState(() => _targetRect = tl & box.size);
    } else if (_measureAttempts < 5) {
      // 目标尚未布局完成 → 下一帧重试
      _measureAttempts++;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    } else {
      // 目标不可见（如页面被切换）→ 安全结束，不影响 App。
      widget.onFinished();
    }
  }

  void _goTo(int next) {
    if (next < 0 || next >= widget.steps.length) return;
    setState(() {
      _index = next;
      _targetRect = null;
      _measureAttempts = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _finish() => widget.onFinished();

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 磨砂玻璃背景
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(color: const Color(0x4DFFFFFF)),
              ),
            ),
          ),
          // 压暗 + 目标孔洞
          Positioned.fill(
            child: CustomPaint(
              painter: _CoachScrimPainter(target: _targetRect),
            ),
          ),
          // 指向卡片
          if (_targetRect != null) _buildCard(screen),
          // 底部控制
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _buildControls(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Size screen) {
    final target = _targetRect!;
    const cardW = 300.0;
    const cardH = 138.0;
    const margin = 16.0;
    final left = (target.center.dx - cardW / 2)
        .clamp(margin, screen.width - cardW - margin);
    double top;
    final bool arrowUp;
    if (target.bottom + cardH + 72 < screen.height) {
      top = target.bottom + 14;
      arrowUp = true;
    } else if (target.top - cardH - 72 > 0) {
      top = target.top - cardH - 14;
      arrowUp = false;
    } else {
      top = (screen.height - cardH) / 2;
      arrowUp = true;
    }
    final arrowDx = (target.center.dx - left).clamp(16.0, cardW - 16.0);

    return Positioned(
      left: left,
      top: top,
      width: cardW,
      height: cardH,
      child: _glassCard(arrowDx: arrowDx, arrowUp: arrowUp),
    );
  }

  Widget _glassCard({required double arrowDx, required bool arrowUp}) {
    final step = _step;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white, width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.icon, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: const TextStyle(
                        fontFamily: 'WorkSans',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.body,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 指向目标的箭头
        Positioned(
          top: arrowUp ? -7 : null,
          bottom: arrowUp ? null : -7,
          left: arrowDx - 7,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final isLast = _index == widget.steps.length - 1;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _finish,
            child: const Text('跳过'),
          ),
          const SizedBox(width: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.steps.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: i == _index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _index ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
          if (_index > 0)
            TextButton(
              onPressed: () => _goTo(_index - 1),
              child: const Text('上一步'),
            ),
          FilledButton(
            onPressed: isLast ? _finish : () => _goTo(_index + 1),
            child: Text(isLast ? '完成 🎉' : '下一步'),
          ),
        ],
      ),
    );
  }
}

/// 全屏压暗 + 目标孔洞高亮。
class _CoachScrimPainter extends CustomPainter {
  final Rect? target;

  _CoachScrimPainter({required this.target});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(Offset.zero & size);
    if (target != null) {
      path.addRRect(RRect.fromRectAndRadius(target!, const Radius.circular(12)));
    }
    canvas.drawPath(path, Paint()..color = const Color(0x99000000));
    if (target != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(target!, const Radius.circular(12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = AppColors.primary,
      );
    }
  }

  @override
  bool shouldRepaint(_CoachScrimPainter old) => old.target != target;
}
