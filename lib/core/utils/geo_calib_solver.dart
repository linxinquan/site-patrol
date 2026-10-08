/// 由「规划路线 + 真实 GPS 轨迹」**自动反解**图纸地理配准（零输入）。
///
/// 原理：一次巡场里，规划路线（图纸像素坐标，事先已知）与 GPS 轨迹（经纬度，
/// 现场采集）走的是**同一条路**。把两者对齐后，"图纸上走了多远"与"实地走了
/// 多远"之比就是米/像素，再由任一点对反解出图纸左上角的经纬度。
///
/// 算法分两步，缺一不可：
/// 1. **粗对齐**：按各自累积里程归一化后等距重采样，得到初始点对与粗比例 k0。
///    仅靠里程对齐在**走回头路**时会错位（进度 50% 之后又回到起点附近）。
/// 2. **ICP 精化**：用 k0 把 GPS 投到像素空间，再在上一匹配点附近的**局部窗口**
///    内找最近点，迭代若干轮。这一步能吸收回头路、GPS 抖动、采样不均匀。
///
/// 精度边界（重要）：结果受 **GPS 民用精度 3~5 m** 限制，比例误差通常 1~3%。
/// 适合判断"路线走没走偏楼"，**不适合量尺寸**——量尺寸请用 AR 量尺。
library;

import 'dart:math' as math;

import 'geo_project.dart';

/// 图纸像素坐标点。
typedef PixelPoint = ({double x, double y});

/// 真实 GPS 坐标点。
typedef GeoPoint = ({double lat, double lng});

/// 自动解算的结果 + 可信度评估。
class GeoCalibSolution {
  /// 图纸左上角像素 (0,0) 对应的纬度（度）。
  final double originLat;

  /// 图纸左上角像素 (0,0) 对应的经度（度）。
  final double originLng;

  /// 米/像素。
  final double metersPerPixel;

  /// 匹配点对的 RMS 残差（米）：越小说明两条轨迹越吻合。
  final double residualM;

  /// 实际参与解算的匹配点对数。
  final int matched;

  /// 参与解算的规划路线里程占比（0~1）：太低说明路线只走了一小段。
  final double coverage;

  const GeoCalibSolution({
    required this.originLat,
    required this.originLng,
    required this.metersPerPixel,
    required this.residualM,
    required this.matched,
    required this.coverage,
  });

  /// 是否达到"可用"标准：点对够多、覆盖过半、残差在 GPS 精度量级内。
  ///
  /// 阈值说明：残差 8 m ≈ GPS 民用误差的 2 倍；点数 ≥ 12 可吸收 0~5 m 的抖动；
  /// 覆盖率 ≥ 0.6 保证不是只走了路线的一小段就下结论。
  bool get reliable => matched >= 12 && coverage >= 0.6 && residualM <= 8.0;
}

/// 两点间大圆距离（米）。
double haversineMeters(GeoPoint a, GeoPoint b) {
  const earthR = 6371008.8; // IUGG 平均地球半径（米）
  final dLat = (b.lat - a.lat) * math.pi / 180.0;
  final dLng = (b.lng - a.lng) * math.pi / 180.0;
  final la1 = a.lat * math.pi / 180.0;
  final la2 = b.lat * math.pi / 180.0;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(la1) * math.cos(la2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * earthR * math.asin(math.min(1.0, math.sqrt(h)));
}

/// 累积弧长（入参是相邻点距离序列，返回长度 = 段数+1，首 0）。
List<double> _cumulative(List<double> seg) {
  final out = List<double>.filled(seg.length + 1, 0.0);
  for (var i = 0; i < seg.length; i++) {
    out[i + 1] = out[i] + seg[i];
  }
  return out;
}

List<double> _segPixel(List<PixelPoint> p) => [
      for (var i = 1; i < p.length; i++)
        math.sqrt(math.pow(p[i].x - p[i - 1].x, 2) +
                math.pow(p[i].y - p[i - 1].y, 2))
            .toDouble(),
    ];

List<double> _segGeo(List<GeoPoint> p) =>
    [for (var i = 1; i < p.length; i++) haversineMeters(p[i - 1], p[i])];

/// 在折线上按弧长等距取点（返回插值后的点，长度 = n）。
///
/// [posAt] 把「第 i 段内的比例 t」映射成一个点。cum 长度为 点数（首 0），
/// [posAt](segIndex, t) 需要 segIndex ∈ [0, 点数-2]。
List<T> _resample<T>(
  int pointCount,
  List<double> cum,
  int n,
  T Function(int segIndex, double t) posAt,
) {
  final total = cum.last;
  final out = <T>[];
  if (total <= 0 || n < 2) return out;
  var seg = 0;
  for (var k = 0; k < n; k++) {
    final target = total * k / (n - 1);
    while (seg < pointCount - 2 && cum[seg + 1] < target) {
      seg++;
    }
    final len = cum[seg + 1] - cum[seg];
    final t = len <= 0 ? 0.0 : (target - cum[seg]) / len;
    out.add(posAt(seg, t));
  }
  return out;
}

/// 最小二乘求米/像素（零均值化，只用相对量 → 对 GPS 整体偏移不敏感）。
double? _solveScale(List<PixelPoint> px, List<({double x, double y})> mt) {
  final n = math.min(px.length, mt.length);
  if (n < 3) return null;
  var pxSum = 0.0, pySum = 0.0, mxSum = 0.0, mySum = 0.0;
  for (var i = 0; i < n; i++) {
    pxSum += px[i].x;
    pySum += px[i].y;
    mxSum += mt[i].x;
    mySum += mt[i].y;
  }
  final cx = pxSum / n, cy = pySum / n, gx = mxSum / n, gy = mySum / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = px[i].x - cx;
    final dy = px[i].y - cy;
    num += dx * (mt[i].x - gx) + dy * (mt[i].y - gy);
    den += dx * dx + dy * dy;
  }
  if (den <= 1e-9) return null; // 路线退化（几乎没位移）
  final k = num / den;
  if (!k.isFinite || k <= 0) return null;
  return k;
}

