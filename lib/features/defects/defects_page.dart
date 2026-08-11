import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../data/models.dart';

class DefectsPage extends ConsumerWidget {
  const DefectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(defectFilterProvider);
    final defects = ref.watch(defectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: defects.maybeWhen(
          data: (ds) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('缺陷工单',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.fg)),
              Text('F9 · 闭环管理（共 ${ds.length} 条）',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppTokens.muted,
                      fontWeight: FontWeight.normal)),
            ],
          ),
          orElse: () => const Text('缺陷工单'),
        ),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(defectFilterProvider.notifier).state = null,
            icon: const Icon(LucideIcons.filter),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterChips(current: filter),
          Expanded(
            child: AsyncState(
              value: defects,
              builder: (ds) {
                final list = filter == null
                    ? ds
                    : ds.where((d) => d.status == filter).toList();
                if (list.isEmpty) {
                  return const Column(
                    children: [
                      Expanded(
                        child: Center(
                            child: Text('该状态下暂无缺陷',
                                style: TextStyle(color: AppTokens.muted))),
                      ),
                      OfflineBar.defects,
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(AppTokens.space4),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppTokens.space3),
                  itemBuilder: (_, i) {
                    if (i == list.length) return OfflineBar.defects;
                    return _DefectCard(list[i]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  final DefectStatus? current;
  const _FilterChips({required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const options = [
      null,
      DefectStatus.draft,
      DefectStatus.doing,
      DefectStatus.done,
      DefectStatus.reject,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: options.map(
          (s) {
            final selected = s == current;
            final label = s == null ? '全部' : s.label;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: selected,
                selectedColor: AppTokens.accent,
                labelStyle: TextStyle(
                    color: selected ? AppTokens.onAccent : AppTokens.fg),
                onSelected: (_) =>
                    ref.read(defectFilterProvider.notifier).state = s,
              ),
            );
          },
        ).toList(),
      ),
    );
  }
}

class _DefectCard extends StatelessWidget {
  final Defect d;
  const _DefectCard(this.d);

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: () => context.push('/defects/record/${d.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusBadge(
                    text: d.status.label,
                    color: d.status.color,
                    bg: d.status.soft),
                const SizedBox(width: 8),
                StatusBadge(
                    text: d.severity.label,
                    color: d.severity.color,
                    bg: d.severity.color.withValues(alpha: 0.12)),
                const Spacer(),
                Text(d.type,
                    style:
                        const TextStyle(fontSize: 12, color: AppTokens.muted)),
              ],
            ),
            const SizedBox(height: 10),
            Text(d.part,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.fg)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(LucideIcons.mapPin,
                    size: 13, color: AppTokens.muted),
                const SizedBox(width: 4),
                Text(d.floor,
                    style:
                        const TextStyle(fontSize: 12, color: AppTokens.muted)),
                const SizedBox(width: 12),
                const Icon(LucideIcons.clock, size: 13, color: AppTokens.muted),
                const SizedBox(width: 4),
                Text(d.ts,
                    style:
                        const TextStyle(fontSize: 12, color: AppTokens.muted)),
              ],
            ),
            const SizedBox(height: 6),
            Text('${d.resp} · ${d.note}',
                style:
                    const TextStyle(fontSize: 12, color: AppTokens.mutedA11y)),
          ],
        ),
      );
}
