/// io 实现：写入临时文件后调用系统分享。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareOrDownloadBytes({
  required String fileName,
  required String mimeType,
  required Uint8List bytes,
  String? subject,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: mimeType)],
    subject: subject,
  ));
}
