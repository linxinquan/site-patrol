/// 量尺结果的**统一文案**（清单页与报告四端共用）。
///
/// 为什么集中在这里：报告有 HTML/PDF/DOCX/XLSX 四个渲染端，
/// 若各端各自拼字符串，会出现「同一份数据四个说法」——
/// 误差带写没写、测量方式叫什么，必须只有一处定义。
library;

import '../../data/models.dart';
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

/// 判定文本：误差带 > 容差/3 时不下结论（测量不确定度规约），标「需卷尺复核」。
String measureVerdictText(MeasureItem e, double tolMm, double tolPct) {
  if (e.errorMm != null && !e.canJudge(tolMm)) return '需卷尺复核（误差过大）';
  return e.pass(tolMm, tolPct) ? '合格' : '超差';
}

/// 单行摘要（DOCX 段落 / HTML 文本行 / XLSX 备注列共用）。
String measureCheckLine(
  MeasureItem e, {
  double tolMm = 15,
  double tolPct = 2,
}) =>
    '${e.name}：实测 ${measureValueText(e)}'
    ' · 图纸 ${fmtMm(e.drawingMm)} mm'
    ' · 偏差 ${fmtMmSigned(e.deviation)} mm (${fmtPctSigned(e.deviationPct)}%)'
    ' · ${measureVerdictText(e, tolMm, tolPct)}'
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

/// 表格行（与 [kCheckTableHeaders] 一一对应）。
List<String> measureCheckRow(
  MeasureItem e, {
  double tolMm = 15,
  double tolPct = 2,
}) =>
    [
      e.name,
      measureValueText(e),
      '${fmtMm(e.drawingMm)} mm',
      '${fmtMmSigned(e.deviation)} mm (${fmtPctSigned(e.deviationPct)}%)',
      measureVerdictText(e, tolMm, tolPct),
      measureSourceLabel(e.source),
    ];
