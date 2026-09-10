import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:gongdi_app/core/storage/ar_scale_calibration.dart';
import 'package:gongdi_app/core/utils/engineering_naming.dart';
import 'package:gongdi_app/core/utils/homography.dart';
import 'package:gongdi_app/core/utils/measure_labels.dart';
import 'package:gongdi_app/core/utils/measure_math.dart';
import 'package:gongdi_app/data/models.dart';
import 'package:gongdi_app/data/vision_service.dart';

void main() {
  group('工程命名与模数吸附', () {
    test('门窗编号按制图习惯：M0921 / C1518', () {
      expect(openingCode('door', 900, 2100), 'M0921');
      expect(openingCode('window', 1500, 1800), 'C1518');
      expect(openingCode('门', 900, 2100), 'M0921');
      expect(openingCode('opening', 1200, 2400), 'D1224');
      // 非常规大尺寸不补零、不截断
      expect(openingCode('door', 12000, 2100), 'M12021');
    });

    test('模数吸附：2075→2100、890→900、1234 超差返回 null', () {
      final a = snapToModule(2075);
      expect(a, isNotNull);
      expect(a!.value, 2100);
      expect(a.diff, -25);

      final b = snapToModule(890);
      expect(b!.value, 900);
      expect(b.diff, -10);

      expect(snapToModule(1234), isNull, reason: '差 34mm > 默认 30mm');
      expect(snapToModule(1234, tol: 40)!.value, 1200);
    });

    test('吸附提示文案包含标准值与差值', () {
      expect(snapHint(2075), contains('2100'));
      expect(snapHint(2075), contains('-25'));
      expect(snapHint(1234), contains('非标准模数'));
    });

    test('目标类型中文名', () {
      expect(targetKindLabel('door'), '门洞');
      expect(targetKindLabel('ceiling_height'), '净高');
      expect(targetKindLabel('unknown'), '尺寸');
    });
  });

  group('AI 被测目标解析', () {
    String json(List<List<Object>> targets) {
      final body = '{"targets":[${targets.map((t) => '{"kind":"${t[0]}",'
          '"name":"${t[1]}","p1":[${t[2]},${t[3]}],"p2":[${t[4]},${t[5]}],'
          '"conf":${t[6]}}').join(',')}]}';
      return '```json\n$body\n```';
    }

    test('解析并按置信度排序、过滤越界与重合点', () {
      final list = MeasureTarget.listFromContent(json([
        ['beam', '梁宽', 0.2, 0.3, 0.6, 0.3, 0.6],
        ['door', '门洞宽', 0.3, 0.6, 0.7, 0.6, 0.95],
        ['window', '越界', 0.3, 0.6, 1.4, 0.6, 0.9],
        ['wall', '重合', 0.5, 0.5, 0.5, 0.5, 0.9],
      ]));
      expect(list, isNotNull);
      expect(list!.length, 2);
      expect(list.first.kind, 'door', reason: '置信度高者在前');
      expect(list.last.kind, 'beam');
    });

    test('无目标 / 脏数据 → null（不抛异常）', () {
      expect(MeasureTarget.listFromContent('{"targets":[]}'), isNull);
      expect(MeasureTarget.listFromContent('not json'), isNull);
      expect(MeasureTarget.listFromContent('{"targets":[{"kind":"door"}]}'),
          isNull);
    });

    test('超过 8 个只保留置信度最高的 8 个', () {
      final many = [
        for (var i = 0; i < 12; i++)
          ['door', '门$i', 0.05 * i, 0.1, 0.05 * i + 0.3, 0.1, 0.5 + i * 0.03],
      ];
      final list = MeasureTarget.listFromContent(json(many));
      expect(list!.length, 8);
      expect(list.first.conf, greaterThan(list.last.conf));
    });
  });

  group('量尺统一文案（四端共用）', () {
    test('实测文本带误差带；无误差带时不假装有精度', () {
      const withErr = MeasureItem(
          name: '门洞宽',
          drawingMm: 900,
          photoMm: 907,
          source: 'ai',
          errorMm: 4.5);
      const noErr = MeasureItem(
          name: '门洞宽', drawingMm: 900, photoMm: 907, source: 'photo');
      // fmtMm 按制图习惯取整 → 4.5 → 5
      expect(measureValueText(withErr), '907 mm ±5');
      expect(measureValueText(noErr), '907 mm');
    });

    test('误差带 > 容差/3 时不下结论，标需复核', () {
      const bigErr = MeasureItem(
          name: '门洞宽',
          drawingMm: 900,
          photoMm: 907,
          source: 'ar_lidar',
          errorMm: 8); // 容差 15 → 1/3 = 5，8 > 5
      expect(measureVerdictText(bigErr, 15, 2), contains('需卷尺复核'));

      // 误差带够小但偏差超容差 → 超差
      const outOfTol = MeasureItem(
          name: '门洞宽',
          drawingMm: 890,
          photoMm: 907,
          source: 'ar_lidar',
          errorMm: 3);
      expect(measureVerdictText(outOfTol, 15, 2), '超差');

      // 误差小且偏差在容差内 → 合格
      const ok = MeasureItem(
          name: '门洞宽',
          drawingMm: 900,
          photoMm: 905,
          source: 'ar_lidar',
          errorMm: 3);
      expect(measureVerdictText(ok, 15, 2), '合格');
    });

    test('单行摘要含实测、图纸、偏差与测量方式', () {
      const item = MeasureItem(
          name: '窗洞 C1518',
          drawingMm: 1500,
          photoMm: 1509,
          source: 'ar_lidar',
          errorMm: 3);
      final line = measureCheckLine(item);
      expect(line, contains('1509 mm ±3'));
      expect(line, contains('1500 mm'));
      expect(line, contains('+9 mm'));
      expect(line, contains('AR量尺(LiDAR)'));
      expect(kCheckTableHeaders.length, measureCheckRow(item).length);
    });
  });

  group('AR 系统偏差校正', () {
    test('k = 真值 / 实测中位，可修正系统偏差', () {
      const c = ArScaleCalibration(
          refMm: 297, measuredMm: 300, samples: 3, ts: 0);
      expect((c.k - 0.99).abs() < 1e-9, isTrue);
      expect((c.apply(3000) - 2970).abs() < 1e-6, isTrue);
      expect(c.deltaMm, -3);
      expect(c.isUsable, isTrue);
      final back = ArScaleCalibration.fromJson(c.toJson());
      expect(back.k, c.k);
      expect(back.samples, 3);
    });

    test('偏差 >15% 或样本不足 → 不可用（多半是测错目标）', () {
      expect(
        const ArScaleCalibration(
                refMm: 297, measuredMm: 400, samples: 3, ts: 0)
            .isUsable,
        isFalse,
      );
      expect(
        const ArScaleCalibration(
                refMm: 297, measuredMm: 299, samples: 1, ts: 0)
            .isUsable,
        isFalse,
      );
    });
  });

  test('AI 目标采纳链路：端点经单应换算得到正确尺寸', () {
    // 合成斜拍投影（像素坐标）
    const h = <double>[
      0.5, 0, 200, //
      0, 0.5, 150, //
      0.00018, 0.00012, 1, //
    ];
    const imgW = 4000.0, imgH = 3000.0;
    Offset projNorm(Offset mm) {
      final d = h[6] * mm.dx + h[7] * mm.dy + h[8];
      final px = (h[0] * mm.dx + h[1] * mm.dy + h[2]) / d;
      final py = (h[3] * mm.dx + h[4] * mm.dy + h[5]) / d;
      return Offset(px / imgW, py / imgH);
    }

    // 标定：用 3×3 网格（格距 600）
    final gridMmPts = [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++) Offset(c * 600.0, r * 600.0),
    ];
    final src = gridMmPts
        .map((p) => Offset(projNorm(p).dx * imgW, projNorm(p).dy * imgH))
        .toList();
    final pairs = buildGridCorrespondences(
        picks: src, cols: 3, rows: 3, gridMm: 600);
    final hom = Homography.solve(pairs.src, pairs.dst)!;
    final calib = PhotoCalib(
      refMm: 1697,
      ax: 0,
      ay: 0,
      bx: 1,
      by: 1,
      imgW: imgW,
      imgH: imgH,
      homography: hom.toList(),
      calibPoints: 9,
    );

    // AI 给出「900mm 宽」的门洞两端（真实 mm → 归一化坐标）
    final t = MeasureTarget(
      kind: 'door',
      p1: projNorm(const Offset(0, 200)),
      p2: projNorm(const Offset(900, 200)),
      conf: 0.9,
    );
    final a = Offset(t.p1.dx * imgW, t.p1.dy * imgH);
    final b = Offset(t.p2.dx * imgW, t.p2.dy * imgH);
    final mm = photoMeasuredMmAuto(calib, a.dx, a.dy, b.dx, b.dy);
    expect((mm - 900).abs() < 0.5, isTrue, reason: '实测 $mm');

    // 命名：门洞 900 × 洞口高 2100 → M0921
    expect(openingCode(t.kind, mm, 2100), 'M0921');
    // 模数吸附：890 附近应吸附到 900
    expect(snapToModule(893)!.value, 900);
  });
}
