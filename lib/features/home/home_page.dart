import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/section_title.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../shared/widgets/project_switcher.dart';
import '../../shared/widgets/user_switcher.dart';
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
    this.size = 22,
    this.weight = FontWeight.w700,
    this.color = AppTokens.fg,
    this.letterSpacing = 0,
  });

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          // 数字跟随各平台系统字体（iOS SF Pro / Android Roboto），
          // 用等宽数字保证计数对齐；不再强制 Nunito。
          fontFeatures: const [FontFeature.tabularFigures()],
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider);
    final floors = ref.watch(floorsProvider);
    final defects = ref.watch(defectsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppTokens.space3,
        title: AsyncState(
          value: project,
          builder: (p) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 第 1 行：项目切换按钮（项目名 + chevron）
              const Align(
                alignment: Alignment.centerLeft,
                child: ProjectSwitcher(),
              ),
              // 第 2 行：天气 · AQI · 施工状态（纯文本 12/400/#666666）
              Row(
                children: [
                  const _WeatherAqiTexts(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppTokens.fg2,
                          height: 20 / 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: UserSwitcher(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.space3, AppTokens.space3, AppTokens.space3, AppTokens.space5),
        children: [
          // —— 0. 天气预警（有预警时置顶显示，自带间距）——
          const _WeatherAlertBanner(),

          // —— 项目指标（白卡 4 等分，无标题直贴导航栏下方）——
          AsyncState(
            value: floors,
            builder: (fs) => AsyncState(
              value: defects,
              builder: (ds) => _CompactMetrics(floors: fs, defects: ds),
            ),
          ),
          const SizedBox(height: AppTokens.space3), // 项目指标 → 快捷操作 间距 12

          // —— 快捷操作（横向滑动，每张卡更紧凑）——
          floors.maybeWhen(
            data: (fs) => _QuickActions(floors: fs),
            orElse: () => const _QuickActions(floors: _mockDataFloors),
          ),
          const SizedBox(height: AppTokens.space3),

          // —— 项目进度时间轴（列出关键节点）——
          AsyncState(
            value: project,
            builder: (p) => AsyncState(
              value: defects,
              builder: (ds) => _ProjectTimelineCard(project: p, defects: ds),
            ),
          ),
          const SizedBox(height: AppTokens.space3),

          // —— 2.5 数据闭环价值条（弱化、不抢重点，展示产品定位）——
          const _ValueStrip(),
          const SizedBox(height: 24), // 数据闭环价值条 → 今日待办 间距 24

          // —— 4. 今日待办（Frame 2131330676：待办 · N / 日期副行 / 新卡片）——
          AsyncState(value: defects, builder: _TodoSection.new),
          const SizedBox(height: AppTokens.space4),

          // —— 5. 项目大事记（重点内容）——
          SectionTitle(
              title: '项目大事记',
              action: '查看全部',
              actionIcon: MingCuteIcons.rightLine,
              onAction: () =>
                  AppSnack.show(context, '大事记列表页建设中，敬请期待')),
          // 标题 → 卡片间距 8（SectionTitle 自带下 padding 8 承担）
          const _TimelineEvents(),
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
  final List<GlobalKey> _chipKeys = []; // 每张里程碑卡挂 key，供点击后居中聚焦
  bool _autoScrolled = false;
  String? _projectId;
  int? _selectedIdx; // 点击选中的里程碑卡（选中态：#E6F5FF 底 + 蓝框，日期/阶段名保持原色）

  @override
  void didUpdateWidget(covariant _ProjectTimelineCard old) {
    super.didUpdateWidget(old);
    // 项目切换后重置自动滚动定位与选中态
    if (_projectId != widget.project.id) {
      _projectId = widget.project.id;
      _autoScrolled = false;
      _selectedIdx = null;
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 把指定索引的里程碑卡滚动到列表可视区居中（alignment 0.5），避免边缘卡片被遮挡。
  void _scrollToItem(int i) {
    if (!_scrollCtrl.hasClients) return;
    final ctx = _chipKeys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        alignment: 0.5, duration: const Duration(milliseconds: 250));
  }

  /// 首帧后把「当前」节点卡滚动到列表中间（居中聚焦），仅首次执行。
  void _scrollToFocus(int focusIdx) {
    if (_autoScrolled) return;
    _scrollToItem(focusIdx);
    _autoScrolled = true;
  }

  /// 选中节点详情条（内嵌在项目进度卡内，替代原底部弹窗）：
  /// #F1F7FF 底圆角 8，padding 4/8，两行：计划时间 / 状态。
  Widget _detailStrip(Milestone m) {
    const gray = Color(0xFF666666);
    const iconGray = Color(0xFF999999); // 计划时间/状态图标颜色
    const blue = Color(0xFF0395FF);
    final statusText = m.done ? '已完成' : m.current ? '进行中' : '未开始';
    final statusColor = m.current
        ? blue
        : m.done
            ? const Color(0xFF34C759)
            : const Color(0xFFFF3B30); // 未开始/未来 = 规范红 #FF3B30，与里程碑标签「未来」一致

    Widget row(IconData icon, String label, String value, Color valueColor) =>
        Row(
          children: [
            Icon(icon, size: 14, color: iconGray),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    height: 20 / 12,
                    fontWeight: FontWeight.w400,
                    color: gray)),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    height: 20 / 12,
                    fontWeight: FontWeight.w400,
                    color: valueColor)),
          ],
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F5FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(MingCuteIcons.timeLine, '计划时间：', m.date, gray),
          row(MingCuteIcons.threeQuartersCircleDashLine, '状态：',
              statusText, statusColor),
        ],
      ),
    );
  }

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
              child: const Icon(MingCuteIcons.gitBranchLine,
                  color: AppTokens.brand),
            ),
            const SizedBox(width: AppTokens.space3),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('项目进度',
                      style: TextStyle(
                          fontSize: 16,
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

    // 选中节点：默认选「当前」节点，无当前节点则退到最后一个
    final currentSel = ms.indexWhere((m) => m.current);
    final selIdx = (_selectedIdx ?? (currentSel >= 0 ? currentSel : ms.length - 1))
        .clamp(0, ms.length - 1);

    // 卡 key 列表与里程碑数量对齐，供点击后居中聚焦
    if (_chipKeys.length != ms.length) {
      _chipKeys.clear();
      _chipKeys.addAll(List.generate(ms.length, (_) => GlobalKey()));
    }

    return AppCard(
      padding: const EdgeInsets.all(AppTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：项目进度标题 + 浅蓝底蓝字百分比徽标（圆角 6）
          Row(
            children: [
              const Text('项目进度',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 24 / 16,
                      letterSpacing: 0,
                      color: AppTokens.fg)),
              const Spacer(),
              Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTokens.brandTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 20 / 12,
                    color: Color(0xFF0395FF),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 渐变进度条（底 #F1F7FF，填充 #61D3FA→#428BF7，末端 3 白点装饰）
          _GradientProgressBar(value: progress),
          const SizedBox(height: 16), // 进度条 → 里程碑卡片 间距 16
          // 横向里程碑卡列表（可左右滑动；首帧后聚焦到「当前」节点卡并居中）
          Builder(builder: (ctx) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToFocus(currentSel >= 0 ? currentSel : ms.length - 1);
            });
            return               SizedBox(
              height: 60, // 卡片 padding 8+8 + 标签 44 = 60
              child: ScrollConfiguration(
                behavior: _MouseDragScrollBehavior(),
                child: ListView.separated(
                  controller: _scrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: ms.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _MilestoneChip(
                    key: _chipKeys[i], // 每张卡挂 key，供点击后居中聚焦
                    m: ms[i],
                    selected: selIdx == i,
                    onTap: () {
                      setState(() => _selectedIdx = i);
                      _scrollToItem(i); // 点击后把该卡滚动到居中，避免边缘被遮挡
                    },
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          // 选中节点详情条（默认展示当前节点）
          _detailStrip(ms[selIdx]),
        ],
      ),
    );
  }
}

/// 渐变进度条：底色浅蓝 + 渐变填充，末端 3 个白色圆点（透明度 0.3/0.6/1）纯装饰。
class _GradientProgressBar extends StatelessWidget {
  final double value;
  const _GradientProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return SizedBox(
      height: 8,
      child: Stack(
        children: [
          // 底槽
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE6F5FF),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          // 渐变填充 + 末端白点
          FractionallySizedBox(
            widthFactor: v,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xFF61D3FA), Color(0xFF0395FF)],
                      ),
                    ),
                  ),
                  if (v > 0.15)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _dot(0.3),
                            const SizedBox(width: 2),
                            _dot(0.6),
                            const SizedBox(width: 2),
                            _dot(1),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(double opacity) => Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
      );
}

