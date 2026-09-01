import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/data/mock/mock_data.dart';
import 'package:gongdi_app/data/mock/weekly_report_mock.dart';
import 'package:gongdi_app/data/models.dart';
import 'package:gongdi_app/data/weekly_report.dart';
import 'package:gongdi_app/features/defects/report_content.dart';
import 'package:gongdi_app/features/defects/report_docx.dart';
import 'package:gongdi_app/features/defects/report_pdf.dart';

/// 验证 PDF / Word 两个导出端：
/// - 文件结构合法（zip 头 / PDF 头）；
/// - 与 HTML 端共用章节顺序、空板块剔除规则、照片内嵌；
/// - 落一份示例文件到 `build/` 供人工用 Word / 浏览器打开核对。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, Uint8List>> loadPhotos(WeeklyReport r) async {
    final map = <String, Uint8List>{};
    for (final p in r.photos) {
      try {
        final d = await rootBundle.load(p.file);
        map[p.file] = d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
      } catch (_) {}
    }
    return map;
  }

  WeeklyReport sample() =>
      dy04WeeklyReport.copyWithDefects([...defects, ...dy7Defects]);

  test('buildWeeklyReportDocx 产出合法 .docx', () async {
    final report = sample();
    final photos = await loadPhotos(report);
    expect(photos, isNotEmpty);

    final bytes = buildWeeklyReportDocx(
      report,
      reporter: '欧阳嘉 · Arcadis（凯迪思） · 全过程咨询 / PMO',
      generatedAt: '2026-09-01 11:00',
      photoBytes: photos,
    );

    // zip 包标识
    expect(String.fromCharCodes(bytes.take(2)), 'PK');
    expect(bytes.length, greaterThan(10000));

    final out = File('build/现场工作汇报_示例.docx');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);

    // 解包校验内容
    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toList();
    expect(names, contains('[Content_Types].xml'));
    expect(names, contains('word/document.xml'));
    expect(names, contains('word/styles.xml'));
    expect(names, anyElement(startsWith('word/media/')));

    final xml = utf8.decode(
        zip.files.firstWhere((f) => f.name == 'word/document.xml').content
            as List<int>);
    expect(xml, contains('项目东区现场工作汇报'));
    expect(xml, contains('现场施工进度情况'));
    expect(xml, contains('现场（机电）施工进度情况'));
    expect(xml, contains('待沟通协调问题'));
    expect(xml, contains('现场问题清单及闭环情况'));
    // 空板块剔除（与 HTML 端同规则）
    expect(xml, isNot(contains('本周无')));
    expect(xml, isNot(contains('图档台账')));
    // 照片以 DrawingML + 关系 ID 内嵌
    expect(xml, contains('<w:drawing>'));
    expect(xml, contains('r:embed="rIdImg1"'));

    // 关系文件必须登记所有图片，否则 Word 打不开图
    // （Target 是相对 word/ 目录的路径，故为 media/xxx.jpg）
    final rels = utf8.decode(
        zip.files.firstWhere((f) => f.name == 'word/_rels/document.xml.rels')
            .content as List<int>);
    for (final n in names.where((n) => n.startsWith('word/media/'))) {
      expect(rels, contains(n.replaceFirst('word/', '')));
    }
  });

  test('buildWeeklyReportPdf 产出合法 PDF（含嵌入字体与照片）', () async {
    final report = sample();
    final photos = await loadPhotos(report);

    final bytes = await buildWeeklyReportPdf(
      report,
      reporter: '欧阳嘉 · Arcadis（凯迪思） · 全过程咨询 / PMO',
      generatedAt: '2026-09-01 11:00',
      photoBytes: photos,
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(10000));
    final raw = latin1.decode(bytes, allowInvalid: true);
    // 照片以 JPEG 流内嵌
    expect(raw, contains('/DCTDecode'));
    // 中文字体以 TrueType 字体文件嵌入（FontFile2）
    expect(raw, contains('/FontFile2'));
    // package:pdf 会做字体子集化，成品不应把 7MB 字体整体塞进去
    expect(bytes.length, lessThan(6 * 1024 * 1024));

    final out = File('build/现场工作汇报_示例.pdf');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
  });

  test('三个渲染端共用同一套板块顺序与过滤规则', () {
    final blocks = buildReportBlocks(sample());
    expect(blocks.map((b) => b.title), [
      '现场施工进度情况',
      '现场（机电）施工进度情况',
      '待沟通协调问题',
      '现场问题清单及闭环情况',
    ]);
  });

  test('PDF / DOCX 缺陷卡渲染现场照片', () async {
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
    final report = dy04WeeklyReport.copyWithDefects([defect]);
    final photo = await rootBundle.load('assets/site_photos/site_01.jpg');
    final bytes =
        photo.buffer.asUint8List(photo.offsetInBytes, photo.lengthInBytes);
    final photoBytes = {'photos/test.jpg': bytes};

    // DOCX：缺陷照片以 DrawingML 内嵌
    final docx = buildWeeklyReportDocx(
      report,
      reporter: '测试',
      generatedAt: '2026-09-01 11:00',
      photoBytes: photoBytes,
    );
    final zip = ZipDecoder().decodeBytes(docx);
    final xml = utf8.decode(
        zip.files.firstWhere((f) => f.name == 'word/document.xml').content
            as List<int>);
    expect(xml, contains('现场照片'));
    expect(xml, contains('r:embed="rIdImg'));

    // PDF：照片以 JPEG 流内嵌
    final pdf = await buildWeeklyReportPdf(
      report,
      reporter: '测试',
      generatedAt: '2026-09-01 11:00',
      photoBytes: photoBytes,
    );
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(latin1.decode(pdf, allowInvalid: true), contains('/DCTDecode'));
  });
}
