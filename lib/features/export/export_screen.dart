/// 导出与分享：高清 PNG（图纸+色号）/ PDF（图纸+BOM）/ 系统分享 / 保存作品。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app.dart';
import '../../app_providers.dart';
import '../../models/pattern.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/widgets/pattern_canvas.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool _working = false;
  bool _withCodes = true;

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(paletteForPatternProvider).valueOrNull;
    final pattern = ref.watch(conversionProvider).pattern;
    if (palette == null || pattern == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('导出')),
        body: const CuteEmptyState(emoji: '📤', title: '没有可导出的图纸'),
      );
    }

    final colors = [
      for (final e in palette.entries) (e.r << 16) | (e.g << 8) | e.b,
    ];
    final codes = [for (final e in palette.entries) e.code];
    final data = PatternCanvasData(
      grid: pattern.grid,
      size: pattern.size,
      colors: colors,
      codes: codes,
      showCodes: true,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('📤 导出与分享'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go(Routes.home),
            icon: const Icon(Icons.home_rounded, size: 18),
            label: const Text('首页'),
          ),
        ],
      ),
      body: SafeArea(
        child: _working
            ? const Center(child: BeadLoader(message: '生成中…'))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: PatternCanvas(
                                data: data,
                                maxScale: 4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('图纸上标注色号',
                                style: TextStyle(fontSize: 14)),
                            value: _withCodes,
                            onChanged: (v) =>
                                setState(() => _withCodes = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _exportTile(
                    emoji: '🖼️',
                    title: '高清 PNG 图纸',
                    subtitle: '≥1080px，含色号标注，适合打印/分享',
                    onTap: () => _exportPng(pattern, data),
                  ),
                  const SizedBox(height: 10),
                  _exportTile(
                    emoji: '📄',
                    title: 'PDF 图纸 + 用量清单',
                    subtitle: 'A4 可打印，含色号与每色颗数',
                    onTap: () => _exportPdf(pattern, data),
                  ),
                  const SizedBox(height: 10),
                  _exportTile(
                    emoji: '💌',
                    title: '分享图纸 PNG',
                    subtitle: '分享到微信 / 小红书 / QQ',
                    onTap: () => _sharePng(pattern, data),
                  ),
                  const SizedBox(height: 10),
                  _exportTile(
                    emoji: '📋',
                    title: '复制用量清单',
                    subtitle: '纯文本色号清单，方便采购备料',
                    onTap: () => _copyBom(pattern),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => _saveProject(context, pattern),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('💾 保存到作品库',
                        style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _exportTile({
    required String emoji,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Text(emoji, style: const TextStyle(fontSize: 26)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.textSecondary),
      ),
    );
  }

  Future<void> _exportPng(Pattern pattern, PatternCanvasData data) async {
    setState(() => _working = true);
    try {
      final bytes = await renderGridPng(
        PatternCanvasData(
          grid: data.grid,
          size: data.size,
          colors: data.colors,
          codes: data.codes,
          showCodes: _withCodes,
        ),
        outputPixels: 1080,
        withCodes: _withCodes,
      );
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}${Platform.pathSeparator}豆图_${pattern.size}x${pattern.size}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        subject: '豆图拼豆图纸',
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PNG 已生成：${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportPdf(Pattern pattern, PatternCanvasData data) async {
    setState(() => _working = true);
    try {
      final doc = pw.Document();
      final gridBytes = await renderGridPng(
        PatternCanvasData(
          grid: data.grid,
          size: data.size,
          colors: data.colors,
          codes: data.codes,
        ),
        outputPixels: 1080,
        withCodes: _withCodes,
      );

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                '豆图 · 拼豆图纸 ${pattern.size}×${pattern.size}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.pink600,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              '共 ${pattern.totalBeads} 颗 · ${pattern.colorCount} 色',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.Image(
                pw.MemoryImage(gridBytes),
                width: 400,
                height: 400,
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Header(level: 1, child: pw.Text('用量清单')),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['色号', '颜色名', '颗数'],
              data: [
                for (final e in pattern.bom)
                  [e.code, e.name ?? '', '${e.count}'],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 11,
              ),
              cellStyle: const pw.TextStyle(fontSize: 10),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}${Platform.pathSeparator}豆图_${pattern.size}x${pattern.size}_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: '豆图拼豆图纸 PDF',
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 已生成：${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _sharePng(Pattern pattern, PatternCanvasData data) async {
    setState(() => _working = true);
    try {
      final bytes = await renderGridPng(
        data,
        outputPixels: 1080,
        withCodes: _withCodes,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}${Platform.pathSeparator}豆图_share_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        subject: '豆图拼豆图纸',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _copyBom(Pattern pattern) async {
    final text = BomPanel.bomAsText(pattern.bom, pattern.totalBeads);
    await Clipboard.setData(ClipboardData(text: text));
    hapticTap();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用量清单已复制 📋')),
      );
    }
  }

  Future<void> _saveProject(BuildContext context, Pattern pattern) async {
    final name = await _askName(context);
    if (name == null || name.isEmpty) return;
    final saved =
        await ref.read(historyProvider.notifier).saveCurrent(name);
    hapticTap();
    if (!context.mounted) return;
    if (saved != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存「$name」到作品库 🎉')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败：没有可保存的图纸')),
      );
    }
  }

  Future<String?> _askName(BuildContext context) {
    final controller = TextEditingController(
      text: '拼豆作品 ${DateTime.now().month}月${DateTime.now().day}日',
    );
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存作品'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '给作品起个名字'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
