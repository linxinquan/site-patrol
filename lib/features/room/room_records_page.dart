import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/room/room_geometry.dart';
import '../../core/storage/room_scan_store.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_snack.dart';
import 'room_plan_painter.dart';

/// 量房记录列表（ROOM_MEASURE_IMPL §7.1）。
class RoomRecordsPage extends ConsumerWidget {
  const RoomRecordsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = ref.watch(currentProjectIdProvider) ?? '';
    final scans = ref.watch(roomScansProvider(projectId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('量房记录'),
        actions: [
          IconButton(
            icon: const Icon(MingCuteIcons.addLine),
            onPressed: () => context.push('/room-draw',
                extra: RoomScanArgs(projectKey: projectId)),
          ),
        ],
      ),
      body: scans.maybeWhen(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('量房记录读取失败')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有量房记录，点右上角 + 开始量房\n'
                  '（手动成图：在画布上点出房间墙角即可）',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8A90A0), height: 1.8),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (ctx, i) => _RoomCard(record: list[i], projectId: projectId),
          );
        },
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }
}

class _RoomCard extends ConsumerWidget {
  final RoomScanRecord record;
  final String projectId;
  const _RoomCard({required this.record, required this.projectId});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除量房记录'),
        content: Text('确定删除「${record.name}」？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await RoomScanStore.delete(projectId, record.id);
    await refreshRoomScans(ref, projectId);
    if (context.mounted) {
      AppSnack.show(context, '已删除', kind: AppSnackKind.muted);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pts = record.cornerPoints;
    final area = areaM2(pts);
    final delta = record.closureDeltaMm ?? closureDelta(pts);
    final deltaOk = delta <= 15;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/room-detail',
            extra: RoomScanArgs(recordId: record.id, projectKey: projectId)),
        onLongPress: () => _confirmDelete(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 92,
                  height: 72,
                  child: CustomPaint(
                    painter: RoomPlanPainter(
                      walls: record.walls,
                      showDims: false,
                      label: null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${record.name} · ${record.roomUse}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      _fmt(record.scannedAtMs) +
                          ' · ${area.toStringAsFixed(2)} ㎡'
                          ' · ${record.walls.length} 段',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF8A90A0)),
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(
                        deltaOk
                            ? MingCuteIcons.checkCircleLine
                            : MingCuteIcons.warningLine,
                        size: 14,
                        color: deltaOk ? const Color(0xFF1DB954) : const Color(0xFFFF5959),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        deltaOk
                            ? '闭合差 ${delta.round()}mm'
                            : '闭合差 ${delta.round()}mm 需复核',
                        style: TextStyle(
                            fontSize: 12,
                            color: deltaOk
                                ? const Color(0xFF1DB954)
                                : const Color(0xFFFF5959)),
                      ),
                    ]),
                  ],
                ),
              ),
              const Icon(MingCuteIcons.rightLine, size: 18, color: Color(0xFFB9BFCC)),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmt(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String p(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}';
}
