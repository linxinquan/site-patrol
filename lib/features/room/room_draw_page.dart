import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

import '../../core/di/providers.dart';
import '../../core/room/room_geometry.dart';
import '../../core/storage/room_scan_store.dart';
import '../../core/utils/mm_format.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_snack.dart';

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
    _view.value = Matrix4.identity()..translate(80.0, 80.0)..scale(0.12);
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

  Widget _zoomBtn(IconData icon, VoidCallback onTap, {String? tip}) {
    final btn = Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: const Color(0xFF4A4F5E)),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: tip == null ? btn : Tooltip(message: tip, child: btn),
    );
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
      AppSnack.show(context,
          '已闭合（缺口 ${fmtMm(_closeGap!)}mm），可保存',
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
    final offsetCtl = TextEditingController(
        text: (ab * t).distance.toStringAsFixed(0));
    final widthCtl = TextEditingController(text: '900');
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('墙段 ${wallIdx + 1} 添加洞口'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'door', label: Text('门')),
                  ButtonSegment(value: 'window', label: Text('窗')),
                ],
                selected: {typeCtl.text},
                onSelectionChanged: (s) =>
                    setD(() => typeCtl.text = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: offsetCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '距墙段起点 (mm)', isDense: true)),
              TextField(
                  controller: widthCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '洞口宽 (mm)', isDense: true)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop('cancel'),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop('ok'),
                child: const Text('添加')),
          ],
        ),
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
      AppSnack.show(context, '请至少点出 3 个墙角（沿房间走一圈）',
          kind: AppSnackKind.danger);
      return;
    }
    final delta = _closeGap ?? closureDelta(_pts);
    if (delta > 50) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('闭合差偏大'),
          content: Text('首尾缺口 ${fmtMm(delta)}mm > 50mm，可能漏了某段墙。仍要保存吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('回去改')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('仍保存')),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }
    final projectKey = widget.args.projectKey ??
        (ref.read(currentProjectIdProvider) ?? '');
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
      drawingKey: widget.args.drawingKey,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('量房成图（手动）'),
        actions: [
          TextButton(onPressed: _undo, child: const Text('撤销')),
          IconButton(
              onPressed: _clearAll, icon: const Icon(MingCuteIcons.deleteLine)),
          TextButton(
            onPressed: () => setState(() => _orthoOn = !_orthoOn),
            child: Text(ortho ? '正交开' : '正交关',
                style: TextStyle(
                    fontSize: 12,
                    color: ortho ? const Color(0xFF1DB954) : appRed)),
          ),
          TextButton(
              onPressed: _pts.isEmpty ? null : _save,
              child: const Text('保存')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              // 缩放按钮兜底：桌面浏览器无捏合手势，InteractiveViewer 也不吃滚轮缩放。
              return Stack(
                children: [
                  ClipRect(
                    child: InteractiveViewer(
                      transformationController: _view,
                      constrained: false,
                      minScale: 0.05,
                      maxScale: 4,
                      child: GestureDetector(
                        onTapUp: (e) => _onTap(e.localPosition),
                        onLongPressStart: (e) => _onLongPress(e.localPosition),
                        onDoubleTapDown: (e) => _onDoubleTap(e.localPosition),
                        child: CustomPaint(
                          size: const Size(_canvas, _canvas),
                          painter: _RoomGridPainter(
                            pts: _pts,
                            snapped: _snapped,
                            openings: _openings,
                            viewScale: _view.value.getMaxScaleOnAxis(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Column(
                      children: [
                        _zoomBtn(Icons.add, () => _zoomBy(box.biggest, 1.25)),
                        _zoomBtn(
                            Icons.remove, () => _zoomBy(box.biggest, 1 / 1.25)),
                        _zoomBtn(Icons.home_outlined, _resetView,
                            tip: '回到起点'),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
          // 底部状态条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            width: double.infinity,
            color: const Color(0xFFF5F6F9),
            child: Text(
              '${_pts.length} 角 · 周长 ${_fmtM(perim)} · '
              '面积 ${area.toStringAsFixed(2)} ㎡ · '
              '闭合差 ${fmtMm(delta)}mm${delta > 15 ? '（需复核）' : ''}'
              '   提示：单击加点 · 点回起点闭合 · 长按删最近点 · 双击墙段加门/窗',
              style: const TextStyle(fontSize: 12, color: Color(0xFF4A4F5E)),
            ),
          ),
          // 工程信息卡
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('工程信息',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                        width: 110,
                        child: TextField(
                            controller: _nameCtl,
                            decoration: const InputDecoration(
                                labelText: '房间名', isDense: true))),
                    DropdownButton<String>(
                      value: _roomUse,
                      items: [
                        for (final u in _roomUses)
                          DropdownMenuItem(value: u, child: Text(u)),
                      ],
                      onChanged: (v) => setState(() => _roomUse = v ?? '其他'),
                    ),
                    SizedBox(
                        width: 90,
                        child: TextField(
                            controller: _netHeightCtl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: '净高mm', isDense: true))),
                    SizedBox(
                        width: 90,
                        child: TextField(
                            controller: _thicknessCtl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: '墙厚mm', isDense: true))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _perimeterMm() {
    var s = 0.0;
    for (var i = 0; i < _pts.length; i++) {
      s += (_pts[(i + 1) % _pts.length] - _pts[i]).distance;
    }
    return s;
  }

  String _fmtM(double mm) => (mm / 1000).toStringAsFixed(2);
}

const appRed = Color(0xFFFF5959);

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
      canvas.drawLine(Offset(v, 0), Offset(v, size.height),
          v % 1000 == 0 ? major : minor);
    }
    for (var h = 0.0; h <= size.height; h += 500) {
      canvas.drawLine(Offset(0, h), Offset(size.width, h),
          h % 1000 == 0 ? major : minor);
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
          canvas.drawLine(a + (b - a) * u0, a + (b - a) * u1,
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
