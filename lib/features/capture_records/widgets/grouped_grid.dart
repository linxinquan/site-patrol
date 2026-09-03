import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/theme/design_tokens.dart';
import '../capture_records_controller.dart';
import 'thumbnail_card.dart';

/// 按时间分组（今日 / 昨日 / 更早）的瀑布网格，分组头可折叠。
///
/// 折叠状态受外部 [collapsedGroups] 控制（首次进入全部展开；用户可收起）。
class GroupedRecordGrid extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final Set<String> collapsedGroups;
  final ValueChanged<String> onToggleGroup;
  final void Function(Map<String, dynamic> entry) onTapEntry;

  const GroupedRecordGrid({
    super.key,
    required this.records,
    required this.collapsedGroups,
    required this.onToggleGroup,
    required this.onTapEntry,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _groupByTime(records);
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }
    final children = <Widget>[];
    for (final g in groups) {
      final collapsed = collapsedGroups.contains(g.key);
      children.add(_GroupHeader(
        label: g.label,
        count: g.items.length,
        collapsed: collapsed,
        onTap: () => onToggleGroup(g.key),
      ));
      if (!collapsed) {
        children.add(_GroupGrid(
          items: g.items,
          onTapEntry: onTapEntry,
        ));
        children.add(const SizedBox(height: 16));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  static List<_Group> _groupByTime(List<Map<String, dynamic>> records) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final today = <Map<String, dynamic>>[];
    final yesterday = <Map<String, dynamic>>[];
    final older = <Map<String, dynamic>>[];

    for (final e in records) {
      final ts = _ts(e);
      if (ts == 0) {
        older.add(e);
        continue;
      }
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      if (!dt.isBefore(todayStart)) {
        today.add(e);
      } else if (!dt.isBefore(yesterdayStart)) {
        yesterday.add(e);
      } else {
        older.add(e);
      }
    }

    return [
      _Group('today', '今日', today),
      _Group('yesterday', '昨日', yesterday),
      _Group('older', '更早', older),
    ].where((g) => g.items.isNotEmpty).toList();
  }

  static int _ts(Map<String, dynamic> e) => recordTsMillis(e);
}

class _Group {
  final String key;
  final String label;
  final List<Map<String, dynamic>> items;
  const _Group(this.key, this.label, this.items);
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onTap;
  const _GroupHeader(
      {required this.label,
      required this.count,
      required this.collapsed,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.space3, 12, AppTokens.space3, 8),
        child: Row(
          children: [
            Text('$label（$count）',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.fg2)),
            const Spacer(),
            Icon(
              collapsed ? LucideIcons.chevronDown : LucideIcons.chevronUp,
              size: 14,
              color: AppTokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> entry) onTapEntry;
  const _GroupGrid({required this.items, required this.onTapEntry});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space3),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.78,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => CaptureThumbnailCard(
          entry: items[i],
          onTap: () => onTapEntry(items[i]),
        ),
      ),
    );
  }
}