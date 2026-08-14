import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';
import 'async_state.dart';

/// 多项目切换器：展示当前项目名，点击弹出项目列表切换。
/// 切换后写入 currentProjectIdProvider，全局项目数据随之更新。
class ProjectSwitcher extends ConsumerWidget {
  const ProjectSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final project = ref.watch(projectProvider);

    return AsyncState(
      value: project,
      builder: (p) => PopupMenuButton<String>(
        offset: const Offset(0, 48),
        onSelected: (id) {
          if (id != p.id) {
            ref.read(currentProjectIdProvider.notifier).state = id;
          }
        },
        itemBuilder: (context) {
          final list = projects.maybeWhen(
            data: (ps) => ps,
            orElse: () => <Project>[p],
          );
          return [
            for (final item in list)
              PopupMenuItem<String>(
                value: item.id,
                child: Row(
                  children: [
                    Icon(
                      item.id == p.id
                          ? LucideIcons.checkCircle
                          : LucideIcons.building2,
                      size: 16,
                      color: item.id == p.id
                          ? AppTokens.accent
                          : AppTokens.muted,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: item.id == p.id
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: item.id == p.id
                              ? AppTokens.accent
                              : AppTokens.fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ];
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.fg,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(LucideIcons.chevronDown,
                size: 16, color: AppTokens.muted),
          ],
        ),
      ),
    );
  }
}
