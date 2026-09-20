import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/storage/report_record_store.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/nav_icon_button.dart';

/// 巡场报告归档页：列出当前项目**已生成**的巡场报告。
///
/// 入口：首页快捷操作「巡场报告」（路由 `/patrol-reports`）。
/// 数据：[reportRecordsProvider]（LocalStorage 归档；无归档时回退演示种子）。
/// 收录：问题清单页「导出报告」成功后自动写入一条归档（按标题 + 周期合并格式）。
///
/// 列表只呈现元数据（报告名 / 周期 / 格式 / 问题统计）；点卡片看详情与删除，
/// 需要报告原件时回问题清单页重新导出 —— 报告正文（含照片）体积大，不入本地归档。
class PatrolReportsPage extends ConsumerStatefulWidget {
  const PatrolReportsPage({super.key});

  @override
  ConsumerState<PatrolReportsPage> createState() => _PatrolReportsPageState();
}

class _PatrolReportsPageState extends ConsumerState<PatrolReportsPage> {
  @override
  void initState() {
    super.initState();
    // 每次进入重读本地归档：刚在问题清单页导出的报告要立刻出现在列表里。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(reportRecordsProvider);
    });
  }

  /// 删除一条归档（仅删除留痕，不影响已导出的报告文件）。
  Future<void> _confirmDelete(ReportRecord r) async {
    final ok = await AppDialog.show<bool>(
      context: context,
      title: '删除归档',
      description: '确定删除「${r.period}」这份报告归档？已导出的报告文件不受影响。',
      actions: AppDialogActions(
        children: [
          AppDialogButton.secondary(
            label: '取消',
            onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
          ),
          AppDialogButton.danger(
            label: '删除',
            onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ReportRecordStore.delete(r.projectId, r.id);
    ref.invalidate(reportRecordsProvider);
    if (mounted) {
      AppSnack.show(context, '已删除报告归档', kind: AppSnackKind.muted);
    }
  }

  /// 报告详情弹层：完整元数据 + 删除入口。
  void _showDetail(ReportRecord r) {
    AppBottomSheet.show(
      context: context,
      title: '报告详情',
      body: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in <(String, String)>[
                  ('报告名称', r.title),
                  ('项目', r.projectName),
                  ('汇报周期', r.period),
                  ('编制人', r.reporter),
                  ('生成时间', _fmtDateTime(r.createdAt)),
                  ('导出格式', r.formats.isEmpty ? '—' : r.formats.join(' · ')),
                  (
                    '问题统计',
                    '共 ${r.defectCount} 条 · 未闭环 ${r.openCount} · '
                        '已闭环 ${r.doneCount} · 重要紧急 ${r.urgentCount}'
                  ),
                  if (r.note.trim().isNotEmpty) ('巡场小结', r.note.trim()),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.space2),
                    child: _kvRow(e.$1, e.$2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          SizedBox(
            height: AppTokens.buttonH_lg,
            child: Material(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _confirmDelete(r);
                },
                child: const Center(
                  child: Text(
                    '删除归档',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 24 / 16,
                      color: AppTokens.danger,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.space2),
          const Text(
            '需要报告原件时，回问题清单页重新导出即可（PDF / Word / Excel / 网页）。',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 20 / 12,
              color: AppTokens.muted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(reportRecordsProvider);

    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        centerTitle: true,
        title: const Text('巡场报告',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTokens.fg)),
        leadingWidth: 36,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: NavIconButton(icon: MingCuteIcons.leftLine),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTokens.accent,
        foregroundColor: AppTokens.onAccent,
        elevation: 2,
        onPressed: () => context.go('/defects'),
        icon: const Icon(MingCuteIcons.fileExportLine, size: 18),
        label: const Text('生成报告',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: AsyncState(
          value: reports,
          builder: (list) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(reportRecordsProvider),
            child: list.isEmpty
                ? _EmptyState(onExport: () => context.go('/defects'))
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                        AppTokens.space3, AppTokens.space3, AppTokens.space3, 96),
                    children: [
                      _ArchiveHint(count: list.length),
                      const SizedBox(height: AppTokens.space3),
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppTokens.space3),
                        _ReportCard(
                          record: list[i],
                          onTap: () => _showDetail(list[i]),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 归档说明卡：当前项目共几份报告 + 说明「导出后自动收录」。
class _ArchiveHint extends StatelessWidget {
  final int count;
  const _ArchiveHint({required this.count});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTokens.brandTint,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: const Icon(MingCuteIcons.clipboardLine,
                  size: 18, color: AppTokens.brand),
            ),
            const SizedBox(width: AppTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('当前项目报告归档',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 22 / 14,
                          color: AppTokens.fg)),
                  const SizedBox(height: 2),
                  Text(
                    '共 $count 份。在问题清单页导出报告后自动收录，点开可查看统计与删除归档。',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 20 / 12,
                        color: AppTokens.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// 单份报告卡：图标 + 标题/周期 + 问题统计标签 + 生成时间/编制人。
class _ReportCard extends StatelessWidget {
  final ReportRecord record;
  final VoidCallback onTap;
  const _ReportCard({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTokens.brandTint,
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  child: const Icon(MingCuteIcons.clipboardLine,
                      size: 18, color: AppTokens.brand),
                ),
                const SizedBox(width: AppTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(record.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 22 / 14,
                              color: AppTokens.fg)),
                      const SizedBox(height: 2),
                      Text('汇报周期 ${record.period}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              height: 20 / 12,
                              color: AppTokens.muted)),
                    ],
                  ),
                ),
                const Icon(MingCuteIcons.rightLine,
                    size: 18, color: Color(0xFFB9BFCC)),
              ],
            ),
            const SizedBox(height: AppTokens.space3),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _statTag('问题 ${record.defectCount}', AppTokens.brand,
                    AppTokens.brandTint),
                if (record.openCount > 0)
                  _statTag('未闭环 ${record.openCount}', AppTokens.danger,
                      AppTokens.dangerTint),
                _statTag('已闭环 ${record.doneCount}', AppTokens.success,
                    AppTokens.successTint),
                if (record.urgentCount > 0)
                  _statTag('重要紧急 ${record.urgentCount}', AppTokens.warning,
                      AppTokens.warningTint),
                for (final f in record.formats)
                  _statTag(f, AppTokens.muted, AppTokens.surface2),
              ],
            ),
            const SizedBox(height: AppTokens.space2),
            Row(
              children: [
                Expanded(
                  child: Text('生成于 ${_fmtDateTime(record.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 20 / 12,
                          color: AppTokens.muted)),
                ),
                const SizedBox(width: AppTokens.space3),
                Flexible(
                  child: Text(record.reporter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 20 / 12,
                          color: AppTokens.muted)),
                ),
              ],
            ),
          ],
        ),
      );
}

