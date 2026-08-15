import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/app.dart';
import 'package:doutu/app_providers.dart';
import 'package:doutu/core/palette.dart';
import 'package:doutu/models/project.dart';
import 'package:doutu/shared/storage/app_settings.dart';

/// 内存版 settings notifier（widget 测试 FakeAsync 下不能用真实文件 IO）。
class _FakeSettings extends SettingsNotifier {
  final AppSettings settings;

  _FakeSettings(this.settings);

  @override
  Future<AppSettings> build() async => settings;
}

/// 内存版历史 notifier。
class _FakeHistory extends HistoryNotifier {
  @override
  Future<List<Project>> build() async => const [];
}

/// 内存版色卡（避开 FakeAsync 下的 rootBundle IO）。
final _testPalette = Palette(
  id: 'mard_221',
  displayName: 'MARD 221',
  entries: [
    PaletteEntry(code: 'A01', hex: '#FAF4C8', r: 250, g: 244, b: 200),
    PaletteEntry(code: 'H02', hex: '#FEFFFF', r: 254, g: 255, b: 255),
    PaletteEntry(code: 'H07', hex: '#000000', r: 0, g: 0, b: 0),
  ],
);

void main() {
  // 默认 tourSeen=true，避免常规用例被首次引导覆盖层干扰。
  List<Override> overrides({AppSettings? settings}) => [
        settingsProvider.overrideWith(
          () => _FakeSettings(
              settings ?? const AppSettings(tourSeen: true)),
        ),
        historyProvider.overrideWith(_FakeHistory.new),
        palettesProvider.overrideWith((ref) async => {'mard_221': _testPalette}),
      ];

  testWidgets('首页渲染：标题与导入按钮', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: overrides(), child: const DoutuApp()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('豆图 · 拼豆图纸转化器'), findsOneWidget);
    expect(find.text('从相册选图'), findsOneWidget);
    expect(find.text('拍一张'), findsOneWidget);
    expect(find.textContaining('还没有作品'), findsOneWidget);
  });

  testWidgets('设置页：默认色卡为 MARD 221', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: overrides(), child: const DoutuApp()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('设置'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('⚙️ 设置'), findsOneWidget);
    expect(find.text('默认色卡'), findsOneWidget);
    expect(find.text('MARD 221'), findsWidgets);
    expect(find.text('默认板型'), findsOneWidget);
    // 设置页提供"再看一遍新手引导"入口
    expect(find.text('再看一遍新手引导'), findsOneWidget);
  });

  testWidgets('首次启动自动播放新手引导，跳过即关闭', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(settings: const AppSettings(tourSeen: false)),
        child: const DoutuApp(),
      ),
    );
    // 触发 post-frame 引导弹出
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // 引导第一步出现（标题与首页文案不同，精确匹配）
    expect(find.text('把照片变成拼豆图纸'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);

    // 跳过 → 覆盖层关闭
    await tester.tap(find.text('跳过'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('把照片变成拼豆图纸'), findsNothing);
  });
}
