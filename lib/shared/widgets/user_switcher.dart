import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';
import '../../features/auth/auth_controller.dart';
import '../../shared/widgets/identity_tile.dart';

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
      child: CircleAvatar(
        backgroundImage: AssetImage(user.avatar),
        radius: size / 2,
      ),
    );
  }

  void _showUserSheet(
      BuildContext context, WidgetRef ref, List<User> users, User current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
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
                    fontWeight: FontWeight.w600,
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
                      child: IdentityTile(
                        user: u,
                        selected: u.id == current.id,
                        onTap: () {
                          if (u.id != current.id) {
                            ref
                                .read(currentUserIdProvider.notifier)
                                .state = u.id;
                            ref.read(userPrefsProvider).saveUserId(u.id);
                          }
                          Navigator.pop(sheetCtx);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.space2),
            const Divider(height: 1, thickness: 0.5, color: AppTokens.border),
            const SizedBox(height: AppTokens.space2),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                onTap: () async {
                  // 退出登录：清空会话与本地偏好，重置内存态，回到登录页
                  final router = GoRouter.of(context);
                  await ref.read(sessionStoreProvider).clear();
                  await ref.read(userPrefsProvider).clear();
                  ref.read(authStateProvider.notifier).state = null;
                  ref.read(onboardedProvider.notifier).state = false;
                  ref.read(currentUserIdProvider.notifier).state = null;
                  ref.read(currentProjectIdProvider.notifier).state = null;
                  Navigator.pop(sheetCtx);
                  // authState 置空会触发路由守卫重定向到 /login，显式跳转保底
                  router.go('/login');
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppTokens.space3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(MingCuteIcons.exitDoorLine,
                          size: 18, color: AppTokens.danger),
                      SizedBox(width: 8),
                      Text('退出登录',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.danger)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.space3),
          ],
        ),
      ),
    );
  }
}
