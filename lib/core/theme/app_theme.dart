import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// iOS 风格浅色主题（扁平化）。
/// 字体：Inter (≈ SF Pro Text/Display) + Nunito (数字圆润)。
ThemeData get lightTheme => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppTokens.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTokens.accent,
        primary: AppTokens.accent,
        surface: AppTokens.surface,
        error: AppTokens.danger,
      ),
      // iOS 风格字体栈：Inter 是 SF Pro 的开源近似；-apple-system 在 macOS/iOS 走原生 SF
      fontFamily: 'Inter',
      fontFamilyFallback: const [
        '-apple-system',
        'BlinkMacSystemFont',
        'SF Pro Text',
        'Helvetica Neue',
        'PingFang SC',
        'Microsoft YaHei',
        'sans-serif',
      ],
      // iOS 风格的字号阶梯（更紧凑、字间距 -0.01em）
      textTheme: const TextTheme(
        // 大标题（如项目名） — SF Pro Display 风格
        displaySmall: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          color: AppTokens.fg,
          height: 1.15,
        ),
        // 中标题（如 section）
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: AppTokens.fg,
          height: 1.2,
        ),
        // 小标题（如卡名）
        titleLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: AppTokens.fg,
          height: 1.25,
        ),
        // 卡内标题
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: AppTokens.fg,
          height: 1.3,
        ),
        // 正文
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.1,
          color: AppTokens.fg,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.1,
          color: AppTokens.fg,
          height: 1.45,
        ),
        // 辅助文字
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: AppTokens.muted,
          height: 1.35,
        ),
        // 按钮 / 强调
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: AppTokens.fg,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: AppTokens.fg,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: AppTokens.muted,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.bg,
        foregroundColor: AppTokens.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: AppTokens.fg,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppTokens.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.all(Radius.circular(AppTokens.radiusLg))),
      ),
      dividerColor: AppTokens.border,
      dividerTheme: const DividerThemeData(
          color: AppTokens.border, thickness: 0.5, space: 1),
      listTileTheme: const ListTileThemeData(
        tileColor: AppTokens.surface,
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.all(Radius.circular(AppTokens.radiusMd))),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppTokens.surface,
        selectedItemColor: AppTokens.accent,
        unselectedItemColor: AppTokens.muted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppTokens.accent,
          foregroundColor: AppTokens.onAccent,
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.all(Radius.circular(AppTokens.radiusPill))),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: Colors.white,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.all(Radius.circular(AppTokens.radiusPill))),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF2C2C2E),
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.all(Radius.circular(AppTokens.radiusMd))),
      ),
    );

/// 巡场深色沉浸主题。
ThemeData get patrolDarkTheme => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppTokens.patrolBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTokens.accent,
        brightness: Brightness.dark,
        primary: AppTokens.accent,
        surface: AppTokens.patrolSurface,
      ),
      fontFamily: 'Inter',
      fontFamilyFallback: const [
        '-apple-system',
        'SF Pro Text',
        'Helvetica Neue',
        'PingFang SC',
      ],
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.patrolBg,
        foregroundColor: AppTokens.patrolFg,
        elevation: 0,
      ),
    );