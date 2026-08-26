import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../core/cad/wall_lines.dart';
import '../../data/models.dart';
import '../../utils/geo.dart';
import '../../utils/path_metrics.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_snack.dart';

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

  // 历史巡场轨迹（已按底图缩放的绝对坐标序列），用于底图叠加显示。
  List<List<Offset>> _historyTracks = const [];
  List<Color> _historyColors = const [];

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
  void _ensureHistoryPixelized(double pw, double ph) {
    if (_historyPxCached &&
        _historyPxW == pw &&
        _historyPxH == ph &&
        _historyTracks.length == _historyRecords.length) {
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
    final n = _historyRecords.length;
    for (var i = 0; i < n; i++) {
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
        // n=3 时 [紫,粉,橙]（旧→新）；i=0 最旧 → 紫
        final ci = n <= 1 ? 0 : (i * (palette.length - 1) ~/ (n - 1));
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
    _showSummary();
  }

  void _restart() {
    setState(() {
      _status = _PatrolStatus.idle;
      _progress = 0;
      _elapsed = Duration.zero;
      _pausedTotal = Duration.zero;
      _startedAt = null;
    });
    AppSnack.show(context, '已重置巡场轨迹', kind: AppSnackKind.muted);
  }

  void _showSummary() {
    AppSnack.show(
      context,
      '巡场完成：${_distKm.toStringAsFixed(2)} km · $_pointCount 点 · $_durationStr',
      kind: AppSnackKind.success,
    );
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
      builder: (ctx) => _HistorySheet(
        records: _historyRecords,
        historyColors: _historyColors,
        historyTracks: _historyTracks,
      ),
    );
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
        title: const Text('巡场',
            style: TextStyle(
                color: AppTokens.patrolFg,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        actions: [
          if (_plan != null)
            IconButton(
              tooltip: '复位',
              icon: const Icon(MingCuteIcons.fullscreenLine,
                  size: 20, color: AppTokens.patrolFg),
              onPressed: _resetView,
            ),
          if (_plan != null)
            IconButton(
              tooltip: '编辑路线',
              icon: const Icon(MingCuteIcons.editLine,
                  size: 20, color: AppTokens.patrolFg),
              onPressed: () => context.push(
                '/patrol-editor',
                extra: PatrolArgs(planId: _plan!.id),
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
    return Column(
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
                    Icon(MingCuteIcons.wifiOffLine,
                        size: 12, color: AppTokens.patrolMuted),
                    SizedBox(width: 5),
                    Text('离线 · 工地信号弱（GPS 仍记录）',
                        style: TextStyle(
                            fontSize: 12, color: AppTokens.patrolMuted)),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  // 标签浅底 = 原色 5% 透明度（深色沉浸主题下呈暗红微底）
                  color: AppTokens.dangerTint,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _BlinkDot(active: true),
                    const SizedBox(width: 5),
                    Text(_status == _PatrolStatus.running ? '记录中' : '待机',
                        style: TextStyle(
                            fontSize: 12,
                            color: _status == _PatrolStatus.running
                                ? AppTokens.danger
                                : AppTokens.patrolMuted,
                            fontWeight: FontWeight.w400)),
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
        // 地图
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final planW = drawing.w, planH = drawing.h;
              final ar = planW / planH;
              var pw = constraints.maxWidth;
              var ph = pw / ar;
              if (ph > constraints.maxHeight) {
                ph = constraints.maxHeight;
                pw = ph * ar;
              }
              final pts = _planOffsets
                  .map((p) => Offset(p.dx * pw / 100, p.dy * ph / 100))
                  .toList();
              // 历史轨迹首次绘制时按当前底图尺寸像素化。
              _ensureHistoryPixelized(pw, ph);
              // idle 时把"当前位置"放在路径起点（与 prototype 一致）；
              // running/paused/finished 时跟随 _progress（已 ease-in-out）。
              final progressForCurrent =
                  _status == _PatrolStatus.idle ? 0.0 : _progress;
              // 沿样条按弧长插值 → 像素坐标（先做 0~100 空间的样条插值，再缩放到底图）。
              final samples = _getPlanSamples(); // 0~100 空间的样条采样
              final samplesPx = samples
                  .map((p) => Offset(p.dx * pw / 100, p.dy * ph / 100))
                  .toList();
              final curPx = pointAtProgress(samplesPx, progressForCurrent);
              return Center(
                // P0：InteractiveViewer 支持双指捏合/滚轮放大 12× 与单指/鼠标拖动平移。
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 1.0,
                  maxScale: 12.0,
                  boundaryMargin: const EdgeInsets.all(160),
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: pw,
                    height: ph,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          drawing.src,
                          fit: BoxFit.fill,
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Chip(label: '楼层', value: floorKey),
            _Chip(label: '里程', value: '${distKm.toStringAsFixed(2)} km'),
            _Chip(label: '点数', value: '$pointCount'),
            _Chip(label: '时长', value: duration),
            _Chip(label: '模式', value: mode),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.patrolFg)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppTokens.patrolMuted)),
        ],
      );
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
    final isRunning = status == _PatrolStatus.running;
    final isPaused = status == _PatrolStatus.paused;
    final isFinished = status == _PatrolStatus.finished;
    final (String label, VoidCallback action) = switch (status) {
      _PatrolStatus.idle => ('开始巡场', onStart),
      _PatrolStatus.running => ('暂停巡场', onPause),
      _PatrolStatus.paused => ('继续巡场', onResume),
      _PatrolStatus.finished => ('重新巡场', onRestart),
    };
    return Container(
      color: AppTokens.patrolSurface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 主操作（大按钮组件：满宽 / 高 48 / 纯文字不带图标；巡场深色底上品牌蓝）
          AppButton(
            size: AppButtonSize.lg,
            width: double.infinity,
            label: label,
            onPressed: action,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SubBtn(
                  icon: MingCuteIcons.squareLine,
                  label: isFinished ? '已结束' : '结束巡场',
                  enabled: isRunning || isPaused,
                  onTap: onFinish,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SubBtn(
                  icon: MingCuteIcons.historyLine,
                  label: '历史轨迹',
                  onTap: onHistory,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SubBtn(
                  icon: MingCuteIcons.mapLine,
                  label: '标记问题点',
                  onTap: onMark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: enabled
                          ? AppTokens.patrolFg
                          : AppTokens.patrolMuted.withValues(alpha: 0.5))),
            ],
          ),
        ),
      );
}

/// 历史轨迹底部弹窗：列出已加载的历史巡场记录，叠加到当前底图上。
/// 图例 = 历史颜色（与底图叠加一致），点击单条记录可暂时隐藏/显示。
class _HistorySheet extends StatefulWidget {
  final List<PatrolRecord> records;
  final List<Color> historyColors;
  final List<List<Offset>> historyTracks;
  const _HistorySheet({
    required this.records,
    required this.historyColors,
    required this.historyTracks,
  });

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late Set<int> _hidden = {};

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

  Color _colorFor(int idx) {
    final n = widget.historyColors.length;
    if (n == 0) return const Color(0xFF6B7280);
    final i = idx.clamp(0, n - 1);
    return widget.historyColors[i];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶栏：标题 + 关闭
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
                  child: Text('已加载 ${widget.records.length} 条',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTokens.patrolMuted)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(MingCuteIcons.closeLine,
                      size: 18, color: AppTokens.patrolMuted),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('点击单条可暂时隐藏/显示对应历史轨迹',
                style: TextStyle(
                    color: AppTokens.patrolMuted, fontSize: 12)),
            const SizedBox(height: 12),
            // 列表
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final r = widget.records[i];
                  final hidden = _hidden.contains(i);
                  return InkWell(
                    onTap: () => setState(() {
                      if (hidden) {
                        _hidden.remove(i);
                      } else {
                        _hidden.add(i);
                      }
                    }),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTokens.patrolSurface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: hidden
                                ? AppTokens.patrolBorder.withValues(alpha: 0.3)
                                : _colorFor(i).withValues(alpha: 0.5),
                            width: hidden ? 1 : 1.2),
                      ),
                      child: Row(
                        children: [
                          // 颜色色块（也作为"显示/隐藏"的状态指示）
                          Container(
                            width: 4,
                            height: 36,
                            decoration: BoxDecoration(
                              color: hidden
                                  ? AppTokens.patrolMuted
                                      .withValues(alpha: 0.4)
                                  : _colorFor(i),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(r.name,
                                        style: TextStyle(
                                            color: hidden
                                                ? AppTokens.patrolMuted
                                                : AppTokens.patrolFg,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    Text(
                                        _durationStr(
                                            r.startedAt, r.finishedAt),
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
                          const SizedBox(width: 6),
                          Icon(
                            hidden
                                ? MingCuteIcons.circleDashLine
                                : MingCuteIcons.eyeLine,
                            size: 16,
                            color: hidden
                                ? AppTokens.patrolMuted
                                : _colorFor(i),
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
