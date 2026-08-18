import 'dart:async';
import 'package:flutter/gestures.dart';
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
import '../../shared/widgets/maskable_name.dart';
import '../../data/models.dart';
import '../../data/mock/mock_data.dart';

const _mockDataFloors = floors;

/// 大数字展示（圆润时尚 · SF Pro Rounded 风）。
class NumText extends StatelessWidget {
  final String text;
  final double size;
  final FontWeight weight;
  final Color color;
  final double letterSpacing;
  const NumText(
    this.text, {
    super.key,
    this.size = 20,
    this.weight = FontWeight.w800,
    this.color = AppTokens.fg,
    this.letterSpacing = -0.5,
  });

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontFamilyFallback: const [
            '-apple-system',
            'SF Pro Rounded',
            'Inter',
          ],
          fontSize: size,
          height: 1,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          color: color,
        ),
      );
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  /// 把 DateTime 转为 `MM-DD 周X` 形式（如 `08-15 周五`）。
  String _dateLabel() {
    final d = DateTime.now();
    const wd = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${wd[(d.weekday - 1) % 7]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider);
    final floors = ref.watch(floorsProvider);
    final defects = ref.watch(defectsProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: AppTokens.space4,
        title: AsyncState(
          value: project,
          builder: (p) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 第 1 行：项目切换按钮（含项目名 + chevron）
              const Align(
                alignment: Alignment.centerLeft,
                child: ProjectSwitcher(),
              ),
              const SizedBox(height: 5),
              // 第 2 行：时间 · 天气 · 状态
              Row(
                children: [
                  const _ClockText(),
                  const SizedBox(width: 8),
                  // 天气（调本地 /api/weather 代理，真实数据）
                  _WeatherBadge(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatusTag(
                        text: p.status,
                        color: AppTokens.warning),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 10),
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
        padding: const EdgeInsets.fromLTRB(
            AppTokens.space3, AppTokens.space3, AppTokens.space3, AppTokens.space5),
        children: [
          // —— 0. 天气预警（有预警时置顶显示，自带间距）——
          const _WeatherAlertBanner(),

          // —— 1. 项目进度时间轴（列出关键节点）——
          AsyncState(
            value: project,
            builder: (p) => AsyncState(
              value: defects,
              builder: (ds) => _ProjectTimelineCard(project: p, defects: ds),
            ),
          ),
          const SizedBox(height: AppTokens.space3),

          // —— 2. 快捷操作（横向滑动，每张卡更紧凑）——
          floors.maybeWhen(
            data: (fs) => _QuickActions(floors: fs),
            orElse: () => const _QuickActions(floors: _mockDataFloors),
          ),
          const SizedBox(height: AppTokens.space3),

          // —— 4. 今日待办（标题改为具体日期）——
          SectionTitle(
            title: '${_dateLabel()} 待办',
            subtitle: '重点',
            action: '查看全部',
            actionIcon: LucideIcons.chevronRight,
            onAction: () => context.go('/defects'),
          ),
          const SizedBox(height: AppTokens.space2),
          AsyncState(value: defects, builder: _TodoList.new),
          const SizedBox(height: AppTokens.space4),

          // —— 5. 项目大事记（重点内容）——
          const SectionTitle(
              title: '项目大事记',
              subtitle: '实时',
              action: '查看全部',
              actionIcon: LucideIcons.chevronRight),
          const SizedBox(height: AppTokens.space2),
          const _TimelineEvents(),
          const SizedBox(height: AppTokens.space4),

          // —— 6. 弱化项目指标（紧凑横排一行，4 项）——
          const SectionTitle(title: '项目指标'),
          const SizedBox(height: AppTokens.space2),
          AsyncState(
            value: floors,
            builder: (fs) => AsyncState(
              value: defects,
              builder: (ds) => _CompactMetrics(floors: fs, defects: ds),
            ),
          ),
          const SizedBox(height: AppTokens.space4),

          floors.maybeWhen(
            data: (fs) => OfflineBar.home(fs.length),
            orElse: () => OfflineBar.home(_mockDataFloors.length),
          ),
        ],
      ),
    );
  }
}

// ==================== 项目进度时间轴（横向滚动） ====================
class _ProjectTimelineCard extends StatefulWidget {
  final Project project;
  final List<Defect> defects;
  const _ProjectTimelineCard({required this.project, required this.defects});

  @override
  State<_ProjectTimelineCard> createState() => _ProjectTimelineCardState();
}

class _ProjectTimelineCardState extends State<_ProjectTimelineCard> {
  final ScrollController _scrollCtrl = ScrollController();
  // 每个节点卡片的等宽宽度（含间距），用于居中定位
  static const double _itemWidth = 82;
  bool _autoScrolled = false;
  String? _projectId;

  @override
  void didUpdateWidget(covariant _ProjectTimelineCard old) {
    super.didUpdateWidget(old);
    // 项目切换后重置自动滚动定位
    if (_projectId != widget.project.id) {
      _projectId = widget.project.id;
      _autoScrolled = false;
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 滚动到让当前节点偏向左侧（仅首次）。
  /// 让 current 节点位于视口左侧 1/3 处，右侧留 2/3 空间便于发现后续节点可滚动。
  void _scrollToCurrent(int currentIndex, double viewportWidth) {
    if (_autoScrolled) return;
    if (currentIndex < 0) return;
    if (!_scrollCtrl.hasClients) return;
    final center = currentIndex * _itemWidth + _itemWidth / 2;
    final maxScroll = _scrollCtrl.position.maxScrollExtent;
    // 目标偏移 = 圆点中心 - 视口宽 * 1/3（让 current 在视口 1/3 处）
    final target =
        (center - viewportWidth / 3).clamp(0.0, maxScroll).toDouble();
    _scrollCtrl.jumpTo(target);
    _autoScrolled = true;
  }

  void _showDetail(BuildContext context, Milestone m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppTokens.space4,
                AppTokens.space4, AppTokens.space4, AppTokens.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _milestoneDotBig(m),
                    const SizedBox(width: AppTokens.space3),
                    Expanded(
                      child: Text(m.name,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: AppTokens.fg)),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.space3),
                _detailRow(LucideIcons.calendar, '计划时间', m.date),
                const SizedBox(height: AppTokens.space2),
                _detailRow(
                  m.done
                      ? LucideIcons.checkCircle
                      : m.current
                          ? LucideIcons.loader
                          : LucideIcons.clock,
                  '状态',
                  m.done
                      ? '已完成'
                      : m.current
                          ? '进行中'
                          : '未开始',
                ),
                const SizedBox(height: AppTokens.space4),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _milestoneDotBig(Milestone m) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: m.done
              ? AppTokens.success
              : m.current
                  ? AppTokens.brand
                  : AppTokens.surface3,
          shape: BoxShape.circle,
        ),
        child: Icon(
          m.done
              ? LucideIcons.check
              : m.current
                  ? LucideIcons.loader
                  : LucideIcons.dot,
          color: (m.done || m.current) ? Colors.white : AppTokens.muted,
          size: 18,
        ),
      );

  Widget _detailRow(IconData icon, String label, String value) => Row(
        children: [
          Icon(icon, size: 14, color: AppTokens.muted),
          const SizedBox(width: 8),
          Text('$label：',
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTokens.muted,
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTokens.fg,
                  fontWeight: FontWeight.w700)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final ms = widget.project.milestones;
    // 若暂无节点数据，显示占位
    if (ms.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(AppTokens.space4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTokens.brandSoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
              child: const Icon(LucideIcons.gitBranch,
                  color: AppTokens.brand),
            ),
            const SizedBox(width: AppTokens.space3),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('项目进度',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg)),
                  SizedBox(height: 2),
                  Text('进度节点数据待接入',
                      style: TextStyle(
                          fontSize: 12, color: AppTokens.muted)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final doneCount = ms.where((m) => m.done).length;
    final currentIdx =
        ms.indexWhere((m) => m.current); // -1 表示无当前节点
    // 进度算法：已完成里程碑 + 当前里程碑按时间插值
    double progress;
    if (currentIdx >= 0) {
      // 当前节点内部进度：用「当前日期 vs 当前节点截止日期」做线性插值
      final curDate = _parseDate(ms[currentIdx].date);
      final now = DateTime.now();
      // 当前节点进度 = 当前日期 / 当前节点日期，截断到 [0, 1]
      final ratio = curDate == null
          ? 0.5 // 日期解析失败时按 50% 兜底
          : (now.difference(_prevNodeStart(ms, currentIdx)).inDays /
                  (curDate.difference(_prevNodeStart(ms, currentIdx)).inDays)
                      .clamp(1, 9999))
              .clamp(0.0, 1.0);
      progress = (doneCount + ratio) / ms.length;
    } else {
      progress = doneCount / ms.length;
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.space4, AppTokens.space3, AppTokens.space4, AppTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：项目进度标题 + 百分比
          Row(
            children: [
              const Icon(LucideIcons.gitBranch,
                  size: 15, color: AppTokens.brand),
              const SizedBox(width: 6),
              const Text('项目进度',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: AppTokens.fg)),
              const Spacer(),
              // 百分比弱化：不抢重点
              Text('${(progress * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: AppTokens.muted)),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          // 顶部进度条（淡化：更细 + 更浅色）
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AppTokens.surface2,
              valueColor: AlwaysStoppedAnimation(
                  AppTokens.brand.withValues(alpha: 0.35)),
            ),
          ),
          const SizedBox(height: AppTokens.space2),
          // 横向节点列表（紧凑、可左右拖动）
          // 首帧后定位到当前节点
          Builder(builder: (ctx) {
            final viewportW = MediaQuery.of(ctx).size.width;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToCurrent(currentIdx, viewportW);
            });
            return SizedBox(
              height: 80,
              child: ScrollConfiguration(
                behavior: _MouseDragScrollBehavior(),
                child: ListView.builder(
                  controller: _scrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: ms.length,
                  itemBuilder: (_, i) => _MilestoneChip(
                    m: ms[i],
                    isFirst: i == 0,
                    isLast: i == ms.length - 1,
                    onTap: () => _showDetail(context, ms[i]),
                  ),
                ),
              ),
            );
          }),
          // 横向滚动提示
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.chevronsLeftRight,
                  size: 10, color: AppTokens.muted),
              const SizedBox(width: 3),
              Text(
                currentIdx >= 0
                    ? '当前 ${currentIdx + 1} / ${ms.length}  ·  左右滑动查看节点'
                    : '左右滑动查看节点 · 点节点查看详情',
                style: const TextStyle(
                    fontSize: 10,
                    color: AppTokens.muted,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 横向节点项（竖向：日期 → 圆点+连接线 → 名称）。
/// 节点内部自带左右连接线段（首项省略左侧，末项省略右侧），
/// 保证 ListView 滚动不受 Stack 拦截。
class _MilestoneChip extends StatelessWidget {
  final Milestone m;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  const _MilestoneChip({
    required this.m,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 颜色规则：
    //   已结束 -> muted 灰色淡显
    //   当前进行 -> accent 主题色
    //   未来未发生 -> brand 蓝色
    final isCurrent = m.current;
    final isDone = m.done;
    final dotColor = isDone
        ? AppTokens.muted
        : isCurrent
            ? AppTokens.accent
            : AppTokens.brand;
    final nameColor = isCurrent
        ? AppTokens.fg
        : isDone
            ? AppTokens.muted
            : AppTokens.brand;
    final dateColor = isCurrent
        ? AppTokens.accent
        : isDone
            ? AppTokens.muted
            : AppTokens.brand;
    final nameWeight = isCurrent ? FontWeight.w800 : FontWeight.w600;
    // 连接线颜色：左侧由当前节点状态决定（整个 segment 视为当前节点的颜色）
    final lineColor = isDone
        ? AppTokens.muted
        : isCurrent
            ? AppTokens.accent
            : AppTokens.brand;

    return SizedBox(
      width: _ProjectTimelineCardState._itemWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部：日期（短格式 MM-DD）
              SizedBox(
                height: 16,
                child: Text(
                  _shortDate(m.date),
                  style: TextStyle(
                    fontSize: 9.5,
                    color: dateColor,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // 中部：左连接线 + 圆点 + 右连接线（圆点中心在 Row 垂直中心）
              SizedBox(
                height: 18,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 左连接线（首项不画）
                    if (!isFirst)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.only(right: 1),
                          color: lineColor,
                        ),
                      ),
                    // 圆点
                    Container(
                      width: isCurrent ? 12 : 10,
                      height: isCurrent ? 12 : 10,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        border: isCurrent
                            ? Border.all(
                                color: AppTokens.accent.withValues(alpha: 0.22),
                                width: 3)
                            : null,
                      ),
                      child: isDone
                          ? const Icon(LucideIcons.check,
                              size: 7, color: Colors.white)
                          : isCurrent
                              ? Center(
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle),
                                  ),
                                )
                              : null,
                    ),
                    // 右连接线（末项不画）
                    if (!isLast)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.only(left: 1),
                          color: lineColor,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              // 底部：节点名称（最多 2 行）
              Text(
                m.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: nameWeight,
                  color: nameColor,
                  letterSpacing: -0.1,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 节点日期短格式：`YYYY-MM-DD` -> `YY-MM-DD`（保留年/月/日），如 `26-08-31`。
String _shortDate(String d) {
  final parts = d.split('-');
  if (parts.length >= 3) {
    final y = parts[0].length >= 2 ? parts[0].substring(2) : parts[0];
    return '$y-${parts[1]}-${parts[2]}';
  }
  if (parts.length >= 2) {
    final y = parts[0].length >= 2 ? parts[0].substring(2) : parts[0];
    return '$y-${parts[1]}';
  }
  return d;
}

/// 解析 `YYYY-MM-DD`（不含时分秒）到 DateTime，解析失败返回 null。
DateTime? _parseDate(String d) {
  final parts = d.split('-');
  if (parts.length < 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (y == null || m == null || day == null) return null;
  return DateTime(y, m, day);
}

/// 当前节点区间的起始日期 = 上一个节点的截止日期；无上一个则取 2020-01-01。
DateTime _prevNodeStart(List<Milestone> ms, int currentIdx) {
  if (currentIdx <= 0) return DateTime(2020, 1, 1);
  final prev = _parseDate(ms[currentIdx - 1].date);
  return prev ?? DateTime(2020, 1, 1);
}

// ==================== 快捷操作（横向滑动，更紧凑） ====================
class _QuickActions extends StatelessWidget {
  final List<Floor> floors;
  const _QuickActions({required this.floors});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 78,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          children: [
            _QuickCard(
              icon: LucideIcons.navigation,
              title: '开始巡场',
              subtitle: '离线可用',
              tint: AppTokens.accent,
              onTap: () => context.go('/patrol'),
            ),
            _QuickCard(
              icon: LucideIcons.camera,
              title: '拍照验收',
              subtitle: 'AI 识别',
              tint: AppTokens.brand,
              onTap: () => context.push('/capture'),
            ),
            _QuickCard(
              icon: LucideIcons.folderOpen,
              title: '打开图纸',
              subtitle: '${floors.length} 张',
              tint: AppTokens.success,
              onTap: () => context.go('/projects'),
            ),
            _QuickCard(
              icon: LucideIcons.listChecks,
              title: '缺陷列表',
              subtitle: '查看全部',
              tint: AppTokens.warning,
              onTap: () => context.go('/defects'),
            ),
            _QuickCard(
              icon: LucideIcons.layers,
              title: '图层索引',
              subtitle: '快速定位',
              tint: AppTokens.iosTeal,
              onTap: () => context.go('/projects'),
            ),
            _QuickCard(
              icon: LucideIcons.fileText,
              title: 'PDF 原稿',
              subtitle: '蓝图预览',
              tint: AppTokens.iosOrange,
              onTap: () => context.push('/blueprint'),
            ),
          ],
        ),
      );
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: AppTokens.space2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          child: Container(
            width: 116,
            height: 84,
            padding: const EdgeInsets.all(AppTokens.space3),
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              border: Border.all(color: AppTokens.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  child: Icon(icon, color: tint, size: 16),
                ),
                const Spacer(),
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: AppTokens.fg)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTokens.muted,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      );
}

// ==================== 今日待办（重点内容） ====================
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
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space4),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTokens.successSoft,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: const Icon(LucideIcons.checkCheck,
                    color: AppTokens.success, size: 16),
              ),
              const SizedBox(width: AppTokens.space3),
              const Text('当前无待办，所有缺陷已处理',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppTokens.muted,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    }
    return Column(
      children: todos.take(4).map((d) => _TodoItem(d: d)).toList(),
    );
  }
}

class _TodoItem extends StatelessWidget {
  final Defect d;
  const _TodoItem({required this.d});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.space2),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.space3, AppTokens.space3, AppTokens.space3, AppTokens.space3),
          onTap: () => context.push('/defects/record/${d.id}'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 紧急程度色条（红/橙/黄/绿）
              Container(
                width: 4,
                height: 64,
                decoration: BoxDecoration(
                  color: d.severity.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第 1 行：类型分类 + 缺陷名 + 紧急等级
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _categoryTag(d.category),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(d.part,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                  color: AppTokens.fg)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 第 2 行：紧急等级 + 类型 + 楼层 + 自定义标签（合并到一行）
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _severityTag(d.severity),
                        _miniTag(d.type, AppTokens.mutedA11y),
                        _miniTag(d.floor, AppTokens.brand),
                        ...d.tags
                            .take(3)
                            .map((t) => _plainTag(t)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 第 4 行：记录人 + 责任人
                    Row(
                      children: [
                        const Icon(LucideIcons.user,
                            size: 11, color: AppTokens.muted),
                        const SizedBox(width: 3),
                        Text(d.reporter,
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: AppTokens.muted,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 10),
                        const Icon(LucideIcons.building2,
                            size: 11, color: AppTokens.muted),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(d.resp,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppTokens.muted,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.space2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusPill(status: d.status),
                  const SizedBox(height: 4),
                  Text(d.ts.substring(5),
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppTokens.muted,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ),
      );

}

/// 类型分类标签（建筑/结构/装饰/给排水/暖通/电气/其他）。
Widget _categoryTag(DefectCategory c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTokens.brandSoft,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(c.label,
          style: const TextStyle(
              fontSize: 10,
              color: AppTokens.brand,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.05)),
    );

/// 紧急等级标签（红区/橙区/黄区/绿区）。
Widget _severityTag(DefectSeverity s) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: s.soft,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(s.label,
          style: TextStyle(
              fontSize: 10,
              color: s.color,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.05)),
    );

/// 简洁的自定义标签（深灰色、低调不突兀，灰色细边）。
Widget _plainTag(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppTokens.border, width: 0.5),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text('#$label',
          style: const TextStyle(
              fontSize: 10,
              color: AppTokens.mutedA11y,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.05)),
    );

Widget _miniTag(String label, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppTokens.surface2,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: c,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.05)),
    );

class _StatusPill extends StatelessWidget {
  final DefectStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: status.soft,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Text(status.label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                color: status.color)),
      );
}

// ==================== 项目大事记（重点内容，增强视觉） ====================
class _TimelineEvents extends StatelessWidget {
  const _TimelineEvents();

  static const _events = [
    _Event(
        icon: LucideIcons.checkCircle,
        color: AppTokens.success,
        title: '墙身防水层破损 已修复验收',
        ts: '今天 16:20'),
    _Event(
        icon: LucideIcons.camera,
        color: AppTokens.brand,
        title: '完成 B1 顶板分区平面图拍照 12 张',
        ts: '今天 14:42'),
    _Event(
        icon: LucideIcons.alertTriangle,
        color: AppTokens.warning,
        title: '新增缺陷：B1-轴交 A-F/4-7 顶板裂缝',
        ts: '今天 09:42'),
    _Event(
        icon: LucideIcons.navigation,
        color: AppTokens.accent,
        title: '完成上午巡场 1.4km',
        ts: '今天 09:00'),
    _Event(
        icon: LucideIcons.fileText,
        color: AppTokens.iosTeal,
        title: '7栋第一轮测试CAD 全部转OCF（10张）',
        ts: '昨天'),
  ];

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.space4, AppTokens.space3, AppTokens.space4, AppTokens.space3),
        child: Column(
          children: [
            for (var i = 0; i < _events.length; i++)
              _EventRow(
                  event: _events[i],
                  isLast: i == _events.length - 1),
          ],
        ),
      );
}

