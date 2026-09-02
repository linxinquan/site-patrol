import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../core/storage/local_storage.dart';
import '../../core/utils/open_web.dart';
import '../../core/utils/report_export.dart';
import '../../core/utils/report_share.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../shared/widgets/user_switcher.dart';
import '../../data/models.dart';
import '../../data/weekly_report.dart';
import 'report_builder.dart';
import 'report_docx.dart';
import 'report_pdf.dart';

/// 巡场清单页（对齐 Figma 新 UI：巡场问题列表页）。
/// 结构：标题栏(巡场清单·N / F9·闭环管理 + 头像) → 筛选条(5 等分按钮) → 缺陷卡列表。
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
        titleSpacing: 12,
        title: const Text('工单',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTokens.fg,
                height: 28 / 20)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: IconButton(
              tooltip: '导出报告',
              icon: const Icon(MingCuteIcons.fileExportLine,
                  size: 20, color: AppTokens.fg),
              onPressed: () => _export(context, ref, defects),
            ),
          ),
          // 头像：与首页一致，点击弹出用户列表切换身份
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: UserSwitcher(),
          ),
        ],
      ),
      body: AsyncState(
        value: defects,
        builder: (ds) {
          final list = filter == null
              ? ds
              : ds.where((d) => d.status == filter).toList();
          // 筛选条作为列表首个 item，随内容滚动（不吸顶）；间距统一 8。
          return ListView.separated(
            primary: false,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            itemCount: list.length + 2, // 筛选条 + 卡片 + OfflineBar
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              if (i == 0) return _FilterChips(current: filter);
              if (i == list.length + 1) return OfflineBar.defects;
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 72),
                  child: Center(
                    child: Text('该状态下暂无缺陷',
                        style: TextStyle(color: AppTokens.muted)),
                  ),
                );
              }
              return _DefectCard(list[i - 1]);
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
      onPreview: (range, list) => _previewHtml(
        ref,
        range,
        filtered: list,
        reporter: '${user.name} · ${user.org} · ${user.role}',
        generatedAt: generatedAt,
        projectName: projectName,
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
    required void Function(DateTimeRange range, List<Defect> defects)
        onPreview,
  }) {
    final canPreview = canOpenWebWindow;
    final canExport = canExportReportFile;
    final today = DateTime.now();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTokens.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          var range = initialRange;
          final list = _filterByPeriod(allDefects, range);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('导出现场工作汇报',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.fg)),
                    const SizedBox(height: 8),
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
                          final picked = await showDateRangePicker(
                            context: ctx,
                            firstDate: DateTime(2024, 1, 1),
                            lastDate:
                                DateTime(today.year, today.month, today.day),
                            initialDateRange: range,
                            helpText: '选择汇报周期（按缺陷发现时间过滤）',
                            saveText: '确定',
                          );
                          if (picked != null) setSheet(() => range = picked);
                        },
                        child: Ink(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTokens.surface,
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusLg),
                            border: Border.all(color: AppTokens.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(MingCuteIcons.calendarLine,
                                  size: 18, color: AppTokens.brand),
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
                              Text('${list.length} 条',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTokens.brand)),
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
                              fontSize: 12, color: AppTokens.muted),
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
                    if (canPreview)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: AppButton(
                          label: '下载 HTML 报告（浏览器打开后可另存为 PDF）',
                          width: double.infinity,
                          outlined: true,
                          onPressed: list.isEmpty
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  onPreview(range, list);
                                },
                        ),
                      ),
                    if (!canExport && !canPreview)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('当前平台暂不支持导出，请在 Web 端使用该功能。',
                            style:
                                TextStyle(fontSize: 13, color: AppTokens.muted)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 单个格式选项卡片（弹层内）。
  Widget _formatTile(
      BuildContext ctx, ReportExportFormat format,
      {required VoidCallback onTap, bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            onTap: enabled ? onTap : null,
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              border: Border.all(color: AppTokens.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTokens.brandSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    format.label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.brand),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(format.subtitle,
                      style:
                          const TextStyle(fontSize: 13, color: AppTokens.fg2)),
                ),
                const Icon(MingCuteIcons.rightLine,
                    size: 18, color: AppTokens.muted),
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

  /// 浏览器预览 HTML（Web 端「预览」入口）。
  ///
  /// **改为下载 HTML 文件**（原 `data:text/html` 方式在新窗口打开时，
  /// 浏览器对 data URL 的"另存为 PDF"支持有限）。下载后双击用浏览器打开，
  /// 即可正常 Ctrl+P → 另存为 PDF / 直接打印。
  Future<void> _previewHtml(
    WidgetRef ref,
    DateTimeRange range, {
    required List<Defect> filtered,
    required String reporter,
    required String generatedAt,
    required String projectName,
  }) async {
    if (filtered.isEmpty) return;
    final report = ref.read(weeklyReportProvider).copyWithDefects(filtered);
    final photoBytes = await _loadPhotoBytes(report);
    final html = buildWeeklyReportHtml(
      report,
      reporter: reporter,
      generatedAt: generatedAt,
      photoBase64: photoBytes.map((k, v) => MapEntry(k, base64Encode(v))),
    );
    final baseName =
        '现场工作汇报_${_sanitize(projectName)}_${_fmtCompact(range.start)}-${_fmtCompact(range.end)}';
    downloadTextFile('$baseName.html', 'text/html;charset=utf-8', html);
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

/// 筛选条（设计稿 Frame 2131330677）：白底圆角 12 容器，内 5 个等分小按钮。
/// 选中 = #F4F6F7 底 + 品牌蓝字；未选中 = 白底 + 注释灰字；均 14/600、圆角 8。
class _FilterChips extends ConsumerWidget {
  final DefectStatus? current;
  const _FilterChips({required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const options = [
      (null, '全部'),
      (DefectStatus.draft, '待整改'),
      (DefectStatus.doing, '整改中'),
      (DefectStatus.done, '已销项'),
      (DefectStatus.reject, '已拒绝'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Row(
        children: [
          for (final (s, label) in options) ...[
            if (s != null) const SizedBox(width: 4),
            Expanded(
              child: _FilterBtn(
                label: label,
                selected: s == current,
                onTap: () => ref.read(defectFilterProvider.notifier).state = s,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTokens.surface2 : AppTokens.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              height: 34 / 14,
              fontWeight: FontWeight.w600,
              leadingDistribution: TextLeadingDistribution.even,
              color: selected ? AppTokens.brand : AppTokens.note,
            ),
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
          width: 56,
          child: Text(name,
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
                        fontWeight: FontWeight.w600,
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
