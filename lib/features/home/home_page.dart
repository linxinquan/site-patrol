import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../core/navigation/route_observer.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../shared/widgets/project_switcher.dart';
import '../../shared/widgets/user_switcher.dart';
import '../../shared/widgets/voice_input.dart';
import '../../shared/widgets/app_snack.dart';
import '../../data/models.dart';
import '../../data/mock/mock_data.dart';
import '../measure/ar_measure_page.dart';

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

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with RouteAware, WidgetsBindingObserver {
  // 关闭 PageStorage 滚动恢复：每次进入首页都从顶部开始，
  // 避免切换 tab 后页面被推到上次滚动位置（图纸/缺陷卡片被顶出视口）。
  final ScrollController _mainScrollCtrl = ScrollController(keepScrollOffset: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Web 端浏览器会在首帧后恢复历史滚动位置，仅靠一次 jumpTo 会被覆盖。
    // 这里在首帧及之后多个时间点强制归零，确保首页始终从顶部开始。
    _scheduleJumpToTop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _mainScrollCtrl.dispose();
    super.dispose();
  }

  /// 当首页重新成为顶层路由（从其他 tab 切回）时强制滚回顶部。
  @override
  void didPopNext() => _jumpToTop();

  /// App 生命周期恢复到前台（Web 端对应标签页重新可见）也滚回顶部。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _jumpToTop();
  }

  void _scheduleJumpToTop() {
    for (final delay in [Duration.zero, Duration(milliseconds: 50), Duration(milliseconds: 150), Duration(milliseconds: 300)]) {
      Future.delayed(delay, () {
        if (mounted) _jumpToTop();
      });
    }
  }

  void _jumpToTop() {
    if (_mainScrollCtrl.hasClients) {
      _mainScrollCtrl.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final project = ref.watch(projectProvider);
    final floors = ref.watch(floorsProvider);
    final defects = ref.watch(defectsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppTokens.bg,
        toolbarHeight: 44,
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
              // 第 2 行：施工状态（设计稿 Frame 2131330609，仅 status，已去掉天气/AQI）
              // 与第 1 行无间距：容器高 44 = 24 + 20
              Text(
                p.status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppTokens.fg2,
                  height: 20 / 12,
                ),
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
        // 显式 controller + keepScrollOffset:false：彻底关闭 PageStorage 滚动位置恢复，
        // 每次进入首页都从顶部开始（primary:false 仅脱离共享控制器，关不掉恢复）。
        controller: _mainScrollCtrl,
        primary: false,
        padding: const EdgeInsets.fromLTRB(AppTokens.space3, AppTokens.space3,
            AppTokens.space3, AppTokens.space5),
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
          const SizedBox(height: AppTokens.space4), // 项目指标 → 快捷操作 间距 16

          // —— 快捷操作（4×2 网格，自适应屏宽，不横向滑动）——
          // ListView 已带左右 12px padding；这里再叠加 12px 让图标离边缘更远（总离边 24）。
          // 关键点：childAspectRatio 必须让每格高度 = 卡片真实内容高(图标40+间距4+文字20=64)，
          // 否则 GridView 会把格子拉高、底部留出空白，放大「快捷操作→项目进度」的视觉间距。
          // 当前可用宽 342、4 列 3 间距：crossAxisSpacing 42 → 列宽 54；childAspectRatio 54/64
          // → 格高正好 64，无多余空白，该段间距才真正等于下方 SizedBox(space3=12)。四字标签 48<54 放得下。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space3),
            child: floors.maybeWhen(
              data: (fs) => _QuickActions(floors: fs),
              orElse: () => const _QuickActions(floors: _mockDataFloors),
            ),
          ),
          const SizedBox(height: AppTokens.space3), // 快捷操作 → 项目进度 间距 12

          // —— 项目进度时间轴（列出关键节点）——
          AsyncState(
            value: project,
            builder: (p) => AsyncState(
              value: defects,
              builder: (ds) => _ProjectTimelineCard(project: p, defects: ds),
            ),
          ),
          const SizedBox(height: AppTokens.space5), // 项目进度 → 今日待办 间距 24

          // —— 4. 今日待办（Frame 2131330676：待办 · N / 日期副行 / 新卡片）——
          AsyncState(value: defects, builder: _TodoSection.new),
          const SizedBox(height: AppTokens.space5), // 今日待办 → 项目大事记 间距 24

          // —— 5. 项目大事记（按 Frame 2147227969：白卡列表）——
          const Text('项目大事记',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 24 / 16,
                  color: AppTokens.fg)),
          const SizedBox(height: AppTokens.space2), // 标题 → 卡片列表 gap 8
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
  final List<GlobalKey> _chipKeys = []; // 每张里程碑卡挂 key，供首帧聚焦到「当前」节点
  bool _autoScrolled = false;
  String? _projectId;
  int? _selectedIdx; // 选中的里程碑（默认当前节点）；点击后持久、并自动聚焦居中

  @override
  void didUpdateWidget(covariant _ProjectTimelineCard old) {
    super.didUpdateWidget(old);
    // 项目切换后重置自动滚动定位
    if (_projectId != widget.project.id) {
      _projectId = widget.project.id;
      _autoScrolled = false;
      _selectedIdx = null; // 切换项目后重新默认到当前节点
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

  /// 底部信息条：计划时间（选中里程碑日期）+ 状态（跟随选中里程碑：已完成 / 进行中 / 未开始）。
  /// 按稿 Frame 2147227959：渐变 #F1F7FF→#FFFFFF 底、圆角 8、padding 6·8，两行各带灰色图标。
  Widget _planStatusStrip(List<Milestone> ms, int selectedIdx) {
    final sm = ms[selectedIdx];
    final planDate = sm.date;
    final statusText = sm.done ? '已完成' : (sm.current ? '进行中' : '未开始');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF1F7FF), Colors.white],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _planRow(MingCuteIcons.clockLine, '计划时间：', _cnDate(planDate),
              const Color(0xFF60656B)),
          const SizedBox(height: 2),
          _planRow(MingCuteIcons.circleDashLine, '状态：', statusText,
              const Color(0xFF0395FF)),
        ],
      ),
    );
  }

  Widget _planRow(IconData icon, String label, String value, Color valueColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFB5B9BF)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 20 / 12,
                color: Color(0xFF919499))),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 20 / 12,
                color: valueColor)),
      ],
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
                      style: TextStyle(fontSize: 12, color: AppTokens.muted)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final doneCount = ms.where((m) => m.done).length;
    final currentIdx = ms.indexWhere((m) => m.current); // -1 表示无当前节点
    final displayIdx = _selectedIdx ?? (currentIdx >= 0 ? currentIdx : ms.length - 1); // 默认选中「当前」节点：当前卡显示选中样式；点击其他卡后当前回退默认态
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

    return Container(
      // 稿：background: linear-gradient(180deg, rgba(3,149,255,0.06) 0%, rgba(3,149,255,0) 20%), #FFFFFF
      // 两层合成：白底 + 顶部 6% 品牌蓝淡出至透明（20% 之后纯白，避免透明→白的灰带）
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x0F0395FF), Color(0x000395FF)],
                  stops: [0.0, 0.2],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          // 头部：标题 + 百分比徽标，下方进度条（gap 8）
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('项目进度',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 22 / 14,
                          color: Color(0xFF202224))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => showDataLoopModal(context),
                    child: Container(
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0x0D0395FF), // rgba(3,149,255,0.05)
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 20 / 12,
                          leadingDistribution: TextLeadingDistribution.even,
                          color: Color(0xFF0395FF),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _GradientProgressBar(value: progress),
            ],
          ),
          const SizedBox(height: 16),
          // 里程碑卡横向滚动（gap 8；首帧后聚焦到「当前」节点卡并居中）
          Builder(builder: (ctx) {
            while (_chipKeys.length < ms.length) {
              _chipKeys.add(GlobalKey());
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToFocus(displayIdx);
            });
            return SizedBox(
              height: 60,
              child: ScrollConfiguration(
                behavior: _MouseDragScrollBehavior(),
                child: ListView.separated(
                  controller: _scrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: ms.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _MilestoneCard(
                    key: _chipKeys[i],
                    m: ms[i],
                    selected: displayIdx == i,
                    onTap: () {
                      setState(() => _selectedIdx = i);
                      _scrollToItem(i); // 点击自动聚焦居中
                    },
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          // 底部信息条：计划时间 / 状态（跟随选中的里程碑）
          _planStatusStrip(ms, displayIdx),
        ],
      ),
      ),
      ],
    ),
    );
  }
}

