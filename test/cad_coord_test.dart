import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gongdi_app/core/cad/cad_calibration.dart';
import 'package:gongdi_app/core/di/providers.dart';
import 'package:gongdi_app/core/storage/local_storage.dart';
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

  group('拾取链路端到端（_pickAnnotation 的 localPos→px/py→world，含缩放与居中偏移）', () {
    // 复刻 drawing_viewer_page._pickAnnotation 的坐标换算：
    //   dispW = imgW * scale; dispH = imgH * scale
    //   originX = (maxW - dispW)/2; originY = (maxH - dispH)/2
    //   imgX = localPos.dx - originX; imgY = localPos.dy - originY
    //   relX = imgX/dispW (clamp); relY = imgY/dispH (clamp)
    //   px = relX * imgW; py = relY * imgH
    //   world = mapper.screenToWorld(px, py)
    Offset _pickWorld(Offset localPos, double scale, double maxW, double maxH,
        double imgW, double imgH, CadCoordMapper m) {
      final dispW = imgW * scale;
      final dispH = imgH * scale;
      final originX = (maxW - dispW) / 2;
      final originY = (maxH - dispH) / 2;
      final imgX = localPos.dx - originX;
      final imgY = localPos.dy - originY;
      final relX = (dispW > 0) ? (imgX / dispW).clamp(0.0, 1.0) : 0.0;
      final relY = (dispH > 0) ? (imgY / dispH).clamp(0.0, 1.0) : 0.0;
      final px = relX * imgW;
      final py = relY * imgH;
      return m.screenToWorld(px, py);
    }

    const imgW = 4500.0, imgH = 2551.0;
    final scale = imgW / 1489;
    final a = 1 / scale;
    final d = -1 / scale;
    final px0 = imgW / 2, py0 = imgH / 2;
    final wx0 = 100.0, wy0 = 200.0;
    final calcX = a * px0 + (-imgW / 2 * a);
    final calcY = d * py0 + (imgH / 2 * a);
    final c = -imgW / 2 * a + (wx0 - calcX);
    final f = imgH / 2 * a + (wy0 - calcY);
    final mapper = CadCoordMapper.fromAffine(
      viewWidth: imgW, viewHeight: imgH, a: a, c: c, d: d, f: f,
    );

    test('点击整图中心 → 真实坐标(100,200)，与缩放/视口无关', () {
      // 不同缩放与不同视口尺寸都应得到同一结果（因为居中偏移抵消）
      for (final scale in [0.3, 0.55, 1.0, 2.3]) {
        for (final vp in [const Size(800, 600), const Size(1920, 1080)]) {
          final localPos = Offset(vp.width / 2, vp.height / 2); // 视口中心 = 图片中心
          final w = _pickWorld(localPos, scale, vp.width, vp.height, imgW, imgH, mapper);
          expect(w.dx, closeTo(wx0, 1e-4), reason: 'scale=$scale vp=$vp');
          expect(w.dy, closeTo(wy0, 1e-4), reason: 'scale=$scale vp=$vp');
        }
      }
    });

    test('点击整图右下角 → 与浏览器 imagePxToWorld 一致', () {
      final scale = 0.55;
      final vp = const Size(1000, 800);
      final dispW = imgW * scale;
      final dispH = imgH * scale;
      // 图片右下角在屏幕上的 localPos
      final localPos = Offset(vp.width / 2 + dispW / 2, vp.height / 2 + dispH / 2);
      final w = _pickWorld(localPos, scale, vp.width, vp.height, imgW, imgH, mapper);
      // 浏览器 imagePxToWorld：wx=a*imgW+c, wy=d*imgH+f
      final expectX = a * imgW + c;
      final expectY = d * imgH + f;
      expect(w.dx, closeTo(expectX, 1e-4));
      expect(w.dy, closeTo(expectY, 1e-4));
    });

    test('点击图片范围内任意特征点，拾取还原偏差 < 2mm（自洽闭环）', () {
      // 取一个落在图片内部（Y 不被 clamp）的真实世界坐标点。
      // 由 mapper 反推其在图片像素中的位置作为「真值」，再用拾取链路还原，
      // 验证 (拾取值 - 真值) 偏差 < 2mm。该点须满足 py∈[0,imgH]、px∈[0,imgW]。
      const wx1 = 320.5, wy1 = -150.25;
      final px1 = (wx1 - c) / a;
      final py1 = (wy1 - f) / d;
      // 断言该点在图片范围内（确保不会被 clamp 吃掉）
      expect(px1, greaterThan(0));
      expect(px1, lessThan(imgW));
      expect(py1, greaterThan(0));
      expect(py1, lessThan(imgH));

      final scale = 0.8;
      final vp = const Size(1200, 900);
      final dispW = imgW * scale;
      final dispH = imgH * scale;
      final originX = (vp.width - dispW) / 2;
      final originY = (vp.height - dispH) / 2;
      final localPos = Offset(px1 * scale + originX, py1 * scale + originY);
      final w = _pickWorld(localPos, scale, vp.width, vp.height, imgW, imgH, mapper);
      expect((w.dx - wx1).abs(), lessThan(2.0)); // < 2mm
      expect((w.dy - wy1).abs(), lessThan(2.0));
    });

    test('localPos 反向验证：从 world 反推 localPos 再拾取应闭合', () {
      const target = Offset(320.5, -150.25);
      final px = (target.dx - c) / a;
      final py = (target.dy - f) / d;
      final scale = 1.2;
      final vp = const Size(1400, 1000);
      final dispW = imgW * scale;
      final dispH = imgH * scale;
      final originX = (vp.width - dispW) / 2;
      final originY = (vp.height - dispH) / 2;
      final localPos = Offset(px * scale + originX, py * scale + originY);
      final w = _pickWorld(localPos, scale, vp.width, vp.height, imgW, imgH, mapper);
      expect(w.dx, closeTo(target.dx, 1e-3));
      expect(w.dy, closeTo(target.dy, 1e-3));
    });
  });

  group('浏览器真实分享 JSON（嵌套 m 格式）解析与换算一致性', () {
    // 浏览器端 cad_viewer_hybrid.html「复制参数」导出的真实 JSON：
    //   {"v":1,"key":"dy04_7_B05","imgW":4500,"imgH":2551,
    //    "paperW":1489,"paperH":844,
    //    "m":{"a":0.3308888888888889,"b":0,"c":-359.5469524500907,
    //         "d":-0.3308888888888889,"e":0,"f":852.7574962071062},
    //    "time":...}
    final json = <String, dynamic>{
      'v': 1,
      'key': 'dy04_7_B05',
      'imgW': 4500,
      'imgH': 2551,
      'paperW': 1489,
      'paperH': 844,
      'm': <String, dynamic>{
        'a': 0.3308888888888889,
        'b': 0,
        'c': -359.5469524500907,
        'd': -0.3308888888888889,
        'e': 0,
        'f': 852.7574962071062,
      },
    };

    test('fromCalibrationMap 能解析嵌套 m 格式（不报 null）', () {
      final mapper = CadCoordMapper.fromCalibrationMap(json);
      final w = mapper.screenToWorld(0, 0);
      // 与浏览器 imagePxToWorld(0,0) = a*0+c, d*0+f 完全一致
      expect(w.dx, closeTo(-359.5469524500907, 1e-9));
      expect(w.dy, closeTo(852.7574962071062, 1e-9));
    });

    test('与浏览器 imagePxToWorld 多点一致（偏差 < 1e-6mm）', () {
      final mapper = CadCoordMapper.fromCalibrationMap(json);
      final a = 0.3308888888888889, c = -359.5469524500907;
      final d = -0.3308888888888889, f = 852.7574962071062;
      final cases = <List<double>>[
        [0, 0],
        [2250, 1275.5], // 图片中心
        [4500, 2551], // 右下角
        [1234, 567],
      ];
      for (final p in cases) {
        final px = p[0], py = p[1];
        final w = mapper.screenToWorld(px, py);
        final expectX = a * px + c;
        final expectY = d * py + f;
        expect(w.dx, closeTo(expectX, 1e-6));
        expect(w.dy, closeTo(expectY, 1e-6));
      }
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

  // ---- 校准参数持久化（P0-2 遗留项：浏览器原始 JSON 落地，换图/重启免重粘贴） ----
  group('CadCalibrationStore 持久化（系数 + 浏览器原始 JSON）', () {
    /// 内存版 LocalStorage，避免依赖平台实现（Web/IO）。
    late Map<String, String> _kv;
    late CadCalibrationStore store;

    setUp(() {
      _kv = {};
      store = CadCalibrationStore(_MemStorage(_kv));
    });

    const key = 'dy04_7_B05';
    final browserJson =
        '{"v":1,"key":"dy04_7_B05","imgW":4500,"imgH":2551,"paperW":1489,'
        '"paperH":844,"m":{"a":0.3308888888888889,"b":0,"c":-359.5469524500907,'
        '"d":-0.3308888888888889,"e":0,"f":852.7574962071062},"time":1787206896109}';

    test('原始浏览器 JSON 存读一致', () async {
      await store.saveRawJson(key, browserJson);
      final back = await store.readRawJson(key);
      expect(back, browserJson);
    });

    test('系数存读一致，且可被 fromCalibrationMap 解析', () async {
      final mapper = CadCoordMapper.fromCalibrationMap(
        jsonDecode(browserJson) as Map<String, dynamic>,
      );
      await store.saveCalibration(key, mapper);
      final loaded = await store.readCalibration(key);
      expect(loaded, isNotNull);
      // 用还原的 mapper 换算一个已知点，应与浏览器一致（<1e-6mm）。
      final p = loaded!.screenToWorld(2250, 1275.5);
      // 浏览器单点校准下中心点坐标 = (c+a*px, f+d*py)
      final expectX = -359.5469524500907 + 0.3308888888888889 * 2250;
      final expectY = 852.7574962071062 - 0.3308888888888889 * 1275.5;
      expect(p.dx, closeTo(expectX, 1e-6));
      expect(p.dy, closeTo(expectY, 1e-6));
    });

    test('删除后读取返回 null', () async {
      await store.saveRawJson(key, browserJson);
      await store.deleteRawJson(key);
      expect(await store.readRawJson(key), isNull);
    });
  });

  // ---- 校准库（方案 B：多图纸批量套用清单） ----
  group('CalibrationLibrary 多图纸批量套用', () {
    const browserJson =
        '{"v":1,"key":"dy04_7_B05","imgW":4500,"imgH":2551,"paperW":1489,'
        '"paperH":844,"m":{"a":0.3308888888888889,"b":0,"c":-359.5469524500907,'
        '"d":-0.3308888888888889,"e":0,"f":852.7574962071062},"time":1787206896109}';

    late Map<String, String> kv;
    late ProviderContainer container;

    setUp(() {
      kv = {};
      final storage = _MemStorage(kv);
      container = ProviderContainer(
        overrides: [
          cadCalibrationStoreProvider
              .overrideWithValue(CadCalibrationStore(storage)),
          calibrationLibraryProvider
              .overrideWithValue(CalibrationLibrary(storage)),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('upsert + listCalibrated + readRaw 闭环', () async {
      const k1 = 'dy04_7_B05';
      const k2 = 'dy04_7_B06';
      final m = CadCoordMapper.fromCalibrationMap(
        jsonDecode(browserJson) as Map<String, dynamic>,
      );
      final lib = container.read(calibrationLibraryProvider);
      await lib.upsert(k1, m, browserJson);
      await lib.upsert(k2, m, browserJson);

      final list = await lib.listCalibrated();
      expect(list, containsAll([k1, k2]));
      expect(await lib.readRaw(k1), browserJson);
    });

    test('applyToProviders 后内存含全部已校准图纸，打开即用', () async {
      const k1 = 'dy04_7_B05';
      const k2 = 'dy04_7_B06';
      final m = CadCoordMapper.fromCalibrationMap(
        jsonDecode(browserJson) as Map<String, dynamic>,
      );
      final lib = container.read(calibrationLibraryProvider);
      await lib.upsert(k1, m, browserJson);
      await lib.upsert(k2, m, browserJson);

      // 模拟 App 启动期批量套用（直接走 library.buildAll + 写入 provider）。
      final all = await lib.buildAll();
      container.read(cadCalibrationMapProvider.notifier).state = {
        ...container.read(cadCalibrationMapProvider),
        ...all,
      };
      final map = container.read(cadCalibrationMapProvider);
      expect(map.containsKey(k1), isTrue);
      expect(map.containsKey(k2), isTrue);
      // 套用后坐标换算与浏览器一致（<1e-6mm）。
      final p = map[k1]!.screenToWorld(2250, 1275.5);
      final expectX = -359.5469524500907 + 0.3308888888888889 * 2250;
      final expectY = 852.7574962071062 - 0.3308888888888889 * 1275.5;
      expect(p.dx, closeTo(expectX, 1e-6));
      expect(p.dy, closeTo(expectY, 1e-6));
    });

    test('remove 后列表不再包含该图纸', () async {
      const k1 = 'dy04_7_B05';
      final m = CadCoordMapper.fromCalibrationMap(
        jsonDecode(browserJson) as Map<String, dynamic>,
      );
      final lib = container.read(calibrationLibraryProvider);
      await lib.upsert(k1, m, browserJson);
      await lib.remove(k1);
      expect(await lib.listCalibrated(), isEmpty);
      expect(await lib.readRaw(k1), isNull);
    });
  });
}

/// 内存存储实现，仅用于单元测试。
class _MemStorage implements LocalStorage {
  _MemStorage(this._kv);
  final Map<String, String> _kv;

  @override
  Future<String?> readKV(String key) async => _kv[key];
  @override
  Future<void> writeKV(String key, String value) async => _kv[key] = value;
  @override
  Future<void> deleteKV(String key) async => _kv.remove(key);
  @override
  Future<String?> readDoc(String key) async => _kv[key];
  @override
  Future<void> writeDoc(String key, String value) async => _kv[key] = value;
  @override
  Future<void> deleteDoc(String key) async => _kv.remove(key);
  @override
  Future<Uint8List?> readFile(String p) async => null;
  @override
  Future<void> writeFile(String p, Uint8List b) async {}
  @override
  Future<void> deleteFile(String p) async {}
  @override
  Future<bool> fileExists(String p) async => false;
  @override
  Future<void> seedDrawingsIfNeeded() async {}
}
