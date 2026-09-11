import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/room/room_geometry.dart';
import '../../core/storage/room_scan_store.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/nav_icon_button.dart';
import 'room_plan_painter.dart';

/// 量房记录列表（ROOM_MEASURE_IMPL §7.1）。
class RoomRecordsPage extends ConsumerWidget {
  const RoomRecordsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = ref.watch(currentProjectIdProvider) ?? '';
    final scans = ref.watch(roomScansProvider(projectId));
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F6F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        centerTitle: true,
        leadingWidth: 0,
        titleSpacing: 0,
        title: Stack(
          alignment: Alignment.center,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 12),
                child: NavIconButton(
                  icon: MingCuteIcons.leftLine,
                  color: Color(0xFF09244B),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                '量房记录',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 24 / 16,
                  color: AppTokens.fg,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                // 统一使用导航图标按钮，去掉 Web/桌面端 hover 灰底。
                child: NavIconButton(
                  icon: MingCuteIcons.addLine,
                  color: const Color(0xFF09244B),
                  onPressed: () => context.push(
                    '/room-draw',
                    extra: RoomScanArgs(projectKey: projectId),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: scans.maybeWhen(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('量房记录读取失败')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFF4F6F7),
                            borderRadius: BorderRadius.all(Radius.circular(32)),
                          ),
                          child: Icon(
                            MingCuteIcons.cubeLine,
                            size: 28,
                            color: Color(0xFF919499),
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '还没有量房记录',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 22 / 14,
                          color: Color(0xFF202224),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '点右上角 + 开始量房，手动在画布上依次点出房间墙角即可',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 20 / 12,
                          color: Color(0xFF919499),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0x0D0395FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        MingCuteIcons.layout5Line,
                        size: 18,
                        color: Color(0xFF0395FF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '当前项目量房档案',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 22 / 14,
                              color: Color(0xFF202224),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '共 ${list.length} 条记录，点进单条记录可查看户型图、尺寸和闭合差',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              height: 20 / 12,
                              color: Color(0xFF919499),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final record in list) ...[
                _RoomCard(record: record, projectId: projectId),
                const SizedBox(height: 12),
              ],
            ],
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
    final ok = await AppDialog.show<bool>(
      context: context,
      title: '删除量房记录',
      description: '确定删除「${record.name}」？此操作不可撤销。',
      actions: AppDialogActions(
        children: [
          AppDialogButton.secondary(
            label: '取消',
            onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
          ),
          AppDialogButton.primary(
            label: '删除',
            onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
          ),
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
    return AppCard(
      radius: 12,
      onTap: () => context.push('/room-detail',
          extra: RoomScanArgs(recordId: record.id, projectKey: projectId)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/room-detail',
            extra: RoomScanArgs(recordId: record.id, projectKey: projectId)),
        onLongPress: () => _confirmDelete(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 96,
                  height: 76,
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
                    Text(
                      '${record.name} · ${record.roomUse}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        height: 22 / 14,
                        color: Color(0xFF202224),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmt(record.scannedAtMs)} · ${area.toStringAsFixed(2)} ㎡ · ${record.walls.length} 段',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 20 / 12,
                        color: Color(0xFF919499),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: deltaOk
                            ? const Color(0x0D00B84A)
                            : const Color(0x0DFF4444),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            deltaOk
                                ? MingCuteIcons.checkCircleLine
                                : MingCuteIcons.warningLine,
                            size: 14,
                            color: deltaOk
                                ? const Color(0xFF00B84A)
                                : const Color(0xFFFF4444),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            deltaOk
                                ? '闭合差 ${delta.round()}mm'
                                : '闭合差 ${delta.round()}mm 需复核',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 20 / 12,
                              color: deltaOk
                                  ? const Color(0xFF00B84A)
                                  : const Color(0xFFFF4444),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(MingCuteIcons.rightLine,
                  size: 18, color: Color(0xFFB9BFCC)),
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
