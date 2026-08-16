/// 许可证控制器：试用状态机 + 持久化 + Supabase 同步。
///
/// 仅在 TRIAL_MODE 编译时启用（正式版不含此逻辑）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../shared/storage/app_storage.dart';
import 'license_gateway.dart';
import 'license_state.dart';

/// 许可证视图状态。
class LicenseView {
  final LicenseStatus status;

  /// 生效的当前时间（含回拨校正）。
  final DateTime effectiveNow;

  /// 到期时间（试用或激活；null = 未知）。
  final DateTime? expiresAt;

  /// 剩余秒数。
  final int remainingSeconds;

  /// 是否正在与服务器同步。
  final bool syncing;

  /// 激活提交中。
  final bool activating;

  /// 激活结果消息（成功/失败）。
  final String? activationMessage;

  /// 是否激活成功（用于弹提示）。
  final bool activationSuccess;

  const LicenseView({
    required this.status,
    required this.effectiveNow,
    this.expiresAt,
    this.remainingSeconds = 0,
    this.syncing = false,
    this.activating = false,
    this.activationMessage,
    this.activationSuccess = false,
  });

  bool get unlocked =>
      status == LicenseStatus.trialActive || status == LicenseStatus.activated;
}

/// 许可证 Notifier。
class LicenseController extends AsyncNotifier<LicenseView> {
  static const _path = 'license.json';
  LicenseState _state = LicenseState.empty;
  SupabaseLicenseGateway? _gateway;
  String? _fingerprint;
  Timer? _ticker;

  bool get _enabled => const bool.fromEnvironment('TRIAL_MODE');

  @override
  Future<LicenseView> build() async {
    if (!_enabled) {
      // 非试用版：直接放行（保持 Riverpod 状态一致性）
      return LicenseView(
        status: LicenseStatus.activated,
        effectiveNow: DateTime.now(),
      );
    }
    final storage = await ref.watch(appStorageProvider.future);
    _state = licenseStateFromJson(await storage.readText(_path));
    _gateway = SupabaseLicenseGateway(LicenseGatewayConfig.fromEnvironment);

    // 每秒刷新剩余时间（倒计时）
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    ref.onDispose(() => _ticker?.cancel());

    // 同步服务器（设备注册/状态恢复）；失败降级本地
    unawaited(_sync(storage));
    return _evaluate();
  }

  /// 与服务器同步（首启注册试用 / 重装恢复状态）。
  Future<void> _sync(AppStorage storage) async {
    final gateway = _gateway;
    if (gateway == null || !gateway.config.configured) return;
    try {
      _fingerprint ??= await buildDeviceFingerprint();
      final device = await gateway.registerDevice(_fingerprint!);
      final serverState = _state.copyWith(
        trialStartedAt: _state.trialStartedAt ?? device.trialStartedAt,
        activatedUntil:
            _state.activatedUntil ?? device.activatedUntil,
      );
      if (serverState.trialStartedAt != _state.trialStartedAt ||
          serverState.activatedUntil != _state.activatedUntil) {
        _state = serverState;
        await _save(storage);
      }
      _refresh();
    } catch (_) {
      // 网络失败：本地状态继续
    }
  }

  Future<void> _save(AppStorage storage) async {
    try {
      await storage.writeText(_path, licenseStateToJson(_state));
    } catch (_) {}
  }

  LicenseView _evaluate() {
    final (status, effectiveNow, expiresAt) =
        LicenseEvaluator.evaluate(_state, DateTime.now());
    return LicenseView(
      status: status,
      effectiveNow: effectiveNow,
      expiresAt: expiresAt,
      remainingSeconds: LicenseEvaluator.remainingSeconds(
          status, effectiveNow, expiresAt),
      syncing: false,
      activating: false,
      activationMessage: state.valueOrNull?.activationMessage,
      activationSuccess: state.valueOrNull?.activationSuccess ?? false,
    );
  }

  void _refresh() {
    final current = state.valueOrNull;
    if (current == null) return;
    final view = _evaluate();
    state = AsyncData(LicenseView(
      status: view.status,
      effectiveNow: view.effectiveNow,
      expiresAt: view.expiresAt,
      remainingSeconds: view.remainingSeconds,
      syncing: current.syncing,
      activating: current.activating,
      activationMessage: current.activationMessage,
      activationSuccess: current.activationSuccess,
    ));
  }

  /// 记录当前时间（时间回拨检测；每次启动/回到前台调用）。
  Future<void> touch() async {
    if (!_enabled) return;
    final storage = await ref.read(appStorageProvider.future);
    final now = DateTime.now();
    final lastSeen = _state.lastSeenAt;
    if (lastSeen == null || now.isAfter(lastSeen)) {
      _state = _state.copyWith(lastSeenAt: now);
      await _save(storage);
    }
    _refresh();
  }

  /// 提交激活码。
  Future<bool> activate(String code) async {
    final gateway = _gateway;
    if (gateway == null) return false;
    final storage = await ref.read(appStorageProvider.future);
    state = AsyncData(_copyView(activating: true, message: null));
    try {
      if (!gateway.config.configured) {
        throw const LicenseGatewayException('激活服务未配置，请联系开发者');
      }
      _fingerprint ??= await buildDeviceFingerprint();
      final result = await gateway.activate(code, _fingerprint!);
      if (!result.ok) {
        state = AsyncData(_copyView(
          activating: false,
          message: result.message ?? '激活码无效',
        ));
        return false;
      }
      _state = _state.copyWith(
        activatedUntil: result.activatedUntil,
        activatedCode: code.trim().toUpperCase(),
      );
      await _save(storage);
      state = AsyncData(_copyView(
        activating: false,
        message: '✅ 激活成功，已解锁 ${result.durationDays >= 3650 ? "永久" : "${result.durationDays} 天"}',
        success: true,
      ));
      return true;
    } catch (e) {
      state = AsyncData(_copyView(
        activating: false,
        message: '激活失败：$e',
      ));
      return false;
    }
  }

  LicenseView _copyView({
    bool? activating,
    String? message,
    bool success = false,
  }) {
    final cur = state.valueOrNull ?? _evaluate();
    return LicenseView(
      status: cur.status,
      effectiveNow: cur.effectiveNow,
      expiresAt: cur.expiresAt,
      remainingSeconds: cur.remainingSeconds,
      syncing: cur.syncing,
      activating: activating ?? cur.activating,
      activationMessage: message,
      activationSuccess: success,
    );
  }
}

/// 许可证 provider（TRIAL_MODE 下使用）。
final licenseProvider =
    AsyncNotifierProvider<LicenseController, LicenseView>(
  LicenseController.new,
);

/// 是否编译为试用版。
const bool kTrialMode = bool.fromEnvironment('TRIAL_MODE');
