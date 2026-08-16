// 用 pindou-color-data 国内核对版（mard-221-alfonse-doudou，宣称 MARD 官方）更新 mard 色卡。
// 保留我们 A01 编码格式（用户按 A01 买豆），只替换 rgb/hex 为核对版值。
// 用法：dart run tools/convert_palette.dart <核对版colors.json>
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty || !File(args[0]).existsSync()) {
    print('用法：dart run tools/convert_palette.dart <核对版colors.json>');
    return;
  }
  final theirsJson =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final theirs = (theirsJson['colors'] as List<dynamic>)
      .map((e) => e as Map<String, dynamic>)
      .toList();

  String norm(String code) {
    final m = RegExp(r'^([A-Z]+)0*(\d+)$').firstMatch(code.toUpperCase());
    return m == null ? code.toUpperCase() : '${m.group(1)}${m.group(2)}';
  }

  final theirMap = <String, List<int>>{};
  for (final t in theirs) {
    final raw = t['rgb'];
    final List<int> rgb;
    if (raw is String) {
      rgb = raw.split(' ').map(int.parse).toList();
    } else {
      rgb = (raw as List<dynamic>).cast<int>();
    }
    theirMap[norm(t['code'] as String)] = rgb;
  }

  for (final path in ['lib/core/palettes/mard_221.json', 'lib/core/palettes/mard_291.json']) {
    if (!File(path).existsSync()) continue;
    final entries =
        jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
    var updated = 0;
    for (final e in entries) {
      final entry = e as Map<String, dynamic>;
      final rgb = theirMap[norm(entry['code'] as String)];
      if (rgb == null) continue;
      entry['rgb'] = rgb;
      entry['hex'] =
          '#${rgb[0].toRadixString(16).padLeft(2, '0').toUpperCase()}'
              '${rgb[1].toRadixString(16).padLeft(2, '0').toUpperCase()}'
              '${rgb[2].toRadixString(16).padLeft(2, '0').toUpperCase()}';
      updated++;
    }
    File(path).writeAsStringSync(jsonEncode(entries));
    print('$path：更新 $updated 个色号（来源：pindou-color-data mard-221-alfonse-doudou 核对版）');
  }
}
