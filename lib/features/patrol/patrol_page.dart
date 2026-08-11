import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../utils/path_metrics.dart';
import '../../shared/widgets/app_snack.dart';

/// 巡场页：深色沉浸（静态布局还原，轨迹动画 + 实时里程留 P5）。
/// 底图：西楼一层平面图（nkf_west_1f.png）。
class PatrolPage extends StatelessWidget {
  const PatrolPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTokens.patrolBg,
        appBar: AppBar(
          backgroundColor: AppTokens.patrolBg,
          foregroundColor: AppTokens.patrolFg,
          elevation: 0,
          title: const Text('巡场',
              style: TextStyle(
                  color: AppTokens.patrolFg,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ),
        body: Column(
          children: [
            // 顶部：离线提示 + 记录中
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTokens.patrolSurface2,
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.cloudOff,
                            size: 12, color: AppTokens.patrolMuted),
                        SizedBox(width: 5),
                        Text('离线 · 工地信号弱（GPS 仍记录）',
                            style: TextStyle(
                                fontSize: 11, color: AppTokens.patrolMuted)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTokens.dangerSoft,
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BlinkDot(),
                        SizedBox(width: 5),
                        Text('记录中',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTokens.danger,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 统计 chips
            const _StatChips(),
            const SizedBox(height: 10),
            // 地图
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const planW = 1500.0, planH = 944.0;
                  const ar = planW / planH;
                  var pw = constraints.maxWidth;
                  var ph = pw / ar;
                  if (ph > constraints.maxHeight) {
                    ph = constraints.maxHeight;
                    pw = ph * ar;
                  }
                  final pts = patrolPathPoints
                      .map((p) => Offset(p.dx * pw / 100, p.dy * ph / 100))
                      .toList();
                  return Center(
                    child: SizedBox(
                      width: pw,
                      height: ph,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/drawings/nkf_west_1f.png',
                            fit: BoxFit.fill,
                          ),
                          CustomPaint(
                            painter: PatrolOverlayPainter(
                              pts: pts,
                              cpIdxs: patrolCheckpoints,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // 控制面板
            _PatrolPanel(onAction: (msg) {
              AppSnack.show(context, msg, kind: AppSnackKind.muted);
            }),
          ],
        ),
      );
}

class _BlinkDot extends StatefulWidget {
  const _BlinkDot();
  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppTokens.danger,
            shape: BoxShape.circle,
          ),
        ),
      );
}

class _StatChips extends StatelessWidget {
  const _StatChips();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Chip(label: '楼层', value: '西楼 1F'),
            _Chip(label: '里程', value: '0.00 km'),
            _Chip(label: '点数', value: '0'),
            _Chip(label: '时长', value: '00:00'),
            _Chip(label: '模式', value: 'GPS'),
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  const _Chip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.patrolFg)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: AppTokens.patrolMuted)),
        ],
      );
}

class _PatrolPanel extends StatelessWidget {
  final ValueChanged<String> onAction;
  const _PatrolPanel({required this.onAction});

  @override
  Widget build(BuildContext context) => Container(
        color: AppTokens.patrolSurface,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.accent,
                  foregroundColor: AppTokens.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                ),
                onPressed: () => onAction('开始巡场（P5 实现轨迹动画）'),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.play, size: 18),
                    SizedBox(width: 6),
                    Text('开始巡场',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SubBtn(
                    icon: LucideIcons.square,
                    label: '暂停',
                    enabled: false,
                    onTap: () => onAction('巡场未开始'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SubBtn(
                    icon: LucideIcons.history,
                    label: '历史轨迹',
                    onTap: () => onAction('已加载 3 条历史巡场轨迹'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SubBtn(
                    icon: LucideIcons.map,
                    label: '标记问题点',
                    onTap: () => onAction('标记问题点（P3 拍照验收承接）'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _SubBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const _SubBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppTokens.patrolSurface2,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            border: Border.all(
                color: enabled
                    ? AppTokens.patrolBorder
                    : AppTokens.patrolBorder.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: enabled
                      ? AppTokens.patrolFg
                      : AppTokens.patrolMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: enabled
                          ? AppTokens.patrolFg
                          : AppTokens.patrolMuted.withValues(alpha: 0.5))),
            ],
          ),
        ),
      );
}
