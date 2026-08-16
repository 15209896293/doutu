/// Supabase 激活网关：调用 Edge Function（activate / device）。
///
/// 仅 TRIAL_MODE 编译启用。配置通过 --dart-define 注入：
///   --dart-define=SUPABASE_URL=https://xxx.supabase.co
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// 客户端不直接访问数据表（RLS 拒绝），只调 Edge Function。
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// 网关配置（编译期注入）。
class LicenseGatewayConfig {
  final String supabaseUrl;
  final String anonKey;

  /// 空 URL = 网关未配置（离线降级）。
  bool get configured => supabaseUrl.isNotEmpty && anonKey.isNotEmpty;

  const LicenseGatewayConfig({
    this.supabaseUrl = '',
    this.anonKey = '',
  });

  /// 从 --dart-define 读取。
  static const fromEnvironment = LicenseGatewayConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
}

/// 设备注册/查询结果。
class DeviceStatus {
  final DateTime trialStartedAt;
  final DateTime? activatedUntil;

  const DeviceStatus({
    required this.trialStartedAt,
    this.activatedUntil,
  });

  DateTime get trialExpiresAt =>
      trialStartedAt.add(const Duration(hours: 24));
}

/// 激活结果。
class ActivateResult {
  final bool ok;
  final int durationDays;
  final DateTime activatedUntil;
  final String? message;

  const ActivateResult({
    required this.ok,
    required this.durationDays,
    required this.activatedUntil,
    this.message,
  });
}

/// 网关异常（网络/服务端）。
class LicenseGatewayException implements Exception {
  final String message;
  const LicenseGatewayException(this.message);
  @override
  String toString() => message;
}

/// 设备指纹：ANDROID_ID（经平台通道读取）+ 型号，SHA-256 散列。
/// 注：ANDROID_ID 在 Android 8+ 卸载重装后变化——这是平台限制（见方案文档
/// 「防重置设计」），同一安装周期内稳定；重装后靠 Auto Backup + 服务器状态恢复。
Future<String> buildDeviceFingerprint() async {
  const channel = MethodChannel('doutu/license');
  try {
    final androidId = await channel.invokeMethod<String>('androidId') ?? '';
    final raw = '$androidId|android|doutu';
    return _sha256(List<int>.from(raw.codeUnits));
  } catch (_) {
    // 失败时退化为随机（同一安装内仍稳定）
    return 'fp_${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// 纯 Dart SHA-256（仅作指纹散列，非安全场景）。
String _sha256(List<int> data) => _sha256Impl(data);

String _sha256Impl(List<int> data) {
  // 参考实现：标准 SHA-256
  final k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  final h0 = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
    0x1f83d9ab, 0x5be0cd19,
  ];

  final msg = List<int>.from(data);
  final bitLen = msg.length * 8;
  msg.add(0x80);
  while (msg.length % 64 != 56) {
    msg.add(0);
  }
  for (var i = 3; i >= 0; i--) {
    msg.add((bitLen >> (i * 8)) & 0xff);
  }

  final w = List<int>.filled(64, 0);
  final h = List<int>.from(h0);

  int rotr(int x, int n) => (x >> n) | (x << (32 - n)) & 0xffffffff;

  for (var chunk = 0; chunk < msg.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = (msg[chunk + i * 4] << 24) |
          (msg[chunk + i * 4 + 1] << 16) |
          (msg[chunk + i * 4 + 2] << 8) |
          (msg[chunk + i * 4 + 3]);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ (~e & g);
      final t1 = (hh + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g; g = f; f = e;
      e = (d + t1) & 0xffffffff;
      d = c; c = b; b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
    h[5] = (h[5] + f) & 0xffffffff;
    h[6] = (h[6] + g) & 0xffffffff;
    h[7] = (h[7] + hh) & 0xffffffff;
  }

  final out = StringBuffer();
  for (final v in h) {
    out.write(v.toRadixString(16).padLeft(8, '0'));
  }
  return out.toString();
}

/// Supabase 网关。
class SupabaseLicenseGateway {
  final LicenseGatewayConfig config;

  SupabaseLicenseGateway(this.config);

  Uri _fn(String name) =>
      Uri.parse('${config.supabaseUrl}/functions/v1/$name');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.anonKey}',
        'apikey': config.anonKey,
      };

  /// 注册/查询设备（试用开始或恢复状态）。
  Future<DeviceStatus> registerDevice(String fingerprint) async {
    if (!config.configured) {
      throw const LicenseGatewayException('激活服务未配置');
    }
    final resp = await http
        .post(
          _fn('device'),
          headers: _headers,
          body: jsonEncode({'fingerprint': fingerprint}),
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw LicenseGatewayException('服务异常（${resp.statusCode}）');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw LicenseGatewayException(json['error'] as String);
    }
    return DeviceStatus(
      trialStartedAt: DateTime.parse(json['trialStartedAt'] as String),
      activatedUntil: json['activatedUntil'] == null
          ? null
          : DateTime.parse(json['activatedUntil'] as String),
    );
  }

  /// 激活：验证激活码并返回新到期时间。
  Future<ActivateResult> activate(String code, String fingerprint) async {
    if (!config.configured) {
      throw const LicenseGatewayException('激活服务未配置');
    }
    final resp = await http
        .post(
          _fn('activate'),
          headers: _headers,
          body: jsonEncode({
            'code': code.trim().toUpperCase(),
            'fingerprint': fingerprint,
          }),
        )
        .timeout(const Duration(seconds: 8));
    final json = _safeDecode(resp.body);
    if (resp.statusCode != 200 || json?['ok'] != true) {
      return ActivateResult(
        ok: false,
        durationDays: 0,
        activatedUntil: DateTime.now(),
        message: (json?['message'] as String?) ?? '激活失败（${resp.statusCode}）',
      );
    }
    return ActivateResult(
      ok: true,
      durationDays: (json!['durationDays'] as num).toInt(),
      activatedUntil: DateTime.parse(json['activatedUntil'] as String),
    );
  }

  Map<String, dynamic>? _safeDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