class _Event {
  final IconData icon;
  final Color color;
  final String title;
  final String ts;
  const _Event({
    required this.icon,
    required this.color,
    required this.title,
    required this.ts,
  });
}

class _EventRow extends StatelessWidget {
  final _Event event;
  final bool isLast;
  const _EventRow({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧：彩色实心圆 + 连接线
            SizedBox(
              width: 26,
              child: Column(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: event.color,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(event.icon,
                          color: Colors.white, size: 12),
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1.5,
                        color: AppTokens.border,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.space3),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 1, bottom: isLast ? 0 : AppTokens.space3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: AppTokens.fg,
                              height: 1.3)),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Text(event.ts,
                        style: const TextStyle(
                            fontSize: 10.5,
                            color: AppTokens.muted,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

// ==================== 项目指标（弱化、紧凑横排） ====================
class _CompactMetrics extends StatelessWidget {
  final List<Floor> floors;
  final List<Defect> defects;
  const _CompactMetrics({required this.floors, required this.defects});

  @override
  Widget build(BuildContext context) {
    final done = defects.where((d) => d.status == DefectStatus.done).length;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space3, vertical: AppTokens.space3),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MetricItem(
              icon: LucideIcons.fileText,
              color: AppTokens.brand,
              value: '${floors.length}',
              label: '图纸',
            ),
          ),
          _Divider(),
          Expanded(
            child: _MetricItem(
              icon: LucideIcons.alertCircle,
              color: AppTokens.warning,
              value: '${defects.length}',
              label: '缺陷',
            ),
          ),
          const _Divider(),
          Expanded(
            child: _MetricItem(
              icon: LucideIcons.checkCheck,
              color: AppTokens.success,
              value: '$done',
              label: '已整改',
            ),
          ),
          const _Divider(),
          Expanded(
            child: const _MetricItem(
              icon: LucideIcons.users,
              color: AppTokens.mutedA11y,
              value: '12',
              label: '在岗',
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
        height: 28,
        color: AppTokens.border,
      );
}

class _MetricItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _MetricItem({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              NumText(value, size: 16, color: color, letterSpacing: -0.3),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppTokens.muted,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.05)),
              ),
            ],
          ),
        ],
      );
}

