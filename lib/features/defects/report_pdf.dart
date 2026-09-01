import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models.dart';
import '../../data/weekly_report.dart';
import 'report_content.dart';

/// 现场工作汇报 → PDF 生成器（真 PDF：文本可选可搜，照片内嵌）。
///
/// 与 HTML / Word 共用 `report_content.dart` 的章节顺序、空板块剔除规则与配色，
/// 三份产物内容一致，只是承载格式不同。
///
/// 中文处理：`package:pdf` 自带字体无中文字形，必须显式嵌入一份 TrueType。
/// 这里用 Noto Sans SC（思源黑体，OFL），由 `tools/build_report_font.py` 生成，
/// 落 `assets/fonts/NotoSansSC-Regular.ttf`。`package:pdf` 会按实际用到的字符
/// 做子集化，所以成品 PDF 只增几百 KB，不会把 7MB 字体整个塞进去。
///
/// [photoBytes] 为「周报照片 assets 路径 → 原始字节」；缺失时渲染占位块。
/// [font] 可外部传入复用（字体解析有开销，建议缓存，见 `reportFontProvider`）。
Future<Uint8List> buildWeeklyReportPdf(
  WeeklyReport report, {
  required String reporter,
  required String generatedAt,
  Map<String, Uint8List> photoBytes = const {},
  pw.Font? font,
  AssetBundle? bundle,
}) async {
  final f = font ?? await loadReportFont(bundle);
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: f, bold: f, italic: f, boldItalic: f),
    title: '${report.title} - ${report.project}',
    author: reporter,
    creator: '蓝图落地 APP',
  );

  final blocks = buildReportBlocks(report);
  final stats = buildReportStats(report);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(_marginX, 24, _marginX, 26),
      footer: (ctx) => _pageFooter(ctx, generatedAt),
      build: (ctx) => <pw.Widget>[
        _cover(report, reporter, generatedAt),
        pw.SizedBox(height: 10),
        _overview(stats),
        for (var i = 0; i < blocks.length; i++)
          ..._chapter(cnNumber(i), blocks[i], photoBytes),
      ],
    ),
  );

  return doc.save();
}

/// 报告用中文字体资源（A4 版式下正文字号，需完整 CJK 覆盖）。
const String kReportFontAsset = 'assets/fonts/NotoSansSC-Regular.ttf';

/// 载入报告用中文字体。
///
/// 字体约 7MB，解析有开销，调用方应缓存复用（见 `reportFontProvider`）。
Future<pw.Font> loadReportFont([AssetBundle? bundle]) async {
  final data = await (bundle ?? rootBundle).load(kReportFontAsset);
  return pw.Font.ttf(data);
}

/// PDF 导出用中文字体 Provider：按需加载并缓存，避免每次导出重复解析字体。
final reportFontProvider = FutureProvider<pw.Font>((ref) => loadReportFont());

// ==================== 版式常量（pt，A4 = 595.28 × 841.89）====================

/// 左右页边距。
const double _marginX = 28;

/// 正文可用宽度。
const double _contentW = 595.28 - _marginX * 2;

/// 照片墙列数 / 列间距 / 单元格宽度 / 单元格高度。
const int _photoCols = 3;
const double _photoGap = 6;
const double _photoW = (_contentW - _photoGap * (_photoCols - 1)) / _photoCols;
const double _photoH = 100;

/// 严重程度分布条的单元宽度。
const double _barW = (_contentW - 8 * 3) / 4;

// ==================== 组件 ====================

PdfColor _c(String hex) => PdfColor.fromInt(hexToArgb(hex));

final PdfColor _brand = _c(kBrandHex);
final PdfColor _fg = _c(kFgHex);
final PdfColor _fg2 = _c(kFg2Hex);
final PdfColor _muted = _c(kMutedHex);
final PdfColor _line = _c(kLineHex);
final PdfColor _bg = _c(kBgHex);

