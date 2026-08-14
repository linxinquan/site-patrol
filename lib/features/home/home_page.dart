import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/section_title.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../shared/widgets/project_switcher.dart';
import '../../shared/widgets/user_switcher.dart';
import '../../data/models.dart';
import '../../data/mock/mock_data.dart';

const mockDataFloors = floors;

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider);
    final floors = ref.watch(floorsProvider);
    final defects = ref.watch(defectsProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: AppTokens.space4,
        title: project.maybeWhen(
          data: (p) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProjectSwitcher(),
              const SizedBox(height: 2),
              Text(
                '${p.client} · 建筑 ${p.floorArea} · ${p.beds} 床',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTokens.muted,
                    height: 1.2),
              ),
            ],
          ),
          orElse: () => const Text('工作台'),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: UserSwitcher(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTokens.accent,
        foregroundColor: AppTokens.onAccent,
        onPressed: () => context.push('/capture'),
        child: const Icon(LucideIcons.camera, size: 26),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.space4),
        children: [
          AsyncState(
              value: floors,
              builder: (fs) => AsyncState(
                  value: defects,
                  builder: (ds) => _ProjectOverviewCard(floors: fs, defects: ds))),
          const SizedBox(height: AppTokens.space5),
          const SectionTitle(title: '快捷操作'),
          const SizedBox(height: AppTokens.space3),
          floors.maybeWhen(
            data: (fs) => _QuickActions(floors: fs),
            orElse: () => const _QuickActions(floors: mockDataFloors),
          ),
          const SizedBox(height: AppTokens.space5),
          const SectionTitle(title: '今日待办'),
          const SizedBox(height: AppTokens.space3),
          AsyncState(value: defects, builder: _TodoList.new),
          const SizedBox(height: AppTokens.space4),
          floors.maybeWhen(
            data: (fs) => OfflineBar.home(fs.length),
            orElse: () => OfflineBar.home(mockDataFloors.length),
          ),
        ],
      ),
    );
  }
}

class _ProjectOverviewCard extends ConsumerWidget {
  final List<Floor> floors;
  final List<Defect> defects;
  const _ProjectOverviewCard({required this.floors, required this.defects});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider).maybeWhen(
          data: (p) => p,
          orElse: () => null,
        );
    if (project == null) return const SizedBox.shrink();

    final drawings = floors.length;
    final totalDefects = defects.length;
    final done = defects.where((d) => d.status == DefectStatus.done).length;

    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        boxShadow: AppTokens.elevationRaised,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // 左侧橙色竖条：贯穿整卡高度（自适应右侧内容）
          Container(
            width: 4,
            decoration: const BoxDecoration(
              color: AppTokens.accent,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.space4, AppTokens.space4, AppTokens.space4, AppTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              project.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppTokens.fg,
                                  height: 1.2),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${project.client} · 建筑 ${project.floorArea}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTokens.muted,
                                  height: 1.2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTokens.warningSoft,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusPill),
                        ),
                        child: Text(
                          project.status,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.warning,
                              height: 1.2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.space3),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppTokens.space2,
                    crossAxisSpacing: AppTokens.space2,
                    childAspectRatio: 1.85,
                    children: [
                      _StatTile(
                          icon: LucideIcons.fileText,
                          value: '$drawings',
                          label: '图纸',
                          bg: AppTokens.brandSoft,
                          fg: AppTokens.brand),
                      const _StatTile(
                          icon: LucideIcons.navigation,
                          value: '2.4',
                          label: '巡场 km',
                          bg: AppTokens.accentSoft,
                          fg: AppTokens.accent),
                      _StatTile(
                          icon: LucideIcons.alertTriangle,
                          value: '$totalDefects',
                          label: '缺陷',
                          bg: AppTokens.dangerSoft,
                          fg: AppTokens.danger),
                      _StatTile(
                          icon: LucideIcons.circleCheck,
                          value: '$done',
                          label: '已整改',
                          bg: AppTokens.successSoft,
                          fg: AppTokens.success),
                    ],
                  ),
                  if (project.parties.isNotEmpty) ...[
                    const SizedBox(height: AppTokens.space3),
                    _PartyList(parties: project.parties),
                  ],
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// 项目参与方列表（甲方 / 设计院 / 监理 / 咨询 / PMO）。
class _PartyList extends StatelessWidget {
  final List<Party> parties;
  const _PartyList({required this.parties});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '参与单位',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTokens.muted,
                height: 1.2),
          ),
          const SizedBox(height: AppTokens.space2),
          for (final party in parties)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.space2),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.space3, vertical: AppTokens.space2),
                decoration: BoxDecoration(
                  color: AppTokens.surface2,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTokens.brandSoft,
                        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                      ),
                      child: const Icon(LucideIcons.building2,
                          size: 15, color: AppTokens.brand),
                    ),
                    const SizedBox(width: AppTokens.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            party.role,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTokens.accent,
                                height: 1.3),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            party.org,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTokens.fg,
                                height: 1.3),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${party.title} · ${party.contact}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTokens.muted,
                                height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color bg;
  final Color fg;
  const _StatTile(
      {required this.icon,
      required this.value,
      required this.label,
      required this.bg,
      required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space3, vertical: AppTokens.space3),
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Icon(icon, color: fg, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, height: 1.15, color: AppTokens.muted)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _QuickActions extends StatelessWidget {
  final List<Floor> floors;
  const _QuickActions({required this.floors});

  int get _totalIndex => floors.fold<int>(0, (s, f) => s + f.index);

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppTokens.space3,
        crossAxisSpacing: AppTokens.space3,
        childAspectRatio: 1.4,
        children: [
          _QuickCard(
            icon: LucideIcons.navigation,
            title: '开始巡场',
            metric: '2.4',
            metricUnit: 'km',
            badge: '离线可用',
            badgeKind: _BadgeKind.muted,
            foot: '今日已记录 · 轨迹自动保存',
            onTap: () => context.go('/patrol'),
          ),
          _QuickCard(
            icon: LucideIcons.camera,
            title: '拍照验收',
            metric: '西楼 1F',
            badge: '5 锚点',
            badgeKind: _BadgeKind.accent,
            foot: '点图锚定留证 · 支持自定义加点',
            onTap: () => context.push('/capture'),
          ),
          _QuickCard(
            icon: LucideIcons.fileText,
            title: '打开图纸',
            metric: '矢量',
            badge: '${floors.length} 张',
            badgeKind: _BadgeKind.brand,
            foot: '本地点图 · 无限缩放',
            onTap: () => context.go('/projects'),
          ),
          _QuickCard(
            icon: LucideIcons.layers,
            title: '图层索引',
            metric: '快速定位',
            badge: '$_totalIndex 处',
            badgeKind: _BadgeKind.success,
            foot: '楼层索引对图 · 跳转查看',
            onTap: () => context.go('/projects'),
          ),
        ],
      );
}

