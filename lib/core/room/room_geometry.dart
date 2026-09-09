/// 量房几何纯函数：正交吸附 / 闭合差 / 面积 / 标注布局 / 洞口分段。
/// 约定：点坐标 mm；多边形点按走墙顺序（顺/逆时针均可）。
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/models.dart';

/// 点到点距离
double _dist(Offset a, Offset b) => (a - b).distance;

/// 角 abc（b 为顶点）弧度 → 角度（度）
double _angleDeg(Offset a, Offset b, Offset c) {
  final v1 = a - b, v2 = c - b;
  final d = v1.distance * v2.distance;
  if (d == 0) return 0;
  return math.acos((v1.dx * v2.dx + v1.dy * v2.dy) / d) * 180 / math.pi;
}

/// 1) 正交吸附：对每个顶点 b（邻点 a、c），若内角 ∈ [90-tol, 90+tol] 则把
///    a→b、b→c 两向量强制正交（保持 b 位置与两段长度近似，旋转更短的一侧）。
///    返回 {points: 修正后点集, snappedIdx: 被吸附的顶点下标集}。
({List<Offset> points, Set<int> snappedIdx}) orthoSnap(
  List<Offset> pts, {
  double tolDeg = 5,
}) {
  if (pts.length < 3) return (points: List.of(pts), snappedIdx: <int>{});
  final out = List<Offset>.of(pts);
  final snapped = <int>{};
  for (var i = 0; i < pts.length; i++) {
    final a = pts[(i - 1 + pts.length) % pts.length];
    final b = pts[i];
    final c = pts[(i + 1) % pts.length];
    final ang = _angleDeg(a, b, c);
    if (ang > 90 - tolDeg && ang < 90 + tolDeg) {
      // 把 c 沿 (b-a) 垂线投影，使 ab ⊥ bc：以 a 为不动点更稳，
      // 简法：保持 ab 不变，把 c 投影到过 b 且垂直于 ab 的直线上。
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      if (len2 > 1e-6) {
        final bc = c - b;
        // 保持 c 到 b 距离：把 bc 旋转 90° 到 ab 垂直方向，长度不变
        final lenBc = _dist(b, c);
        final n = Offset(-ab.dy, ab.dx) / math.sqrt(len2);
        final oldSide = (bc.dx * n.dx + bc.dy * n.dy);
        out[(i + 1) % pts.length] = b + n * (lenBc * (oldSide >= 0 ? 1 : -1));
        snapped.add(i);
      }
      // 注：若需更高保真可保留两版并选闭合差更小者，v1 用本实现即可
    }
  }
  return (points: out, snappedIdx: snapped);
}

/// 2) 闭合差：多边形首尾缺口长度（mm）
double closureDelta(List<Offset> pts) {
  if (pts.length < 3) return 0;
  return _dist(pts.first, pts.last);
}

/// 3) 多边形面积（鞋带公式），㎡（输入 mm）
double areaM2(List<Offset> pts) {
  if (pts.length < 3) return 0;
  var s = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i], q = pts[(i + 1) % pts.length];
    s += p.dx * q.dy - q.dx * p.dy;
  }
  return (s.abs() / 2) / 1e6; // mm² → ㎡
}

/// 4) 各墙段校正长度（正交吸附后重算，mm）
List<double> wallLengthsMm(List<Offset> pts) => [
      for (var i = 0; i < pts.length; i++)
        _dist(pts[i], pts[(i + 1) % pts.length]),
    ];

/// 标注布局参数：第 i 条墙段的标注引出点（墙段中点 + 外法线偏移 len）
/// 返回 {mid, normalFromMid: 外法向单位向量方向的位置点}
({Offset mid, Offset labelPos}) dimAnchorFor(
  List<Offset> pts, int i, {
  double offsetPx = 24,
}) {
  final a = pts[i], b = pts[(i + 1) % pts.length];
  final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  var n = Offset(-(b.dy - a.dy), b.dx - a.dx);
  final len = n.distance;
  if (len == 0) return (mid: mid, labelPos: mid);
  n = n / len;
  // 取"外"侧：指向多边形外（用质心判断）
  final c = centroid(pts);
  final outward = (mid.dx - c.dx) * n.dx + (mid.dy - c.dy) * n.dy >= 0 ? 1.0 : -1.0;
  return (mid: mid, labelPos: mid + n * outward * offsetPx);
}

Offset centroid(List<Offset> pts) {
  if (pts.isEmpty) return Offset.zero;
  var x = 0.0, y = 0.0;
  for (final p in pts) {
    x += p.dx;
    y += p.dy;
  }
  return Offset(x / pts.length, y / pts.length);
}

/// 5) 洞口在墙段上的打断：给定整墙段 a→b 与洞列表，返回洞口中心位置（局部坐标系归一化）
List<double> openingCentersUnit(
    List<Offset> aB, List<WallOpening> ops, double wallLenMm) {
  if (wallLenMm <= 0) return const [];
  return [
    for (final o in ops)
      ((o.offsetFromMm + o.widthMm / 2) / wallLenMm).clamp(0.0, 1.0),
  ];
}
