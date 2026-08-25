import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/cad/wall_lines.dart';
import '../../core/storage/patrol_plan_store.dart';
import '../../core/utils/cad_coord.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_snack.dart';
import '../../utils/geo.dart';
import '../../utils/path_metrics.dart';

/// 巡场路线编辑器：在图纸底图上自由规划巡场路线。
///
/// 交互规格（照 PATROL_OPTIMIZE.md 阶段二「④ 路线编辑模式」）：
///  - 单击图纸空白处 → 追加一个路点（显示 0~100 相对坐标）
///  - 拖动已有点 → 移动（onPanUpdate，拖后保存新坐标）
///  - 长按点 → 删除该点
///  - 双击点 → 切换检查点标记（蓝实心 = 检查点，空心 = 普通点）
///  - 撤销 → 移除最后一个点；清空 → 清空全部
///  - 保存 → 校验 points≥2 → 写入 PatrolPlanStore
///
/// 坐标换算复用量尺页（measure_page.dart `_onDrawTap`）的 BoxFit.contain 反算：
/// 显示坐标 → 整图坐标 → `/w*100` 相对坐标；绘制时反向映射。
class PatrolEditorPage extends ConsumerStatefulWidget {
  final PatrolArgs args;
  const PatrolEditorPage({super.key, required this.args});

  @override
  ConsumerState<PatrolEditorPage> createState() => _PatrolEditorPageState();
}

class _PatrolEditorPageState extends ConsumerState<PatrolEditorPage> {
  /// 当前项目（保存时落库用）。
  String _projectId = '';
  /// 当前图纸 key / 楼层（路由参数或种子预填）。
  String _drawingKey = '';
  String _floor = '';

  // 编辑中的路线点（PatrolPoint 可空 totalKm 由保存时计算）。
  final List<PatrolPoint> _points = [];
  // 记录已撤销历史（每次修改 push 快照，撤销弹出一个）。
  final List<List<PatrolPoint>> _undoStack = [];

  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _floorCtl = TextEditingController();

  // 拖动中的点下标（null = 未在拖动）。
  int? _draggingIdx;

  // 选中中的路点下标（null = 无选中）；用于"删点"按钮精确删除某一点。
  int? _selectedIdx;

  // P0：缩放/平移控制器（编辑器内同样可放大到房间级布点）。
  final TransformationController _transformController =
      TransformationController();

  // P1：墙线相对坐标缓存（null = 未校准/加载失败 → 不做穿墙检测，仅顶部提示）。
  List<List<double>>? _wallLinesRel;
  bool _wallLinesAttempted = false; // 已尝试加载，避免每次 build 重复拉
  /// 当前图纸是否已校准（与 _wallLinesRel==null 配合区分"未校准"/"墙线缺失"）。
  bool _calibrationOk = false;

