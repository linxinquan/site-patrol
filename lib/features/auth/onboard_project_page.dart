import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/project_tile.dart';
import 'auth_controller.dart';

/// 引导第 2 页：选择项目。
/// 按设计稿 Frame 2131330658 / 2131330655 还原：
/// 标题 24/W400、项目卡（48 建筑图标圆头像 + 名称 16/W600 + 地址 14/#666）、
/// 选中卡蓝边框 #428BF7、底部蓝底「开始使用」圆角 8 高 48。
/// 选完点「开始使用」→ 完成引导 → 首页。
class OnboardProjectPage extends ConsumerStatefulWidget {
  const OnboardProjectPage({super.key});

  @override
  ConsumerState<OnboardProjectPage> createState() =>
      _OnboardProjectPageState();
}

class _OnboardProjectPageState extends ConsumerState<OnboardProjectPage> {
  late String? _projectId;

  @override
  void initState() {
    super.initState();
    final projects = ref.read(projectsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const <Project>[],
        );
    // 默认选中：当前项目 → 第 2 个（对应设计稿选中态：南方科技大学附属医院）→ 首位。
    final current = ref.read(currentProjectIdProvider);
    if (current != null && projects.any((p) => p.id == current)) {
      _projectId = current;
    } else if (projects.length > 1) {
      _projectId = projects[1].id;
    } else {
      _projectId = projects.isNotEmpty ? projects.first.id : null;
    }
  }

  void _confirm() {
    if (_projectId == null) return;
    ref.read(currentProjectIdProvider.notifier).state = _projectId;
    ref.read(onboardedProvider.notifier).state = true;
    ref.read(userPrefsProvider).saveProjectId(_projectId);
    ref.read(userPrefsProvider).saveOnboarded(true);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const <Project>[],
        );
    return Scaffold(
      backgroundColor: AppTokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 返回（onboard/project 由 /onboard 推进，返回上一级）
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(MingCuteIcons.leftLine, color: AppTokens.fg),
                ),
              ),
            ),

            // 标题 + 项目卡列表（可滚动，避免小屏溢出）
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 40, 12, 8),
                child: Column(
                  children: [
                    // 标题组（Frame 2131330649，居中，gap 8）
                    const Text(
                      '选择你的项目',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w400,
                        color: AppTokens.fg,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '选择要落地的项目，可在首页切换项目',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppTokens.muted),
                    ),
                    const SizedBox(height: 24),

                    // 项目卡列表（Frame 2131330655，gap 12）
                    for (int i = 0; i < projects.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      ProjectTile(
                        project: projects[i],
                        selected: projects[i].id == _projectId,
                        onTap: () => setState(() => _projectId = projects[i].id),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 开始使用（大按钮组件：满宽 / 高 48 / 未选项目时禁用灰底）
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: AppButton(
                size: AppButtonSize.lg,
                width: double.infinity,
                label: '开始使用',
                onPressed: _projectId == null ? null : _confirm,
                disabledBgColor: AppTokens.surface3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 项目卡已提取至 shared/widgets/project_tile.dart（与首页切换项目弹层共用同一组件）。
