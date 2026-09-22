import 'package:flutter/material.dart';

import '../../../core/utils/measure_labels.dart';
import '../../../core/utils/measure_modes.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../data/models.dart';
import '../../../shared/widgets/app_snack.dart';

/// 面积 / 体积弹层（量尺宝式"测量模式"的本地点选版）。
///
/// 从**已测的线性尺寸**里选 2 条边算面积、3 条边算体积：
/// 面积 = 长 × 宽，体积 = 长 × 宽 × 高；误差带按各边相对误差线性相加合成。
///
/// 返回可直接入清单的 [MeasureItem]（`unit` 为 `m2` / `m3`，不参与合格判定）
/// 及其**因子边长**（用于在图上按参考样式画出尺寸胶囊）；用户取消返回 null。
Future<({MeasureItem item, List<MeasureItem> factors})?> showAreaVolumeSheet(
  BuildContext context, {
  required List<MeasureItem> candidates,
  String title = '面积 / 体积',
}) {
  final linear = [
    for (final c in candidates)
      if (c.unit == 'mm' && c.photoMm > 0) c,
  ];
  return showModalBottomSheet<({MeasureItem item, List<MeasureItem> factors})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AreaVolumeSheet(title: title, candidates: linear),
  );
}

class _AreaVolumeSheet extends StatefulWidget {
  const _AreaVolumeSheet({required this.title, required this.candidates});

  final String title;
  final List<MeasureItem> candidates;

  @override
  State<_AreaVolumeSheet> createState() => _AreaVolumeSheetState();
}

class _AreaVolumeSheetState extends State<_AreaVolumeSheet> {
  bool _isVolume = false;
  final Set<int> _picked = {};

  int get _need => requiredFactors(isVolume: _isVolume);

  List<MeasureItem> get _factors =>
      [for (final i in _picked.toList()..sort()) widget.candidates[i]];

  ({double value, double err})? get _result =>
      combine(_factors, isVolume: _isVolume);

  void _switchMode(bool isVolume) {
    setState(() {
      _isVolume = isVolume;
      // 切换模式时清空超出的选择（面积 2 项 / 体积 3 项）
      if (_picked.length > requiredFactors(isVolume: isVolume)) {
        final keep = (_picked.toList()..sort())
            .sublist(0, requiredFactors(isVolume: isVolume));
        _picked
          ..clear()
          ..addAll(keep);
      }
    });
  }

  void _autoPick() {
    final s = suggestFactors(widget.candidates, isVolume: _isVolume);
    // 用读数最大的几条做默认组合（现场通常是"最长的两边/三边"）
    setState(() {
      _picked.clear();
      for (final f in s) {
        final idx = widget.candidates.indexOf(f);
        if (idx >= 0) _picked.add(idx);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final need = _need;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              '选 $need 条已测边长组合：面积 = 长 × 宽，体积 = 长 × 宽 × 高。'
              '误差带按各边相对误差相加合成（保守）。',
              style: const TextStyle(fontSize: 11, color: AppTokens.muted),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('面积 ㎡')),
                ButtonSegment(value: true, label: Text('体积 m³')),
              ],
              selected: {_isVolume},
              onSelectionChanged: (s) => _switchMode(s.first),
            ),
            const SizedBox(height: 8),
            if (widget.candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('暂无已测的线性尺寸：请先量取边长（至少 2 条）',
                    style: TextStyle(fontSize: 13, color: AppTokens.muted)),
              )
            else ...[
              Row(
                children: [
                  TextButton(
                      onPressed: _autoPick,
                      child: Text('选最长 $need 条')),
                  const Spacer(),
                  Text('已选 ${_picked.length}/$need',
                      style: const TextStyle(
                          fontSize: 12, color: AppTokens.muted)),
                ],
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < widget.candidates.length; i++)
                      CheckboxListTile(
                        dense: true,
                        value: _picked.contains(i),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            if (_picked.length >= need) {
                              // 超出所需条数时挤掉最早选的那条（保持刚好 N 条）
                              final first = (_picked.toList()..sort()).first;
                              _picked.remove(first);
                            }
                            _picked.add(i);
                          } else {
                            _picked.remove(i);
                          }
                        }),
                        title: Text(widget.candidates[i].name,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          '实测 ${measureValueText(widget.candidates[i])}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                r == null
                    ? (_picked.length == need
                        ? '组合结果超出合理量级：请检查是否选错了边（如把 mm 与 cm 混用）'
                        : '选够 $need 条边后自动出结果')
                    : '${combineLabel(r, isVolume: _isVolume)}'
                        '（因子 ${factorsText(_factors)}）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: r == null ? AppTokens.muted : AppTokens.fg,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: r == null
                        ? null
                        : () {
                            final item = buildCalcItem(
                              factors: _factors,
                              value: r.value,
                              err: r.err,
                              isVolume: _isVolume,
                            );
                            Navigator.of(context)
                                .pop((item: item, factors: _factors));
                          },
                    child: const Text('加入清单'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 供调用方统一的成功提示（含误差带，避免只报一个孤零零的数）。
void showCalcAddedSnack(BuildContext context, MeasureItem item) {
  AppSnack.show(
    context,
    '已加入清单：${item.name}（误差带 ±${(item.errorMm ?? 0).toStringAsFixed(2)}）',
    kind: AppSnackKind.success,
  );
}
