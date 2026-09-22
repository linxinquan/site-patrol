/// 图片导出：把「测量图 / 户型图」离屏渲染成 PNG。
///
/// 为什么用离屏 Canvas 而不是截屏组件：
/// 1. 截屏只能拿到屏幕分辨率，导出图会糊；离屏画布可以按原始照片尺寸输出；
/// 2. 不受当前缩放/滚动位置影响，导出内容稳定可复现；
/// 3. 复用 `dim_draw.dart` 的工程标注画法 → **屏幕看到的与导出的图一致**。
///
/// 输出字节交给 `report_share.dart` 的 `exportReportFile`：
/// - Web：浏览器下载；
/// - iOS/Android：系统分享面板（用户选「存储图像」即进相册）；
/// - 桌面：落盘到下载目录。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../data/models.dart';
import 'dim_draw.dart';
import 'mm_format.dart';

/// 一条待标注的尺寸（画布坐标 + 文本）。
typedef DiagramDim = ({Offset a, Offset b, String text});

/// 导出「测量图」：现场照片 + 工程样式尺寸标注 + 底部图签。
///
/// [dims] 使用**照片像素坐标**（与 `PhotoCalib` 同一坐标系）。
/// 返回 PNG 字节；照片无法解码时返回 null（调用方提示用户）。
Future<Uint8List?> renderMeasureDiagramPng({
  required Uint8List photoBytes,
  required List<DiagramDim> dims,
  String title = '现场测量图',
  String subtitle = '',
  double signHeight = 58,
}) async {
  final image = await _decode(photoBytes);
  if (image == null) return null;

  final w = image.width.toDouble();
  final h = image.height.toDouble() + signHeight;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // 白底（照片可能带透明通道）
  canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawImage(image, Offset.zero, Paint());

  // 尺寸标注：制图习惯配色（深色线 + 白色 halo 数字），压在照片上可读
  for (final d in dims) {
    drawLinearDimension(
      canvas,
      a: d.a,
      b: d.b,
      text: d.text,
      color: const Color(0xFFE0342B),
      fontSize: math.max(12, w / 90),
      strokeWidth: math.max(1.4, w / 900),
      extLine: math.max(6, w / 160),
      tickLen: math.max(6, w / 160),
    );
  }

  _drawTitleBlock(
    canvas,
    Rect.fromLTWH(0, image.height.toDouble(), w, signHeight),
    title: title,
    subtitle: subtitle,
    width: w,
  );

  return _encode(recorder, w, h);
}