/// 渐变进度条：底色 #F1F7FF + 渐变填充(#0395FF→#66D8FF)，末端 3 个白色圆点（透明度 0.3/0.6/1）纯装饰。
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
              color: const Color(0xFFF1F7FF),
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
                        colors: [Color(0xFF0395FF), Color(0xFF66D8FF)],
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

/// 横向里程碑卡（高 60，#F4F6F7 底圆角 8，padding 8，gap 8，Frame 2131330629 等）：
/// 左侧 20×44 竖排状态标签（白底圆角 4，竖排「完成/当前/未来」）+ 右侧两行（日期 12/W600/#202224、阶段名 14/W400/#60656B）。
/// 状态三态：完成 = 白底绿字(#00B84A)；当前 = 蓝底(#0395FF)白字，且整卡底色 #F1F7FF、日期/阶段名转品牌蓝；未来 = 白底红字(#FF4444)。
/// 卡宽由内容自适应（阶段名决定），横向滚动排布。
class _MilestoneCard extends StatelessWidget {
  final Milestone m;
  final bool selected;
  final VoidCallback? onTap;
  const _MilestoneCard(
      {super.key, required this.m, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCurrent = m.current;
    final isDone = m.done;
    final statusLabel = isCurrent ? '当前' : isDone ? '完成' : '未来';
    final statusColor = isCurrent
        ? Colors.white
        : isDone
            ? const Color(0xFF00B84A)
            : const Color(0xFFFF4444);
    final labelBg = isCurrent ? const Color(0xFF0395FF) : Colors.white;
    // 当前/过去/未来卡片外观统一为灰色；仅左侧状态标签配色区分（当前 = 蓝底白字，保持原样）
    const baseCardBg = Color(0xFFF4F6F7);
    const baseDate = Color(0xFF202224);
    const baseName = Color(0xFF60656B);
    // 选中态：背景 5% 品牌蓝 + 文字主题蓝（无描边）
    final cardBg = selected ? const Color(0x0D0395FF) : baseCardBg;
    final dateColor = selected ? const Color(0xFF0395FF) : baseDate;
    final nameColor = selected ? const Color(0xFF0395FF) : baseName;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 60,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
        ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧竖排状态标签（20×44 白底圆角 4）
          Container(
            width: 20,
            height: 44,
            decoration: BoxDecoration(
              color: labelBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: statusLabel.split('').map((c) => Text(
                c,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 18 / 12,
                  color: statusColor,
                ),
              )).toList(),
            ),
          ),
          const SizedBox(width: 8),
          // 右侧两行：日期 + 阶段名（自然宽度，决定卡宽）
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _cnDate(m.date, fullYear: false),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 20 / 12,
                  color: dateColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                m.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 22 / 14,
                  color: nameColor,
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

/// 节点日期中文短格式：`2024-03-31` -> `24年3月31日`。
/// 中文日期：`YYYY年M月D日`（fullYear=true，底部信息条用）或 `YY年M月D日`（fullYear=false，里程碑卡用）。
String _cnDate(String d, {bool fullYear = true}) {
  final dt = _parseDate(d);
  if (dt == null) return d;
  final y = fullYear ? dt.year : dt.year % 100;
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

// ==================== 快捷操作（4×2 网格，自适应屏宽，不横向滑动） ====================
/// 快捷操作图标渐变（统一风格：同向 135° 双色渐变，深→浅同色系）。
/// 8 个分属 8 个不同色相（蓝/橙/青/紫/粉/绿/靛/琥珀），每色最多出现在 2 个图标上，
/// 整体读起来是一套配色。
const _qaGradBlue = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0174F8), Color(0xFF57C2FF)],
);
const _qaGradOrange = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFE8E18), Color(0xFFFFC13F)],
);
const _qaGradCyan = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF00B8D9), Color(0xFF4FD8E8)],
);
const _qaGradPurple = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF7C5CFC), Color(0xFFB79CFF)],
);
const _qaGradPink = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFF4D6D), Color(0xFFFF8FA3)],
);
const _qaGradGreen = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF00B84A), Color(0xFF5FD98A)],
);
const _qaGradIndigo = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF3D5AFE), Color(0xFF7E91FF)],
);
const _qaGradAmber = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFF5A623), Color(0xFFFFD27A)],
);
class _QuickActions extends ConsumerWidget {
  final List<Floor> floors;
  const _QuickActions({required this.floors});

