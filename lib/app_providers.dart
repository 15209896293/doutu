/// 全局 Riverpod providers：设置 / 色卡 / 转换状态 / 历史。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/convert_isolate.dart';
import 'core/palette.dart';
import 'core/palette_repository.dart';
import 'core/pattern_converter.dart';
import 'models/board_preset.dart';
import 'models/pattern.dart';
import 'models/project.dart';
import 'shared/storage/app_settings.dart';
import 'shared/storage/craft_progress_store.dart';
import 'shared/storage/inventory_store.dart';
import 'shared/storage/project_store.dart';

// ---------------------------------------------------------------------------
// 基础服务
// ---------------------------------------------------------------------------

/// 设置存储（惰性初始化）。
final settingsStoreProvider = FutureProvider<SettingsStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return SettingsStore(File('${dir.path}${Platform.pathSeparator}settings.json'));
});

/// 作品存储。
final projectStoreProvider = FutureProvider<ProjectStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return ProjectStore(
    Directory('${dir.path}${Platform.pathSeparator}projects'),
  );
});

/// 跟做进度存储。
final craftProgressStoreProvider =
    FutureProvider<CraftProgressStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return CraftProgressStore(
    File('${dir.path}${Platform.pathSeparator}craft_progress.json'),
  );
});

/// 库存存储。
final inventoryStoreProvider = FutureProvider<InventoryStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return InventoryStore(
    File('${dir.path}${Platform.pathSeparator}inventory.json'),
  );
});

// ---------------------------------------------------------------------------
// 设置
// ---------------------------------------------------------------------------

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final store = await ref.watch(settingsStoreProvider.future);
    return store.load();
  }

  Future<void> saveSettings(AppSettings next) async {
    final store = await ref.read(settingsStoreProvider.future);
    await store.save(next);
    state = AsyncData(next);
  }
}

// ---------------------------------------------------------------------------
// 库存
// ---------------------------------------------------------------------------

final inventoryProvider =
    AsyncNotifierProvider<InventoryNotifier, Map<String, Map<String, int>>>(
  InventoryNotifier.new,
);

class InventoryNotifier extends AsyncNotifier<Map<String, Map<String, int>>> {
  @override
  Future<Map<String, Map<String, int>>> build() async {
    final store = await ref.watch(inventoryStoreProvider.future);
    return store.load();
  }

  /// 设置某色卡某色号的已有颗数；count<=0 时移除该色号。
  Future<void> setCount(String paletteId, String code, int count) async {
    final store = await ref.read(inventoryStoreProvider.future);
    final next = <String, Map<String, int>>{
      for (final e in (state.valueOrNull ?? const {}).entries)
        e.key: Map<String, int>.of(e.value),
    };
    final perPalette = next[paletteId] ?? <String, int>{};
    if (count <= 0) {
      perPalette.remove(code);
    } else {
      perPalette[code] = count;
    }
    next[paletteId] = perPalette;
    await store.save(next);
    state = AsyncData(next);
  }

  /// 清空某色卡的全部库存。
  Future<void> clearPalette(String paletteId) async {
    final store = await ref.read(inventoryStoreProvider.future);
    final next = <String, Map<String, int>>{
      for (final e in (state.valueOrNull ?? const {}).entries)
        if (e.key != paletteId) e.key: Map<String, int>.of(e.value),
    };
    await store.save(next);
    state = AsyncData(next);
  }
}

// ---------------------------------------------------------------------------
// 色卡
// ---------------------------------------------------------------------------

final palettesProvider =
    FutureProvider<Map<String, Palette>>((ref) async {
  final map = <String, Palette>{};
  for (final meta in kPaletteMetas) {
    final json = await rootBundle.loadString(meta.assetPath);
    map[meta.id] = loadPaletteFromString(meta, json);
  }
  return map;
});

/// 当前生效色卡（跟随设置）。
final activePaletteProvider = Provider<AsyncValue<Palette>>((ref) {
  final palettes = ref.watch(palettesProvider);
  final settings = ref.watch(settingsProvider);
  return palettes.whenData((map) {
    final id = settings.valueOrNull?.paletteId ?? 'mard_221';
    return map[id] ?? map['mard_221']!;
  });
});

