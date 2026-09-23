import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../utils/cad_coord.dart';
import '../utils/homography.dart';
import '../../data/models.dart';

/// 半自动标定测量的纯函数集合（无 UI、无状态、便于单测）。
/// 设计见 docs/archive/MEASURE_FEATURE_PLAN.md。

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

/// 照片侧量距（**自动选择标定方式**）：
/// - 已做单应（网格 ≥4 点）标定 → 走平面单应，先把斜拍画面矫正为正视图再量距；
/// - 否则回退两点比例法（旧行为，兼容旧会话与未标定的手动路径）。
///
/// 这是量尺页的主入口：单应标定只改变「毫米从哪来」，上层判定/清单/报告不变。
double photoMeasuredMmAuto(
  PhotoCalib calib,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final h = calib.homography;
  if (h != null && h.length == 9) {
    return Homography.fromMatrix(h).distanceMm(Offset(ax, ay), Offset(bx, by));
  }
  return photoMeasuredMm(calib, ax, ay, bx, by);
}

/// 生成「模数网格」标定的控制点对应关系。
///
/// [cols]/[rows] 为网格列数、行数，[gridMm] 为格距（mm）；
/// 用户按**行优先**（从左到右、从上到下）依次点选网格交点，
/// 第 i 个点的平面坐标即 ((i % cols) × grid, (i ~/ cols) × grid)。
/// 返回 (像素点, 平面 mm) 两个等长列表；点数不足 4 返回空列表。
({List<Offset> src, List<Offset> dst}) buildGridCorrespondences({
  required List<Offset> picks,
  required int cols,
  required int rows,
  required double gridMm,
}) {
  final total = cols * rows;
  if (cols < 2 || rows < 2 || gridMm <= 0 || picks.length < 4) {
    return (src: const <Offset>[], dst: const <Offset>[]);
  }
  final n = picks.length < total ? picks.length : total;
  final src = <Offset>[];
  final dst = <Offset>[];
  for (var i = 0; i < n; i++) {
    src.add(picks[i]);
    dst.add(Offset((i % cols) * gridMm, (i ~/ cols) * gridMm));
  }
  return (src: src, dst: dst);
}

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

// ==================== 离群读数剔除（AR 实拍常见：点到了别的面）====================

/// 稳健统计结果。
/// - [median]/[spread]：**剔除离群后**重算的中位与误差带半宽（±mm）；
/// - [used]/[rejected]：参与计算的样本数 / 被判为离群的样本数。
typedef RobustStat = ({double median, double spread, int used, int rejected});

/// 离群样本的下标（供 UI 逐条标注"将被剔除"）。
///
/// 与 [robustStats] 同一判据（MAD + 兜底尺度），n < [minSamples] 或全部离群时
/// 返回空列表（宁可全留，也不制造"样本被清空"的假象）。
List<int> outlierIndexes(
  List<double> xs, {
  double k = 3.0,
  double minSpreadMm = 5.0,
  int minSamples = 3,
}) {
  if (xs.length < minSamples) return const [];
  final m = medianOf(xs);
  final devs = [for (final x in xs) (x - m).abs()];
  var scale = 1.4826 * medianOf(devs);
  if (scale < minSpreadMm) scale = minSpreadMm;
  final out = <int>[];
  for (var i = 0; i < xs.length; i++) {
    if ((xs[i] - m).abs() > k * scale) out.add(i);
  }
  return out.length == xs.length ? const [] : out;
}

/// 基于 MAD 的离群剔除 + 稳健中位。
///
/// 为什么需要：AR 反复测同一条边时，偶尔有一次点到了**后面的墙/柜子/地脚线**，
/// 读数会跳到 2 倍或 1/2（实测出现过 ±505mm 的离散）。直接用最大-最小当误差带
/// 会把这种"点错面"的读数当成"测量不确定度"，导致整组不可用。
///
/// 规则：中位 m 与 MAD（绝对中位差）→ 尺度 σ=1.4826·MAD（正态一致估计），
/// 保留 |x−m| ≤ [k]·σ 的样本；σ 过小（样本几乎全等）时用 [minSpreadMm] 兜底，
/// 避免把所有样本都判成离群。[minSamples] 以下不做剔除（样本太少没统计意义）。
RobustStat robustStats(
  List<double> xs, {
  double k = 3.0,
  double minSpreadMm = 5.0,
  int minSamples = 3,
}) {
  if (xs.isEmpty) {
    return (median: 0, spread: 0, used: 0, rejected: 0);
  }
  if (xs.length < minSamples) {
    return (
      median: medianOf(xs),
      spread: spreadHalfRange(xs),
      used: xs.length,
      rejected: 0,
    );
  }
  final dropped =
      outlierIndexes(xs, k: k, minSpreadMm: minSpreadMm, minSamples: minSamples);
  if (dropped.isEmpty) {
    return (
      median: medianOf(xs),
      spread: spreadHalfRange(xs),
      used: xs.length,
      rejected: 0,
    );
  }
  final keep = <double>[];
  for (var i = 0; i < xs.length; i++) {
    if (!dropped.contains(i)) keep.add(xs[i]);
  }
  return (
    median: medianOf(keep),
    spread: spreadHalfRange(keep),
    used: keep.length,
    rejected: dropped.length,
  );
}

/// 一组读数是否足够一致（可直接采纳）。
///
/// [maxSpreadMm] 为允许的稳健误差带上限——超过说明这几次点到的**不是同一条边**
/// （或间隔/角度变化太大），应提示用户重测而不是给一个"看起来有误差带"的数。
bool consistentEnough(double spreadMm, double maxSpreadMm) =>
    spreadMm <= maxSpreadMm;

