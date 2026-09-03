import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../core/cad/wall_lines.dart';
import '../../data/models.dart';
import '../../shared/widgets/drawing_image.dart';
import '../../utils/geo.dart';
import '../../utils/path_metrics.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_snack.dart';
import '../../core/storage/patrol_record_store.dart';

/// 巡场状态机。
enum _PatrolStatus { idle, running, paused, finished }

/// 巡场页：深色沉浸 + Ticker 轨迹动画（对齐 HTML startPatrol/tickPatrol/finishPatrol）。
/// 底图/路线/楼层均来自当前项目的 PatrolPlan（按 drawingKey 取图纸），不再硬编码。
class PatrolPage extends ConsumerStatefulWidget {
  final PatrolArgs args;
  const PatrolPage({super.key, required this.args});

  @override
  ConsumerState<PatrolPage> createState() => _PatrolPageState();
}

class _PatrolPageState extends ConsumerState<PatrolPage>
    with SingleTickerProviderStateMixin {
  static const int _totalMs = 16000; // 全程 16s（对齐 HTML dt/16）

  late final Ticker _ticker;
  _PatrolStatus _status = _PatrolStatus.idle;
  double _progress = 0;
  Duration _elapsed = Duration.zero;
  Duration _pausedTotal = Duration.zero;
  DateTime? _startedAt;
  DateTime? _pausedAt;
  double _pulse = 0;

  // 数据驱动：从 patrolPlansProvider 解析当前计划（initState 异步加载）。
  PatrolPlan? _plan;
  bool _loadingPlan = true;
  // 真实里程（km）：按图纸校准实算；未校准为 null → 走 plan.totalKm 兜底。
  double? _realKm;

  // P0：地图缩放/平移控制器；"复位"按钮把它打回 Matrix4.identity。
  final TransformationController _transformController =
      TransformationController();

  // P1：巡场页穿墙段下标（路线不变时只算一次）。
  Set<int> _crossingSegs = const {};

  // 任务2：本次巡场检查点打卡（一个点最多一次；完成时写入 PatrolRecord）。
  final List<CheckIn> _checkins = [];
  bool _recordSaved = false;

  // 历史巡场轨迹（已按底图缩放的绝对坐标序列），用于底图叠加显示。
  // 默认隐藏（空），用户从「历史轨迹」面板勾选后才会注入。
  List<List<Offset>> _historyTracks = const [];
  List<Color> _historyColors = const [];
  // 当前"可见"的历史记录下标集合（来自 _HistorySheet 的勾选）。
  Set<int> _visibleHistoryIdxs = const {};

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _resolvePlan();
    // 监听巡场路线列表变化（编辑器保存后 invalidate 触发），自动刷新当前计划与穿墙段，
    // 避免"编辑后没保存"的错觉。保留当前巡场状态（progress/status）。
    ref.listenManual(patrolPlansProvider(ref.read(currentProjectIdProvider) ??
        (ref.read(projectsProvider).valueOrNull?.firstOrNull?.id ?? '')),
        (_, __) {
      if (mounted) _resolvePlan();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _transformController.dispose();
    super.dispose();
  }

  /// P0：地图复位（缩放/平移打回初始值）。
  void _resetView() {
    _transformController.value = Matrix4.identity();
    AppSnack.show(context, '视图已复位', kind: AppSnackKind.muted);
  }

  /// 解析计划：当前项目 → 有 planId 用指定计划，否则取该项目第一条；没有则置空。
  Future<void> _resolvePlan() async {
    try {
      final project = await ref.read(projectProvider.future);
      final plans = await ref.read(patrolPlansProvider(project.id).future);
      PatrolPlan? plan;
      if (widget.args.planId != null) {
        for (final p in plans) {
          if (p.id == widget.args.planId) {
            plan = p;
            break;
          }
        }
      }
      plan ??= plans.isNotEmpty ? plans.first : null;
      final real = await _computeRealKm(plan);
      final crossings = await _computeCrossings(plan);
      // 加载该项目的历史巡场记录（用于底图叠加展示）。
      final records = await ref
          .read(patrolRecordsProvider(plan?.projectId ?? project.id).future);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _realKm = real;
        _crossingSegs = crossings;
        _loadingPlan = false;
        // 历史轨迹像素化延迟到绘制阶段（需要底图实际像素尺寸），这里只缓存记录。
        _historyRecords = records;
        // 重置已像素化缓存，下一帧重算。
        _historyPxCached = false;
      });
    } catch (_) {
      // 项目/计划读取异常：置空，走空态提示。
      if (!mounted) return;
      setState(() {
        _plan = null;
        _loadingPlan = false;
      });
    }
  }

  // 历史记录缓存（未按当前底图像素缩放），到 _buildPatrolBody 里首次绘制时完成像素化。
  List<PatrolRecord> _historyRecords = const [];
  bool _historyPxCached = false;
  double _historyPxW = 0;
  double _historyPxH = 0;

  /// 把历史记录按当前底图实际像素尺寸换算为绝对坐标，并按时间倒序分配冷→暖色。
  /// 仅对 _visibleHistoryIdxs 集合中的记录做像素化（其它默认不画，避免底图被杂色淹没）。
  void _ensureHistoryPixelized(double pw, double ph) {
    if (_historyPxCached &&
        _historyPxW == pw &&
        _historyPxH == ph &&
        _historyTracks.length == _visibleHistoryIdxs.length) {
      return;
    }
    if (_visibleHistoryIdxs.isEmpty) {
      _historyTracks = const [];
      _historyColors = const [];
      _historyPxCached = true;
      _historyPxW = pw;
      _historyPxH = ph;
      return;
    }
    // 配色：越新越暖（紫→红→橙）。
    const palette = <Color>[
      Color(0xFF8B5CF6), // 紫 - 最旧
      Color(0xFFEC4899), // 粉
      Color(0xFFF59E0B), // 橙 - 最近
    ];
    final tracks = <List<Offset>>[];
    final colors = <Color>[];
    // 按时间顺序遍历（i=0 最旧，i=N-1 最新），便于分配冷→暖。
    final visibleSorted = _visibleHistoryIdxs.toList()..sort();
    final n = _historyRecords.length;
    for (var j = 0; j < visibleSorted.length; j++) {
      final i = visibleSorted[j];
      if (i < 0 || i >= n) continue;
      final r = _historyRecords[i];
      if (r.track.isEmpty) continue;
      final pts = <Offset>[];
      for (final m in r.track) {
        final x = (m['x'] ?? 0).toDouble();
        final y = (m['y'] ?? 0).toDouble();
        pts.add(Offset(x * pw / 100, y * ph / 100));
      }
      if (pts.length >= 2) {
        tracks.add(pts);
        final ci = visibleSorted.length <= 1
            ? 0
            : (j * (palette.length - 1) ~/ (visibleSorted.length - 1));
        colors.add(palette[ci.clamp(0, palette.length - 1)]);
      }
    }
    _historyTracks = tracks;
    _historyColors = colors;
    _historyPxCached = true;
    _historyPxW = pw;
    _historyPxH = ph;
  }

  /// 按图纸校准算真实里程（⑤ realRouteKm）；未校准返回 null（totalKm 兜底）。
  Future<double?> _computeRealKm(PatrolPlan? plan) async {
    if (plan == null || plan.points.length < 2) return null;
    final drawing = ref.read(drawingsProvider).valueOrNull?[plan.drawingKey];
    if (drawing == null) return null;
    var mapper = ref.read(cadCalibrationMapProvider)[plan.drawingKey];
    mapper ??= await loadCadCalibration(ref, plan.drawingKey);
    return realRouteKm(plan.points, mapper, drawing.w, drawing.h);
  }

  /// P1：计算穿墙段（仅校准时）。未校准/IO 失败 → 空集合（优雅降级）。
  Future<Set<int>> _computeCrossings(PatrolPlan? plan) async {
    if (plan == null || plan.points.length < 2) return const {};
    try {
      var mapper = ref.read(cadCalibrationMapProvider)[plan.drawingKey];
      mapper ??= await loadCadCalibration(ref, plan.drawingKey);
      final walls = await loadWallLinesRel(plan.drawingKey, mapper);
      if (walls == null) return const {};
      final pts = [for (final p in plan.points) [p.dx, p.dy]];
      return crossingSegments(pts, walls);
    } catch (_) {
      return const {};
    }
  }

  /// 当前计划路径点（PatrolPoint → Offset，供 pointAtProgress 等算法用）。
  List<Offset> get _planOffsets => [
        for (final p in _plan!.points) Offset(p.dx, p.dy),
      ];

  /// 样条采样（缓存）：把推荐路线密集化为平滑曲线点。
  List<Offset>? _planSamples;
  List<Offset> _getPlanSamples() {
    if (_planSamples != null && _planSamples!.length == _planOffsets.length * 16) {
      return _planSamples!;
    }
    return _planSamples = catmullRomSamples(_planOffsets, samplesPerSeg: 16);
  }

  void _onTick(Duration _) {
    // 呼吸脉冲：所有状态都持续（idle/paused/finished 都要保持"当前位置"呼吸感）
    final now = DateTime.now();
    setState(() {
      _pulse = (now.millisecondsSinceEpoch % 1600) / 1600;
    });
    if (_status != _PatrolStatus.running) return;
    final elapsed = now.difference(_startedAt!) - _pausedTotal;
    if (elapsed.inMilliseconds < 0) return;
    final linear = (elapsed.inMilliseconds / _totalMs).clamp(0.0, 1.0);
    // ease-in-out（Cubic Bezier 近似）：起步慢→中段匀速→收尾减速，
    // 让"模拟人走"看起来更自然，而不是匀速机械推进。
    final eased = linear < 0.5
        ? 4 * linear * linear * linear
        : 1 - math.pow(-2 * linear + 2, 3) / 2;
    setState(() {
      _elapsed = elapsed;
      _progress = eased.toDouble();
      if (_progress >= 1.0) {
        _status = _PatrolStatus.finished;
        _progress = 1.0;
      }
    });
    if (_status == _PatrolStatus.finished) {
      _showSummary();
    }
  }

  // —— 状态机动作 ——
  void _start() {
    setState(() {
      _status = _PatrolStatus.running;
      _startedAt = DateTime.now();
      _pausedTotal = Duration.zero;
      _elapsed = Duration.zero;
      _progress = 0;
    });
    AppSnack.show(context, '巡场开始：沿规划路线行进，请留意沿途检查点',
        kind: AppSnackKind.brand);
  }

  void _pause() {
    if (_status != _PatrolStatus.running) return;
    setState(() {
      _status = _PatrolStatus.paused;
      _pausedAt = DateTime.now();
    });
    AppSnack.show(context, '巡场已暂停，当前位置已记录', kind: AppSnackKind.muted);
  }

  void _resume() {
    if (_status != _PatrolStatus.paused) return;
    setState(() {
      _pausedTotal += DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      _status = _PatrolStatus.running;
    });
  }

  void _finish({bool manual = true}) {
    if (_status == _PatrolStatus.finished && !manual) return;
    setState(() {
      _status = _PatrolStatus.finished;
      _progress = 1.0;
      _pausedAt = null;
    });
    if (!_recordSaved) _saveRecord();
    _showSummary();
  }

  void _restart() {
    setState(() {
      _status = _PatrolStatus.idle;
      _progress = 0;
      _elapsed = Duration.zero;
      _pausedTotal = Duration.zero;
      _startedAt = null;
      _checkins.clear();
      _recordSaved = false;
    });
    AppSnack.show(context, '已重置巡场轨迹', kind: AppSnackKind.muted);
  }

  void _showSummary() {
    final t = _checkpointTotal;
    final d = _checkedInIdxs.length;
    final ck =
        t > 0 ? ' · 打卡 $d/$t（${(d / t * 100).round()}%）' : ' · 无检查点';
    AppSnack.show(
      context,
      '巡场完成：${_distKm.toStringAsFixed(2)} km · $_pointCount 点 · $_durationStr$ck',
      kind: AppSnackKind.success,
    );
  }

  // —— 任务2：检查点打卡 ——
  /// 路线检查点总数（达成率分母）。
  int get _checkpointTotal => _plan?.checkpointIdxs.length ?? 0;
  /// 已打卡的检查点下标集合。
  Set<int> get _checkedInIdxs => {for (final c in _checkins) c.pointIdx};
  /// 顶点 idx 沿折线的累计弧长占比（0~1，pointAtProgress 同体系）。
  double _arcFracAt(int idx) {
    final pts = _planOffsets;
    if (pts.length < 2) return 0;
    var total = 0.0, cum = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final d = (pts[i] - pts[i - 1]).distance;
      total += d;
      if (i <= idx) cum += d;
    }
    return total <= 0 ? 0 : cum / total;
  }

  /// 到达打卡：对"当前已到达且未打卡"的最近检查点打卡。
  void _checkInHere() {
    final plan = _plan;
    if (plan == null) return;
    if (_status != _PatrolStatus.running && _status != _PatrolStatus.paused) {
      AppSnack.show(context, '请先开始巡场再打卡', kind: AppSnackKind.muted);
      return;
    }
    final reached = plan.checkpointIdxs
        .where((i) => _arcFracAt(i) <= _progress + 1e-6)
        .toList();
    if (reached.isEmpty) {
      AppSnack.show(context, '尚未到达检查点，请沿路线继续前进',
          kind: AppSnackKind.muted);
      return;
    }
    final already = _checkedInIdxs;
    final pending = reached.where((i) => !already.contains(i)).toList()
      ..sort((a, b) => _arcFracAt(b).compareTo(_arcFracAt(a)));
    if (pending.isEmpty) {
      AppSnack.show(context, '当前已达检查点均已打卡', kind: AppSnackKind.muted);
      return;
    }
    final idx = pending.first;
    final pos = plan.checkpointIdxs.indexOf(idx);
    setState(() {
      _checkins.add(
          CheckIn(pointIdx: idx, tsMs: DateTime.now().millisecondsSinceEpoch));
    });
    AppSnack.show(context, '已打卡 检查点${pos + 1}/共${plan.checkpointIdxs.length}',
        kind: AppSnackKind.brand);
  }

  /// 完成时把本次记录（含打卡）持久化，照 PatrolPlanStore 模式。
  Future<void> _saveRecord() async {
    final plan = _plan;
    final start = _startedAt;
    if (plan == null || start == null || _recordSaved) return;
    _recordSaved = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = PatrolRecord(
      id: 'rec_$now',
      planId: plan.id,
      projectId: plan.projectId,
      drawingKey: plan.drawingKey,
      name: plan.name,
      startedAt: start.millisecondsSinceEpoch,
      finishedAt: now,
      distKm: _distKm,
      pointCount: _pointCount,
      issueCount: 0,
      checkins: List.of(_checkins),
      checkpointTotal: plan.checkpointIdxs.length,
    );
    try {
      final existing = await PatrolRecordStore.list(plan.projectId);
      await PatrolRecordStore.save(plan.projectId, [record, ...existing]);
      if (!mounted) return;
      ref.invalidate(patrolRecordsProvider(plan.projectId));
    } catch (_) {
      // 存储失败不打断巡场流程
    }
  }

  // —— 实时统计 ——
  // 里程：优先按图纸校准实算（_realKm），未校准则用 plan.totalKm 兜底。
  double get _distKm {
    final total = _realKm ?? _plan?.totalKm ?? 0.0;
    return _progress * total;
  }

  int get _pointCount => (_progress * (_plan?.points.length ?? 0)).round();
  String get _durationStr {
    final s = _elapsed.inSeconds.clamp(0, 3599);
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  /// 当前位置（相对坐标 0~1，供标记问题点使用）。
  Offset _currentRel() {
    final raw = pointAtProgress(_planOffsets, _progress);
    return Offset(raw.dx / 100, raw.dy / 100);
  }

  Future<void> _markIssue(Drawing drawing) async {
    final plan = _plan;
    if (plan == null) return;
    final rel = _currentRel(); // 0~1
    // B05 演示校准已写入本地 store（见 providers.dart seedDefaultCalibrations）；
    // 内存映射缺该图时兜底从 store 加载，确保能带世界坐标 mm。
    var mapper = ref.read(cadCalibrationMapProvider)[plan.drawingKey];
    mapper ??= await loadCadCalibration(ref, plan.drawingKey);
    double? wx, wy;
    if (mapper != null) {
      final px = rel.dx * drawing.w; // 0~1 → 整图像素
      final py = rel.dy * drawing.h;
      final w = mapper.screenToWorld(px, py);
      wx = w.dx;
      wy = w.dy;
    }
    if (!mounted) return;
    context.push(
      '/capture',
      extra: CaptureArgs(
        projectId: plan.projectId,
        floor: plan.floor,
        anchorLabel: '巡场中·当前位置',
        x: rel.dx,
        y: rel.dy,
        drawingKey: plan.drawingKey,
        drawPointWorldX: wx,
        drawPointWorldY: wy,
      ),
    );
  }

  void _showHistory() {
    if (_historyRecords.isEmpty) {
      AppSnack.show(context, '暂无历史巡场轨迹', kind: AppSnackKind.muted);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.patrolSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // sheet 关闭后强制刷新一次底图叠加（处理"关闭时清空"等场景）。
      builder: (ctx) => _HistorySheet(
        records: _historyRecords,
        initiallyVisible: _visibleHistoryIdxs,
        onChanged: (visible) {
          if (!mounted) return;
          setState(() {
            _visibleHistoryIdxs = visible;
            // 像素化缓存失效，下一帧按新可见集合重算。
            _historyPxCached = false;
          });
        },
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {
        // 关闭弹窗时若已全部取消勾选，清空 painter 入参，底图恢复干净。
        if (_visibleHistoryIdxs.isEmpty) {
          _historyTracks = const [];
          _historyColors = const [];
          _historyPxCached = false;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final drawingsAsync = ref.watch(drawingsProvider);
    final drawing = _plan == null
        ? null
        : drawingsAsync.valueOrNull?[_plan!.drawingKey];
    return Scaffold(
      backgroundColor: AppTokens.patrolBg,
      appBar: AppBar(
        backgroundColor: AppTokens.patrolBg,
        foregroundColor: AppTokens.patrolFg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 12,
        title: const Text('巡场',
            style: TextStyle(
                color: AppTokens.patrolFg,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 28 / 20)),
        actions: [
          if (_plan != null)
            NavIconButton(
              icon: MingCuteIcons.liveLocationLine,
              color: AppTokens.patrolFg,
              size: 24,
              onPressed: _resetView,
            ),
          if (_plan != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child:               NavIconButton(
                icon: MingCuteIcons.editLine,
                color: AppTokens.patrolFg,
                size: 24,
                onPressed: () => context.push(
                  '/patrol-editor',
                  extra: PatrolArgs(planId: _plan!.id),
                ),
              ),
            ),
        ],
      ),
      body: _loadingPlan
          ? const Center(
              child: CircularProgressIndicator(color: AppTokens.patrolFg))
          : _plan == null || drawing == null
              ? const _EmptyPlanView()
              : _buildPatrolBody(drawing),
    );
  }

  Widget _buildPatrolBody(Drawing drawing) {
    final plan = _plan!;
    // 状态胶囊配置（Frame 2147228032，随 _PatrolStatus 切换）
    final (double pillW, Color pillBg, IconData pillIcon, String pillLabel) =
        switch (_status) {
      _PatrolStatus.idle => (
        60.0,
        const Color(0xFFFF4444),
        MingCuteIcons.circleDashLine,
        '待机'
      ),
      _PatrolStatus.running => (
        72.0,
        const Color(0xFF00B84A),
        MingCuteIcons.camcorder3Line,
        '记录中'
      ),
      _PatrolStatus.paused => (
        72.0,
        const Color(0xFFFF9500),
        MingCuteIcons.pauseCircleLine,
        '已暂停'
      ),
      _PatrolStatus.finished => (
        72.0,
        const Color(0xFF0395FF),
        MingCuteIcons.checkCircleLine,
        '已完成'
      ),
    };
    return Column(
      children: [
        // 顶部：离线提示 + 状态（Frame 2147228032）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // 离线提示胶囊（白底 / 红字红图标 / 胶囊圆角，自适应内容宽度）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(MingCuteIcons.wifiOffLine,
                        size: 16, color: Color(0xFFFF4444)),
                    const SizedBox(width: 4),
                    Text('离线（工地信号弱，GPS仍记录）',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 20 / 12,
                            leadingDistribution: TextLeadingDistribution.even,
                            color: Color(0xFFFF4444))),
                  ],
                ),
              ),
              const Spacer(),
              // 状态胶囊（随状态变化：配色/图标/宽）
              Container(
                width: pillW,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(pillIcon, size: 16, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(pillLabel,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 20 / 12,
                            leadingDistribution: TextLeadingDistribution.even,
                            color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _StatChips(
          floorKey: plan.floor,
          distKm: _distKm,
          pointCount: _pointCount,
          duration: _durationStr,
          mode: _status == _PatrolStatus.finished
              ? '完成'
              : _status == _PatrolStatus.running
                  ? 'GPS'
                  : '待命',
        ),
        const SizedBox(height: 10),
        // 地图（占满剩余高度的显示区域：宽=屏宽，高=可用高度；图 contain 不拉伸）
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boxW = constraints.maxWidth; // 屏宽（body 全宽）
              final boxH = constraints.maxHeight; // 剩余可用高度（由 Expanded 提供）
              final planW = drawing.w, planH = drawing.h;
              final ar = planW / planH;
              // 图 contain 在 boxW×boxH 内（不拉伸、按居中留白）
              double dispW, dispH, offX, offY;
              if (boxW / ar <= boxH) {
                dispW = boxW;
                dispH = boxW / ar;
                offX = 0;
                offY = (boxH - dispH) / 2;
              } else {
                dispH = boxH;
                dispW = boxH * ar;
                offY = 0;
                offX = (boxW - dispW) / 2;
              }
              Offset toPx(p) =>
                  Offset(offX + p.dx * dispW / 100, offY + p.dy * dispH / 100);
              final pts = _planOffsets.map(toPx).toList();
              // 历史轨迹首次绘制时按当前底图尺寸像素化。
              _ensureHistoryPixelized(dispW, dispH);
              // idle 时把"当前位置"放在路径起点（与 prototype 一致）；
              // running/paused/finished 时跟随 _progress（已 ease-in-out）。
              final progressForCurrent =
                  _status == _PatrolStatus.idle ? 0.0 : _progress;
              // 沿样条按弧长插值 → 像素坐标（先做 0~100 空间的样条插值，再缩放到底图）。
              final samples = _getPlanSamples(); // 0~100 空间的样条采样
              final samplesPx = samples.map(toPx).toList();
              final curPx = pointAtProgress(samplesPx, progressForCurrent);
              return Center(
                // P0：InteractiveViewer 支持双指捏合/滚轮放大 12× 与单指/鼠标拖动平移。
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 1.0,
                  maxScale: 12.0,
                  boundaryMargin: EdgeInsets.zero,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: boxW,
                    height: boxH,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DrawingImage(
                          drawing.src,
                          fit: BoxFit.contain,
                        ),
                        CustomPaint(
                          painter: PatrolOverlayPainter(
                            pts: pts,
                            cpIdxs: plan.checkpointIdxs,
                            progress: _progress,
                            currentPos: curPx,
                            pulse: _pulse,
                            crossingSegs: _crossingSegs,
                            historyTracks: _historyTracks,
                            historyColors: _historyColors,
                            checkedInIdxs: _checkedInIdxs,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // 任务2：到达打卡栏（运行/暂停中且路线含检查点时显示）
        if ((_status == _PatrolStatus.running ||
                _status == _PatrolStatus.paused) &&
            _checkpointTotal > 0)
          _CheckInBar(
            done: _checkedInIdxs.length,
            total: _checkpointTotal,
            onCheckIn: _checkInHere,
          ),
        // 控制面板
        _PatrolPanel(
          status: _status,
          onStart: _start,
          onPause: _pause,
          onResume: _resume,
          onFinish: _finish,
          onRestart: _restart,
          onHistory: _showHistory,
          onMark: () => _markIssue(drawing),
        ),
      ],
    );
  }
}

/// 空态：当前项目没有巡场路线（提示后续跳路线编辑页）。
class _EmptyPlanView extends StatelessWidget {
  const _EmptyPlanView();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(MingCuteIcons.mapLine,
                size: 48, color: AppTokens.patrolMuted),
            const SizedBox(height: 12),
            const Text('请先创建巡场路线',
                style: TextStyle(
                    color: AppTokens.patrolFg,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('路线编辑入口将在后续版本开放',
                style: TextStyle(
                    color: AppTokens.patrolMuted, fontSize: 12)),
            const SizedBox(height: 16),
            AppButton(
              size: AppButtonSize.md,
              label: '知道了',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
}

class _BlinkDot extends StatefulWidget {
  final bool active;
  const _BlinkDot({this.active = false});

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
          decoration: BoxDecoration(
            color: widget.active ? AppTokens.danger : AppTokens.patrolMuted,
            shape: BoxShape.circle,
          ),
        ),
      );
}

class _StatChips extends StatelessWidget {
  final String floorKey;
  final double distKm;
  final int pointCount;
  final String duration;
  final String mode;
  const _StatChips({
    required this.floorKey,
    required this.distKm,
    required this.pointCount,
    required this.duration,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(child: _Chip(label: '楼层', value: floorKey)),
              Expanded(child: _Chip(label: '里程', value: '${distKm.toStringAsFixed(2)} km')),
              Expanded(child: _Chip(label: '点数', value: '$pointCount')),
              Expanded(child: _Chip(label: '时长', value: duration)),
              Expanded(child: _Chip(label: '模式', value: mode)),
            ],
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  const _Chip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.patrolFg)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF60656B))),
        ],
      );
}

/// 任务2：到达打卡栏（巡场运行/暂停时显示实时达成率 + 打卡按钮）。
class _CheckInBar extends StatelessWidget {
  final int done;
  final int total;
  final VoidCallback onCheckIn;
  const _CheckInBar({
    required this.done,
    required this.total,
    required this.onCheckIn,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (done / total * 100).round();
    final allDone = total > 0 && done >= total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppTokens.patrolSurface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppTokens.patrolBorder.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(
                allDone
                    ? MingCuteIcons.checkCircleLine
                    : MingCuteIcons.mapPinLine,
                size: 18,
                color: allDone
                    ? const Color(0xFF16A34A)
                    : AppTokens.patrolFg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '到达打卡 已到 $done/$total（$pct%）',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: allDone
                        ? const Color(0xFF16A34A)
                        : AppTokens.patrolFg),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: allDone ? null : onCheckIn,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: allDone
                      ? AppTokens.patrolMuted.withValues(alpha: 0.3)
                      : const Color(0xFF0395FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  allDone ? '全部完成' : '到达打卡',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          allDone ? AppTokens.patrolMuted : Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatrolPanel extends StatelessWidget {
  final _PatrolStatus status;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final VoidCallback onRestart;
  final VoidCallback onHistory;
  final VoidCallback onMark;
  const _PatrolPanel({
    required this.status,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onRestart,
    required this.onHistory,
    required this.onMark,
  });

  @override
  Widget build(BuildContext context) {
    // 过渡动画：开始巡场←→(暂停/结束) 切换时，5 个按钮常驻，用隐式动画做位移动画：
    // 历史轨迹左移、标记问题右移、开始巡场在中央淡出、暂停/结束从中央一分为二向两侧分开。
    final started = status == _PatrolStatus.running ||
        status == _PatrolStatus.paused;

    Widget slot({
      required double idleLeft,
      required double runLeft,
      required bool visible,
      required Widget child,
    }) {
      final left = started ? runLeft : idleLeft;
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        left: left,
        top: 0,
        width: 56,
        height: 84,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            opacity: visible ? 1 : 0,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              scale: visible ? 1 : 0.6,
              child: child,
            ),
          ),
        ),
      );
    }

    final history = _RoundBtn(
      icon: MingCuteIcons.history2Line,
      fill: Colors.white,
      iconColor: const Color(0xFF202224),
      label: '历史轨迹',
      onTap: onHistory,
    );
    final mark = _RoundBtn(
      icon: MingCuteIcons.markupLine,
      fill: Colors.white,
      iconColor: const Color(0xFF202224),
      label: '标记问题',
      onTap: onMark,
    );
    final start = _RoundBtn(
      icon: status == _PatrolStatus.finished
          ? MingCuteIcons.refresh2Line
          : MingCuteIcons.playFill,
      fill: status == _PatrolStatus.finished
          ? const Color(0xFFFF9500)
          : const Color(0xFF0395FF),
      iconColor: Colors.white,
      label: status == _PatrolStatus.finished ? '重新巡场' : '开始巡场',
      onTap: status == _PatrolStatus.finished ? onRestart : onStart,
    );
    final pause = _RoundBtn(
      icon: status == _PatrolStatus.running
          ? MingCuteIcons.pauseFill
          : MingCuteIcons.playFill,
      fill: const Color(0xFF00B84A),
      iconColor: Colors.white,
      label: status == _PatrolStatus.running ? '暂停' : '继续',
      onTap: status == _PatrolStatus.running ? onPause : onResume,
    );
    final end = _RoundBtn(
      icon: MingCuteIcons.stopFill,
      fill: const Color(0xFFFF4444),
      iconColor: Colors.white,
      label: '结束',
      onTap: onFinish,
    );

    return Center(
      child: Container(
        width: 366,
        color: const Color(0xFFF4F6F7),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: 84,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 历史轨迹：idle 居中偏左(39) → running 最左(0)
              slot(idleLeft: 39, runLeft: 0, visible: true, child: history),
              // 开始 / 重新巡场：常驻中央(155)，切换时淡出缩小
              slot(idleLeft: 155, runLeft: 155, visible: !started, child: start),
              // 暂停 / 继续：从中央(155)向左分开到(103.3)
              slot(idleLeft: 155, runLeft: 103.3, visible: started, child: pause),
              // 结束：从中央(155)向右分开到(206.7)
              slot(idleLeft: 155, runLeft: 206.7, visible: started, child: end),
              // 标记问题：idle 居中偏右(271) → running 最右(310)
              slot(idleLeft: 271, runLeft: 310, visible: true, child: mark),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆形图标操作按钮（对齐 Frame 2147228045）：56×56 圆 + 下方 12px 辅文标签。
class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color fill;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  const _RoundBtn({
    required this.icon,
    required this.fill,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 56,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 24, color: iconColor),
              ),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 20 / 12,
                    leadingDistribution: TextLeadingDistribution.even,
                    color: Color(0xFF60656B),
                  )),
            ],
          ),
        ),
      );
}