/// 当前图纸实际使用的色卡：优先按图纸记录的 paletteId 解析。
/// 修复：保存的作品在切换默认色卡后，仍按生成时的色卡正确渲染。
final paletteForPatternProvider = Provider<AsyncValue<Palette>>((ref) {
  final palettes = ref.watch(palettesProvider);
  final conv = ref.watch(conversionProvider);
  final id = conv.pattern?.paletteId ??
      ref.watch(settingsProvider).valueOrNull?.paletteId ??
      'mard_221';
  return palettes.whenData((map) => map[id] ?? map['mard_221']!);
});

// ---------------------------------------------------------------------------
// 转换流程状态
// ---------------------------------------------------------------------------

enum ConversionStatus { empty, picked, converting, done, error }

/// 转换流程状态。
class ConversionState {
  final ConversionStatus status;

  /// 已选/裁剪后的图片字节。
  final Uint8List? imageBytes;

  /// 板型（决定网格边长与掩码）。
  final BoardPreset board;

  /// 转换参数（网格尺寸由板型决定，其余可调）。
  final ConvertOptions options;

  /// 转换结果。
  final Pattern? pattern;

  /// 每格平均色（原图对比视图用）。
  final List<int> avgColors;

  /// 错误信息。
  final String? error;

  /// 当前编辑的网格副本（编辑器修改时与 pattern 分离）。
  final List<int>? editedGrid;

  const ConversionState({
    this.status = ConversionStatus.empty,
    this.imageBytes,
    this.board = const BoardPreset(id: '81', label: '81×81', size: 81),
    this.options = const ConvertOptions(gridSize: 81),
    this.pattern,
    this.avgColors = const [],
    this.error,
    this.editedGrid,
  });

  ConversionState copyWith({
    ConversionStatus? status,
    Uint8List? imageBytes,
    BoardPreset? board,
    ConvertOptions? options,
    Pattern? pattern,
    List<int>? avgColors,
    String? error,
    List<int>? editedGrid,
    bool clearPattern = false,
    bool clearEditedGrid = false,
  }) {
    return ConversionState(
      status: status ?? this.status,
      imageBytes: imageBytes ?? this.imageBytes,
      board: board ?? this.board,
      options: options ?? this.options,
      pattern: clearPattern ? null : (pattern ?? this.pattern),
      avgColors: avgColors ?? this.avgColors,
      error: error ?? this.error,
      editedGrid: clearEditedGrid
          ? null
          : (editedGrid ?? this.editedGrid),
    );
  }
}

final conversionProvider =
    NotifierProvider<ConversionNotifier, ConversionState>(
  ConversionNotifier.new,
);

class ConversionNotifier extends Notifier<ConversionState> {
  @override
  ConversionState build() => const ConversionState();

  /// 设置导入图片（按用户设置初始化板型与参数）。
  void setImage(Uint8List bytes, {AppSettings? settings}) {
    final board = settings == null
        ? const BoardPreset(id: '81', label: '81×81', size: 81)
        : _boardFromSettings(settings);
    final opts = settings == null
        ? ConvertOptions(gridSize: board.size)
        : _optionsFromSettings(settings, board);
    state = ConversionState(imageBytes: bytes, board: board, options: opts);
  }

  /// 设置板型（同步更新网格尺寸与掩码）。
  void setBoard(BoardPreset board) {
    state = state.copyWith(
      board: board,
      options: ConvertOptions(
        gridSize: board.size,
        maxColors: state.options.maxColors,
        dither: state.options.dither,
        removeBackground: state.options.removeBackground,
        minBlockSize: state.options.minBlockSize,
        maskShape: board.shape == BoardShape.circle ? 'circle' : null,
        restrictToOwned: state.options.restrictToOwned,
      ),
      clearPattern: true,
      clearEditedGrid: true,
    );
  }

  /// 更新转换参数。
  void setOptions(ConvertOptions options) {
    state = state.copyWith(options: options);
  }

  /// 执行转换（在 isolate 中）。
  Future<void> convert(Palette palette, {List<int>? allowedIndices}) async {
    final bytes = state.imageBytes;
    if (bytes == null) return;
    state = state.copyWith(
      status: ConversionStatus.converting,
      error: null,
      clearPattern: true,
      clearEditedGrid: true,
    );
    final opts = allowedIndices == null
        ? state.options
        : state.options.copyWith(allowedIndices: allowedIndices);
    final response = await convertInBackground(ConvertRequest(
      imageBytes: bytes,
      palette: palette,
      options: opts,
    ));
    if (response.error != null) {
      state = state.copyWith(
        status: ConversionStatus.error,
        error: response.error,
      );
      return;
    }
    state = state.copyWith(
      status: ConversionStatus.done,
      pattern: response.pattern,
      avgColors: response.avgColors,
    );
  }

