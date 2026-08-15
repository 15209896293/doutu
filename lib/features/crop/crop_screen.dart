/// 裁剪页：固定裁剪框 + 图片缩放平移（dev-plan 4.2 裁剪与比例调整）。
///
/// 不引入原生裁剪插件：用 image 包解码 + InteractiveViewer 实现，
/// 包体更小（plan 技术栈缺裁剪库选型，此处自行实现补齐）。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import '../../app.dart';
import '../../app_providers.dart';
import '../../core/subject_detector.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/product_tour.dart';

/// 裁剪比例选项。
enum CropRatio { free, square, w4h3, h4w3 }

extension CropRatioX on CropRatio {
  double? get value => switch (this) {
        CropRatio.free => null,
        CropRatio.square => 1.0,
        CropRatio.w4h3 => 4 / 3,
        CropRatio.h4w3 => 3 / 4,
      };

  String get label => switch (this) {
        CropRatio.free => '自由',
        CropRatio.square => '1:1',
        CropRatio.w4h3 => '4:3',
        CropRatio.h4w3 => '3:4',
      };
}

class CropScreen extends ConsumerStatefulWidget {
  const CropScreen({super.key});

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  final _controller = TransformationController();
  CropRatio _ratio = CropRatio.square;
  img.Image? _image;
  Uint8List? _displayBytes;
  String? _error;

  /// 「自动提取主体」与「裁剪完成」按钮锚点（引导用）。
  final _keyAutoExtract = GlobalKey();
  final _keyConfirmCrop = GlobalKey();

