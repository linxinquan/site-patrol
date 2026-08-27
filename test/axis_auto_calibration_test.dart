import 'dart:typed_data';
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

    test('完整管线：底图带误检线（贴近真实）', () {
      // 真实场景：cadPts 干净（DXF 轴网交点），imgPts 混入误检线交点。
      // detectAxisLines 用 coverageMin:0.5 已过滤大部分短线段，
      // 误检线交点比例约为真实交点的 20~40%。
      final cadPts = genCadPts();
      final imgPts = genImgPts();
      final rng = _Rand(42);
      for (var i = 0; i < 10; i++) {
        imgPts.add(Offset(
            100 + rng.next() * 1000, 80 + rng.next() * 700));
      }
      final res = matchAxisIntersections(
        imgPts,
        cadPts,
        1200,
        800,
        trials: 600,
        matchRadiusMm: 3000,
        minInliers: 4,
      );
      expect(res.success, isTrue, reason: '误检线下应仍能匹配出真实轴网');
      expect(res.inliers.length, greaterThanOrEqualTo(8));
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

  group('detectAxisLines v2（最长连续暗段 + 容缺 + 聚类）', () {
    /// 构造一张白底图：画 3 横 + 4 竖（长线）+ 中间有 1-2px 短缺口 + 一些噪点。
    /// 验证 v2 能稳定识别出这 7 条长线，对噪声稳健。
    Uint8List makeImage(int W, int H, void Function(int x, int y) draw) {
      final bytes = Uint8List(W * H * 4);
      for (var i = 0; i < bytes.length; i += 4) {
        bytes[i] = 255;
        bytes[i + 1] = 255;
        bytes[i + 2] = 255;
        bytes[i + 3] = 255;
      }
      for (var y = 0; y < H; y++) {
        for (var x = 0; x < W; x++) {
          draw(x, y);
        }
      }
      // 把 draw 回调施加的"暗色像素"写回
      return bytes;
    }

    test('识别 3 横 + 4 竖（长线带 1-2px 缺口）', () {
      const W = 1000, H = 600;
      // 画线：横线 y=100,300,500；竖线 x=200,400,600,800
      // 在 5% 长度处插入 2px 缺口（"图框"位置）
      // + 在 y=200 加 30 段短线（噪声）
      final dark = <int>{};
      void setDark(int x, int y) {
        final i = (y * W + x) * 4;
        dark.add(i);
      }
      // 横线
      for (final y in [100, 300, 500]) {
        for (var x = 0; x < W; x++) {
          if (x > 200 && x < 203) continue; // 2px 缺口
          setDark(x, y);
        }
      }
      // 竖线
      for (final x in [200, 400, 600, 800]) {
        for (var y = 0; y < H; y++) {
          if (y > 250 && y < 253) continue; // 2px 缺口
          setDark(x, y);
        }
      }
      // 噪声短线段（10px 一段）
      var seed = 0xACE1;
      int rnd() {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed;
      }
      for (var n = 0; n < 30; n++) {
        final sy = rnd() % H;
        final sx = rnd() % (W - 10);
        for (var k = 0; k < 10; k++) {
          setDark(sx + k, sy);
        }
      }
      final rgba = Uint8List(W * H * 4);
      // 背景白 (255,255,255,255)
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 255;
        rgba[i + 1] = 255;
        rgba[i + 2] = 255;
        rgba[i + 3] = 255;
      }
      // 线设为黑 (0,0,0,255)
      for (final i in dark) {
        rgba[i] = 0;
        rgba[i + 1] = 0;
        rgba[i + 2] = 0;
      }
      final grid = detectAxisLines(
        rgba, W, H,
        sampleW: 500, minRatio: 0.5, maxGap: 4, clusterTol: 5,
      );
      expect(grid.horizontals.length, greaterThanOrEqualTo(3),
          reason: '应检出 3 条横线');
      expect(grid.verticals.length, greaterThanOrEqualTo(4),
          reason: '应检出 4 条竖线');
      // 验质心位置（允许 ±5px）
      final hY = grid.horizontals.map((l) => l.a.dy).toList()..sort();
      expect((hY[0] - 100).abs() < 5, isTrue, reason: '第一条横线 y≈100');
      expect((hY[1] - 300).abs() < 5, isTrue, reason: '第二条横线 y≈300');
      expect((hY[2] - 500).abs() < 5, isTrue, reason: '第三条横线 y≈500');
      final vX = grid.verticals.map((l) => l.a.dx).toList()..sort();
      expect((vX[0] - 200).abs() < 5, isTrue, reason: '第一条竖线 x≈200');
      expect((vX[3] - 800).abs() < 5, isTrue, reason: '第四条竖线 x≈800');
    });

    test('纯噪声：应返回空线集（不误检）', () {
      const W = 500, H = 300;
      final rgba = Uint8List(W * H * 4);
      var seed = 0xBEEF;
      for (var i = 0; i < rgba.length; i += 4) {
        // 5% 像素设为暗（不形成贯穿行/列的稀疏噪声）
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        if ((seed & 0x3F) == 0) {
          rgba[i] = 0;
          rgba[i + 1] = 0;
          rgba[i + 2] = 0;
        } else {
          rgba[i] = 255;
          rgba[i + 1] = 255;
          rgba[i + 2] = 255;
        }
      }
      final grid = detectAxisLines(
        rgba, W, H, sampleW: 400, minRatio: 0.5, maxGap: 4, clusterTol: 5,
      );
      expect(grid.horizontals.length, 0, reason: '纯噪声不应检出横线');
      expect(grid.verticals.length, 0, reason: '纯噪声不应检出竖线');
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
