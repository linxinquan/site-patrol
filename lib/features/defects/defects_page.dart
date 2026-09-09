import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../core/storage/local_storage.dart';
import '../../core/utils/report_share.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_date_range_picker.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../shared/widgets/user_switcher.dart';
import '../../shared/widgets/user_switch_sheet.dart';
import '../../data/models.dart';
import '../../data/weekly_report.dart';
import 'report_builder.dart';
import 'report_docx.dart';
import 'report_pdf.dart';
import 'report_xlsx.dart';

/// 巡场清单页（对齐 Figma 新 UI：巡场问题列表页）。
/// 结构：标题栏(工单 + 导出/头像) → 状态分段(Frame 2131330677) → 操作卡(Frame 2147228092) → 缺陷卡列表。
/// "待设计师处置 / 待施工方回复"为独立二级页 DisposalReplyPage，由操作卡按钮跳转进入。
class DefectsPage extends ConsumerWidget {
  const DefectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(defectFilterProvider);
    final defects = ref.watch(defectsProvider);

    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 44,
        centerTitle: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Text('工单',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.fg,
                      height: 28 / 20)),
              const Spacer(),
              // Frame 2147228050：右侧两个 24×24 图标，gap 16，右对齐
              IconButton(
                icon: const Icon(MingCuteIcons.fileExportLine,
                    size: 24, color: AppTokens.fg),
                onPressed: () => _export(context, ref, defects),
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                focusColor: Colors.transparent,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
              const SizedBox(width: 16),
              const UserSwitcher(),
            ],
          ),
        ),
      ),
      body: AsyncState(
        value: defects,
        builder: (ds) {
          final list = ds
              .where((d) => filter == null || d.status == filter)
              .toList();
          const headerCount = 2; // 状态分段 + 操作卡
          final isEmpty = list.isEmpty;
          final itemCount = isEmpty
              ? headerCount + 2 // headers + 空状态卡 + OfflineBar
              : list.length + headerCount + 1; // headers + cards + OfflineBar

          return ListView.separated(
            primary: false,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            itemCount: itemCount,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              if (i == 0) return const _StatusSegmented();
              if (i == 1) return const _ActionCard();

              if (isEmpty) {
                if (i == headerCount) return const _EmptyState();
                return OfflineBar.defects;
              }

              final cardIndex = i - headerCount;
              if (cardIndex < list.length) return _DefectCard(list[cardIndex]);
              return OfflineBar.defects;
            },
          );
        },
      ),
    );
  }

  /// 导出报告：取当前项目缺陷 + 周报素材 → 选汇报周期 → 弹层选格式（PDF / Word / HTML）。
  Future<void> _export(BuildContext context, WidgetRef ref,
      AsyncValue<List<Defect>> defects) async {
    final all = defects.maybeWhen(
      data: (d) => d,
      orElse: () => const <Defect>[],
    );
    if (all.isEmpty) {
      AppSnack.show(context, '暂无可导出的缺陷记录', kind: AppSnackKind.muted);
      return;
    }
    final project = ref
        .read(projectProvider)
        .maybeWhen(data: (p) => p, orElse: () => null);
    final user = ref.read(currentUserProvider);
    final now = DateTime.now();
    final generatedAt =
        '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
        '${_pad(now.hour)}:${_pad(now.minute)}';
    final projectName = project?.name ?? '建筑验收项目';

    _showExportSheet(
      context,
      allDefects: all,
      initialRange: _defaultWeekRange(now),
      onPick: (format, range, list) => _runExport(
        context,
        ref,
        format,
        range: range,
        filtered: list,
        projectName: projectName,
        reporter: '${user.name} · ${user.org} · ${user.role}',
        generatedAt: generatedAt,
      ),
    );
  }

  /// 把周报引用的现场照片 + 巡场清单照片读成原始字节（缺失时报告内显示占位）。
  Future<Map<String, Uint8List>> _loadPhotoBytes(WeeklyReport report) async {
    final map = <String, Uint8List>{};
    for (final p in report.photos) {
      try {
        final data = await rootBundle.load(p.file);
        map[p.file] = data.buffer.asUint8List(
            data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        // 照片缺失：报告内渲染「照片未加载」占位
      }
    }
    // 缺陷现场照片：从本地存储读取（移动端 Documents / Web 会话内存）。
    for (final d in report.defects) {
      final rel = d.photoPath;
      if (rel == null || rel.isEmpty || map.containsKey(rel)) continue;
      try {
        final data = await LocalStorage.instance.readFile(rel);
        if (data != null) map[rel] = data;
      } catch (_) {
        // 读不到缺陷照片不阻断导出，报告内显示占位。
      }
    }
    return map;
  }

  /// 默认汇报周期：本周一（含）到今天（含），周报语义。
  DateTimeRange _defaultWeekRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: now.weekday - 1));
    return DateTimeRange(start: start, end: today);
  }

  /// 按汇报周期过滤缺陷：取 `Defect.ts` 前 10 位（yyyy-MM-dd）落在 [range] 内的记录；
  /// 时间戳无法解析的记录视为纳入，避免误丢。
  List<Defect> _filterByPeriod(List<Defect> all, DateTimeRange range) {
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    return all.where((d) {
      final ts = d.ts.trim();
      final date =
          ts.length >= 10 ? DateTime.tryParse(ts.substring(0, 10)) : null;
      if (date == null) return true;
      final day = DateTime(date.year, date.month, date.day);
      return !day.isBefore(start) && !day.isAfter(end);
    }).toList();
  }

  String _fmtDate(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
  String _fmtCompact(DateTime d) => '${d.year}${_pad(d.month)}${_pad(d.day)}';

  /// 导出方式弹层：选汇报周期 → PDF / Word / HTML 三选一（Web 另附「预览」入口）。
  void _showExportSheet(
    BuildContext context, {
    required List<Defect> allDefects,
    required DateTimeRange initialRange,
    required void Function(
            ReportExportFormat format, DateTimeRange range, List<Defect> defects)
        onPick,
  }) {
    final canExport = canExportReportFile;
    final today = DateTime.now();
    AppBottomSheet.show<void>(
      context: context,
      title: '导出现场工作汇报',
      isScrollControlled: true,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          var range = initialRange;
          final list = _filterByPeriod(allDefects, range);
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '报告自动整合现场照片、机电进度、台账与巡场清单，按周报版式排版，'
                  '可选 PDF / Word / HTML 三种格式，导出后无需再手工整理。',
                  style: const TextStyle(fontSize: 13, color: AppTokens.fg2),
                ),
                    const SizedBox(height: 12),
                    // 汇报周期选择（按缺陷发现时间过滤，周报语义）
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                        onTap: () async {
                          final picked = await AppDateRangePicker.show(
                            ctx,
                            firstDate: DateTime(2024, 1, 1),
                            lastDate:
                                DateTime(today.year, today.month, today.day),
                            initialRange: range,
                          );
                          if (picked != null) setSheet(() => range = picked);
                        },
                        child: Ink(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTokens.surface,
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusSm),
                          ),
                          child: Row(
                            children: [
                              const Icon(MingCuteIcons.calendarLine,
                                  size: 18, color: AppTokens.fg),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('汇报周期',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppTokens.fg2)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_fmtDate(range.start)} ~ ${_fmtDate(range.end)}',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppTokens.fg),
                                    ),
                                  ],
                                ),
                              ),
                              Text('${list.length}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTokens.fg)),
                              const SizedBox(width: 4),
                              const Icon(MingCuteIcons.rightLine,
                                  size: 18, color: AppTokens.muted),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (list.length != allDefects.length)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '已按周期过滤：全部 ${allDefects.length} 条中筛出 ${list.length} 条',
                          style: const TextStyle(
                              fontSize: 12, color: AppTokens.brand),
                        ),
                      ),
                    const SizedBox(height: 14),
                    for (final format in ReportExportFormat.values)
                      _formatTile(
                        ctx,
                        format,
                        enabled: list.isNotEmpty,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          onPick(format, range, list);
                        },
                      ),
                    if (!canExport)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('当前平台暂不支持导出，请在 Web 端使用该功能。',
                            style:
                                TextStyle(fontSize: 13, color: AppTokens.muted)),
                      ),
                  ],
                ),
              );
        },
      ),
    );
  }

  /// 单个格式选项卡片（弹层内，按设计稿 Frame 2147228009：40×40 彩色图标 chip + 标题/副文）。
  Widget _formatTile(
      BuildContext ctx, ReportExportFormat format,
      {required VoidCallback onTap, bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            onTap: enabled ? onTap : null,
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppTokens.surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Color(format.colorHex),
                      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    ),
                    child: const Icon(MingCuteIcons.fileFill,
                        size: 24, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(format.label,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 24 / 16,
                                color: AppTokens.fg)),
                        const SizedBox(height: 2),
                        Text(format.subtitle,
                            style: const TextStyle(
                                fontSize: 12,
                                height: 20 / 12,
                                color: AppTokens.muted)),
                      ],
                    ),
                  ),
                  const Icon(MingCuteIcons.rightLine,
                      size: 16, color: AppTokens.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 生成 + 导出（含格式转换与字体加载；PDF 首次解析字体约 7MB）。
  Future<void> _runExport(
    BuildContext context,
    WidgetRef ref,
    ReportExportFormat format, {
    required DateTimeRange range,
    required List<Defect> filtered,
    required String projectName,
    required String reporter,
    required String generatedAt,
  }) async {
    if (!canExportReportFile) {
      AppSnack.show(context, '当前平台暂不支持导出，请在 Web 端使用该功能',
          kind: AppSnackKind.muted);
      return;
    }
    if (filtered.isEmpty) {
      AppSnack.show(context, '所选周期内暂无缺陷记录，请调整汇报周期',
          kind: AppSnackKind.muted);
      return;
    }
    final report = ref.read(weeklyReportProvider).copyWithDefects(filtered);
    final photoBytes = await _loadPhotoBytes(report);
    if (!context.mounted) return;
    final baseName =
        '现场工作汇报_${_sanitize(projectName)}_${_fmtCompact(range.start)}-${_fmtCompact(range.end)}';
    _showBusy(context, format);
    try {
      final (filename, mimeType, bytes) = await _buildExportFile(
        ref,
        format,
        report,
        reporter: reporter,
        generatedAt: generatedAt,
        photoBytes: photoBytes,
        baseName: baseName,
      );
      final saved = await exportReportFile(filename, mimeType, bytes);
      if (!context.mounted) return;
      AppSnack.show(
        context,
        saved == null ? '报告已导出：$filename' : '报告已保存：$saved',
        kind: AppSnackKind.success,
      );
    } catch (e) {
      if (context.mounted) {
        AppSnack.show(context, '导出失败：$e', kind: AppSnackKind.danger);
      }
    } finally {
      if (context.mounted) _dismissBusy(context);
    }
  }

  /// 按所选格式生成目标字节。
  Future<(String, String, Uint8List)> _buildExportFile(
    WidgetRef ref,
    ReportExportFormat format,
    WeeklyReport report, {
    required String reporter,
    required String generatedAt,
    required Map<String, Uint8List> photoBytes,
    required String baseName,
  }) async {
    switch (format) {
      case ReportExportFormat.xlsx:
        final bytes = buildWeeklyReportXlsx(
          report,
          reporter: reporter,
          generatedAt: generatedAt,
        );
        return (
          '$baseName.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          bytes,
        );
      case ReportExportFormat.pdf:
        final font = await ref.read(reportFontProvider.future);
        final bytes = await buildWeeklyReportPdf(
          report,
          reporter: reporter,
          generatedAt: generatedAt,
          photoBytes: photoBytes,
          font: font,
        );
        return ('$baseName.pdf', 'application/pdf', bytes);
      case ReportExportFormat.docx:
        final bytes = buildWeeklyReportDocx(
          report,
          reporter: reporter,
          generatedAt: generatedAt,
          photoBytes: photoBytes,
        );
        return (
          '$baseName.docx',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          bytes,
        );
      case ReportExportFormat.html:
        final html = buildWeeklyReportHtml(
          report,
          reporter: reporter,
          generatedAt: generatedAt,
          photoBase64: photoBytes
              .map((k, v) => MapEntry(k, base64Encode(v))),
        );
        return (
          '$baseName.html',
          'text/html; charset=utf-8',
          Uint8List.fromList(utf8.encode(html)),
        );
    }
  }

  /// 生成中蒙层：不可关闭，防重复点击。
  void _showBusy(BuildContext context, ReportExportFormat format) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(width: 16),
                Text('正在生成 ${format.label} 报告…',
                    style:
                        const TextStyle(fontSize: 14, color: AppTokens.fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 关闭生成中蒙层。
  void _dismissBusy(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

/// 「处置与回复」独立二级页（设计稿 Frame 2147228094）：
/// - 状态栏 47 + 导航栏 44（AppBar）：左箭头 + 居中标题「处置与回复」
/// - 状态分段（Frame 2131330677 两个分段）：待设计师处置 / 待施工方回复
/// - 缺陷卡片列表（沿用 _DefectCard，含状态标签 + 备注）
///
/// kind = 'designer' 默认进入「待设计师处置」；kind = 'reply' 默认进入「待施工方回复」。
/// 段内可自由切换两段，本地状态管，不污染主页筛选。
class DisposalReplyPage extends ConsumerStatefulWidget {
  final String kind; // 'designer' | 'reply'
  const DisposalReplyPage({super.key, required this.kind});

  @override
  ConsumerState<DisposalReplyPage> createState() => _DisposalReplyPageState();
}

class _DisposalReplyPageState extends ConsumerState<DisposalReplyPage> {
  late String _kind;

  @override
  void initState() {
    super.initState();
    _kind = widget.kind;
  }

  bool _match(Defect d) => _kind == 'designer'
      ? d.pendingDesignerDisposal
      : (d.reply ?? '').isEmpty;

  @override
  Widget build(BuildContext context) {
    final defects = ref.watch(defectsProvider);
    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 44,
        centerTitle: true,
        leadingWidth: 36,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: NavIconButton(
            icon: MingCuteIcons.leftLine,
            color: AppTokens.fg,
            onPressed: () => context.pop(),
          ),
        ),
        title: const Text('处置与回复',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF000000),
                height: 24 / 16)),
      ),
      body: AsyncState(
        value: defects,
        builder: (ds) {
          final list = ds.where(_match).toList();
          return ListView.separated(
            primary: false,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            itemCount: list.isEmpty ? 3 : list.length + 2,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              if (i == 0) return _DisposalSegmented(
                selected: _kind,
                onChanged: (v) => setState(() => _kind = v),
              );
              if (list.isEmpty) {
                if (i == 1) {
                  return _EmptyState(
                    hint: _kind == 'designer'
                        ? '暂无待设计师处置的工单'
                        : '暂无待施工方回复的工单',
                  );
                }
                return OfflineBar.defects;
              }
              if (i - 1 < list.length) return _DefectCard(list[i - 1]);
              return OfflineBar.defects;
            },
          );
        },
      ),
    );
  }
}

