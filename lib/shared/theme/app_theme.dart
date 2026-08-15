/// 可爱系主题：糖果配色、大圆角、圆润字体。
library;

import 'package:flutter/material.dart';

/// 配色系统（dev-plan 3.2）。
abstract class AppColors {
  static const bg = Color(0xFFFFF8F3); // 暖白底
  static const card = Color(0xFFFFFFFF); // 卡片白
  static const primary = Color(0xFFFF6B9D); // 糖果粉 · 主色
  static const secondary = Color(0xFF6BCFB5); // 薄荷绿 · 副色
  static const accentYellow = Color(0xFFFFD93D); // 亮黄
  static const accentBlue = Color(0xFF6FB1FC); // 天蓝
  static const accentLavender = Color(0xFFC89BFF); // 薰衣草
  static const accentOrange = Color(0xFFFFA45C); // 蜜橙
  static const textMain = Color(0xFF3D2E2A); // 暖棕正文
  static const textSecondary = Color(0xFF9B8B82); // 次要灰
  static const border = Color(0xFFF0E6DD); // 边框
}

/// 圆角规范（dev-plan 3.4）。
abstract class AppRadius {
  static const button = 16.0;
  static const card = 16.0;
  static const input = 12.0;
  static const chip = 999.0;
}

/// 柔和阴影（dev-plan 3.4 卡片阴影）。
const kCardShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x0DFF6B9D),
    blurRadius: 12,
    offset: Offset(0, 2),
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
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'WorkSans',
        fontWeight: FontWeight.w600,
        fontSize: 18,
        color: AppColors.textMain,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'WorkSans',
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'WorkSans',
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.card,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textMain,
      contentTextStyle: const TextStyle(
        fontFamily: 'WorkSans',
        color: Colors.white,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// 数字/英文展示字体（EricaOne，dev-plan 3.3）。
const kDisplayTextStyle = TextStyle(
  fontFamily: 'EricaOne',
  fontSize: 24,
  color: AppColors.textMain,
);

/// 色号/数据字体（JetBrainsMono）。
const kMonoTextStyle = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 14,
  color: AppColors.textMain,
);
