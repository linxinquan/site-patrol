import 'mm_format.dart';

/// 建筑工程命名与模数吸附（纯函数，便于单测）。
///
/// 制图习惯：门窗洞口按「代号 + 宽(dm) + 高(dm)」编号——
/// 门 M0921 = 宽 900 × 高 2100；窗 C1518 = 宽 1500 × 高 1800。
/// 尺寸以 dm 计（各两位），这是设计院通行写法，工人与监理一眼能对上图纸。

/// 洞口类型 → 代号。门 M、窗 C、其它洞口 D。
String openingCodePrefix(String kind) {
  switch (kind) {
    case 'door':
    case '门':
      return 'M';
    case 'window':
    case '窗':
      return 'C';
    default:
      return 'D';
  }
}

/// 门窗洞口编号：`M0921` / `C1518`（宽、高按 dm 取整，各两位）。
///
/// 超过 99dm（9.9m）的非常规尺寸不补零、直接拼接数值，避免截断误导。
String openingCode(String kind, double wmm, double hmm) {
  String two(double mm) {
    final dm = (mm / 100).round();
    if (dm <= 0) return '00';
    if (dm > 99) return dm.toString();
    return dm.toString().padLeft(2, '0');
  }

  return '${openingCodePrefix(kind)}${two(wmm)}${two(hmm)}';
}

/// AI 识别到的被测目标类型 → 工程习惯用词。
String targetKindLabel(String kind) {
  switch (kind) {
    case 'door':
      return '门洞';
    case 'window':
      return '窗洞';
    case 'opening':
      return '洞口';
    case 'beam':
      return '梁宽';
    case 'column':
      return '柱宽';
    case 'wall':
      return '墙长';
    case 'ceiling_height':
      return '净高';
    case 'floor':
      return '地面尺寸';
    default:
      return '尺寸';
  }
}

/// 常用标准尺寸模数（mm）：门窗洞口与构件常见整数系列。
const List<int> kCommonModules = [
  400, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600,
  1800, 2000, 2100, 2200, 2400, 2700, 3000, 3300, 3600, 4200, 4800,
];

/// 模数吸附：返回最接近的标准值与其差值（实测 − 标准）。
///
/// 差值绝对值超过 [tol]（默认 30mm，可按项目容差调整）则视为
/// 「不是标准模数」，返回 null——只提示、不硬改数值。
({double value, double diff})? snapToModule(double mm, {double tol = 30}) {
  var best = 0.0;
  var bestDiff = double.infinity;
  for (final m in kCommonModules) {
    final d = (mm - m).abs();
    if (d < bestDiff) {
      bestDiff = d;
      best = m.toDouble();
    }
  }
  if (bestDiff > tol) return null;
  return (value: best, diff: mm - best);
}

/// 吸附提示文案：`接近标准模数 2100 mm（差 -25 mm）`；
/// 无匹配时提示非标准模数（设计师按模数出图，明显不吸附往往是量错或真偏差）。
String snapHint(double mm, {double tol = 30}) {
  final s = snapToModule(mm, tol: tol);
  if (s == null) {
    return '${fmtMm(mm)} mm 非标准模数，建议复核';
  }
  return '接近标准模数 ${fmtMm(s.value)} mm（差 ${fmtMmSigned(s.diff)} mm）';
}
