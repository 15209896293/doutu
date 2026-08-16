/// 试用/激活许可证状态模型（纯 Dart，可单测）。
///
/// 状态：试用中（24h）→ 到期锁定 → 激活码解锁（N 天/永久）。
/// 时间防回拨：持久化 [lastSeenAt]，系统时间回拨时按已见时间继续计时。
library;

import 'dart:convert';

/// 试用时长（小时）。
const int kTrialDurationHours = 24;

/// 许可证持久化状态。
class LicenseState {
  /// 首次试用开始时间（本地尽力；联网注册后以服务器为准）。
  final DateTime? trialStartedAt;

  /// 最近一次"见过"的时间（时间回拨检测）。
  final DateTime? lastSeenAt;

  /// 激活到期时间（null = 未激活）。
  final DateTime? activatedUntil;

  /// 最近成功使用的激活码。
  final String? activatedCode;

  const LicenseState({
    this.trialStartedAt,
    this.lastSeenAt,
    this.activatedUntil,
    this.activatedCode,
  });

  LicenseState copyWith({
    DateTime? trialStartedAt,
    DateTime? lastSeenAt,
    DateTime? activatedUntil,
    String? activatedCode,
    bool clearActivation = false,
  }) {
    return LicenseState(
      trialStartedAt: trialStartedAt ?? this.trialStartedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      activatedUntil: clearActivation ? null : (activatedUntil ?? this.activatedUntil),
      activatedCode: clearActivation ? null : (activatedCode ?? this.activatedCode),
    );
  }

  Map<String, dynamic> toJson() => {
        if (trialStartedAt != null)
          'trialStartedAt': trialStartedAt!.toIso8601String(),
        if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
        if (activatedUntil != null)
          'activatedUntil': activatedUntil!.toIso8601String(),
        if (activatedCode != null) 'activatedCode': activatedCode,
      };

  factory LicenseState.fromJson(Map<String, dynamic> json) => LicenseState(
        trialStartedAt: _parse(json['trialStartedAt']),
        lastSeenAt: _parse(json['lastSeenAt']),
        activatedUntil: _parse(json['activatedUntil']),
        activatedCode: json['activatedCode'] as String?,
      );

  static DateTime? _parse(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  static const empty = LicenseState();
}

/// 许可证判定结果。
enum LicenseStatus {
  /// 试用中（未到期）。
  trialActive,

  /// 已激活且未到期。
  activated,

  /// 试用到期且未激活 → 锁定。
  locked,

  /// 激活到期 → 锁定（可重新激活）。
  lockedExpired,
}

/// 许可证判定器。
class LicenseEvaluator {
  /// 判定当前状态。
  ///
  /// [now]：当前时间（测试可注入）；内部做时间回拨检测：
  /// 若 [now] 早于 [state.lastSeenAt]，按 [state.lastSeenAt] 计时。
  /// 返回 (状态, 生效的当前时间, 到期时间)。
  static (LicenseStatus, DateTime, DateTime?) evaluate(
    LicenseState state,
    DateTime now,
  ) {
    // 时间回拨检测：系统时间早于已见时间 → 用已见时间
    final lastSeen = state.lastSeenAt;
    final effectiveNow =
        (lastSeen != null && now.isBefore(lastSeen)) ? lastSeen : now;

    final activatedUntil = state.activatedUntil;
    if (activatedUntil != null) {
      if (effectiveNow.isBefore(activatedUntil)) {
        return (LicenseStatus.activated, effectiveNow, activatedUntil);
      }
      return (LicenseStatus.lockedExpired, effectiveNow, activatedUntil);
    }

    final trialStart = state.trialStartedAt;
    if (trialStart != null) {
      final trialExpires = trialStart.add(const Duration(hours: kTrialDurationHours));
      if (effectiveNow.isBefore(trialExpires)) {
        return (LicenseStatus.trialActive, effectiveNow, trialExpires);
      }
    }
    final trialExpiresAt = trialStart?.add(const Duration(hours: kTrialDurationHours));
    return (LicenseStatus.locked, effectiveNow, trialExpiresAt);
  }

  /// 剩余可用时长（秒）；已锁定返回 0。
  static int remainingSeconds(LicenseStatus status, DateTime effectiveNow, DateTime? expiresAt) {
    if (expiresAt == null) return 0;
    switch (status) {
      case LicenseStatus.activated:
      case LicenseStatus.trialActive:
        final s = expiresAt.difference(effectiveNow).inSeconds;
        return s > 0 ? s : 0;
      case LicenseStatus.locked:
      case LicenseStatus.lockedExpired:
        return 0;
    }
  }

  /// 人类可读剩余时长。
  static String formatRemaining(int seconds) {
    if (seconds <= 0) return '已到期';
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '$d 天 $h 小时';
    if (h > 0) return '$h 小时 $m 分';
    if (m > 0) return '$m 分钟';
    return '$seconds 秒';
  }
}

/// 序列化辅助（供存储层使用）。
String licenseStateToJson(LicenseState s) => jsonEncode(s.toJson());

LicenseState licenseStateFromJson(String? text) {
  if (text == null) return LicenseState.empty;
  try {
    final json = jsonDecode(text) as Map<String, dynamic>;
    return LicenseState.fromJson(json);
  } catch (_) {
    return LicenseState.empty;
  }
}
