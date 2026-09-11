import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/room/room_geometry.dart';
import '../../core/storage/measure_store.dart';
import '../../core/storage/room_scan_store.dart';
import '../../core/utils/mm_format.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/nav_icon_button.dart';

/// 量房成图页（手动打点成图，ROOM_MEASURE_IMPL §7.2）。
///
/// 坐标：InteractiveViewer 内为 8000×8000mm 逻辑画布（1mm=1逻辑px），
/// 手势层直接取到 mm 坐标；v1 打点交互为 单击加点/长按删最近点/双击墙段加洞口，
/// 拖动改点/照片成图留待后续（避免与画布平移手势冲突）。
class RoomDrawPage extends ConsumerStatefulWidget {
  final RoomScanArgs args;
  const RoomDrawPage({super.key, required this.args});

  @override
  ConsumerState<RoomDrawPage> createState() => _RoomDrawPageState();
}

class _RoomDrawPageState extends ConsumerState<RoomDrawPage> {
  static const double _canvas = 8000; // mm
  final _nameCtl = TextEditingController(text: '房间');
  final _netHeightCtl = TextEditingController();
  final _thicknessCtl = TextEditingController(text: '200');
  String _roomUse = '其他';
  static const _roomUses = ['卧室', '客厅', '厨房', '卫浴', '其他'];

  final List<Offset> _pts = []; // 墙角点（mm）
  Set<int> _snapped = const {};
  bool _orthoOn = true;
  // 临时洞口（保存时归入对应 RoomWall）
  final List<({int wallIdx, WallOpening op})> _openings = [];

  /// 点回起点完成闭合时记录的首尾缺口（≤60mm），此后闭合差以此为准
  /// （否则开环点列 closureDelta = 首尾距离恒为大值，演示与工程口径不符）。
  double? _closeGap;
  final _view = TransformationController();

  @override
  void initState() {
    super.initState();
    // 缩放/平移后重绘画笔（线宽/点径需按最新 viewScale 换算）。
    _view.addListener(_onViewChanged);
    // 进入即给"可用视野"：8m 画布 1:1 只见原点一角，先按 ~0.12 倍铺开（可视约 3m 宽）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetView());
  }

  void _onViewChanged() {
    if (mounted) setState(() {});
  }

  /// 视野复位到画布起点区域（~0.12 倍）。
  void _resetView() {
    _view.value = Matrix4.identity()
      ..translate(80.0, 80.0)
      ..scale(0.12);
  }

  /// 以视口中心为锚点缩放。
  void _zoomBy(Size vp, double f) {
    final m = _view.value.clone();
    final s = m.getMaxScaleOnAxis();
    final ns = (s * f).clamp(0.05, 4.0);
    final eff = ns / s;
    final c = Offset(vp.width / 2, vp.height / 2);
    m
      ..translate(c.dx, c.dy)
      ..scale(eff)
      ..translate(-c.dx, -c.dy);
    _view.value = m;
  }

  @override
  void dispose() {
    _view.removeListener(_onViewChanged);
    _nameCtl.dispose();
    _netHeightCtl.dispose();
    _thicknessCtl.dispose();
    _view.dispose();
    super.dispose();
  }

  void _applySnap() {
    if (!_orthoOn) {
      setState(() => _snapped = const {});
      return;
    }
    final r = orthoSnap(_pts);
    setState(() {
      _pts
        ..clear()
        ..addAll(r.points);
      _snapped = r.snappedIdx;
    });
  }

  // —— 手势 ——
  void _onTap(Offset mm) {
    // 点回起点 = 闭合：记录首尾缺口（不再追加重复点），闭合差即此缺口。
    if (_pts.length >= 3 && (_pts.first - mm).distance <= 60) {
      setState(() => _closeGap = (_pts.first - mm).distance);
      _applySnap();
      AppSnack.show(context, '已闭合（缺口 ${fmtMm(_closeGap!)}mm），可保存',
          kind: AppSnackKind.success);
      return;
    }
    if (_nearPoint(mm) != null) return; // 近点交给选择/删除流程（见长按）
    setState(() {
      _pts.add(mm);
      _closeGap = null;
    });
    _applySnap();
  }

  int? _nearPoint(Offset p, {double tol = 40}) {
    for (var i = 0; i < _pts.length; i++) {
      if ((_pts[i] - p).distance <= tol) return i;
    }
    return null;
  }

  void _onLongPress(Offset mm) {
    final idx = _nearPoint(mm);
    if (idx == null) return;
    setState(() => _pts.removeAt(idx));
    _applySnap();
  }