  @override
  Widget build(BuildContext context, WidgetRef ref) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
        crossAxisSpacing: 42,
        mainAxisSpacing: 12,
        childAspectRatio: 54 / 64,
        children: [
          _QuickCard(
            icon: MingCuteIcons.navigationFill,
            title: '工地巡场',
            gradient: _qaGradBlue,
            onTap: () => context.go('/patrol'),
          ),
          _QuickCard(
            icon: MingCuteIcons.cameraFill,
            title: '拍照验收',
            gradient: _qaGradOrange,
            onTap: () => context.push('/capture'),
          ),
          _QuickCard(
            icon: MingCuteIcons.folderOpenFill,
            title: '图纸管理',
            gradient: _qaGradCyan,
            onTap: () => context.go('/projects'),
          ),
          _QuickCard(
            icon: MingCuteIcons.boxFill,
            title: 'AR量尺',
            gradient: _qaGradPurple,
            onTap: () {
              final projectKey = ref.read(currentProjectIdProvider) ?? '';
              final floor = floors.firstOrNull;
              if (floor == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('当前项目没有可用图纸，无法使用AR量尺')),
                );
                return;
              }
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ArMeasurePage(
                  args: MeasureArgs(
                    projectKey: projectKey,
                    drawingKey: floor.key,
                    floor: floor.name,
                  ),
                ),
              ));
            },
          ),
          _QuickCard(
            icon: MingCuteIcons.listCheckFill,
            title: '缺陷工单',
            gradient: _qaGradPink,
            onTap: () => context.go('/defects'),
          ),
          _QuickCard(
            icon: MingCuteIcons.micFill,
            title: '语音记录',
            gradient: _qaGradGreen,
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: AppTokens.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTokens.radiusLg),
                ),
              ),
              builder: (_) => VoiceInputSheet(
                onResult: (text) {
                  AppSnack.show(context, '已识别：$text',
                      kind: AppSnackKind.success);
                },
              ),
            ),
          ),
          _QuickCard(
            icon: MingCuteIcons.clipboardLine,
            title: '验收记录',
            gradient: _qaGradBlue,
            onTap: () => context.push('/capture-records'),
          ),
          _QuickCard(
            icon: MingCuteIcons.layersFill,
            title: '图层索引',
            gradient: _qaGradIndigo,
            onTap: () => context.go('/projects'),
          ),
          _QuickCard(
            icon: MingCuteIcons.fileFill,
            title: 'PDF原稿',
            gradient: _qaGradAmber,
            onTap: () => context.push('/blueprint'),
          ),
        ],
      );
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final LinearGradient gradient;
  final VoidCallback onTap;
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 20 / 12,
                color: Color(0xFF202224),
              ),
            ),
          ],
        ),
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
        // 头部单行：待办 · N（左） | 日期 | 查看全部 + 右箭头（右，整体可点跳转巡场清单页）
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
            if (i > 0) const SizedBox(height: AppTokens.space3),
            _TodoCard(d: todos[i]),
          ],
      ],
    );
  }
}

