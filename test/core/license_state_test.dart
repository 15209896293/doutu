import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/core/license/license_state.dart';

void main() {
  final base = DateTime(2026, 8, 15, 12, 0, 0);

  group('许可证状态机', () {
    test('首次安装（无记录）→ 锁定（需注册开始试用）', () {
      final (status, _, expiresAt) =
          LicenseEvaluator.evaluate(LicenseState.empty, base);
      expect(status, LicenseStatus.locked);
      expect(expiresAt, isNull);
    });

    test('试用开始后 24 小时内 → 试用中', () {
      final s = LicenseState(trialStartedAt: base);
      final (status, _, expiresAt) =
          LicenseEvaluator.evaluate(s, base.add(const Duration(hours: 23)));
      expect(status, LicenseStatus.trialActive);
      expect(expiresAt, base.add(const Duration(hours: 24)));
    });

    test('试用 24 小时后 → 锁定', () {
      final s = LicenseState(trialStartedAt: base);
      final (status, _, _) =
          LicenseEvaluator.evaluate(s, base.add(const Duration(hours: 24, minutes: 1)));
      expect(status, LicenseStatus.locked);
    });

    test('激活后未到期 → 已激活', () {
      final s = LicenseState(
        trialStartedAt: base,
        activatedUntil: base.add(const Duration(days: 7)),
      );
      final (status, _, expiresAt) =
          LicenseEvaluator.evaluate(s, base.add(const Duration(days: 3)));
      expect(status, LicenseStatus.activated);
      expect(expiresAt, base.add(const Duration(days: 7)));
    });

    test('激活到期后 → lockedExpired（可重新激活）', () {
      final s = LicenseState(
        trialStartedAt: base,
        activatedUntil: base.add(const Duration(days: 7)),
      );
      final (status, _, _) =
          LicenseEvaluator.evaluate(s, base.add(const Duration(days: 8)));
      expect(status, LicenseStatus.lockedExpired);
    });

    test('时间回拨：系统时间早于已见时间 → 按已见时间计时（试用不延长）', () {
      final s = LicenseState(
        trialStartedAt: base,
        lastSeenAt: base.add(const Duration(hours: 20)),
      );
      // 用户把系统时间拨回 10 小时前
      final (status, effectiveNow, _) =
          LicenseEvaluator.evaluate(s, base.add(const Duration(hours: 10)));
      expect(status, LicenseStatus.trialActive);
      expect(effectiveNow, base.add(const Duration(hours: 20)),
          reason: '生效时间应为已见时间（防回拨）');
    });

    test('剩余时长计算与格式化', () {
      expect(LicenseEvaluator.formatRemaining(0), '已到期');
      expect(LicenseEvaluator.formatRemaining(90 * 86400), '90 天 0 小时');
      expect(LicenseEvaluator.formatRemaining(3600 * 3 + 60 * 5), '3 小时 5 分');
      expect(LicenseEvaluator.formatRemaining(42), '42 秒');
    });

    test('JSON 序列化往返', () {
      const s = LicenseState(
        trialStartedAt: null,
        activatedUntil: null,
      );
      final withData = LicenseState(
        trialStartedAt: base,
        lastSeenAt: base.add(const Duration(hours: 1)),
        activatedUntil: base.add(const Duration(days: 30)),
        activatedCode: 'DOU30D-ABCD-EFGH',
      );
      final restored = licenseStateFromJson(licenseStateToJson(withData));
      expect(restored.trialStartedAt, base);
      expect(restored.lastSeenAt, base.add(const Duration(hours: 1)));
      expect(restored.activatedUntil, base.add(const Duration(days: 30)));
      expect(restored.activatedCode, 'DOU30D-ABCD-EFGH');
      final emptyRestored = licenseStateFromJson(licenseStateToJson(s));
      expect(emptyRestored.trialStartedAt, isNull);
      // 损坏 JSON → 空状态
      expect(licenseStateFromJson('not json').trialStartedAt, isNull);
    });
  });
}
