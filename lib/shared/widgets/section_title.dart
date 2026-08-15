import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';

/// iOS 风格分组头部：
/// 主标题（大字 SF Pro Display）+ 右上描述小字 + 右侧"查看全部"操作。
/// 紧凑、左右对齐、视觉重心明确。
class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.space2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 主标题（iOS SF 风：粗体、稍大字）
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: AppTokens.fg,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTokens.accentSoft,
                  borderRadius:
                      BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.accent,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (action != null)
              InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        action!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.accent,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        actionIcon ?? LucideIcons.chevronRight,
                        size: 13,
                        color: AppTokens.accent,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}
