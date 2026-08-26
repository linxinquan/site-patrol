import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';

/// 身份选择卡（共用组件）：选择身份页与首页切换用户底部弹层共用。
/// 白底圆角 12、最小高 72、padding 12、头像 48 + 姓名/角色徽标一行 + 单位一行。
/// 选中：1px 蓝边框 #428BF7（透明边框占位，避免内容位移）。
class IdentityTile extends StatelessWidget {
  final User user;
  final bool selected;
  final VoidCallback onTap;
  const IdentityTile({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  /// 角色 → 徽标（字色, 底色 = 原色 5% 透明度），按设计稿：
  /// 业主代表=红、全过程咨询/PMO=绿、设计管理/施工监理=蓝。
  (Color, Color) _roleBadge() {
    final r = user.role;
    if (r.contains('业主')) {
      return (AppTokens.danger, AppTokens.dangerTint);
    }
    if (r.contains('咨询') || r.contains('PMO')) {
      return (AppTokens.success, AppTokens.successTint);
    }
    return (AppTokens.brand, AppTokens.brandTint); // 设计 / 监理 / 默认
  }

  @override
  Widget build(BuildContext context) {
    final (badgeFg, badgeBg) = _roleBadge();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTokens.brand : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 头像 48×48
            ClipOval(
              child: Image.asset(
                user.avatar,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 48,
                  height: 48,
                  color: AppTokens.surface2,
                  alignment: Alignment.center,
                  child: Text(
                    user.name.characters.first,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.fg),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 文本列（姓名 + 角色徽标 / 单位）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 第一行：姓名（左，弹性）+ 角色徽标（右）
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.fg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          user.role.replaceAll(' ', ''),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: badgeFg,
                            height: 20 / 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // 第二行：单位
                  Text(
                    user.org,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTokens.fg2,
                      height: 22 / 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