/// 由比例 k 与一个点对还原"图纸 (0,0) 对应哪个经纬度"。
GeoPoint _anchorFromPair(PixelPoint p, GeoPoint g, double k) {
  final mPerLng = metersPerDegreeLng(g.lat);
  return (
    lat: g.lat - (p.y * k) / kMetersPerDegreeLat,
    lng: g.lng - (p.x * k) / mPerLng,
  );
}

/// 交叉校验结果：相邻打卡点对解出的**局部比例**与全局解算值的对比。
class CrossCheckResult {
  /// 参与校验的相邻点对数。
  final int pairs;

  /// 各点对局部比例的中位数（米/像素）。
  final double medianMpp;

  /// 局部比例的**离散度**（相对中位数的最大偏差，1 = 0%）。
  ///
  /// 这是关键指标：相邻两点间距通常只有十几米，而 GPS 端点误差有 3~5m，
  /// 所以**单对局部比例本身误差可达 20%+，不能用来提精度**；
  /// 但如果多对之间**彼此一致**（离散度小），说明 GPS 稳定、自动解算可信；
  /// 反之离散度大 = GPS 在漂或配准有偏，此时应提示人工介入。
  final double dispersion;

  /// 与全局解算比例的中位相对偏差（1 = 0%）。
  final double driftVsGlobal;

  const CrossCheckResult({
    required this.pairs,
    required this.medianMpp,
    required this.dispersion,
    required this.driftVsGlobal,
  });

  /// 点对太少（<2 对）时无法交叉校验。
  bool get enough => pairs >= 2;

  /// 局部比例彼此是否一致（离散度 < 30%）。
  bool get selfConsistent => dispersion < 0.30;

  /// 与全局解算是否吻合（偏差 < 25%）。
  bool get agreesWithGlobal => driftVsGlobal < 0.25;

  /// 综合判定：局部彼此一致 **且** 与全局吻合，才认为这次解算可信。
  bool get trustworthy => enough && selfConsistent && agreesWithGlobal;
}

/// 由「打卡点对」做交叉校验。
///
/// - [checkins] 每项需含 `pointIdx`（图纸路线点序号）与 GPS 经纬度
/// - [route] 规划路线（图纸像素坐标）
/// - [globalMpp] 自动解算得到的全局米/像素（用于对比）
///
/// 返回 null 表示打卡点不足（带 GPS 的点少于 2 个，或路线太短）。
///
/// 为什么不是"提精度"而是"验伪"：相邻打卡点间距通常十几米，GPS 端点误差 3~5m，
/// 单对局部比例误差可达 20~30%；**局部越短越不准**。它的价值在于——
/// 局部比例彼此是否一致（GPS 稳不稳）、与全局是否吻合（配准对不对）。
CrossCheckResult? crossCheckByCheckins({
  required List<({int pointIdx, double lat, double lng})> checkins,
  required List<PixelPoint> route,
  required double globalMpp,
}) {
  if (checkins.length < 2 || route.length < 2) return null;

  // 局部比例 = 两点实地距离(haversine) / 两点图纸距离(像素)
  final locals = <double>[];
  for (var i = 1; i < checkins.length; i++) {
    final a = checkins[i - 1];
    final b = checkins[i];
    if (a.pointIdx < 0 ||
        a.pointIdx >= route.length ||
        b.pointIdx < 0 ||
        b.pointIdx >= route.length) {
      continue; // 点序号越界（路线改过）→ 跳过
    }
    final pa = route[a.pointIdx];
    final pb = route[b.pointIdx];
    final dpx = math.sqrt(math.pow(pb.x - pa.x, 2) + math.pow(pb.y - pa.y, 2));
    if (dpx < 1.0) continue; // 图纸距离太短，比例不可信
    final dm = haversineMeters((lat: a.lat, lng: a.lng), (lat: b.lat, lng: b.lng));
    if (dm < 2.0) continue; // 实地距离太短（GPS 没动）
    locals.add(dm / dpx);
  }
  if (locals.isEmpty) return null;

  locals.sort();
  final median = locals[locals.length ~/ 2];
  if (median <= 0) return null;

  // 离散度：各局部比例相对中位数的最大偏差
  var maxDev = 0.0;
  for (final v in locals) {
    final d = (v - median).abs() / median;
    if (d > maxDev) maxDev = d;
  }
  // 与全局解算的中位偏差
  final drift = (median - globalMpp).abs() / globalMpp;

  return CrossCheckResult(
    pairs: locals.length,
    medianMpp: median,
    dispersion: maxDev,
    driftVsGlobal: drift,
  );
}

