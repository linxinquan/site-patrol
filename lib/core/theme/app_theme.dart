import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// iOS 风格浅色主题（扁平化）。
/// 字体：各平台系统默认字体（iOS 苹方 / SF Pro，Android Roboto + 思源黑体，
/// Web 通过 HTML 渲染器使用系统字体：Windows 微软雅黑 / Mac 苹方）。不打包自定义字体。
ThemeData get lightTheme => ThemeData(
      useMaterial3: true,
      // iOS 操作习惯：去除 Material 水波纹与悬停高亮，图标/按钮不做浏览器式 hover
      splashFactory: NoSplash.splashFactory,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      // 全局去除悬浮提示（含 AppBar 自动返回键自带的 "Back" 文字气泡）
      tooltipTheme: const TooltipThemeData(triggerMode: TooltipTriggerMode.manual),
      // 图标按钮不做浏览器式 hover：浮层/高亮全透明
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      scaffoldBackgroundColor: AppTokens.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTokens.accent,
        primary: AppTokens.accent,
        surface: AppTokens.surface,
        error: AppTokens.danger,
      ),
      // 不强制自定义字体：fontFamily 为 null 时 Flutter 自动使用各平台系统默认字体。
      // fontFamilyFallback 仅作兜底（主要影响 Web HTML 渲染器的 CSS 字体栈）。
      fontFamily: null,
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'Noto Sans CJK SC',
        'Source Han Sans SC',
        'sans-serif',
      ],
      // 字号阶梯（六档：32/22/16/14/12/10，字距统一 0，字重仅 w400/w700）
      textTheme: const TextTheme(
        // 大标题（如项目名） — SF Pro Display 风格
        displaySmall: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppTokens.fg,
          height: 1.25,
        ),
        // 中标题（如 section）
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppTokens.fg,
          height: 30 / 22,
        ),
        // 小标题（如卡名）
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppTokens.fg,
          height: 24 / 16,
        ),
        // 卡内标题
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppTokens.fg,
          height: 24 / 16,
        ),
        // 正文
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: AppTokens.fg,
          height: 24 / 16,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: AppTokens.fg,
          height: 22 / 14,
        ),
        // 辅助文字
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: AppTokens.muted,
          height: 20 / 12,
        ),
        // 按钮 / 强调
        labelLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppTokens.fg,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppTokens.fg,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
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
        // 不写死 toolbarHeight：交给 Flutter 系统默认（kToolbarHeight=56），
        // 且系统会自动在工具栏上方叠加状态栏留白，自动适配无刘海/刘海/灵动岛。
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
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
        selectedItemColor: AppTokens.fg,
        unselectedItemColor: AppTokens.muted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      // 按钮默认 = 中档（高度36 严格 / 左右padding≥12 / 圆角12 / 白字 / 14·w700·行高22）
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppTokens.accent,
          foregroundColor: AppTokens.onAccent,
          minimumSize: const Size(0, AppTokens.buttonH_md),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.buttonPadX_md),
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.all(Radius.circular(AppTokens.radiusButton))),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            height: 22 / 14,
            color: AppTokens.onAccent,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTokens.accent,
          side: BorderSide(color: AppTokens.accent),
          minimumSize: const Size(0, AppTokens.buttonH_md),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.buttonPadX_md),
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.all(Radius.circular(AppTokens.radiusButton))),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            height: 22 / 14,
            color: AppTokens.accent,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppTokens.accent,
          minimumSize: const Size(0, AppTokens.buttonH_md),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.buttonPadX_md),
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.all(Radius.circular(AppTokens.radiusButton))),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            height: 22 / 14,
            color: AppTokens.accent,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF2C2C2E),
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w400,
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
      // 巡场深色页同样关闭悬浮提示
      tooltipTheme: const TooltipThemeData(triggerMode: TooltipTriggerMode.manual),
      scaffoldBackgroundColor: AppTokens.patrolBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTokens.accent,
        brightness: Brightness.dark,
        primary: AppTokens.accent,
        surface: AppTokens.patrolSurface,
      ),
      fontFamily: null,
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'Noto Sans CJK SC',
        'sans-serif',
      ],
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.patrolBg,
        foregroundColor: AppTokens.patrolFg,
        elevation: 0,
      ),
    );