import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_snack.dart';
import '../capture/capture_page.dart' show StoredDetailSheet;
import 'capture_records_controller.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/filter_tabs.dart';
import 'widgets/grouped_grid.dart';
import 'widgets/stats_strip.dart';

/// 验收记录事后工作台：当前项目全部拍照验收记录的浏览、筛选、追溯与转工单。
///
/// 入口：首页 8 宫格「验收记录」卡片（`/capture-records`）。
/// 数据：[captureRecordsProvider] 按当前项目图纸 key 过滤 + ts 倒序。
/// 转工单：[onConvert] 回调调用 [Repository.addDefect] → [refreshDefects] →
/// [CaptureRecordsNotifier.markDefectConverted] → [AppSnack]。
class CaptureRecordsPage extends ConsumerStatefulWidget {
  const CaptureRecordsPage({super.key});

  @override
  ConsumerState<CaptureRecordsPage> createState() =>
      _CaptureRecordsPageState();
}

class _CaptureRecordsPageState extends ConsumerState<CaptureRecordsPage> {
  final Set<String> _collapsedGroups = {};

  /// 当前详情弹层正在显示的 entry；用于转工单 / 删除时回写。
  Map<String, dynamic>? _activeEntry;

  @override
  void initState() {
    super.initState();
    // 每次进入页面都重读 LocalStorage（拍照页保存的新记录、其他页面写回的
    // 转工单状态等），避免 provider 缓存导致列表过时。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(captureRecordsProvider.notifier).reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(captureRecordsProvider);
    final filter = ref.watch(captureRecordsFilterProvider);

    // 二次筛选（时间 / 楼层 / AI 仅）。
    final filtered = applyRecordsFilter(records, filter);

    final stats = _calcStats(records, filtered);
    final floors = _availableFloors(records);

    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('验收记录',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTokens.fg)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft,
              size: 18, color: AppTokens.fg),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTokens.success,
        foregroundColor: AppTokens.onAccent,
        elevation: 2,
        onPressed: () => context.push('/capture'),
        icon: const Icon(LucideIcons.camera, size: 18),
        label: const Text('拍照',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: records.isEmpty
            ? _EmptyState(
                onTakePhoto: () => context.push('/capture'),
              )
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(
                          top: AppTokens.space2,
                          bottom: AppTokens.space3),
                      child: StatsStrip(
                        total: stats.total,
                        today: stats.today,
                        pending: stats.pending,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: RecordFilterTabs(
                      time: filter.time,
                      onTimeChange: (t) {
                        ref.read(captureRecordsFilterProvider.notifier).state =
                            filter.copyWith(time: t);
                      },
                      floor: filter.floor,
                      onOpenFloorSheet: () => _openFloorSheet(floors, filter),
                    ),
                  ),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppTokens.space2)),
                  if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _NoMatchState(
                        onReset: () {
                          ref.read(captureRecordsFilterProvider.notifier).state =
                              const CaptureRecordsFilter();
                        },
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: GroupedRecordGrid(
                        records: filtered,
                        collapsedGroups: _collapsedGroups,
                        onToggleGroup: (key) {
                          setState(() {
                            if (!_collapsedGroups.add(key)) {
                              _collapsedGroups.remove(key);
                            }
                          });
                        },
                        onTapEntry: (entry) =>
                            _openDetail(context, entry, records),
                      ),
                    ),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 96)),
                ],
              ),
      ),
    );
  }

  // -------- 弹层与回调 --------

  Future<void> _openDetail(
    BuildContext context,
    Map<String, dynamic> entry,
    List<Map<String, dynamic>> allRecords,
  ) async {
    _activeEntry = entry;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => StoredDetailSheet(
        entry: entry,
        onDelete: () async {
          final id = entry['id']?.toString();
          if (id == null) return;
          await ref.read(captureRecordsProvider.notifier).deleteById(id);
          if (context.mounted) {
            AppSnack.show(context, '记录已删除', kind: AppSnackKind.muted);
          }
        },
        onConvert: (idxs) => _onConvert(entry, idxs),
      ),
    );
    _activeEntry = null;
  }

  /// 转工单：构造 Defect → repo.addDefect → refreshDefects → 回写 status → Snack。
  /// 全部成功返回 `true`，弹层会就地标记 converted。
  Future<bool> _onConvert(
      Map<String, dynamic> entry, List<int> idxs) async {
    if (idxs.isEmpty) return false;
    final repo = ref.read(repositoryProvider);
    final defectsRaw = (entry['defects'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    final captureId = entry['id']?.toString() ?? '';

    for (final idx in idxs) {
      if (idx < 0 || idx >= defectsRaw.length) continue;
      final defect = buildDefectFromCaptureDefect(
        capture: entry,
        vlDefect: defectsRaw[idx],
        idx: idx,
      );
      await repo.addDefect(defect);
    }
    ref.invalidate(defectsProvider);
    for (final idx in idxs) {
      await ref
          .read(captureRecordsProvider.notifier)
          .markDefectConverted(captureId, idx);
    }
    if (mounted) {
      AppSnack.show(
        context,
        '已生成 ${idxs.length} 条缺陷工单',
        actionLabel: '去缺陷列表',
        onAction: () => context.push('/defects'),
        kind: AppSnackKind.success,
      );
    }
    return true;
  }

  // -------- 统计与筛选 --------

  _Stats _calcStats(
    List<Map<String, dynamic>> all,
    List<Map<String, dynamic>> filtered,
  ) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    var today = 0;
    var pending = 0;
    for (final e in all) {
      final ts = recordTsMillis(e);
      if (ts > 0 &&
          !DateTime.fromMillisecondsSinceEpoch(ts).isBefore(todayStart)) {
        today++;
      }
      final ds = e['defects'];
      if (ds is List) {
        for (final d in ds) {
          if (d is Map && (d['status']?.toString() ?? 'pending') != 'converted') {
            pending++;
          }
        }
      }
    }
    return _Stats(total: all.length, today: today, pending: pending);
  }

  List<String> _availableFloors(List<Map<String, dynamic>> records) {
    final s = <String>{};
    for (final e in records) {
      final f = e['floor']?.toString() ?? '';
      if (f.isNotEmpty) s.add(f);
    }
    final list = s.toList();
    list.sort();
    return list;
  }

  Future<void> _openFloorSheet(
      List<String> floors, CaptureRecordsFilter current) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => FilterSheet(
        availableFloors: floors,
        currentFloor: current.floor,
        currentAiOnly: current.aiOnly,
        onApply: ({required String? floor, required bool aiOnly}) {
          ref.read(captureRecordsFilterProvider.notifier).state =
              current.copyWith(
            floor: floor,
            aiOnly: aiOnly,
            clearFloor: floor == null,
          );
        },
      ),
    );
  }
}

class _Stats {
  final int total;
  final int today;
  final int pending;
  const _Stats(
      {required this.total, required this.today, required this.pending});
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onTakePhoto;
  const _EmptyState({required this.onTakePhoto});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(48),
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.clipboardCheck,
                  size: 36, color: AppTokens.muted),
            ),
            const SizedBox(height: 16),
            const Text('当前项目暂无验收记录',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.fg)),
            const SizedBox(height: 6),
            const Text('拍照后会自动归档到这里',
                style: TextStyle(fontSize: 12, color: AppTokens.muted)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onTakePhoto,
              style: FilledButton.styleFrom(
                backgroundColor: AppTokens.success,
                foregroundColor: AppTokens.onAccent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppTokens.radiusButton),
                ),
              ),
              icon: const Icon(LucideIcons.camera, size: 16),
              label: const Text('去拍照',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatchState extends StatelessWidget {
  final VoidCallback onReset;
  const _NoMatchState({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 60),
          const Icon(LucideIcons.filter,
              size: 32, color: AppTokens.muted),
          const SizedBox(height: 12),
          const Text('当前筛选条件下没有记录',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppTokens.fg2)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onReset,
            child: const Text('清除筛选',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.success)),
          ),
        ],
      ),
    );
  }
}