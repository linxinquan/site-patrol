import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/identity_tile.dart';
import 'auth_controller.dart';

/// 引导第 1 页：选择身份。
/// 按设计稿 Frame 2131330645 / 2131330657 / 2131330655 还原：
/// 标题 24/W400、4 张身份卡（头像 48、姓名 16/W600、单位 14/#666、
/// 角色胶囊徽标按角色着色）、选中卡蓝边框 #428BF7、底部蓝底「下一步」圆角 8 高 48。
/// 选完点「下一步」进入 /onboard/project 选项目。
class OnboardPage extends ConsumerStatefulWidget {
  const OnboardPage({super.key});

  @override
  ConsumerState<OnboardPage> createState() => _OnboardPageState();
}

class _OnboardPageState extends ConsumerState<OnboardPage> {
  late String? _userId;

  @override
  void initState() {
    super.initState();
    final users = ref.read(usersProvider);
    final current = ref.read(currentUserIdProvider);
    // 默认选中：当前登录用户 → 设计管理角色（对应设计稿第 3 张选中态）→ 首位。
    if (current != null && users.any((u) => u.id == current)) {
      _userId = current;
    } else {
      String? design;
      for (final u in users) {
        if (u.role.contains('设计')) {
          design = u.id;
          break;
        }
      }
      _userId = design ?? (users.isNotEmpty ? users.first.id : null);
    }
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
      backgroundColor: AppTokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 返回（onboard 是引导第一步，返回即回到登录页）
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: _back,
                  icon: const Icon(MingCuteIcons.leftLine, color: AppTokens.fg),
                ),
              ),
            ),

            // 标题 + 身份卡列表（可滚动，避免小屏溢出）
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 40, 12, 8),
                child: Column(
                  children: [
                    // 标题组（Frame 2131330649，居中，gap 8）
                    const Text(
                      '选择你的身份',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w400,
                        color: AppTokens.fg,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '选择当前账户，可点击头像切换身份',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppTokens.muted),
                    ),
                    const SizedBox(height: 24),

                    // 身份卡列表（Frame 2131330655，gap 12）
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
            ),

            // 下一步（大按钮组件：满宽 / 高 48 / 未选身份时禁用灰底）
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: AppButton(
                size: AppButtonSize.lg,
                width: double.infinity,
                label: '下一步',
                onPressed: _userId == null ? null : _next,
                disabledBgColor: AppTokens.surface3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 身份卡已提取至 shared/widgets/identity_tile.dart（与首页切换用户弹层共用同一组件）。
