import 'package:flutter_test/flutter_test.dart';
import 'package:gongdi_app/core/utils/cad_coord.dart';

void main() {
  group('CadCoordMapper 仿射校准换算（与浏览器端 cad_viewer_hybrid 数学一致）', () {
    // B05：img 4500×2551，物理页 1489×844mm
    const imgW = 4500.0, imgH = 2551.0;

    // 复刻浏览器端单点校准生成 MAP（2026-08-17 修复后）：
    //   scale = imgW / 1489 ≈ 3.022 px/mm
    //   a = 1/scale；Y 系数存 d = -1/scale
    //   c = -imgW/2*a + (wx - calcX)；f = imgH/2*a + (wy - calcY)
    // 这里假设点击整图中心点 (2250, 1275.5) 作为校准点，真实坐标 (X,Y)=(100, 200)。
    final scale = imgW / 1489; // 3.022...
    final a = 1 / scale;
    final d = -1 / scale;
    // 校准点：图片中心
    final px0 = imgW / 2, py0 = imgH / 2;
    final wx0 = 100.0, wy0 = 200.0;
    final calcX = a * px0 + (-imgW / 2 * a);
    final calcY = d * py0 + (imgH / 2 * a);
    final c = -imgW / 2 * a + (wx0 - calcX);
    final f = imgH / 2 * a + (wy0 - calcY); // 注意浏览器用 f = imgH/2/scale

    final mapper = CadCoordMapper.fromAffine(
      viewWidth: imgW,
      viewHeight: imgH,
      a: a,
      c: c,
      d: d,
      f: f,
    );

    test('校准点处坐标精确等于输入真实坐标', () {
      final world = mapper.screenToWorld(px0, py0);
      expect(world.dx, closeTo(wx0, 1e-6));
      expect(world.dy, closeTo(wy0, 1e-6));
    });

    test('整图像素→世界坐标（X 与图片像素成正比）', () {
      // 点击整图最右下角 (4500, 2551)
      final world = mapper.screenToWorld(imgW, imgH);
      // X: a*4500 + c
      final expectX = a * imgW + c;
      // Y: d*2551 + f
      final expectY = d * imgH + f;
      expect(world.dx, closeTo(expectX, 1e-6));
      expect(world.dy, closeTo(expectY, 1e-6));
    });

    test('worldToScreen 是 screenToWorld 的逆变换', () {
      const px = 1234.5, py = 987.6;
      final w = mapper.screenToWorld(px, py);
      final back = mapper.worldToScreen(w.dx, w.dy);
      expect(back.dx, closeTo(px, 1e-6));
      expect(back.dy, closeTo(py, 1e-6));
    });

    test('fromCalibrationMap 解析浏览器导出的 JSON', () {
      final m = CadCoordMapper.fromCalibrationMap({
        'imgW': imgW, 'imgH': imgH,
        'a': a, 'b': 0, 'c': c, 'd': d, 'e': 0, 'f': f,
      });
      expect(m.useAffine, isTrue);
      expect(m.screenToWorld(px0, py0).dx, closeTo(wx0, 1e-6));
      expect(m.screenToWorld(px0, py0).dy, closeTo(wy0, 1e-6));
    });

    test('模拟浏览器验证过的特征点（比例尺正确性）', () {
      // 浏览器端实测：特征点1 图片像素约 (x, y)，CAD 真实 (175.1692, 800.6095)
      // 我们用该点反推图片像素：px=(wx-c)/a
      const wx1 = 175.1692, wy1 = 800.6095;
      final px1 = (wx1 - c) / a;
      final py1 = (wy1 - f) / d;
      final w = mapper.screenToWorld(px1, py1);
      expect(w.dx, closeTo(wx1, 1e-4));
      expect(w.dy, closeTo(wy1, 1e-4));
    });
  });

  group('未校准回退演示坐标系', () {
    test('50m 范围换算', () {
      final mapper = CadCoordMapper(
        viewWidth: 4500,
        viewHeight: 2551,
        worldLeft: 0,
        worldTop: 50000,
        worldWidth: 50000,
        worldHeight: 50000,
      );
      final w = mapper.screenToWorld(0, 0);
      expect(w.dx, 0);
      expect(w.dy, 50000);
      final w2 = mapper.screenToWorld(4500, 2551);
      expect(w2.dx, closeTo(50000, 1e-6));
      expect(w2.dy, closeTo(0, 1e-6));
    });
  });
}