/// 横向里程碑卡（60 高，#F8F8F8 底圆角 8，padding all(8)，gap 8，Frame 2131330648）：
/// 左侧 20×44 竖排状态标签（白底圆角 4）+ 右侧两行文本（日期 12/W700/#222222、阶段名 14/W400/#666666）。
/// 状态标签三态（已统一为规范分区色）：当前 = 品牌蓝(#0395FF)底白字「当前」；完成 = 白底绿字(#34C759)「完成」；未来 = 白底红字(#FF3B30)「未来」。
/// 选中（当前 / 点击）卡：底色 #E6F5FF + 边框 #0395FF 1pt；日期与阶段名保持原色。
class _MilestoneChip extends StatelessWidget {
  final Milestone m;
  final bool selected;
  final VoidCallback onTap;
  const _MilestoneChip(
      {super.key, required this.m, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF0395FF);
    const green = Color(0xFF34C759);
    const red = Color(0xFFFF3B30);
    final isCurrent = m.current;
    // 状态文案：当前节点优先；已完成（非当前）标记「完成」；其余「未来」
    final label = isCurrent ? '当前' : (m.done ? '完成' : '未来');
    final tagBg = isCurrent ? blue : Colors.white;
    final tagFg = isCurrent
        ? Colors.white
        : (m.done ? green : red); // 完成=绿、未来=红

    // 选中态：仅底色 + 边框变化，日期/阶段名保持原色（#222222 / #666666）
    final cardColor = selected ? const Color(0xFFE6F5FF) : const Color(0xFFF8F8F8);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        // 所有卡都带 1px 边框（未选中为透明），保证高度一致
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? blue : Colors.transparent, width: 1),
        ),
        child: Row(
          // 竖排标签与文字组垂直居中对齐；内容自适应宽度（横向列表无界宽度下不使用 Expanded）
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 竖排状态标签：20×44，两字上下排列（12/W400，行高 18）
            Container(
              width: 20,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tagBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final ch in label.split(''))
                    Text(
                      ch,
                      // strut 强制行盒 = 18px，避免 CJK 字形在行盒内偏移
                      strutStyle: const StrutStyle(
                          fontSize: 12,
                          height: 18 / 12,
                          forceStrutHeight: true),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 18 / 12,
                        color: tagFg,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 右侧两行：日期(12/W600/#222222) + 阶段名(14/W400/#666666)，固定 42 高与标签等高
            SizedBox(
              height: 42,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _cnDate(m.date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: const StrutStyle(
                        fontSize: 12,
                        height: 20 / 12,
                        forceStrutHeight: true),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 20 / 12,
                      color: Color(0xFF222222),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: const StrutStyle(
                        fontSize: 14,
                        height: 22 / 14,
                        forceStrutHeight: true),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 22 / 14,
                      color: Color(0xFF666666),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 节点日期中文短格式：`2024-03-31` -> `24年3月31日`。
String _cnDate(String d) {
  final dt = _parseDate(d);
  if (dt == null) return d;
  final y = dt.year % 100;
  return '$y年${dt.month}月${dt.day}日';
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
  Widget build(BuildContext context) => Row(
        children: [
          _QuickCard(
            iconAsset: 'assets/icons/patrol.png',
            title: '立即巡场',
            subtitle: '离线可用',
            gradientBegin: const Color(0xFF0174F8),
            gradientEnd: const Color(0xFF57C2FF),
            onTap: () => context.go('/patrol'),
          ),
          const SizedBox(width: 12),
          _QuickCard(
            iconAsset: 'assets/icons/capture.png',
            title: '拍照验收',
            subtitle: 'AI 识别',
            gradientBegin: const Color(0xFFFF5E5B),
            gradientEnd: const Color(0xFFFD8B7C),
            onTap: () => context.push('/capture'),
          ),
          const SizedBox(width: 12),
          _QuickCard(
            iconAsset: 'assets/icons/drawings.png',
            title: '项目图纸',
            subtitle: '${floors.length} 张',
            gradientBegin: const Color(0xFFFE8E18),
            gradientEnd: const Color(0xFFFFC13F),
            onTap: () => context.go('/projects'),
          ),
        ],
      );
}

/// 快捷操作大卡（114×110，圆角 12）：竖向渐变底 + 36×36 图标切图
/// + 标题 14/W600 白字 + 副标题 12/W400 白字（透明度 0.7）。
class _QuickCard extends StatelessWidget {
  final String iconAsset;
  final String title;
  final String subtitle;
  final Color gradientBegin;
  final Color gradientEnd;
  final VoidCallback onTap;
  const _QuickCard({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.gradientBegin,
    required this.gradientEnd,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 110,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [gradientBegin, gradientEnd],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 36×36 图标切图（PNG 自带白底）
                Image.asset(iconAsset, width: 36, height: 36),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 22 / 14,
                    color: Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 20 / 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ==================== 数据闭环价值条（弱化、展示产品定位） ====================
/// 设计院视角的四步数据闭环：现场拍照 → AI 分类关联图纸规范 → 责任判定 → 知识库。
/// 用首页统一卡片风格（AppCard 白底圆角 12、无描边），弱化内部对比度不抢重点。
class _ValueStrip extends StatelessWidget {
  const _ValueStrip();

  static const _steps = [
    _StripStep(icon: LucideIcons.camera, label: '现场拍照'),
    _StripStep(icon: LucideIcons.brainCircuit, label: 'AI 分类关联'),
    _StripStep(icon: LucideIcons.scale, label: '责任判定'),
    _StripStep(icon: LucideIcons.database, label: '知识库'),
  ];

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space4, vertical: 12),
        child: Row(
          children: [
            // 左侧：闭环标题（竖排小字，弱化）
            const Padding(
              padding: EdgeInsets.only(right: AppTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('数据',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppTokens.fg)),
                  Text('闭环',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppTokens.accent)),
                ],
              ),
            ),
            // 四步：图标 + 名称 + 连接线（从顶部对齐，连接线对准图标中心）
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _steps.length; i++) ...[
                    _StripStepView(step: _steps[i]),
                    if (i < _steps.length - 1) const _StripConnector(),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

class _StripStep {
  final IconData icon;
  final String label;
  const _StripStep({required this.icon, required this.label});
}

class _StripStepView extends StatelessWidget {
  final _StripStep step;
  const _StripStepView({required this.step});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(step.icon, size: 14, color: AppTokens.note),
            ),
            const SizedBox(height: 4),
            Text(step.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 9,
                    color: AppTokens.muted,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _StripConnector extends StatelessWidget {
  const _StripConnector();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          // 顶部留白 = 图标高度的一半（26/2），让连接线对齐图标中心
          const SizedBox(height: 13),
          Container(
            width: 10,
            height: 1.5,
            color: AppTokens.border,
          ),
        ],
      );
}

// ==================== 今日待办（Frame 2131330676） ====================
/// 待办板块：头部单行（「待办 · N」16/W600/#000000 | 「日期 | 查看全部」12/W400/#999999 + 16px 右箭头，
/// space-between 两端对齐）+ 白底圆角 12 卡片列表（卡间 gap 8）。
class _TodoSection extends StatelessWidget {
  final List<Defect> ds;
  const _TodoSection(this.ds);

  /// 中文日期：`8月18日 星期二`（设计稿全称星期）。
  static String _cnDate() {
    final d = DateTime.now();
    const wd = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${d.month}月${d.day}日 ${wd[(d.weekday - 1) % 7]}';
  }

  @override
  Widget build(BuildContext context) {
    final todos = ds
        .where((d) =>
            d.status == DefectStatus.draft || d.status == DefectStatus.doing)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部单行：待办 · N（左） | 日期 | 查看全部 + 右箭头（右，整体可点跳转工单页）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('待办 · ${todos.length}',
                strutStyle: const StrutStyle(
                    fontSize: 16, height: 24 / 16, forceStrutHeight: true),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 24 / 16,
                    color: Color(0xFF000000))),
            InkWell(
              onTap: () => context.go('/defects'),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${_cnDate()} | 查看全部',
                      strutStyle: const StrutStyle(
                          fontSize: 12,
                          height: 20 / 12,
                          forceStrutHeight: true),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 20 / 12,
                          color: Color(0xFF999999))),
                  const SizedBox(width: 4),
                  const Icon(MingCuteIcons.rightLine,
                      size: 16, color: Color(0xFF999999)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.space2), // 头部 → 卡片 gap 8
        if (todos.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.space3),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTokens.successSoft,
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                    child: const Icon(MingCuteIcons.checksLine,
                        color: AppTokens.success, size: 16),
                  ),
                  const SizedBox(width: AppTokens.space3),
                  const Text('当前无待办，所有缺陷已处理',
                      style: TextStyle(
                          fontSize: 14,
                          color: AppTokens.muted,
                          fontWeight: FontWeight.w400)),
                ],
              ),
            ),
          )
        else
          for (var i = 0; i < todos.take(4).length; i++) ...[
            if (i > 0) const SizedBox(height: AppTokens.space2),
            _TodoCard(d: todos[i]),
          ],
      ],
    );
  }
}

