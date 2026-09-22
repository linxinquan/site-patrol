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

  group('Web 预览吸附（真机吸附的交互与文案预演）', () {
    const size = Size(300, 400);

    test('靠近画面中心 → 吸附到中心交点', () {
      final r = snapToPreviewGuides(const Offset(152, 202), size);
      expect(r.kind, '中心交点');
      expect(r.point, const Offset(150, 200));
    });

    test('只靠近竖网格线 → 吸附到该竖线（纵坐标不动）', () {
      final r = snapToPreviewGuides(const Offset(103, 310), size);
      expect(r.kind, '竖网格线');
      expect(r.point, const Offset(100, 310));
    });

    test('同时靠近横竖网格线 → 吸附为网格交点', () {
      final r = snapToPreviewGuides(const Offset(102, 138), size);
      expect(r.kind, '网格交点');
      expect(r.point, const Offset(100, 133.33333333333334));
    });

    test('离辅助线太远 → 不吸附（返回原始点、无提示）', () {
      const p = Offset(40, 60);
      final r = snapToPreviewGuides(p, size);
      expect(r.kind, isNull);
      expect(r.point, p);
    });
  });

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
