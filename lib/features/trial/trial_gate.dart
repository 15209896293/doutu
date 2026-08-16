/// 试用门卫：TRIAL_MODE 下根据许可证状态决定显示主应用或全屏锁定/激活页。
///
/// 通过 MaterialApp.router 的 [MaterialApp.builder] 挂载，位于 Navigator 之上：
/// 未解锁时用全屏覆盖层拦截所有页面（「到期全锁」），解锁后放行子应用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/license/license_controller.dart';
import '../../core/license/license_state.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';

/// 试用门卫。
class TrialGate extends ConsumerStatefulWidget {
  final Widget child;

  const TrialGate({super.key, required this.child});

  @override
  ConsumerState<TrialGate> createState() => _TrialGateState();
}

class _TrialGateState extends ConsumerState<TrialGate> {
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    // 记录当前时间（时间回拨检测）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(licenseProvider.notifier).touch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final license = ref.watch(licenseProvider);
    return license.when(
      loading: () => const _TrialSplash(),
      error: (e, _) => _LockScreen(
        title: '😵 初始化失败',
        message: '许可证服务初始化失败：$e\n请重启应用重试。',
      ),
      data: (view) {
        if (!view.unlocked) {
          return _LockScreen(
            title: view.status == LicenseStatus.lockedExpired
                ? '🔒 激活已到期'
                : '🔒 试用已结束',
            message: view.expiresAt == null
                ? '需要激活码才能继续使用'
                : '24 小时试用已于\n${_fmt(view.expiresAt!)} 结束。\n输入激活码即可继续使用。',
          );
        }
        // 解锁：正常使用；试用中时顶部显示剩余时间细条
        if (view.status == LicenseStatus.trialActive && !_bannerDismissed) {
          return Stack(
            children: [
              widget.child,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _TrialBanner(
                  remainingSeconds: view.remainingSeconds,
                  onClose: () => setState(() => _bannerDismissed = true),
                ),
              ),
            ],
          );
        }
        return widget.child;
      },
    );
  }

  static String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// 启动加载页。
class _TrialSplash extends StatelessWidget {
  const _TrialSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: BeadLoader(message: '正在检查许可证…')),
    );
  }
}

/// 全屏锁定 + 激活页。
class _LockScreen extends ConsumerStatefulWidget {
  final String title;
  final String message;

  const _LockScreen({required this.title, required this.message});

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(licenseProvider).valueOrNull;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🧸', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'WorkSans',
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  style: kMonoTextStyle.copyWith(fontSize: 15, letterSpacing: 1.2),
                  decoration: InputDecoration(
                    labelText: '激活码',
                    hintText: 'DOU7D-XXXX-XXXX',
                    prefixIcon: const Icon(Icons.key_rounded,
                        color: AppColors.primary),
                    filled: true,
                    fillColor: AppColors.fill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('🚀 激活',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 12),
                if (_result != null)
                  Text(
                    _result!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _result!.startsWith('✅')
                          ? AppColors.secondary
                          : AppColors.accentOrange,
                    ),
                  ),
                if (view?.activationMessage != null && _result == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    view!.activationMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.accentOrange,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  '本应用为试用版：新安装可免费试用 24 小时。\n'
                  '到期后需输入激活码解锁。\n'
                  '试用与激活状态已联网记录，重装/清除数据不会重置试用期。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _result = '请输入激活码');
      return;
    }
    setState(() {
      _submitting = true;
      _result = null;
    });
    final ok = await ref
        .read(licenseProvider.notifier)
        .activate(code);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _result = ok
          ? (ref.read(licenseProvider).valueOrNull?.activationMessage ??
              '✅ 激活成功')
          : (ref.read(licenseProvider).valueOrNull?.activationMessage ??
              '激活失败，请检查激活码');
    });
  }
}

/// 试用剩余时间细条（试用中显示在顶部）。
class _TrialBanner extends StatelessWidget {
  final int remainingSeconds;
  final VoidCallback onClose;

  const _TrialBanner({
    required this.remainingSeconds,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final text = LicenseEvaluator.formatRemaining(remainingSeconds);
    return Material(
      color: AppColors.primary.withValues(alpha: 0.92),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              const Icon(Icons.timer_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '试用剩余 $text',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: const Icon(Icons.close_rounded,
                    size: 16, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