/// 单张待办卡（白底圆角 12、padding 12）：
/// 行 1：标题 16/W600/#222222 + 分类标签(#F1F7FF/#428BF7) | 状态标签(#FF4444 白字)；
/// 行 2：标签流（严重度 / 类型 / 楼层 / #自定义标签，均 12/W400 圆角 6）；
/// 行 3：左侧（记录人 + 责任人）一组 | 右侧时间 12/#999999，两端对齐。
class _TodoCard extends StatelessWidget {
  final Defect d;
  const _TodoCard({required this.d});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppTokens.space3),
        onTap: () => context.push('/defects/record/${d.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 行 1：标题 + 分类标签 | 状态标签
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(d.part,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            strutStyle: const StrutStyle(
                                fontSize: 16,
                                height: 24 / 16,
                                forceStrutHeight: true),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 24 / 16,
                                color: AppTokens.fg)),
                      ),
                      const SizedBox(width: 4),
                      _catTag(d.category),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                _statusTag(d.status),
              ],
            ),
            const SizedBox(height: 4),
            // 行 2：标签流
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _zoneTag(d.severity),
                _grayTag(d.type),
                _floorTag(d.floor),
                ...d.tags.take(3).map((t) => _grayTag('#$t')),
              ],
            ),
            const SizedBox(height: AppTokens.space3),
            // 行 3：左侧（记录人 + 责任人）一组 | 右侧时间，两端对齐
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(MingCuteIcons.user3Line,
                        size: 14, color: AppTokens.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(d.reporter,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          strutStyle: const StrutStyle(
                              fontSize: 12,
                              height: 20 / 12,
                              forceStrutHeight: true),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              height: 20 / 12,
                              color: AppTokens.fg2)),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    const Icon(MingCuteIcons.building4Line,
                        size: 14, color: AppTokens.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(d.resp,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          strutStyle: const StrutStyle(
                              fontSize: 12,
                              height: 20 / 12,
                              forceStrutHeight: true),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              height: 20 / 12,
                              color: AppTokens.fg2)),
                    ),
                  ],
                ),
                Text(d.ts.substring(5),
                    strutStyle: const StrutStyle(
                        fontSize: 12, height: 20 / 12, forceStrutHeight: true),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 20 / 12,
                        color: AppTokens.muted)),
              ],
            ),
          ],
        ),
      );
}

