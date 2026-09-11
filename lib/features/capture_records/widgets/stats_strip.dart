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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: '累计记录',
              value: total,
              icon: Icons.widgets_outlined,
            ),
          ),
          const _Divider(),
          Expanded(
            child: _Stat(
              label: '今日新增',
              value: today,
              icon: Icons.today_outlined,
            ),
          ),
          const _Divider(),
          Expanded(
            child: _Stat(
              label: '待整改',
              value: pending,
              accent: true,
              icon: Icons.error_outline,
            ),
          ),
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
        height: 36,
        color: AppTokens.border,
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final bool accent;
  final IconData icon;
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    this.accent = false,
  });
  @override
  Widget build(BuildContext context) {
    final color = accent ? AppTokens.danger : AppTokens.fg;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: accent ? AppTokens.danger : AppTokens.fg2),
        const SizedBox(height: 4),
        Text('$value',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 20 / 12,
              color: AppTokens.muted,
            )),
      ],
    );
  }
}
