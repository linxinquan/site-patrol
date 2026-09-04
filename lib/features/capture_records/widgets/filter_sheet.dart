import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../../core/theme/design_tokens.dart';

/// 楼层 + AI 仅 筛选弹层。
///
/// 弹层展示当前项目记录中出现的楼层去重列表 + 「仅看 AI 缺陷」开关；
/// 顶部带「重置」按钮。父级通过 `onApply(floor, aiOnly)` 接收结果。
class FilterSheet extends StatefulWidget {
  final List<String> availableFloors;
  final String? currentFloor;
  final bool currentAiOnly;
  final void Function({required String? floor, required bool aiOnly}) onApply;

  const FilterSheet({
    super.key,
    required this.availableFloors,
    required this.currentFloor,
    required this.currentAiOnly,
    required this.onApply,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late String? _floor = widget.currentFloor;
  late bool _aiOnly = widget.currentAiOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题「筛选」由 AppBottomSheet 头部提供；重置按钮移入内容区顶部
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              setState(() {
                _floor = null;
                _aiOnly = false;
              });
            },
            child: const Text('重置',
                style: TextStyle(fontSize: 12, color: AppTokens.muted)),
          ),
        ),
        const SizedBox(height: 4),
        const Text('楼层',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.fg)),
            const SizedBox(height: 8),
            if (widget.availableFloors.isEmpty)
              const Text('当前项目暂无楼层数据',
                  style: TextStyle(fontSize: 12, color: AppTokens.muted))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in widget.availableFloors)
                    _Chip(
                      label: f,
                      selected: _floor == f,
                      onTap: () => setState(() {
                        _floor = _floor == f ? null : f;
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            _SwitchRow(
              label: '仅看识别到缺陷的记录',
              value: _aiOnly,
              onChanged: (v) => setState(() => _aiOnly = v),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.accent,
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                        AppTokens.radiusButton),
                  ),
                ),
                onPressed: () {
                  widget.onApply(floor: _floor, aiOnly: _aiOnly);
                  Navigator.of(context).pop();
                },
                child: const Text('应用',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.onAccent)),
              ),
            ),
          ],
        );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTokens.accent : AppTokens.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
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

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow(
      {required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTokens.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(MingCuteIcons.sparklesLine, size: 16, color: AppTokens.fg2),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: AppTokens.fg, height: 1))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTokens.accent,
          ),
        ],
      ),
    );
  }
}