/// 分类标签（主色 5% 浅底 / 主色字，12/W400，高 20，圆角 6）。
Widget _catTag(DefectCategory c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTokens.brandTint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(c.label,
          strutStyle: const StrutStyle(
              fontSize: 12, height: 20 / 12, forceStrutHeight: true),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 20 / 12,
              color: AppTokens.brand)),
    );

/// 状态标签（12/W700 白字，圆角 6，padding 2·8）：实色底不套 5% 规则。
/// 与工单页 StatusPill 四色一致：待整改 #FF3B30 / 整改中 #FF9500 / 已销项 #34C759 / 已拒绝 #0395FF。
Widget _statusTag(DefectStatus s) {
  final Color c;
  switch (s) {
    case DefectStatus.draft:
      c = AppTokens.danger;
    case DefectStatus.doing:
      c = AppTokens.warning;
    case DefectStatus.done:
      c = AppTokens.success;
    case DefectStatus.reject:
      c = AppTokens.brand;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(s.label,
        strutStyle: const StrutStyle(
            fontSize: 12, height: 20 / 12, forceStrutHeight: true),
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 20 / 12,
            color: Colors.white)),
  );
}

/// 通用小标签（12/W400，圆角 6，padding 2·8）。
Widget _pillTag(String label, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          maxLines: 1,
          strutStyle: const StrutStyle(
              fontSize: 12, height: 20 / 12, forceStrutHeight: true),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 20 / 12,
              color: fg)),
    );

