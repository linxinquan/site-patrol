/// AR / 照片量尺的**叠加样式库**（对齐参考样式：量尺宝式）。
///
/// 参考样式要点（用户提供 4 张样张）：
/// 1. 线：**明黄细实线**（不是黑/绿粗线）；
/// 2. 端点：**空心方块**（不是实心圆点，也不带 A/B 字母）；
/// 3. 标注：**胶囊**（深底半透明 + 黄描边 + 白字），竖边上的标注**旋转 90°**；
/// 4. 面积：半透明黄**面域填充** + 实线外框 + 两条**虚线对角线** + 中央大字 `6.250m²`；
/// 5. 体积：黄色**立方体线框**（前景实线 / 后侧虚线）+ 三边尺寸胶囊 + 中央大字 `8.000m³`；
/// 6. 长度用 `m` + 3 位小数（`2.236m`），不足 1m 用 `mm` 整数（`900mm`）。
///
/// 集中在这里的原因：AR 原生视图（画在相机上）、Web 预览painter、以及导出图
/// 三处都要"同一种观感"，各画一套必然走样。
library;

import 'dart:math' as math;
import 'dart:ui'
    show
        Canvas,
        Color,
        Offset,
        Paint,
        PaintingStyle,
        Path,
        RRect,
        Radius,
        Rect,
        Size,
        StrokeCap,
        TextDirection;

import 'package:flutter/painting.dart'
    show FontWeight, TextPainter, TextSpan, TextStyle;

import 'mm_format.dart';

/// 主色：明黄（描边/线/端点）。
const Color kMeasureYellow = Color(0xFFFFC400);

/// 面域填充色（半透明黄）。
const Color kMeasureFill = Color(0x40FFC400);

/// 标注文字色（压在面上时用深墨色，保证浅底可读）。
const Color kMeasureInk = Color(0xFF1B1B1B);

/// 胶囊底（深色半透明）。
const Color kMeasureCapsuleBg = Color(0xE6101010);

/// 长度文案（参考样式）：≥1m 用 `m` + 3 位小数，否则 `mm` 取整。
String fmtLengthText(double mm) => mm.abs() >= 1000
    ? '${(mm / 1000).toStringAsFixed(3)}m'
    : '${fmtMm(mm)}mm';

/// 面积大字（参考样式 `6.250m²`）：3 位小数，无空格。
String fmtAreaText(double m2) => '${m2.toStringAsFixed(3)}m²';

/// 体积大字（参考样式 `8.000m³`）：3 位小数，无空格。
String fmtVolumeText(double m3) => '${m3.toStringAsFixed(3)}m³';

/// 尺寸线：黄细线 + 两端**空心方块** + 中点**胶囊**标签。
///
/// [tick] 为端点方块边长（屏幕像素）；[lineWidth] 为线宽。
void paintDimLine(
  Canvas canvas,
  Offset a,
  Offset b,
  String label, {
  bool showLabel = true,
  double lineWidth = 2.4,
  double tick = 11,
  bool vertical = false,
  String? fontFamily,
}) {
  final stroke = Paint()
    ..color = kMeasureYellow
    ..strokeWidth = lineWidth
    ..strokeCap = StrokeCap.square
    ..style = PaintingStyle.stroke;
  canvas.drawLine(a, b, stroke);
  _paintSquareHandle(canvas, a, tick);
  _paintSquareHandle(canvas, b, tick);
  if (!showLabel || label.isEmpty) return;
  paintCapsuleLabel(
    canvas,
    (a + b) / 2,
    label,
    vertical: vertical,
    fontFamily: fontFamily,
  );
}

/// 端点空心方块（白底 + 黄描边），与参考样张一致。
void _paintSquareHandle(Canvas canvas, Offset c, double size) {
  final rect = Rect.fromCenter(center: c, width: size, height: size);
  canvas.drawRect(
    rect,
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill,
  );
  canvas.drawRect(
    rect,
    Paint()
      ..color = kMeasureYellow
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke,
  );
}

