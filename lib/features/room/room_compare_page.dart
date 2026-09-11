import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

import '../../core/di/providers.dart';
import '../../core/storage/room_scan_store.dart';
import '../../core/utils/cad_coord.dart';
import '../../core/utils/mm_format.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/drawing_image.dart';

/// 量房图纸核尺对照（ROOM_MEASURE_IMPL §7.5 / P0-5）。
///
/// 逐墙在图纸上点"对应两端"→ 用 CAD 校准映射算出图纸尺寸(mm)，
/// 与量房墙长(photoMm)生成 `MeasureItem` 判定并写入记录.checks。
class RoomComparePage extends ConsumerStatefulWidget {
  final RoomScanArgs args;
  const RoomComparePage({super.key, required this.args});

  @override
  ConsumerState<RoomComparePage> createState() => _RoomComparePageState();
}

class _RoomComparePageState extends ConsumerState<RoomComparePage> {
  RoomScanRecord? _record;
  Drawing? _drawing;
  CadCoordMapper? _mapper;
  bool _loading = true;
  int _wallIdx = 0;
  final List<Offset> _picks = []; // 整图像素两点（当前墙，测完清空）

  String get _projectKey =>
      widget.args.projectKey ?? (ref.read(currentProjectIdProvider) ?? '');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final list = await RoomScanStore.list(_projectKey);
    final rec = widget.args.recordId == null
        ? null
        : list.where((r) => r.id == widget.args.recordId).firstOrNull;
    final drawings = ref.read(drawingsProvider).valueOrNull ?? {};
    String? wantKey = widget.args.drawingKey;
    if ((wantKey == null || !drawings.containsKey(wantKey)) &&
        drawings.isNotEmpty) {
      wantKey = drawings.keys.first;
    }
    if (!mounted) return;
    setState(() {
      _record = rec;
      _drawing = wantKey == null ? null : drawings[wantKey];
      _loading = false;
    });
    if (_drawing != null) await _loadMapper(_drawing!.key);
  }

  Future<void> _loadMapper(String key) async {
    setState(() => _loading = true);
    var mapper = ref.read(cadCalibrationMapProvider)[key];
    mapper ??= await loadCadCalibration(ref, key);
    if (!mounted) return;
    setState(() {
      _mapper = mapper;
      _loading = false;
    });
  }

  void _onDrawTap(Offset local, Size box) {
    final d = _drawing;
    if (d == null || _mapper == null) return;
    final px = _localToPx(local, box, d.w, d.h);
    setState(() {
      _picks.add(px);
      if (_picks.length == 2) {
        final rec = _record!;
        final wall = rec.walls[_wallIdx];
        final a = _mapper!.screenToWorld(_picks[0].dx, _picks[0].dy);
        final b = _mapper!.screenToWorld(_picks[1].dx, _picks[1].dy);
        final drawingMm = (a - b).distance;
        final checks = [...rec.checks];
        final exist = checks.indexWhere((c) => c.name == '墙${_wallIdx + 1}');
        final item = MeasureItem(
          name: '墙${_wallIdx + 1}',
          drawingMm: drawingMm,
          photoMm: wall.lengthMm,
          source: 'manual',
        );
        if (exist >= 0) {
          checks[exist] = item;
        } else {
          checks.add(item);
        }
        _record = rec.copyWith(checks: checks);
        _picks.clear();
        if (_wallIdx < rec.walls.length - 1) _wallIdx += 1;
        AppSnack.show(context,
            '墙${_wallIdx} 对照完成：图纸 ${fmtMm(drawingMm)}mm · 量得 ${fmtMm(wall.lengthMm)}mm',
            kind: AppSnackKind.brand);
      }
    });
  }

  Offset _localToPx(Offset local, Size box, double imgW, double imgH) {
    final r = imgW / imgH;
    double cw = box.width, ch = box.width / r;
    if (ch > box.height) {
      ch = box.height;
      cw = box.height * r;
    }
    final offX = (box.width - cw) / 2;
    final offY = (box.height - ch) / 2;
    return Offset((local.dx - offX) / cw * imgW, (local.dy - offY) / ch * imgH);
  }

  Future<void> _saveAndExit() async {
    final rec = _record;
    if (rec == null) return;
    await RoomScanStore.save(_projectKey, rec);
    await refreshRoomScans(ref, _projectKey);
    if (mounted) {
      AppSnack.show(context, '核尺结果已保存（${rec.checks.length} 项）',
          kind: AppSnackKind.success);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = _record;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (rec == null) {
      return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const Text(
              '图纸核尺',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          body: const Center(child: Text('记录不存在')));
    }
    final drawings = ref.watch(drawingsProvider).valueOrNull ?? {};
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          '图纸核尺对照',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(onPressed: _saveAndExit, child: const Text('保存')),
        ],
      ),
      body: Column(
        children: [
          // 图纸选择
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              const Text('对照图纸：', style: TextStyle(fontSize: 12)),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _drawing?.key,
                  items: [
                    for (final e in drawings.entries)
                      DropdownMenuItem(
                          value: e.key, child: Text(e.value.title)),
                  ],
                  onChanged: (k) {
                    if (k == null) return;
                    setState(() => _drawing = drawings[k]);
                    _picks.clear();
                    _loadMapper(k);
                  },
                ),
              ),
            ]),
          ),
          // 墙选择
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (var i = 0; i < rec.walls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('墙${i + 1} ${fmtMm(rec.walls[i].lengthMm)}'),
                      selected: _wallIdx == i,
                      onSelected: (_) {
                        setState(() {
                          _wallIdx = i;
                          _picks.clear();
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 提示条
          Container(
            width: double.infinity,
            color: _mapper == null
                ? const Color(0xFFFFF3E0)
                : const Color(0xFFE7F4FF),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              _mapper == null
                  ? '图纸未校准：请先在「图纸查看」页完成坐标校准再来对照。'
                  : '在图纸上点出「墙${_wallIdx + 1}」的两端（第 ${_picks.length + 1}/2 点）',
              style: TextStyle(
                  fontSize: 12,
                  color: _mapper == null
                      ? const Color(0xFFB26A00)
                      : const Color(0xFF1565C0)),
            ),
          ),
          // 图纸
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(
                builder: (ctx, c) {
                  final d = _drawing;
                  if (d == null) {
                    return const Center(child: Text('当前项目没有图纸'));
                  }
                  final box = c.biggest;
                  final r = d.w / d.h;
                  double cw = box.width, ch = box.width / r;
                  if (ch > box.height) {
                    ch = box.height;
                    cw = box.height * r;
                  }
                  final offX = (box.width - cw) / 2;
                  final offY = (box.height - ch) / 2;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onTapUp: _mapper == null
                              ? null
                              : (e) => _onDrawTap(e.localPosition, box),
                          child: DrawingImage(d.src, fit: BoxFit.contain),
                        ),
                      ),
                      for (final p in _picks)
                        Positioned(
                          left: offX + p.dx / d.w * cw - 11,
                          top: offY + p.dy / d.h * ch - 22,
                          child: const Icon(MingCuteIcons.mapPinLine,
                              size: 22, color: Color(0xFF3478F6)),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          // 对照结果
          Container(
            height: 150,
            width: double.infinity,
            color: Colors.white,
            child: rec.checks.isEmpty
                ? const Center(
                    child: Text('还没有对照结果',
                        style: TextStyle(color: Color(0xFF8A90A0))))
                : ListView(
                    children: [
                      for (final c in rec.checks)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            c.pass(15, 2)
                                ? MingCuteIcons.checkCircleLine
                                : MingCuteIcons.closeCircleLine,
                            color: c.pass(15, 2)
                                ? const Color(0xFF1DB954)
                                : const Color(0xFFFF5959),
                          ),
                          title: Text(
                              '${c.name} · 偏差 ${fmtMmSigned(c.deviation)}mm'),
                          subtitle: Text(
                              '图纸 ${fmtMm(c.drawingMm)} / 量得 ${fmtMm(c.photoMm)}'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
