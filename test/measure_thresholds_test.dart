import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/core/storage/measure_threshold_store.dart';
import 'package:gongdi_app/core/utils/measure_labels.dart';
import 'package:gongdi_app/core/utils/measure_stats.dart';
import 'package:gongdi_app/data/models.dart';
import 'package:gongdi_app/data/vision_service.dart';
import 'package:gongdi_app/data/weekly_report.dart';
import 'package:gongdi_app/features/defects/report_content.dart';

MeasureItem itemWith({
  String name = '门洞宽',
  double drawingMm = 900,
  double photoMm = 907,
  double? errorMm,
  String source = 'ai',
}) =>
    MeasureItem(
      name: name,
      drawingMm: drawingMm,
      photoMm: photoMm,
      source: source,
      errorMm: errorMm,
    );

void main() {
  group('项目级判定门槛（不再硬编码 15mm/2%）', () {
    test('默认门槛：容差 15/2%，误差带门槛 = 容差/3', () {
      const t = MeasureThresholds();
      expect(t.isDefault, isTrue);
      expect(t.effectiveJudgeMax, closeTo(5, 1e-9));
      expect(t.summary, contains('15'));
      expect(t.summary, contains('5'));
    });

    test('自定义门槛覆盖容差/3，判定结论随之改变', () {
      final item = itemWith(errorMm: 6);
      // 默认：6 > 15/3=5 → 不下结论
      expect(measureVerdictText(item, 15, 2), contains('需卷尺复核'));
      // 项目门槛放宽到 10mm → 允许判定（偏差 +7 ≤ 15 → 合格）
      expect(measureVerdictText(item, 15, 2, judgeMaxErrorMm: 10), '合格');
      // 项目门槛收紧到 3mm → 仍不下结论
      expect(measureVerdictText(item, 15, 2, judgeMaxErrorMm: 3),
          contains('需卷尺复核'));
    });

    test('容差本身也可项目化（0.5mm 级精装）', () {
      final item = itemWith(drawingMm: 900, photoMm: 903, errorMm: 0.5);
      // 项目容差 ±2mm：偏差 3 > 2 → 超差
      expect(measureVerdictText(item, 2, 0.2, judgeMaxErrorMm: 1), '超差');
      // 项目容差 ±5mm：偏差 3 ≤ 5 → 合格
      expect(measureVerdictText(item, 5, 0.5, judgeMaxErrorMm: 1), '合格');
    });

    test('MeasureCheck 带门槛 → 汇总口径与逐条判定一致', () {
      final checks = [
        MeasureCheck(
            drawingLabel: 'A 图', item: itemWith(errorMm: 6), tolMm: 15),
        MeasureCheck(
            drawingLabel: 'A 图',
            item: itemWith(errorMm: 6),
            tolMm: 15,
            judgeMaxErrorMm: 10),
      ];
      final s = summarizeChecks(checks);
      expect(s.total, 2);
      expect(s.ok, 1, reason: '第二条门槛放宽后可判定');
      expect(s.review, 1, reason: '第一条按默认容差/3 需复核');
    });

    test('JSON 往返：未设置门槛时不写字段、读回仍为 null', () {
      const t = MeasureThresholds(tolMm: 5, tolPct: 1);
      final back = MeasureThresholds.fromJson(t.toJson());
      expect(back.tolMm, 5);
      expect(back.tolPct, 1);
      expect(back.judgeMaxErrorMm, isNull);
      expect(back.effectiveJudgeMax, closeTo(5 / 3, 1e-9));

      const t2 = MeasureThresholds(judgeMaxErrorMm: 4);
      expect(MeasureThresholds.fromJson(t2.toJson()).judgeMaxErrorMm, 4);
      // 脏数据安全降级
      expect(MeasureThresholds.fromJson(const {}).tolMm, 15);
    });
  });

  group('偏差趋势（发现系统性偏差）', () {
    List<MeasureItem> devs(List<double> d) => [
          for (var i = 0; i < d.length; i++)
            MeasureItem(
                name: '项$i', drawingMm: 1000, photoMm: 1000 + d[i]),
        ];

    test('统计量：中位/均值/极值/标准差', () {
      final t = deviationTrend(devs([10, 20, 30]));
      expect(t.n, 3);
      expect(t.median, 20);
      expect(t.mean, closeTo(20, 1e-9));
      expect(t.min, 10);
      expect(t.max, 30);
      expect(t.sd, closeTo(10, 1e-9), reason: '样本标准差 n-1');
    });

    test('同号偏差占比高 → 疑系统性偏大/偏小', () {
      expect(biasHint(devs([10, 20, 30])), contains('系统性偏大'));
      expect(biasHint(devs([-10, -20, -30])), contains('系统性偏小'));
    });

    test('正负分散 → 判为随机误差', () {
      expect(biasHint(devs([10, -12, 8, -9, 5, -6])), contains('随机误差'));
    });

    test('无图纸真值不参与统计（避免假分布）', () {
      final t = deviationTrend([
        const MeasureItem(name: '未填图纸', drawingMm: 0, photoMm: 900),
      ]);
      expect(t.n, 0);
      expect(deviationTrendText([const MeasureItem(name: 'x', drawingMm: 0, photoMm: 900)]),
          contains('无有效对照项'));
    });

    test('文案含中位/标准差/判读，可直接进报告', () {
      final s = deviationTrendText(devs([10, 20, 30]));
      expect(s, contains('中位'));
      expect(s, contains('标准差'));
      expect(s, contains('系统性偏大'));
      expect(checksSummaryLines(const []).length, 2);
    });
  });

  test('报告概览统计含尺寸校对（与缺陷统计并列）', () {
    final report = WeeklyReport(
      project: 'P',
      title: 'T',
      period: '2026-09',
      org: 'O',
      checks: [
        // 合格：误差带 4 ≤ 5
        MeasureCheck(
            drawingLabel: 'A',
            item: itemWith(drawingMm: 900, photoMm: 907, errorMm: 4)),
        // 超差：误差带 4 ≤ 5，但偏差 +60 > 15
        MeasureCheck(
            drawingLabel: 'A',
            item: itemWith(drawingMm: 900, photoMm: 960, errorMm: 4)),
        // 需复核：误差带 8 > 5
        MeasureCheck(
            drawingLabel: 'B',
            item: itemWith(drawingMm: 900, photoMm: 907, errorMm: 8)),
      ],
    );
    final s = buildReportStats(report);
    expect(s.checkTotal, 3);
    expect(s.checkOk, 1);
    expect(s.checkFail, 1);
    expect(s.checkReview, 1);
    // 与缺陷统计互不影响
    expect(s.defects, 0);
  });

  test('AI 门窗宽高配对字段（axis/group）解析', () {
    final list = MeasureTarget.listFromContent('{"targets":['
        '{"kind":"door","group":"door1","axis":"width",'
        '"p1":[0.30,0.60],"p2":[0.70,0.60],"conf":0.9},'
        '{"kind":"door","group":"door1","axis":"height",'
        '"p1":[0.30,0.60],"p2":[0.30,0.20],"conf":0.88}]}');
    expect(list, isNotNull);
    expect(list!.length, 2);
    expect(list.where((t) => t.isWidth).length, 1);
    expect(list.where((t) => t.isHeight).length, 1);
    expect(list.first.group, 'door1');
    // 缺 axis/group 的老格式仍可解析（向后兼容）
    final legacy = MeasureTarget.listFromContent('{"targets":['
        '{"kind":"beam","p1":[0.1,0.2],"p2":[0.6,0.2],"conf":0.8}]}');
    expect(legacy!.single.axis, '');
    expect(legacy.single.group, '');
  });
}
