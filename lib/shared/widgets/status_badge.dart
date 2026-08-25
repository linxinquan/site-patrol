import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';

/// 通用状态标签（胶囊）。
/// 底色规则：默认 = 文字色 5% 透明度（`color.withValues(alpha: 0.05)`）；
/// 仅需要实色底的灰标签才显式传 [bg]（如 surface2 #F4F6F7）。
class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color? bg;
  /// 字重：默认 W700（兼容既有调用）；浅底标签规范为 12/W400，可显式传 W400。
  final FontWeight? fontWeight;
  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
    this.bg,
    this.fontWeight,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg ?? color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: fontWeight ?? FontWeight.w700),
        ),
      );
}
