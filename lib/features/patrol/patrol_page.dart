import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../utils/path_metrics.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_snack.dart';

/// 巡场状态机。
enum _PatrolStatus { idle, running, paused, finished }

/// 巡场页：深色沉浸 + Ticker 轨迹动画（对齐 HTML startPatrol/tickPatrol/finishPatrol）。
/// 底图：西楼一层平面图（nkf_west_1f.png）。
class PatrolPage extends StatefulWidget {
  const PatrolPage({super.key});

  @override
  State<PatrolPage> createState() => _PatrolPageState();
}

class _PatrolPageState extends State<PatrolPage>
    with SingleTickerProviderStateMixin {
  static const int _totalMs = 16000; // 全程 16s（对齐 HTML dt/16）
  static const double _totalKm = 0.52; // 模拟里程
  static const int _totalPts = 48; // 模拟点数

  late final Ticker _ticker;
  _PatrolStatus _status = _PatrolStatus.idle;
  double _progress = 0;
  Duration _elapsed = Duration.zero;
  Duration _pausedTotal = Duration.zero;
  DateTime? _startedAt;
  DateTime? _pausedAt;
  double _pulse = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
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
    setState(() {
      _elapsed = elapsed;
      _progress = (elapsed.inMilliseconds / _totalMs).clamp(0.0, 1.0);
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
  double get _distKm => _progress * _totalKm;
  int get _pointCount => (_progress * _totalPts).round();
  String get _durationStr {
    final s = _elapsed.inSeconds.clamp(0, 3599);
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  /// 当前位置（相对坐标 0~1，供标记问题点使用）。
  Offset _currentRel() {
    final raw = pointAtProgress(patrolPathPoints, _progress);
    return Offset(raw.dx / 100, raw.dy / 100);
  }

  void _markIssue() {
    final rel = _currentRel();
    context.push(
      '/capture',
      extra: CaptureArgs(
        floor: '西楼1F',
        anchorLabel: '巡场中·当前位置',
        x: rel.dx,
        y: rel.dy,
      ),
    );
  }

  void _showHistory() {
    AppSnack.show(context, '已加载 3 条历史巡场轨迹', kind: AppSnackKind.muted);
  }

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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTokens.patrolSurface2,
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(MingCuteIcons.wifiOffLine,
                            size: 12, color: AppTokens.patrolMuted),
                        SizedBox(width: 5),
                        Text('离线 · 工地信号弱（GPS 仍记录）',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTokens.patrolMuted)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      // 标签浅底 = 原色 5% 透明度（深色沉浸主题下呈暗红微底）
                      color: AppTokens.dangerTint,
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusPill),
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
                  // idle 时把"当前位置"放在路径起点（与 prototype 一致）；
                  // running/paused/finished 时跟随 _progress。
                  final progressForCurrent =
                      _status == _PatrolStatus.idle ? 0.0 : _progress;
                  final cur = pointAtProgress(patrolPathPoints, progressForCurrent);
                  final curPx =
                      Offset(cur.dx * pw / 100, cur.dy * ph / 100);
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
                              progress: _progress,
                              currentPos: curPx,
                              pulse: _pulse,
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
            _PatrolPanel(
              status: _status,
              onStart: _start,
              onPause: _pause,
              onResume: _resume,
              onFinish: _finish,
              onRestart: _restart,
              onHistory: _showHistory,
              onMark: _markIssue,
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
  final double distKm;
  final int pointCount;
  final String duration;
  final String mode;
  const _StatChips({
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
            const _Chip(label: '楼层', value: '西楼 1F'),
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
