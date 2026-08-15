import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';
import 'async_state.dart';

/// iOS 风格项目切换器：
/// 展示当前项目名（胶囊高亮），点击弹出底部 ActionSheet 项目列表。
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTokens.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            border: Border.all(color: AppTokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.building2, size: 15, color: AppTokens.accent),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.fg,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(LucideIcons.chevronDown, size: 14, color: AppTokens.muted),
            ],
          ),
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
                      fontSize: 17, fontWeight: FontWeight.w700, color: AppTokens.fg),
                ),
              ),
              const SizedBox(height: AppTokens.space4),
              for (final p in projects)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.space3),
                  child: _ProjectRow(
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

/// 单个项目行（iOS 风格：图标 + 名称 + 状态 + 选中勾）。
class _ProjectRow extends StatelessWidget {
  final Project project;
  final bool selected;
  final VoidCallback onTap;
  const _ProjectRow({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  Color get _tint => selected ? AppTokens.accent : AppTokens.brand;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppTokens.space4),
          decoration: BoxDecoration(
            color: selected ? AppTokens.accentSoft : AppTokens.surface2,
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            border: Border.all(
              color: selected ? AppTokens.accent : AppTokens.border,
              width: selected ? 1.2 : 0.5,
            ),
          ),
          child: Row(
            children: [
              // 项目图标
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected ? AppTokens.accent : _tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(
                  LucideIcons.building2,
                  color: selected ? AppTokens.onAccent : _tint,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppTokens.accent : AppTokens.fg,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${project.client} · ${project.floorArea}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppTokens.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.space3),
              if (selected)
                const Icon(LucideIcons.checkCircle,
                    color: AppTokens.accent, size: 22)
              else
                const Icon(LucideIcons.chevronRight,
                    color: AppTokens.muted, size: 18),
            ],
          ),
        ),
      );
}
