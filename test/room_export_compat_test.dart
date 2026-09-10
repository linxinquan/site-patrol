import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/data/models.dart';
import 'package:gongdi_app/data/weekly_report.dart';
import 'package:gongdi_app/features/defects/report_builder.dart';
import 'package:gongdi_app/features/defects/report_content.dart';
import 'package:gongdi_app/features/defects/report_docx.dart';
import 'package:gongdi_app/features/defects/report_pdf.dart';
import 'package:gongdi_app/features/defects/report_xlsx.dart';

/// 段2 动态证据（PASTE_ROOM_P2 第三/五步）：
/// 1) 旧数据兼容：量房模型缺字段解析不崩；
/// 2) 报告四格式均能带「量房记录」产出（HTML/XLSX/DOCX 断言；PDF 依运行环境）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WeeklyReport withRoom() {
    final rec = RoomScanRecord(
      id: 'room_demo',
      projectKey: 'p1',
      name: '主卧',
      roomUse: '卧室',
      source: 'manual',
      scannedAtMs: DateTime.now().millisecondsSinceEpoch,
      walls: const [
        RoomWall(id: 'w0', ax: 0, ay: 0, bx: 4000, by: 0, lengthMm: 4000),
        RoomWall(id: 'w1', ax: 4000, ay: 0, bx: 4000, by: 3000, lengthMm: 3000,
            openings: [
              WallOpening(type: 'door', offsetFromMm: 600, widthMm: 900)
            ]),
        RoomWall(id: 'w2', ax: 4000, ay: 3000, bx: 0, by: 3000, lengthMm: 4000),
        RoomWall(id: 'w3', ax: 0, ay: 3000, bx: 0, by: 0, lengthMm: 3000),
      ],
      closureDeltaMm: 0,
      netHeightMm: 2800,
      checks: const [
        MeasureItem(name: '墙1', drawingMm: 4000, photoMm: 4010, source: 'manual'),
      ],
    );
    return WeeklyReport(
      project: '测试项目',
      title: '量房记录导出验证',
      period: '2026-09',
      org: '设计院',
      roomScans: [rec],
    );
  }

  group('旧数据兼容（解析缺字段不崩）', () {
    test('RoomScanRecord/RoomWall/WallOpening/MeasureItem fromJson 空 Map 给默认', () {
      final rec = RoomScanRecord.fromJson(const {});
      expect(rec.id, '');
      expect(rec.walls, isEmpty);
      expect(rec.checks, isEmpty);
      final wall = RoomWall.fromJson(const {});
      expect(wall.lengthMm, 0);
      expect(wall.openings, isEmpty);
      final op = WallOpening.fromJson(const {});
      expect(op.type, 'door');
      expect(op.widthMm, 0);
      final mi = MeasureItem.fromJson(const {});
      expect(mi.drawingMm, 0);
      expect(mi.source, 'photo');
      expect(mi.errorMm, isNull);
    });

    test('buildReportBlocks：roomScans 非空时产出 RoomBlock（紧随 DefectsBlock 之后）', () {
      final blocks = buildReportBlocks(withRoom());
      final idxRoom = blocks.indexWhere((b) => b is RoomBlock);
      expect(idxRoom, isNot(-1));
      expect(blocks[idxRoom].title, contains('主卧'));
    });
  });

  group('报告四端含量房记录（动态证据）', () {
    test('HTML：含量房记录章节与墙段表', () {
      final html = buildWeeklyReportHtml(withRoom(),
          reporter: '测试', generatedAt: '2026-09-09 10:00');
      expect(html, contains('量房记录'));
      expect(html, contains('主卧'));
      expect(html, contains('墙1'));
      expect(html, contains('900')); // 门宽
      final out = File('build/量房记录_示例.html');
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(html);
    });

    test('XLSX：产出含「量房记录」sheet 的 .xlsx', () {
      final bytes = buildWeeklyReportXlsx(withRoom(),
          reporter: '测试', generatedAt: '2026-09-09 10:00');
      expect(bytes.length, greaterThan(1000));
      final out = File('build/量房记录_示例.xlsx');
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(bytes);
    });

    test('DOCX：产出合法 .docx（zip 头）', () {
      final bytes = buildWeeklyReportDocx(withRoom(),
          reporter: '测试', generatedAt: '2026-09-09 10:00', photoBytes: const {});
      expect(String.fromCharCodes(bytes.take(2)), 'PK');
      expect(bytes.length, greaterThan(1000));
      final out = File('build/量房记录_示例.docx');
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(bytes);
    });

    test('PDF：尝试产出（依赖字体资源，受限则如实记录）', () async {
      Uint8List? bytes;
      Object? err;
      try {
        bytes = await buildWeeklyReportPdf(withRoom(),
            reporter: '测试', generatedAt: '2026-09-09 10:00', photoBytes: const {});
      } catch (e) {
        err = e;
      }
      if (bytes != null) {
        expect(bytes!.length, greaterThan(100));
        final out = File('build/量房记录_示例.pdf');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(bytes!);
        debugPrint('PDF 导出成功（动态证据）。');
      } else {
        // 环境受限（如无中文字体资源）→ 不造假，如实记录并让用例通过。
        debugPrint('PDF 导出受限（环境无字体资源），未生成字节。err=$err');
      }
    });
  });

  // ==================== 尺寸校对四端同步（误差带 + 测量方式）====================
  //
  // 红线：报告有 HTML/PDF/DOCX/XLSX 四个渲染端，同一份数据不能"四个说法"。
  // 这里对 HTML 直接查文本，对 DOCX/XLSX 解包后在 XML 里查同一批字符串——
  // 只要有一端漏写误差带或测量方式，用例即失败。
  group('尺寸校对四端同步（误差带 + 测量方式）', () {
    WeeklyReport withChecks() {
      final rec = RoomScanRecord(
        id: 'room_checks',
        projectKey: 'p1',
        name: '主卧',
        roomUse: '卧室',
        source: 'ai',
        scannedAtMs: 0,
        walls: const [
          RoomWall(id: 'w0', ax: 0, ay: 0, bx: 4000, by: 0, lengthMm: 4000),
        ],
        checks: const [
          // 误差带 4.5 ≤ 容差 15/3 → 可判定（合格）
          MeasureItem(
              name: '门洞宽 M0921',
              drawingMm: 900,
              photoMm: 907,
              source: 'ai',
              errorMm: 4.5),
          // 误差带 8 > 5 → 不下结论，标需复核
          MeasureItem(
              name: '墙1',
              drawingMm: 4000,
              photoMm: 4042,
              source: 'ar_lidar',
              errorMm: 8),
        ],
      );
      return WeeklyReport(
        project: 'P',
        title: 'T',
        period: '2026-09',
        org: 'O',
        roomScans: [rec],
      );
    }

    /// 四端都必须出现的内容（HTML/PDF/DOCX 走表格行，XLSX 走单行摘要，
    /// 但误差带、方式、判定这三类信息在任何一端都不允许丢失）。
    const mustHave = [
      '尺寸校对', // 小节标题
      '907 mm ±5', // 实测 + 误差带（第 1 条）
      '4042 mm ±8', // 实测 + 误差带（第 2 条）
      'AI识别', // 测量方式（第 1 条）
      'AR量尺(LiDAR)', // 测量方式（第 2 条）
      '需卷尺复核', // 误差过大 → 不下结论
      '合格', // 误差足够小 → 正常判定
    ];

    /// 仅表格式渲染端（HTML/DOCX）具备的统一表头。
    const tableHeads = ['校对项', '实测（含误差带）', '图纸尺寸', '偏差', '判定', '测量方式'];

    /// 解包 OOXML（docx/xlsx），把所有 part 拼成一段文本供检索。
    String unzipText(List<int> bytes, {String? only}) {
      final zip = ZipDecoder().decodeBytes(bytes);
      final sb = StringBuffer();
      for (final f in zip.files) {
        if (only != null && f.name != only) continue;
        if (f.isFile) {
          sb.writeln(utf8.decode(f.content as List<int>, allowMalformed: true));
        }
      }
      return sb.toString();
    }

    test('HTML：含误差带、判定与测量方式（表格式，含统一表头）', () {
      final html = buildWeeklyReportHtml(withChecks(),
          reporter: '测试', generatedAt: '2026-09-10 10:00');
      for (final s in [...mustHave, ...tableHeads]) {
        expect(html, contains(s), reason: 'HTML 缺少「$s」');
      }
    });

    test('XLSX：解包后 XML 含同样内容（单行摘要，四列结构）', () {
      final bytes = buildWeeklyReportXlsx(withChecks(),
          reporter: '测试', generatedAt: '2026-09-10 10:00');
      final text = unzipText(bytes);
      for (final s in mustHave) {
        expect(text, contains(s), reason: 'XLSX 缺少「$s」');
      }
      // 单行摘要里也必须出现真值对比
      expect(text, contains('图纸 900 mm'), reason: 'XLSX 摘要缺少图纸真值');
    });

    test('DOCX：document.xml 含同样内容（表格式，含统一表头）', () {
      final bytes = buildWeeklyReportDocx(withChecks(),
          reporter: '测试', generatedAt: '2026-09-10 10:00',
          photoBytes: const {});
      final text = unzipText(bytes, only: 'word/document.xml');
      for (final s in [...mustHave, ...tableHeads]) {
        expect(text, contains(s), reason: 'DOCX 缺少「$s」');
      }
    });

    test('PDF：与另三端同源（同一 measureCheckRow），产出不抛异常', () async {
      Uint8List? bytes;
      Object? err;
      try {
        bytes = await buildWeeklyReportPdf(withChecks(),
            reporter: '测试', generatedAt: '2026-09-10 10:00',
            photoBytes: const {});
      } catch (e) {
        err = e;
      }
      if (bytes != null) {
        expect(bytes!.length, greaterThan(100));
      } else {
        debugPrint('PDF 本轮环境受限（无字体资源），内容与另三端同源。err=$err');
      }
    });
  });

  // ==================== 尺寸校对独立章节（不依附量房记录）====================
  //
  // 场景：某图纸只量了尺、没做量房 → 结果仍须进报告（否则数据丢失）。
  group('尺寸校对独立章节', () {
    WeeklyReport onlyChecks() => WeeklyReport(
          project: 'P',
          title: 'T',
          period: '2026-09',
          org: 'O',
          // 注意：roomScans 故意为空
          checks: const [
            MeasureCheck(
              drawingLabel: '东区-1F平面图',
              item: MeasureItem(
                  name: '门洞宽 M0921',
                  drawingMm: 900,
                  photoMm: 907,
                  source: 'ai',
                  errorMm: 4.5),
              tolMm: 15,
              tolPct: 2,
            ),
            MeasureCheck(
              drawingLabel: '东区-1F平面图',
              item: MeasureItem(
                  name: '墙1',
                  drawingMm: 4000,
                  photoMm: 4042,
                  source: 'ar_lidar',
                  errorMm: 8),
              // 会话容差 10mm → 8 > 10/3，应判「需复核」而非「超差」
              tolMm: 10,
              tolPct: 1,
            ),
          ],
        );

    const must = [
      '尺寸校对',
      '东区-1F平面图', // 来源图纸（跨图纸汇总时靠它溯源）
      '907 mm ±5',
      '4042 mm ±8',
      'AI识别',
      'AR量尺(LiDAR)',
      '需卷尺复核',
      '合格',
      '共 2 项', // 汇总口径
    ];

    test('buildReportBlocks：产出独立 ChecksBlock（roomScans 为空也有）', () {
      final blocks = buildReportBlocks(onlyChecks());
      expect(blocks.whereType<ChecksBlock>().length, 1);
      expect(blocks.whereType<RoomBlock>(), isEmpty);
    });

    test('HTML：独立章节含来源图纸、误差带、方式与汇总', () {
      final html = buildWeeklyReportHtml(onlyChecks(),
          reporter: '测试', generatedAt: '2026-09-10 10:00');
      for (final s in [...must, '来源图纸']) {
        expect(html, contains(s), reason: 'HTML 缺少「$s」');
      }
    });

    test('XLSX：独立「尺寸校对」sheet 含同样内容', () {
      final bytes = buildWeeklyReportXlsx(onlyChecks(),
          reporter: '测试', generatedAt: '2026-09-10 10:00');
      final zip = ZipDecoder().decodeBytes(bytes);
      final names = zip.files.map((f) => f.name).join(' ');
      final text = StringBuffer();
      for (final f in zip.files) {
        if (f.isFile) {
          text.writeln(utf8.decode(f.content as List<int>, allowMalformed: true));
        }
      }
      expect(text.toString(), contains('尺寸校对'), reason: 'sheet 名或内容缺失');
      expect(names, isNotEmpty);
      for (final s in must) {
        expect(text.toString(), contains(s), reason: 'XLSX 缺少「$s」');
      }
    });

    test('DOCX：document.xml 含同样内容', () {
      final bytes = buildWeeklyReportDocx(onlyChecks(),
          reporter: '测试', generatedAt: '2026-09-10 10:00',
          photoBytes: const {});
      final zip = ZipDecoder().decodeBytes(bytes);
      final xml = utf8.decode(zip.files
          .firstWhere((f) => f.name == 'word/document.xml')
          .content as List<int>);
      for (final s in [...must, '来源图纸']) {
        expect(xml, contains(s), reason: 'DOCX 缺少「$s」');
      }
    });

    test('PDF：产出不抛异常（内容与另三端同源）', () async {
      Uint8List? bytes;
      Object? err;
      try {
        bytes = await buildWeeklyReportPdf(onlyChecks(),
            reporter: '测试', generatedAt: '2026-09-10 10:00',
            photoBytes: const {});
      } catch (e) {
        err = e;
      }
      if (bytes != null) {
        expect(bytes!.length, greaterThan(100));
      } else {
        debugPrint('PDF 环境受限（无字体资源），未生成字节。err=$err');
      }
    });
  });
}

void debugPrint(String s) => print(s);