/// 「处置与回复」状态分段（设计稿 Frame 2131330677 两个分段版本）：
/// 灰色轨道 #E9EAEB 内 padding 2 / gap 2；选中白底 + #202224 文字；
/// 未选透明底 + #919499 文字；均 14/W500，圆角 6。
class _DisposalSegmented extends StatelessWidget {
  final String selected; // 'designer' | 'reply'
  final ValueChanged<String> onChanged;
  const _DisposalSegmented({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EAEB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DisposalSegBtn(
              label: '待设计师处置',
              selected: selected == 'designer',
              onTap: () => onChanged('designer'),
            ),
          ),
          Expanded(
            child: _DisposalSegBtn(
              label: '待施工方回复',
              selected: selected == 'reply',
              onTap: () => onChanged('reply'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisposalSegBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DisposalSegBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              height: 22 / 14,
              fontWeight: FontWeight.w500,
              color: selected
                  ? const Color(0xFF202224)
                  : const Color(0xFF919499),
            ),
          ),
        ),
      );
}

/// 状态分段控件（设计稿 Frame 2131330677）：灰色轨道 + 五个等宽分段。
/// 选中 = 白底 + 品牌蓝字 #0395FF；未选 = 透明底 + 辅助灰字 #B5B9BF；均 14/W500。
class _StatusSegmented extends ConsumerWidget {
  const _StatusSegmented();

