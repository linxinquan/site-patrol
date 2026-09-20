import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../data/repository/mock_repository.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../capture/capture_page.dart' show StoredDetailSheet;
import 'capture_records_controller.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/filter_tabs.dart';
import 'widgets/grouped_grid.dart';
import 'widgets/stats_strip.dart';

/// 验收记录事后工作台：当前项目全部拍照验收记录的浏览、筛选、追溯与转入问题清单。
///
/// 入口：首页 8 宫格「验收记录」卡片（`/capture-records`）。
/// 数据：[captureRecordsProvider] 按当前项目图纸 key 过滤 + ts 倒序。
/// 转入问题清单：[onConvert] 回调调用 [Repository.addDefect] → [refreshDefects] →
/// [CaptureRecordsNotifier.markDefectConverted] → [AppSnack]。
class CaptureRecordsPage extends ConsumerStatefulWidget {
  const CaptureRecordsPage({super.key});

  @override
  ConsumerState<CaptureRecordsPage> createState() => _CaptureRecordsPageState();
}

class _CaptureRecordsPageState extends ConsumerState<CaptureRecordsPage> {
  final Set<String> _collapsedGroups = {};

  @override
  void initState() {
    super.initState();
    // 每次进入页面都重读 LocalStorage（拍照页保存的新记录、其他页面写回的
    // 转入问题清单状态等），避免 provider 缓存导致列表过时。
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

    final stats = _calcStats(records);
    final floors = _availableFloors(records);

    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        centerTitle: true,
        title: const Text('验收记录',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTokens.fg)),
        leadingWidth: 36,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: NavIconButton(
            icon: MingCuteIcons.leftLine,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTokens.accent,
        foregroundColor: AppTokens.onAccent,
        elevation: 2,
        onPressed: () => context.push('/capture'),
        icon: const Icon(MingCuteIcons.cameraLine, size: 18),
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
                      // 统一正文首块内容与导航栏底部保持 12 的间距。
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: AppCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppTokens.brandTint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                MingCuteIcons.package2Line,
                                size: 18,
                                color: AppTokens.brand,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '当前项目验收归档',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      height: 22 / 14,
                                      color: AppTokens.fg,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '按时间、楼层和 AI 识别结果快速筛选，点开单条记录可继续转入问题清单',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      height: 20 / 12,
                                      color: AppTokens.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(
                          top: AppTokens.space2, bottom: AppTokens.space3),
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
                          ref
                              .read(captureRecordsFilterProvider.notifier)
                              .state = const CaptureRecordsFilter();
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
                        onTapEntry: (entry) => _openDetail(context, entry),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
      ),
    );
  }

  // -------- 弹层与回调 --------

  Future<void> _openDetail(
    BuildContext context,
    Map<String, dynamic> entry,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
        onConvertNote: () => _onConvertNote(entry),
      ),
    );
  }

  /// 转入问题清单：构造 Defect → repo.addDefect → refreshDefects → 回写 status → Snack。
  /// 全部成功返回 `true`，弹层会就地标记 converted。
  Future<bool> _onConvert(Map<String, dynamic> entry, List<int> idxs) async {
    if (idxs.isEmpty) return false;
    final repo = ref.read(repositoryProvider);
    // 归入当前项目，避免新增记录串到另一个项目。
    // 原在 CapturePage 保存时设置；2026-09-18 保存不再自动建缺陷后，改在转入这里设置
    // —— 必须早于 addDefect，否则 MockRepository 会按上一次的 is7 标记归档。
    if (repo is MockRepository) {
      repo.currentIs7 = ref.read(is7DongProjectProvider);
    }
    final defectsRaw = (entry['defects'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    final captureId = entry['id']?.toString() ?? '';
    // 旧记录可能没有 projectId：用当前项目兜底，保证转入的缺陷有项目归属。
    final projectId = ref.read(activeProjectIdProvider);

    try {
      for (final idx in idxs) {
        if (idx < 0 || idx >= defectsRaw.length) continue;
        final defect = buildDefectFromCaptureDefect(
          capture: entry,
          vlDefect: defectsRaw[idx],
          idx: idx,
          projectIdOverride: projectId,
        );
        await repo.addDefect(defect);
      }
      ref.invalidate(defectsProvider);
      for (final idx in idxs) {
        await ref
            .read(captureRecordsProvider.notifier)
            .markDefectConverted(captureId, idx);
      }
    } catch (e) {
      // 写入中断（本地存储不可用等）：明确提示失败，让用户可重试。
      // 未写成功的「已转入」标记会让记录继续显示 pending，重复点击不会产生重复缺陷
      //（Defect id 为 `<captureId>#<idx>`，问题清单按 id 去重）。
      if (mounted) {
        AppSnack.show(context, '转入问题清单失败：$e', kind: AppSnackKind.danger);
      }
      return false;
    }
    if (mounted) {
      AppSnack.show(
        context,
        '已生成 ${idxs.length} 条问题记录',
        actionLabel: '去问题清单',
        onAction: () => context.push('/defects'),
        kind: AppSnackKind.success,
      );
    }
    return true;
  }

  /// 按描述转入（DV-16）：AI 未识别到缺陷时，用手写的问题描述生成 1 条问题记录。
  /// 以 `sourceCaptureIdx = -1` 标记，与逐条转入（0..n）区分；id 稳定 → 重复点击幂等。
  Future<bool> _onConvertNote(Map<String, dynamic> entry) async {
    final record = CaptureRecord.fromJson(entry);
    final note = record.note.trim();
    if (note.isEmpty) {
      if (mounted) {
        AppSnack.show(context, '请先在验收记录里填写问题描述',
            kind: AppSnackKind.muted);
      }
      return false;
    }
    final repo = ref.read(repositoryProvider);
    if (repo is MockRepository) {
      repo.currentIs7 = ref.read(is7DongProjectProvider);
    }
    final captureId = record.id;
    final projectId = ref.read(activeProjectIdProvider);
    final firstLine = note.split('\n').first.trim();
    try {
      await repo.addDefect(Defect(
        id: '$captureId#note',
        projectId:
            projectId.isNotEmpty ? projectId : record.projectId,
        part: record.anchor.isEmpty ? '验收点' : record.anchor,
        type: firstLine.length > 20 ? firstLine.substring(0, 20) : firstLine,
        category: DefectCategory.other,
        severity: DefectSeverity.orange,
        status: DefectStatus.draft,
        anchor: record.anchor,
        floor: record.floor,
        ts: record.ts,
        gps: record.gps,
        alt: record.alt,
        resp: '',
        reporter: record.reporter.isEmpty ? '验收记录' : record.reporter,
        tags: ['验收转工单', '验收#$captureId'],
        note: note,
        seed: 'capture_convert',
        drawingKey: record.drawingKey.isEmpty ? null : record.drawingKey,
        worldX: record.worldX,
        worldY: record.worldY,
        photos: record.photo == null ? const [] : [record.photo!],
        photoPath: record.photo,
        sourceCaptureId: captureId,
        sourceCaptureIdx: -1,
        sync: SyncMeta.create(),
      ));
      ref.invalidate(defectsProvider);
    } catch (e) {
      if (mounted) {
        AppSnack.show(context, '转入问题清单失败：$e', kind: AppSnackKind.danger);
      }
      return false;
    }
    if (mounted) {
      AppSnack.show(
        context,
        '已按描述生成 1 条问题记录',
        actionLabel: '去问题清单',
        onAction: () => context.push('/defects'),
        kind: AppSnackKind.success,
      );
    }
    return true;
  }

  // -------- 统计与筛选 --------

  /// 统计口径：三项均为「当前项目全量」，与页面上的时间 / 楼层 / AI 筛选无关。
  /// （原第二参数 `filtered` 从未被使用，2026-09-18 清理死参数。）
  _Stats _calcStats(List<Map<String, dynamic>> all) {
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
          if (d is Map &&
              (d['status']?.toString() ?? 'pending') != 'converted') {
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
    await AppBottomSheet.show<void>(
      context: context,
      title: '筛选',
      body: (_) => FilterSheet(
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
              child: const Icon(MingCuteIcons.clipboardLine,
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
                backgroundColor: AppTokens.accent,
                foregroundColor: AppTokens.onAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusButton),
                ),
              ),
              icon: const Icon(MingCuteIcons.cameraLine, size: 16),
              label: const Text('去拍照',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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
          const Icon(MingCuteIcons.filterLine,
              size: 32, color: AppTokens.muted),
          const SizedBox(height: 12),
          const Text('当前筛选条件下没有记录',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.fg2)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onReset,
            child: const Text('清除筛选',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.accent)),
          ),
        ],
      ),
    );
  }
}
