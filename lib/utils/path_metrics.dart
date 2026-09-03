import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/utils/cad_coord.dart';
import '../data/models.dart';

/// 巡场路径工具：从 HTML demo 的 app.js（patrolPath / patrolCheckpoints / roundPolyline）移植。
/// 坐标体系：相对坐标 0~100（0-100% 底图），与 SVG viewBox="0 0 100 100" 一致。
///
/// 注意：`patrolPathPoints` / `patrolCheckpoints` 业务常量已迁移至
/// `lib/data/mock/mock_data.dart` 的 `seedPatrolPlans`（见 PATROL_OPTIMIZE.md），
/// 本文件仅保留纯算法：roundPolyline / catmullRomSpline / pointAtProgress / realRouteKm / PatrolOverlayPainter。

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

/// Catmull-Rom 样条平滑（α=0.5 中心化版本）：把折线点序列转为 C1 连续平滑曲线，
/// 输出 `Path`。`samplesPerSeg` 为每两点之间的插值采样数（越大越平滑），建议 12~20。
///
/// 行为：首尾用首末点自身作为虚拟邻点（闭式外推），保证端点不动；中间点作为控制点。
/// 转角处自然圆滑，更像人走的"弧线"，而非直角折线。
Path catmullRomPath(List<Offset> pts, {double samplesPerSeg = 16}) {
  final path = Path();
  if (pts.isEmpty) return path;
  if (pts.length < 3) {
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    return path;
  }
  path.moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = i == 0 ? pts[0] : pts[i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = i + 2 < pts.length ? pts[i + 2] : pts.last;
    final steps = math.max(2, samplesPerSeg.round());
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final t2 = t * t;
      final t3 = t2 * t;
      // Catmull-Rom basis（uniform，α=0.5 → tension 0.5 的 centripetal 近似）
      final x = 0.5 *
          ((2 * p1.dx) +
              (-p0.dx + p2.dx) * t +
              (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
              (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3);
      final y = 0.5 *
          ((2 * p1.dy) +
              (-p0.dy + p2.dy) * t +
              (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
              (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3);
      path.lineTo(x, y);
    }
  }
  return path;
}

/// 对 Catmull-Rom 采样生成密集点（默认 16 点/段），返回降采样用于绘制与插值。
List<Offset> catmullRomSamples(List<Offset> pts, {double samplesPerSeg = 16}) {
  final out = <Offset>[];
  if (pts.isEmpty) return out;
  if (pts.length < 3) return List.of(pts);
  out.add(pts[0]);
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = i == 0 ? pts[0] : pts[i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = i + 2 < pts.length ? pts[i + 2] : pts.last;
    final steps = math.max(2, samplesPerSeg.round());
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final t2 = t * t;
      final t3 = t2 * t;
      final x = 0.5 *
          ((2 * p1.dx) +
              (-p0.dx + p2.dx) * t +
              (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
              (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3);
      final y = 0.5 *
          ((2 * p1.dy) +
              (-p0.dy + p2.dy) * t +
              (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
              (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3);
      out.add(Offset(x, y));
    }
  }
  return out;
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
///
/// 主路径用 Catmull-Rom 样条平滑（更像"人走"的弧线，而不是直角折线）；
/// [historyTracks] 叠加快照中已走过的历史轨迹（按时间倒序，色相由冷到暖、宽度递减）。
class PatrolOverlayPainter extends CustomPainter {
  final List<Offset> pts; // 已按像素缩放的绝对坐标
  final List<int> cpIdxs;
  final double progress;
  final Offset? currentPos;
  final double pulse;
  // P1：穿墙段下标（与 _RouteEditorPainter 一致语义：i 对应 pts[i]→pts[i+1]）；
  // 巡场页加载墙线后计算一次传入，未校准时为空集。
  final Set<int> crossingSegs;
  // 历史轨迹（已按底图缩放的绝对坐标）。空时仅画主路径。
  final List<List<Offset>> historyTracks;
  // 历史轨迹颜色（与 historyTracks 一一对应）。
  final List<Color> historyColors;
  // 任务2：已打卡的检查点下标集合。空时保持原蓝色绘制（向后兼容）。
  final Set<int> checkedInIdxs;
  const PatrolOverlayPainter({
    required this.pts,
    required this.cpIdxs,
    this.progress = 1.0,
    this.currentPos,
    this.pulse = 0,
    this.crossingSegs = const {},
    this.historyTracks = const [],
    this.historyColors = const [],
    this.checkedInIdxs = const {},
  });

  /// 检查点颜色：绿=已打卡；红=已经过但未打卡（漏检）；蓝=未到达。
  /// 按折线弧长 fraction 与当前进度比较判定"是否已经过"。
  Color _cpColor(int idx, double p) {
    if (checkedInIdxs.contains(idx)) return const Color(0xFF16A34A);
    if (pts.length < 2) return const Color(0xFF1D4ED8);
    var total = 0.0, cum = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final d = (pts[i] - pts[i - 1]).distance;
      total += d;
      if (i <= idx) cum += d;
    }
    if (total <= 0) return const Color(0xFF1D4ED8);
    return cum / total <= p ? const Color(0xFFEF4444) : const Color(0xFF1D4ED8);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);

    // 0. 历史轨迹（最底层、半透明样条，给主路径让位感）
    for (var k = 0; k < historyTracks.length; k++) {
      final track = historyTracks[k];
      if (track.length < 2) continue;
      final c = k < historyColors.length
          ? historyColors[k]
          : const Color(0xFF6B7280);
      final hp = catmullRomPath(track, samplesPerSeg: 10);
      final paint = Paint()
        ..color = c.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(hp, paint);
    }

    // 1. 主路径：Catmull-Rom 平滑样条（替代 roundPolyline 的小圆角折线，更像人走）
    final full = catmullRomPath(pts, samplesPerSeg: 16);

    final basePaint = Paint()
      ..color = const Color(0xFF0395FF).withValues(alpha: 0.7) // 主路径线：主色 0395FF
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(full, basePaint);

    // 1.1 P1：穿墙段红色覆盖（画在蓝线之上，与橙色"已走"不冲突）
    if (crossingSegs.isNotEmpty) {
      final redPaint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.7)
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
      final metrics = full.computeMetrics().toList();
      // 样条可能产生多段（理论上单段），取首段绘制已走部分。
      final metric = metrics.isNotEmpty
          ? metrics.first
          : (Path()..moveTo(pts.first.dx, pts.first.dy)).computeMetrics().first;
      final walked = metric.extractPath(0, metric.length * p);
      final walkedPaint = Paint()
        ..color = const Color(0xFFFF9500) // 已巡场走过的路线：FF9500
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(walked, walkedPaint);
    }

    // 3. 检查点（实心圆 + 白边 + 白心）：绿=已打卡 / 红=已过未打(漏检) / 蓝=未到达
    final cpStroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final i in cpIdxs) {
      canvas.drawCircle(pts[i], 7, cpStroke);
      canvas.drawCircle(pts[i], 6.5, Paint()..color = _cpColor(i, p));
      canvas.drawCircle(pts[i], 2.2, Paint()..color = const Color(0xFFFFFFFF));
    }

    // 4. 起点（绿）：与检查点同尺寸语言
    canvas.drawCircle(
        pts.first, 7,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawCircle(
        pts.first, 6.5,
        Paint()
          ..color = const Color(0xFF00B84A) // 起点绿 00B84A
          ..style = PaintingStyle.fill);

    // 5. 终点（红）：仅巡场结束高亮，与检查点同尺寸语言
    final endPaint = Paint()
      ..color = const Color(0xFFFF4444) // 终点红 FF4444，无透明度
      ..style = PaintingStyle.fill;
    final endStroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pts.last, 7, endStroke);
    canvas.drawCircle(pts.last, 6.5, endPaint);

    // 6. 当前位置：蓝色原点 + 双层呼吸扩散圈（pulse 0~1）
    //    idle 时 currentPos == null → 默认在 pts.first
    final pos = currentPos ?? pts.first;
    final breathR1 = 12.0 + pulse * 16.0; // 外圈：基准放大，扩张+渐隐
    final breathA1 = (1 - pulse) * 0.45;
    final breathR2 = 8.5 + pulse * 12.0; // 内圈：小一些，基准相应放大
    final breathA2 = (1 - pulse) * 0.7;
    canvas.drawCircle(
        pos,
        breathR1,
        Paint()
          ..color = const Color(0xFF0395FF).withValues(alpha: breathA1));
    canvas.drawCircle(
        pos,
        breathR2,
        Paint()
          ..color = const Color(0xFF0395FF).withValues(alpha: breathA2));
    // 中心实心蓝点 + 白边（主色 0395FF，大小 6 / 描边 2）
    canvas.drawCircle(
        pos, 6.0,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        pos, 6.0,
        Paint()
          ..color = const Color(0xFF0395FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0);
    canvas.drawCircle(
        pos, 3.0,
        Paint()
          ..color = const Color(0xFF0395FF)
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant PatrolOverlayPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.currentPos != currentPos ||
      oldDelegate.pulse != pulse ||
      oldDelegate.crossingSegs != crossingSegs ||
      oldDelegate.historyTracks.length != historyTracks.length ||
      oldDelegate.historyColors.length != historyColors.length;
}