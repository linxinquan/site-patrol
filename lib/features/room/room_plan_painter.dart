import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/room/room_geometry.dart';
import '../../core/utils/mm_format.dart';
import '../../data/models.dart';

/// 户型图绘制（列表缩略 / 详情大图共用）。
///
/// 坐标约定：`RoomWall` 端点为 mm 局部坐标；绘制时统一按包围盒等比缩放到
/// 画布尺寸。v1 表现：单线墙 + 填充示意 + 洞口缺口/门弧窗线 + 可选尺寸标注层
/// （用 `dimAnchorFor` 外法向引线）。orthoSnap 高亮（被吸附角小绿点）由
/// [highlightSnapped] 打开时叠加。
class RoomPlanPainter extends CustomPainter {
  final List<RoomWall> walls;
  final bool showDims;
  final String? label; // 如 "主卧 · 15.00㎡"
  final Color wallColor;
  final Color dimColor;
  final Color fillColor;
  final Set<int> highlightedVertices;

  const RoomPlanPainter({
    required this.walls,
    this.showDims = true,
    this.label,
    this.wallColor = const Color(0xFF30323A),
    this.dimColor = const Color(0xFF7A7F8C),
    this.fillColor = const Color(0xFFE9EEF6),
    this.highlightedVertices = const {},
  });

  /// 墙段角点（首→尾），供闭合多边形/标注布局使用。
  List<Offset> get _corners => [
        for (final w in walls) Offset(w.ax, w.ay),
        if (walls.isNotEmpty) Offset(walls.last.bx, walls.last.by),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    if (walls.isEmpty) return;
    final pts = _corners;
    if (pts.length < 2) return;

    // 包围盒与等比缩放（留出标注边距）
    final raw = _bounds(pts);
    final rawW = raw.width, rawH = raw.height;
    if (rawW <= 0 || rawH <= 0) return;
    const pad = 40.0;
    final availW = math.max(20.0, size.width - pad * 2);
    final availH = math.max(20.0, size.height - pad * 2);
    final scale = math.min(availW / rawW, availH / rawH);
    final dw = rawW * scale, dh = rawH * scale;
    final offX = (size.width - dw) / 2;
    final offY = (size.height - dh) / 2;

    Offset map(Offset p) => Offset(offX + (p.dx - raw.left) * scale,
        offY + (p.dy - raw.top) * scale);

    // 房间填充
    if (pts.length >= 3) {
      final path = Path()..addPolygon(pts.map(map).toList(), true);
      canvas.drawPath(path, Paint()..color = fillColor);
    }

    final wallPaint = Paint()
      ..color = wallColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final w in walls) {
      final a = map(Offset(w.ax, w.ay));
      final b = map(Offset(w.bx, w.by));
      canvas.drawLine(a, b, wallPaint);
      _drawOpenings(canvas, map, w);
    }

    // 角点（吸附高亮绿色）
    for (var i = 0; i < pts.length; i++) {
      final c = map(pts[i]);
      canvas.drawCircle(
        c,
        2.2,
        Paint()
          ..color = highlightedVertices.contains(i)
              ? const Color(0xFF1DB954)
              : dimColor,
      );
    }

    // 尺寸标注层
    if (showDims && pts.length >= 3) {
      _drawDims(canvas, map, pts);
    }

    // 面积/名称文字
    if (label != null && pts.isNotEmpty) {
      final c = map(centroid(pts));
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF30323A)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
    }
  }

  /// 洞口：门上画 90° 弧（示意门扇），窗画双线；同时把洞口宽度在墙上"挖空"。
  void _drawOpenings(Canvas canvas, Offset Function(Offset) map, RoomWall w) {
    for (final o in w.openings) {
      final total = w.lengthMm;
      if (total <= 0) continue;
      final u0 = (o.offsetFromMm / total).clamp(0.0, 1.0);
      final u1 = ((o.offsetFromMm + o.widthMm) / total).clamp(0.0, 1.0);
      final a = Offset(w.ax, w.ay);
      final b = Offset(w.bx, w.by);
      final pa = map(Offset(a.dx + (b.dx - a.dx) * u0, a.dy + (b.dy - a.dy) * u0));
      final pb = map(Offset(a.dx + (b.dx - a.dx) * u1, a.dy + (b.dy - a.dy) * u1));
      // 挖空墙线显示洞口
      canvas.drawLine(pa, pb, Paint()
        ..color = fillColor
        ..strokeWidth = 6);
      if (o.type == 'window') {
        // 窗：洞口中线细线示意
        canvas.drawLine(pa, pb, Paint()
          ..color = wallColor
          ..strokeWidth = 1.4);
      } else {
        // 门：洞口内侧一条短垂线示意（v1 从简）
        final dir = (pb - pa);
        final len = dir.distance;
        if (len > 2) {
          final n = Offset(-dir.dy / len, dir.dx / len);
          final mid = (pa + pb) / 2;
          canvas.drawLine(mid, mid + n * 6, Paint()
            ..color = dimColor
            ..strokeWidth = 1.2);
        }
      }
    }
  }

  void _drawDims(
      Canvas canvas, Offset Function(Offset) map, List<Offset> pts) {
    final dimPaint = Paint()
      ..color = dimColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < walls.length; i++) {
      final w = walls[i];
      final anchor = dimAnchorFor(pts, i, offsetPx: 26);
      final mid = map(anchor.mid);
      final labelPos = map(anchor.labelPos);
      canvas.drawLine(mid, labelPos, dimPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: fmtMm(w.lengthMm),
          style: TextStyle(fontSize: 9, color: dimColor, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(labelPos.dx - tp.width / 2, labelPos.dy - tp.height / 2));
    }
  }

  Rect _bounds(List<Offset> pts) {
    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @override
  bool shouldRepaint(covariant RoomPlanPainter old) =>
      old.walls != walls || old.showDims != showDims || old.label != label;
}
