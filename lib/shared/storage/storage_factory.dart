/// 跨端存储工厂：io（文件系统）/ web（localStorage）条件导入。
library;

import 'app_storage.dart';
import 'storage_factory_io.dart'
    if (dart.library.js_interop) 'storage_factory_web.dart' as impl;

/// 创建当前平台的存储实现。
Future<AppStorage> createAppStorage() => impl.create();
