import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:gongdi_app/core/utils/homography.dart';
import 'package:gongdi_app/core/utils/measure_math.dart';
import 'package:gongdi_app/data/models.dart';

/// 合成一个「强透视」投影（模拟手机斜拍墙面）：
/// 平面 mm → 图像 px，等价于相机的针孔投影，h6/h7 越大倾斜越厉害。
const List<double> kSkew = [
  1, 0, 0, //
  0, 1, 0, //
  0.0012, 0.0008, 1, //
];

Offset project(List<double> h, Offset mm) {
  final d = h[6] * mm.dx + h[7] * mm.dy + h[8];
  return Offset(
    (h[0] * mm.dx + h[1] * mm.dy + h[2]) / d,
    (h[3] * mm.dx + h[4] * mm.dy + h[5]) / d,
  );
}

/// 3×3 网格（格距 600）的平面毫米坐标（行优先）。
List<Offset> gridMm({double step = 600, int n = 3}) => [
      for (var r = 0; r < n; r++)
        for (var c = 0; c < n; c++) Offset(c * step, r * step),
    ];

void main() {
  test('正对 4 点矩形标定：距离与真值一致', () {
    // fromRect 约定顺序：左上→右上→右下→左下
    final corners = [
      const Offset(0, 0),
      const Offset(600, 0),
      const Offset(600, 600),
      const Offset(0, 600),
    ];
    final hom = Homography.fromRect(corners, 600, 600);
    expect(hom, isNotNull);
    // 对角线真值 600√2 ≈ 848.53
    final mm = hom!.distanceMm(corners[0], corners[2]);
    expect((mm - 600 * 1.414213562).abs() < 0.01, isTrue, reason: '实测 $mm');
  });

  test('斜拍 4 点矩形标定：透视下仍能恢复真实尺寸（h₈=0 的合法退化）', () {
    // 用强透视投影后，四个角点构成的对应关系单应 h₈ 可能为 0；
    // 这正是「固定 h₈=1」的 8 元解法会失败的场景。
    final mmCorners = [
      const Offset(0, 0),
      const Offset(600, 0),
      const Offset(600, 600),
      const Offset(0, 600),
    ];
    final px = mmCorners.map((p) => project(kSkew, p)).toList();
    final hom = Homography.fromRect(px, 600, 600);
    expect(hom, isNotNull, reason: '透视下的矩形四点应能求解');
    final diag = hom!.distanceMm(px[0], px[2]);
    expect((diag - 600 * 1.414213562).abs() < 0.5, isTrue, reason: '实测 $diag');
    // 边长同样应恢复
    final top = hom.distanceMm(px[0], px[1]);
    expect((top - 600).abs() < 0.5, isTrue, reason: '上边实测 $top');
  });

  test('强透视斜拍：9 点单应恢复的尺寸误差 < 0.5mm', () {
    final mm = gridMm();
    final px = mm.map((p) => project(kSkew, p)).toList();

    final hom = Homography.solve(px, mm);
    expect(hom, isNotNull, reason: '9 点应能求解');

    // 1) 控制点反投影应回到原毫米坐标
    for (var i = 0; i < mm.length; i++) {
      final back = hom!.apply(px[i]);
      expect((back - mm[i]).distance < 0.01, isTrue,
          reason: '第 $i 点反投影 ${back} ≠ ${mm[i]}');
    }

    // 2) 未参与标定的两点（斜对角 0,0 → 1200,1200）距离应准确
    final truth = (mm[8] - mm[0]).distance; // 1200√2 ≈ 1697.06
    final got = hom!.distanceMm(px[0], px[8]);
    expect((got - truth).abs() < 0.5, isTrue, reason: '实测 $got，真值 $truth');
  });

  test('同一斜拍场景：两点比例法误差远大于单应校正（收益可见）', () {
    final mmA = const Offset(0, 0);
    final mmB = const Offset(1200, 0);
    final mmC = const Offset(1200, 1200);

    final pxA = project(kSkew, mmA);
    final pxB = project(kSkew, mmB);
    final pxC = project(kSkew, mmC);

    // 两点比例法：用 A→B（已知 1200mm）标定 mm/px，再量 A→C
    final mmPerPx = 1200 / (pxB - pxA).distance;
    final legacy = (pxC - pxA).distance * mmPerPx;
    final truth = (mmC - mmA).distance;

    final hom = Homography.solve(
      gridMm().map((p) => project(kSkew, p)).toList(),
      gridMm(),
    );
    final corrected = hom!.distanceMm(pxA, pxC);

    final legacyErr = (legacy - truth).abs();
    final correctedErr = (corrected - truth).abs();
    expect(correctedErr < 0.5, isTrue, reason: '校正后误差 $correctedErr');
    expect(legacyErr > correctedErr * 10, isTrue,
        reason: '两点比例误差 $legacyErr 应远大于单应 $correctedErr');
  });

  test('退化输入：点数不足 / 共线 / 零尺寸矩形 → null', () {
    expect(Homography.solve([], []), isNull);
    expect(
      Homography.solve(
        [const Offset(0, 0), const Offset(1, 0), const Offset(2, 0)],
        [const Offset(0, 0), const Offset(1, 0), const Offset(2, 0)],
      ),
      isNull,
    );
    // 4 点共线
    final line = [
      const Offset(0, 0),
      const Offset(10, 0),
      const Offset(20, 0),
      const Offset(30, 0),
    ];
    expect(Homography.solve(line, line), isNull);
    expect(Homography.fromRect(line, 0, 100), isNull);
  });

  test('buildGridCorrespondences：行优先生成平面坐标，不足 4 点返回空', () {
    final picks = [
      const Offset(10, 10),
      const Offset(50, 12),
      const Offset(90, 14),
      const Offset(12, 60),
      const Offset(52, 62),
      const Offset(92, 64),
    ];
    final r = buildGridCorrespondences(
      picks: picks,
      cols: 3,
      rows: 3,
      gridMm: 600,
    );
    expect(r.src.length, 6);
    expect(r.dst[0], const Offset(0, 0));
    expect(r.dst[2], const Offset(1200, 0));
    expect(r.dst[3], const Offset(0, 600));
    expect(r.dst[5], const Offset(1200, 600));

    final short = buildGridCorrespondences(
      picks: picks.take(3).toList(),
      cols: 3,
      rows: 3,
      gridMm: 600,
    );
    expect(short.src, isEmpty);
  });

  test('向后兼容：旧 PhotoCalib 无单应 → 自动量距等于两点比例法', () {
    final old = PhotoCalib(
      refMm: 1000,
      ax: 0,
      ay: 0,
      bx: 100,
      by: 0,
      imgW: 4000,
      imgH: 3000,
    );
    expect(old.hasHomography, isFalse);
    final legacy = photoMeasuredMm(old, 0, 0, 50, 0);
    final auto = photoMeasuredMmAuto(old, 0, 0, 50, 0);
    expect((auto - legacy).abs() < 1e-9, isTrue,
        reason: '无单应时必须完全回退旧算法，auto=$auto legacy=$legacy');
    // 旧 JSON（无新字段）解析不应崩，且 hasHomography=false
    final parsed = PhotoCalib.fromJson({
      'refMm': 1000,
      'pixA': 0,
      'pixB': 100,
      'imgW': 4000,
    });
    expect(parsed.hasHomography, isFalse);
    expect(parsed.calibPoints, 0);
    // 脏数据（长度不对）也要安全降级
    final dirty = PhotoCalib.fromJson({
      'refMm': 1000,
      'ax': 0,
      'ay': 0,
      'bx': 100,
      'by': 0,
      'imgW': 4000,
      'homography': [1, 2, 3],
    });
    expect(dirty.hasHomography, isFalse);
  });

  test('新字段可持久化并回读（含残差/网格跨度）', () {
    final hom = Homography.solve(
      gridMm().map((p) => project(kSkew, p)).toList(),
      gridMm(),
    );
    final calib = PhotoCalib(
      refMm: 1697.06,
      ax: 0,
      ay: 0,
      bx: 1,
      by: 1,
      imgW: 4000,
      imgH: 3000,
      homography: hom!.toList(),
      homographyResidualMm: 0.2,
      calibWidthMm: 1200,
      calibHeightMm: 1200,
      calibPoints: 9,
    );
    final back = PhotoCalib.fromJson(calib.toJson());
    expect(back.hasHomography, isTrue);
    expect(back.calibPoints, 9);
    expect(back.calibWidthMm, 1200);
    expect(back.homographyResidualMm, 0.2);
    // 回读后量距仍正确
    final mm = gridMm();
    final px = mm.map((p) => project(kSkew, p)).toList();
    final got = photoMeasuredMmAuto(back, px[0].dx, px[0].dy, px[8].dx, px[8].dy);
    expect((got - (mm[8] - mm[0]).distance).abs() < 0.5, isTrue,
        reason: '回读后实测 $got');
  });

  test('噪声控制点：残差能反映标定质量（≥5 点才有意义）', () {
    final mm = gridMm();
    final px = mm.map((p) => project(kSkew, p)).toList();
    // 人为把最后一个点推偏 3px（≈真实打点误差）
    px[8] = px[8] + const Offset(3, 0);
    final hom = Homography.solve(px, mm)!;
    final res = Homography.residualMm(hom, px, mm);
    expect(res > 0, isTrue, reason: '含噪控制点残差应 >0');
    expect(res < 30, isTrue, reason: '3px 扰动不该放大到荒谬量级：$res');
  });
}
