import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../data/models.dart';
import '../../data/weekly_report.dart';
import 'report_content.dart';

/// 现场工作汇报 → Excel 销项表（.xlsx，SpreadsheetML）生成器。
///
/// 纯 Dart 手写 OOXML + `package:archive` 打包，与 `report_docx.dart` 同一套路，
/// **不依赖任何插件 / 原生能力**，Web、桌面、移动端都能生成同一份文件。
///
/// 表结构对齐设计师巡场报告单（LDI/SZAD 模板）三大区：
///   巡场意见（序号 / 重要等级 / 意见描述）→ 整改回复（内容 / 回复人 / 时间）
///   → 闭合确认（是否闭合 / 完成状态 / 未闭合说明）
///
/// 两个工作表：
///   1. 「销项汇总」——周期、项目、统计概览
///   2. 「巡场销项表」——按楼栋分组的明细行（无楼栋数据时回退按严重程度分组）
///
/// 单元格统一用 `inlineStr`（内联字符串），省去 sharedStrings 索引管理，
/// 代价是体积略大，对本场景（几百行）可忽略。
Uint8List buildWeeklyReportXlsx(
  WeeklyReport report, {
  required String reporter,
  required String generatedAt,
}) {
  final book = _XlsxBook();
  final stats = buildReportStats(report);

  book.summarySheet(report, stats, reporter, generatedAt);
  book.defectSheet(report, stats);
  return book.build();
}

// ==================== 样式槽位（styles.xml 下标）====================
// 字体
const int _fNormal = 0;
const int _fBold = 1;
const int _fHeader = 2; // 加粗 + 白色
const int _fTitle = 3; // 加粗 + 大号

// 填充（OOXML 约定：槽位 0 = none、槽位 1 = gray125 为规范必需，
// 即使本文件不直接引用也必须按此顺序占位，否则 Excel 打开报样式错误。
// 下方 _styles() 的 fills 顺序即对应这些编号。）
const int _fillNone = 0;
const int _fillBrand = 2; // 表头品牌蓝
const int _fillGroup = 3; // 楼栋分组头浅底
const int _fillAlt = 4; // 隔行浅底

// 边框（槽位 0 = none 不直接引用，仅供 fills/borders 顺序对齐用）
const int _bdBox = 1; // 细四边

// cellXfs 索引（槽位 0 = 默认，不直接引用）
const int _sTitle = 1;
const int _sMeta = 2;
const int _sHeader = 3; // 表头：品牌蓝底 + 白字加粗 + 边框 + 居中
const int _sCell = 4; // 正文：边框 + 顶端对齐 + 自动换行
const int _sCellAlt = 5; // 正文隔行浅底
const int _sGroup = 6; // 分组头：浅底加粗 + 边框
const int _sCenter = 7; // 居中正文

// ==================== 工作簿组装 ====================

class _XlsxBook {
  final List<_Sheet> _sheets = [];

  void summarySheet(
    WeeklyReport r,
    ReportStats s,
    String reporter,
    String generatedAt,
  ) {
    final rows = <_Row>[];
    var r1 = 1;
    rows.add(_Row(r1++, [_c(r.title, _sTitle)]));
    rows.add(_Row(r1++, [_c('项目：${r.project}', _sMeta)]));
    rows.add(_Row(r1++, [_c('周期：${r.period}', _sMeta)]));
    if (r.org.isNotEmpty) {
      rows.add(_Row(r1++, [_c('编制单位：${r.org}', _sMeta)]));
    }
    rows.add(_Row(r1++, [_c('编制人：$reporter    生成时间：$generatedAt', _sMeta)]));
    r1++; // 空行

    rows.add(_Row(r1++, [_c('统计概览', _sGroup), _c('', _sGroup)]));
    rows.add(_Row(r1++, [_c('指标', _sHeader), _c('数值', _sHeader)]));
    final pairs = <List<String>>[
      ['现场照片', '${s.photos}'],
      ['涉及楼栋', '${s.buildings}'],
      ['施工内容', '${s.issues}'],
      ['巡场问题', '${s.defects}'],
      ['未闭环', '${s.open}'],
      ['已闭环', '${s.done}'],
      ['重要紧急', '${s.urgent}'],
      ['已回复', '${s.replied}'],
    ];
    for (var i = 0; i < pairs.length; i++) {
      rows.add(_Row(r1++, [
        _c(pairs[i][0], i.isEven ? _sCell : _sCellAlt),
        _c(pairs[i][1], i.isEven ? _sCenter : _sCenter),
      ]));
    }
    _sheets.add(_Sheet('销项汇总', rows, cols: const [22, 14]));
  }