/// 历史轨迹底部弹窗：列出已加载的历史巡场记录。
/// 默认**全部不勾选**——勾选状态才会叠加到底图，未勾选时底图保持干净。
/// 关闭弹窗时若已无勾选，自动清空底图叠加（已由父级回调处理）。
class _HistorySheet extends StatefulWidget {
  final List<PatrolRecord> records;
  final Set<int> initiallyVisible;
  final ValueChanged<Set<int>> onChanged;
  const _HistorySheet({
    required this.records,
    required this.initiallyVisible,
    required this.onChanged,
  });

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  /// 用户主动勾选的集合；初始为空（默认底图干净）。
  late Set<int> _visible = {...widget.initiallyVisible};

  void _toggle(int i, bool v) {
    setState(() {
      if (v) {
        _visible.add(i);
      } else {
        _visible.remove(i);
      }
      widget.onChanged(_visible);
    });
  }

  void _selectAll(bool v) {
    setState(() {
      _visible = v ? {for (var i = 0; i < widget.records.length; i++) i} : {};
      widget.onChanged(_visible);
    });
  }

  // 与父级 painter 同一调色板：紫→粉→橙（时间倒序）。
  static const _palette = <Color>[
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
  ];

  Color _colorFor(int idx, int total) {
    if (total <= 1) return _palette.first;
    final ci = (idx * (_palette.length - 1) / (total - 1)).round();
    return _palette[ci.clamp(0, _palette.length - 1)];
  }