/// 单张待办卡（白底圆角 8、padding 12，卡内 gap 12）：
/// 行 1：标题 16/W600/#202224（左，截断） + 状态标签（右，实色底白字，高 22）；
/// 行 2：标签流一行（分类蓝 / 严重度红橙 / 楼层红 / 类型灰 / #自定义灰，12/W400 圆角 6）；
/// 行 3：记录人 + 责任人（各 user4Fill 灰图标 + #919499 名，两人间距 12） | 右侧时间，两端对齐。
class _TodoCard extends StatelessWidget {
  final Defect d;
  const _TodoCard({required this.d});

  @override
  Widget build(BuildContext context) => AppCard(
        radius: AppTokens.radiusSm,
        padding: const EdgeInsets.all(AppTokens.space3),
        onTap: () => context.push('/defects/record/${d.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 行 1：标题 + 状态标签（两端对齐）
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(d.part,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      strutStyle: const StrutStyle(
                          fontSize: 16, height: 24 / 16, forceStrutHeight: true),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 24 / 16,
                          color: AppTokens.fg)),
                ),
                const SizedBox(width: 4),
                _statusTag(d.status),
              ],
            ),
            const SizedBox(height: 8),
            // 行 2：标签流（分类 / 严重度 / 楼层 / 类型 / #自定义）
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _catTag(d.category),
                const SizedBox(width: 4),
                _zoneTag(d.severity),
                const SizedBox(width: 4),
                _floorTag(d.floor),
                const SizedBox(width: 4),
                _grayTag(d.type),
                ...d.tags.take(2).map((t) => Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: _grayTag('#$t'),
                    )),
              ],
            ),
            const SizedBox(height: AppTokens.space3),
            // 行 3：记录人 + 责任人 | 时间（两端对齐）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _person(d.reporter),
                      const SizedBox(width: AppTokens.space3),
                      _person(d.resp),
                    ],
                  ),
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

