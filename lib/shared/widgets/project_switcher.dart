import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import 'app_bottom_sheet.dart';
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

    final selected = await AppBottomSheet.show<Project>(
      context: context,
      title: '切换项目',
      body: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < projects.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            ProjectTile(
              project: projects[i],
              selected: projects[i].id == current.id,
              showBorder: false, // 切换项目稿：卡片无选中边框
              onTap: () => Navigator.pop(ctx, projects[i]),
            ),
          ],
        ],
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