/// 导出「户型图/测量图」：房间轮廓 + 墙段尺寸 + 洞口 + 面积/闭合差 + 图签。
///
/// 坐标为 `RoomScanRecord` 的世界毫米坐标（x 向右、y 向下），内部自动缩放适配画布。
Future<Uint8List> renderRoomDiagramPng({
  required RoomScanRecord record,
  String? projectName,
  String? dateText,
  int width = 1600,
  int height = 1200,
  double margin = 120,
  double signHeight = 58,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFFAFAFA));

  final pts = [for (final w in record.walls) Offset(w.ax, w.ay)];
  if (pts.isEmpty) {
    return _encode(recorder, width.toDouble(), height.toDouble());
  }

  // 世界坐标 → 画布坐标（等比缩放 + 居中）
  var minX = pts.first.dx, maxX = pts.first.dx;
  var minY = pts.first.dy, maxY = pts.first.dy;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  final drawW = width - margin * 2;
  final drawH = height - margin * 2 - signHeight;
  final spanX = math.max(maxX - minX, 1.0);
  final spanY = math.max(maxY - minY, 1.0);
  final scale = math.min(drawW / spanX, drawH / spanY);
  final offX = margin + (drawW - spanX * scale) / 2;
  final offY = margin + (drawH - spanY * scale) / 2;
  Offset toCanvas(Offset p) =>
      Offset(offX + (p.dx - minX) * scale, offY + (p.dy - minY) * scale);

  final canvasPts = [for (final p in pts) toCanvas(p)];

  // 墙体：按墙厚等比加粗（下限 2px 保证可见）
  final wallStroke = math.max(
    2.0,
    (record.walls.first.thicknessMm ?? 200) * scale,
  );
  final wallPaint = Paint()
    ..color = const Color(0xFF30323A)
    ..strokeWidth = wallStroke
    ..strokeCap = StrokeCap.square
    ..style = PaintingStyle.stroke;
  final path = Path()..moveTo(canvasPts.first.dx, canvasPts.first.dy);
  for (final p in canvasPts.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  canvas.drawPath(path, wallPaint);

  // 洞口：在墙上留白（门/窗用不同宽度示意）
  for (var i = 0; i < record.walls.length; i++) {
    final wall = record.walls[i];
    final a = canvasPts[i];
    final b = canvasPts[(i + 1) % canvasPts.length];
    final len = (b - a).distance;
    if (len < 1) continue;
    final dir = (b - a) / len;
    for (final op in wall.openings) {
      final wallLenMm = wall.lengthMm <= 0 ? 1.0 : wall.lengthMm;
      final u0 = (op.offsetFromMm / wallLenMm).clamp(0.0, 1.0);
      final u1 = ((op.offsetFromMm + op.widthMm) / wallLenMm).clamp(0.0, 1.0);
      canvas.drawLine(
        a + dir * (len * u0),
        a + dir * (len * u1),
        Paint()
          ..color = const Color(0xFFFAFAFA)
          ..strokeWidth = wallStroke + 2,
      );
    }
  }

  // 墙段尺寸：工程样式，数字只写数值（单位在图签注明 mm）
  for (var i = 0; i < record.walls.length; i++) {
    final a = canvasPts[i];
    final b = canvasPts[(i + 1) % canvasPts.length];
    if ((b - a).distance < 40) continue; // 太短不标，避免糊成一团
    drawLinearDimension(
      canvas,
      a: a,
      b: b,
      text: fmtMm(record.walls[i].lengthMm),
      color: const Color(0xFFE0342B),
      fontSize: 15,
      strokeWidth: 1.4,
      extLine: 8,
      tickLen: 8,
    );
  }

  // 面积（面域标注样式）：mm² → m²
  final areaM2 = _areaMm2(pts) / 1e6;
  drawAreaAnnotation(
    canvas,
    polygon: canvasPts,
    text: '${record.name}  ${areaM2.toStringAsFixed(2)} ㎡',
    color: const Color(0xFF0284E8),
    fontSize: 26,
  );

  _drawTitleBlock(
    canvas,
    Rect.fromLTWH(0, height - signHeight, width.toDouble(), signHeight),
    title: '${record.name} · ${record.roomUse} · 户型测量图',
    subtitle: [
      if (projectName != null && projectName.isNotEmpty) projectName,
      '尺寸单位：mm',
      if (record.netHeightMm != null) '净高 ${fmtMm(record.netHeightMm!)}',
      if (record.closureDeltaMm != null)
        '闭合差 ${fmtMm(record.closureDeltaMm!)} mm',
      if (dateText != null && dateText.isNotEmpty) dateText,
    ].join('   |   '),
    width: width.toDouble(),
  );

  return _encode(recorder, width.toDouble(), height.toDouble());
}

/// 多边形面积（mm²，鞋带公式）。
double _areaMm2(List<Offset> pts) {
  if (pts.length < 3) return 0;
  var s = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    s += a.dx * b.dy - b.dx * a.dy;
  }
  return s.abs() / 2;
}

/// 底部图签：标题 + 副信息（单位/净高/闭合差/日期），制图图纸标题栏的简化版。
void _drawTitleBlock(
  Canvas canvas,
  Rect rect, {
  required String title,
  required String subtitle,
  required double width,
}) {
  canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawLine(
    Offset(rect.left, rect.top),
    Offset(rect.right, rect.top),
    Paint()
      ..color = const Color(0xFFD0D5DD)
      ..strokeWidth = 1,
  );
  final titleTp = TextPainter(
    text: TextSpan(
      text: title,
      style: TextStyle(
        fontSize: math.max(14, width / 70),
        fontWeight: FontWeight.w700,
        color: const Color(0xFF202224),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  titleTp.paint(canvas, Offset(rect.left + 16, rect.top + 8));

  if (subtitle.isNotEmpty) {
    final subTp = TextPainter(
      text: TextSpan(
        text: subtitle,
        style: TextStyle(
          fontSize: math.max(11, width / 110),
          color: const Color(0xFF60656B),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width - 32);
    subTp.paint(canvas, Offset(rect.left + 16, rect.top + 10 + titleTp.height));
  }
}

Future<ui.Image?> _decode(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}

Future<Uint8List> _encode(ui.PictureRecorder recorder, double w, double h) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(w.round(), h.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List() ?? Uint8List(0);
}
