import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';
import '../../shared/widgets/project_tile.dart';
import 'async_state.dart';

/// 项目切换器（iOS 风格）：
/// 展示当前项目名（16/W700/#222222 + 24×24 下箭头），点击弹出底部 ActionSheet 项目列表。
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
      backgroundColor: AppTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
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

/// 底部 ActionSheet：项目列表（iOS 风格）。
class _ProjectPickerSheet extends StatelessWidget {
  final List<Project> projects;
  final String currentId;
  const _ProjectPickerSheet({required this.projects, required this.currentId});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.space4, AppTokens.space4, AppTokens.space4, AppTokens.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  '切换项目',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: AppTokens.fg),
                ),
              ),
              const SizedBox(height: AppTokens.space4),
              for (final p in projects)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.space3),
                  child: ProjectTile(
                    project: p,
                    selected: p.id == currentId,
                    onTap: () => Navigator.pop(context, p),
                  ),
                ),
            ],
          ),
        ),
      );
}

// 项目卡已提取至 shared/widgets/project_tile.dart（与选择项目页共用同一组件）。
