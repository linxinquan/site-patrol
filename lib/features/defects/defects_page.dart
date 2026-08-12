import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_card.dart';
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
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space4, vertical: AppTokens.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧：红色三角警告图标（对齐原型 row__icon）
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTokens.dangerSoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: const Icon(LucideIcons.alertTriangle,
                  size: 16, color: AppTokens.danger),
            ),
            const SizedBox(width: AppTokens.space3),
            // 中部：标题 + 类型/严重度/部位 + 责任人备注
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    d.part,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.fg),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${d.type} · 严重度 ${d.severity.label} · ${d.anchor}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppTokens.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${d.resp} · ${d.note}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppTokens.mutedA11y),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.space3),
            // 右侧：大尺寸状态胶囊（对齐原型 defectBadge）
            StatusPill(status: d.status),
          ],
        ),
      );
}

/// 缺陷状态大胶囊：虚线圆 + 图标 + 文字，按状态着色。
/// 对齐 prototype HTML 的 defectBadge():
///   draft  → 待整改 (warning 黄)
///   doing  → 整改中 (brand 蓝)
///   done   → 已销项 (success 绿)
///   reject → 已拒绝 (danger 红)
class StatusPill extends StatelessWidget {
  final DefectStatus status;
  const StatusPill({super.key, required this.status});

  Color get _color {
    switch (status) {
      case DefectStatus.draft:
        return AppTokens.warning;
      case DefectStatus.doing:
        return AppTokens.brand;
      case DefectStatus.done:
        return AppTokens.success;
      case DefectStatus.reject:
        return AppTokens.danger;
    }
  }

  Color get _soft {
    switch (status) {
      case DefectStatus.draft:
        return AppTokens.warningSoft;
      case DefectStatus.doing:
        return AppTokens.brandSoft;
      case DefectStatus.done:
        return AppTokens.successSoft;
      case DefectStatus.reject:
        return AppTokens.dangerSoft;
    }
  }

  IconData get _icon {
    switch (status) {
      case DefectStatus.draft:
        return LucideIcons.refreshCcw; // 循环（与"待整改"对应）
      case DefectStatus.doing:
        return LucideIcons.refreshCcw; // 循环（与"整改中"对应）
      case DefectStatus.done:
        return LucideIcons.check;
      case DefectStatus.reject:
        return LucideIcons.x;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _soft,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(
              color: _color.withValues(alpha: 0.35), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 虚线圆 + 中心图标
            SizedBox(
              width: 28,
              height: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(28, 28),
                    painter: _DashedRingPainter(color: _color),
                  ),
                  Icon(_icon, size: 14, color: _color),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              status.label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _color),
            ),
          ],
        ),
      );
}

/// 虚线圆环 painter（圆 + 一段段短弧绘制）。
class _DashedRingPainter extends CustomPainter {
  final Color color;
  _DashedRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final r = (size.shortestSide - paint.strokeWidth) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final path = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final metric = path.computeMetrics().first;
    const dash = 4.0;
    const gap = 2.0;
    double dist = 0.0;
    while (dist < metric.length) {
      final next = (dist + dash).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(dist, next), paint);
      dist = next + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color;
}
