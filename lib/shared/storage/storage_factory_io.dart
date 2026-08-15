/// io 平台工厂：创建基于文件系统的存储。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_storage.dart';
import 'app_storage_io.dart';

Future<AppStorage> create() async {
  final dir = await getApplicationSupportDirectory();
  return IoAppStorage(Directory(dir.path));
}
