import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../shared/widgets/user_switcher.dart';
import '../../data/models.dart';

/// 缺陷工单页（对齐 Figma 新 UI：工单列表页）。
/// 结构：标题栏(工单·N / F9·闭环管理 + 头像) → 筛选条(5 等分按钮) → 缺陷卡列表。
class DefectsPage extends ConsumerWidget {
  const DefectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(defectFilterProvider);
    final defects = ref.watch(defectsProvider);

    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        toolbarHeight: 44,
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 12,
        title: defects.maybeWhen(
          data: (ds) {
            // 标题数字 = 未闭环工单数（待整改 + 整改中），已销项/已拒绝为终态不计入。
            final open = ds
                .where((d) =>
                    d.status == DefectStatus.draft ||
                    d.status == DefectStatus.doing)
                .length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('工单 · $open',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.fg)),
                const Text('F9 · 闭环管理',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppTokens.fg2)),
              ],
            );
          },
          orElse: () => const Text('工单'),
        ),
        actions: const [
          // 头像：与首页一致，点击弹出用户列表切换身份
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: UserSwitcher(),
          ),
        ],
      ),
      body: AsyncState(
        value: defects,
        builder: (ds) {
          final list = filter == null
              ? ds
              : ds.where((d) => d.status == filter).toList();
          // 筛选条作为列表首个 item，随内容滚动（不吸顶）；间距统一 8。
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            itemCount: list.length + 2, // 筛选条 + 卡片 + OfflineBar
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              if (i == 0) return _FilterChips(current: filter);
              if (i == list.length + 1) return OfflineBar.defects;
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 72),
                  child: Center(
                    child: Text('该状态下暂无缺陷',
                        style: TextStyle(color: AppTokens.muted)),
                  ),
                );
              }
              return _DefectCard(list[i - 1]);
            },
          );
        },
      ),
    );
  }
}

/// 筛选条（设计稿 Frame 2131330677）：白底圆角 12 容器，内 5 个等分小按钮。
/// 选中 = #F4F6F7 底 + 品牌蓝字；未选中 = 白底 + 注释灰字；均 14/600、圆角 8。
class _FilterChips extends ConsumerWidget {
  final DefectStatus? current;
  const _FilterChips({required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const options = [
      (null, '全部'),
      (DefectStatus.draft, '待整改'),
      (DefectStatus.doing, '整改中'),
      (DefectStatus.done, '已销项'),
      (DefectStatus.reject, '已拒绝'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Row(
        children: [
          for (final (s, label) in options) ...[
            if (s != null) const SizedBox(width: 4),
            Expanded(
              child: _FilterBtn(
                label: label,
                selected: s == current,
                onTap: () => ref.read(defectFilterProvider.notifier).state = s,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTokens.surface2 : AppTokens.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? AppTokens.brand : AppTokens.note,
            ),
          ),
        ),
      );
}

/// 缺陷卡片（设计稿 Frame 2131330687 等）：
/// 标题行(16/600 + 右侧状态标签) → 字段区(缺陷类型/严重程度/缺陷位置/记录人/发现时间/责任人，14) → 备注块(#F4F6F7 圆角 8)。
class _DefectCard extends StatelessWidget {
  final Defect d;
  const _DefectCard(this.d);

  /// 严重程度文本色（规范分区色）：严重 #FF3B30 / 较重 #FF9500 / 一般 #FADC19 / 轻微 #34C759。
  static Color _severityColor(DefectSeverity s) {
    switch (s) {
      case DefectSeverity.red:
        return AppTokens.danger;
      case DefectSeverity.orange:
        return AppTokens.warning;
      case DefectSeverity.yellow:
        return const Color(0xFFFADC19);
      case DefectSeverity.green:
        return AppTokens.success;
    }
  }

  /// 字段行：名称固定 70 宽（辅助灰 #919499）+ 值（次级文字 #60656B / 严重度带色），行高 22。
  Widget _field(String name, String value, {Color? valueColor}) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(name,
              style: const TextStyle(
                  fontSize: 14, color: AppTokens.muted, height: 22 / 14)),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14,
                color: valueColor ?? AppTokens.fg2,
                height: 22 / 14),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: () => context.push('/defects/record/${d.id}'),
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题行：名称 + 右侧状态标签
            Row(
              children: [
                Expanded(
                  child: Text(
                    d.part,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.fg),
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(status: d.status),
              ],
            ),
            const SizedBox(height: 8),
            // 字段区
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field('缺陷类型：', d.type),
                const SizedBox(height: 6),
                _field('严重程度：', d.severity.label,
                    valueColor: _severityColor(d.severity)),
                const SizedBox(height: 6),
                _field('缺陷位置：', d.anchor),
                const SizedBox(height: 6),
                _field('记录人：', d.reporter),
                const SizedBox(height: 6),
                _field('发现时间：', d.ts),
                const SizedBox(height: 6),
                _field('责任人：', d.resp),
              ],
            ),
            const SizedBox(height: 8),
            // 备注块（灰底内嵌）
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Text(
                d.note,
                style: const TextStyle(
                    fontSize: 14, color: AppTokens.fg, height: 22 / 14),
              ),
            ),
          ],
        ),
      );
}

/// 缺陷状态标签（设计稿 Frame 2131330662：实色底白字，圆角 6，12/600）。
///   draft  → 待整改（红 #FF3B30）
///   doing  → 整改中（橙 #FF9500）
///   done   → 已销项（绿 #34C759）
///   reject → 已拒绝（品牌蓝 #0395FF）
class StatusPill extends StatelessWidget {
  final DefectStatus status;
  const StatusPill({super.key, required this.status});

  Color get _bg {
    switch (status) {
      case DefectStatus.draft:
        return AppTokens.danger;
      case DefectStatus.doing:
        return AppTokens.warning;
      case DefectStatus.done:
        return AppTokens.success;
      case DefectStatus.reject:
        return AppTokens.brand;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status.label,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTokens.surface),
        ),
      );
}
