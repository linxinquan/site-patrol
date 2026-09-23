import 'package:flutter_test/flutter_test.dart';
import 'package:gongdi_app/core/utils/measure_math.dart';
import 'package:gongdi_app/core/utils/mm_format.dart';

/// AR 世界坐标（米）→ 三值（mm）的单位换算回归测试。
///
/// 真机事故：`pythagorasParts` 约定输入 mm，而 ARKit 上报的世界坐标是**米**，
/// 调用处漏乘 1000 后 0.7m 变成 0.7，再经 `fmtMm` 取整显示成 `1mm`——
/// 界面读数 1mm，而原生画在地面上的尺寸线却是 700mm。
void main() {
  group('partsFromWorldMeters', () {
    test('0.7m 水平边 → 700mm（不是 1mm）', () {
      final p = partsFromWorldMeters(
        ax: 0, ay: 0, az: 0,
        bx: 0.7, by: 0, bz: 0,
      );
      expect(p.slope, closeTo(700, 1e-6));
      expect(p.horizontal, closeTo(700, 1e-6));
      expect(p.vertical, 0);

      // 锁死事故表现：漏乘 1000 时 fmtMm 会把 0.7 显示成 "1"
      expect(fmtMm(0.7), '1');
      expect(fmtMm(p.slope), '700');
    });

    test('高差取 |Δy|（ARKit y 轴向上）', () {
      final p = partsFromWorldMeters(
        ax: 0, ay: 1.0, az: 0,
        bx: 0, by: 3.8, bz: 0,
      );
      expect(p.vertical, closeTo(2800, 1e-6));
      expect(p.slope, closeTo(2800, 1e-6));
      expect(p.horizontal, closeTo(0, 1e-6));
    });

    test('斜边与水平投影：3m 横 × 4m 高 → 斜边 5m', () {
      final p = partsFromWorldMeters(
        ax: 0, ay: 0, az: 0,
        bx: 3, by: 4, bz: 0,
      );
      expect(p.slope, closeTo(5000, 1e-6));
      expect(p.horizontal, closeTo(3000, 1e-6));
      expect(p.vertical, closeTo(4000, 1e-6));
    });

    test('与 pythagorasParts(毫米) 同口径', () {
      final fromMeters = partsFromWorldMeters(
        ax: 1.2, ay: 0.5, az: -0.3,
        bx: 2.9, by: 1.1, bz: 0.4,
      );
      final fromMm = pythagorasParts(
        ax: 1200, ay: 500, az: -300,
        bx: 2900, by: 1100, bz: 400,
      );
      expect(fromMeters.slope, closeTo(fromMm.slope, 1e-6));
      expect(fromMeters.horizontal, closeTo(fromMm.horizontal, 1e-6));
      expect(fromMeters.vertical, closeTo(fromMm.vertical, 1e-6));
    });
  });

  group('HeightSum（高度和）', () {
    test('逐段累加：两段起才算“和”', () {
      final hs = HeightSum();
      expect(hs.segments, 0);
      expect(hs.ready, isFalse);

      hs.add(1500, 8);
      expect(hs.mm, 1500);
      expect(hs.segments, 1);
      expect(hs.ready, isFalse); // 一段就是它自己，不构成"和"

      hs.add(2000, 12);
      expect(hs.mm, 3500);
      expect(hs.errMm, 20); // 误差带按保守线性相加
      expect(hs.segments, 2);
      expect(hs.ready, isTrue);
    });

    test('非正读数（误点）被忽略，不污染和值', () {
      final hs = HeightSum();
      hs.add(1200, 5);
      hs.add(0, 0);
      hs.add(-30, 1);
      expect(hs.mm, 1200);
      expect(hs.segments, 1);
    });

    test('reset 清零', () {
      final hs = HeightSum()..add(900, 4)..add(1100, 6);
      hs.reset();
      expect(hs.mm, 0);
      expect(hs.errMm, 0);
      expect(hs.segments, 0);
      expect(hs.ready, isFalse);
    });

    test('只有 heightSum 是累加模式', () {
      expect(ArMeasureMode.heightSum.accumulates, isTrue);
      expect(ArMeasureMode.slope.accumulates, isFalse);
      expect(ArMeasureMode.horizontal.accumulates, isFalse);
      expect(ArMeasureMode.vertical.accumulates, isFalse);
    });
  });
}
