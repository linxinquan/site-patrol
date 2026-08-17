import 'package:flutter/material.dart';

/// 设计 Token：iOS 风格扁平化（浅色）。
/// 配色对齐 iOS 系统色 + 原生原型主色，采用无重阴影、大圆角、浅灰分组背景。
class AppTokens {
  // —— 主色（保留品牌识别）——
  static const Color accent = Color(0xFFEA580C); // iOS 橙（原生主操作色）
  static const Color accentHover = Color(0xFFC2410C);
  static const Color accentActive = Color(0xFF9A3412);
  static const Color accentSoft = Color(0xFFFFEDD5);
  static const Color brand = Color(0xFF007AFF); // iOS 系统蓝
  static const Color brandHover = Color(0xFF0066CC);
  static const Color brandSoft = Color(0xFFE5F1FF);

  // —— iOS 系统色 ——
  static const Color iosGreen = Color(0xFF34C759);
  static const Color iosRed = Color(0xFFFF3B30);
  static const Color iosOrange = Color(0xFFFF9500);
  static const Color iosYellow = Color(0xFFFFCC00);
  static const Color iosTeal = Color(0xFF5AC8FA);

  // —— 语义色（映射 iOS）——
  static const Color success = Color(0xFF34C759);
  static const Color successSoft = Color(0xFFE6F8ED);
  static const Color warning = Color(0xFFFF9500);
  static const Color warningSoft = Color(0xFFFFF3E0);
  static const Color danger = Color(0xFFFF3B30);
  static const Color dangerSoft = Color(0xFFFFEBEA);

  // —— 背景与表面（iOS 分组样式）——
  static const Color bg = Color(0xFFF2F2F7); // iOS 系统分组背景
  static const Color surface = Color(0xFFFFFFFF); // 卡片
  static const Color surface2 = Color(0xFFF8F8FA); // 次级填充
  static const Color surface3 = Color(0xFFEFEFF4); // 输入/嵌入底

  // —— 文字 ——
  static const Color fg = Color(0xFF000000); // iOS 主文字纯黑
  static const Color fg2 = Color(0xFF3C3C43); // 次级文字
  static const Color muted = Color(0xFF8E8E93); // iOS 系统灰
  static const Color mutedA11y = Color(0xFF6C6C70); // 可访问灰

  // —— 分割线/边框 ——
  static const Color border = Color(0xFFE5E5EA); // iOS 分割线
  static const Color borderStrong = Color(0xFFC7C7CC);

  // —— 固定字色 ——
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color onBrand = Color(0xFFFFFFFF);

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

  // —— 圆角（iOS 大圆角）——
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 22;
  static const double radiusPill = 999;

  // —— 阴影（iOS 极轻扁平，几乎无投影）——
  static List<BoxShadow> get elevationRaised => const [
        BoxShadow(
          color: Color(0x14000000), // 8% 黑
          blurRadius: 8,
          offset: Offset(0, 1),
        ),
      ];
  static List<BoxShadow> get elevationOverlay => const [
        BoxShadow(
          color: Color(0x1F000000), // 12% 黑
          blurRadius: 32,
          offset: Offset(0, 10),
        ),
      ];
  static List<BoxShadow> get elevationNone => const [];

  // —— 结构尺寸 ——
  static const double tabbarH = 64;
  static const double statusbarH = 28;
}
