/// 量尺结果的**统一文案**（清单页与报告四端共用）。
///
/// 为什么集中在这里：报告有 HTML/PDF/DOCX/XLSX 四个渲染端，
/// 若各端各自拼字符串，会出现「同一份数据四个说法」——
/// 误差带写没写、测量方式叫什么，必须只有一处定义。
library;

import '../../data/models.dart';
import '../../data/weekly_report.dart' show MeasureCheck;
import 'measure_stats.dart';
import 'mm_format.dart';

/// 测量方式显示名（`MeasureItem.source` / `RoomScanRecord.source`）。
String measureSourceLabel(String source) {
  switch (source) {
    case 'ar_lidar':
      return 'AR量尺(LiDAR)';
    case 'roomplan':
      return 'RoomPlan扫描';
    case 'manual':
      return '手动打点';
    case 'ai':
      return 'AI识别';
    case 'ai_grid':
      return 'AI网格标定';
    case 'photo_ref':
      return '参照物标定';
    case 'photo':
      return '照片量尺';
    default:
      return source.isEmpty ? '未标注' : source;
  }
}

/// 实测值文本：`907 mm ±5`（无误差带时只给数值，不假装有精度）。
String measureValueText(MeasureItem e) => e.errorMm == null
    ? '${fmtMm(e.photoMm)} mm'
    : '${fmtMm(e.photoMm)} mm ±${fmtMm(e.errorMm!)}';

/// 判定文本：误差带超过门槛时不下结论，标「需卷尺复核」。
///
/// 门槛优先用 [judgeMaxErrorMm]（项目级配置），未配置时回退容差/3
/// （测量不确定度规约：测量不确定度应不大于容差的 1/3）。
String measureVerdictText(
  MeasureItem e,
  double tolMm,
  double tolPct, {
  double? judgeMaxErrorMm,
}) {
  final gate = judgeMaxErrorMm ?? tolMm / 3;
  if (e.errorMm != null && !(e.errorMm! > 0 && e.errorMm! <= gate)) {
    return '需卷尺复核（误差过大）';
  }
  return e.pass(tolMm, tolPct) ? '合格' : '超差';
}

/// 单行摘要（DOCX 段落 / HTML 文本行 / XLSX 备注列共用）。
String measureCheckLine(
  MeasureItem e, {
  double tolMm = 15,
  double tolPct = 2,
  double? judgeMaxErrorMm,
}) =>
    '${e.name}：实测 ${measureValueText(e)}'
    ' · 图纸 ${fmtMm(e.drawingMm)} mm'
    ' · 偏差 ${fmtMmSigned(e.deviation)} mm (${fmtPctSigned(e.deviationPct)}%)'
    ' · ${measureVerdictText(e, tolMm, tolPct, judgeMaxErrorMm: judgeMaxErrorMm)}'
    ' · 方式：${measureSourceLabel(e.source)}';

/// 表头（PDF/HTML/XLSX 表格式呈现时共用，保证四端列名一致）。
const List<String> kCheckTableHeaders = [
  '校对项',
  '实测（含误差带）',
  '图纸尺寸',
  '偏差',
  '判定',
  '测量方式',
];

/// 报告独立章节用表头（多一列「来源图纸」，便于跨图纸汇总时溯源）。
const List<String> kCheckTableHeadersWithSource = [
  '来源图纸',
  '校对项',
  '实测（含误差带）',
  '图纸尺寸',
  '偏差',
  '判定',
  '测量方式',
];

/// 带来源图纸的表格行（与 [kCheckTableHeadersWithSource] 一一对应）。
List<String> measureCheckRowWithSource(
  MeasureCheck c,
) =>
    [
      c.drawingLabel,
      ...measureCheckRow(c.item,
          tolMm: c.tolMm,
          tolPct: c.tolPct,
          judgeMaxErrorMm: c.judgeMaxErrorMm),
    ];

/// 汇总口径统计：合格 / 超差 / 需复核 三档计数。
///
/// 「需复核」= 误差带超过项目门槛（未配置时为容差/3），与 App 内判定完全同源。
({int ok, int fail, int review, int total}) summarizeChecks(
  List<MeasureCheck> checks,
) {
  var ok = 0, fail = 0, review = 0;
  for (final c in checks) {
    final v = measureVerdictText(c.item, c.tolMm, c.tolPct,
        judgeMaxErrorMm: c.judgeMaxErrorMm);
    if (v.startsWith('合格')) {
      ok++;
    } else if (v.startsWith('超差')) {
      fail++;
    } else {
      review++;
    }
  }
  return (ok: ok, fail: fail, review: review, total: checks.length);
}

/// 汇总行文案（四端共用）：`共 5 项：合格 2 · 超差 1 · 需复核 2`。
String checksSummaryText(List<MeasureCheck> checks) {
  final s = summarizeChecks(checks);
  return '共 ${s.total} 项：合格 ${s.ok} · 超差 ${s.fail} · 需复核 ${s.review}';
}

/// 汇总行文案 + 偏差趋势（报告用）：两行，第二行用于发现系统性偏差。
List<String> checksSummaryLines(List<MeasureCheck> checks) => [
      checksSummaryText(checks),
      deviationTrendText([for (final c in checks) c.item]),
    ];

/// 表格行（与 [kCheckTableHeaders] 一一对应）。
List<String> measureCheckRow(
  MeasureItem e, {
  double tolMm = 15,
  double tolPct = 2,
  double? judgeMaxErrorMm,
}) =>
    [
      e.name,
      measureValueText(e),
      '${fmtMm(e.drawingMm)} mm',
      '${fmtMmSigned(e.deviation)} mm (${fmtPctSigned(e.deviationPct)}%)',
      measureVerdictText(e, tolMm, tolPct, judgeMaxErrorMm: judgeMaxErrorMm),
      measureSourceLabel(e.source),
    ];