// ==================== 勾股三值（AR：由世界坐标拆分量）====================

/// 由两点三维坐标（mm）拆出三值：斜边（空间距离）/ 水平投影 / 高度差。
///
/// ARKit 为 y 轴向上，故高度差取 |Δy|；水平投影取 √(Δx²+Δz²)。
/// 现场用途：量层高/洞口高用"高差"，量开间进深用"水平"，量对角线用"斜边"。
({double slope, double horizontal, double vertical}) pythagorasParts({
  required double ax,
  required double ay,
  required double az,
  required double bx,
  required double by,
  required double bz,
}) {
  final dx = bx - ax, dy = by - ay, dz = bz - az;
  return (
    slope: math.sqrt(dx * dx + dy * dy + dz * dz),
    horizontal: math.sqrt(dx * dx + dz * dz),
    vertical: dy.abs(),
  );
}

/// 由 AR 原生上报的**世界坐标端点（米）**拆出三值（mm）。
///
/// ARKit 的世界坐标以**米**为单位（见 [EdgeGeom]），而 [pythagorasParts]
/// 约定输入 mm：单位换算必须在这里一次做对。漏乘 1000 会让 0.7m 变成 0.7，
/// 经 `fmtMm` 取整后显示成 `1mm`——真机 AR量尺踩过的坑（原生尺寸线画的是
/// 700mm，界面读数却是 1mm），故单独抽成函数并加单测锁死。
({double slope, double horizontal, double vertical}) partsFromWorldMeters({
  required double ax,
  required double ay,
  required double az,
  required double bx,
  required double by,
  required double bz,
}) =>
    pythagorasParts(
      ax: ax * 1000,
      ay: ay * 1000,
      az: az * 1000,
      bx: bx * 1000,
      by: by * 1000,
      bz: bz * 1000,
    );

/// 一条边的世界坐标端点（米）：来自 ARKit 命中的两点。
typedef EdgeGeom = ({
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
});

/// 由两条边的世界端点求**面域四角**（共享角点优先）。
///
/// 量开间 + 进深时，两边通常共用一个墙角：检测到共享角点（端点距离 ≤ [tolM]）
/// 就以它为原点铺矩形；找不到就以第一条边为底边、第二条边为"另一条方向"平移
/// （所见即所得，几何仅用于可视化，数值仍来自实测边长）。
List<({double x, double y, double z})> faceCorners(EdgeGeom e1, EdgeGeom e2,
    {double tolM = 0.08}) {
  double dist(
          ({double x, double y, double z}) a, ({double x, double y, double z}) b) =>
      math.sqrt(math.pow(a.x - b.x, 2) +
          math.pow(a.y - b.y, 2) +
          math.pow(a.z - b.z, 2));
  final e1a = (x: e1.ax, y: e1.ay, z: e1.az);
  final e1b = (x: e1.bx, y: e1.by, z: e1.bz);
  final e2a = (x: e2.ax, y: e2.ay, z: e2.az);
  final e2b = (x: e2.bx, y: e2.by, z: e2.bz);
  // 四种端点配对里找共享角点
  for (final (s1, f1, s2, f2) in [
    (e1a, e1b, e2a, e2b),
    (e1a, e1b, e2b, e2a),
    (e1b, e1a, e2a, e2b),
    (e1b, e1a, e2b, e2a),
  ]) {
    if (dist(s1, s2) <= tolM) {
      final far1 = f1;
      final far2 = f2;
      final fourth = (
        x: far1.x + (far2.x - s1.x),
        y: far1.y + (far2.y - s1.y),
        z: far1.z + (far2.z - s1.z),
      );
      return [s1, far1, fourth, far2];
    }
  }
  // 无共享角点：以 e1 为底边，沿 e2 的方向平移
  final dx = e2b.x - e2a.x, dy = e2b.y - e2a.y, dz = e2b.z - e2a.z;
  return [
    e1a,
    e1b,
    (x: e1b.x + dx, y: e1b.y + dy, z: e1b.z + dz),
    (x: e1a.x + dx, y: e1a.y + dy, z: e1a.z + dz),
  ];
}

/// AR 读数模式：决定"采纳哪一个值"。
enum ArMeasureMode {
  slope('斜边', '空间直线距离（默认，量对角线/异面两点）'),
  horizontal('水平', '水平投影距离（量开间/进深/长度）'),
  vertical('高差', '垂直高度差（量层高/洞口高/落差）'),
  heightSum('高度和', '分段累加竖直高度：量一段、举高再量一段，读数自动相加');

  const ArMeasureMode(this.label, this.hint);

  final String label;
  final String hint;

  /// 是否需要在采纳时累加（高度和特有；其余模式一段即一个读数）。
  bool get accumulates => this == ArMeasureMode.heightSum;
}

/// 「高度和」累加器：把若干**竖直段**累加成总高。
///
/// 现场用途：目标高过手机单次能覆盖的范围（高处管线、层高复核），
/// 或中间被遮挡时——地面→手机量一段、手机→目标再量一段，两段之和即总高。
/// 单段读数仍各自入列（可追溯），本累加器只负责给出"和"。
class HeightSum {
  double _mm = 0;
  double _errMm = 0;
  int _segments = 0;

  double get mm => _mm;
  double get errMm => _errMm;
  int get segments => _segments;

  /// 至少两段才有"和"的意义（一段就是它自己）。
  bool get ready => _segments >= 2;

  /// 累加一段；非正读数视为误点，直接忽略（不污染和值）。
  void add(double mm, double errMm) {
    if (mm <= 0) return;
    _mm += mm;
    _errMm += errMm;
    _segments++;
  }

  void reset() {
    _mm = 0;
    _errMm = 0;
    _segments = 0;
  }
}