  static const _options = [
    (null, '全部'),
    (DefectStatus.draft, '待整改'),
    (DefectStatus.doing, '整改中'),

    (DefectStatus.done, '已销项'),
    (DefectStatus.reject, '已拒绝'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(defectFilterProvider);
    void tap(DefectStatus? s) {
      ref.read(defectFilterProvider.notifier).state = filter == s ? null : s;
    }

    return Container(
      width: double.infinity,
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EAEB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (final (s, label) in _options) ...[
            Expanded(
              child: _SegBtn(
                label: label,
                selected: s == filter,
                onTap: () => tap(s),
              ),
            ),
            if (s != _options.last.$1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}

/// 单个分段（Frame 2131330677 小按钮）：选中白底、未选透明；圆角 6，高 30，等分拉伸。
class _SegBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              height: 22 / 14,
              fontWeight: FontWeight.w500,
              // 选中 #202224 / 未选 #919499（用户指定，区别于品牌蓝与浅灰）
              color: selected
                  ? const Color(0xFF202224)
                  : const Color(0xFF919499),
            ),
          ),
        ),
      );
}

/// 空数据缺省态：白卡 + 图标 + 文案，避免空列表时露出一大片灰底像 Bug。
class _EmptyState extends StatelessWidget {
  final String? hint;
  const _EmptyState({this.hint});