/// 空态：提示去问题清单页导出报告（回收站式空卡，可下拉刷新）。
class _EmptyState extends StatelessWidget {
  final VoidCallback onExport;
  const _EmptyState({required this.onExport});

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTokens.space3),
        children: [
          const SizedBox(height: AppTokens.space6),
          AppCard(
            padding: const EdgeInsets.all(AppTokens.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppTokens.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(MingCuteIcons.clipboardLine,
                      size: 28, color: AppTokens.muted),
                ),
                const SizedBox(height: AppTokens.space3),
                const Text('暂无巡场报告',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 24 / 16,
                        color: AppTokens.fg)),
                const SizedBox(height: 4),
                const Text(
                  '在问题清单页导出报告（PDF / Word / Excel / 网页）后，会自动收录到这里',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 20 / 12,
                      color: AppTokens.muted),
                ),
                const SizedBox(height: AppTokens.space4),
                AppButton(
                  label: '去导出报告',
                  size: AppButtonSize.lg,
                  width: double.infinity,
                  onPressed: onExport,
                ),
              ],
            ),
          ),
        ],
      );
}

/// 统计标签：原色文字 + 原色 5% 浅底（灰标签用 surface2 实色底）。
Widget _statTag(String label, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          maxLines: 1,
          strutStyle: const StrutStyle(
              fontSize: 12, height: 20 / 12, forceStrutHeight: true),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 20 / 12,
              color: fg)),
    );

/// 详情弹层的一行「标签 : 值」。
Widget _kvRow(String label, String value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 68,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 20 / 12,
                  color: AppTokens.muted)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 20 / 12,
                  color: AppTokens.fg)),
        ),
      ],
    );

/// `2025-08-18 09:20`。
String _fmtDateTime(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String p(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}