/// 顶部 AppBar 用的小标签（状态条 + 短文字）。
class _StatusTag extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final bg = color.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
          color: color,
        ),
      ),
    );
  }
}

/// 实时时钟：显示 `HH:mm`，每 30 秒刷新。
class _ClockText extends StatefulWidget {
  const _ClockText();

  @override
  State<_ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<_ClockText> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.clock, size: 12, color: AppTokens.muted),
        const SizedBox(width: 3),
        Text('$h:$m',
            style: const TextStyle(
                fontSize: 11,
                color: AppTokens.muted,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }
}

//// AppBar 天气徽标：读取 weatherProvider，显示天气图标 + 温度。
class _WeatherBadge extends ConsumerWidget {
  const _WeatherBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(weatherProvider);
    return w.maybeWhen(
      data: (info) {
        final icon = _weatherIcon(info.iconName);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTokens.warning),
            const SizedBox(width: 2),
            Text('${info.text} ${info.temp}°C',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTokens.muted,
                    fontWeight: FontWeight.w500)),
            // AQI 徽标（空气质量）
            if (info.aqi != null && info.aqi!.isNotEmpty) ...[
              const SizedBox(width: 6),
              _AqiBadge(aqi: info.aqi!, category: info.category ?? ''),
            ],
          ],
        );
      },
      orElse: () => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.sun, size: 12, color: AppTokens.warning),
          const SizedBox(width: 2),
          const Text('--°C',
              style: TextStyle(
                  fontSize: 11, color: AppTokens.muted)),
        ],
      ),
    );
  }

  /// 天气描述映射到 LucideIcons。
  IconData _weatherIcon(String name) {
    switch (name) {
      case 'cloudLightning':
        return LucideIcons.cloudLightning;
      case 'cloudRain':
        return LucideIcons.cloudRain;
      case 'cloudSnow':
        return LucideIcons.cloudSnow;
      case 'cloudFog':
        return LucideIcons.cloudFog;
      case 'cloud':
        return LucideIcons.cloud;
      case 'cloudSun':
        return LucideIcons.cloudSun;
      default:
        return LucideIcons.sun;
    }
  }
}

