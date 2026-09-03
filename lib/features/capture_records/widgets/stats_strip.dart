import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';

/// 验收记录页顶部状态条：累计 / 今日 / 待整改 三组数值。
///
/// 纯展示组件，数值与标签由父级传入；块间用细分割线划分。
class StatsStrip extends StatelessWidget {
  final int total;
  final int today;
  final int pending;

  const StatsStrip({
    super.key,
    required this.total,
    required this.today,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.space3),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.border),
      ),
      child: Row(
        children: [
          Expanded(child: _Stat(label: '累计', value: total)),
          const _Divider(),
          Expanded(child: _Stat(label: '今日', value: today)),
          const _Divider(),
          Expanded(child: _Stat(label: '待整改', value: pending, accent: true)),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 28,
        color: AppTokens.border,
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final bool accent;
  const _Stat({required this.label, required this.value, this.accent = false});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: accent ? AppTokens.danger : AppTokens.fg)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppTokens.muted)),
      ],
    );
  }
}