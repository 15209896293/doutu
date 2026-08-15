/// App 设置：默认色卡 / 默认板型 / 转换偏好 / 新手引导状态。
library;

import 'dart:convert';
import 'dart:io';

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

  /// 是否已看过新手引导（product tour）。
  final bool tourSeen;

  /// 是否已看过裁剪页的「自动提取主体」引导。
  final bool cropTourSeen;

  const AppSettings({
    this.paletteId = 'mard_221',
    this.boardId = '81',
    this.customBoardSize = 52,
    this.maxColors = 0,
    this.dither = true,
    this.removeBackground = true,
    this.tourSeen = false,
    this.cropTourSeen = false,
  });

  AppSettings copyWith({
    String? paletteId,
    String? boardId,
    int? customBoardSize,
    int? maxColors,
    bool? dither,
    bool? removeBackground,
    bool? tourSeen,
    bool? cropTourSeen,
  }) {
    return AppSettings(
      paletteId: paletteId ?? this.paletteId,
      boardId: boardId ?? this.boardId,
      customBoardSize: customBoardSize ?? this.customBoardSize,
      maxColors: maxColors ?? this.maxColors,
      dither: dither ?? this.dither,
      removeBackground: removeBackground ?? this.removeBackground,
      tourSeen: tourSeen ?? this.tourSeen,
      cropTourSeen: cropTourSeen ?? this.cropTourSeen,
    );
  }

  Map<String, dynamic> toJson() => {
        'paletteId': paletteId,
        'boardId': boardId,
        'customBoardSize': customBoardSize,
        'maxColors': maxColors,
        'dither': dither,
        'removeBackground': removeBackground,
        'tourSeen': tourSeen,
        'cropTourSeen': cropTourSeen,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        paletteId: json['paletteId'] as String? ?? 'mard_221',
        boardId: json['boardId'] as String? ?? '81',
        customBoardSize: json['customBoardSize'] as int? ?? 52,
        maxColors: json['maxColors'] as int? ?? 0,
        dither: json['dither'] as bool? ?? true,
        removeBackground: json['removeBackground'] as bool? ?? true,
        tourSeen: json['tourSeen'] as bool? ?? false,
        cropTourSeen: json['cropTourSeen'] as bool? ?? false,
      );
}

/// 设置存储（JSON 文件）。
class SettingsStore {
  final File file;

  SettingsStore(this.file);

  Future<AppSettings> load() async {
    if (!await file.exists()) return const AppSettings();
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AppSettings.fromJson(json);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }
}
