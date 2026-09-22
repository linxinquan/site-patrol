import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/core/utils/measure_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('量尺叠加样式（对齐参考样张）', () {
    test('长度文案：≥1m 用 m+3 位小数，否则 mm 整数', () {
      expect(fmtLengthText(2236), '2.236m');
      expect(fmtLengthText(6990), '6.990m');
      expect(fmtLengthText(900), '900mm');
      expect(fmtLengthText(0), '0mm');
    });

    test('面积/体积大字：3 位小数、无空格、带上标单位', () {
      expect(fmtAreaText(6.25), '6.250m²');
      expect(fmtAreaText(13.1234), '13.123m²');
      expect(fmtVolumeText(8), '8.000m³');
    });

    test('主色为明黄（样张口径），不是黑/绿', () {
      expect(kMeasureYellow, const Color(0xFFFFC400));
      expect(kMeasureFill.a, lessThan(1.0), reason: '面域必须是半透明填充');
    });
  });

  // 注：Web 预览的"模拟吸附"已按产品决策移除——网格线不是物体边界，
  // 模拟吸附并提示"已吸附：网格交点"会让用户误以为识别到了真实边界。
  // 真实吸附由原生 ARKit raycast + 平面边界求最近点实现（ArMeasureView.swift）。

  group('绘制健壮性（空标签 / 退化几何不抛异常）', () {
    test('尺寸线 / 胶囊 / 面域 / 体积线框均可安全绘制', () {
      final rec = PictureRecorder();
      final canvas = Canvas(rec);
      paintDimLine(canvas, const Offset(10, 10), const Offset(120, 80), '2.236m');
      paintDimLine(canvas, const Offset(10, 10), const Offset(10, 10), '');
      paintCapsuleLabel(canvas, const Offset(50, 50), '2.000m', vertical: true);
      paintAreaFace(
        canvas,
        [const Offset(0, 0), const Offset(100, 0), const Offset(100, 60),
         const Offset(0, 60)],
        '6.250m²',
      );
      // 面域少于 3 点：直接跳过（不应崩）
      paintAreaFace(canvas, [const Offset(0, 0)], '1.000m²');
      paintVolumeWire(
        canvas,
        [const Offset(0, 0), const Offset(100, 0), const Offset(100, 60),
         const Offset(0, 60)],
        const Offset(0, -40),
        hLabel: '2.500m',
        centerText: '8.000m³',
      );
      // 体积线框点不足：跳过
      paintVolumeWire(canvas, const [], Offset.zero,
          hLabel: '', centerText: '');
      expect(rec.endRecording(), isNotNull);
    });
  });
}