/// 严重度标签：严重/较重/一般/轻微（红/橙/黄/绿四色），原色文字 + 原色 5% 透明度浅底（Tint 令牌）。
Widget _zoneTag(DefectSeverity s) {
  final Color fg;
  final Color bg;
  switch (s) {
    case DefectSeverity.red:
      fg = AppTokens.danger;
      bg = AppTokens.dangerTint;
    case DefectSeverity.orange:
      fg = AppTokens.warning;
      bg = AppTokens.warningTint;
    case DefectSeverity.yellow:
      fg = const Color(0xFFFADC19);
      bg = AppTokens.yellowTint;
    case DefectSeverity.green:
      fg = AppTokens.success;
      bg = AppTokens.successTint;
  }
  return _pillTag(s.label, fg, bg);
}

/// 灰标签（#F4F6F7 实色底 / #919499 字）：缺陷类型与 #自定义标签，5% 规则的唯一例外。
Widget _grayTag(String label) =>
    _pillTag(label, AppTokens.muted, AppTokens.surface2);

/// 楼层标签（红区色文字 + 红色 5% 浅底，贴合分区体系）。
Widget _floorTag(String label) =>
    _pillTag(label, AppTokens.danger, AppTokens.dangerTint);

// ==================== 项目大事记（重点内容，增强视觉） ====================
/// 大事记事件列表：AppCard 内横向事件行（Frame 2131330695 布局 + 圆点时间轴）。
/// 事件行 = 左区（时间列 40 宽居中「时刻 14/W600/fg + 相对日期 12/400/muted」
/// + 22px 圆点「事件色 5% 浅底 + 12px 彩色图标，规范『浅底 = 文字色 5%』」
/// + 1.5px border 连接线向下延伸 + 标题列「标题 14/W600/fg + 责任人 12/400/muted」）
/// + 右侧类型浅底标签（12/W400 事件色，底 5%，圆角 6，padding 2·8），元素间 gap 8。
class _TimelineEvents extends StatelessWidget {
  const _TimelineEvents();

