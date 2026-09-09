/// 尺寸数值的**显示**格式化（对齐建筑制图习惯）。
///
/// 只影响界面呈现，**不改变任何存储/计算精度**——持久化与判定仍用原始双精度值。
///
/// 施工图习惯：
/// - 尺寸一律以 **mm 为单位取整**呈现（3000 / 900，不带小数）；
/// - 标高类才以 m 计并保留三位小数（本 App 未涉及，故不提供）；
/// - **百分比偏差保留 1 位小数**——偏差常小于 1%，取整会显示成 0% 而误导；
/// - 标定比例（mm/px）、经纬度、地图缩放等技术中间量保留小数，不在此收敛范围。
library;

/// mm 取整：3042.37 → `3042`。
String fmtMm(num v) => v.round().toString();

/// mm 取整并带正负号（用于偏差）：+12.4 → `+12`；-3.2 → `-3`；0 → `0`。
String fmtMmSigned(num v) {
  final n = v.round();
  return n > 0 ? '+$n' : n.toString();
}

/// 百分比显示（保留 1 位小数）。
String fmtPct(num v) => v.toStringAsFixed(1);

/// 百分比显示并带正负号（用于偏差率）。
String fmtPctSigned(num v) => '${v >= 0 ? '+' : ''}${fmtPct(v)}';

/// 去掉多余小数位（用于输入框回填）：15.0 → `15`；2.5 → `2.5`。
///
/// 直接 `toString()` 会得到 `15.0`，把整数字段渲染出假小数，违反制图取整习惯。
String fmtNumTrim(num v) {
  final d = v.toDouble();
  if (d == d.roundToDouble()) return d.toInt().toString();
  return d.toString();
}