/// 人员行（user4Fill 灰图标 16 + 名称 12/#919499，间距 4）。
Widget _person(String name) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(MingCuteIcons.user4Fill,
            size: 16, color: Color(0xFFB5B9BF)),
        const SizedBox(width: 4),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            strutStyle: const StrutStyle(
                fontSize: 12, height: 20 / 12, forceStrutHeight: true),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 20 / 12,
                color: AppTokens.muted)),
      ],
    );

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
              leadingDistribution: TextLeadingDistribution.even,
              color: AppTokens.brand)),
    );

/// 状态标签（12/W500 白字，高 22，圆角 6，padding 0·8）：实色底不套 5% 规则。
/// 与工单页 StatusPill 四色一致：待整改 #FF4444 / 整改中 #FF9500 / 已销项 #34C759 / 已拒绝 #0395FF。
Widget _statusTag(DefectStatus s) {
  final Color c;
  switch (s) {
    case DefectStatus.draft:
      c = const Color(0xFFFF4444);
    case DefectStatus.doing:
      c = AppTokens.warning;
    case DefectStatus.done:
      c = AppTokens.success;
    case DefectStatus.reject:
      c = AppTokens.brand;
  }
  return Container(
    height: 22,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(s.label,
        strutStyle: const StrutStyle(
            fontSize: 12, height: 20 / 12, forceStrutHeight: true),
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 20 / 12,
            leadingDistribution: TextLeadingDistribution.even,
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
        color: Color(0xFF34C759), // 验收 绿
        type: '验收',
        resp: '深圳市建工集团 王工',
        title: '墙身防水层破损 已修复验收',
        time: '16:20',
        day: '今日'),
    _Event(
        icon: MingCuteIcons.documentLine,
        color: Color(0xFF0395FF), // 图纸 蓝
        type: '图纸',
        resp: '深圳市建工集团 李工',
        title: '完成 B1 顶板分区平面图拍照 12 张',
        time: '14:42',
        day: '今日'),
    _Event(
        icon: MingCuteIcons.warningLine,
        color: Color(0xFFFF9500), // 缺陷 橙
        type: '缺陷',
        resp: '中建三局 张工',
        title: '新增缺陷：B1-轴交 A-F/4-7 顶板裂缝',
        time: '09:42',
        day: '今日'),
    _Event(
        icon: MingCuteIcons.navigationLine,
        color: Color(0xFF919499), // 巡场 灰
        type: '巡场',
        resp: '深圳市建工集团 王工',
        title: '完成上午巡场 1.4km',
        time: '09:00',
        day: '今日'),
    _Event(
        icon: MingCuteIcons.documentLine,
        color: Color(0xFF0395FF), // 图纸 蓝
        type: '图纸',
        resp: '深圳市建工集团 陈工',
        title: '7栋第一轮测试CAD 全部转OCF（10张）',
        time: '09:40',
        day: '昨日'),
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _events.length; i++) ...[
            _EventCard(event: _events[i]),
            if (i < _events.length - 1)
              const SizedBox(height: AppTokens.space3), // 卡片间距 12
          ],
        ],
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

