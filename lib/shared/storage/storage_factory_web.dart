/// web 平台工厂：创建基于 localStorage 的存储。
library;

import 'app_storage.dart';
import 'app_storage_web.dart';

Future<AppStorage> create() async => WebAppStorage();
