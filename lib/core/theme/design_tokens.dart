import 'package:flutter/material.dart';

/// 设计 Token：扁平化（浅色）风格。
/// 主色为品牌蓝 #0395FF（accent 与 brand 已统一）；无重阴影、统一圆角、浅灰背景。
class AppTokens {
  // —— 主色（品牌蓝 #0395FF，accent 令牌族与 brand 同源）——
  static const Color accent = Color(0xFF0395FF); // 品牌蓝（全局主操作色）
  static const Color accentHover = Color(0xFF0284E6);
  static const Color accentActive = Color(0xFF0273CC);
  static const Color accentSoft = Color(0xFFE6F5FF);
  static const Color brand = Color(0xFF0395FF); // 主色（链接 / 图纸 / 主操作蓝）
  static const Color brandHover = Color(0xFF0273CC);
  static const Color brandSoft = Color(0xFFE6F5FF);

  // —— 语义色（状态语义：成功 / 警告 / 危险；自有规范色）——
  // Soft = 图标底 / 弹层等「块面」浅底；Tint = 标签浅底（原色 5% 透明度，见下方标签浅底段）。
  static const Color success = Color(0xFF34C759);
  static const Color successSoft = Color(0xFFE6F8ED);
  static const Color warning = Color(0xFFFF9500);
  static const Color warningSoft = Color(0xFFFFF3E0);
  static const Color danger = Color(0xFFFF3B30);
  static const Color dangerSoft = Color(0xFFFFEBEA);

  // —— 标签浅底（= 标签原色 5% 透明度，alpha 0x0D）——
  // 规则：所有标签的浅底一律取自身文字色的 5% 透明度；
  // 例外：灰标签（类型 / #自定义标签 / 楼栋楼层）仍用 surface2 #F4F6F7 实色底。
  static const Color brandTint = Color(0x0D0395FF); // 主色标签底
  static const Color successTint = Color(0x0D34C759); // 轻微 / 成功标签底
  static const Color warningTint = Color(0x0DFF9500); // 较重 / 警告标签底
  static const Color dangerTint = Color(0x0DFF3B30); // 严重 / 危险 / 楼层标签底
  static const Color yellowTint = Color(0x0DFADC19); // 一般标签底

  // —— 背景与表面 ——
  static const Color bg = Color(0xFFF4F6F7); // 页面全局背景
  static const Color surface = Color(0xFFFFFFFF); // 卡片 / 弹层表面
  static const Color surface2 = Color(0xFFF4F6F7); // 次级填充（图标底、小标签底）
  static const Color surface3 = Color(0xFFE9EAEB); // 输入框 / 嵌入底（禁用态灰底等）

  // —— 文字 ——
  static const Color fg = Color(0xFF202224); // 主文字
  static const Color fg2 = Color(0xFF60656B); // 次级文字
  static const Color muted = Color(0xFF919499); // 辅助弱化文字
  static const Color note = Color(0xFFB5B9BF); // 注释文字说明（最弱一档，用于补充说明/脚注）

  // —— 分割线 / 边框 ——
  static const Color border = Color(0xFFE9EAEB); // 分割线、卡片细边框

  // —— 固定字色 ——
  static const Color onAccent = Color(0xFFFFFFFF); // 蓝底白字（原浅金底深字已废弃）
  static const Color onBrand = Color(0xFFFFFFFF); // 蓝底白字

  // —— 巡场深色沉浸主题（占位，P5 用）——
  static const Color patrolBg = Color(0xFF0B1220);
  static const Color patrolSurface = Color(0xFF111A2E);
  static const Color patrolSurface2 = Color(0xFF1A2540);
  static const Color patrolFg = Color(0xFFE8EEF6);
  static const Color patrolMuted = Color(0xFF94A3B8);
  static const Color patrolBorder = Color(0xFF1E293B);

  // —— 间距（4px 网格：4 / 8 / 12 / 16 / 24 / 32 / 48）——
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space7 = 48;

  // —— 圆角：外层卡片（AppCard 容器）12；内层卡/小标签 8；按钮 12；胶囊 999 不变 ——
  static const double radiusSm = 8;
  static const double radiusMd = 8;
  static const double radiusLg = 12; // 外层卡片统一 12
  static const double radiusXl = 8;
  static const double radiusPill = 999;
  static const double radiusButton = 12; // 主操作按钮统一 12（实色 / 描边 / 文字三形态）

  // —— 按钮三档（高度为权威值：文字在固定高度内垂直居中，不再由上下 padding 撑高）——
  static const double buttonH_lg = 48; // 大按钮高度（严格 48）
  static const double buttonH_md = 36; // 中按钮高度（默认档）
  static const double buttonH_sm = 32; // 小按钮高度
  static const double buttonPadX_lg = 24; // 大按钮左右 padding 下限
  static const double buttonPadX_md = 12; // 中按钮左右 padding 下限
  static const double buttonPadX_sm = 12; // 小按钮左右 padding 下限

  // —— 阴影（按设计规范：所有卡片取消投影、统一扁平化，令牌置空）——
  static List<BoxShadow> get elevationRaised => const [];
  static List<BoxShadow> get elevationOverlay => const [];
  static List<BoxShadow> get elevationNone => const [];

  // —— 结构尺寸 ——
  // iOS 标准 tab bar 高度 49pt（不含底部 home indicator 安全区）。
  static const double tabbarH = 49;
  static const double statusbarH = 28;
}
