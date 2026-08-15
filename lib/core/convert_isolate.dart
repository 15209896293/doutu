/// 转换编排：图片字节 → Isolate 执行算法 → Pattern。
library;

import 'package:flutter/foundation.dart';

import 'palette.dart';
import 'pattern_converter.dart';
import '../models/pattern.dart';

/// Isolate 转换请求（纯数据，可跨 isolate 拷贝）。
class ConvertRequest {
  final Uint8List imageBytes;
  final Palette palette;
  final ConvertOptions options;

  ConvertRequest({
    required this.imageBytes,
    required this.palette,
    required this.options,
  });
}

/// Isolate 转换结果。
class ConvertResponse {
  final Pattern? pattern;
  final List<int> avgColors;
  final String? error;

  ConvertResponse({this.pattern, this.avgColors = const [], this.error});
}

/// Isolate 入口（顶层函数，供 compute 调用）。
ConvertResponse runConvertIsolate(ConvertRequest request) {
  try {
    final converter = PatternConverter(request.palette);
    final result = converter.convert(request.imageBytes, request.options);
    return ConvertResponse(pattern: result.pattern, avgColors: result.avgColors);
  } catch (e) {
    return ConvertResponse(error: e.toString());
  }
}

/// 在后台 isolate 中执行转换（不阻塞 UI）。
Future<ConvertResponse> convertInBackground(ConvertRequest request) {
  return compute(runConvertIsolate, request);
}