  void _undo() {
    if (_pts.isEmpty) return;
    setState(() {
      _pts.removeLast();
      _closeGap = null;
    });
    _applySnap();
  }

  void _clearAll() {
    setState(() {
      _pts.clear();
      _openings.clear();
      _snapped = const {};
      _closeGap = null;
    });
  }

  // 双击选墙段（点距墙段 < tol）
  Future<void> _onDoubleTap(Offset mm) async {
    if (_pts.length < 2) return;
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < _pts.length; i++) {
      final a = _pts[i];
      final b = _pts[(i + 1) % _pts.length];
      final d = _distToSeg(mm, a, b);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best < 0 || bestD > 50) {
      AppSnack.show(context, '请双击靠近某条墙段', kind: AppSnackKind.muted);
      return;
    }
    await _addOpeningFor(best, mm);
  }

  double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 <= 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2)
        .clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  // —— 洞口 ——
  Future<void> _addOpeningFor(int wallIdx, Offset tapMm) async {
    final a = _pts[wallIdx];
    final b = _pts[(wallIdx + 1) % _pts.length];
    final len = (a - b).distance;
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = len2 <= 0
        ? 0.0
        : ((((tapMm.dx - a.dx) * ab.dx + (tapMm.dy - a.dy) * ab.dy) / len2)
            .clamp(0.0, 1.0));
    final typeCtl = TextEditingController(text: 'door');
    final offsetCtl =
        TextEditingController(text: (ab * t).distance.toStringAsFixed(0));
    final widthCtl = TextEditingController(text: '900');
    final type = await AppDialog.show<String>(
      context: context,
      title: '添加门窗洞口',
      content: StatefulBuilder(
        builder: (ctx, setD) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择洞口类型并填写尺寸，系统会挂到当前墙段上。',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 22 / 14,
                color: AppTokens.fg2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDialogTypeOption(
                    label: '门',
                    selected: typeCtl.text == 'door',
                    onTap: () => setD(() => typeCtl.text = 'door'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDialogTypeOption(
                    label: '窗',
                    selected: typeCtl.text == 'window',
                    onTap: () => setD(() => typeCtl.text = 'window'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDialogInputField(
              label: '距墙段起点 (mm)',
              controller: offsetCtl,
            ),
            const SizedBox(height: 12),
            _buildDialogInputField(
              label: '洞口宽 (mm)',
              controller: widthCtl,
            ),
          ],
        ),
      ),
      actions: AppDialogActions(
        children: [
          AppDialogButton.secondary(
            label: '取消',
            onTap: () =>
                Navigator.of(context, rootNavigator: true).pop('cancel'),
          ),
          AppDialogButton.primary(
            label: '添加',
            onTap: () => Navigator.of(context, rootNavigator: true).pop('ok'),
          ),
        ],
      ),
    );
    if (type != 'ok') return;
    if (!mounted) return;
    final off = double.tryParse(offsetCtl.text) ?? 0;
    final wid = double.tryParse(widthCtl.text) ?? 900;
    if (off < 0 || off + wid > len + 1e-3) {
      AppSnack.show(context, '洞口超出墙段范围（墙长 ${fmtMm(len)}mm）',
          kind: AppSnackKind.danger);
      return;
    }
    setState(() {
      _openings.add((
        wallIdx: wallIdx,
        op: WallOpening(
            type: typeCtl.text == 'window' ? 'window' : 'door',
            offsetFromMm: off,
            widthMm: wid),
      ));
    });
  }

  // —— 保存 ——
  Future<void> _save() async {
    if (_pts.length < 3) {
      AppSnack.show(context, '请至少点出 3 个墙角（沿房间走一圈）', kind: AppSnackKind.danger);
      return;
    }
    final delta = _closeGap ?? closureDelta(_pts);
    if (delta > 50) {
      final ok = await AppDialog.show<bool>(
        context: context,
        title: '闭合差偏大',
        description: '首尾缺口 ${fmtMm(delta)}mm 大于 50mm，可能漏画了某段墙，建议先回去检查。',
        actions: AppDialogActions(
          children: [
            AppDialogButton.secondary(
              label: '回去改',
              onTap: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
            ),
            AppDialogButton.primary(
              label: '仍然保存',
              onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }
    final projectKey =
        widget.args.projectKey ?? (ref.read(currentProjectIdProvider) ?? '');
    if (projectKey.isEmpty) {
      AppSnack.show(context, '缺少项目，无法保存', kind: AppSnackKind.danger);
      return;
    }
    final lens = wallLengthsMm(_pts);
    final walls = <RoomWall>[
      for (var i = 0; i < _pts.length; i++)
        RoomWall(
          id: 'w$i',
          ax: _pts[i].dx,
          ay: _pts[i].dy,
          bx: _pts[(i + 1) % _pts.length].dx,
          by: _pts[(i + 1) % _pts.length].dy,
          lengthMm: lens[i],
          thicknessMm: double.tryParse(_thicknessCtl.text) ?? 200,
          openings: [
            for (final e in _openings)
              if (e.wallIdx == i) e.op,
          ],
        ),
    ];
    final now = DateTime.now().millisecondsSinceEpoch;
    // 关联该图纸的「量尺校对」结果 → 作为本记录的 checks 进报告尺寸校对区
    // （记录本身带 drawingKey 正是为此）；无图纸/无会话则为空，不阻断保存。
    var checks = const <MeasureItem>[];
    final dk = widget.args.drawingKey;
    if (dk != null && dk.isNotEmpty) {
      final s = await MeasureStore.load(projectKey, dk);
      if (s != null) checks = s.items;
    }
    final record = RoomScanRecord(
      id: 'room_$now',
      projectKey: projectKey,
      name: _nameCtl.text.trim().isEmpty ? '房间' : _nameCtl.text.trim(),
      roomUse: _roomUse,
      source: 'manual',
      scannedAtMs: now,
      walls: walls,
      closureDeltaMm: delta,
      netHeightMm: double.tryParse(_netHeightCtl.text),
      drawingKey: dk,
      checks: checks,
    );
    await RoomScanStore.save(projectKey, record);
    await refreshRoomScans(ref, projectKey);
    if (mounted) {
      AppSnack.show(context, '已保存量房：${record.name}',
          kind: AppSnackKind.success);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ptsCount = _pts.length;
    final perim = ptsCount >= 2 ? _perimeterMm() : 0.0;
    final area = ptsCount >= 3 ? areaM2(_pts) : 0.0;
    final delta = _closeGap ?? (ptsCount >= 3 ? closureDelta(_pts) : 0.0);
    final ortho = _orthoOn;
    final canvasHeight =
        MediaQuery.sizeOf(context).height < 760 ? 360.0 : 420.0;
    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        centerTitle: true,
        leadingWidth: 0,
        titleSpacing: 0,
        title: Stack(
          alignment: Alignment.center,
          children: const [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 12),
                child: NavIconButton(
                  icon: MingCuteIcons.leftLine,
                  color: Color(0xFF09244B),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                '量房成图',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 24 / 16,
                  color: AppTokens.fg,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWorktopCard(
                title: '量房概览',
                helper: '按房间轮廓依次点墙角，闭合后再补门窗洞口，生成结果会自动关联当前项目。',
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetricPill(
                          label: '墙角',
                          value: '$ptsCount 个',
                        ),
                        _buildMetricPill(
                          label: '周长',
                          value: '${_fmtM(perim)} m',
                        ),
                        _buildMetricPill(
                          label: '面积',
                          value: '${area.toStringAsFixed(2)} ㎡',
                        ),
                        _buildMetricPill(
                          label: '闭合差',
                          value: '${fmtMm(delta)}mm',
                          highlight: delta > 15,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTokens.surface2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '操作说明：单击加点，点回起点闭合，长按删除最近点，双击墙段添加门窗洞口。',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 20 / 12,
                          color: AppTokens.fg2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildWorktopCard(
                title: '量房画布',
                helper: '支持拖动画布、双指缩放，右下角的复位 / 放大 / 缩小与图纸详情保持同一套样式。',
                action: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 360;
                    if (compact) {
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          _buildToolChip(
                            icon: MingCuteIcons.back2Line,
                            label: '撤销',
                            onTap: _pts.isEmpty ? null : _undo,
                          ),
                          _buildToolChip(
                            icon: MingCuteIcons.deleteLine,
                            label: '清空',
                            onTap: _pts.isEmpty ? null : _clearAll,
                          ),
                          _buildToolChip(
                            icon: MingCuteIcons.rulerLine,
                            label: ortho ? '正交开' : '正交关',
                            onTap: () => setState(() => _orthoOn = !_orthoOn),
                            active: ortho,
                          ),
                        ],
                      );
                    }
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildToolChip(
                          icon: MingCuteIcons.back2Line,
                          label: '撤销',
                          onTap: _pts.isEmpty ? null : _undo,
                        ),
                        const SizedBox(width: 8),
                        _buildToolChip(
                          icon: MingCuteIcons.deleteLine,
                          label: '清空',
                          onTap: _pts.isEmpty ? null : _clearAll,
                        ),
                        const SizedBox(width: 8),
                        _buildToolChip(
                          icon: MingCuteIcons.rulerLine,
                          label: ortho ? '正交开' : '正交关',
                          onTap: () => setState(() => _orthoOn = !_orthoOn),
                          active: ortho,
                        ),
                      ],
                    );
                  },
                ),
                child: SizedBox(
                  height: canvasHeight,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // 画布工作区保持白底轻量化，缩放按钮沿用图纸详情那套 40×64 白卡。
                      return Container(
                        decoration: BoxDecoration(
                          color: AppTokens.surface2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: InteractiveViewer(
                                  transformationController: _view,
                                  constrained: false,
                                  minScale: 0.05,
                                  maxScale: 4,
                                  child: GestureDetector(
                                    onTapUp: (e) => _onTap(e.localPosition),
                                    onLongPressStart: (e) =>
                                        _onLongPress(e.localPosition),
                                    onDoubleTapDown: (e) =>
                                        _onDoubleTap(e.localPosition),
                                    child: CustomPaint(
                                      size: const Size(_canvas, _canvas),
                                      painter: _RoomGridPainter(
                                        pts: _pts,
                                        snapped: _snapped,
                                        openings: _openings,
                                        viewScale:
                                            _view.value.getMaxScaleOnAxis(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 12,
                              top: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTokens.surface,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  ptsCount < 3 ? '请先顺时针点出房间轮廓' : '已闭合后可继续补门窗洞口',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    height: 20 / 12,
                                    color: AppTokens.fg2,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 12,
                              bottom: 12,
                              child: _RoomZoomFab(
                                onZoomIn: () => _zoomBy(box.biggest, 1.25),
                                onZoomOut: () => _zoomBy(box.biggest, 1 / 1.25),
                                onReset: _resetView,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildWorktopCard(
                title: '房间信息',
                helper: '保存后会进入量房记录，可继续查看户型图、墙段长度和闭合差。',
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildInputField(
                      label: '房间名称',
                      width: 168,
                      child: TextField(
                        controller: _nameCtl,
                        decoration: const InputDecoration(
                          hintText: '例如：主卧 / 会议室',
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                    _buildInputField(
                      label: '空间用途',
                      width: 132,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _roomUse,
                          isDense: true,
                          items: [
                            for (final u in _roomUses)
                              DropdownMenuItem<String>(
                                value: u,
                                child: Text(
                                  u,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    height: 22 / 14,
                                    color: AppTokens.fg,
                                  ),
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => _roomUse = v ?? '其他'),
                        ),
                      ),
                    ),
                    _buildInputField(
                      label: '净高 (mm)',
                      width: 120,
                      child: TextField(
                        controller: _netHeightCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '选填',
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                    _buildInputField(
                      label: '墙厚 (mm)',
                      width: 120,
                      child: TextField(
                        controller: _thicknessCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '默认 200',
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Material(
        color: AppTokens.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: AppButton(
              size: AppButtonSize.lg,
              width: double.infinity,
              label: _pts.isEmpty ? '请先开始量房' : '保存量房记录',
              onPressed: _pts.isEmpty ? null : _save,
            ),
          ),
        ),
      ),
    );
  }

  /// 白底工作台卡片：统一量房页各区块的标题、说明和内容布局。
  Widget _buildWorktopCard({
    required String title,
    String? helper,
    Widget? action,
    required Widget child,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(12),
        ),
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
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 22 / 14,
                          color: AppTokens.fg,
                        ),
                      ),
                      if (helper != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          helper,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 20 / 12,
                            color: AppTokens.fg2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 12),
                  Flexible(child: action),
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  /// 顶部概览的轻量指标胶囊：用来快速扫点数、面积和闭合差状态。
  Widget _buildMetricPill({
    required String label,
    required String value,
    bool highlight = false,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: highlight ? const Color(0x0DFF4444) : AppTokens.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: RichText(
          text: TextSpan(
            text: '$label ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 20 / 12,
              color: AppTokens.fg2,
            ),
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 20 / 12,
                  color: highlight ? const Color(0xFFFF4444) : AppTokens.fg,
                ),
              ),
            ],
          ),
        ),
      );

  /// 画布右上角轻操作：撤销、清空、正交开关统一做成轻量胶囊按钮。
  Widget _buildToolChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool active = false,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: active ? AppTokens.brandTint : AppTokens.surface2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: active ? AppTokens.brand : AppTokens.fg2,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 20 / 12,
                    color: active ? AppTokens.brand : AppTokens.fg2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// 表单字段壳：统一成浅灰底信息块，避免原生输入框的重边框样式。
  Widget _buildInputField({
    required String label,
    required Widget child,
    double? width,
  }) =>
      SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTokens.surface2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 20 / 12,
                  color: AppTokens.muted,
                ),
              ),
              const SizedBox(height: 4),
              child,
            ],
          ),
        ),
      );

  /// 洞口类型选择项：弹窗里使用蓝描边选中态，和全局选中卡风格一致。
  Widget _buildDialogTypeOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTokens.brandTint : AppTokens.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppTokens.brand : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 22 / 14,
                color: selected ? AppTokens.brand : AppTokens.fg,
              ),
            ),
          ),
        ),
      );

  /// 洞口弹窗输入框：统一成浅灰底输入块，避免系统原生输入框风格过重。
  Widget _buildDialogInputField({
    required String label,
    required TextEditingController controller,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 20 / 12,
                color: AppTokens.muted,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ],
        ),
      );

  double _perimeterMm() {
    var s = 0.0;
    for (var i = 0; i < _pts.length; i++) {
      s += (_pts[(i + 1) % _pts.length] - _pts[i]).distance;
    }
    return s;
  }

  String _fmtM(double mm) => (mm / 1000).toStringAsFixed(2);
}

/// 与图纸详情保持一致的右下缩放控件：复位 / 放大 / 缩小三张独立白卡。
class _RoomZoomFab extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _RoomZoomFab({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _zoomCard(MingCuteIcons.fullscreenLine, '复位', onReset),
          const SizedBox(height: 8),
          _zoomCard(MingCuteIcons.addLine, '放大', onZoomIn),
          const SizedBox(height: 8),
          _zoomCard(MingCuteIcons.minimizeLine, '缩小', onZoomOut),
        ],
      );

  Widget _zoomCard(IconData icon, String label, VoidCallback onTap) => Material(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 40,
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: const Color(0xFF09244B)),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 20 / 12,
                      color: Color(0xFF60656B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 画布绘制：网格 + 当前墙角连线 + 吸附高亮 + 洞口示意。
class _RoomGridPainter extends CustomPainter {
  final List<Offset> pts;
  final Set<int> snapped;
  final List<({int wallIdx, WallOpening op})> openings;

  /// 当前视图缩放（mm→屏幕px）。画布元素都画在毫米坐标系里，
  /// 缩小视图时线宽会被同步缩小到亚像素（0.12 倍时 1px→0.12px）而不可见，
  /// 因此线宽/点径统一除以 viewScale 换算回屏幕像素。
  final double viewScale;
  const _RoomGridPainter({
    required this.pts,
    required this.snapped,
    required this.openings,
    required this.viewScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final k = 1.0 / viewScale;
    final minor = Paint()
      ..color = const Color(0xFFE6EBF3)
      ..strokeWidth = 1 * k;
    final major = Paint()
      ..color = const Color(0xFFC9D2E0)
      ..strokeWidth = 1.5 * k;
    for (var v = 0.0; v <= size.width; v += 500) {
      canvas.drawLine(
          Offset(v, 0), Offset(v, size.height), v % 1000 == 0 ? major : minor);
    }
    for (var h = 0.0; h <= size.height; h += 500) {
      canvas.drawLine(
          Offset(0, h), Offset(size.width, h), h % 1000 == 0 ? major : minor);
    }

    if (pts.isEmpty) return;
    final wallPaint = Paint()
      ..color = const Color(0xFF30323A)
      ..strokeWidth = 3 * k
      ..strokeCap = StrokeCap.round;
    final isClosed = pts.length >= 3;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      canvas.drawLine(a, b, wallPaint);
      // 洞口示意（同 wallIdx 对应的 i）
      for (final e in openings) {
        if (e.wallIdx == i) {
          final len = (b - a).distance;
          final u0 = (e.op.offsetFromMm / len).clamp(0.0, 1.0);
          final u1 = ((e.op.offsetFromMm + e.op.widthMm) / len).clamp(0.0, 1.0);
          canvas.drawLine(
              a + (b - a) * u0,
              a + (b - a) * u1,
              Paint()
                ..color = Colors.white
                ..strokeWidth = 9 * k);
        }
      }
    }
    for (var i = 0; i < pts.length; i++) {
      canvas.drawCircle(
          pts[i],
          6 * k,
          Paint()
            ..color = snapped.contains(i) || (isClosed && i == pts.length - 1)
                ? const Color(0xFF1DB954)
                : const Color(0xFF3478F6));
    }
  }

  @override
  bool shouldRepaint(covariant _RoomGridPainter old) =>
      old.pts != pts ||
      old.snapped != snapped ||
      old.openings != openings ||
      old.viewScale != viewScale;
}