  String _formatTime(int ms) {
    if (ms == 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _durationStr(int startedAt, int finishedAt) {
    if (startedAt == 0 || finishedAt == 0) return '未完成';
    final s = ((finishedAt - startedAt) / 1000).round();
    final m = s ~/ 60, ss = s % 60;
    return '$m分${ss}秒';
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.records.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶栏：标题 + 计数 + 全选 + 关闭
            Row(
              children: [
                const Text('历史巡场轨迹',
                    style: TextStyle(
                        color: AppTokens.patrolFg,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTokens.patrolSurface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                      '已加载 $n 条${_visible.isNotEmpty ? ' · 已选 ${_visible.length}' : ''}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTokens.patrolMuted)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      _selectAll(_visible.length < n),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppTokens.patrolFg,
                  ),
                  child: Text(
                    _visible.length < n ? '全选' : '全不选',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(MingCuteIcons.closeLine,
                      size: 18, color: AppTokens.patrolMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('勾选后叠加到底图（默认不显示，保持底图干净）',
                style: TextStyle(
                    color: AppTokens.patrolMuted, fontSize: 12)),
            const SizedBox(height: 12),
            // 列表
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: n,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final r = widget.records[i];
                  final checked = _visible.contains(i);
                  final c = _colorFor(i, n);
                  return InkWell(
                    onTap: () => _toggle(i, !checked),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTokens.patrolSurface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: checked
                                ? c.withValues(alpha: 0.7)
                                : AppTokens.patrolBorder
                                    .withValues(alpha: 0.4),
                            width: checked ? 1.4 : 1),
                      ),
                      child: Row(
                        children: [
                          // 自绘 checkbox + 色块
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: checked
                                  ? c
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: checked
                                      ? c
                                      : AppTokens.patrolBorder,
                                  width: 1.2),
                            ),
                            alignment: Alignment.center,
                            child: checked
                                ? const Icon(
                                    MingCuteIcons.checkLine,
                                    size: 12,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          // 色相色带
                          Container(
                            width: 4,
                            height: 36,
                            decoration: BoxDecoration(
                              color: c,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(r.name,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color:
                                                  AppTokens.patrolFg,
                                              fontSize: 14,
                                              fontWeight:
                                                  FontWeight.w600)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                        _durationStr(r.startedAt,
                                            r.finishedAt),
                                        style: const TextStyle(
                                            color: AppTokens.patrolMuted,
                                            fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    _MetricChip(
                                        label: '里程',
                                        value:
                                            '${r.distKm.toStringAsFixed(2)} km'),
                                    const SizedBox(width: 8),
                                    _MetricChip(
                                        label: '点数',
                                        value: '${r.pointCount}'),
                                    const SizedBox(width: 8),
                                    _MetricChip(
                                        label: '问题',
                                        value: '${r.issueCount}',
                                        highlight: r.issueCount > 0),
                                    if (r.checkpointTotal > 0) ...[
                                      const SizedBox(width: 8),
                                      _MetricChip(
                                          label: '打卡',
                                          value:
                                              '${r.checkins.length}/${r.checkpointTotal}',
                                          highlight: r.checkins.length >=
                                              r.checkpointTotal),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                    '开始 ${_formatTime(r.startedAt)}'
                                    '${r.finishedAt > 0 ? '  ·  结束 ${_formatTime(r.finishedAt)}' : ''}',
                                    style: const TextStyle(
                                        color: AppTokens.patrolMuted,
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _MetricChip(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFFEF4444).withValues(alpha: 0.15)
              : AppTokens.patrolSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label ',
                style: const TextStyle(
                    color: AppTokens.patrolMuted, fontSize: 11)),
            Text(value,
                style: TextStyle(
                    color: highlight
                        ? const Color(0xFFEF4444)
                        : AppTokens.patrolFg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
