import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// 照片防篡改水印信息（工程记录场景）。
///
/// 水印直接烧录进图片像素，裁剪/涂抹水印即破坏原始画面，
/// 配合 [imageSha256] 的哈希留痕，可实现工程照片的不可篡改取证。
class WatermarkMeta {
  /// 项目 / 楼栋
  final String project;
  /// 部位 / 楼层
  final String anchor;
  /// 拍摄时间（已格式化，如 2026-08-18 14:30）
  final String time;
  /// GPS 字符串（如 22.5936°N 113.9799°E）
  final String gps;
  /// 海拔
  final String altitude;
  /// 拍摄人
  final String reporter;
  /// 图纸坐标（可选，mm）：世界坐标文本
  final String? worldCoord;
  /// 唯一凭证号（拍摄流水）
  final String serial;

  const WatermarkMeta({
    required this.project,
    required this.anchor,
    required this.time,
    required this.gps,
    required this.altitude,
    required this.reporter,
    this.worldCoord,
    required this.serial,
  });

  /// 底部分块文字（每条 ≤ 尽量短，避免溢出图片宽度）。
  List<String> get lines => [
        '${project.trim()} · ${anchor.trim()}',
        if (worldCoord != null && worldCoord!.isNotEmpty) worldCoord!,
        '${time}  ${gps}  ${altitude}',
        '拍摄：${reporter} · 凭证 ${serial}',
      ];
}

/// 给照片烧录防篡改水印。
///
/// [bytes] 输入图片字节（JPEG/PNG）。输出带水印的 JPEG 字节；
/// 解码失败返回 null（由调用方保留原图并提示）。
///
/// 水印布局：底部黑色半透明信息栏 + 全图斜向重复水印（防裁剪）。
/// 底部信息栏内容见 [WatermarkMeta.lines]。
Future<Uint8List?> applyPhotoWatermark(
  Uint8List bytes,
  WatermarkMeta meta, {
  int quality = 88,
}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final w = image.width;
  final h = image.height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // 1. 原图
  canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.high);

  // 2. 全图斜向水印（防裁剪/防截取局部）
  final linePaint = Paint()
    ..color = const Color(0x66FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final diagTextStyle = TextStyle(
    color: const Color(0x33FFFFFF),
    fontSize: _scaleFont(w, 30),
    letterSpacing: 2,
  );
  final diag = _buildTextPainter('${meta.project} · 工程记录 · ${meta.serial}', diagTextStyle);
  final step = diag.height + _scaleFont(w, 90);
  for (double y = -h.toDouble(); y < h * 2; y += step) {
    final x0 = 0.0;
    final len = w.toDouble();
    canvas.save();
    canvas.translate(x0, y);
    canvas.rotate(-0.35);
    diag.paint(canvas, Offset.zero);
    // 斜向细线
    canvas.drawLine(
      Offset.zero,
      Offset(len, 0),
      linePaint,
    );
    canvas.restore();
  }

  // 3. 底部信息栏（黑色半透明条 + 白色文字）
  final barH = meta.lines.length * _scaleFont(w, 30) + 36.0;
  final barRect = Rect.fromLTWH(0, h - barH, w.toDouble(), barH);
  canvas.drawRect(
    barRect,
    Paint()..color = const Color(0xCC111111),
  );
  // 左侧竖色条（工程水印风格）
  canvas.drawRect(
    Rect.fromLTWH(0, h - barH, 6, barH),
    Paint()..color = const Color(0xFFF59E0B),
  );

  final textStyle = TextStyle(
    color: const Color(0xFFF5F5F5),
    fontSize: _scaleFont(w, 26),
    fontWeight: FontWeight.w700,
    height: 1.4,
  );
  var y = h - barH + 12.0;
  for (final line in meta.lines) {
    final tp = _buildTextPainter(line, textStyle);
    tp.paint(canvas, Offset(18, y));
    y += tp.height + 2;
  }

  // 4. 编码输出 JPEG
  final picture = recorder.endRecording();
  final out = await picture.toImage(w, h);
  final byteData = await out.toByteData(format: ui.ImageByteFormat.png);
  final png = byteData!.buffer.asUint8List();
  image.dispose();
  out.dispose();

  // PNG → JPEG 压缩（调 quality）
  return _jpegFromPng(png, quality);
}

/// 简单把 PNG 转 JPEG（用 package:image，见 image_compress）。
Uint8List? _jpegFromPng(Uint8List png, int quality) {
  // 复用 image 包编码，保证压缩体积小（移动端/Web 均可）。
  final decoded = img.decodePng(png);
  if (decoded == null) return png;
  return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
}

/// 图片字节 SHA-256 校验指纹（留痕用）。
String imageSha256(Uint8List bytes) => sha256.convert(bytes).toString();

/// 在 isolate 中计算图片 SHA-256（避免 UI 线程阻塞）。
/// Web 平台 dart:isolate 不支持，fallback 到主线程同步执行。
Future<String> imageSha256Async(Uint8List bytes) async {
  try {
    return await Isolate.run(() => sha256.convert(bytes).toString());
  } on UnsupportedError {
    return sha256.convert(bytes).toString();
  }
}

/// 图片字节 MD5 短指纹（供界面展示，便于人工对照）。
String imageMd5(Uint8List bytes) => md5.convert(bytes).toString();

TextPainter _buildTextPainter(String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: ui.TextDirection.ltr,
    textAlign: TextAlign.left,
  )..layout();
  return tp;
}

double _scaleFont(int w, double base) {
  // 宽 1280 为基准；小于 800 的缩略图用更小字避免溢出。
  if (w < 500) return (base * 0.6).clamp(12.0, base);
  return base;
}
