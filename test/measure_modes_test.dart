import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/core/utils/measure_labels.dart';
import 'package:gongdi_app/core/utils/measure_math.dart';
import 'package:gongdi_app/core/utils/measure_modes.dart';
import 'package:gongdi_app/core/utils/measure_stats.dart';
import 'package:gongdi_app/core/utils/measure_style.dart';
import 'package:gongdi_app/data/models.dart';
import 'package:gongdi_app/data/weekly_report.dart';

MeasureItem edge(
  double mm, {
  double? errMm,
  String name = '边长',
  String source = 'ar_lidar',
  double drawingMm = 0,
}) =>
    MeasureItem(
      name: name,
      drawingMm: drawingMm,
      photoMm: mm,
      source: source,
      errorMm: errMm,
    );

void main() {
  group('面积/体积组合（含误差传递）', () {
    test('面积 = 长 × 宽，单位换算到 ㎡', () {
      final r = computeArea(edge(3200, errMm: 16), edge(4100, errMm: 20))!;
      expect(r.value, closeTo(13.12, 1e-9), reason: '3.2m × 4.1m');
      // 相对误差：0.5% + 0.4878% ≈ 0.9878% → 13.12 × 0.9878% ≈ 0.1296
      expect(r.err, closeTo(0.13, 0.005), reason: '误差带按相对误差相加');
    });

    test('体积 = 长 × 宽 × 高，单位换算到 m³', () {
      final r = combine(
        [edge(3000, errMm: 15), edge(4000, errMm: 20), edge(2800, errMm: 14)],
        isVolume: true,
      )!;
      expect(r.value, closeTo(33.6, 1e-9));
      expect(r.err, greaterThan(0));
      expect(r.err, lessThan(r.value * 0.03), reason: '误差带应在 1~3% 量级');
    });

    test('误差带缺省时按 0.5% 保守估计（不假装精确）', () {
      final r = computeArea(edge(1000), edge(1000))!;
      expect(r.value, closeTo(1.0, 1e-9));
      expect(r.err, closeTo(1.0 * 0.01, 1e-9), reason: '两侧各 0.5%');
    });

    test('非法输入返回 null（不抛异常、不给假数）', () {
      expect(computeArea(edge(0), edge(1000)), isNull);
      expect(computeArea(edge(-100), edge(1000)), isNull);
      // 面积项不能当因子（单位不是 mm）
      final areaItem = buildCalcItem(
          factors: [edge(1000), edge(1000)],
          value: 1,
          err: 0.01,
          isVolume: false);
      expect(computeArea(areaItem, edge(1000)), isNull);
    });

    test('量级校验挡住明显点错（如把 mm 当 cm）', () {
      expect(plausibleArea(13.12), isTrue);
      expect(plausibleArea(0.001), isFalse);
      expect(plausibleArea(99999), isFalse);
      expect(plausibleVolume(33.6), isTrue);
      expect(plausibleVolume(999999), isFalse);
      // 组合入口同样受校验约束
      expect(combine([edge(1), edge(1)], isVolume: false), isNull);
    });

    test('因子数量必须精确匹配（面积 2、体积 3）', () {
      expect(requiredFactors(isVolume: false), 2);
      expect(requiredFactors(isVolume: true), 3);
      expect(canCombine([edge(1000)], isVolume: false), isFalse);
      expect(canCombine([edge(1000), edge(1000)], isVolume: false), isTrue);
      expect(canCombine([edge(1000), edge(1000)], isVolume: true), isFalse);
    });

    test('buildCalcItem：单位与文案正确，且不参与合格判定', () {
      final item = buildCalcItem(
        factors: [edge(3200, name: '开间'), edge(4100, name: '进深')],
        value: 13.1234,
        err: 0.1296,
        isVolume: false,
      );
      expect(item.unit, 'm2');
      expect(item.source, 'calc');
      expect(item.drawingMm, 0, reason: '面积无图纸对照');
      expect(item.name, contains('13.12'));
      expect(item.name, contains('㎡'));
      expect(item.name, contains('3200 × 4100 mm'));
      expect(measureValueText(item), '13.12 ㎡ ±0.13');
      expect(measureVerdictText(item, 15, 2), contains('不判定'));
    });

    test('volume item 同样带 m³ 单位与文案', () {
      final item = buildCalcItem(
        factors: [edge(3000), edge(4000), edge(2800)],
        value: 33.6,
        err: 0.5,
        isVolume: true,
      );
      expect(item.unit, 'm3');
      expect(measureValueText(item), '33.60 m³ ±0.50');
      expect(combineLabel((value: 33.6, err: 0.5), isVolume: true),
          contains('m³'));
    });

    test('suggestFactors：默认挑最长的边，且数量正确', () {
      final cands = [edge(1200), edge(4000), edge(3200), edge(900)];
      final s2 = suggestFactors(cands, isVolume: false);
      expect(s2.length, 2);
      expect(s2.map((e) => e.photoMm).toList(), [4000, 3200]);
      final s3 = suggestFactors(cands, isVolume: true);
      expect(s3.length, 3);
    });
  });

  group('面积/体积模式连续测量（FaceBuilder）', () {
    test('面积：量够 2 条边自动出面，中途不产出', () {
      final b = FaceBuilder(isVolume: false);
      expect(b.need, 2);
      expect(b.add(edge(4000, errMm: 20)), isNull);
      expect(b.got, 1);
      expect(b.currentLabel, '宽', reason: '已量长，下一条是宽');
      expect(b.progressText(), '长 4.000m ✓ · 宽 待测');

      final out = b.add(edge(2000, errMm: 10));
      expect(out, isNotNull);
      expect(out!.item.unit, 'm2');
      expect((out.item.photoMm - 8.0).abs() < 1e-9, isTrue, reason: '4m × 2m');
      expect(out.factors.length, 2);
      // 产出后自动清空，可继续量下一个面（连续测量）
      expect(b.got, 0);
      expect(b.progressText(), '长 待测 · 宽 待测');
    });

    test('体积：量够 3 条边自动成体', () {
      final b = FaceBuilder(isVolume: true);
      expect(b.need, 3);
      expect(b.add(edge(4000)), isNull);
      expect(b.add(edge(2000)), isNull);
      expect(b.currentLabel, '高');
      final out = b.add(edge(1000));
      expect(out!.item.unit, 'm3');
      expect((out.item.photoMm - 8.0).abs() < 1e-9, isTrue, reason: '4×2×1');
    });

    test('量级异常（点错）→ 不产出且清空，避免脏数据继续叠加', () {
      final b = FaceBuilder(isVolume: false);
      b.add(edge(4000));
      // 第二条只有 0.001mm 量级 → combine 校验拦下
      final out = b.add(edge(0.001));
      expect(out, isNull);
      expect(b.got, 0, reason: '异常后必须清空已积累的边');
    });

    test('模式与边数定义：直线 1、面积 2、体积 3', () {
      expect(ArGeometryMode.line.edgeCount, 1);
      expect(ArGeometryMode.area.edgeCount, 2);
      expect(ArGeometryMode.volume.edgeCount, 3);
      expect(ArGeometryMode.area.isFace, isTrue);
      expect(ArGeometryMode.line.isFace, isFalse);
      expect(edgeLabels(isVolume: true), ['长', '宽', '高']);
      expect(edgeLabels(isVolume: false), ['长', '宽']);
    });
  });

  group('预览/示意的合成几何（比例来自真实读数）', () {
    test('面域矩形：长宽比与实测一致，且不超出视口', () {
      const size = Size(360, 480);
      final r = synthFaceRect(size, 4000, 2000);
      expect((r.width / r.height - 2.0).abs() < 1e-6, isTrue);
      expect(r.width <= size.width * 0.72 + 1e-6, isTrue);
      expect(r.height <= size.height * 0.62 + 1e-6, isTrue);
      // 退化输入不抛异常
      expect(synthFaceRect(size, 0, 2000).width, 0);
    });

    test('体积几何：底面 4 角 + 上移向量（向上）', () {
      const size = Size(360, 480);
      final g = synthVolumeGeometry(size, 4000, 2000, 1500);
      expect(g.base.length, 4);
      expect(g.rise.dy < 0, isTrue, reason: '高度方向在屏幕上向上');
      expect(synthVolumeGeometry(size, 0, 1, 1).base, isEmpty);
    });
  });

  group('面域四角推导（faceCorners，真机原生绘制用）', () {
    EdgeGeom edge(
      double ax, double ay, double az,
      double bx, double by, double bz,
    ) =>
        (ax: ax, ay: ay, az: az, bx: bx, by: by, bz: bz);

    test('共享墙角：以公共角点为原点铺矩形', () {
      // 开间（东向 4m）+ 进深（南向 2m），共角点在原点
      final e1 = edge(0, 0, 0, 4, 0, 0);
      final e2 = edge(0, 0, 0, 0, 0, -2);
      final c = faceCorners(e1, e2);
      expect(c.length, 4);
      expect(c[0], (x: 0.0, y: 0.0, z: 0.0));
      expect(c[1], (x: 4.0, y: 0.0, z: 0.0));
      // 第四角 = far1 + (far2 - shared) = (4,0,0) + (0,0,-2)
      expect(c[2], (x: 4.0, y: 0.0, z: -2.0));
      expect(c[3], (x: 0.0, y: 0.0, z: -2.0));
    });

    test('共享墙角（方向相反配对）也能识别', () {
      final e1 = edge(4, 0, 0, 0, 0, 0); // 反向：B 在原点
      final e2 = edge(0, 0, 0, 0, 0, -2);
      final c = faceCorners(e1, e2);
      expect(c[0], (x: 0.0, y: 0.0, z: 0.0));
      expect(c[1], (x: 4.0, y: 0.0, z: 0.0));
      expect(c[3], (x: 0.0, y: 0.0, z: -2.0));
    });

    test('无共享角点：以第一条边为底边、第二条边方向平移', () {
      final e1 = edge(0, 0, 0, 4, 0, 0);
      final e2 = edge(1, 0, 0, 1, 0, -3); // 与 e1 无公共端点
      final c = faceCorners(e1, e2);
      expect(c[0], (x: 0.0, y: 0.0, z: 0.0));
      expect(c[1], (x: 4.0, y: 0.0, z: 0.0));
      expect(c[2], (x: 4.0, y: 0.0, z: -3.0));
      expect(c[3], (x: 0.0, y: 0.0, z: -3.0));
    });

    test('共享角点阈值外（>8cm）走平移分支', () {
      final e1 = edge(0, 0, 0, 4, 0, 0);
      final e2 = edge(0.2, 0, 0, 0.2, 0, -2); // 最近端点距 0.2m > 0.08m
      final c = faceCorners(e1, e2);
      // 平移分支：以 e1 为底边，四角 = e1 的两端 + 沿 e2 方向平移
      expect(c[0], (x: 0.0, y: 0.0, z: 0.0));
      expect(c[1], (x: 4.0, y: 0.0, z: 0.0));
      expect(c[2], (x: 4.0, y: 0.0, z: -2.0));
    });
  });

  group('单位感知的清单 / 报告文案（防止 ㎡ 被当 mm 取整）', () {
    test('线性尺寸仍按制图习惯取整', () {
      expect(measureValueText(edge(907, errMm: 4.5, name: '门洞宽')), '907 mm ±5');
      expect(measureUnitLabel('mm'), 'mm');
    });

    test('面积/体积保留 2 位小数（不取整、不带 mm）', () {
      final area = buildCalcItem(
          factors: [edge(1000), edge(1250)],
          value: 1.25,
          err: 0.0125,
          isVolume: false);
      expect(measureValueText(area), '1.25 ㎡ ±0.01');
      expect(measureValueText(area), isNot(contains('mm')));
    });

    test('面积/体积行在报告表格里不出现"图纸 0 mm / 偏差 +x mm"', () {
      final area = buildCalcItem(
          factors: [edge(1000), edge(1000)],
          value: 1.0,
          err: 0.01,
          isVolume: false);
      final row = measureCheckRow(area);
      expect(row.length, kCheckTableHeaders.length, reason: '列数与表头一致');
      expect(row[2], '—', reason: '图纸尺寸列应为 —');
      expect(row[3], '—', reason: '偏差列应为 —');
      final line = measureCheckLine(area);
      expect(line, contains('不判定'));
      expect(line, isNot(contains('图纸')));
    });

    test('汇总口径把"未判定"单列，不混进"需复核"', () {
      final checks = [
        // 有图纸对照 + 误差带达标 → 合格
        MeasureCheck(
            drawingLabel: 'A',
            item: edge(907, errMm: 4, name: '门洞宽', drawingMm: 900)),
        // 误差带超门槛（20 > 15/3）→ 需复核
        MeasureCheck(
            drawingLabel: 'A',
            item: edge(906, errMm: 20, name: '墙长', drawingMm: 900)),
        MeasureCheck(
            drawingLabel: 'A',
            item: buildCalcItem(
                factors: [edge(1000), edge(1000)],
                value: 1.0,
                err: 0.01,
                isVolume: false)),
      ];
      final s = summarizeChecks(checks);
      expect(s.total, 3);
      expect(s.na, 1, reason: '面积项计入"未判定"');
      expect(s.review, 1);
      final text = checksSummaryText(checks);
      expect(text, contains('未判定 1 项'));
    });

    test('偏差趋势只统计线性尺寸（面积/体积不参与分布）', () {
      final items = [
        MeasureItem(name: 'A', drawingMm: 1000, photoMm: 1010),
        MeasureItem(name: 'B', drawingMm: 1000, photoMm: 1020),
        MeasureItem(name: 'C', drawingMm: 1000, photoMm: 1030),
        buildCalcItem(
            factors: [edge(1000), edge(1000)],
            value: 1.0,
            err: 0.01,
            isVolume: false),
      ];
      final t = deviationTrend(items);
      expect(t.n, 3, reason: '面积项被排除');
      expect(biasHint(items), contains('系统性偏大'));
    });
  });
}
