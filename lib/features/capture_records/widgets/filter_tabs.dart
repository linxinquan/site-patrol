import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../../core/theme/design_tokens.dart';
import '../capture_records_controller.dart';

/// 时间窗口 Tab + 楼层筛选入口。
///
/// 顶部 3 个胶囊式时间标签 + 1 个「楼层」按钮；选中态绿色品牌底白字，
/// 未选中灰底深字。楼层按钮右侧小箭头 + 当前选中楼层（如有）。
class RecordFilterTabs extends StatelessWidget {
  final RecordTimeRange time;
  final ValueChanged<RecordTimeRange> onTimeChange;
  final String? floor;
  final VoidCallback onOpenFloorSheet;

  const RecordFilterTabs({
    super.key,
    required this.time,
    required this.onTimeChange,
    required this.floor,
    required this.onOpenFloorSheet,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space3),
      child: Row(
        children: [
          _Tab(
            label: '全部',
            selected: time == RecordTimeRange.all,
            onTap: () => onTimeChange(RecordTimeRange.all),
          ),
          const SizedBox(width: 8),
          _Tab(
            label: '今日',
            selected: time == RecordTimeRange.today,
            onTap: () => onTimeChange(RecordTimeRange.today),
          ),
          const SizedBox(width: 8),
          _Tab(
            label: '本周',
            selected: time == RecordTimeRange.week,
            onTap: () => onTimeChange(RecordTimeRange.week),
          ),
          const SizedBox(width: 8),
          _FloorButton(floor: floor, onTap: onOpenFloorSheet),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab(
      {required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTokens.accent : AppTokens.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? AppTokens.accent : AppTokens.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppTokens.onAccent : AppTokens.fg)),
        ),
      ),
    );
  }
}

class _FloorButton extends StatelessWidget {
  final String? floor;
  final VoidCallback onTap;
  const _FloorButton({required this.floor, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final selected = floor != null && floor!.isNotEmpty;
    return Material(
      color: selected ? AppTokens.accent : AppTokens.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? AppTokens.accent : AppTokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(MingCuteIcons.layersLine,
                  size: 12,
                  color: AppTokens.fg2),
              const SizedBox(width: 4),
              Text(
                selected ? (floor ?? '楼层') : '楼层',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppTokens.onAccent : AppTokens.fg,
                    height: 1),
              ),
              const SizedBox(width: 4),
              Icon(
                MingCuteIcons.downSmallLine,
                size: 12,
                color: selected ? AppTokens.onAccent : AppTokens.fg2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}