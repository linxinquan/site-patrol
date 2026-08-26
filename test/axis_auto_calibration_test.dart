import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/core/cad/axis_auto_calibration.dart';
import 'package:gongdi_app/core/cad/axis_calibration.dart';

void main() {
  group('axisIntersections', () {
    test('横竖轴线求交', () {
      final grid = AxisGrid(
        horizontals: [
          AxisLine(Offset(0, 100), Offset(1000, 100)),
          AxisLine(Offset(0, 300), Offset(1000, 300)),
        ],
        verticals: [
          AxisLine(Offset(50, 0), Offset(50, 500)),
          AxisLine(Offset(80, 0), Offset(80, 500)),
        ],
      );
      final pts = axisIntersections(grid);
      expect(pts.length, 4);
      expect(pts, contains(Offset(50, 100)));
      expect(pts, contains(Offset(80, 300)));
    });
  });

  group('fitAffineLeastSquares sanity', () {
    test('拟合简单仿射', () {
      final pairs = [
        CalibPointPair(pixel: Offset(0, 0), world: Offset(10, 20)),
        CalibPointPair(pixel: Offset(100, 0), world: Offset(60, 20)),
        CalibPointPair(pixel: Offset(0, 50), world: Offset(10, -5)),
      ];
      final m = fitAffineLeastSquares(pairs, 200, 100);
      expect(m, isNotNull);
      final w = m!.screenToWorld(0, 0);
      expect((w.dx - 10).abs(), lessThan(0.001));
      expect((w.dy - 20).abs(), lessThan(0.001));
      final w2 = m.screenToWorld(100, 0);
      expect((w2.dx - 60).abs(), lessThan(0.001));
    });
  });

  group('matchAxisIntersections', () {
    // 构造已知仿射：worldX = 0.5*px - 10000, worldY = -0.5*py + 50000
    // （CAD Y 向上 = 像素 Y 向下，d<0）
    List<Offset> genImgPts() {
      final pts = <Offset>[];
      for (var i = 0; i < 8; i++) {
        for (var j = 0; j < 6; j++) {
          pts.add(Offset(100.0 + i * 120, 80.0 + j * 90));
        }
      }
      return pts;
    }

    List<Offset> genCadPts() {
      return genImgPts()
          .map((p) => Offset(0.5 * p.dx - 10000, -0.5 * p.dy + 50000))
          .toList();
    }

    test('确定性网格匹配：理想网格', () {
      final imgPts = genImgPts();
      final cadPts = genCadPts();
      final res = matchAxisGridDeterministic(imgPts, cadPts, 1200, 800);
      expect(res, isNotNull, reason: '确定性网格匹配应成功');
      final m = res!.fit!.mapper;
      final p = imgPts[15];
      final w = m.screenToWorld(p.dx, p.dy);
      expect((w.dx - (0.5 * p.dx - 10000)).abs(), lessThan(1.0));
      expect((w.dy - (-0.5 * p.dy + 50000)).abs(), lessThan(1.0));
    });

    test('确定性网格匹配：带干扰点', () {
      final imgPts = genImgPts();
      final cadPts = genCadPts();
      // 适度噪声（约 40% 干扰点，贴近实际：cadPts 主体是真实轴网交点）
      final rng = _Rand(42);
      for (var i = 0; i < 20; i++) {
        cadPts.add(Offset(
            rng.next() * 400000 - 200000, rng.next() * 400000 - 200000));
      }
      final res = matchAxisGridDeterministic(imgPts, cadPts, 1200, 800);
      expect(res, isNotNull, reason: '适度噪声下应仍能匹配出真实轴网');
      expect(res!.inliers.length, greaterThanOrEqualTo(8));
    });

    test('理想网格自动匹配成功（RANSAC 路径）', () {
      final imgPts = genImgPts();
      final cadPts = genCadPts();
      final res = matchAxisIntersections(
        imgPts,
        cadPts,
        1200,
        800,
        trials: 500,
        matchRadiusMm: 50,
        minInliers: 3,
        verbose: false,
      );
      expect(res.success, isTrue, reason: '应成功匹配轴网交点');
      expect(res.inliers.length, greaterThanOrEqualTo(3));
      final m = res.fit!.mapper;
      // 验证中心点映射精度
      final p = imgPts[15];
      final w = m.screenToWorld(p.dx, p.dy);
      expect((w.dx - (0.5 * p.dx - 10000)).abs(), lessThan(1.0));
      expect((w.dy - (-0.5 * p.dy + 50000)).abs(), lessThan(1.0));
    });

    test('无对应关系时失败', () {
      final imgPts = genImgPts();
      // 随机散布点（非网格），与底图无任何真实对应
      final rng = _Rand(7);
      final cadPts = <Offset>[];
      for (var i = 0; i < 300; i++) {
        cadPts.add(Offset(rng.next() * 300000, rng.next() * 300000));
      }
      final res = matchAxisIntersections(
        imgPts,
        cadPts,
        1200,
        800,
        trials: 200,
        matchRadiusMm: 10,
        minInliers: 10,
      );
      expect(res.success, isFalse, reason: '无对应数据应判定失败');
    });
  });
}

class _Rand {
  int _state;
  _Rand(this._state);
  double next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}