class _EventCard extends StatelessWidget {
  final _Event event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：相对时间（左）+ 类型标签（右）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${event.day} ${event.time}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 22 / 14,
                        color: Color(0xFF60656B))),
                Container(
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // 类型色 5% 浅底（rgb 同类型色，alpha 0.05）
                    color: event.color.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(event.type,
                      style: TextStyle(
                          fontSize: 12,
                          height: 20 / 12,
                          fontWeight: FontWeight.w500,
                          leadingDistribution: TextLeadingDistribution.even,
                          color: event.color)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 分隔线 0.5px #E9EAEB
            Container(height: 0.5, color: const Color(0xFFE9EAEB)),
            const SizedBox(height: 8),
            // 标题 16/W600/#202224
            Text(event.title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 24 / 16,
                    color: Color(0xFF202224))),
            const SizedBox(height: 4),
            // 底部：责任人（user4Fill 灰图标 + 名称）+ 时间
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(MingCuteIcons.user4Fill,
                        size: 16, color: Color(0xFFB5B9BF)),
                    const SizedBox(width: 4),
                    Text(event.resp,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF919499))),
                  ],
                ),
                Text(event.time,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF919499))),
              ],
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF4F6F7), Color(0xFFFFFFFF)],
        ),
        border: Border.all(color: Colors.white, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
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
              color: const Color(0xFFFF4444),
              label: '缺陷',
            ),
          ),
          Expanded(
            child: _MetricItem(
              value: '$done',
              color: const Color(0xFF00B84A),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: color,
              height: 28 / 20,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppTokens.fg,
              height: 20 / 12,
            ),
          ),
        ],
      );
}

/// 天气预警 banner：有预警时置顶显示（橙色警示条），可关闭。
class _WeatherAlertBanner extends ConsumerStatefulWidget {
  const _WeatherAlertBanner();

  @override
  ConsumerState<_WeatherAlertBanner> createState() =>
      _WeatherAlertBannerState();
}

class _WeatherAlertBannerState extends ConsumerState<_WeatherAlertBanner> {
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

// ==================== 数据闭环弹窗（点击项目进度百分比徽标弹出） ====================
/// 居中弹窗：白卡 326×圆角16、遮罩 #000 50%；标题「数据闭环」+ 关闭图标 +
/// 2×2 四步能力卡（现场拍照 / AI 分类关联 / 责任判定 / 知识库）+ 「继续使用」品牌按钮。
void showDataLoopModal(BuildContext context) {
  showDialog(
    context: context,
    useRootNavigator: true,
    barrierColor: const Color(0x80000000),
    barrierDismissible: true,
    builder: (ctx) => Center(
      child: Container(
        width: 326,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 头部：标题居中（按需求去掉关闭图标，点击遮罩或「继续使用」关闭）
            SizedBox(
              height: 48,
              child: const Center(
                child: Text('数据闭环',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 24 / 16,
                        color: Color(0xFF202224))),
              ),
            ),
            const SizedBox(height: 12),
            // 2×2 能力卡
            SizedBox(
              width: 244,
              height: 244,
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                physics: const NeverScrollableScrollPhysics(),
                children: const [
                  _DataLoopTile(
                    icon: MingCuteIcons.cameraFill,
                    iconGradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x000395FF), Color(0xFF0395FF)]),
                    cardGradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x000395FF), Color(0x0D0395FF)]),
                    title: '现场拍照',
                    subtitle: '随手记录',
                  ),
                  _DataLoopTile(
                    icon: MingCuteIcons.classify3AiFill,
                    iconGradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0x00FF4444), Color(0xFFFF4444)]),
                    cardGradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0x00FF4444), Color(0x0DFF4444)]),
                    title: 'AI分类关联',
                    subtitle: '图纸+规范',
                  ),
                  _DataLoopTile(
                    icon: MingCuteIcons.balanceFill,
                    iconGradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0xFF00B84A), Color(0x0000B84A)]),
                    cardGradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0x0D00B84A), Color(0x0000B84A)]),
                    title: '责任判定',
                    subtitle: '设计/施工',
                  ),
                  _DataLoopTile(
                    icon: MingCuteIcons.book6AiFill,
                    iconGradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0xFFFF9500), Color(0x00FF9500)]),
                    cardGradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x0DFF9500), Color(0x00FF9500)]),
                    title: '知识库',
                    subtitle: '反哺设计',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 继续使用（品牌色按钮）
            GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                width: 240,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0395FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('继续使用',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 24 / 16,
                        leadingDistribution: TextLeadingDistribution.even,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DataLoopTile extends StatelessWidget {
  final IconData icon;
  final LinearGradient iconGradient;
  final LinearGradient cardGradient;
  final String title;
  final String subtitle;
  const _DataLoopTile({
    required this.icon,
    required this.iconGradient,
    required this.cardGradient,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          gradient: cardGradient,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => iconGradient.createShader(rect),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 22 / 14,
                    color: Color(0xFF202224))),
            const SizedBox(height: 2),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 20 / 12,
                    color: Color(0xFF919499))),
          ],
        ),
      );
}
