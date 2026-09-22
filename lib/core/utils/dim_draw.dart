/// 工程制图风格的尺寸标注绘制（按制图习惯，替代"线段 + 浮标签"）。
///
/// 构成（`drawLinearDimension`）：
/// - **尺寸界线**：两端各一条垂直于尺寸线的短线（略超出尺寸线两端）；
/// - **尺寸线**：连接两界线的直线，端点画 **45° 斜短线**（建筑制图常用，
///   比实心箭头更常见，且在照片上也不糊）；
/// - **尺寸数字**：写在尺寸线中部上方，带**白色描边**（halo），
///   保证压在照片/网格上仍清晰，不遮挡被测物体。
///
/// 与"量尺宝"的差异：量尺宝用黄底胶囊标签（消费级观感）；我们按工程习惯走
/// 尺寸线+数字，颜色由调用方给（深色底用亮色、浅色底用深色）。
///
/// 纯绘制函数（只依赖 `painting`），Flutter 画布与**离屏图片导出**
/// 共用同一套画法，保证"屏幕看到的"和"导出的图"完全一致。
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// 线性尺寸标注。
///
/// [a]/[b] 为被测两点（画布坐标）；[text] 为尺寸数字文本（如 `900` 或 `900 mm`）。
/// [aboveSide] 为 true 时数字画在尺寸线"上方"（相对屏幕 y 负方向），
/// 否则画在下方——用于避免与照片内容重叠。
void drawLinearDimension(
  Canvas canvas, {
  required Offset a,
  required Offset b,
  required String text,
  required Color color,
  double fontSize = 12,
  double strokeWidth = 1.4,
  double extLine = 6,
  double tickLen = 6,
  double textGap = 4,
  bool aboveSide = true,
}) {
  final span = (b - a).distance;
  if (span < 0.5) return;
  final dir = (b - a) / span;
  // 尺寸线法向（垂直方向）
  final nrm = Offset(-dir.dy, dir.dx);

  final line = Paint()
    ..color = color
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round;
  final thin = Paint()
    ..color = color.withValues(alpha: 0.85)
    ..strokeWidth = strokeWidth * 0.8
    ..strokeCap = StrokeCap.round;

  // ① 尺寸界线：两端垂直于尺寸线的短线（各向外延伸 extLine）
  canvas.drawLine(a - nrm * extLine, a + nrm * extLine, thin);
  canvas.drawLine(b - nrm * extLine, b + nrm * extLine, thin);

  // ② 尺寸线
  canvas.drawLine(a, b, line);

  // ③ 端点 45° 斜短线（建筑制图起止符）
  void tick(Offset p) {
    final d1 = dir * (tickLen / 2);
    final d2 = nrm * (tickLen / 2);
    canvas.drawLine(p - d1 + d2, p + d1 - d2, line);
  }

  tick(a);
  tick(b);

  // ④ 尺寸数字（带白色 halo，压在照片上也读得清）
  final side = aboveSide ? -1.0 : 1.0;
  final mid = (a + b) / 2 + nrm * (side * (textGap + fontSize * 0.75));
  _drawHaloText(
    canvas,
    text,
    mid,
    color: color,
    fontSize: fontSize,
    haloColor: const Color(0xE6FFFFFF),
  );
}

/// 面积/体积等"面域"标注：半透明填充 + 虚线边界 + 居中大字。
void drawAreaAnnotation(
  Canvas canvas, {
  required List<Offset> polygon,
  required String text,
  required Color color,
  double fontSize = 18,
  bool fill = true,
  bool dashed = true,
}) {
  if (polygon.length < 3) return;
  final path = Path()..moveTo(polygon.first.dx, polygon.first.dy);
  for (final p in polygon.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();

  if (fill) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.16),
    );
  }
  if (dashed) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.9);
    for (var i = 0; i < polygon.length; i++) {
      _drawDashedLine(
        canvas,
        polygon[i],
        polygon[(i + 1) % polygon.length],
        outline,
      );
    }
  }

  // 面积标注画在形心（用顶点平均值近似，够用且稳定）
  var cx = 0.0, cy = 0.0;
  for (final p in polygon) {
    cx += p.dx;
    cy += p.dy;
  }
  cx /= polygon.length;
  cy /= polygon.length;
  _drawHaloText(
    canvas,
    text,
    Offset(cx, cy),
    color: color,
    fontSize: fontSize,
    haloColor: const Color(0xE6FFFFFF),
    bold: true,
  );
}

/// 虚线（供面域边界/辅助线使用）。
void drawDashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  double dash = 6,
  double gap = 4,
}) =>
    _drawDashedLine(canvas, a, b, paint, dash: dash, gap: gap);

void _drawDashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  double dash = 6,
  double gap = 4,
}) {
  final total = (b - a).distance;
  if (total < 1) return;
  final dir = (b - a) / total;
  var t = 0.0;
  while (t < total) {
    final t2 = math.min(t + dash, total);
    canvas.drawLine(a + dir * t, a + dir * t2, paint);
    t = t2 + gap;
  }
}

/// 带描边的文字（先描白边再填色），保证压在照片上可读。
void _drawHaloText(
  Canvas canvas,
  String text,
  Offset center, {
  required Color color,
  required double fontSize,
  required Color haloColor,
  bool bold = false,
}) {
  if (text.isEmpty) return;
  final base = TextStyle(
    fontSize: fontSize,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
    height: 1.15,
  );
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: base.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = haloColor,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

  final fill = TextPainter(
    text: TextSpan(text: text, style: base.copyWith(color: color)),
    textDirection: TextDirection.ltr,
  )..layout();
  fill.paint(
      canvas, Offset(center.dx - fill.width / 2, center.dy - fill.height / 2));
}

/// 把尺寸数值格式化为制图习惯文本（mm 取整，不写单位时由调用方决定）。
String dimText(num mm, {bool withUnit = false}) =>
    withUnit ? '${mm.round()} mm' : '${mm.round()}';
