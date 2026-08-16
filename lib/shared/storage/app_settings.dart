/// App 设置：默认色卡 / 默认板型 / 转换偏好 / 新手引导状态。
library;

import 'dart:convert';

import 'app_storage.dart';

/// 设置值对象。
class AppSettings {
  /// 默认色卡 id（"mard_221"）。
  final String paletteId;

  /// 默认板型 id（"29"/"29c"/"52"/"81"/"128"/"custom"）。
  final String boardId;

  /// 自定义板型边长。
  final int customBoardSize;

  /// 默认色数上限（0 = 不限）。
  final int maxColors;

  /// 默认是否抖动。
  final bool dither;

  /// 默认是否移除背景。
  final bool removeBackground;

  /// 默认转换预设（simplified/standard/detailed/smooth）。
  final String presetId;

  /// 默认色差距离模式（"oklab"/"ciede2000"）。
  final String colorDistanceMode;

  /// 是否已看过新手引导（product tour）。
  final bool tourSeen;

  /// 是否已看过裁剪页的「自动提取主体」引导。
  final bool cropTourSeen;

  /// 可选：选图后自动框出图片主体（默认关闭）。
  final bool autoFrameSubject;

  const AppSettings({
    this.paletteId = 'mard_221',
    this.boardId = '81',
    this.customBoardSize = 52,
    this.maxColors = 10,
    this.dither = false,
    this.removeBackground = true,
    this.presetId = 'standard',
    this.colorDistanceMode = 'oklab',
    this.tourSeen = false,
    this.cropTourSeen = false,
    this.autoFrameSubject = false,
  });

  AppSettings copyWith({
    String? paletteId,
    String? boardId,
    int? customBoardSize,
    int? maxColors,
    bool? dither,
    bool? removeBackground,
    String? presetId,
    String? colorDistanceMode,
    bool? tourSeen,
    bool? cropTourSeen,
    bool? autoFrameSubject,
  }) {
    return AppSettings(
      paletteId: paletteId ?? this.paletteId,
      boardId: boardId ?? this.boardId,
      customBoardSize: customBoardSize ?? this.customBoardSize,
      maxColors: maxColors ?? this.maxColors,
      dither: dither ?? this.dither,
      removeBackground: removeBackground ?? this.removeBackground,
      presetId: presetId ?? this.presetId,
      colorDistanceMode: colorDistanceMode ?? this.colorDistanceMode,
      tourSeen: tourSeen ?? this.tourSeen,
      cropTourSeen: cropTourSeen ?? this.cropTourSeen,
      autoFrameSubject: autoFrameSubject ?? this.autoFrameSubject,
    );
  }

  Map<String, dynamic> toJson() => {
        'paletteId': paletteId,
        'boardId': boardId,
        'customBoardSize': customBoardSize,
        'maxColors': maxColors,
        'dither': dither,
        'removeBackground': removeBackground,
        'presetId': presetId,
        'colorDistanceMode': colorDistanceMode,
        'tourSeen': tourSeen,
        'cropTourSeen': cropTourSeen,
        'autoFrameSubject': autoFrameSubject,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        paletteId: json['paletteId'] as String? ?? 'mard_221',
        boardId: json['boardId'] as String? ?? '81',
        customBoardSize: json['customBoardSize'] as int? ?? 52,
        maxColors: json['maxColors'] as int? ?? 0,
        dither: json['dither'] as bool? ?? false,
        removeBackground: json['removeBackground'] as bool? ?? true,
        presetId: json['presetId'] as String? ?? 'standard',
        colorDistanceMode: json['colorDistanceMode'] as String? ?? 'oklab',
        tourSeen: json['tourSeen'] as bool? ?? false,
        cropTourSeen: json['cropTourSeen'] as bool? ?? false,
        autoFrameSubject: json['autoFrameSubject'] as bool? ?? false,
      );
}

/// 设置存储（跨端：io 文件 / web localStorage）。
class SettingsStore {
  final AppStorage storage;
  final String path;

  SettingsStore(this.storage, this.path);

  Future<AppSettings> load() async {
    final text = await storage.readText(path);
    if (text == null) return const AppSettings();
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      return AppSettings.fromJson(json);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await storage.writeText(path, jsonEncode(settings.toJson()));
  }
}