  String get _text => hint ?? '暂无工单';

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(MingCuteIcons.inboxLine, size: 40, color: AppTokens.muted),
            const SizedBox(height: 12),
            Text(
              _text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 22 / 14,
                fontWeight: FontWeight.w400,
                color: AppTokens.muted,
              ),
            ),
          ],
        ),
      );
}

/// 工单页顶部操作卡（设计稿 Frame 2147228092）：白卡列布局，padding 12，行间距 12。
/// 上：身份信息（头像 + 姓名 + 角色标签） + 右侧「切换身份」；
/// 下：两个等分行动按钮（待设计师处置 / 待施工方回复），点击进入对应筛选二级页。
class _ActionCard extends ConsumerWidget {
  const _ActionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final role = user.role.isNotEmpty ? user.role : '设计管理';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 行1：身份（头像 + 姓名 + 角色标签）…… 切换身份
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _identityAvatar(user.avatar, 24),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 22 / 14,
                              color: Color(0xFF202224))),
                    ),
                    const SizedBox(width: 8),
                    // 角色标签（品牌蓝 5% 底 + 品牌蓝字）
                    Container(
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: const Color(0x0D0395FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(role,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 20 / 12,
                                color: Color(0xFF0395FF))),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 切换身份（灰底按钮）
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showUserSwitchSheet(context, ref),
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Text('切换身份',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 20 / 12,
                            color: Color(0xFF60656B))),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 行2：两个等分行动按钮（待设计师处置 / 待施工方回复）
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  icon: MingCuteIcons.penLine,
                  label: '待设计师处置',
                  onTap: () => context.push('/defects/disposal/designer'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionBtn(
                  icon: MingCuteIcons.comment2Line,
                  label: '待施工方回复',
                  onTap: () => context.push('/defects/disposal/reply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 行动按钮（Frame 2147228091 小按钮）：品牌蓝 5% 底，居中图标 16 + 文字 14/w400/#60656B。
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0x0D0395FF), // rgba(3,149,255,0.05)
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: const Color(0xFF60656B)),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 22 / 14,
                      color: Color(0xFF60656B))),
            ],
          ),
        ),
      );
}

