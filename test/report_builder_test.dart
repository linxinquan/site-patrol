import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/data/mock/mock_data.dart';
import 'package:gongdi_app/data/mock/weekly_report_mock.dart';
import 'package:gongdi_app/data/models.dart';
import 'package:gongdi_app/data/weekly_report.dart';
import 'package:gongdi_app/features/defects/report_builder.dart';

/// 验证周报生成器：输出非空、含周报各板块，并落一份示例 HTML（带真图）供人工预览。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, String>> loadPhotos(WeeklyReport r) async {
    final map = <String, String>{};
    for (final p in r.photos) {
      try {
        final d = await rootBundle.load(p.file);
        map[p.file] = base64Encode(
            d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));
      } catch (_) {}
    }
    return map;
  }

  test('buildWeeklyReportHtml 生成完整工程周报', () async {
    final report =
        dy04WeeklyReport.copyWithDefects([...defects, ...dy7Defects]);
    final photos = await loadPhotos(report);
    final html = buildWeeklyReportHtml(
      report,
      reporter: '欧阳嘉 · Arcadis（凯迪思） · 全过程咨询 / PMO',
      generatedAt: '2026-09-01 11:00',
      photoBase64: photos,
    );

    // 封面
    expect(html, contains('项目东区现场工作汇报'));
    expect(html, contains('腾讯深圳总部项目'));
    expect(html, contains('2023-10-07 ~ 2023-10-13'));
    // 周报板块
    expect(html, contains('现场施工进度情况'));
    expect(html, contains('现场（机电）施工进度情况'));
    expect(html, contains('待沟通协调问题'));
    // 无数据支撑的板块（图档/变更台账、设计交底、技术协调）不再出现
    expect(html, isNot(contains('本周无')));
    expect(html, isNot(contains('图档台账')));
    expect(html, isNot(contains('变更台账')));
    expect(html, isNot(contains('设计交底')));
    // 真实数据
    expect(html, contains('云楼8栋2层空调风管穿钢梁开动遗漏'));
    expect(html, contains('绿毯F4区域防水施工'));
    // 机电进度按专业拆行（标签式）
    expect(html, contains('pg-tag'));
    // 缺陷章节
    expect(html, contains('现场问题清单及闭环情况'));
    expect(html, contains('西楼1F门诊大厅墙面空鼓'));
    // 照片已内嵌
    expect(html, contains('data:image/jpeg;base64,'));
    expect(photos.length, greaterThan(0));

    // 落一份示例文件供人工预览。
    final out = File('build/现场工作汇报_示例.html');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(html);
  });

  test('buildWeeklyReportHtml 缺陷卡内嵌现场照片（base64）', () async {
    final d0 = dy7Defects.first;
    final defect = Defect(
      id: 'photo-defect',
      part: '${d0.part}（带照片）',
      type: d0.type,
      category: d0.category,
      severity: d0.severity,
      status: d0.status,
      anchor: d0.anchor,
      floor: d0.floor,
      ts: d0.ts,
      gps: d0.gps,
      alt: d0.alt,
      resp: d0.resp,
      respUnit: d0.respUnit,
      reporter: d0.reporter,
      tags: const ['拍照识别'],
      note: d0.note,
      seed: 'test',
      drawingKey: d0.drawingKey,
      worldX: d0.worldX,
      worldY: d0.worldY,
      photoPath: 'photos/test.jpg',
    );
    final photo = await rootBundle.load('assets/site_photos/site_01.jpg');
    final bytes =
        photo.buffer.asUint8List(photo.offsetInBytes, photo.lengthInBytes);
    final html = buildWeeklyReportHtml(
      dy04WeeklyReport.copyWithDefects([defect]),
      reporter: '测试',
      generatedAt: '2026-09-01 11:00',
      photoBase64: {'photos/test.jpg': base64Encode(bytes)},
    );
    expect(html, contains('class="defect-photo"'));
    expect(html, contains('data:image/jpeg;base64,'));

    // 照片字节缺失时渲染占位，不阻断导出
    final html2 = buildWeeklyReportHtml(
      dy04WeeklyReport.copyWithDefects([defect]),
      reporter: '测试',
      generatedAt: '2026-09-01 11:00',
      photoBase64: const {},
    );
    expect(html2, contains('现场照片未加载'));
  });
}
