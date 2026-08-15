/// 跨端「分享/下载」助手：移动端系统分享，Web 端浏览器下载。
library;

import 'dart:typed_data';

import 'share_helper_io.dart'
    if (dart.library.js_interop) 'share_helper_web.dart' as impl;

/// 分享或下载字节内容。
Future<void> shareOrDownloadBytes({
  required String fileName,
  required String mimeType,
  required Uint8List bytes,
  String? subject,
}) =>
    impl.shareOrDownloadBytes(
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      subject: subject,
    );
