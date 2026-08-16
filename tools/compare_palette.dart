// 对比现有 mard_221.json 与 pindou-color-data 国内核对版（alfonse-doudou）的差异。
// 用法：先下载 https://raw.githubusercontent.com/HansBug/pindou-color-data/main/mard-221-alfonse-doudou/colors.json 到 temp
// ignore_for_file: avoid_print, implementation_imports

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final oursPath = args.isNotEmpty ? args[0] : 'lib/core/palettes/mard_221.json';
  final theirsPath = args.length > 1 ? args[1] : null;
  if (theirsPath == null || !File(theirsPath).existsSync()) {
    print('用法：dart run tools/compare_palette.dart lib/core/palettes/mard_221.json <核对版colors.json>');
    return;
  }

  final ours = jsonDecode(File(oursPath).readAsStringSync()) as List<dynamic>;
  final theirsJson = jsonDecode(File(theirsPath).readAsStringSync()) as Map<String, dynamic>;
  final theirs = (theirsJson['colors'] as List<dynamic>)
      .map((e) => e as Map<String, dynamic>)
      .toList();

  // 色号归一化：A1 == A01 == A001
  String norm(String code) {
    final m = RegExp(r'^([A-Z]+)0*(\d+)$').firstMatch(code.toUpperCase());
    return m == null ? code.toUpperCase() : '${m.group(1)}${m.group(2)}';
  }

  final theirMap = <String, Map<String, dynamic>>{};
  for (final t in theirs) {
    final k = norm(t['code'] as String);
    if (theirMap.containsKey(k)) {
      print('DUPLICATE KEY: $k');
    }
    theirMap[k] = t;
  }
  print('theirMap keys: ${theirMap.length}, 样例: ${theirMap.keys.take(5).toList()}');
  final probe = theirMap['A1'];
  print('probe A1: ${probe?['hex']}');

  var matched = 0, missing = 0;
  var sumDeltaE = 0.0, maxDeltaE = 0.0;
  var shifted = 0; // 同码但 RGB 差异显著的色号
  final examples = <String>[];
  var maxCode = '';

  for (final o in ours) {
    final code = o['code'] as String;
    final rgb = (o['rgb'] as List<dynamic>).cast<int>();
    final t = theirMap[norm(code)];
    if (t == null) {
      missing++;
      continue;
    }
    matched++;
    final List<int> trgb;
    final trgbRaw = t['rgb'];
    if (trgbRaw is String) {
      trgb = trgbRaw.split(' ').map(int.parse).toList();
    } else {
      trgb = (trgbRaw as List<dynamic>).cast<int>();
    }
    final d = _deltaE(rgb, trgb);
    sumDeltaE += d;
    if (d > maxDeltaE) {
      maxDeltaE = d;
      maxCode = code;
    }
    if (d > 3.0) {
      shifted++;
      if (examples.length < 8) {
        examples.add('$code: 我们 #${o['hex']} vs 核对 #${t['hex']} (ΔE=${d.toStringAsFixed(1)})');
      }
    }
  }

  print('匹配色号：$matched / ${ours.length}（缺失：$missing）');
  print('平均 ΔE：${(sumDeltaE / (matched == 0 ? 1 : matched)).toStringAsFixed(2)}');
  print('最大 ΔE：${maxDeltaE.toStringAsFixed(2)}（$maxCode）');
  print('ΔE > 3 的色号数：$shifted（需校正）');
  print('示例差异：');
  for (final e in examples) {
    print('  $e');
  }
}

double _deltaE(List<int> a, List<int> b) {
  // 简易欧氏 RGB 距离（对比用足够）
  final dr = a[0] - b[0], dg = a[1] - b[1], db = a[2] - b[2];
  return (dr * dr + dg * dg + db * db).toDouble() / 3; // 平均通道差，近似感知
}