/// 圆形头像（24/32 通用，无图则灰底）。
Widget _identityAvatar(String avatar, double size) {
  if (avatar.isEmpty) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFD9D9D9),
        shape: BoxShape.circle,
      ),
    );
  }
  return ClipOval(
    child: Image.asset(
      avatar,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        color: const Color(0xFFD9D9D9),
      ),
    ),
  );
}

/// 缺陷卡片（设计稿 Frame 2131330687 等）：
/// 标题行(16/600 + 右侧状态标签) → 字段区(缺陷类型/严重程度/缺陷位置/记录人/发现时间/责任人，14) → 备注块(#F4F6F7 圆角 8)。
class _DefectCard extends StatelessWidget {
  final Defect d;
  const _DefectCard(this.d);

  /// 严重程度文本色（规范分区色）：严重 #FF4444 / 较重 #FF9500 / 一般 #FF9500 / 轻微 #34C759。
  /// 注：设计稿 Frame 2147228012 中「一般」档取值为 #FF9500（与较重同橙），故 yellow 档对齐使用 warning。
  static Color _severityColor(DefectSeverity s) {
    switch (s) {
      case DefectSeverity.red:
        return const Color(0xFF4444);
      case DefectSeverity.orange:
        return AppTokens.warning;
      case DefectSeverity.yellow:
        return AppTokens.warning;
      case DefectSeverity.green:
        return AppTokens.success;
    }
  }

