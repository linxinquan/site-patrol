/// AR 标注**样式效果图**生成器 —— 在电脑上核对真机观感。
///
/// 背景：真机标注由 iOS 原生 SceneKit 渲染（`ios/Runner/ArMeasureView.swift`），
/// Windows 上跑不了；这个脚本用**同一套样式规范**（明黄 #FFC400、空心方块端点、
/// 深底胶囊、虚线、中央大字）离屏渲染出 4 种形态，产出 PNG 供在电脑上直接核对。
///
/// 注意：**几何是示意**（按真实读数的比例合成），不是真实 AR 空间坐标；但线型、
/// 胶囊、虚线、大字、配色这些"观感要素"与真机同口径。
///
/// 运行：flutter test tools/ar_style_preview.dart
/// 产出：build/ar_style_preview/{01_line,02_pythagoras,03_area,04_volume}.png
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gongdi_app/core/utils/measure_style.dart';

/// AR 取景的深灰底（纯黑看不出半透明填充的层次）。
const ui.Color _bg = ui.Color(0xFF2B2B31);

const ui.Size _size = ui.Size(720, 960);

/// `flutter test` 环境默认只有测试字体 Ahem（每个字符都是实心方块），
/// 且样式库的 TextStyle 未指定字族时会落到它上面 —— 所以这里显式加载 UI 字体
/// 并用 [fontFamily] 传给每个绘制函数。
const String _font = 'MiSans';

Future<void> _dump(String name, void Function(ui.Canvas) draw) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(
    rec,
    ui.Rect.fromLTWH(0, 0, _size.width, _size.height),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, _size.width, _size.height),
    ui.Paint()..color = _bg,
  );
  draw(canvas);
  final img = await rec
      .endRecording()
      .toImage(_size.width.toInt(), _size.height.toInt());
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  final dir = Directory('build/ar_style_preview')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes);
  img.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File('assets/fonts/MiSans-Regular.ttf').readAsBytesSync();
    await (FontLoader(_font)
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
  });

  test('生成 4 种形态的样式效果图', () async {
    // ① 直线：黄线 + 两端空心方块 + 中点胶囊
    await _dump('01_line', (c) {
      paintDimLine(
        c,
        ui.Offset(_size.width * 0.10, _size.height * 0.60),
        ui.Offset(_size.width * 0.90, _size.height * 0.72),
        '6.990m',
        fontFamily: _font,
      );
    });

    // ② 勾股：斜边实线 + 两条直角边虚线（水平投影 / 高度差）+ 胶囊
    await _dump('02_pythagoras', (c) {
      final a = ui.Offset(_size.width * 0.20, _size.height * 0.80);
      final b = ui.Offset(_size.width * 0.66, _size.height * 0.20);
      final corner = ui.Offset(b.dx, a.dy);
      final dash = ui.Paint()
        ..color = kMeasureYellow.withValues(alpha: 0.9)
        ..strokeWidth = 1.6;
      paintDashedLine(c, a, corner, dash);
      paintDashedLine(c, corner, b, dash);
      paintDimLine(c, a, b, '3.023m', vertical: true, fontFamily: _font);
    });

    // ③ 面积：半透明面域 + 实线外框 + 对角虚线 + 两边胶囊 + 中央大字
    await _dump('03_area', (c) {
      final r = synthFaceRect(_size, 2500, 2500);
      paintAreaFace(
        c,
        [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft],
        '6.250m²',
        fontFamily: _font,
      );
      paintCapsuleLabel(c, ui.Offset(r.left, r.center.dy), '2.500m',
          vertical: true, fontFamily: _font);
      paintCapsuleLabel(c, ui.Offset(r.center.dx, r.bottom), '2.500m',
          fontFamily: _font);
    });

    // ④ 体积：立方体（可见边实线 / 隐藏边虚线）+ 三边胶囊 + 中央大字
    await _dump('04_volume', (c) {
      final g = synthVolumeGeometry(_size, 4000, 1000, 2000);
      paintVolumeWire(c, g.base, g.rise,
          hLabel: '2.000m', centerText: '8.000m³', fontFamily: _font);
      paintCapsuleLabel(c, (g.base[0] + g.base[1]) / 2, '4.000m',
          fontFamily: _font);
      paintCapsuleLabel(c, (g.base[1] + g.base[2]) / 2, '1.000m',
          fontFamily: _font);
    });

    expect(File('build/ar_style_preview/01_line.png').existsSync(), isTrue);
  });
}
