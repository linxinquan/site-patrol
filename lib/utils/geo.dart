/// 几何纯函数（巡场穿墙检测，单测友好，无 Flutter 依赖）。
library;

/// 线段严格相交（不含端点相接）。
/// 返回 true = (a,b) 与 (c,d) 两条线段在内部相交（不是端点接触）。
bool segmentsCross(
  double ax,
  double ay,
  double bx,
  double by,
  double cx,
  double cy,
  double dx,
  double dy,
) {
  // 叉积：cross(o, p, q) = (p - o) × (q - o)；符号表示 q 在 p 的哪一侧。
  double cross(double ox, double oy, double px, double py, double qx, double qy) =>
      (px - ox) * (qy - oy) - (py - oy) * (qx - ox);

  final d1 = cross(cx, cy, dx, dy, ax, ay);
  final d2 = cross(cx, cy, dx, dy, bx, by);
  final d3 = cross(ax, ay, bx, by, cx, cy);
  final d4 = cross(ax, ay, bx, by, dx, dy);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// 一段路线 (ax,ay)→(bx,by)（相对坐标 0-100）是否穿墙。
/// [walls] 为同坐标系下的墙线段 [[ax,ay,bx,by], ...]。
bool routeSegmentHitsWall(
  double ax,
  double ay,
  double bx,
  double by,
  List<List<double>> walls,
) {
  for (final w in walls) {
    if (segmentsCross(ax, ay, bx, by, w[0], w[1], w[2], w[3])) return true;
  }
  return false;
}

/// 计算一段路线折线（相对坐标 0-100）中穿墙段下标集合。
///  段 i 对应路线点 i → i+1（0 ≤ i < points.length-1）。
Set<int> crossingSegments(
  List<List<double>> points,
  List<List<double>> walls,
) {
  final out = <int>{};
  for (var i = 1; i < points.length; i++) {
    if (routeSegmentHitsWall(
      points[i - 1][0],
      points[i - 1][1],
      points[i][0],
      points[i][1],
      walls,
    )) {
      out.add(i - 1);
    }
  }
  return out;
}