  /// 编辑器修改网格。
  void setEditedGrid(List<int> grid) {
    state = state.copyWith(editedGrid: List<int>.of(grid));
  }

  /// 编辑器确认修改（回写 pattern 并重算 BOM）。
  void commitEdit(Palette palette) {
    final edited = state.editedGrid;
    final pattern = state.pattern;
    if (edited == null || pattern == null) return;
    state = state.copyWith(
      pattern: Pattern(
        size: pattern.size,
        grid: List<int>.of(edited),
        paletteId: pattern.paletteId,
        bom: _buildBom(edited, palette),
      ),
      editedGrid: null,
    );
  }

  /// 打开已保存作品：把作品图纸载入转换状态，供预览/编辑/跟做/导出。
  void openProject(Project project) {
    final p = project.pattern;
    final opts = Project.optionsFrom(project.convertParams);
    final isCircle = opts.maskShape == 'circle';
    state = ConversionState(
      status: ConversionStatus.done,
      board: BoardPreset(
        id: isCircle && p.size == 29 ? '29c' : '${p.size}',
        label: isCircle && p.size == 29 ? '29 圆形' : '${p.size}×${p.size}',
        size: p.size,
        shape: isCircle ? BoardShape.circle : BoardShape.square,
      ),
      options: opts,
      pattern: p,
    );
  }

  /// 重置整个流程。
  void reset() {
    state = const ConversionState();
  }
}

List<BomEntry> _buildBom(List<int> grid, Palette palette) {
  final usage = <int, int>{};
  for (final idx in grid) {
    if (idx < 0) continue;
    usage[idx] = (usage[idx] ?? 0) + 1;
  }
  final entries = usage.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final e in entries)
      BomEntry(
        code: palette.entries[e.key].code,
        count: e.value,
        color: (palette.entries[e.key].r << 16) |
            (palette.entries[e.key].g << 8) |
            palette.entries[e.key].b,
        productCode: palette.entries[e.key].productCode,
        name: palette.entries[e.key].name,
      ),
  ];
}

/// 从用户设置还原板型。
BoardPreset _boardFromSettings(AppSettings s) {
  if (s.boardId == 'custom') {
    return BoardPreset(id: 'custom', label: '自定义', size: s.customBoardSize);
  }
  for (final b in BoardPreset.presets) {
    if (b.id == s.boardId) return b;
  }
  return const BoardPreset(id: '81', label: '81×81', size: 81);
}

/// 从用户设置还原转换参数。
ConvertOptions _optionsFromSettings(AppSettings s, BoardPreset board) {
  return ConvertOptions(
    gridSize: board.size,
    maxColors: s.maxColors,
    dither: s.dither,
    removeBackground: s.removeBackground,
    minBlockSize: 2,
    maskShape: board.shape == BoardShape.circle ? 'circle' : null,
  );
}

// ---------------------------------------------------------------------------
// 历史记录
// ---------------------------------------------------------------------------

final historyProvider = AsyncNotifierProvider<HistoryNotifier, List<Project>>(
  HistoryNotifier.new,
);

class HistoryNotifier extends AsyncNotifier<List<Project>> {
  @override
  Future<List<Project>> build() async {
    final store = await ref.watch(projectStoreProvider.future);
    return store.list();
  }

  /// 保存当前转换结果为作品。
  Future<Project?> saveCurrent(String name) async {
    final conv = ref.read(conversionProvider);
    final pattern = conv.pattern;
    if (pattern == null) return null;
    final store = await ref.read(projectStoreProvider.future);
    final now = DateTime.now();
    final id =
        '${now.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch % 1000000}';
    final project = Project(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
      convertParams: Project.paramsFrom(conv.options),
      pattern: pattern,
    );
    await store.save(project);
    await _reload();
    return project;
  }

  Future<void> delete(String id) async {
    final store = await ref.read(projectStoreProvider.future);
    await store.delete(id);
    await _reload();
  }

  Future<void> _reload() async {
    final store = await ref.read(projectStoreProvider.future);
    state = AsyncData(await store.list());
  }
}