pw.TextStyle _ts({
  double size = 8,
  PdfColor? color,
  bool bold = false,
  double? height,
}) =>
    pw.TextStyle(
      fontSize: size,
      color: color ?? _fg,
      height: height,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

pw.Widget _cover(
    WeeklyReport report, String reporter, String generatedAt) {
  final meta = <(String, String)>[
    if (report.period.isNotEmpty) ('汇报周期', report.period),
    if (report.org.isNotEmpty) ('编制单位', report.org),
    ('报告人', reporter),
    ('生成时间', generatedAt),
  ];
  return pw.Container(
    decoration: pw.BoxDecoration(
      color: _brand,
      borderRadius:
          const pw.BorderRadius.vertical(bottom: pw.Radius.circular(8)),
    ),
    padding: const pw.EdgeInsets.fromLTRB(20, 18, 20, 16),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(report.title,
            style: _ts(size: 19, color: PdfColors.white, bold: true)),
        pw.SizedBox(height: 4),
        pw.Text(report.project,
            style: _ts(size: 9.5, color: const PdfColor.fromInt(0xD9FFFFFF))),
        pw.SizedBox(height: 14),
        pw.Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [for (final m in meta) _metaChip(m.$1, m.$2)],
        ),
      ],
    ),
  );
}

pw.Widget _metaChip(String k, String v) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: const PdfColor.fromInt(0x55FFFFFF), width: .6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(k, style: _ts(size: 7, color: const PdfColor.fromInt(0xB3FFFFFF))),
          pw.SizedBox(height: 1),
          pw.Text(v, style: _ts(size: 8.5, color: PdfColors.white)),
        ],
      ),
    );

pw.Widget _overview(ReportStats s) {
  final items = <(String, String, String)>[
    ('现场照片', '${s.photos}', kBrandHex),
    ('进度楼栋', '${s.buildings}', kBrandHex),
    ('待协调问题', '${s.issues}', '#FF9500'),
    ('现场问题', '${s.defects}', '#FF3B30'),
    ('未闭环', '${s.open}', '#FF9500'),
    ('已闭环', '${s.done}', '#34C759'),
  ];
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    decoration: pw.BoxDecoration(
      color: _bg,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    child: pw.Row(
      children: [
        for (final e in items)
          pw.Expanded(
            child: pw.Column(children: [
              pw.Text(e.$2, style: _ts(size: 17, color: _c(e.$3), bold: true)),
              pw.SizedBox(height: 2),
              pw.Text(e.$1, style: _ts(size: 7.5, color: _muted)),
            ]),
          ),
      ],
    ),
  );
}

List<pw.Widget> _chapter(
    String no, ReportBlock block, Map<String, Uint8List> photoBytes) {
  final head = pw.Container(
    margin: const pw.EdgeInsets.only(top: 14, bottom: 7),
    padding: const pw.EdgeInsets.only(left: 7),
    decoration: pw.BoxDecoration(
      border: pw.Border(left: pw.BorderSide(color: _brand, width: 3)),
    ),
    child: pw.Text('$no、${cleanBlockTitle(block.title)}',
        style: _ts(size: 12.5, color: _brand, bold: true)),
  );

  final body = switch (block) {
    PhotosBlock() => _photos(block.groups, photoBytes),
    ProgressBlock() => _progress(block.rows),
    LedgerBlock() => _ledger(block.ledger),
    NoteBlock() => _note(block.note),
    IssuesBlock() => _issues(block.items),
    DefectsBlock() => _defects(block.defects, photoBytes),
  };

  return [head, ...body];
}

// ---------------- 一、现场施工进度（照片墙）----------------