  /// 穿墙段下标（i 对应路线段 _points[i]→_points[i+1]）。
  Set<int> get _crossingSegs {
    final walls = _wallLinesRel;
    if (walls == null || walls.isEmpty) return const {};
    final rel = [
      for (final p in _points) [p.dx, p.dy],
    ];
    return crossingSegments(rel, walls);
  }

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _floorCtl.dispose();
    _transformController.dispose();
    super.dispose();
  }

  /// P0：视图复位（编辑器内同 _transformController）。
  void _resetView() {
    _transformController.value = Matrix4.identity();
    AppSnack.show(context, '视图已复位', kind: AppSnackKind.muted);
  }

  /// 解析项目 / 图纸 / 计划：route extra 传 PatrolArgs(planId) 编辑已有计划。
  Future<void> _loadContext() async {
    try {
      final project = await ref.read(projectProvider.future);
      final plans = await ref.read(patrolPlansProvider(project.id).future);
      _projectId = project.id;

      // 优先按 planId 预填已有计划；否则用该项目第一条作预填上下文。
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

      if (!mounted) return;
      setState(() {
        _drawingKey = plan?.drawingKey ?? '';
        _floor = plan?.floor ?? '';
        _points.addAll(plan?.points ?? []);
        _nameCtl.text = plan?.name ?? '巡场路线';
        _floorCtl.text = _floor;
      });
      // P1：异步加载墙线（仅校准时有效）；失败置 null 走顶部降级提示。
      await _loadWallLines();
    } catch (_) {
      if (mounted) {
        AppSnack.show(context, '加载计划失败', kind: AppSnackKind.danger);
      }
    }
  }

  /// 加载当前图纸墙线（相对坐标 0-100）；未校准或加载失败 → null。
  /// 用 setState 触发重绘与穿墙段重算（_crossingSegs getter 依赖 _points / _wallLinesRel）。
  Future<void> _loadWallLines() async {
    if (_wallLinesAttempted) return;
    _wallLinesAttempted = true;
    if (_drawingKey.isEmpty) return;
    try {
      final mapper = await loadCadCalibration(ref, _drawingKey);
      final walls = await loadWallLinesRel(_drawingKey, mapper);
      if (!mounted) return;
      setState(() {
        _wallLinesRel = walls;
        _calibrationOk = mapper != null;
      });
    } catch (_) {
      // 静默：null 即降级（顶部"该图纸未校准，无法检测穿墙"）。
    }
  }

  /// 推入撤销快照（修改前调用）。
  void _pushUndo() {
    _undoStack.add(List.of(_points));
    // 控制栈长，防内存膨胀。
    if (_undoStack.length > 100) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) {
      AppSnack.show(context, '没有可撤销的操作', kind: AppSnackKind.muted);
      return;
    }
    setState(() {
      _points
        ..clear()
        ..addAll(_undoStack.removeLast());
    });
  }

  void _clearAll() {
    _pushUndo();
    setState(() {
      _points.clear();
      _selectedIdx = null;
    });
    AppSnack.show(context, '已清空全部路点', kind: AppSnackKind.muted);
  }

  /// 显式"+ 点位"按钮：在图纸视觉中心追加一个相对坐标 50/50 的点。
  /// 适合路线跨图、用户缩放后想在大致中央再补充一个点的场景。
  void _appendAtCenter(Drawing drawing) {
    _pushUndo();
    setState(() => _points.add(const PatrolPoint(dx: 50, dy: 50)));
  }

  /// 显式"删点"按钮：优先删除【选中的点】，无选中则删最后一个点。
  void _popLastPoint() {
    if (_points.isEmpty) return;
    _pushUndo();
    final idx = _selectedIdx ?? _points.length - 1;
    setState(() {
      if (idx < _points.length) {
        _points.removeAt(idx);
      }
      _selectedIdx = null;
    });
    AppSnack.show(context, '已删除第 ${idx + 1} 个点', kind: AppSnackKind.muted);
  }

  // —— 坐标换算（复用 measure_page 的 contain 反算） ——

  /// BoxFit.contain 下底图实际渲染尺寸。
  Size _containSize(Size box, Drawing drawing) {
    final r = drawing.w / drawing.h;
    double w = box.width, h = box.width / r;
    if (h > box.height) {
      h = box.height;
      w = box.height * r;
    }
    return Size(w, h);
  }

  /// GestureDetector 给的 localPosition 是 viewport 坐标；用
  /// InteractiveViewer 的 `toScene` 反算到 child 坐标（已应用缩放/平移）。
  Offset _viewportToLocal(Offset viewport) =>
      _transformController.toScene(viewport);

  /// child 坐标（Image 局部，即原来的"显示坐标"）→ 相对坐标 0~100。
  Offset _displayToRel(Offset local, Size box, Drawing drawing) {
    final contain = _containSize(box, drawing);
    final offX = (box.width - contain.width) / 2;
    final offY = (box.height - contain.height) / 2;
    final px = (local.dx - offX) / contain.width * drawing.w;
    final py = (local.dy - offY) / contain.height * drawing.h;
    return Offset(
      (px / drawing.w * 100).clamp(0.0, 100.0),
      (py / drawing.h * 100).clamp(0.0, 100.0),
    );
  }

  /// 相对坐标 0~100 → 显示坐标（供绘制覆盖层）。
  Offset _relToDisplay(Offset rel, Size box, Drawing drawing) {
    final contain = _containSize(box, drawing);
    final offX = (box.width - contain.width) / 2;
    final offY = (box.height - contain.height) / 2;
    final px = rel.dx / 100 * contain.width + offX;
    final py = rel.dy / 100 * contain.height + offY;
    return Offset(px, py);
  }

  /// 命中检测：某显示坐标是否落在已有点上（半径阈值，便于拖动/删除/双击）。
  int? _hitIndex(Offset display, Size box, Drawing drawing) {
    for (var i = 0; i < _points.length; i++) {
      final p = _relToDisplay(
          Offset(_points[i].dx, _points[i].dy), box, drawing);
      if ((p - display).distance <= 22) return i;
    }
    return null;
  }

  // —— 手势 ——

  void _onTapUp(Offset local, Size box, Drawing drawing) {
    if (_draggingIdx != null) {
      _draggingIdx = null;
      return; // 刚拖完，忽略本次 tap 的追加
    }
    final hit = _hitIndex(local, box, drawing);
    if (hit != null) {
      // 单击已有点 → 选中该点（便于用"删点"按钮精确删除 / 高亮提示）。
      _pushUndo();
      setState(() => _selectedIdx = hit);
      AppSnack.show(context, '已选中第 ${hit + 1} 个点，可点「删点」删除', kind: AppSnackKind.muted);
      return;
    }
    _pushUndo();
    final rel = _displayToRel(local, box, drawing);
    setState(() {
      _selectedIdx = null; // 空白处点击 = 取消选中 + 追加新点
      _points.add(PatrolPoint(dx: rel.dx, dy: rel.dy));
    });
  }

  void _onDoubleTap(Offset local, Size box, Drawing drawing) {
    final hit = _hitIndex(local, box, drawing);
    if (hit == null) return;
    _pushUndo();
    setState(() {
      final p = _points[hit];
      _points[hit] = PatrolPoint(
        dx: p.dx,
        dy: p.dy,
        isCheckpoint: !p.isCheckpoint,
      );
      _selectedIdx = null;
    });
  }

  void _onLongPress(Offset local, Size box, Drawing drawing) {
    final hit = _hitIndex(local, box, drawing);
    if (hit == null) return;
    _pushUndo();
    setState(() {
      _points.removeAt(hit);
      _selectedIdx = null;
    });
    AppSnack.show(context, '已删除第 ${hit + 1} 个路点', kind: AppSnackKind.muted);
  }

  void _onPanDown(Offset local, Size box, Drawing drawing) {
    final hit = _hitIndex(local, box, drawing);
    if (hit != null) {
      // 拖动手势优先于选中：拖动时取消当前选中。
      setState(() => _selectedIdx = null);
    }
    _draggingIdx = hit;
  }

  void _onPanUpdate(Offset local, Size box, Drawing drawing) {
    final idx = _draggingIdx;
    if (idx == null) return;
    final rel = _displayToRel(local, box, drawing);
    setState(() {
      final p = _points[idx];
      _points[idx] = PatrolPoint(
        dx: rel.dx,
        dy: rel.dy,
        isCheckpoint: p.isCheckpoint,
      );
    });
  }

  void _onPanEnd() {
    if (_draggingIdx != null) {
      // 拖动结束：把拖动前状态入栈（作为一次可撤销操作）。
      _pushUndo();
      _draggingIdx = null;
    }
  }

  // —— 保存 ——

  Future<void> _save() async {
    if (_points.length < 2) {
      AppSnack.show(context, '路线至少需要 2 个点', kind: AppSnackKind.danger);
      return;
    }
    // P1：存在穿墙段 → 弹确认（允许保存：墙线数据可能含门窗洞口等误差）。
    if (_crossingSegs.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('路线存在穿墙段'),
          content: Text(
              '当前路线有 ${_crossingSegs.length} 段穿墙（红色高亮）。\n可能是门窗洞口或墙线数据误差，仍要保存吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('仍要保存')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final drawing = ref.read(drawingsProvider).valueOrNull?[_drawingKey];
    if (drawing == null) {
      AppSnack.show(context, '图纸未找到，无法保存', kind: AppSnackKind.danger);
      return;
    }
    if (_projectId.isEmpty) {
      AppSnack.show(context, '项目未就绪，请重试', kind: AppSnackKind.danger);
      return;
    }
    final name = _nameCtl.text.trim().isEmpty ? '巡场路线' : _nameCtl.text.trim();
    final floor = _floorCtl.text.trim().isEmpty ? _floor : _floorCtl.text.trim();

    // 已校准图纸：按 CAD 坐标算真实里程；未校准：让 totalKm 为 null，巡场页走估算。
    final mapper = await loadCadCalibration(ref, _drawingKey);
    double? totalKm;
    if (mapper != null) {
      totalKm = _calcRouteKm(mapper, drawing);
    }

    final plan = PatrolPlan(
      id: widget.args.planId ??
          'plan_${DateTime.now().millisecondsSinceEpoch}',
      projectId: _projectId,
      drawingKey: _drawingKey,
      name: name,
      floor: floor,
      points: List.of(_points),
      totalKm: totalKm,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    // 覆盖写当前项目全部路线（编辑已有计划时替换同 id）。
    final existing = await PatrolPlanStore.list(_projectId);
    final next = [...existing.where((p) => p.id != plan.id), plan];
    await PatrolPlanStore.save(_projectId, next);
    if (!mounted) return;
    AppSnack.show(context, '路线已保存', kind: AppSnackKind.success);
    context.pop();
  }

  /// 复用 path_metrics.realRouteKm 的路线里程计算。
  double? _calcRouteKm(CadCoordMapper mapper, Drawing drawing) =>
      realRouteKm(_points, mapper, drawing.w, drawing.h);

  @override
  Widget build(BuildContext context) {
    final drawingsAsync = ref.watch(drawingsProvider);
    final drawing = drawingsAsync.valueOrNull?[_drawingKey];
    final canSave = _points.length >= 2;
    return Scaffold(
      backgroundColor: AppTokens.patrolBg,
      appBar: AppBar(
        backgroundColor: AppTokens.patrolBg,
        foregroundColor: AppTokens.patrolFg,
        elevation: 0,
        title: const Text('路线编辑',
            style: TextStyle(
                color: AppTokens.patrolFg,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: '复位',
            icon: const Icon(MingCuteIcons.fullscreenLine,
                size: 20, color: AppTokens.patrolFg),
            onPressed: _resetView,
          ),
          TextButton(
            onPressed: _save,
            child: Text(canSave ? '保存' : '保存（≥2点）',
                style: TextStyle(
                    color: canSave ? AppTokens.patrolFg : AppTokens.patrolMuted,
                    fontSize: 14)),
          ),
        ],
      ),
      body: drawing == null
          ? const Center(
              child: Text('图纸加载中…',
                  style: TextStyle(color: AppTokens.patrolMuted)))
          : Column(
              children: [
                // 名称 / 楼层表单
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _editField('路线名称', _nameCtl),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _editField('楼层', _floorCtl),
                      ),
                    ],
                  ),
                ),
                // 提示条 + 显式按钮
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(MingCuteIcons.mapLine,
                          size: 12, color: AppTokens.patrolMuted),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '单击/➕ 加点 · 拖动移动 · 长按删除 · 双击切检查点（蓝实心）· 当前 ${_points.length} 点',
                          style: const TextStyle(
                              fontSize: 11, color: AppTokens.patrolMuted),
                        ),
                      ),
                      // 显式"+ 点位"按钮：在图纸中心追加一个临时点
                      _miniBtn(
                        icon: MingCuteIcons.addLine,
                        label: '加点',
                        onTap: () => _appendAtCenter(drawing),
                      ),
                      const SizedBox(width: 6),
                      // 显式"删除最后一点"按钮
                      _miniBtn(
                        icon: MingCuteIcons.deleteLine,
                        label: '删点',
                        enabled: _points.isNotEmpty,
                        onTap: _popLastPoint,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // P1：穿墙警告横幅；未校准 / 无墙线时显示降级提示。
                _WarningBanner(
                  wallLines: _wallLinesRel,
                  crossingCount: _crossingSegs.length,
                  attempted: _wallLinesAttempted,
                  calibrationOk: _calibrationOk,
                ),
                // 图纸画布
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final box = constraints.biggest;
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (e) =>
                                _onTapUp(_viewportToLocal(e.localPosition), box, drawing),
                            onDoubleTap: () {},
                            onDoubleTapDown: (e) => _onDoubleTap(
                                _viewportToLocal(e.localPosition), box, drawing),
                            onLongPressStart: (e) =>
                                _onLongPress(_viewportToLocal(e.localPosition), box, drawing),
                            onPanDown: (e) =>
                                _onPanDown(_viewportToLocal(e.localPosition), box, drawing),
                            onPanUpdate: (e) =>
                                _onPanUpdate(_viewportToLocal(e.localPosition), box, drawing),
                            onPanEnd: (_) => _onPanEnd(),
                            onPanCancel: _onPanEnd,
                            child: InteractiveViewer(
                              transformationController: _transformController,
                              minScale: 1.0,
                              maxScale: 12.0,
                              boundaryMargin: const EdgeInsets.all(160),
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: box.width,
                                height: box.height,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Image.asset(
                                        drawing.src,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    // 覆盖层：折线 + 点 + 序号
                                    CustomPaint(
                                      size: Size.infinite,
                                      painter: _RouteEditorPainter(
                                        points: [
                                          for (final p in _points)
                                            _relToDisplay(
                                                Offset(p.dx, p.dy), box, drawing),
                                    ],
                                    checkpoints: [
                                      for (var i = 0;
                                          i < _points.length;
                                          i++)
                                        if (_points[i].isCheckpoint) i
                                    ],
                                    crossingSegs: _crossingSegs,
                                    selectedIdx: _selectedIdx,
                                  ),
                                ),
                              ],
                              ),
                            ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // 操作按钮：撤销 / 清空
                Container(
                  color: AppTokens.patrolSurface,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _editBtn(
                            icon: MingCuteIcons.historyLine,
                            label: '撤销',
                            onTap: _undo,
                            enabled: _undoStack.isNotEmpty),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _editBtn(
                            icon: MingCuteIcons.deleteLine,
                            label: '清空',
                            onTap: _clearAll,
                            enabled: _points.isNotEmpty),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _editBtn(
                            icon: MingCuteIcons.saveLine,
                            label: '保存',
                            onTap: _save,
                            enabled: canSave),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _editField(String label, TextEditingController c) => TextField(
        controller: c,
        style: const TextStyle(color: AppTokens.patrolFg, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppTokens.patrolMuted, fontSize: 12),
          isDense: true,
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: AppTokens.patrolBorder),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: AppTokens.patrolFg),
          ),
        ),
      );

  /// 路线编辑器顶部"加点/删点"等行内小按钮。
  Widget _miniBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
  }) =>
      InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTokens.patrolSurface2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: enabled
                    ? AppTokens.patrolBorder
                    : AppTokens.patrolBorder.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 13,
                  color: enabled
                      ? AppTokens.patrolFg
                      : AppTokens.patrolMuted.withValues(alpha: 0.5)),
              const SizedBox(width: 3),
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

  Widget _editBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
  }) =>
      InkWell(
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
              const SizedBox(height: 2),
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

/// P1：编辑器顶部穿墙状态横幅。
///  1. 未尝试加载 → 不显示（避免初次闪烁）
///  2. 已校准但无墙线段 → 绿色"路线无穿墙"（仅在有点时显示）
///  3. 校准成功、有穿墙段 → 红色"⚠ 有 N 段穿墙"
///  4. 未校准 → 黄色"该图纸未校准，无法检测穿墙"
///  5. 已校准但墙线资产缺失（Python 管线未跑）→ 黄色"该图纸暂无墙线数据，请运行 python server/cad_meta_build.py"
class _WarningBanner extends StatelessWidget {
  final List<List<double>>? wallLines;
  final int crossingCount;
  final bool attempted;
  final bool calibrationOk; // true=该图已校准；false=未校准
  const _WarningBanner({
    required this.wallLines,
    required this.crossingCount,
    required this.attempted,
    required this.calibrationOk,
  });

  @override
  Widget build(BuildContext context) {
    if (!attempted) return const SizedBox.shrink();
    // 状态 4/5：区分未校准与墙线缺失
    if (wallLines == null) {
      final msg = calibrationOk
          ? '该图纸暂无墙线数据，请运行 python server/cad_meta_build.py 后重试'
          : '该图纸未校准，无法检测穿墙';
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7), // amber-100
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(MingCuteIcons.alertLine,
                  size: 14, color: Color(0xFFB45309)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  msg,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFB45309)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (crossingCount == 0) {
      // 状态 2：仅在有点段时显示绿色
      return const SizedBox.shrink();
    }
    // 状态 3：红色警示
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2), // red-100
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(MingCuteIcons.alertLine,
                size: 14, color: Color(0xFFB91C1C)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '⚠ 有 $crossingCount 段路线穿墙，请沿走廊补点',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFB91C1C)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 路线编辑覆盖层：折线 + 点（检查点蓝实心 / 普通点空心）+ 序号。
/// P1：穿墙段（crossingSegs 内）画红色粗线覆盖，警示色与正常蓝色折线并存。
class _RouteEditorPainter extends CustomPainter {
  final List<Offset> points; // 显示坐标
  final List<int> checkpoints;
  final Set<int> crossingSegs; // 穿墙段下标（路线段 i 对应 points[i]→points[i+1]）
  final int? selectedIdx; // 选中点下标（橙色高亮，供"删点"精确定位）
  const _RouteEditorPainter({
    required this.points,
    required this.checkpoints,
    this.crossingSegs = const {},
    this.selectedIdx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      // 少于 2 点只画点。
      for (var i = 0; i < points.length; i++) {
        _drawPoint(canvas, points[i], checkpoints.contains(i), i);
      }
      return;
    }
    // 折线（先画正常蓝色底层，再对穿墙段叠加红色粗线）
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF3B82F6).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (crossingSegs.isNotEmpty) {
      final redPaint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final i in crossingSegs) {
        if (i + 1 >= points.length) continue;
        final seg = Path()
          ..moveTo(points[i].dx, points[i].dy)
          ..lineTo(points[i + 1].dx, points[i + 1].dy);
        canvas.drawPath(seg, redPaint);
      }
    }
    for (var i = 0; i < points.length; i++) {
      _drawPoint(canvas, points[i], checkpoints.contains(i), i);
    }
  }

  void _drawPoint(Canvas canvas, Offset p, bool isCp, int idx) {
    final isSel = idx == selectedIdx;
    final fill = isSel
        ? const Color(0xFFF97316) // 选中 → 橙色
        : (isCp ? const Color(0xFF1D4ED8) : const Color(0xFFFFFFFF));
    canvas.drawCircle(
      p,
      7,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 3.0 : 1.5,
    );
    canvas.drawCircle(p, 6.5, Paint()..color = fill);
    if (isCp) {
      canvas.drawCircle(p, 2.2, Paint()..color = const Color(0xFFFFFFFF));
    }
    // 序号标签（点位右上角小数字，1/2/3...），便于"哪一段是哪一段"
    final tp = TextPainter(
      text: TextSpan(
        text: '${idx + 1}',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: isCp ? const Color(0xFF1D4ED8) : AppTokens.patrolFg,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p + const Offset(9, -14));
  }

  @override
  bool shouldRepaint(covariant _RouteEditorPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.checkpoints != checkpoints ||
      oldDelegate.crossingSegs != crossingSegs ||
      oldDelegate.selectedIdx != selectedIdx;
}
