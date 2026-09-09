import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:gongdi_app/core/room/room_geometry.dart';
import 'package:gongdi_app/data/models.dart';

void main() {
  test('3m×4m 直角矩形：闭合差=首尾缺口(底边)、面积 12㎡、墙长正确', () {
    // 4 个角点本身不成环：首(0,0)→尾(3000,0) 的缺口即隐式底边 3000
    // （ROOM_MEASURE_IMPL_DETAIL §4 原用例断言闭合差 0 与列表不符，按实现语义更正）
    final pts = [
      const Offset(0, 0),
      const Offset(0, 4000),
      const Offset(3000, 4000),
      const Offset(3000, 0),
    ];
    expect(closureDelta(pts), closeTo(3000, 1e-6));
    expect(areaM2(pts), closeTo(12.0, 1e-6)); // 3m×4m = 12㎡
    expect(wallLengthsMm(pts), [4000, 3000, 4000, 3000]);
  });

  test('末点回到首点(显式闭合) → 闭合差≈0', () {
    final closed = [
      const Offset(0, 0),
      const Offset(0, 4000),
      const Offset(3000, 4000),
      const Offset(3000, 0),
      const Offset(0, 0),
    ];
    expect(closureDelta(closed), closeTo(0, 1e-6));
  });

  test('88° 角被吸附为 90°（启发式：至少命中吸附且点集不变形）', () {
    final pts = [
      const Offset(0, 0),
      const Offset(0, 4000),
      const Offset(3010, 4010), // 略偏，应被吸附
      const Offset(3000, 0),
    ];
    final r = orthoSnap(pts);
    expect(r.snappedIdx, isNotEmpty);
    expect(r.points.length, pts.length);
  });

  test('面积 ㎡ 输出（旋转房间不依赖方向）', () {
    final r = [
      const Offset(0, 0),
      const Offset(2000, 0),
      const Offset(2000, 1500),
      const Offset(0, 1500),
    ];
    expect(areaM2(r), closeTo(3.0, 1e-6));
  });

  test('标注外法向与质心方向一致（向外）', () {
    final pts = [
      const Offset(0, 0),
      const Offset(0, 4000),
      const Offset(3000, 4000),
      const Offset(3000, 0),
    ];
    final anchor = dimAnchorFor(pts, 0); // 左墙
    // labelPos.x 应 < mid.x（朝外侧 x 负向）
    expect(anchor.labelPos.dx, lessThan(anchor.mid.dx));
  });

  test('洞口中心归一化', () {
    const w = [
      WallOpening(type: 'door', offsetFromMm: 100, widthMm: 900),
    ];
    final units = openingCentersUnit([Offset.zero, const Offset(0, 4000)], w, 4000);
    expect(units.single, closeTo((100 + 450) / 4000, 1e-9));
  });
}
