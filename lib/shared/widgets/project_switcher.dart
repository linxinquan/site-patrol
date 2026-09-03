import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';
import '../../shared/widgets/project_tile.dart';
import 'async_state.dart';

/// 项目切换器（iOS 风格）：
/// 展示当前项目名（16/W600/#202224 + 24×24 下箭头），点击弹出底部项目列表。
class ProjectSwitcher extends ConsumerWidget {
  const ProjectSwitcher({super.key});

  Future<void> _showPicker(BuildContext context, WidgetRef ref) async {
    final projects = ref.read(projectsProvider).maybeWhen(
          data: (ps) => ps,
          orElse: () => <Project>[],
        );
    if (projects.isEmpty) return;
    final current = ref.read(projectProvider).maybeWhen(
          data: (p) => p,
          orElse: () => projects.first,
        );

    final selected = await showModalBottomSheet<Project>(
      context: context,
      useRootNavigator: true, // 推到根导航，遮罩才能覆盖 ShellRoute 的底部 Tab 栏
      backgroundColor: const Color(0xFFF4F6F7),
      barrierColor: const Color(0x80000000), // 遮罩 #000 50%
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _ProjectPickerSheet(
        projects: projects,
        currentId: current.id,
      ),
    );

    if (selected != null && selected.id != current.id) {
      ref.read(currentProjectIdProvider.notifier).state = selected.id;
      ref.read(userPrefsProvider).saveProjectId(selected.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider);
    return AsyncState(
      value: project,
      builder: (p) => InkWell(
        onTap: () => _showPicker(context, ref),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.fg,
                  height: 24 / 16,
                ),
              ),
            ),
            const Icon(MingCuteIcons.downSmallFill,
                size: 24, color: AppTokens.fg),
          ],
        ),
      ),
    );
  }
}

/// 底部项目列表弹窗，按设计稿「切换项目」帧（Frame 2147228008）还原：
/// 遮罩 #000 50%；sheet 背景 #F4F6F7、顶部圆角 24；头部标题「切换项目」居中 + 关闭按钮；
/// 列表为 2 张项目卡（ProjectTile，无选中边框，贴合本稿）。
class _ProjectPickerSheet extends StatelessWidget {
  final List<Project> projects;
  final String currentId;
  const _ProjectPickerSheet({required this.projects, required this.currentId});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // —— 头部：标题居中 + 关闭按钮（右上）——
              // 注意：外层 padding.top 为 0（稿 Frame 2147228008 = 0 12 24），
              // 头部高 48 自带 12 上下内边距，故此处不再额外加顶部间距。
              SizedBox(
                width: double.infinity,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      '切换项目',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 24 / 16,
                        color: Color(0xFF202224),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(context),
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: Icon(MingCuteIcons.closeMediumLine,
                              size: 24, color: Color(0xFF09244B)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // —— 项目卡列表（gap 12）——
              for (int i = 0; i < projects.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                ProjectTile(
                  project: projects[i],
                  selected: projects[i].id == currentId,
                  showBorder: false, // 切换项目稿：卡片无选中边框
                  onTap: () => Navigator.pop(context, projects[i]),
                ),
              ],
            ],
          ),
        ),
      );
}
