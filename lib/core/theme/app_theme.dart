import 'package:flutter/material.dart';
import 'design_tokens.dart';

ThemeData get lightTheme => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppTokens.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTokens.accent,
        primary: AppTokens.accent,
        surface: AppTokens.surface,
        error: AppTokens.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.surface,
        foregroundColor: AppTokens.fg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: AppTokens.fg),
      ),
      cardTheme: CardThemeData(
        color: AppTokens.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusLg)),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: AppTokens.fg, fontSize: 14, height: 1.6),
        bodySmall: TextStyle(color: AppTokens.muted, fontSize: 13),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppTokens.surface,
        selectedItemColor: AppTokens.accent,
        unselectedItemColor: AppTokens.muted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      dividerColor: AppTokens.border,
    );

/// 巡场深色沉浸主题（P5 接入真实 GPS 轨迹时使用）。
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
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.patrolBg,
        foregroundColor: AppTokens.patrolFg,
        elevation: 0,
      ),
    );
