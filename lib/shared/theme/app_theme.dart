/// 苹果官网风格主题：白底极简、大标题、苹果蓝主色、胶囊按钮、发丝级描边。
///
/// 仿照 apple.com 的设计语言：
/// - 背景纯白 / 浅灰分区（#F5F5F7）
/// - 主色苹果蓝 #0071E3，正文 #1D1D1F，次要文字 #6E6E73
/// - 按钮为全圆角胶囊（StadiumBorder）
/// - 卡片圆角 18，发丝级描边，少阴影
library;

import 'package:flutter/material.dart';

/// 配色系统（仿苹果官网）。
abstract class AppColors {
  static const bg = Color(0xFFFFFFFF); // 纯白底
  static const sectionBg = Color(0xFFF5F5F7); // 浅灰分区底
  static const fill = Color(0xFFF5F5F7); // 输入框 / 浅填充
  static const card = Color(0xFFFFFFFF); // 卡片白
  static const primary = Color(0xFF0071E3); // 苹果蓝 · 主色
  static const secondary = Color(0xFF1D1D1F); // 近黑 · 强调色
  static const accentYellow = Color(0xFFFF9F0A); // 系统橙（警示/高亮）
  static const accentBlue = Color(0xFF0071E3); // 天蓝（同主色）
  static const accentLavender = Color(0xFF86868B); // 中性灰
  static const accentOrange = Color(0xFFFF9F0A); // 蜜橙（警示）
  static const success = Color(0xFF34C759); // 系统绿（成功）
  static const danger = Color(0xFFFF3B30); // 系统红
  static const textMain = Color(0xFF1D1D1F); // 近黑正文
  static const textSecondary = Color(0xFF6E6E73); // 次要灰
  static const border = Color(0xFFE8E8ED); // 发丝级描边
}

/// 圆角规范（苹果风格：按钮全圆角胶囊、卡片大圆角）。
abstract class AppRadius {
  static const button = 980.0; // 胶囊按钮
  static const card = 18.0;
  static const input = 12.0;
  static const chip = 999.0;
}

/// 柔和阴影（苹果官网卡片阴影：轻微下坠）。
const kCardShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x1A000000),
    blurRadius: 24,
    offset: Offset(0, 8),
  ),
];

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.bg,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'WorkSans',
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textMain,
      displayColor: AppColors.textMain,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.textMain,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'WorkSans',
        fontWeight: FontWeight.w700,
        fontSize: 17,
        color: AppColors.textMain,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF86868B).withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'WorkSans',
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'WorkSans',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(
          fontFamily: 'WorkSans',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.fill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.fill,
      selectedColor: AppColors.primary,
      labelStyle: const TextStyle(
        fontFamily: 'WorkSans',
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: AppColors.textMain,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: 'WorkSans',
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.success
            : const Color(0xFFE9E9EA),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.primary,
      thumbColor: Colors.white,
      overlayColor: AppColors.primary.withValues(alpha: 0.12),
      inactiveTrackColor: const Color(0xFFE9E9EA),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.bg,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.secondary,
      contentTextStyle: const TextStyle(
        fontFamily: 'WorkSans',
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      elevation: 24,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'WorkSans',
        fontWeight: FontWeight.w700,
        fontSize: 17,
        color: AppColors.textMain,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'WorkSans',
        fontSize: 14,
        height: 1.5,
        color: AppColors.textSecondary,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
  );
}

/// 大标题展示字体（苹果官网式大标题）。
const kDisplayTextStyle = TextStyle(
  fontFamily: 'WorkSans',
  fontWeight: FontWeight.w700,
  fontSize: 30,
  height: 1.15,
  letterSpacing: -0.5,
  color: AppColors.textMain,
);

/// 色号/数据字体（JetBrainsMono）。
const kMonoTextStyle = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 14,
  color: AppColors.textMain,
);