  /// 裁剪页引导（可选功能提示，看过一次即不再弹）。
  bool _cropTourVisible = false;
  bool _cropTourShown = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = ref.read(conversionProvider).imageBytes;
    if (bytes == null) {
      setState(() => _error = '未选择图片');
      return;
    }
    try {
      final image = img.decodeImage(bytes);
      setState(() {
        _image = image;
        _displayBytes =
            image == null ? null : Uint8List.fromList(img.encodePng(image));
        _error = image == null ? '图片解码失败，试试换一张图片' : null;
      });
    } catch (_) {
      setState(() {
        _error = '图片解码失败，试试换一张图片';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmCrop() async {
    final image = _image;
    if (image == null) {
      await _showCropFailDialog('还没有可裁剪的图片，请重新选择一张。');
      return;
    }
    // 当前视口信息在 build 里通过 LayoutBuilder 记录
    if (_viewportSize == null || _cropRect == null) {
      await _showCropFailDialog('裁剪区域还没有准备好，请稍后再试或换一张图片。');
      return;
    }

    try {
      final viewport = _viewportSize!;
      final cropRect = _cropRect!;

      // 视口坐标 → 子坐标系（去掉 fit 缩放）→ 原图坐标
      final matrix = _controller.value;
      // 先计算图片显示尺寸（BoxFit.contain 于视口）
      final fit = applyBoxFit(
        BoxFit.contain,
        Size(image.width.toDouble(), image.height.toDouble()),
        viewport,
      );
      final offsetX = (viewport.width - fit.destination.width) / 2;
      final offsetY = (viewport.height - fit.destination.height) / 2;

      // 裁剪框中心 → 视口坐标 → 逆变换到"fit 目标"坐标 → 映射到原图
      final cx = (cropRect.left + cropRect.right) / 2 - offsetX;
      final cy = (cropRect.top + cropRect.bottom) / 2 - offsetY;

      // 通过 InteractiveViewer 矩阵逆变换
      final inv = Matrix4.inverted(matrix);
      final p = MatrixUtils.transformPoint(inv, Offset(cx, cy));

      // fit 目标坐标 → 原图坐标
      final srcX = p.dx / fit.destination.width * image.width;
      final srcY = p.dy / fit.destination.height * image.height;

      // 裁剪尺寸（原图像素，安全 clamp 到图片范围内）
      final scale = image.width / fit.destination.width;
      final cropW = (cropRect.width * scale).round().clamp(1, image.width);
      final cropH = (cropRect.height * scale).round().clamp(1, image.height);

      final left =
          (srcX - cropW / 2).clamp(0.0, (image.width - cropW).toDouble());
      final top =
          (srcY - cropH / 2).clamp(0.0, (image.height - cropH).toDouble());

      final cropped = img.copyCrop(
        image,
        x: left.round(),
        y: top.round(),
        width: cropW,
        height: cropH,
      );
      final bytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 95));

      ref.read(conversionProvider.notifier).setImage(bytes);
      if (mounted) context.push(Routes.setup);
    } catch (_) {
      await _showCropFailDialog('这张图片裁剪失败了，试试换一张图片。');
    }
  }

  /// 自动提取主体：框选主体包围盒（背景杂物多时先裁出主体）。
  Future<void> _autoFrameSubject() async {
    final image = _image;
    if (image == null || _viewportSize == null || _cropRect == null) return;
    final region = detectSubject(image);
    if (region == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有识别到明确的主体，试试手动裁剪或换一张背景简单的图片'),
          ),
        );
      }
      return;
    }
    try {
      final viewport = _viewportSize!;
      final cropRect = _cropRect!;
      final fit = applyBoxFit(
        BoxFit.contain,
        Size(image.width.toDouble(), image.height.toDouble()),
        viewport,
      );
      final offsetX = (viewport.width - fit.destination.width) / 2;
      final offsetY = (viewport.height - fit.destination.height) / 2;
      final scaleF = fit.destination.width / image.width;

      // 主体包围盒 → 子坐标系
      final bx = offsetX + region.x * scaleF;
      final by = offsetY + region.y * scaleF;
      final bw = region.width * scaleF;
      final bh = region.height * scaleF;

      // 缩放到裁剪框内（留 8% 边距）
      final s = math.min(cropRect.width / bw, cropRect.height / bh) * 0.92;
      final sClamped = s.clamp(0.1, 10.0);
      final tx = cropRect.center.dx - sClamped * (bx + bw / 2);
      final ty = cropRect.center.dy - sClamped * (by + bh / 2);

      setState(() {
        _controller.value = Matrix4.identity()
          ..translateByDouble(tx, ty, 0, 1)
          ..scaleByDouble(sClamped, sClamped, 1, 1);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已自动框选主体（置信度 ${(region.confidence * 100).round()}%），可再手动调整',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('自动提取失败，请手动裁剪')),
        );
      }
    }
  }

  Future<void> _showCropFailDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('无法处理这张图片'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.go(Routes.home);
            },
            child: const Text('换一张图片'),
          ),
        ],
      ),
    );
  }

  Size? _viewportSize;
  Rect? _cropRect;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    // 首次进入裁剪页时，用 coach marks 提示「自动提取主体」（可选步骤）。
    if (_image != null &&
        settings != null &&
        !settings.cropTourSeen &&
        !_cropTourShown) {
      _cropTourShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _cropTourVisible = true);
      });
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
      appBar: AppBar(
        title: const Text('裁剪与比例'),
        actions: [
          IconButton(
            key: _keyAutoExtract,
            tooltip: '自动提取主体',
            icon: const Icon(Icons.auto_awesome_rounded),
            onPressed: _autoFrameSubject,
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary)))
          : _image == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(child: _buildCropArea()),
                    _buildRatioBar(),
                    _buildActionBar(),
                  ],
                ),
        ),
        if (_cropTourVisible)
          Positioned.fill(
            child: CoachTour(
              steps: _cropTourSteps,
              onFinished: _onCropTourFinished,
            ),
          ),
      ],
    );
  }

  List<CoachStep> get _cropTourSteps => [
        CoachStep(
          targetKey: _keyAutoExtract,
          icon: '✨',
          title: '背景太乱？自动提取主体',
          body: '点右上角这个按钮，会自动框出图片主体，再手动微调即可。可选步骤，不用也没关系。',
        ),
        CoachStep(
          targetKey: _keyConfirmCrop,
          icon: '✂️',
          title: '框好后继续',
          body: '调整好裁剪框后，点「裁剪完成 → 下一步」进入色卡与板型设置。',
        ),
      ];

  void _onCropTourFinished() {
    setState(() => _cropTourVisible = false);
    _markCropTourSeen();
  }

  Future<void> _markCropTourSeen() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || settings.cropTourSeen) return;
    try {
      await ref
          .read(settingsProvider.notifier)
          .saveSettings(settings.copyWith(cropTourSeen: true));
    } catch (_) {
      // 持久化失败不影响使用。
    }
  }

  Widget _buildCropArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = constraints.biggest;
        final ratio = _ratio.value;
        double w = constraints.maxWidth;
        double h = constraints.maxHeight;
        if (ratio != null) {
          if (w / h > ratio) {
            w = h * ratio;
          } else {
            h = w / ratio;
          }
        }
        final rect = Rect.fromCenter(
          center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
          width: w,
          height: h,
        );
        _cropRect = rect;

        return Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: 0.1,
                  maxScale: 10,
                  constrained: false,
                  child: Image.memory(
                    _displayBytes!,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
            // 遮罩
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _CropMaskPainter(rect)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRatioBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final r in CropRatio.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(r.label),
                selected: _ratio == r,
                onSelected: (_) => setState(() => _ratio = r),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => context.go(Routes.home),
              child: const Text('重选'),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              key: _keyConfirmCrop,
              onPressed: _confirmCrop,
              child: const Text('裁剪完成 → 下一步'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 裁剪框遮罩。
class _CropMaskPainter extends CustomPainter {
  final Rect rect;

  _CropMaskPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(path, mask);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.primary;
    canvas.drawRect(rect, border);

    // 九宫格辅助线
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.6);
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_CropMaskPainter old) => old.rect != rect;
}
