/// 图纸网格画布：CustomPainter 渲染拼豆图纸。
///
/// 支持三种模式：
/// - flat：平铺色块（默认）
/// - round：圆形豆子模拟（成品模拟预览）
/// - 可选色号文字标注（放大多倍后显示）
///
/// 性能策略：画布内容缓存为 ui.Image（PictureRecorder 离屏渲染一次），
/// 缩放/平移由 InteractiveViewer 的变换矩阵处理，不重绘像素。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/pattern.dart';

/// 渲染样式。
enum GridRenderMode {
  /// 平铺色块。
  flat,

  /// 圆形豆子（成品模拟）。
  round,
}

/// 网格画布参数。
class PatternCanvasData {
  /// 色号索引矩阵（-1 = 透明）。
  final List<int> grid;
  final int size;

  /// 色号 → RGB（palette 色表，供色块上色）。
  final List<int> colors;

  /// 色号 → 色号文本。
  final List<String> codes;

  /// 是否显示色号文字。
  final bool showCodes;

  /// 渲染模式。
  final GridRenderMode mode;

  /// 网格线颜色（平铺模式）。
  final Color gridLineColor;

  /// 透明格背景。
  final Color background;

  const PatternCanvasData({
    required this.grid,
    required this.size,
    required this.colors,
    required this.codes,
    this.showCodes = false,
    this.mode = GridRenderMode.flat,
    this.gridLineColor = const Color(0x14FF6B9D),
    this.background = Colors.white,
  });
}

/// 图纸画布（含缓存与缩放）。
class PatternCanvas extends StatefulWidget {
  final PatternCanvasData data;
  final double initialScale;
  final double minScale;
  final double maxScale;

  /// 高亮格（跟做模式：当前色号的格子）与选中格（编辑器）。
  final Set<int>? highlightCells;
  final Color highlightColor;
  final Set<int>? outlineCells;

  const PatternCanvas({
    super.key,
    required this.data,
    this.initialScale = 1,
    this.minScale = 0.5,
    this.maxScale = 8,
    this.highlightCells,
    this.highlightColor = const Color(0xFFFFD93D),
    this.outlineCells,
  });

  @override
  State<PatternCanvas> createState() => _PatternCanvasState();
}

class _PatternCanvasState extends State<PatternCanvas> {
  ui.Image? _cachedImage;
  PatternCanvasData? _cachedData;

  @override
  void didUpdateWidget(covariant PatternCanvas old) {
    super.didUpdateWidget(old);
    if (!identical(old.data, widget.data)) {
      _cachedImage = null;
      _cachedData = null;
    }
  }

  Future<ui.Image> _render(PatternCanvasData data) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final n = data.size;
    final cell = 24.0; // 离屏基准格宽
    final total = n * cell;

    // 背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, total, total),
      Paint()..color = data.background,
    );

    final fillPaint = Paint();
    final gridPaint = Paint()
      ..color = data.gridLineColor
      ..strokeWidth = 0.5;

    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final idx = data.grid[y * n + x];
        final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        if (idx >= 0) {
          if (data.mode == GridRenderMode.round) {
            _drawBead(canvas, rect, Color(data.colors[idx]));
          } else {
            fillPaint.color = Color(0xFF000000 | data.colors[idx]);
            canvas.drawRect(rect, fillPaint);
          }
        } else {
          // 透明格：棋盘浅格
          final p = Paint()..color = const Color(0x0A000000);
          canvas.drawRect(rect, p);
        }
      }
    }

    if (data.mode == GridRenderMode.flat) {
      // 网格线
      for (var i = 0; i <= n; i++) {
        canvas.drawLine(
          Offset(i * cell, 0),
          Offset(i * cell, total),
          gridPaint,
        );
        canvas.drawLine(
          Offset(0, i * cell),
          Offset(total, i * cell),
          gridPaint,
        );
      }
    }

    // 色号文字（格子足够大时）
    if (data.showCodes) {
      final textPaint = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final idx = data.grid[y * n + x];
          if (idx < 0 || idx >= data.codes.length) continue;
          textPaint.text = TextSpan(
            text: data.codes[idx],
            style: TextStyle(
              fontSize: cell * 0.32,
              fontFamily: 'JetBrainsMono',
              color: _contrastText(Color(data.colors[idx])),
            ),
          );
          textPaint.layout(maxWidth: cell);
          final offset = Offset(
            x * cell + (cell - textPaint.width) / 2,
            y * cell + (cell - textPaint.height) / 2,
          );
          textPaint.paint(canvas, offset);
        }
      }
    }

    final picture = recorder.endRecording();
    return picture.toImage(n * cell.toInt(), n * cell.toInt());
  }

  void _drawBead(Canvas canvas, Rect rect, Color color) {
    final center = rect.center;
    final radius = rect.width * 0.46;
    final paint = Paint()..color = color;
    canvas.drawCircle(center, radius, paint);
    // 高光
    final hl = Paint()..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawCircle(
      center.translate(-radius * 0.25, -radius * 0.3),
      radius * 0.28,
      hl,
    );
    // 中心孔
    final hole = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(center, radius * 0.28, hole);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (_cachedImage == null || !identical(_cachedData, data)) {
      _cachedData = data;
      _render(data).then((image) {
        if (mounted) setState(() => _cachedImage = image);
      });
    }

    final image = _cachedImage;
    return InteractiveViewer(
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      boundaryMargin: const EdgeInsets.all(80),
      child: image == null
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : RawImage(
              image: image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}

/// 根据背景亮度选对比文字色。
Color _contrastText(Color bg) {
  final luminance = bg.computeLuminance();
  return luminance > 0.5 ? const Color(0xFF3D2E2A) : Colors.white;
}

/// 构建渲染数据（从 Pattern + Palette）。
PatternCanvasData canvasDataFor(
  Pattern pattern,
  List<int> paletteColors,
  List<String> codes, {
  bool showCodes = false,
  GridRenderMode mode = GridRenderMode.flat,
}) {
  return PatternCanvasData(
    grid: pattern.grid,
    size: pattern.size,
    colors: paletteColors,
    codes: codes,
    showCodes: showCodes,
    mode: mode,
  );
}

/// 网格转 PNG 字节（导出用，支持任意输出边长）。
Future<Uint8List> renderGridPng(
  PatternCanvasData data, {
  int outputPixels = 1024,
  bool withCodes = true,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final n = data.size;
  final cell = outputPixels / n;
  final total = outputPixels.toDouble();

  canvas.drawRect(
    Rect.fromLTWH(0, 0, total, total),
    Paint()..color = data.background,
  );

  final paint = Paint();
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final idx = data.grid[y * n + x];
      if (idx < 0) continue;
      paint.color = Color(0xFF000000 | data.colors[idx]);
      canvas.drawRect(
        Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
        paint,
      );
    }
  }

  if (withCodes) {
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final idx = data.grid[y * n + x];
        if (idx < 0 || idx >= data.codes.length) continue;
        final tp = TextPainter(
          text: TextSpan(
            text: data.codes[idx],
            style: TextStyle(
              fontSize: cell * 0.3,
              fontFamily: 'JetBrainsMono',
              color: _contrastText(Color(data.colors[idx])),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            x * cell + (cell - tp.width) / 2,
            y * cell + (cell - tp.height) / 2,
          ),
        );
      }
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(outputPixels, outputPixels);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
