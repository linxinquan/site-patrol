import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';

/// 首页板块标题（与待办标题 Frame 2131330676 同款规范）：
/// 主标题 16/W600/fg + 可选副标题徽标（surface2 实色底灰字）
/// + 右侧"查看全部"12/W400/muted + 16px 箭头（同待办标题，muted 灰）。
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
            // 主标题（16/W600，与待办标题一致）
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                height: 24 / 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
                color: AppTokens.fg,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTokens.surface2,
                  borderRadius:
                      BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: AppTokens.muted,
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
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppTokens.muted,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        actionIcon ?? MingCuteIcons.rightLine,
                        size: 16,
                        color: AppTokens.muted,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}
