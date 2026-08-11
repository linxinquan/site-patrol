import 'package:flutter/material.dart';

/// 设计 Token：照搬原型 styles.css 的 :root 变量（临时主题，集中在此便于后续整体换皮）。
class AppTokens {
  // —— 浅色主题（默认）——
  static const Color accent = Color(0xFFEA580C);
  static const Color accentHover = Color(0xFFC2410C);
  static const Color accentActive = Color(0xFF9A3412);
  static const Color accentSoft = Color(0xFFFFEDD5);
  static const Color brand = Color(0xFF1D4ED8);
  static const Color brandHover = Color(0xFF1E40AF);
  static const Color brandSoft = Color(0xFFDBEAFE);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFF1F5F9);
  static const Color fg = Color(0xFF0F172A);
  static const Color muted = Color(0xFF64748B);
  static const Color mutedA11y = Color(0xFF475569);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);
  static const Color success = Color(0xFF16A34A);
  static const Color successSoft = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFCA8A04);
  static const Color warningSoft = Color(0xFFFEF9C3);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFEE2E2);
  static const Color onAccent = Color(0xFFFFFFFF);

  // —— 巡场深色沉浸主题（占位，P5 用）——
  static const Color patrolBg = Color(0xFF0B1220);
  static const Color patrolSurface = Color(0xFF111A2E);
  static const Color patrolSurface2 = Color(0xFF1A2540);
  static const Color patrolFg = Color(0xFFE8EEF6);
  static const Color patrolMuted = Color(0xFF94A3B8);
  static const Color patrolBorder = Color(0xFF1E293B);

  // —— 间距（4px 网格）——
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space7 = 32;
  static const double space8 = 40;

  // —— 圆角 ——
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 999;

  // —— 阴影 ——
  static List<BoxShadow> get elevationRaised => [
        BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 2,
            offset: const Offset(0, 1)),
        BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1)),
      ];
  static List<BoxShadow> get elevationOverlay => [
        BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 10)),
      ];

  // —— 结构尺寸 ——
  static const double tabbarH = 64;
  static const double statusbarH = 28;
}
