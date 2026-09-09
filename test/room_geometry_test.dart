import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/core/room/room_geometry.dart';
import 'package:gongdi_app/data/models.dart';

void main() {
  group('闭合差 / 周长 / 面积', () {
    test('首尾重复(显式闭合)时闭合差≈0，周长=4×4000', () {
      final sq = [
        Offset(0, 0), Offset(4000, 0), Offset(4000, 4000), Offset(0, 4000), Offset(0, 0),
      ];
      expect(polygonClosureDelta(sq), lessThan(1e-9));
      expect(polygonPerimeterMm(sq), closeTo(16000, 1e-6));
    });

    test('收尾回到起点附近有缺口 → 闭合差=首尾缺口（≈9mm 可接受）', () {
      final almost = [
        Offset(0, 0), Offset(4000, 0), Offset(4000, 4000), Offset(0, 4000), Offset(8, -4),
      ];
      expect(polygonClosureDelta(almost), closeTo(8.94, 0.01));
    });

    test('开口点列闭合差 = 首尾缺口', () {
      final open = [Offset(0, 0), Offset(3000, 0), Offset(3000, 3000), Offset(2000, 3000)];
      // last(2000,3000)→first(0,0)
      expect(polygonClosureDelta(open), closeTo(3605.55, 0.01));
    });

    test('3×5m 矩形面积 = 15㎡', () {
      final r = [Offset(0, 0), Offset(3000, 0), Offset(3000, 5000), Offset(0, 5000)];
      expect(roomAreaM2(r), closeTo(15, 1e-9));
    });
  });

  group('正交吸附', () {
    test('92° 角吸附为 90°，邻点不动（其余角远离 90°，无级联）', () {
      // 仅顶点 P1 的内角 ≈93.05°（其他角 ~76/112/79°，不在容差内）
      final pts = [
        Offset(0, 0),     // P0
        Offset(0, 3000),  // P1（待吸附）
        Offset(3000, 3160), // P2
        Offset(4000, 1000), // P3
      ];
      expect(interiorAngleRad(pts, 1) * 180 / 3.141592653589793,
          closeTo(93.05, 0.5));

      final r = orthoSnapPoints(pts);
      expect(r.snapped, {1});
      final after = interiorAngleRad(r.points, 1) * 180 / 3.141592653589793;
      expect(after, closeTo(90, 1e-3));
      expect(r.points[0], Offset(0, 0)); // 邻点不动
      expect(r.points[2], Offset(3000, 3160));
    });

    test('角为 40/60/80°（远离直角）不吸附', () {
      final pts = [Offset(0, 0), Offset(3000, 0), Offset(400, 2200)];
      final r = orthoSnapPoints(pts);
      expect(r.snapped, isEmpty);
    });
  });

  group('尺寸标注布局', () {
    List<RoomWall> squareWalls() {
      // CCW 4×4m：下→右→上→左
      return const [
        RoomWall(id: 'w0', ax: 0, ay: 0, bx: 4000, by: 0),
        RoomWall(id: 'w1', ax: 4000, ay: 0, bx: 4000, by: 4000),
        RoomWall(id: 'w2', ax: 4000, ay: 4000, bx: 0, by: 4000),
        RoomWall(id: 'w3', ax: 0, ay: 4000, bx: 0, by: 0),
      ];
    }

    test('每条墙出 1 条标注，文本=整毫米长', () {
      final lines = dimensionLinesFor(squareWalls());
      expect(lines.length, 4);
      expect(lines.every((l) => l.label == '4000'), isTrue);
    });

    test('内法线指向图形内部', () {
      final lines = dimensionLinesFor(squareWalls());
      final bottom = lines.firstWhere((l) => l.mid.dy == 0);
      // 底边 (0,0)→(4000,0)：内法线应指向 y 正（图形内部）
      expect(bottom.inward.dy, greaterThan(0));
      expect(bottom.inward.dx.abs(), lessThan(1e-9));
    });
  });
}
