import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../data/models.dart';
import '../../features/auth/auth_controller.dart';
import 'app_snack.dart';
import 'user_switch_sheet.dart';

/// 个人中心侧边栏：点击顶部菜单图标后从左侧滑出。
/// 这次按设计稿重构为「固定头部 + 中间滚动内容 + 底部固定退出按钮」，
/// 同时让抽屉宽度跟随屏幕变化，最大保持 310。
void openProfileDrawer(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: const Color(0x80000000),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim, _) => const _ProfileDrawer(),
      transitionsBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

class _ProfileDrawer extends ConsumerWidget {
  const _ProfileDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final projects = ref.watch(projectsProvider);

    // 透明 Material + Scaffold 继续保留，避免 Web 下出现可点击文字默认下划线等问题。
    return Material(
      type: MaterialType.transparency,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Builder(
          builder: (ctx) {
            final media = MediaQuery.of(ctx);
            // 设计稿宽度关系是 310 / 390，所以这里直接按屏宽约 79.5% 计算，
            // 让侧边栏随设备宽度同步缩放，而不是固定卡在 310。
            final panelWidth = media.size.width * (310 / 390);

            return Stack(
              children: [
                // 蒙版区域点击直接关闭。
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(ctx, rootNavigator: true).pop(),
                    child: const SizedBox.expand(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: panelWidth,
                    height: double.infinity,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: Color(0xFFF4F6F7)),
                      child: Column(
                        children: [
                          _header(ctx, media),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _userBlock(ctx, user, ref),
                                    const SizedBox(height: 24),
                                    _projectsBlock(
                                      ctx,
                                      ref,
                                      projects,
                                    ),
                                    const SizedBox(height: 24),
                                    _othersBlock(ctx),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              12,
                              12,
                              12,
                              math.max(16, media.viewPadding.bottom + 8),
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: _logoutButton(ctx, ref),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 顶部栏固定 48，高度之外再叠加系统顶部安全区。
  Widget _header(BuildContext context, MediaQueryData media) {
    return Padding(
      padding: EdgeInsets.only(top: media.padding.top),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(
                    MingCuteIcons.closeMediumLine,
                    size: 24,
                    color: Color(0xFF09244B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 个人信息块：头像 + 姓名 + 切换身份按钮，以及下方蓝色身份卡。
  Widget _userBlock(BuildContext context, User user, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _avatar(user.avatar, 32),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 24 / 16,
                  color: Color(0xFF202224),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showUserSwitchSheet(context, ref),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      MingCuteIcons.transfer3Line,
                      size: 16,
                      color: Color(0xFF0395FF),
                    ),
                    SizedBox(width: 4),
                    Text(
                      '切换身份',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 20 / 12,
                        color: Color(0xFF0395FF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0395FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      user.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 24 / 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    constraints: const BoxConstraints(minWidth: 36),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '身份',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 20 / 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                user.org,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 20 / 12,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 项目列表块：标题保持辅助灰，卡片本身允许高亮当前项目。
  Widget _projectsBlock(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Project>> projects,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        projects.maybeWhen(
          data: (ps) => Text(
            '我的项目 · ${ps.length}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 20 / 12,
              color: Color(0xFF919499),
            ),
          ),
          orElse: () => const Text(
            '我的项目',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 20 / 12,
              color: Color(0xFF919499),
            ),
          ),
        ),
        const SizedBox(height: 8),
        projects.maybeWhen(
          data: (ps) => Column(
            children: [
              for (int i = 0; i < ps.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _projectCard(
                  context,
                  ref,
                  ps[i],
                ),
              ],
            ],
          ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// 单个项目卡：统一保持白底，不再给当前项目额外选中态。
  Widget _projectCard(
    BuildContext context,
    WidgetRef ref,
    Project project,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        ref.read(currentProjectIdProvider.notifier).state = project.id;
        ref.read(userPrefsProvider).saveProjectId(project.id);
        Navigator.of(context, rootNavigator: true).pop();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 24 / 16,
                color: Color(0xFF202224),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              project.location,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 20 / 12,
                color: Color(0xFF919499),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 其他入口块：统一放到一张白卡里，内部行距按设计稿为 24。
  Widget _othersBlock(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '其他',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 20 / 12,
            color: Color(0xFF919499),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _reservedItem(context, MingCuteIcons.userAdd2Line, '添加更多账号'),
              const SizedBox(height: 24),
              _reservedItem(context, MingCuteIcons.questionLine, '帮助'),
              const SizedBox(height: 24),
              _reservedItem(context, MingCuteIcons.settings3Line, '设置'),
            ],
          ),
        ),
      ],
    );
  }

  /// 预留入口行：左侧图标文案，右侧箭头，点击先给提示。
  Widget _reservedItem(BuildContext context, IconData icon, String label) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => AppSnack.show(
        context,
        '$label · 敬请期待',
        kind: AppSnackKind.muted,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF60656B)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 22 / 14,
                  color: Color(0xFF60656B),
                ),
              ),
            ],
          ),
          const Icon(
            MingCuteIcons.rightLine,
            size: 16,
            color: Color(0xFFB5B9BF),
          ),
        ],
      ),
    );
  }

  /// 退出登录按钮固定在底部，并把底部安全区一起算进去。
  Widget _logoutButton(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _logout(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x0DFF4444),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(MingCuteIcons.exitLine, size: 20, color: Color(0xFFFF4444)),
            SizedBox(width: 4),
            Text(
              '退出登录',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 24 / 16,
                color: Color(0xFFFF4444),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 退出登录：清理本地会话并跳回登录页。
  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(sessionStoreProvider).clear();
    ref.read(authStateProvider.notifier).state = null;
    ref.read(onboardedProvider.notifier).state = false;
    if (context.mounted) GoRouter.of(context).go('/login');
  }

  /// 通用头像：支持资源图和回退占位。
  Widget _avatar(String avatar, double size) {
    if (avatar.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFFD9D9D9),
          shape: BoxShape.circle,
        ),
      );
    }
    return ClipOval(
      child: Image.asset(
        avatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: const Color(0xFFD9D9D9),
        ),
      ),
    );
  }
}
