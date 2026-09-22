import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/core/utils/diagram_export.dart';
import 'package:gongdi_app/core/utils/measure_math.dart';
import 'package:gongdi_app/data/models.dart';

/// PNG 文件头（用于校验导出确实是图片，而不是空字节）。
const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

bool _isPng(Uint8List b) =>
    b.length > 8 && List.generate(8, (i) => b[i]).toString() == _pngMagic.toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('离群读数剔除（实测 ±505mm 那次的问题）', () {
    test('偶发点到别的面 → 被剔除，中位与误差带回到正常量级', () {
      // 真实场景：同一段墙 4 次读数，其中一次点到了后面的柜子（~2.4m）
      final xs = [768.0, 769.0, 771.0, 2416.0];
      final st = robustStats(xs);
      expect(st.rejected, 1, reason: '2.4m 那次应判为离群');
      expect(st.used, 3);
      expect(st.median, closeTo(769, 0.001));
      expect(st.spread, closeTo(2, 0.001), reason: '误差带回到 ±2mm 量级');
      expect(consistentEnough(st.spread, 30), isTrue);
    });

    test('样本普遍分散（真的没对准）→ 不误杀，误差带仍大且拒绝采纳', () {
      final xs = [500.0, 800.0, 1200.0, 1600.0];
      final st = robustStats(xs);
      expect(st.spread, greaterThan(30));
      expect(consistentEnough(st.spread, 30), isFalse, reason: '应拒绝采纳并提示重测');
    });

    test('样本很少（<3）不做剔除，避免"看起来干净"的假象', () {
      final st = robustStats([770.0, 2416.0]);
      expect(st.rejected, 0);
      expect(st.used, 2);
      expect(st.spread, closeTo(823, 0.001));
    });

    test('样本几乎全等时不误杀（兜底尺度生效）', () {
      final st = robustStats([1000.0, 1000.5, 1001.0]);
      expect(st.rejected, 0);
      expect(st.used, 3);
    });

    test('离群下标与统计口径一致', () {
      final xs = [768.0, 769.0, 771.0, 2416.0];
      expect(outlierIndexes(xs), [3]);
      expect(robustStats(xs).rejected, outlierIndexes(xs).length);
    });

    test('空样本安全返回', () {
      final st = robustStats(const []);
      expect(st.median, 0);
      expect(st.used, 0);
    });
  });

  group('勾股三值（由世界坐标拆分）', () {
    test('3-4-5 直角三角形：斜边/水平/高差分别正确', () {
      // 水平走 3000（x），垂直走 4000（y），z 不变 → 斜边 5000
      final r = pythagorasParts(
          ax: 0, ay: 0, az: 0, bx: 3000, by: 4000, bz: 0);
      expect(r.slope, closeTo(5000, 1e-6));
      expect(r.horizontal, closeTo(3000, 1e-6));
      expect(r.vertical, closeTo(4000, 1e-6));
    });

    test('只有水平分量（量开间）→ 高差≈0', () {
      final r = pythagorasParts(
          ax: 0, ay: 1200, az: 0, bx: 3600, by: 1200, bz: 0);
      expect(r.horizontal, closeTo(3600, 1e-6));
      expect(r.vertical, closeTo(0, 1e-6));
      expect(r.slope, closeTo(3600, 1e-6));
    });

    test('负方向的高差取绝对值（量落差）', () {
      final r = pythagorasParts(
          ax: 0, ay: 2800, az: 0, bx: 0, by: 100, bz: 0);
      expect(r.vertical, closeTo(2700, 1e-6));
    });

    test('深度方向（z）计入水平投影', () {
      final r = pythagorasParts(
          ax: 0, ay: 0, az: 0, bx: 0, by: 0, bz: 2000);
      expect(r.horizontal, closeTo(2000, 1e-6));
      expect(r.slope, closeTo(2000, 1e-6));
      expect(r.vertical, closeTo(0, 1e-6));
    });

    test('模式枚举齐全且带中文名（UI 直接消费）', () {
      expect(ArMeasureMode.values.length, 3);
      expect(ArMeasureMode.values.map((m) => m.label).toList(),
          ['斜边', '水平', '高差']);
    });
  });

  group('图片导出（离屏 Canvas）', () {
    Future<Uint8List> makePhoto(int w, int h) async {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = const Color(0xFFBFD4E8));
      final img = await rec.endRecording().toImage(w, h);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }

    RoomScanRecord room() => RoomScanRecord(
          id: 'room_test',
          projectKey: 'p1',
          name: '主卧',
          roomUse: '卧室',
          source: 'manual',
          scannedAtMs: 0,
          walls: const [
            RoomWall(id: 'w0', ax: 0, ay: 0, bx: 4000, by: 0, lengthMm: 4000),
            RoomWall(
                id: 'w1',
                ax: 4000,
                ay: 0,
                bx: 4000,
                by: 3000,
                lengthMm: 3000,
                openings: [
                  WallOpening(type: 'door', offsetFromMm: 600, widthMm: 900)
                ]),
            RoomWall(
                id: 'w2', ax: 4000, ay: 3000, bx: 0, by: 3000, lengthMm: 4000),
            RoomWall(id: 'w3', ax: 0, ay: 3000, bx: 0, by: 0, lengthMm: 3000),
          ],
          closureDeltaMm: 8,
          netHeightMm: 2800,
        );

    test('户型图导出：产出合法 PNG', () async {
      final bytes = await renderRoomDiagramPng(
        record: room(),
        projectName: '测试项目',
        dateText: '2026-09-21 16:00',
      );
      expect(bytes.length, greaterThan(1000));
      expect(_isPng(bytes), isTrue, reason: '应为 PNG 文件头');
    });

    test('测量图导出：照片 + 标注 → 合法 PNG，且比原图更大（含图签）', () async {
      final photo = await makePhoto(320, 240);
      final out = await renderMeasureDiagramPng(
        photoBytes: photo,
        dims: [
          (a: const Offset(40, 60), b: const Offset(280, 60), text: '2400'),
          (a: const Offset(40, 60), b: const Offset(40, 200), text: '1400'),
        ],
        title: '现场测量图',
        subtitle: '尺寸单位：mm   |   2 项实测',
      );
      expect(out, isNotNull);
      expect(_isPng(out!), isTrue);
      expect(out.length, greaterThan(photo.length));
    });

    test('测量图：照片字节损坏时返回 null（不抛异常）', () async {
      final out = await renderMeasureDiagramPng(
        photoBytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        dims: const [],
        title: 'T',
      );
      expect(out, isNull);
    });
  });
}
