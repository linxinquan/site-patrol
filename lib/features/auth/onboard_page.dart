import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';

/// 引导第 1 页：选择用户。
/// 选完点「下一步」进入 /onboard/project 选项目。
class OnboardPage extends ConsumerStatefulWidget {
  const OnboardPage({super.key});

  @override
  ConsumerState<OnboardPage> createState() => _OnboardPageState();
}

class _OnboardPageState extends ConsumerState<OnboardPage> {
  String? _userId;

  void _next() {
    if (_userId == null) return;
    ref.read(currentUserIdProvider.notifier).state = _userId;
    context.push('/onboard/project');
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  // 顶部标题
                  const Text(
                    '选择你的身份',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.fg,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '选择当前账户',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppTokens.muted),
                  ),
                  const SizedBox(height: 28),

                  // 用户列表
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final u in users)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppTokens.space3),
                            child: _UserTile(
                              user: u,
                              selected: u.id == _userId,
                              onTap: () => setState(() => _userId = u.id),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // 下一步按钮
                  FilledButton(
                    onPressed: _userId == null ? null : _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTokens.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTokens.surface3,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      '下一步',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final User user;
  final bool selected;
  final VoidCallback onTap;
  const _UserTile({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedBg = AppTokens.accent.withValues(alpha: 0.06);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space4, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? selectedBg : AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          border: Border.all(
            color: selected ? AppTokens.accent : AppTokens.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            ClipOval(
              child: Image.asset(user.avatar,
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                        width: 46,
                        height: 46,
                        color: AppTokens.surface2,
                        alignment: Alignment.center,
                        child: Text(
                          user.name.characters.first,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppTokens.accent),
                        ),
                      )),
            ),
            const SizedBox(width: AppTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg)),
                  const SizedBox(height: 3),
                  Text('${user.org} · ${user.role}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTokens.muted,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Icon(
              selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
              size: 22,
              color: selected ? AppTokens.accent : AppTokens.border,
            ),
          ],
        ),
      ),
    );
  }
}
