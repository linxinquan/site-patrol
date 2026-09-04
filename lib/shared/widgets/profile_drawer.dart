import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:go_router/go_router.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';
import '../../features/auth/auth_controller.dart';
import 'user_switch_sheet.dart';
import 'app_snack.dart';

/// 个人中心侧边栏：点击顶部菜单图标从左侧滑出（宽 310，背景 #F4F6F7），右侧遮罩 #000 50%。
/// 内容：个人信息 + 切换身份按钮、我的项目、其他（设置/帮助等预留）、退出登录。
/// 设计稿「信息侧边栏」帧（Rectangle 1000003188 / 1000003187）。
void openProfileDrawer(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: const Color(0x80000000), // 遮罩 #000 50%
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim, _) => const _ProfileDrawer(),
      transitionsBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(anim),
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

    // 自定义路由推出的页面根没有 Material/Scaffold 上下文；在 Flutter Web 的 HTML
    // 渲染器下，缺失 Material 祖先时，可点击文字（GestureDetector 包裹的 Text）会被
    // HTML 渲染器当成原生 <a> 链接，从而带上浏览器默认下划线。这里用透明的 Material +
    // Scaffold 提供正确的语义上下文，下划线即消失；Scaffold 也让 snackbar 可正常弹出。
    return Material(
      type: MaterialType.transparency,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Builder(
          builder: (ctx) {
            return Stack(
              children: [
                // 蒙版点击关闭（整屏透明，命中即关闭侧边栏）
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(ctx, rootNavigator: true).pop(),
                    child: const SizedBox.expand(),
                  ),
                ),
                // 左侧侧边栏内容
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 310,
                    height: double.infinity,
                    color: const Color(0xFFF4F6F7),
                    child: Stack(
                      children: [
                        // —— 关闭按钮（右上，状态栏下）——
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: SafeArea(
                            top: true,
                            child: SizedBox(
                              height: 44,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        Navigator.of(ctx, rootNavigator: true).pop(),
                                    child: const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Icon(MingCuteIcons.closeMediumLine,
                                          size: 24, color: Color(0xFF09244B)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // —— 内容区（top 103 起，可滚动）——
                        Positioned(
                          top: 103,
                          left: 12,
                          right: 12,
                          bottom: 96,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ===== 个人信息块（gap 24 外层，本块内 gap 12）=====
                                _userBlock(ctx, user, ref),
                                const SizedBox(height: 24),

                                // ===== 我的项目 =====
                                _projectsBlock(ctx, ref, projects),
                                const SizedBox(height: 24),

                                // ===== 其他（设置/帮助等预留）=====
                                _othersBlock(ctx),
                              ],
                            ),
                          ),
                        ),
                        // —— 退出登录（底部固定）——
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 40,
                          height: 48,
                          child: _logoutButton(ctx, ref),
                        ),
                      ],
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

  // —— 个人信息块：头像 + 姓名 + 切换身份 / 角色 + 单位 ——
  Widget _userBlock(BuildContext context, User user, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 行1：头像 + 姓名 + 切换身份按钮
        SizedBox(
          height: 32,
          child: Row(
            children: [
              _avatar(user.avatar, 32),
              const SizedBox(width: 8),
              Text(
                user.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 24 / 16,
                  color: Color(0xFF202224),
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showUserSwitchSheet(context, ref),
                child: Container(
                  width: 72,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0395FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      '切换身份',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 20 / 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 行2：角色 + 身份徽标 / 单位（白卡）
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    user.role,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 22 / 14,
                      color: Color(0xFF202224),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 36,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0x0D0395FF), // 品牌蓝 5%
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Text(
                        '身份',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 20 / 12,
                          color: Color(0xFF0395FF),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                user.org,
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
      ],
    );
  }

  // —— 我的项目块 ——
  Widget _projectsBlock(BuildContext ctx, WidgetRef ref,
      AsyncValue<List<Project>> projects) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题「我的项目 · N」
        projects.maybeWhen(
          data: (ps) => Text(
            '我的项目 · ${ps.length}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 20 / 12,
              color: Color(0xFF202224),
            ),
          ),
          orElse: () => const Text(
            '我的项目',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 20 / 12,
              color: Color(0xFF202224),
            ),
          ),
        ),
        const SizedBox(height: 8),
        projects.maybeWhen(
          data: (ps) => Column(
            children: [
              for (int i = 0; i < ps.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _projectCard(ctx, ref, ps[i]),
              ],
            ],
          ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _projectCard(BuildContext ctx, WidgetRef ref, Project p) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // 与切换项目弹窗一致：切换当前项目并关闭侧边栏，首页项目名随即更新。
        ref.read(currentProjectIdProvider.notifier).state = p.id;
        ref.read(userPrefsProvider).saveProjectId(p.id);
        Navigator.of(ctx, rootNavigator: true).pop();
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
              p.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 22 / 14,
                color: Color(0xFF202224),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              p.location,
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

  // —— 其他（设置 / 帮助 / 添加更多账号，预留）——
  Widget _othersBlock(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '其他',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 20 / 12,
            color: Color(0xFF202224),
          ),
        ),
        const SizedBox(height: 4),
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

  Widget _reservedItem(BuildContext context, IconData icon, String label) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // TODO: 设置 / 帮助 / 添加更多账号 功能后续接入，先预留位置。
      onTap: () => AppSnack.show(context, '$label · 敬请期待',
          kind: AppSnackKind.muted),
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
          const Icon(MingCuteIcons.rightLine, size: 16, color: Color(0xFFB5B9BF)),
        ],
      ),
    );
  }

  // —— 退出登录按钮 ——
  Widget _logoutButton(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _logout(context, ref),
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0x0DFF4444), // 红 5%
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(MingCuteIcons.exitLine, size: 20, color: Color(0xFFFF4444)),
            const SizedBox(width: 4),
            const Text(
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

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    // 清本地会话（重启不再自动登录），并复位登录态与引导态，路由守卫会重定向到 /login。
    await ref.read(sessionStoreProvider).clear();
    ref.read(authStateProvider.notifier).state = null;
    ref.read(onboardedProvider.notifier).state = false;
    if (context.mounted) GoRouter.of(context).go('/login');
  }

  // —— 头像（32/48 通用，加载失败回退灰底）——
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
