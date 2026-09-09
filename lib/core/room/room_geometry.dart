/// 量房几何与工程习惯纯函数（无 UI、可单测）。
///
/// 坐标体系：户型多边形顶点为 **mm** 的平面坐标（局部坐标系，首点可平移）。
/// 工程习惯口径见 `MEASURE_ROOM_PLAN.md` 三：
/// - 正交修正（85~95° 吸附为直角）；
/// - 闭合差 ≤15mm 为可接受（对应量房行业口径）；
/// - 面积 ㎡、尺寸 mm。
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../data/models.dart';

/// 相邻点到 `b` 的距离。
double _d(Offset a, Offset b) => (a - b).distance;

/// 首尾闭合差（mm）：最后一个点到第一个点的缺口。
/// 手工成图点列首尾不必精确重合，缺口即累计误差。
double polygonClosureDelta(List<Offset> ptsMm) {
  if (ptsMm.length < 3) return 0;
  return _d(ptsMm.last, ptsMm.first);
}

/// 周长（mm）。
double polygonPerimeterMm(List<Offset> ptsMm) {
  if (ptsMm.length < 2) return 0;
  var s = 0.0;
  for (var i = 0; i < ptsMm.length; i++) {
    s += _d(ptsMm[i], ptsMm[(i + 1) % ptsMm.length]);
  }
  return s;
}

/// 鞋带公式面积（㎡）。凸/凹多边形均适用；自交点列不保证。
double roomAreaM2(List<Offset> ptsMm) {
  if (ptsMm.length < 3) return 0;
  var twice = 0.0;
  for (var i = 0; i < ptsMm.length; i++) {
    final a = ptsMm[i];
    final b = ptsMm[(i + 1) % ptsMm.length];
    twice += a.dx * b.dy - b.dx * a.dy;
  }
  return (twice.abs() / 2) / 1e6; // mm² → m²
}

/// 顶点内角（弧度）：顶点 `i` 处两条邻边构成的转角（0..π）。
double interiorAngleRad(List<Offset> ptsMm, int i) {
  final n = ptsMm.length;
  if (n < 3) return 0;
  final a = ptsMm[(i - 1 + n) % n];
  final b = ptsMm[i];
  final c = ptsMm[(i + 1) % n];
  final v1 = a - b, v2 = c - b;
  if (v1.distance < 1e-6 || v2.distance < 1e-6) return 0;
  final cosA =
      (v1.dx * v2.dx + v1.dy * v2.dy) / (v1.distance * v2.distance);
  return math.acos(cosA.clamp(-1.0, 1.0));
}

/// 正交吸附：将 90°±[tolDeg] 的内角顶点移到"以两邻点为直径的圆"（泰勒斯圆）
/// 上最近点——保证该角精确为 90° 且顶点位移最小；邻点不动。
///
/// 返回修正后的点列与"被吸附顶点下标集合"。明显斜墙（超出容差）保持原样，
/// 由调用方提示"非直角，请复核"。
({List<Offset> points, Set<int> snapped}) orthoSnapPoints(
  List<Offset> ptsMm, {
  double tolDeg = 5,
}) {
  if (ptsMm.length < 3) return (points: List.of(ptsMm), snapped: const {});
  final out = List<Offset>.of(ptsMm);
  final snapped = <int>{};
  for (var i = 0; i < out.length; i++) {
    final n = out.length;
    final a = out[(i - 1 + n) % n];
    final b = out[(i + 1) % n];
    final dAB = _d(a, b);
    if (dAB < 1e-3) continue;
    final rad = interiorAngleRad(out, i);
    final deg = rad * 180 / math.pi;
    if ((deg - 90).abs() > tolDeg) continue;
    // P' 在圆（直径 AB）上最接近原 P 的点：∠AP'B=90°。
    final p = out[i];
    final c = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final v = p - c;
    if (v.distance < 1e-6) continue;
    out[i] = c + v / v.distance * (dAB / 2);
    snapped.add(i);
  }
  return (points: out, snapped: snapped);
}

/// 生成墙段尺寸标注布局：每条墙段给「起终点、中点、外法线方向、文本」。
///
/// 法线方向由多边形环向决定：按 鞋带面积符号 判断顺/逆时针，
/// 内法线恒指向图形内部，标注线沿内法线略偏移避免压线。
/// 渲染层按 [DimLine] 画引出线 + 箭头 + 文字（CustomPaint）。
class DimLine {
  final Offset a;
  final Offset b;
  final Offset mid;
  /// 内法线单位向量（指向图形内侧）。
  final Offset inward;
  final String label;

  const DimLine({
    required this.a,
    required this.b,
    required this.mid,
    required this.inward,
    required this.label,
  });
}

/// 用鞋带符号判环向（正=CCW）。
double _signedTwiceArea(List<Offset> pts) {
  var twice = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final q = pts[(i + 1) % pts.length];
    twice += p.dx * q.dy - q.dx * p.dy;
  }
  return twice;
}

/// 墙段（来自 RoomScanRecord）→ 尺寸标注布局。文本 = 有效墙长 mm 取整。
List<DimLine> dimensionLinesFor(List<RoomWall> walls) {
  final pts = <Offset>[
    for (final w in walls) Offset(w.ax, w.ay),
    if (walls.isNotEmpty)
      Offset(walls.last.bx, walls.last.by),
  ];
  // CCW（正面积）→ 内法线 = 边方向右转 90°；CW → 左转 90°。
  final ccw = _signedTwiceArea(pts) >= 0;
  final lines = <DimLine>[];
  for (final w in walls) {
    final a = Offset(w.ax, w.ay);
    final b = Offset(w.bx, w.by);
    final e = b - a;
    final len = e.distance;
    if (len < 1e-6) continue;
    var nx = -e.dy / len;
    var ny = e.dx / len;
    if (!ccw) {
      nx = -nx;
      ny = -ny;
    }
    lines.add(DimLine(
      a: a,
      b: b,
      mid: Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2),
      inward: Offset(nx, ny),
      label: w.effectiveLengthMm.round().toString(),
    ));
  }
  return lines;
}
