// 生成试用版测试激活码，输出 SQL INSERT（贴到 Supabase SQL Editor 执行）。
//
// 用法：dart run tools/gen_trial_codes.dart [数量] [每码次数]
// 默认：每类 5 个，每个码限用 1 次。
// ignore_for_file: avoid_print

import 'dart:math';

void main(List<String> args) {
  final perType = args.isNotEmpty ? int.tryParse(args[0]) ?? 5 : 5;
  final maxUses = args.length > 1 ? int.tryParse(args[1]) ?? 1 : 1;

  final rng = Random.secure();
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // 去掉易混淆字符

  String rand(int len) => List.generate(
        len,
        (_) => chars[rng.nextInt(chars.length)],
      ).join();

  final types = <(String, int, String)>[
    ('DOU7D', 7, '试用体验：7 天'),
    ('DOU30D', 30, '深度体验：30 天'),
    ('DOU90D', 90, '忠实用户：90 天'),
    ('DOUPERM', 3650, '永久（内部/答谢）'),
  ];

  final rows = <String>[];
  for (final (prefix, days, note) in types) {
    for (var i = 0; i < perType; i++) {
      final code = '$prefix-${rand(4)}-${rand(4)}';
      rows.add("  ('$code', $days, $maxUses, '$note')");
    }
  }

  print('-- 豆图试用版激活码（每类 $perType 个，每码限用 $maxUses 次）');
  print('insert into public.codes (code, duration_days, max_uses, note) values');
  print(rows.join(',\n'));
  print('on conflict (code) do nothing;');
  print('');
  print('-- 码列表（发给测试用户）：');
  for (final (prefix, _, _) in types) {
    final codes = rows
        .where((r) => r.contains("'$prefix-"))
        .map((r) => RegExp("'([^']+)'").firstMatch(r)!.group(1)!)
        .join('  ');
    print('[$prefix] $codes');
  }
}
