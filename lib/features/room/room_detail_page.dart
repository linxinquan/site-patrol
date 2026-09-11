import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/room/room_geometry.dart';
import '../../core/storage/room_scan_store.dart';
import '../../core/utils/mm_format.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_snack.dart';
import 'room_plan_painter.dart';

/// 量房详情（ROOM_MEASURE_IMPL §7.3）。
class RoomDetailPage extends ConsumerStatefulWidget {
  final RoomScanArgs args;
  const RoomDetailPage({super.key, required this.args});

  @override
  ConsumerState<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends ConsumerState<RoomDetailPage> {
  RoomScanRecord? _record;

  String get _projectKey =>
      widget.args.projectKey ?? (ref.read(currentProjectIdProvider) ?? '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await RoomScanStore.list(_projectKey);
    if (!mounted) return;
    setState(() {
      _record = widget.args.recordId == null
          ? null
          : list.where((r) => r.id == widget.args.recordId).firstOrNull;
    });
  }

  Future<void> _save(RoomScanRecord r) async {
    await RoomScanStore.save(_projectKey, r);
    await refreshRoomScans(ref, _projectKey);
    if (mounted) setState(() => _record = r);
  }

  Future<void> _editWall(RoomScanRecord r, int i) async {
    final w = r.walls[i];
    final thickCtl =
        TextEditingController(text: (w.thicknessMm ?? 200).toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('墙 ${i + 1}（${fmtMm(w.lengthMm)}mm）'),
        content: TextField(
          controller: thickCtl,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: '墙厚 (mm)', isDense: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final walls = [...r.walls];
    walls[i] = w.copyWith(
        thicknessMm: double.tryParse(thickCtl.text) ?? w.thicknessMm);
    await _save(r.copyWith(walls: walls));
  }

  Future<void> _deleteWall(RoomScanRecord r, int i) async {
    final walls = [...r.walls]..removeAt(i);
    if (walls.isEmpty) {
      AppSnack.show(context, '至少要保留一面墙', kind: AppSnackKind.danger);
      return;
    }
    await _save(r.copyWith(walls: walls));
  }

  @override
  Widget build(BuildContext context) {
    final r = _record;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          '量房详情',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: r == null
            ? null
            : [
                TextButton.icon(
                  onPressed: () => context.push('/room-compare',
                      extra: RoomScanArgs(
                          recordId: r.id,
                          projectKey: r.projectKey,
                          drawingKey: r.drawingKey,
                          drawingTitle: null)),
                  icon: const Icon(MingCuteIcons.cubeLine, size: 16),
                  label: const Text('对照图纸'),
                ),
              ],
      ),
      body: r == null ? const Center(child: Text('记录不存在或已删除')) : _buildBody(r),
    );
  }

  Widget _buildBody(RoomScanRecord r) {
    final pts = r.cornerPoints;
    final area = areaM2(pts);
    final delta = r.closureDeltaMm ?? closureDelta(pts);
    final deltaOk = delta <= 15;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 320,
            child: CustomPaint(
              painter: RoomPlanPainter(
                walls: r.walls,
                showDims: true,
                label: '${r.name} · ${area.toStringAsFixed(2)} ㎡',
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text('${r.name} · ${r.roomUse} · ${_fmt(r.scannedAtMs)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          '面积 ${area.toStringAsFixed(2)} ㎡ · '
          '周长 ${(r.walls.fold(0.0, (s, w) => s + w.lengthMm) / 1000).toStringAsFixed(2)} m'
          ' · 闭合差 ${fmtMm(delta)}mm'
          '${deltaOk ? '' : '（需复核）'}'
          '${r.netHeightMm != null ? ' · 净高 ${fmtMm(r.netHeightMm!)}mm' : ''}'
          ' · 来源 ${r.source}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF8A90A0)),
        ),
        const SizedBox(height: 12),
        const Text('墙段',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 4),
        for (var i = 0; i < r.walls.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text('墙 ${i + 1} · ${fmtMm(r.walls[i].lengthMm)} mm'),
              subtitle: Text('墙厚 ${fmtMm(r.walls[i].thicknessMm ?? 200)} mm'
                  ' · 洞口 ${r.walls[i].openings.length} 处'
                  '${r.walls[i].openings.isEmpty ? '' : ' · ${r.walls[i].openings.map((o) => o.type == 'door' ? '门${fmtMm(o.widthMm)}' : '窗${fmtMm(o.widthMm)}').join('、')}'}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                      onPressed: () => _editWall(r, i), child: const Text('改')),
                  IconButton(
                    icon: const Icon(MingCuteIcons.deleteLine,
                        size: 18, color: Color(0xFFFF5959)),
                    onPressed: () => _deleteWall(r, i),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        const Text('图纸核尺对照',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 4),
        if (r.checks.isEmpty)
          const Text('尚未对照图纸。点右上角「对照图纸」：在图纸上逐墙量取对应尺寸生成偏差。',
              style: TextStyle(fontSize: 12, color: Color(0xFF8A90A0)))
        else
          for (final c in r.checks)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: Icon(
                  c.pass(15, 2)
                      ? MingCuteIcons.checkCircleLine
                      : MingCuteIcons.closeCircleLine,
                  color: c.pass(15, 2)
                      ? const Color(0xFF1DB954)
                      : const Color(0xFFFF5959),
                ),
                title: Text(c.name),
                subtitle: Text(
                    '图纸 ${fmtMm(c.drawingMm)} mm / 量得 ${fmtMm(c.photoMm)} mm'
                    ' · 偏差 ${fmtMmSigned(c.deviation)} mm'),
              ),
            ),
      ],
    );
  }
}

String _fmt(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String p(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}