  static const _events = [
    _Event(
        icon: MingCuteIcons.checkCircleLine,
        color: AppTokens.success,
        type: '验收',
        resp: '深圳市建工集团 王工',
        title: '墙身防水层破损 已修复验收',
        time: '16:20',
        day: '今日'),
    _Event(
        icon: MingCuteIcons.documentLine,
        color: AppTokens.brand,
        type: '图纸',
        resp: '深圳市建工集团 李工',
        title: '完成 B1 顶板分区平面图拍照 12 张',
        time: '14:42',
        day: '今日'),
    _Event(
        icon: MingCuteIcons.warningLine,
        color: AppTokens.warning,
        type: '缺陷',
        resp: '中建三局 张工',
        title: '新增缺陷：B1-轴交 A-F/4-7 顶板裂缝',
        time: '09:42',
        day: '今日'),
    _Event(
        icon: MingCuteIcons.navigationLine,
        color: AppTokens.fg,
        type: '巡场',
        resp: '深圳市建工集团 王工',
        title: '完成上午巡场 1.4km',
        time: '09:00',
        day: '今日'),
    _Event(
        icon: MingCuteIcons.documentLine,
        color: AppTokens.brand,
        type: '图纸',
        resp: '深圳市建工集团 陈工',
        title: '7栋第一轮测试CAD 全部转OCF（10张）',
        time: '09:40',
        day: '昨日'),
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
  final IconData icon; // 事件类型图标（圆点内，与 color 同色）
  final Color color;
  final String type; // 事件类型标签文案（验收/巡场/缺陷/图纸）
  final String resp; // 责任人（含单位，如「深圳市建工集团 李工」）
  final String title;
  final String time; // 时刻（如 16:20）
  final String day; // 相对日期（今日/昨日）
  const _Event({
    required this.icon,
    required this.color,
    required this.type,
    required this.resp,
    required this.title,
    required this.time,
    required this.day,
  });
}

class _EventRow extends StatelessWidget {
  final _Event event;
  final bool isLast;
  const _EventRow({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : AppTokens.space4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左区（flex-grow 1）：时间列 + 圆点列 + 标题列（gap 8）
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 时间列（Frame 2131330692，40 宽居中）：时刻 14/W600/fg + 相对日期 12/400/muted
                    SizedBox(
                      width: 40,
                      child: Column(
                        children: [
                          Text(event.time,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 22 / 14,
                                  color: AppTokens.fg)),
                          Text(event.day,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  height: 20 / 12,
                                  color: AppTokens.muted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 圆点列：22px 圆点（事件色 5% 浅底 + 12px 彩色图标，规范「浅底 = 文字色 5%」）
                    // + 1.5px border 色连接线（Expanded 向下延伸至下一事件圆点，保留时间轴语义）
                    Column(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: event.color.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child:
                                Icon(event.icon, color: event.color, size: 12),
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 1.5,
                              color: AppTokens.border,
                              margin:
                                  const EdgeInsets.symmetric(vertical: 3),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // 标题列（Frame 2131330693）：标题 14/W600/fg + 责任人 12/400/muted
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 22 / 14,
                                  color: AppTokens.fg)),
                          Text(event.resp,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  height: 20 / 12,
                                  color: AppTokens.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 类型浅底标签（Frame 2131330652）：12/W400 事件色，底 5%，圆角 6，padding 2·8
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(event.type,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: event.color,
                        height: 20 / 12)),
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space3),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MetricItem(
              value: '${floors.length}',
              color: AppTokens.brand,
              label: '图纸',
            ),
          ),
          Expanded(
            child: _MetricItem(
              value: '${defects.length}',
              color: AppTokens.warning,
              label: '缺陷',
            ),
          ),
          Expanded(
            child: _MetricItem(
              value: '$done',
              color: AppTokens.success,
              label: '已整改',
            ),
          ),
          const Expanded(
            child: _MetricItem(
              value: '12',
              color: AppTokens.muted,
              label: '在岗',
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String value;
  final Color color;
  final String label;
  const _MetricItem({
    required this.value,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: color,
              height: 32 / 24,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppTokens.fg2,
              height: 20 / 12,
            ),
          ),
        ],
      );
}

/// AppBar 第 2 行：天气 + AQI 纯文本（12/400/#666666/行高20，设计稿样式）。
class _WeatherAqiTexts extends ConsumerWidget {
  const _WeatherAqiTexts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(weatherProvider);
    return w.maybeWhen(
      data: (info) {
        final hasAqi = info.aqi != null && info.aqi!.isNotEmpty;
        final aqiText = hasAqi
            ? 'AQI ${info.aqi}${info.category == null || info.category!.isEmpty ? '' : ' ${info.category}'}'
            : null;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${info.text} ${info.temp}°C',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppTokens.fg2,
                    height: 20 / 12)),
            if (aqiText != null) ...[
              const SizedBox(width: 8),
              Text(aqiText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppTokens.fg2,
                      height: 20 / 12)),
            ],
          ],
        );
      },
      orElse: () => const Text('--°C',
          style: TextStyle(fontSize: 12, color: AppTokens.fg2)),
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
            Icon(MingCuteIcons.warningLine, size: 18, color: color),
            const SizedBox(width: AppTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${first.type}预警 · ${first.level}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  if (first.title.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(first.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTokens.muted,
                            fontWeight: FontWeight.w400)),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _dismissed = true),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(MingCuteIcons.closeLine, size: 16, color: AppTokens.muted),
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