  void defectSheet(WeeklyReport r, ReportStats s) {
    final rows = <_Row>[];
    var idx = 1; // 工作表行号（含表头与分组头）
    var seq = 0; // 缺陷序号（跨分组累计，与 HTML/PDF 编号一致）

    // 表头：对齐巡场报告单三大区
    rows.add(_Row(idx++, const [
      _Cell('序号', _sHeader),
      _Cell('楼栋', _sHeader),
      _Cell('部位 / 缺陷', _sHeader),
      _Cell('重要等级', _sHeader),
      _Cell('严重程度', _sHeader),
      _Cell('状态', _sHeader),
      _Cell('责任单位 / 人', _sHeader),
      _Cell('发现时间', _sHeader),
      _Cell('整改回复', _sHeader),
      _Cell('回复人', _sHeader),
      _Cell('回复时间', _sHeader),
      _Cell('是否闭合', _sHeader),
      _Cell('完成状态', _sHeader),
      _Cell('未闭合说明', _sHeader),
    ]));

    var alt = false;
    for (final g in groupDefects(r.defects)) {
      // 分组头：楼栋名（或回退的严重程度名）+ 统计，横跨整行
      rows.add(_Row(idx++, [
        _c(g.title, _sGroup),
        _c(g.subtitle ?? '${g.items.length} 项', _sGroup),
        for (var i = 2; i < 14; i++) _c('', _sGroup),
      ]));
      for (final d in g.items) {
        seq++;
        rows.add(_Row(idx++, [
          _c('$seq', alt ? _sCenter : _sCenter),
          _c(d.buildingOrEmpty, alt ? _sCellAlt : _sCell),
          _c(_defectText(d), alt ? _sCellAlt : _sCell),
          _c(d.effectiveImportance.label, alt ? _sCenter : _sCenter),
          _c(d.severity.label, alt ? _sCenter : _sCenter),
          _c(d.status.label, alt ? _sCenter : _sCenter),
          _c(_respText(d), alt ? _sCellAlt : _sCell),
          _c(d.ts, alt ? _sCenter : _sCenter),
          _c(d.reply ?? '', alt ? _sCellAlt : _sCell),
          _c(d.replyBy ?? '', alt ? _sCellAlt : _sCell),
          _c(d.replyTs ?? '', alt ? _sCenter : _sCenter),
          _c(d.closed ? '是' : '否', alt ? _sCenter : _sCenter),
          _c(d.completion ?? '', alt ? _sCenter : _sCenter),
          _c(d.closeNote ?? '', alt ? _sCellAlt : _sCell),
        ]));
        alt = !alt;
      }
    }
    _sheets.add(_Sheet('巡场销项表', rows, cols: const [
      6, 10, 30, 12, 10, 10, 20, 18, 30, 12, 18, 10, 12, 24
    ]));
  }

