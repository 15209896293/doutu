/// web 实现：浏览器直接下载（data URL + <a download>）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> shareOrDownloadBytes({
  required String fileName,
  required String mimeType,
  required Uint8List bytes,
  String? subject,
}) async {
  final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
  final a = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = fileName;
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
}