List<pw.Widget> _photos(
    List<WeeklyPhotoGroup> groups, Map<String, Uint8List> photoBytes) {
  final out = <pw.Widget>[];
  for (final g in groups) {
    final rows = <pw.TableRow>[];
    for (var i = 0; i < g.photos.length; i += _photoCols) {
      rows.add(pw.TableRow(
        children: [
          for (var c = 0; c < _photoCols; c++)
            _photoCell(
              i + c < g.photos.length ? g.photos[i + c].file : null,
              photoBytes,
            ),
        ],
      ));
    }
    // 整组放进一个 TableRow：package:pdf 不会把行拆到两页，避免照片组断裂。
    out.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Table(
        // 单列 + 固定宽度：既撑满版心，又让 package:pdf 把整行当作不可拆单元。
        columnWidths: const {0: pw.FixedColumnWidth(_contentW)},
        children: [
          pw.TableRow(children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _groupCaption(g),
                if (rows.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6),
                    child: pw.Table(
                      columnWidths: {
                        for (var i = 0; i < _photoCols; i++)
                          i: const pw.FlexColumnWidth(1),
                      },
                      children: rows,
                    ),
                  ),
              ],
            ),
          ]),
        ],
      ),
    ));
  }
  return out;
}

pw.Widget _groupCaption(WeeklyPhotoGroup g) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _bg,
        border: pw.Border(left: pw.BorderSide(color: _brand, width: 2.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
              child: pw.Text(g.caption, style: _ts(size: 9.5, bold: true))),
          if (g.date.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 8),
              child: pw.Text(g.date, style: _ts(size: 8, color: _fg2)),
            ),
        ],
      ),
    );

pw.Widget _photoCell(String? file, Map<String, Uint8List> photoBytes) {
  final bytes = file == null ? null : photoBytes[file];
  if (bytes == null) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(right: _photoGap),
      child: pw.Container(
        width: _photoW,
        height: _photoH,
        color: _bg,
        alignment: pw.Alignment.center,
        child: pw.Text(
          file == null ? '' : '照片未加载',
          style: _ts(size: 7.5, color: _muted),
        ),
      ),
    );
  }
  return pw.Padding(
    padding: const pw.EdgeInsets.only(right: _photoGap),
    child: pw.Container(
      width: _photoW,
      height: _photoH,
      decoration: const pw.BoxDecoration(
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 4,
        verticalRadius: 4,
        child: pw.Image(pw.MemoryImage(bytes),
            width: _photoW, height: _photoH, fit: pw.BoxFit.cover),
      ),
    ),
  );
}

// ---------------- 表格类板块 ----------------

pw.TableBorder _gridBorder() => pw.TableBorder.symmetric(
      inside: pw.BorderSide(color: _line, width: .5),
      outside: pw.BorderSide(color: _line, width: .5),
    );

pw.Widget _cell(String text,
        {double size = 8,
        PdfColor? color,
        bool bold = false,
        pw.Alignment? align}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Align(
        alignment: align ?? pw.Alignment.centerLeft,
        child: pw.Text(text, style: _ts(size: size, color: color, bold: bold)),
      ),
    );

pw.Widget _th(String text, {pw.Alignment? align}) => pw.Container(
      color: _bg,
      child: _cell(text,
          size: 8, color: _fg2, bold: true, align: align ?? pw.Alignment.centerLeft),
    );

