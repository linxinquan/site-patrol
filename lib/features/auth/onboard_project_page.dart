import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import 'auth_controller.dart';

/// 引导第 2 页：选择项目。
/// 选完点「进入工地」→ 完成引导 → 首页。
class OnboardProjectPage extends ConsumerStatefulWidget {
  const OnboardProjectPage({super.key});

  @override
  ConsumerState<OnboardProjectPage> createState() =>
      _OnboardProjectPageState();
}

class _OnboardProjectPageState extends ConsumerState<OnboardProjectPage> {
  String? _projectId;

  void _confirm() {
    if (_projectId == null) return;
    ref.read(currentProjectIdProvider.notifier).state = _projectId;
    ref.read(onboardedProvider.notifier).state = true;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => <Project>[],
        );
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
                  const SizedBox(height: 8),
                  // 返回按钮
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(LucideIcons.chevronLeft,
                          color: AppTokens.muted),
                    ),
                  ),
                  // 顶部标题
                  const Text(
                    '选择当前项目',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.fg,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '选择要巡检的工地',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppTokens.muted),
                  ),
                  const SizedBox(height: 28),

                  // 项目列表
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final p in projects)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppTokens.space3),
                            child: _ProjectTile(
                              project: p,
                              selected: p.id == _projectId,
                              onTap: () =>
                                  setState(() => _projectId = p.id),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // 进入工地按钮
                  FilledButton(
                    onPressed: _projectId == null ? null : _confirm,
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
                      '进入工地',
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

class _ProjectTile extends StatelessWidget {
  final Project project;
  final bool selected;
  final VoidCallback onTap;
  const _ProjectTile({
    required this.project,
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
            horizontal: AppTokens.space4, vertical: 16),
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
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: (selected ? AppTokens.accent : AppTokens.surface2)
                    .withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.building2,
                  size: 22, color: AppTokens.accent),
            ),
            const SizedBox(width: AppTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg)),
                  const SizedBox(height: 3),
                  Text(project.location,
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
