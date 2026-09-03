import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTokens.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Text('筛选',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.fg)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _floor = null;
                      _aiOnly = false;
                    });
                  },
                  child: const Text('重置',
                      style: TextStyle(
                          fontSize: 12, color: AppTokens.muted)),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                  backgroundColor: AppTokens.success,
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
        ),
      ),
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
      color: selected ? AppTokens.success : AppTokens.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? AppTokens.success : AppTokens.border),
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
          const Icon(LucideIcons.sparkles, size: 16, color: AppTokens.fg2),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: AppTokens.fg))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTokens.success,
          ),
        ],
      ),
    );
  }
}