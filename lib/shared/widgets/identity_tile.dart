import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';

/// 身份选择卡（共用组件）：选择身份页与首页切换用户底部弹层共用。
/// 按设计稿「选择你的身份」帧（Frame 2131330653 等）：
/// 白底圆角 8、高 72、padding 12、gap 8，头像 48 + 姓名(16/W600)/角色徽标一行 + 单位(14/辅助灰)一行。
/// 角色徽标：字色按角色（红/绿/蓝）、底色=原色 5%、圆角 6、padding 0 6、高 20。
/// 选中边框：默认开启（选择身份页用）；弹窗传 [showBorder]=false 以贴合「切换用户」稿（卡片无边框）。
class IdentityTile extends StatelessWidget {
  final User user;
  final bool selected;
  final VoidCallback onTap;
  final bool showBorder;
  const IdentityTile({
    required this.user,
    required this.selected,
    required this.onTap,
    this.showBorder = true,
  });

  // 设计稿角色色（与全局 token 的 danger/success 有细微差异，按稿取精确值）
  static const Color _roleRed = Color(0xFFFF4444); // 业主代表
  static const Color _roleGreen = Color(0xFF00B84A); // 全过程咨询 / PMO
  static const Color _roleBlue = Color(0xFF0395FF); // 设计管理 / 施工监理

  /// 角色 → 徽标（字色, 底色 = 原色 5% 透明度），按设计稿：
  /// 业主代表=红 #FF4444、全过程咨询/PMO=绿 #00B84A、设计管理/施工监理=蓝 #0395FF。
  (Color, Color) _roleBadge() {
    final r = user.role;
    if (r.contains('业主')) {
      return (_roleRed, _roleRed.withValues(alpha: 0.05));
    }
    if (r.contains('咨询') || r.contains('PMO')) {
      return (_roleGreen, _roleGreen.withValues(alpha: 0.05));
    }
    return (_roleBlue, _roleBlue.withValues(alpha: 0.05)); // 设计 / 监理 / 默认
  }

  @override
  Widget build(BuildContext context) {
    final (badgeFg, badgeBg) = _roleBadge();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (selected && showBorder)
                ? const Color(0xFF0395FF)
                : Colors.transparent,
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
                            height: 24 / 16,
                            color: AppTokens.fg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          user.role.replaceAll(' ', ''),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: badgeFg,
                            height: 20 / 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // 第二行：单位（辅助说明 #919499）
                  Text(
                    user.org,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF919499),
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