  Uint8List build() {
    final archive = Archive();
    void add(String name, String text) =>
        archive.addFile(ArchiveFile.bytes(name, utf8.encode(text)));

    add('[Content_Types].xml', _contentTypes(_sheets.length));
    add('_rels/.rels', _rootRels());
    add('xl/workbook.xml', _workbook(_sheets));
    add('xl/_rels/workbook.xml.rels', _workbookRels(_sheets.length));
    add('xl/styles.xml', _styles());
    for (var i = 0; i < _sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _worksheet(_sheets[i]));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}

// ==================== 数据模型 ====================

class _Sheet {
  _Sheet(this.name, this.rows, {required this.cols});
  final String name;
  final List<_Row> rows;
  final List<int> cols;
}

class _Row {
  _Row(this.r, this.cells);
  final int r;
  final List<_Cell> cells;
}

class _Cell {
  const _Cell(this.text, this.style);
  final String text;
  final int style;
}

_Cell _c(String text, int style) => _Cell(text, style);

/// 「部位 / 缺陷」列文本：部位 + 缺陷类型 + 描述概要。
String _defectText(Defect d) {
  final buf = StringBuffer();
  final part = d.part.trim();
  if (part.isNotEmpty) buf.write(part);
  final type = d.type.trim();
  if (type.isNotEmpty) {
    if (buf.isNotEmpty) buf.write(' · ');
    buf.write(type);
  }
  final note = d.note.trim();
  if (note.isNotEmpty) {
    if (buf.isNotEmpty) buf.write('\n');
    buf.write(note);
  }
  return buf.toString();
}

/// 责任人文本：优先「单位 人」，回退单字段。
String _respText(Defect d) {
  final unit = d.respUnit.trim();
  final resp = d.resp.trim();
  if (unit.isNotEmpty && resp.isNotEmpty) return '$unit $resp';
  return unit.isNotEmpty ? unit : resp;
}

// ==================== XML 片段 ====================

/// XML 文本转义（属性与正文通用）。
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// 控制字符在 XML 1.0 中非法，需剔除（照片备注等可能带换行以外的控制符）。
String _xmlSafe(String s) => s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// 列号 → 列名（0→A，25→Z，26→AA）。
String _colName(int index) {
  var n = index;
  final buf = StringBuffer();
  while (n >= 0) {
    buf.write(String.fromCharCode(65 + (n % 26)));
    n = n ~/ 26 - 1;
  }
  return buf.toString().split('').reversed.join();
}

String _contentTypes(int sheetCount) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
${[
  for (var i = 1; i <= sheetCount; i++)
    '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
].join('\n')}
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''';

String _rootRels() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

String _workbook(List<_Sheet> sheets) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>${[
  for (var i = 0; i < sheets.length; i++)
    '<sheet name="${_esc(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'
].join('')}</sheets>
</workbook>''';

String _workbookRels(int sheetCount) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[
  for (var i = 1; i <= sheetCount; i++)
    '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'
].join('\n')}
<Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

String _worksheet(_Sheet sheet) {
  final cols = <String>[];
  for (var i = 0; i < sheet.cols.length; i++) {
    cols.add('<col min="${i + 1}" max="${i + 1}" width="${sheet.cols[i]}" customWidth="1"/>');
  }
  final rows = sheet.rows.map((row) {
    final cells = <String>[];
    for (var i = 0; i < row.cells.length; i++) {
      final c = row.cells[i];
      if (c.text.isEmpty) {
        // 空单元格只写样式，保持边框连续
        cells.add('<c r="${_colName(i)}${row.r}" s="${c.style}"/>');
      } else {
        cells.add('<c r="${_colName(i)}${row.r}" s="${c.style}" t="inlineStr">'
            '<is><t xml:space="preserve">${_esc(_xmlSafe(c.text))}</t></is></c>');
      }
    }
    return '<row r="${row.r}">${cells.join('')}</row>';
  }).join('');

  final lastRow = sheet.rows.isEmpty ? 1 : sheet.rows.last.r;
  final lastCol = sheet.cols.length;
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<dimension ref="A1:${_colName(lastCol - 1)}$lastRow"/>
<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
<sheetFormatPr defaultRowHeight="16"/>
<cols>${cols.join('')}</cols>
<sheetData>$rows</sheetData>
</worksheet>''';
}

String _styles() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="4">
<font><sz val="11"/><name val="等线"/></font>
<font><b/><sz val="11"/><name val="等线"/></font>
<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="等线"/></font>
<font><b/><sz val="16"/><color rgb="FF202224"/><name val="等线"/></font>
</fonts>
<fills count="5">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF0395FF"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFE8F4FE"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFF7F9FA"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="2">
<border><left/><right/><top/><bottom/><diagonal/></border>
<border>
<left style="thin"><color rgb="FFD9DCE0"/></left>
<right style="thin"><color rgb="FFD9DCE0"/></right>
<top style="thin"><color rgb="FFD9DCE0"/></top>
<bottom style="thin"><color rgb="FFD9DCE0"/></bottom>
<diagonal/>
</border>
</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="8">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="$_fTitle" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="$_fHeader" fillId="$_fillBrand" borderId="$_bdBox" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="$_fNormal" fillId="$_fillNone" borderId="$_bdBox" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="$_fNormal" fillId="$_fillAlt" borderId="$_bdBox" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="$_fBold" fillId="$_fillGroup" borderId="$_bdBox" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="$_fNormal" fillId="$_fillNone" borderId="$_bdBox" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="常规" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''';
