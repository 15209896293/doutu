import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/import/import_screen.dart';
import 'features/crop/crop_screen.dart';
import 'features/setup/setup_screen.dart';
import 'features/preview/preview_screen.dart';
import 'features/editor/editor_screen.dart';
import 'features/craft/craft_screen.dart';
import 'features/export/export_screen.dart';
import 'features/history/history_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/settings/settings_screen.dart';
import 'shared/theme/app_theme.dart';

/// 路由名（dev-plan 4.4 页面清单）。
abstract class Routes {
  static const home = '/';
  static const crop = '/crop';
  static const setup = '/setup';
  static const preview = '/preview';
  static const editor = '/editor';
  static const craft = '/craft';
  static const export = '/export';
  static const history = '/history';
  static const settings = '/settings';
  static const inventory = '/inventory';
}

final _router = GoRouter(
  routes: [
    GoRoute(path: Routes.home, builder: (c, s) => const ImportScreen()),
    GoRoute(path: Routes.crop, builder: (c, s) => const CropScreen()),
    GoRoute(path: Routes.setup, builder: (c, s) => const SetupScreen()),
    GoRoute(path: Routes.preview, builder: (c, s) => const PreviewScreen()),
    GoRoute(path: Routes.editor, builder: (c, s) => const EditorScreen()),
    GoRoute(path: Routes.craft, builder: (c, s) => const CraftScreen()),
    GoRoute(path: Routes.export, builder: (c, s) => const ExportScreen()),
    GoRoute(path: Routes.history, builder: (c, s) => const HistoryScreen()),
    GoRoute(path: Routes.settings, builder: (c, s) => const SettingsScreen()),
    GoRoute(path: Routes.inventory, builder: (c, s) => const InventoryScreen()),
  ],
);

/// 豆图 App。
class DoutuApp extends StatelessWidget {
  const DoutuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp.router(
        title: '豆图 · 拼豆图纸转化器',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: _router,
      ),
    );
  }
}