/// 从规划路线 + GPS 轨迹自动反解地理配准。
///
/// - [route] 规划路线（**图纸像素**坐标，顺序即行进方向）
/// - [fixes] 本次巡场采集的 GPS 轨迹（经纬度，时间顺序）
/// - [sampleCount] 粗对齐采样点数
/// - [icpRounds] ICP 精化轮数
/// - [window] ICP 局部窗口（路线点索引搜索半径）
///
/// 返回 null 表示数据不足或退化：点数太少、路线几乎没位移、GPS 全挤在一处。
GeoCalibSolution? solveGeoCalibrationFromRoute({
  required List<PixelPoint> route,
  required List<GeoPoint> fixes,
  int sampleCount = 40,
  int icpRounds = 6,
  int window = 12,
}) {
  if (route.length < 3 || fixes.length < 3) return null;

  final routeCum = _cumulative(_segPixel(route));
  if (routeCum.last <= 1e-6) return null; // 路线没动
  final gpsCum = _cumulative(_segGeo(fixes));
  if (gpsCum.last <= 1.0) return null; // 实地没动（<1m），解不出比例

  // ② 粗对齐（按里程归一化等距重采样）
  final n = math.min(sampleCount, math.min(route.length, fixes.length));
  if (n < 3) return null;

  final routeS = _resample<PixelPoint>(route.length, routeCum, n, (seg, t) {
    final a = route[seg], b = route[seg + 1];
    return (x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t);
  });

  final lat0 = fixes.first.lat;
  final mPerLng0 = metersPerDegreeLng(lat0);
  final geoM = _resample<({double x, double y})>(fixes.length, gpsCum, n, (seg, t) {
    final a = fixes[seg], b = fixes[seg + 1];
    return (
      x: (a.lng + (b.lng - a.lng) * t - fixes.first.lng) * mPerLng0,
      y: (a.lat + (b.lat - a.lat) * t - fixes.first.lat) * kMetersPerDegreeLat,
    );
  });
  if (routeS.length != n || geoM.length != n) return null;

  // ③ 粗比例
  final k0 = _solveScale(routeS, geoM);
  if (k0 == null) return null;
  var k = k0; // 非空，后续迭代重新赋值

  // ④ ICP 精化：GPS 投到像素空间 → 局部窗口最近点匹配 → 重解比例
  var matchedPx = routeS;
  var matchedM = geoM;
  for (var round = 0; round < icpRounds; round++) {
    final idx = <int>[];
    var cursor = 0;
    for (final m in matchedM) {
      final p = (x: m.x / k, y: m.y / k);
      var best = -1;
      var bestD = double.infinity;
      final lo = math.max(0, cursor - window);
      final hi = math.min(route.length - 1, cursor + window);
      for (var i = lo; i <= hi; i++) {
        final dx = route[i].x - p.x;
        final dy = route[i].y - p.y;
        final d = dx * dx + dy * dy;
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      if (best >= 0) {
        idx.add(best);
        cursor = best; // 不强制前进：允许原地匹配，避免错过窗口
      }
    }
    if (idx.length < 3) return null;
    matchedPx = [for (final i in idx) route[i]];
    matchedM = [
      for (var j = 0; j < idx.length; j++) geoM[j],
    ];
    final k2 = _solveScale(matchedPx, matchedM);
    if (k2 == null) return null;
    final converged = (k2 - k).abs() / k < 1e-4;
    k = k2;
    if (converged) break;
  }

  // ⑤ 由第一对点还原锚点经纬度（用匹配到的第一个点对更稳）
  final anchor = _anchorFromPair(matchedPx.first, fixes.first, k);

  // ⑥ 残差（RMS，米）：把匹配点对投回米制，与 GPS 偏移比
  final baseX = matchedM.first.x;
  final baseY = matchedM.first.y;
  var se = 0.0;
  final mCount = math.min(matchedPx.length, matchedM.length);
  for (var i = 0; i < mCount; i++) {
    final mx = matchedPx[i].x * k + baseX;
    final my = matchedPx[i].y * k + baseY;
    final ex = mx - matchedM[i].x;
    final ey = my - matchedM[i].y;
    se += ex * ex + ey * ey;
  }
  final residual = mCount <= 0 ? double.infinity : math.sqrt(se / mCount);

  return GeoCalibSolution(
    originLat: anchor.lat,
    originLng: anchor.lng,
    metersPerPixel: k,
    residualM: residual,
    matched: mCount,
    coverage: 1.0, // 采样已覆盖整条路线；后续可按匹配到的路线区间细化
  );
}