enum _BadgeKind { muted, accent, brand, success }

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String metric;
  final String? metricUnit;
  final String badge;
  final _BadgeKind badgeKind;
  final String foot;
  final VoidCallback onTap;
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.metric,
    this.metricUnit,
    required this.badge,
    required this.badgeKind,
    required this.foot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (badgeFg, badgeBg) = switch (badgeKind) {
      _BadgeKind.accent => (AppTokens.accent, AppTokens.accentSoft),
      _BadgeKind.brand => (AppTokens.brand, AppTokens.brandSoft),
      _BadgeKind.success => (AppTokens.success, AppTokens.successSoft),
      _BadgeKind.muted => (AppTokens.mutedA11y, AppTokens.surface2),
    };

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTokens.accentSoft,
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Icon(icon, color: AppTokens.accent, size: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Text(badge,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: badgeFg)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.fg)),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 16, color: AppTokens.accent),
              children: [
                TextSpan(
                    text: metric,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppTokens.accent)),
                if (metricUnit != null)
                  TextSpan(
                      text: ' $metricUnit',
                      style: const TextStyle(
                          fontSize: 11, color: AppTokens.muted)),
              ],
            ),
          ),
          const Spacer(),
          Text(foot,
              style: const TextStyle(fontSize: 11, color: AppTokens.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _TodoList extends StatelessWidget {
  final List<Defect> ds;
  const _TodoList(this.ds);
  @override
  Widget build(BuildContext context) {
    final todos = ds
        .where((d) =>
            d.status == DefectStatus.draft || d.status == DefectStatus.doing)
        .toList();
    if (todos.isEmpty) {
      return const AppCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('暂无待办', style: TextStyle(color: AppTokens.muted)),
          ),
        ),
      );
    }
    return Column(
      children: todos
          .map((d) => Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.space3),
                child: AppCard(
                  onTap: () => context.push('/defects/record/${d.id}'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 左侧：严重程度小圆点
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: d.severity.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppTokens.space3),
                      // 中部：标题 + 类型负责人 + 时间
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppTokens.fg),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${d.type} · ${d.resp}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTokens.muted),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              d.ts,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTokens.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppTokens.space3),
                      // 右侧：状态徽章（虚线圆 + 图标 + 文案）
                      _StatusPill(
                        status: d.status,
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}

/// 状态徽章：左侧圆形虚线图标 + 右侧文字（对齐原型"待整改/待复核/待销项"）。
class _StatusPill extends StatelessWidget {
  final DefectStatus status;
  const _StatusPill({required this.status});

  IconData get _icon {
    switch (status) {
      case DefectStatus.draft:
        return LucideIcons.refreshCcw; // 待整改：循环箭头
      case DefectStatus.doing:
        return LucideIcons.refreshCcw; // 待复核：循环箭头
      case DefectStatus.done:
        return LucideIcons.check; // 已销项
      case DefectStatus.reject:
        return LucideIcons.x; // 已拒绝
    }
  }

  String get _label => status.label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: status.soft,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(16, 16),
              painter: _DashedCirclePainter(color: status.color),
            ),
            const SizedBox(width: 4),
            Icon(_icon, size: 11, color: status.color),
            const SizedBox(width: 6),
            Text(
              _label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: status.color),
            ),
          ],
        ),
      );
}

/// 圆形虚线边框 painter。
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const dash = 3.0;
    const gap = 2.0;
    final r = (size.shortestSide - paint.strokeWidth) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    final path = Path()..addOval(rect);
    final metrics = path.computeMetrics().first;
    double dist = 0.0;
    while (dist < metrics.length) {
      final next = dist + dash;
      canvas.drawPath(
          metrics.extractPath(dist, next.clamp(0, metrics.length)), paint);
      dist = next + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.color != color;
}
