import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';

/// 用户切换器：点击头像弹出用户列表，选择后切换当前登录用户。
class UserSwitcher extends ConsumerWidget {
  const UserSwitcher({super.key, this.size = 36});

  /// 头像尺寸（直径）。
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final users = ref.watch(usersProvider);

    return GestureDetector(
      onTap: () => _showUserSheet(context, ref, users, user),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundImage: AssetImage(user.avatar),
            radius: size / 2,
          ),
          // 右下角小徽标：当前用户首字（或一个切换图标）
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: AppTokens.accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppTokens.surface, width: 2),
              ),
              child: const Icon(LucideIcons.refreshCcw,
                  size: 9, color: AppTokens.onAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserSheet(
      BuildContext context, WidgetRef ref, List<User> users, User current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text('切换用户',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.fg)),
            const SizedBox(height: 4),
            const Text('以不同角色身份进入系统',
                style: TextStyle(fontSize: 12, color: AppTokens.muted)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.space4, vertical: AppTokens.space2),
                children: [
                  for (final u in users)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.space2),
                      child: Material(
                        color: u.id == current.id
                            ? AppTokens.accentSoft
                            : AppTokens.surface2,
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                          onTap: () {
                            if (u.id != current.id) {
                              ref
                                  .read(currentUserIdProvider.notifier)
                                  .state = u.id;
                            }
                            Navigator.pop(sheetCtx);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(AppTokens.space3),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundImage: AssetImage(u.avatar),
                                  radius: 22,
                                ),
                                const SizedBox(width: AppTokens.space3),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            u.name,
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: AppTokens.fg),
                                          ),
                                          const SizedBox(width: 6),
                                          if (u.id == current.id)
                                            Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTokens.accentSoft,
                                                borderRadius: BorderRadius
                                                    .circular(
                                                        AppTokens.radiusPill),
                                              ),
                                              child: const Text('当前用户',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color:
                                                          AppTokens.accent)),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        u.org,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTokens.muted,
                                            height: 1.3),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        u.role,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTokens.accent,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                if (u.id == current.id)
                                  const Icon(LucideIcons.check,
                                      size: 18, color: AppTokens.accent),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.space3),
          ],
        ),
      ),
    );
  }
}