  /// 字段行：名称固定 56 宽（辅助灰 #919499）+ 与值间隔 16 + 值（次级文字 #60656B / 严重度带色），行高 22。
  Widget _field(String name, String value, {Color? valueColor}) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14, color: AppTokens.muted, height: 22 / 14)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14,
                color: valueColor ?? AppTokens.fg2,
                height: 22 / 14),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AppCard(
        radius: AppTokens.radiusSm,
        onTap: () => context.push('/defects/record/${d.id}'),
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题行：名称 + 右侧状态标签
            Row(
              children: [
                Expanded(
                  child: Text(
                    d.part,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppTokens.fg),
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(status: d.status),
              ],
            ),
            const SizedBox(height: 8),
            // 字段区
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field('问题缺陷', d.type),
                const SizedBox(height: 6),
                _field('严重程度', d.severity.label,
                    valueColor: _severityColor(d.severity)),
                const SizedBox(height: 6),
                _field('缺陷位置', d.anchor),
                const SizedBox(height: 6),
                _field('记录人', d.reporter),
                const SizedBox(height: 6),
                _field('发现时间', d.ts),
                const SizedBox(height: 6),
                _field('责任人', d.resp),
              ],
            ),
            const SizedBox(height: 8),
            // 备注块（灰底内嵌，文字左对齐、次级灰）
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Text(
                d.note,
                style: const TextStyle(
                    fontSize: 14, color: AppTokens.fg2, height: 22 / 14),
              ),
            ),
            // 任务4：设计师处置结果条（处置过才显示）
            if (d.designerAction != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0x120395FF),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Text(
                  '设计师${d.designerActionLabel} · ${d.designerBy ?? ''}'
                  '${(d.designerNote ?? '').isNotEmpty ? '：${d.designerNote}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF0395FF)),
                ),
              ),
            ],
            // 任务5：整改回复块（已回复才显示，设计稿 Frame 2131330685）：
            // 浅蓝底 rgba(3,149,255,0.05) = 0x0D0395FF、圆角 8、内边距 8、纵向间距 8。
            // 顶行 space-between：左 回复人（单位+姓名 14/fg2） / 右「整改 回复：」；
            // 中部回复正文（14/fg，自动换行自适应）；底部时间（12/muted）。
            if ((d.reply ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTokens.space2),
                decoration: BoxDecoration(
                  color: const Color(0x0D0395FF),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            d.replyBy ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 22 / 14,
                              color: AppTokens.fg2,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTokens.space4),
                        const Text(
                          '整改 回复：',
                          style: TextStyle(
                            fontSize: 14,
                            height: 22 / 14,
                            color: AppTokens.fg2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.space2),
                    Text(
                      d.reply ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 22 / 14,
                        color: AppTokens.fg,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space2),
                    Text(
                      d.replyTs ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 20 / 12,
                        color: AppTokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}

/// 两位补零。
String _pad(int n) => n.toString().padLeft(2, '0');

/// 清理文件名非法字符（Windows / 文件名通用）。
String _sanitize(String s) => s
    .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '_');

/// 缺陷状态标签（设计稿 Frame 2131330662：实色底白字，圆角 6，12/500，高 22）。
///   draft  → 待整改（红 #FF4444）
///   doing  → 整改中（橙 #FF9500）
///   done   → 已销项（绿 #00B84A）
///   reject → 已拒绝（品牌蓝 #0395FF）
class StatusPill extends StatelessWidget {
  final DefectStatus status;
  const StatusPill({super.key, required this.status});

  Color get _bg {
    switch (status) {
      case DefectStatus.draft:
        return const Color(0xFF4444);
      case DefectStatus.doing:
        return AppTokens.warning;
      case DefectStatus.done:
        return const Color(0xFF00B84A);
      case DefectStatus.reject:
        return AppTokens.brand;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 22,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status.label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 12,
              height: 20 / 12,
              fontWeight: FontWeight.w500,
              leadingDistribution: TextLeadingDistribution.even,
              color: AppTokens.surface),
        ),
      );
}