/// 胶囊标签：深底半透明 + 黄描边 + 白字；[vertical]=true 时旋转 90°（竖边标注）。
void paintCapsuleLabel(
  Canvas canvas,
  Offset center,
  String text, {
  bool vertical = false,
  Color accent = kMeasureYellow,
  Color bg = kMeasureCapsuleBg,
  double fontSize = 13,
  String? fontFamily,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        fontFamily: fontFamily,
        color: const Color(0xFFFFFFFF),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  const padX = 9.0, padY = 5.0;
  final w = tp.width + padX * 2;
  final h = tp.height + padY * 2;
  // 旋转后包围盒需要交换宽高，才能让胶囊贴合文字
  final rw = vertical ? h : w;
  final rh = vertical ? w : h;
  final rect = RRect.fromRectAndRadius(
    Rect.fromCenter(center: center, width: rw, height: rh),
    Radius.circular(rh / 2),
  );
  canvas.drawRRect(rect, Paint()..color = bg..style = PaintingStyle.fill);
  canvas.drawRRect(
    rect,
    Paint()
      ..color = accent
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke,
  );
  canvas.save();
  canvas.translate(center.dx, center.dy);
  if (vertical) canvas.rotate(math.pi / 2);
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();
}

/// 面积叠加：半透明黄面域 + 实线外框 + **虚线对角线** + 中央大字。
void paintAreaFace(Canvas canvas, List<Offset> poly, String centerText,
    {String? fontFamily}) {
  if (poly.length < 3) return;
  final path = Path()..addPolygon(poly, true);
  canvas.drawPath(path, Paint()..color = kMeasureFill..style = PaintingStyle.fill);
  canvas.drawPath(
    path,
    Paint()
      ..color = kMeasureYellow
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke,
  );
  // 两条对角线（虚线）——参考样式里用来"填满"面的观感
  final dash = Paint()
    ..color = kMeasureYellow.withValues(alpha: 0.85)
    ..strokeWidth = 1.4;
  paintDashedLine(canvas, poly[0], poly[2], dash);
  if (poly.length >= 4) paintDashedLine(canvas, poly[1], poly[3], dash);
  _paintCenterText(canvas, path.getBounds().center, centerText,
      fontFamily: fontFamily);
}

/// 体积叠加：**可见边实线 + 隐藏边虚线** + 高尺寸胶囊 + 中央大字。
///
/// [base] 为底面四个角，顺序必须是**近左 → 近右 → 远右 → 远左**（顺时针），
/// [rise] 为向上的屏幕位移向量（如 `Offset(0, -140)`）。
///
/// 隐藏边（远右角相关的三条）用虚线，与参考样张一致——体积图上"看不见的边"
/// 若画成实线，会让人误判轮廓。
void paintVolumeWire(
  Canvas canvas,
  List<Offset> base,
  Offset rise, {
  required String hLabel,
  required String centerText,
  String? fontFamily,
}) {
  if (base.length < 4) return;
  final top = [for (final p in base) p + rise];
  final solid = Paint()
    ..color = kMeasureYellow
    ..strokeWidth = 2.4
    ..style = PaintingStyle.stroke;
  final dash = Paint()
    ..color = kMeasureYellow.withValues(alpha: 0.9)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  // 底面：近边与两侧边可见；远右→远左（隐藏边）虚线
  canvas.drawLine(base[0], base[1], solid);
  canvas.drawLine(base[1], base[2], solid);
  canvas.drawLine(base[3], base[0], solid);
  paintDashedLine(canvas, base[2], base[3], dash);
  // 竖边：近左 / 近右 / 远左可见；远右（隐藏）虚线
  canvas.drawLine(base[0], top[0], solid);
  canvas.drawLine(base[1], top[1], solid);
  canvas.drawLine(base[3], top[3], solid);
  paintDashedLine(canvas, base[2], top[2], dash);
  // 顶面：与底面对应
  canvas.drawLine(top[0], top[1], solid);
  canvas.drawLine(top[1], top[2], solid);
  canvas.drawLine(top[3], top[0], solid);
  paintDashedLine(canvas, top[2], top[3], dash);

  // 竖向尺寸（高）标注在近左竖边旁（参考样张：竖排胶囊）
  paintCapsuleLabel(canvas, (base[0] + top[0]) / 2, hLabel,
      vertical: true, fontFamily: fontFamily);
  // 中央大字（体心投影处）
  final center = Offset(
    (base[0].dx + base[2].dx) / 2,
    (base[0].dy + base[2].dy) / 2 + rise.dy / 2,
  );
  _paintCenterText(canvas, center, centerText, fontFamily: fontFamily);
}

/// 中央大字（参考样式：深墨色、字重中等、压在面上）。
void _paintCenterText(Canvas canvas, Offset center, String text,
    {double fontSize = 30, String? fontFamily}) {
  if (text.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        fontFamily: fontFamily,
        color: kMeasureInk,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
}

void paintDashedLine(Canvas canvas, Offset a, Offset b, Paint p,
    {double dash = 12, double gap = 9}) {
  final total = (b - a).distance;
  if (total < 1) return;
  final dir = (b - a) / total;
  var t = 0.0;
  while (t < total) {
    final t2 = math.min(t + dash, total);
    canvas.drawLine(a + dir * t, a + dir * t2, p);
    t = t2 + gap;
  }
}

/// 预览/示意用：按**真实长宽比例**合成一个居中的面域矩形。
///
/// 用于 Web 预览与导出示意——没有 AR 空间坐标时，几何只能是示意，
/// 但**比例来自真实读数**（长宽比正确，观感与参考样张一致）。
Rect synthFaceRect(Size size, double aMm, double bMm) {
  if (aMm <= 0 || bMm <= 0) {
    return Rect.fromCenter(
        center: size.center(Offset.zero), width: 0, height: 0);
  }
  final maxW = size.width * 0.72;
  final maxH = size.height * 0.62;
  // 以"长边贴上限"为准，等比缩放，保证面域留在视口内
  final scale = math.min(maxW / aMm, maxH / bMm);
  final w = aMm * scale;
  final h = bMm * scale;
  return Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
}

/// 预览/示意用：按真实 长/宽/高 合成体积线框的底面四角与上移向量。
///
/// 用**斜二测**画法（前立面正视图 + 30° 纵深方向），与参考样张的立方体一致：
/// - 长 = 前立面横向边长（w）
/// - 高 = 竖向边长（rise）
/// - 宽 = 纵深边长（沿 30° 方向：dx=0.87d, dy=-0.5d）
///
/// 返回的 [base] 顺序固定为 **近左 → 近右 → 远右 → 远左**，
/// 供 [paintVolumeWire] 判定"可见边实线 / 隐藏边虚线"。
({List<Offset> base, Offset rise}) synthVolumeGeometry(
  Size size,
  double lengthMm,
  double widthMm,
  double heightMm,
) {
  if (lengthMm <= 0 || widthMm <= 0 || heightMm <= 0) {
    return (base: const <Offset>[], rise: Offset.zero);
  }
  final maxW = size.width * 0.58; // 长 + 纵深横向投影的总宽上限
  final maxH = size.height * 0.52; // 高 + 纵深竖向投影的总高上限
  const k = 0.87, s = 0.5; // 30° 纵深的横/纵分量
  // 等比缩放：让 (长 + 0.87宽) 与 (高 + 0.5宽) 同时不越界
  final scale = math.min(
    maxW / (lengthMm + widthMm * k),
    maxH / (heightMm + widthMm * s),
  );
  final w = lengthMm * scale;
  final h = heightMm * scale;
  final d = widthMm * scale;
  final off = Offset(d * k, -d * s);
  final center = size.center(Offset.zero);
  // 以"长+纵深"的横向中心、"高+纵深"的竖向中心为锚点摆放
  final left = center.dx - (w + off.dx) / 2;
  final frontBottomY = center.dy + (h - off.dy) / 2;
  final base = <Offset>[
    Offset(left, frontBottomY),
    Offset(left + w, frontBottomY),
    Offset(left + w + off.dx, frontBottomY + off.dy),
    Offset(left + off.dx, frontBottomY + off.dy),
  ];
  return (base: base, rise: Offset(0, -h));
}


