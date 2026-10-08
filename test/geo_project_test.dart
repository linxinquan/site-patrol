import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:gongdi_app/core/utils/geo_project.dart';

/// 地理配准投影的回归测试。
///
/// 这是"真实 GPS 轨迹能画到图纸上"的地基：方向搞反（正北画到图纸下方）、
/// 单位差 1000 倍都不会报错，只会让现场看到一条完全错误的轨迹，所以必须锁死。
void main() {
  // 取深圳某工地做样例（北纬 22.5°，东经 114°）
  const originLat = 22.5;
  const originLng = 114.0;
  const mpp = 0.0396; // 米/像素 ≈ 1:100 的 A0 图在 3000px 底图上

  group('latLngToDrawingPixel', () {
    test('原点经纬度 → 图纸 (0,0)', () {
      final p = latLngToDrawingPixel(
        lat: originLat,
        lng: originLng,
        originLat: originLat,
        originLng: originLng,
        metersPerPixel: mpp,
      );
      expect(p, isNotNull);
      expect(p!.dx, closeTo(0, 1e-9));
      expect(p.dy, closeTo(0, 1e-9));
    });

    test('正东 100m → x 正向 100/mpp 像素，y 不动', () {
      final dLng = 100 / metersPerDegreeLng(originLat);
      final p = latLngToDrawingPixel(
        lat: originLat,
        lng: originLng + dLng,
        originLat: originLat,
        originLng: originLng,
        metersPerPixel: mpp,
      );
      expect(p!.dx, closeTo(100 / mpp, 0.5));
      expect(p.dy, closeTo(0, 1e-6));
    });

    test('正北 100m → y 为负（屏幕 y 轴向下）', () {
      final dLat = 100 / kMetersPerDegreeLat;
      final p = latLngToDrawingPixel(
        lat: originLat + dLat,
        lng: originLng,
        originLat: originLat,
        originLng: originLng,
        metersPerPixel: mpp,
      );
      expect(p!.dx, closeTo(0, 1e-6));
      // 正北在图纸上方 ⟹ 屏幕 y 减小
      expect(p.dy, closeTo(-100 / mpp, 0.5));
    });

    test('未配准（米/像素非法）→ 返回 null，绝不退化成 (0,0)', () {
      // 这是历史 bug 的核心断言：以前缺字段/缺比例时按 0 处理，
      // 整条真实轨迹被堆到图纸左上角，看起来像"轨迹只有一个点"。
      expect(
        latLngToDrawingPixel(
          lat: originLat,
          lng: originLng,
          originLat: originLat,
          originLng: originLng,
          metersPerPixel: 0,
        ),
        isNull,
      );
      expect(
        latLngToDrawingPixel(
          lat: originLat,
          lng: originLng,
          originLat: originLat,
          originLng: originLng,
          metersPerPixel: -1,
        ),
        isNull,
      );
    });

    test('经度方向随纬度收敛：纬度越高，每度经度对应米数越少', () {
      expect(metersPerDegreeLng(60), lessThan(metersPerDegreeLng(20)));
    });
  });

  group('drawingPixelToLatLng（逆变换）', () {
    test('正反变换往返一致（配准 UI 反算锚点用）', () {
      const px = 1234.0;
      const py = -567.0;
      final ll = drawingPixelToLatLng(
        pixel: const Offset(px, py),
        originLat: originLat,
        originLng: originLng,
        metersPerPixel: mpp,
      );
      expect(ll, isNotNull);
      final back = latLngToDrawingPixel(
        lat: ll!.lat,
        lng: ll.lng,
        originLat: originLat,
        originLng: originLng,
        metersPerPixel: mpp,
      );
      expect(back!.dx, closeTo(px, 1e-6));
      expect(back.dy, closeTo(py, 1e-6));
    });

    test('比例尺非法 → null', () {
      expect(
        drawingPixelToLatLng(
          pixel: const Offset(1, 1),
          originLat: originLat,
          originLng: originLng,
          metersPerPixel: 0,
        ),
        isNull,
      );
    });
  });

  group('metersPerPixelFromScale', () {
    test('1:100 的 A0 图（纸面 1.189m）在 3000px 底图上 ≈ 0.0396 m/px', () {
      final v = metersPerPixelFromScale(
        paperWidthMeters: 1.189,
        scaleDenominator: 100,
        pixelWidth: 3000,
      );
      expect(v, closeTo(0.0396, 1e-4));
    });

    test('同一张纸：比例尺分母越大（1:100 比 1:50），覆盖实地越广 ⟹ 米/像素越大', () {
      final v50 = metersPerPixelFromScale(
        paperWidthMeters: 1.189,
        scaleDenominator: 50,
        pixelWidth: 3000,
      )!;
      final v100 = metersPerPixelFromScale(
        paperWidthMeters: 1.189,
        scaleDenominator: 100,
        pixelWidth: 3000,
      )!;
      // 1:50 覆盖实地 59.45m，1:100 覆盖 118.9m —— 后者每像素代表的米更多
      expect(v100, greaterThan(v50));
      expect(v100, closeTo(0.0396, 1e-4));
    });

    test('非法输入 → null（比例尺分母或像素宽为 0）', () {
      expect(
        metersPerPixelFromScale(
          paperWidthMeters: 1.189,
          scaleDenominator: 0,
          pixelWidth: 3000,
        ),
        isNull,
      );
      expect(
        metersPerPixelFromScale(
          paperWidthMeters: 1.189,
          scaleDenominator: 100,
          pixelWidth: 0,
        ),
        isNull,
      );
    });
  });
}
