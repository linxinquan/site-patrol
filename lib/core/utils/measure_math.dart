import 'dart:math' as math;

import '../utils/cad_coord.dart';
import '../../data/models.dart';

/// 半自动标定测量的纯函数集合（无 UI、无状态、便于单测）。
/// 设计见 MEASURE_FEATURE_PLAN.md。

/// 图纸侧：两点（整图像素坐标）经 CAD 校准后的距离（mm）。
///
/// [mapper] 当前图纸的仿射校准换算器；[imageW]/[imageH] 为整图渲染像素尺寸；
/// (ax,ay)/(bx,by) 为整图坐标系下的像素点。
double drawingDistanceMm(
  CadCoordMapper mapper,
  double imageW,
  double imageH,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final a = mapper.screenToWorld(ax, ay);
  final b = mapper.screenToWorld(bx, by);
  return (a - b).distance;
}

/// 图纸侧比例（mm/px）：以标定两点间「已知的图纸标注尺寸」反推。
/// [knownMm] 该两点在图纸上的真实标注尺寸（mm）。
double drawingMmPerPx(
  CadCoordMapper mapper,
  double imageW,
  double imageH,
  double ax,
  double ay,
  double bx,
  double by,
  double knownMm,
) {
  final px = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
  if (px <= 1e-6) return 0;
  return knownMm / px;
}

/// 照片侧：照片上两点（整图像素坐标）的距离（像素）。
double photoDistancePx(
  double ax,
  double ay,
  double bx,
  double by,
) =>
    math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));

/// 照片侧量得尺寸（mm）：像素距离 × 照片标定比例（mm/px）。
double photoMeasuredMm(
  PhotoCalib calib,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final px = photoDistancePx(ax, ay, bx, by);
  return px * calib.mmPerPx;
}

/// 照片比例（mm/px）：参考物尺寸 / 参考物像素跨度。
double photoMmPerPx(PhotoCalib calib) => calib.mmPerPx;

/// 偏差（mm）= 照片实测 - 图纸。
double deviationMm(double photoMm, double drawingMm) => photoMm - drawingMm;

/// 偏差率（%）= 偏差 / 图纸 × 100。
double deviationPct(double photoMm, double drawingMm) =>
    drawingMm == 0 ? 0 : deviationMm(photoMm, drawingMm) / drawingMm * 100;

/// 是否合格：|偏差| ≤ 容差(mm) 且 |偏差率| ≤ 容差(%)。
bool isPass(double photoMm, double drawingMm, double tolMm, double tolPct) =>
    deviationMm(photoMm, drawingMm).abs() <= tolMm &&
    deviationPct(photoMm, drawingMm).abs() <= tolPct;

// ==================== 重复采样稳健统计（AR/LiDAR 测距）====================

/// 样本中位数（稳健中心估计，抗单次异常值/抖动）。
double medianOf(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// 稳健误差带半宽（±mm）：max(|max−中位|, |中位−min|)，反映重复采样离散度。
/// 不足 2 个样本返回 0（无法估计）。
///
/// 用途：AR 对同一被测边重复打点 N 次后，用中位数作为读数、本值作为
/// ±误差带。误差带进入 `MeasureItem.errorMm`，与容差做「1/3 判定门控」。
double spreadHalfRange(List<double> xs) {
  if (xs.length < 2) return 0;
  final m = medianOf(xs);
  var mx = 0.0;
  for (final x in xs) {
    final d = (x - m).abs();
    if (d > mx) mx = d;
  }
  return mx;
}

/// 判定是否可信：测量误差带半宽应 ≤ 容差的 1/3（测量不确定度规约）。
/// 误差不可估计（0 或 null）或过大 → 不建议给合格/超差结论，应标"复核"。
bool canJudgeByError(double? errorMm, double tolMm) =>
    errorMm != null && errorMm > 0 && errorMm <= tolMm / 3;
