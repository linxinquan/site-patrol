import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/cad/wall_lines.dart';
import '../../core/storage/patrol_plan_store.dart';
import '../../core/utils/cad_coord.dart';
import '../../data/models.dart';
import '../../shared/widgets/drawing_image.dart';
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
  // 画布尺寸 / 图纸（供交互回调换算坐标）。
  Size _canvasBox = Size.zero;
  Drawing? _canvasDrawing;
  Matrix4? _dragStartMatrix; // 拖动点起始时的变换矩阵（稳定换算，避免图纸被平移）
  bool _dragUndoPushed = false; // 本次拖动是否已入撤销栈
  bool _didPan = false; // 本次手势是否平移了图纸（用于吞掉松手后的误 tap）

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
    if (_didPan) {
      _didPan = false;
      return; // 刚平移过图纸，忽略松手后的误 tap（避免多点）
    }
    if (_draggingIdx != null) {
      _draggingIdx = null;
      return;
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

  // —— 拖动路点（用 InteractiveViewer 的 interaction 回调，避免与图纸平移手势冲突） ——
  // 命中路点 → 锁定该点并临时禁用 InteractiveViewer 平移，使其跟随手指移动而图纸不动；
  // 命中空白处 → 正常平移/缩放图纸，_didPan 标记用于吞掉松手后的误 tap。
  void _onInteractionStart(ScaleStartDetails details) {
    _didPan = false;
    final scene = _transformController.toScene(details.focalPoint);
    final hit = _hitIndex(scene, _canvasBox, _canvasDrawing!);
    if (hit != null) {
      _draggingIdx = hit;
      _dragStartMatrix = Matrix4.fromList(_transformController.value.storage);
      _dragUndoPushed = false;
      setState(() {}); // 禁用图纸平移，专注拖点
    }
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (_draggingIdx == null) {
      _didPan = true; // 空白处拖动 = 平移图纸
      return;
    }
    if (!_dragUndoPushed) {
      _pushUndo(); // 拖动开始时记一次撤销快照
      _dragUndoPushed = true;
    }
    // 用拖动起始矩阵换算，保证图纸不被平移干扰
    final scene = MatrixUtils.transformPoint(
        Matrix4.inverted(_dragStartMatrix!), details.focalPoint);
    final rel = _displayToRel(scene, _canvasBox, _canvasDrawing!);
    setState(() {
      final p = _points[_draggingIdx!];
      _points[_draggingIdx!] = PatrolPoint(
        dx: rel.dx.clamp(0.0, 100.0),
        dy: rel.dy.clamp(0.0, 100.0),
        isCheckpoint: p.isCheckpoint,
      );
    });
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    if (_draggingIdx != null) {
      _draggingIdx = null;
      setState(() {}); // 恢复图纸平移
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
    // 关键：让巡场页（返回后复用同一 Widget）立即刷新，避免"编辑后没保存"的错觉。
    ref.invalidate(patrolPlansProvider(_projectId));
    AppSnack.show(context, '路线已保存', kind: AppSnackKind.success);
    context.pop(true);
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
        backgroundColor: const Color(0xFFF8F8F8),
        foregroundColor: AppTokens.patrolFg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: NavIconButton(
          icon: MingCuteIcons.leftLine,
          color: AppTokens.patrolFg,
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: const Text('路线编辑',
            style: TextStyle(
                color: Color(0xFF000000),
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        actions: [
          // 操作说明（替换原顶部「保存」文字按钮）
          _HelpPill(onTap: _showHelp),
        ],
      ),
      body: drawing == null
          ? const Center(
              child: Text('图纸加载中…',
                  style: TextStyle(color: AppTokens.patrolMuted)))
          : Column(
              children: [
                const SizedBox(height: 8),
                // 信息卡片：路线名称 / 楼层（可点击改）/ 路线点
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _InfoCard(
                    name: _nameCtl.text.isEmpty ? '巡场路线' : _nameCtl.text,
                    floor: _floorCtl.text.isEmpty ? _floor : _floorCtl.text,
                    pointCount: _points.length,
                    onEditName: () => _showEditSheet(kind: 'name'),
                    onEditFloor: () => _showEditSheet(kind: 'floor'),
                  ),
                ),
                const SizedBox(height: 8),
                // 穿墙警告横幅（未校准 / 有穿墙段时显示）
                _WarningBanner(
                  wallLines: _wallLinesRel,
                  crossingCount: _crossingSegs.length,
                  attempted: _wallLinesAttempted,
                  calibrationOk: _calibrationOk,
                ),
                const SizedBox(height: 8),
                // 图纸画布
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _buildCanvas(drawing),
                  ),
                ),
                const SizedBox(height: 8),
                // 加点 / 删点
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _AddRemoveBar(
                    onAdd: () => _appendAtCenter(drawing),
                    onRemove: _popLastPoint,
                    canRemove: _points.isNotEmpty,
                  ),
                ),
                const SizedBox(height: 8),
                // 底部操作栏：撤销 / 清空 / 复位 / 保存（通栏、无圆角）
                _ActionBar(
                  canSave: canSave,
                  canUndo: _undoStack.isNotEmpty,
                  canClear: _points.isNotEmpty,
                  onUndo: _undo,
                  onClear: _clearAll,
                  onReset: _resetView,
                  onSave: _save,
                ),
                const SizedBox(height: 8),
              ],
            ),
    );
  }

  // —— 画布（从 build 抽出，保持手势/绘制逻辑不变） ——
  Widget _buildCanvas(Drawing drawing) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        _canvasBox = box;
        _canvasDrawing = drawing;
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
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 1.0,
              maxScale: 12.0,
              boundaryMargin: const EdgeInsets.all(160),
              clipBehavior: Clip.hardEdge,
              // 拖动路点时临时禁用图纸平移，避免「拖点变拖图」
              panEnabled: _draggingIdx == null,
              scaleEnabled: true,
              onInteractionStart: _onInteractionStart,
              onInteractionUpdate: _onInteractionUpdate,
              onInteractionEnd: _onInteractionEnd,
              child: SizedBox(
                width: box.width,
                height: box.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DrawingImage(
                        drawing.src,
                        fit: BoxFit.contain,
                      ),
                    ),
                    CustomPaint(
                      size: Size.infinite,
                      painter: _RouteEditorPainter(
                        points: [
                          for (final p in _points)
                            _relToDisplay(Offset(p.dx, p.dy), box, drawing),
                        ],
                        checkpoints: [
                          for (var i = 0; i < _points.length; i++)
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
    );
  }

  /// 顶部右上「操作说明」胶囊（白色胶囊 + 问号图标 + 品牌蓝文字）。
  Widget _HelpPill({required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          child: Container(
            height: 28,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(MingCuteIcons.questionLine,
                    size: 16, color: AppTokens.brand),
                const SizedBox(width: 4),
                const Text('操作说明',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1,
                        fontWeight: FontWeight.w500,
                        color: AppTokens.brand)),
              ],
            ),
          ),
        ),
      );

  /// 信息卡片：路线名称 / 楼层 / 路线点。前两者可点击弹出底部弹窗修改。
  Widget _InfoCard({
    required String name,
    required String floor,
    required int pointCount,
    required VoidCallback onEditName,
    required VoidCallback onEditFloor,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _InfoRow(label: '路线名称', value: name, onTap: onEditName),
            const SizedBox(height: 12),
            _InfoRow(label: '楼层', value: floor, onTap: onEditFloor),
            const SizedBox(height: 12),
            _InfoRow(label: '路线点', value: '$pointCount 点'),
          ],
        ),
      );

  Widget _InfoRow({
    required String label,
    required String value,
    VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 22,
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 14, height: 1, color: AppTokens.muted)),
              const Spacer(),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, height: 1, color: AppTokens.fg)),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(MingCuteIcons.editLine,
                    size: 16, color: AppTokens.fg),
              ],
            ],
          ),
        ),
      );

  /// 加点 / 删点 工具条（白底圆角，图标+文字均为弱化灰）。
  Widget _AddRemoveBar({
    required VoidCallback onAdd,
    required VoidCallback onRemove,
    required bool canRemove,
  }) =>
      Row(
        children: [
          Expanded(
            child: _AddRemoveBtn(
              icon: MingCuteIcons.addCircleFill,
              label: '加点',
              onTap: onAdd,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _AddRemoveBtn(
              icon: MingCuteIcons.minusCircleFill,
              label: '删点',
              onTap: canRemove ? onRemove : null,
            ),
          ),
        ],
      );

  Widget _AddRemoveBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 20,
                  color: onTap == null
                      ? AppTokens.muted.withValues(alpha: 0.5)
                      : AppTokens.muted),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      height: 1,
                      color: onTap == null
                          ? AppTokens.muted.withValues(alpha: 0.5)
                          : AppTokens.muted)),
            ],
          ),
        ),
      );

  /// 底部操作栏：撤销 / 清空 / 复位 / 保存。
  Widget _ActionBar({
    required bool canSave,
    required bool canUndo,
    required bool canClear,
    required VoidCallback onUndo,
    required VoidCallback onClear,
    required VoidCallback onReset,
    required VoidCallback onSave,
  }) =>
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            _ActionItem(
                icon: MingCuteIcons.backLine,
                label: '撤销',
                onTap: canUndo ? onUndo : null),
            _ActionItem(
                icon: MingCuteIcons.delete2Line,
                label: '清空',
                onTap: canClear ? onClear : null),
            _ActionItem(
                icon: MingCuteIcons.liveLocationLine,
                label: '复位',
                onTap: onReset),
            _ActionItem(
                icon: MingCuteIcons.fileDownloadLine,
                label: '保存',
                onTap: onSave,
                isSave: true,
                saveEnabled: canSave),
          ],
        ),
      );

  Widget _ActionItem({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isSave = false,
    bool saveEnabled = false,
  }) {
    final enabled = onTap != null;
    final Color c = isSave
        ? (saveEnabled ? AppTokens.brand : AppTokens.note)
        : (enabled ? AppTokens.fg : AppTokens.muted);
    final Color labelC = isSave
        ? (saveEnabled ? AppTokens.brand : AppTokens.note)
        : (enabled ? AppTokens.fg2 : AppTokens.muted);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: c),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: labelC)),
          ],
        ),
      ),
    );
  }

  /// 路线名称 / 楼层 编辑底部弹窗（占位：交互已通，CSS 待用户后续提供后细化）。
  void _showEditSheet({required String kind}) {
    final isName = kind == 'name';
    final ctl = TextEditingController(
        text: isName ? _nameCtl.text : _floorCtl.text);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isName ? '修改路线名称' : '修改楼层',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.fg)),
            const SizedBox(height: 16),
            TextField(
              controller: ctl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: isName ? '路线名称' : '楼层',
                labelStyle:
                    const TextStyle(color: AppTokens.muted, fontSize: 12),
                isDense: true,
                enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppTokens.border)),
                focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppTokens.brand)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    if (isName) {
                      _nameCtl.text = ctl.text.trim();
                    } else {
                      _floorCtl.text = ctl.text.trim();
                    }
                  });
                  Navigator.of(ctx).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTokens.brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('确定'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 操作说明底部弹窗：路线编辑的加点 / 删点等操作指引。
  void _showHelp() {
    final items = <List<String>>[
      ['加点', '单击图纸空白处添加一个路点；或点底部「加点」在画面中央补充一个点。'],
      ['删点', '长按路点删除；选中某点后点「删点」可精确删除该点；「清空」删除全部路点。'],
      ['移动', '拖动路点可调整其位置。'],
      ['检查点', '双击路点切换检查点（橙色实心），普通点为白底蓝边。'],
      ['撤销 / 复位', '误操作可点「撤销」回退一步；「复位」恢复视图缩放。'],
      ['保存', '路点 ≥ 2 时可保存；路线穿墙会提示确认后再保存。'],
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('操作说明',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.fg)),
            const SizedBox(height: 12),
            ...items.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                          text: '${e[0]}：',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.brand)),
                      TextSpan(
                          text: e[1],
                          style: const TextStyle(
                              fontSize: 13, color: AppTokens.fg)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 路线编辑顶部穿墙状态横幅（白底圆角、红字红图标，对齐 Figma Frame 2147228049）。
///  1. 未尝试加载 → 不显示（避免初次闪烁）
///  2. 已校准但无墙线段 → 不显示
///  3. 校准成功、有穿墙段 → 红色"⚠ 有 N 段穿墙，请沿走廊补点"
///  4. 未校准 → 红色"该图纸未校准，无法检测穿墙"
///  5. 已校准但墙线资产缺失（Python 管线未跑）→ 红色"该图纸暂无墙线数据，请运行 python server/cad_meta_build.py"
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
    final String msg;
    if (wallLines == null) {
      // 状态 4/5：区分未校准与墙线缺失
      msg = calibrationOk
          ? '该图纸暂无墙线数据，请运行 python server/cad_meta_build.py 后重试'
          : '该图纸未校准，无法检测穿墙';
    } else if (crossingCount > 0) {
      // 状态 3：红色警示
      msg = '⚠ 有 $crossingCount 段路线穿墙，请沿走廊补点';
    } else {
      // 状态 2：无穿墙段 → 不显示
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white, // 纯白底
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(MingCuteIcons.alertFill,
                size: 18, color: Color(0xFFE03131)), // 实红，无透明度
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1, // 关键：固定行高，图标与文字严格水平居中
                    fontWeight: FontWeight.w400,
                    color: Color(0xFFE03131),
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

/// 路线编辑覆盖层：折线 + 点（选中=蓝实心 / 检查点=橙实心 / 普通点=白底蓝描边）+ 序号。
/// P1：穿墙段（crossingSegs 内）画红色粗线覆盖，警示色与正常蓝色折线并存。
class _RouteEditorPainter extends CustomPainter {
  final List<Offset> points; // 显示坐标
  final List<int> checkpoints;
  final Set<int> crossingSegs; // 穿墙段下标（路线段 i 对应 points[i]→points[i+1]）
  final int? selectedIdx; // 选中点下标（蓝色高亮，供"删点"精确定位）
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
    // 1) 整条路线：Catmull-Rom 样条平滑（编辑时与巡场页一致的"模拟人走"曲线）。
    final smoothPath = catmullRomPath(points, samplesPerSeg: 16);
    canvas.drawPath(
      smoothPath,
      Paint()
        ..color = const Color(0xFF0395FF).withValues(alpha: 0.7) // 主色 0395FF
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // 2) 穿墙警示：每段按局部的 4 点样条切片（保留平滑视觉，不退化为直线）。
    if (crossingSegs.isNotEmpty) {
      final redPaint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final i in crossingSegs) {
        if (i + 1 >= points.length) continue;
        final segPath = _segmentSplinePath(i);
        if (segPath != null) canvas.drawPath(segPath, redPaint);
      }
    }
    // 3) 路径点（始终最上层）。
    for (var i = 0; i < points.length; i++) {
      _drawPoint(canvas, points[i], checkpoints.contains(i), i);
    }
  }

  /// 用 points[i-1]..points[i+2] 4 个点跑一次局部 Catmull-Rom 样条，
  /// 然后用 PathMetric.extractPath(0, length) 截取 [i]→[i+1] 对应的弧段。
  /// 端点处没有邻点时退化为直线（极短段，平滑度影响可忽略）。
  Path? _segmentSplinePath(int i) {
    if (i <= 0 || i + 2 >= points.length) {
      // 边界：首末段无完整邻点，直接用直线。
      return Path()
        ..moveTo(points[i].dx, points[i].dy)
        ..lineTo(points[i + 1].dx, points[i + 1].dy);
    }
    final p0 = points[i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[i + 2];
    final full = catmullRomPath([p0, p1, p2, p3], samplesPerSeg: 16);
    // Catmull-Rom 把整段 0..1 切三等分对应 [p0-p1, p1-p2, p2-p3]。
    // 这里要截 [p1]→[p2] 即 1/3..2/3 区间。
    final metric = full.computeMetrics().first;
    final seg = metric.extractPath(
      metric.length * (1 / 3),
      metric.length * (2 / 3),
    );
    return seg;
  }

  void _drawPoint(Canvas canvas, Offset p, bool isCp, int idx) {
    final isSel = idx == selectedIdx;
    final Color fill;
    final Color strokeColor;
    final double strokeW;
    if (isSel) {
      fill = const Color(0xFF3B82F6); // 选中 → 蓝实心
      strokeColor = const Color(0xFFFFFFFF); // 白描边凸显选中
      strokeW = 2.5;
    } else if (isCp) {
      fill = const Color(0xFFF97316); // 检查点 → 橙实心
      strokeColor = const Color(0xFFFFFFFF);
      strokeW = 1.5;
    } else {
      fill = const Color(0xFFFFFFFF); // 普通点 → 白底
      strokeColor = const Color(0xFF3B82F6); // 蓝描边（与路线同色）
      strokeW = 2.0;
    }
    canvas.drawCircle(
      p,
      7,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );
    canvas.drawCircle(p, 6.5, Paint()..color = fill);
    // 序号标签：圆内水平垂直居中。
    // 选中/检查点（蓝/橙实心）→ 纯白字；普通点 → 蓝色字，与描边同色。
    final Color txtColor = (isSel || isCp)
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF3B82F6);
    final tp = TextPainter(
      text: TextSpan(
        text: '${idx + 1}',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: txtColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // 用文字行度量取字形中心（em box 居中），保证数字在圆心正中央。
    final m = tp.computeLineMetrics().first;
    final top = p.dy - (m.ascent + m.descent) / 2;
    tp.paint(canvas, Offset(p.dx - tp.width / 2, top));
  }

  @override
  bool shouldRepaint(covariant _RouteEditorPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.checkpoints != checkpoints ||
      oldDelegate.crossingSegs != crossingSegs ||
      oldDelegate.selectedIdx != selectedIdx;
}
