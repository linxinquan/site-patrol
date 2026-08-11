import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 巡场路径工具：从 HTML demo 的 app.js（patrolPath / patrolCheckpoints / roundPolyline）移植。
/// 坐标体系：相对坐标 0~100（0-100% 底图），与 SVG viewBox="0 0 100 100" 一致。

/// 巡场步行路线（沿走廊/医街走，不横穿房间；相对坐标 0-100）。
/// 底图为西楼一层平面图（nkf_west_1f）。
const List<Offset> patrolPathPoints = [
  Offset(50, 30), // 0: 门诊大厅（起点）
  Offset(50, 40), // 1: 门厅导诊
  Offset(50, 52), // 2: 中央医街中轴
  Offset(40, 52), // 3: 西走廊
  Offset(30, 52), // 4: 左翼走廊入口
  Offset(20, 52), // 5
  Offset(18, 52), // 6: 左病房翼北
  Offset(18, 58), // 7: 左病房翼中
  Offset(18, 62), // 8: 左病房翼南
  Offset(30, 62), // 9: 左翼走廊南
  Offset(40, 62), // 10
  Offset(50, 62), // 11: 中央医街南段
  Offset(50, 52), // 12: 返回中轴
  Offset(60, 52), // 13
  Offset(70, 52), // 14: 右翼走廊入口
  Offset(80, 52), // 15
  Offset(82, 52), // 16: 右病房翼北
  Offset(82, 58), // 17: 右病房翼中
  Offset(82, 62), // 18: 右病房翼南
  Offset(70, 62), // 19: 右翼走廊南
  Offset(60, 62), // 20
  Offset(50, 62), // 21: 中央医街南段
  Offset(50, 70), // 22
  Offset(50, 78), // 23: 地下车库入口（终点）
];

/// 关键检查点（蓝点）：路径中的索引。
const List<int> patrolCheckpoints = [1, 4, 7, 9, 14, 17, 19];

/// 巡场底图 key（对应 drawings mock 中的 nkf_west_1f）。
const String patrolPlanKey = 'nkf_west_1f';

/// 把折线转为带圆角的导航式路径（HTML roundPolyline 的 Dart 移植）。
Path roundPolyline(List<Offset> pts, double r) {
  final path = Path();
  if (pts.length < 2) return path;
  double dist(Offset a, Offset b) => (a - b).distance;
  Offset sub(Offset a, Offset b) => a - b;
  double len(Offset v) => v.distance;
  Offset unit(Offset v) {
    final l = len(v);
    return l == 0 ? Offset.zero : v / l;
  }

  path.moveTo(pts[0].dx, pts[0].dy);
  for (var i = 1; i < pts.length - 1; i++) {
    final prev = pts[i - 1], cur = pts[i], next = pts[i + 1];
    final v1 = unit(sub(cur, prev));
    final v2 = unit(sub(next, cur));
    final seg1 = dist(prev, cur), seg2 = dist(cur, next);
    final cornerR = math.min(r, math.min(seg1 / 2, seg2 / 2));
    final p1 = cur - v1 * cornerR;
    final p2 = cur + v2 * cornerR;
    path.lineTo(p1.dx, p1.dy);
    path.quadraticBezierTo(cur.dx, cur.dy, p2.dx, p2.dy);
  }
  final last = pts[pts.length - 1];
  path.lineTo(last.dx, last.dy);
  return path;
}

/// 按检查点把路径切成段（P5 动画时每段走到终点才显示）。
class PatrolSegment {
  final int startIdx;
  final int endIdx;
  final List<Offset> pts;
  final double threshold; // endIdx / (total-1)
  const PatrolSegment({
    required this.startIdx,
    required this.endIdx,
    required this.pts,
    required this.threshold,
  });
}

List<PatrolSegment> buildPatrolSegments(List<Offset> pts, List<int> cpIdxs) {
  final bounds = [0, ...cpIdxs, pts.length - 1];
  final segs = <PatrolSegment>[];
  for (var i = 0; i < bounds.length - 1; i++) {
    final s = bounds[i], e = bounds[i + 1];
    segs.add(PatrolSegment(
      startIdx: s,
      endIdx: e,
      pts: pts.sublist(s, e + 1),
      threshold: e / (pts.length - 1),
    ));
  }
  return segs;
}

/// 巡场底图绘制（静态版）：路径 + 检查点 + 起终点。
/// 输入尺寸为底图实际像素尺寸；坐标按 w/h 缩放。
class PatrolOverlayPainter extends CustomPainter {
  final List<Offset> pts; // 已按像素缩放的绝对坐标
  final List<int> cpIdxs;
  const PatrolOverlayPainter({required this.pts, required this.cpIdxs});

  @override
  void paint(Canvas canvas, Size size) {
    // 路径（圆角折线，accent 色）
    final path = roundPolyline(pts, 2.5);
    final pathPaint = Paint()
      ..color = const Color(0xFFEA580C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, pathPaint);

    // 起点（绿）/ 终点（红）
    final startPaint = Paint()..color = const Color(0xFF16A34A);
    final endPaint = Paint()..color = const Color(0xFFDC2626);
    canvas.drawCircle(pts.first, 2.4, startPaint);
    canvas.drawCircle(pts.last, 2.4, endPaint);

    // 检查点（蓝）
    final cpPaint = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..style = PaintingStyle.fill;
    final cpStroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (final i in cpIdxs) {
      canvas.drawCircle(pts[i], 1.6, cpStroke);
      canvas.drawCircle(pts[i], 1.6, cpPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PatrolOverlayPainter oldDelegate) => true;
}