List<pw.Widget> _progress(List<WeeklyProgressRow> rows) => [
      pw.Table(
        border: _gridBorder(),
        columnWidths: const {0: pw.FixedColumnWidth(72), 1: pw.FlexColumnWidth(1)},
        children: [
          pw.TableRow(children: [_th('楼栋'), _th('现场安装施工进度情况')]),
          for (final r in rows)
            pw.TableRow(children: [
              _cell(r.building, bold: true, size: 8.5),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (final seg in splitProgressDetail(r.detail))
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        child: pw.RichText(
                          text: pw.TextSpan(children: [
                            if (seg.tag.isNotEmpty)
                              pw.TextSpan(
                                text: '${seg.tag}：',
                                style: _ts(size: 8, color: _brand, bold: true),
                              ),
                            pw.TextSpan(text: seg.text, style: _ts(size: 8)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
        ],
      ),
    ];

List<pw.Widget> _ledger(WeeklyLedger l) => [
      pw.Table(
        border: _gridBorder(),
        columnWidths: {
          for (var i = 0; i < l.columns.length; i++)
            i: i == 0 ? const pw.FixedColumnWidth(64) : const pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(
              children: [for (final c in l.columns) _th(c)]),
          for (final row in l.filledRows)
            pw.TableRow(children: [
              for (var i = 0; i < l.columns.length; i++)
                _cell(i < row.length ? row[i] : ''),
            ]),
        ],
      ),
    ];

List<pw.Widget> _note(WeeklyNote n) => [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          color: _bg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Text(n.text, style: _ts(size: 8.5)),
      ),
    ];

List<pw.Widget> _issues(List<WeeklyIssue> items) => [
      pw.Table(
        border: _gridBorder(),
        columnWidths: const {
          0: pw.FixedColumnWidth(30),
          1: pw.FlexColumnWidth(2.4),
          2: pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(children: [
            _th('序号', align: pw.Alignment.center),
            _th('事由'),
            _th('备注'),
          ]),
          for (final e in items)
            pw.TableRow(children: [
              _cell(e.no, color: _muted, align: pw.Alignment.center),
              _cell(e.subject),
              _cell(e.remark, color: _fg2),
            ]),
        ],
      ),
    ];

// ---------------- 四、现场问题清单及闭环情况 ----------------

List<pw.Widget> _defects(
    List<Defect> defects, Map<String, Uint8List> photoBytes) {
  final list = sortDefects(defects);
  final out = <pw.Widget>[];

  // 严重程度分布
  out.add(pw.Row(
    children: [
      for (final s in kSeverityOrder)
        pw.Container(
          width: _barW,
          margin: const pw.EdgeInsets.only(right: 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(s.label, style: _ts(size: 7.5, color: _fg2)),
                  pw.Text('${list.where((d) => d.severity == s).length}',
                      style: _ts(
                          size: 11,
                          color: _c(severityHex(s)),
                          bold: true)),
                ],
              ),
              pw.SizedBox(height: 3),
              _bar(list.where((d) => d.severity == s).length, list.length,
                  severityHex(s)),
            ],
          ),
        ),
    ],
  ));
  out.add(pw.SizedBox(height: 12));

  // 按严重程度分组的缺陷卡
  var idx = 0;
  for (final s in kSeverityOrder) {
    final group = list.where((d) => d.severity == s).toList();
    if (group.isEmpty) continue;
    out.add(pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 7),
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _c(severityHex(s)),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(s.label,
              style: _ts(size: 10, color: _c(severityFg(s)), bold: true)),
          pw.Text('${s.action} · ${group.length} 项',
              style: _ts(size: 8, color: _c(severityFg(s)))),
        ],
      ),
    ));
    for (final d in group) {
      idx++;
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Table(
          // 缺陷卡整卡放进一行，避免卡片跨页断裂
          columnWidths: const {0: pw.FixedColumnWidth(_contentW)},
          children: [
            pw.TableRow(children: [_defectCard(idx, d, photoBytes)]),
          ],
        ),
      ));
    }
  }

  // 状态汇总表
  out.add(pw.SizedBox(height: 6));
  out.add(pw.Table(
    border: _gridBorder(),
    columnWidths: const {
      0: pw.FixedColumnWidth(22),
      1: pw.FlexColumnWidth(2.4),
      2: pw.FixedColumnWidth(44),
      3: pw.FixedColumnWidth(40),
      4: pw.FlexColumnWidth(1.6),
      5: pw.FixedColumnWidth(66),
    },
    children: [
      pw.TableRow(children: [
        _th('序号', align: pw.Alignment.center),
        _th('部位 / 缺陷'),
        _th('严重程度'),
        _th('状态'),
        _th('责任人'),
        _th('发现时间'),
      ]),
      for (final st in kStatusOrder)
        for (final d in list.where((e) => e.status == st))
          pw.TableRow(children: [
            _cell('${list.indexOf(d) + 1}',
                color: _muted, align: pw.Alignment.center, size: 7.5),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(d.part, style: _ts(size: 8, bold: true)),
                  pw.SizedBox(height: 1),
                  pw.Text('${d.anchor} · ${d.floor}',
                      style: _ts(size: 7, color: _muted)),
                ],
              ),
            ),
            _pill(d.severity.label, severityHex(d.severity), severityFg(d.severity)),
            _pill(d.status.label, statusBg(d.status), statusFg(d.status)),
            _cell(d.resp, size: 7.5),
            _cell(d.ts, size: 7, color: _fg2),
          ]),
    ],
  ));

  return out;
}

