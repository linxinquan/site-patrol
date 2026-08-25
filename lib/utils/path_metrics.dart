import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/utils/cad_coord.dart';
import '../data/models.dart';

/// 巡场路径工具：从 HTML demo 的 app.js（patrolPath / patrolCheckpoints / roundPolyline）移植。
/// 坐标体系：相对坐标 0~100（0-100% 底图），与 SVG viewBox="0 0 100 100" 一致。
///
/// 注意：`patrolPathPoints` / `patrolCheckpoints` 业务常量已迁移至
/// `lib/data/mock/mock_data.dart` 的 `seedPatrolPlans`（见 PATROL_OPTIMIZE.md），
/// 本文件仅保留纯算法：roundPolyline / pointAtProgress / realRouteKm / PatrolOverlayPainter。

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

/// 沿路径按进度插值出当前位置（相对坐标，与巡场路径同体系）。
Offset pointAtProgress(List<Offset> pts, double progress) {
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += (pts[i] - pts[i - 1]).distance;
  }
  if (total == 0) return pts.first;
  var target = total * progress.clamp(0.0, 1.0);
  for (var i = 1; i < pts.length; i++) {
    final d = (pts[i] - pts[i - 1]).distance;
    if (target <= d) {
      final t = d == 0 ? 0.0 : target / d;
      return pts[i - 1] + (pts[i] - pts[i - 1]) * t;
    }
    target -= d;
  }
  return pts.last;
}

/// 按校准后的 CAD 坐标计算路线真实里程（km）。
///
/// [points] 为巡场路线点（相对坐标 0~100）；[mapper] 为图纸坐标校准映射；
/// [imgW]/[imgH] 为整图像素尺寸。先 0~100 → 整图像素，再经
/// `CadCoordMapper.screenToWorld` 得世界坐标（mm），逐段欧氏距离累加后换算 km。
///
/// 图纸未校准（mapper == null 或点数 <2）时返回 null，调用方用 [PatrolPlan.totalKm] 兜底。
double? realRouteKm(
    List<PatrolPoint> points, CadCoordMapper? mapper, double imgW, double imgH) {
  if (mapper == null || points.length < 2) return null;
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    final a = mapper.screenToWorld(
        points[i - 1].dx / 100 * imgW, points[i - 1].dy / 100 * imgH);
    final b = mapper.screenToWorld(
        points[i].dx / 100 * imgW, points[i].dy / 100 * imgH);
    total += (a - b).distance; // mm
  }
  return total / 1e6; // → km
}

/// 巡场底图绘制（轨迹动画版）：路径 + 检查点 + 起终点 + 脉冲当前位置。
/// 输入尺寸为底图实际像素尺寸；坐标按 w/h 缩放。
/// [progress] 0~1 控制路径逐段显现；[currentPos] 为像素坐标的当前位置；
/// [pulse] 0~1 驱动脉冲扩散动画。
class PatrolOverlayPainter extends CustomPainter {
  final List<Offset> pts; // 已按像素缩放的绝对坐标
  final List<int> cpIdxs;
  final double progress;
  final Offset? currentPos;
  final double pulse;
  // P1：穿墙段下标（与 _RouteEditorPainter 一致语义：i 对应 pts[i]→pts[i+1]）；
  // 巡场页加载墙线后计算一次传入，未校准时为空集。
  final Set<int> crossingSegs;
  const PatrolOverlayPainter({
    required this.pts,
    required this.cpIdxs,
    this.progress = 1.0,
    this.currentPos,
    this.pulse = 0,
    this.crossingSegs = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    final full = roundPolyline(pts, 2.5);

    // 1. 完整路径（蓝色细线，对齐原型：路径始终可见，仅颜色区分已走/未走）
    final basePaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(full, basePaint);

    // 1.1 P1：穿墙段红色覆盖（画在蓝线之上，与橙色"已走"不冲突）
    if (crossingSegs.isNotEmpty) {
      final redPaint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final i in crossingSegs) {
        if (i + 1 >= pts.length) continue;
        canvas.drawLine(pts[i], pts[i + 1], redPaint);
      }
    }

    // 2. 已走路径（橙色高亮覆盖在蓝线之上，0 进度时不画）
    if (p > 0.003) {
      final metric = full.computeMetrics().first;
      final walked = metric.extractPath(0, metric.length * p);
      final walkedPaint = Paint()
        ..color = const Color(0xFFEA580C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(walked, walkedPaint);
    }

    // 3. 检查点（蓝色实心圆 + 白边）：始终显眼
    final cpFill = Paint()..color = const Color(0xFF1D4ED8);
    final cpStroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (final i in cpIdxs) {
      canvas.drawCircle(pts[i], 2.6, cpStroke);
      canvas.drawCircle(pts[i], 2.6, cpFill);
    }

    // 4. 起点（绿）：常亮小圆
    canvas.drawCircle(
        pts.first, 2.4,
        Paint()
          ..color = const Color(0xFF16A34A)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        pts.first, 2.4,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);

    // 5. 终点（红）：仅巡场结束高亮
    final endPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;
    final endStroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(pts.last, 2.4, endStroke);
    endPaint.color = endPaint.color.withValues(alpha: p >= 1 ? 1 : 0.35);
    canvas.drawCircle(pts.last, 2.4, endPaint);

    // 6. 当前位置：蓝色原点 + 双层呼吸扩散圈（pulse 0~1）
    //    idle 时 currentPos == null → 默认在 pts.first
    final pos = currentPos ?? pts.first;
    final breathR1 = 6.0 + pulse * 10.0; // 外圈：扩张+渐隐
    final breathA1 = (1 - pulse) * 0.45;
    final breathR2 = 4.0 + pulse * 6.5; // 内圈：小一些
    final breathA2 = (1 - pulse) * 0.7;
    canvas.drawCircle(
        pos,
        breathR1,
        Paint()
          ..color = const Color(0xFF3B82F6).withValues(alpha: breathA1));
    canvas.drawCircle(
        pos,
        breathR2,
        Paint()
          ..color = const Color(0xFF60A5FA).withValues(alpha: breathA2));
    // 中心实心蓝点 + 白边
    canvas.drawCircle(
        pos, 2.8,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        pos, 2.8,
        Paint()
          ..color = const Color(0xFF1D4ED8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
    canvas.drawCircle(
        pos, 1.6,
        Paint()
          ..color = const Color(0xFF1D4ED8)
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant PatrolOverlayPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.currentPos != currentPos ||
      oldDelegate.pulse != pulse ||
      oldDelegate.crossingSegs != crossingSegs;
}