/// AQI 空气质量徽标：圆点 + 等级文字，颜色随空气质量等级变化。
class _AqiBadge extends StatelessWidget {
  final String aqi;
  final String category;
  const _AqiBadge({required this.aqi, required this.category});

  /// 空气质量等级 → 颜色（优/良/轻度/中度/重度/严重）。
  Color get _color {
    final c = category;
    if (c.contains('优')) return const Color(0xFF16A34A); // 绿
    if (c.contains('良')) return const Color(0xFFEAB308); // 黄
    if (c.contains('轻度')) return const Color(0xFFF97316); // 橙
    if (c.contains('中度')) return const Color(0xFFEF4444); // 红
    if (c.contains('重度')) return const Color(0xFF8B5CF6); // 紫
    if (c.contains('严重')) return const Color(0xFF7C2D12); // 褐
    return AppTokens.muted;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          Text(
            'AQI $aqi${category.isEmpty ? '' : ' $category'}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 天气预警 banner：有预警时置顶显示（橙色警示条），可关闭。
class _WeatherAlertBanner extends ConsumerStatefulWidget {
  const _WeatherAlertBanner();

  @override
  ConsumerState<_WeatherAlertBanner> createState() =>
      _WeatherAlertBannerState();
}

class _WeatherAlertBannerState
    extends ConsumerState<_WeatherAlertBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(weatherProvider);
    final warnings = w.maybeWhen(
      data: (info) => info.warnings,
      orElse: () => const <WeatherWarning>[],
    );
    // 无预警或已关闭 → 不渲染
    if (warnings.isEmpty || _dismissed) return const SizedBox.shrink();

    final first = warnings.first;
    final color = first.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.space3, 10, AppTokens.space2, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.alertTriangle, size: 18, color: color),
            const SizedBox(width: AppTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${first.type}预警 · ${first.level}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  if (first.title.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(first.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTokens.mutedA11y,
                            fontWeight: FontWeight.w500)),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _dismissed = true),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(LucideIcons.x, size: 16, color: AppTokens.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// 允许鼠标左键拖拽滚动（Flutter web 默认只支持触摸拖动，鼠标需显式启用）。
class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}