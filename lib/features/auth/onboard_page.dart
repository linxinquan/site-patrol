import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

import '../../core/di/providers.dart';
import '../../shared/widgets/identity_tile.dart';
import 'auth_controller.dart';

/// 引导第 1 页：选择身份。
/// 按设计稿「选择你的身份」帧还原（画布 390×844，背景 #F8F8F8）：
/// - 状态栏 47 + 导航栏 44；返回图标 24×24 在 left 12 / top 57（相对安全区 top 10）
/// - 主内容区 left 12 / top 139：标题组（308 宽，24/W600 + 14/W400，gap 8）+ gap 24 + 身份卡列表（gap 12）
/// - 身份卡 366×72 白底圆角 8（见 IdentityTile）
/// - 底部主按钮 240×48 圆角 8 品牌蓝「下一步」，top 613 居中
/// 选完点「下一步」进入 /onboard/project 选项目。
class OnboardPage extends ConsumerStatefulWidget {
  const OnboardPage({super.key});

  // —— 设计稿「选择你的身份」帧专用色 ——
  static const Color bg = Color(0xFFF8F8F8); // 页面背景
  static const Color fg = Color(0xFF202224); // 标题-正文
  static const Color muted = Color(0xFF919499); // 辅助说明
  static const Color brand = Color(0xFF0395FF); // 品牌色
  static const Color backIcon = Color(0xFF222222); // 返回图标

  @override
  ConsumerState<OnboardPage> createState() => _OnboardPageState();
}

class _OnboardPageState extends ConsumerState<OnboardPage> {
  late String? _userId;

  @override
  void initState() {
    super.initState();
    // 不默认选中任何身份，进入后再由用户点选；未选中时「下一步」按钮禁用。
    _userId = null;
  }

  void _next() {
    if (_userId == null) return;
    ref.read(currentUserIdProvider.notifier).state = _userId;
    ref.read(userPrefsProvider).saveUserId(_userId);
    context.push('/onboard/project');
  }

  Future<void> _back() async {
    // onboard 由路由守卫 redirect 进入，路由栈内并无 /login；
    // 若直接 go('/login')，守卫会因 authState 仍有效而再次弹回 /onboard，
    // 形成死循环。故返回前先清登录态与本地偏好，再回登录页。
    await ref.read(sessionStoreProvider).clear();
    await ref.read(userPrefsProvider).clear();
    ref.read(authStateProvider.notifier).state = null;
    ref.read(onboardedProvider.notifier).state = false;
    ref.read(currentUserIdProvider.notifier).state = null;
    ref.read(currentProjectIdProvider.notifier).state = null;
    if (context.mounted) {
      context.canPop() ? context.pop() : context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);
    return Scaffold(
      backgroundColor: OnboardPage.bg,
      body: SafeArea(
        // 可滚动，避免小屏内容溢出
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // —— 返回（left 12 / top 10，图标 24×24）——
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: _back,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 24, height: 24),
                    icon: const Icon(MingCuteIcons.leftLine,
                        size: 24, color: OnboardPage.backIcon),
                  ),
                ),
              ),

              // 返回区底 34 → 主内容 top 92，间距 58
              const SizedBox(height: 58),

              // —— 标题组（Frame 2131330649：308 宽居中，gap 8）——
              Center(
                child: SizedBox(
                  width: 308,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        '选择你的身份',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          height: 32 / 24,
                          color: OnboardPage.fg,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '选择当前巡检账号，可点击「更多」菜单切换身份',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 22 / 14,
                          color: OnboardPage.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // —— 身份卡列表（Frame 2131330655：gap 12，左右留 12）——
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    for (int i = 0; i < users.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      IdentityTile(
                        user: users[i],
                        selected: users[i].id == _userId,
                        onTap: () => setState(() => _userId = users[i].id),
                      ),
                    ],
                  ],
                ),
              ),

              // 主内容底 502 → 按钮 top 566（画布 613），间距 64
              const SizedBox(height: 64),

              // —— 下一步：240×48 圆角 8 品牌蓝，居中 ——
              Center(
                child: _NextButton(
                  onPressed: _userId == null ? null : _next,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// 主按钮：240×48 圆角 8 品牌蓝，「下一步」16/W500/白 行高 24。
/// 未复用 AppButton 是因为本帧按稿为圆角 8 / 字重 500，与全局 token（圆角 12 / W700）不同。
class _NextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _NextButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 240,
        height: 48,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: OnboardPage.brand,
            disabledBackgroundColor: const Color(0xFFE9EAEB),
            foregroundColor: Colors.white,
            disabledForegroundColor: const Color(0xFF919499),
            // 关闭 Material 默认 48 点击区扩张，避免高度被撑开
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 24 / 16,
              letterSpacing: 0,
            ),
          ),
          child: const Text('下一步', textAlign: TextAlign.center),
        ),
      );
}