pw.Widget _bar(int n, int total, String color) {
  final pct = total == 0 ? 0.0 : n / total;
  return pw.Row(children: [
    pw.Container(
        width: _barW * pct, height: 5, color: _c(color)),
    pw.Container(width: _barW * (1 - pct), height: 5, color: _line),
  ]);
}

pw.Widget _pill(String text, String bg, String fg) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: pw.BoxDecoration(
          color: _c(bg),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Text(text, style: _ts(size: 7, color: _c(fg))),
      ),
    );

pw.Widget _defectCard(
        int idx, Defect d, Map<String, Uint8List> photoBytes) =>
    pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: .6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // 标题行：序号 + 部位 + 严重程度 + 状态
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF4F6F7),
              borderRadius: pw.BorderRadius.vertical(
                  top: pw.Radius.circular(5)),
            ),
            child: pw.Row(children: [
              pw.Container(
                width: 15,
                height: 15,
                alignment: pw.Alignment.center,
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF202224),
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text('$idx',
                    style: _ts(size: 7.5, color: PdfColors.white)),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                  child: pw.Text(d.part,
                      style: _ts(size: 9, bold: true))),
              _pill('${d.severity.label} · ${d.severity.action}',
                  severityHex(d.severity), severityFg(d.severity)),
              _pill(d.status.label, statusBg(d.status), statusFg(d.status)),
            ]),
          ),
          // 字段表（两列并排）
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: _defectFields(d),
          ),
          // 现场照片（拍照记录写入的相对路径 → photoBytes）
          if (d.photoPath != null)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: _defectPhoto(d, photoBytes),
            ),
          // 问题描述
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                color: _bg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(text: '问题描述：', style: _ts(size: 7.5, color: _muted)),
                  pw.TextSpan(text: d.note, style: _ts(size: 8)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );

/// 缺陷现场照片（缺失字节时渲染占位，不阻断导出）。
pw.Widget _defectPhoto(Defect d, Map<String, Uint8List> photoBytes) {
  final bytes = photoBytes[d.photoPath!];
  if (bytes == null) {
    return pw.Container(
      width: _contentW * 0.55,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _bg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text('现场照片未加载', style: _ts(size: 7.5, color: _muted)),
    );
  }
  return pw.ClipRRect(
    horizontalRadius: 4,
    verticalRadius: 4,
    child: pw.Image(
      pw.MemoryImage(bytes),
      width: _contentW * 0.55,
      height: 100,
      fit: pw.BoxFit.cover,
    ),
  );
}

pw.Widget _defectFields(Defect d) {
  final fields = defectFields(d);
  final rows = <pw.TableRow>[];
  for (var i = 0; i < fields.length; i += 2) {
    final a = fields[i];
    final b = i + 1 < fields.length ? fields[i + 1] : null;
    rows.add(pw.TableRow(children: [
      _fieldCell(a.$1, a.$2),
      b == null
          ? pw.SizedBox()
          : _fieldCell(b.$1, b.$2),
    ]));
  }
  return pw.Table(
    columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1)},
    children: rows,
  );
}

pw.Widget _fieldCell(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3, right: 8),
      child: pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(text: '$k：', style: _ts(size: 7.5, color: _muted)),
          pw.TextSpan(text: v, style: _ts(size: 7.5)),
        ]),
      ),
    );

// ---------------- 页脚 ----------------

pw.Widget _pageFooter(pw.Context ctx, String generatedAt) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration:
          pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: .5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              '本报告由「蓝图落地」APP 自动生成 · 现场照片与进度数据同步自设计院周报 · 生成时间 $generatedAt',
              style: _ts(size: 6.5, color: _muted),
            ),
          ),
          pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
              style: _ts(size: 6.5, color: _muted)),
        ],
      ),
    );
