import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/section_title.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../shared/widgets/app_snack.dart';
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
        title: project.maybeWhen(
          data: (p) => Text(
            '工作台 · ${p.client} · 建筑 ${p.floorArea} · ${p.beds} 床',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: AppTokens.fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          orElse: () => const Text('工作台'),
        ),
        actions: [
          GestureDetector(
            onTap: () => AppSnack.show(context, '当前账号：杨工（上海同济咨询-设计管理工程师）',
                kind: AppSnackKind.muted),
            child: const Padding(
              padding: EdgeInsets.only(right: 12),
              child: CircleAvatar(
                backgroundImage: AssetImage('assets/avatars/yang-gong.jpg'),
                radius: 16,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTokens.accent,
        foregroundColor: AppTokens.onAccent,
        onPressed: () =>
            AppSnack.show(context, '拍照验收（P3 实现）', kind: AppSnackKind.accent),
        child: const Icon(LucideIcons.camera, size: 26),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.space4),
        children: [
          AsyncState(value: project, builder: _OverviewCard.new),
          const SizedBox(height: AppTokens.space4),
          AsyncState(
              value: floors,
              builder: (fs) => AsyncState(
                  value: defects, builder: (ds) => _StatTiles(fs, ds))),
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

class _OverviewCard extends StatelessWidget {
  final Project p;
  const _OverviewCard(this.p);
  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.fg)),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(LucideIcons.building2,
                  size: 14, color: AppTokens.muted),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(p.client,
                      style: const TextStyle(
                          fontSize: 13, color: AppTokens.muted))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(LucideIcons.mapPin, size: 14, color: AppTokens.muted),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(p.location,
                      style: const TextStyle(
                          fontSize: 13, color: AppTokens.muted))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(LucideIcons.info, size: 14, color: AppTokens.accent),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(p.status,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.accent))),
            ]),
            const SizedBox(height: AppTokens.space4),
            Row(children: [
              Expanded(child: _MiniStat('用地面积', p.siteArea)),
              Expanded(child: _MiniStat('建筑面积', p.floorArea)),
              Expanded(child: _MiniStat('规划床位', '${p.beds}')),
            ]),
          ],
        ),
      );
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.fg)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppTokens.muted)),
        ],
      );
}

/// 4 个统计磁贴：图纸 / 巡场 km / 缺陷 / 已整改（2×2 网格，对齐 HTML 语义）。
class _StatTiles extends StatelessWidget {
  final List<Floor> floors;
  final List<Defect> defects;
  const _StatTiles(this.floors, this.defects);
  @override
  Widget build(BuildContext context) {
    final drawings = floors.length;
    final totalDefects = defects.length;
    final done = defects.where((d) => d.status == DefectStatus.done).length;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppTokens.space3,
      crossAxisSpacing: AppTokens.space3,
      childAspectRatio: 2.4,
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
    );
  }
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
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space4, vertical: AppTokens.space3),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
              child: Icon(icon, color: fg, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg)),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, color: AppTokens.muted)),
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
            onTap: () => AppSnack.show(context, '拍照验收（P3 实现）',
                kind: AppSnackKind.accent),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        StatusBadge(
                            text: d.status.label,
                            color: d.status.color,
                            bg: d.status.soft),
                        const SizedBox(width: 8),
                        StatusBadge(
                            text: d.severity.label,
                            color: d.severity.color,
                            bg: d.severity.color.withValues(alpha: 0.12)),
                        const Spacer(),
                        Text(d.floor,
                            style: const TextStyle(
                                fontSize: 12, color: AppTokens.muted)),
                      ]),
                      const SizedBox(height: 10),
                      Text(d.part,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.fg)),
                      const SizedBox(height: 6),
                      Text('${d.type} · ${d.resp}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTokens.muted)),
                      const SizedBox(height: 2),
                      Text(d.ts,
                          style: const TextStyle(
                              fontSize: 12, color: AppTokens.muted)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}
