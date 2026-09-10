import 'dart:math' as math;

import '../../data/models.dart';
import 'mm_format.dart';

/// 量尺偏差分布统计（用于发现**系统性偏差**）。
///
/// 为什么需要：单看一条"偏差 +20mm"很难判断是偶发还是系统性问题；
/// 但同一张图纸上**多条偏差都同号**，基本可以断定是图纸缩放/校准或
/// 标定比例整体偏了——这比逐条复核快得多。
({int n, double mean, double median, double min, double max, double sd})
    deviationTrend(List<MeasureItem> items) {
  final devs = <double>[
    for (final e in items)
      if (e.drawingMm > 0) e.deviation,
  ];
  if (devs.isEmpty) {
    return (n: 0, mean: 0, median: 0, min: 0, max: 0, sd: 0);
  }
  devs.sort();
  final n = devs.length;
  final mean = devs.reduce((a, b) => a + b) / n;
  final median =
      n.isOdd ? devs[n ~/ 2] : (devs[n ~/ 2 - 1] + devs[n ~/ 2]) / 2;
  var acc = 0.0;
  for (final d in devs) {
    acc += (d - mean) * (d - mean);
  }
  // 样本标准差（n-1），n=1 时为 0
  final sd = n > 1 ? math.sqrt(acc / (n - 1)) : 0.0;
  return (n: n, mean: mean, median: median, min: devs.first, max: devs.last, sd: sd);
}

/// 系统性偏差判读：同号比例高 → 疑似系统性偏大/偏小。
///
/// 判据（保守）：样本 ≥3 且同号比例 ≥ 80%，或 |中位| 明显大于标准差而集中。
String biasHint(List<MeasureItem> items) {
  final devs = <double>[
    for (final e in items)
      if (e.drawingMm > 0) e.deviation,
  ];
  if (devs.length < 3) return '';
  final pos = devs.where((d) => d > 0).length;
  final neg = devs.where((d) => d < 0).length;
  final n = devs.length;
  if (pos / n >= 0.8) return '多数为“实测偏大”的正偏差，疑系统性偏大（查图纸比例/标定）';
  if (neg / n >= 0.8) return '多数为“实测偏小”的负偏差，疑系统性偏小（查图纸比例/标定）';
  final t = deviationTrend(items);
  if (t.sd > 0 && t.mean.abs() > 2 * t.sd) {
    return '偏差集中于 ${fmtMmSigned(t.mean)}mm 附近，疑系统性偏差';
  }
  return '偏差正负分散，更像随机误差，非系统性偏差';
}

/// 一行式统计文案（界面与报告共用）：
/// `偏差分布（5 项）：中位 +8mm（-12~+25），均值 +6mm，标准差 9.4mm · <系统性判读>`
String deviationTrendText(List<MeasureItem> items) {
  final t = deviationTrend(items);
  if (t.n == 0) return '偏差分布：无有效对照项（需填图纸尺寸才参与统计）';
  final hint = biasHint(items);
  return '偏差分布（${t.n} 项）：中位 ${fmtMmSigned(t.median)}mm'
      '（${fmtMmSigned(t.min)} ~ ${fmtMmSigned(t.max)}），'
      '均值 ${fmtMmSigned(t.mean)}mm，标准差 ${t.sd.toStringAsFixed(1)}mm'
      '${hint.isEmpty ? '' : ' · $hint'}';
}
