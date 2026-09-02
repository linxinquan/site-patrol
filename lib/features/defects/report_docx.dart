import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import '../../data/models.dart';
import '../../data/weekly_report.dart';
import 'report_content.dart';

/// 现场工作汇报 → Word（.docx，Office Open XML）生成器。
///
/// 纯 Dart 手写 OOXML + `package:archive` 打包，**不依赖任何插件 / 原生能力**，
/// 因此在 Web、桌面、移动端都能生成同一份文件。
///
/// 生成物特点：
/// - 照片以 `word/media/*.jpg` 内嵌（不是外链），发给任何人打开都有图；
/// - 使用标准段落样式（Heading1）+ 真实表格，Word 里可直接改字、加行、调格式；
/// - A4 纵向、2cm 页边距，与 PDF / HTML 版式同一套配色与章节顺序。
///
/// [photoBytes] 为「周报照片 assets 路径 → 原始字节」；缺失的照片渲染占位文字，
/// 不阻断导出。
Uint8List buildWeeklyReportDocx(
  WeeklyReport report, {
  required String reporter,
  required String generatedAt,
  Map<String, Uint8List> photoBytes = const {},
}) {
  final doc = _DocxDoc(photoBytes: photoBytes);
  final stats = buildReportStats(report);
  final blocks = buildReportBlocks(report);

  doc.cover(
    title: report.title,
    project: report.project,
    period: report.period,
    org: report.org,
    reporter: reporter,
    generatedAt: generatedAt,
  );
  doc.overview(stats);

  for (var i = 0; i < blocks.length; i++) {
    doc.chapter(cnNumber(i), blocks[i]);
  }

  doc.footer(generatedAt);
  return doc.build();
}

// ==================== 版式常量（twips，1cm = 567twips）====================

/// A4 纵向正文可用宽度（210mm - 2×20mm 页边距）。
const int _contentW = 9638;

/// twips → EMU（DrawingML 尺寸单位）。
int _emu(int twips) => twips * 635;

/// 照片墙列数。
const int _photoCols = 3;

/// 单张照片目标宽度（twips）。
const int _photoW = 3000;

/// 单张照片高度上限（twips），避免竖图把整页撑爆。
const int _photoMaxH = 3000;

// ==================== 文档组装 ====================

class _DocxDoc {
  _DocxDoc({required this.photoBytes});

  final Map<String, Uint8List> photoBytes;
  final StringBuffer _body = StringBuffer();

  /// 已登记的图片（顺序即 rId 顺序）。
  final List<_Media> _media = [];

  Uint8List build() {
    final archive = Archive();
    void add(String name, String text) =>
        archive.addFile(ArchiveFile.bytes(name, utf8.encode(text)));

    add('[Content_Types].xml', _contentTypes());
    add('_rels/.rels', _rootRels());
    add('word/document.xml', _document(_body.toString()));
    add('word/styles.xml', _styles());
    // 关系表必须在正文写完后生成——图片条目是边排版边登记的。
    add('word/_rels/document.xml.rels', _docRels(_media));
    for (var i = 0; i < _media.length; i++) {
      final m = _media[i];
      archive.addFile(ArchiveFile.bytes('word/media/${m.name}', m.bytes));
    }

    final zipped = ZipEncoder().encode(archive);
    return zipped is Uint8List ? zipped : Uint8List.fromList(zipped);
  }

  // ---------------- 封面 ----------------

  void cover({
    required String title,
    required String project,
    required String period,
    required String org,
    required String reporter,
    required String generatedAt,
  }) {
    _body.write(_p(_r(title, bold: true, size: 52, color: '0395FF'),
        align: 'center', after: 60));
    _body.write(_p(_r(project, size: 24, color: '60656B'),
        align: 'center', after: 280));

    final rows = <List<_Cell>>[
      if (period.isNotEmpty) _metaRow('汇报周期', period),
      if (org.isNotEmpty) _metaRow('编制单位', org),
      _metaRow('报告人', reporter),
      _metaRow('生成时间', generatedAt),
    ];
    _body.write(_table([2200, _contentW - 2200], rows));
    _body.write(_spacer(200));
  }

  List<_Cell> _metaRow(String k, String v) => [
        _Cell(_p(_r(k, color: '919499', size: 20), after: 0),
            shade: 'F4F6F7', width: 2200),
        _Cell(_p(_r(v, bold: true, size: 20), after: 0)),
      ];

  // ---------------- 概览数字条 ----------------

  void overview(ReportStats s) {
    final items = <(String, String, String)>[
      ('现场照片', '${s.photos}', '0395FF'),
      ('进度楼栋', '${s.buildings}', '0395FF'),
      ('待协调问题', '${s.issues}', 'FF9500'),
      ('巡场问题', '${s.defects}', 'FF3B30'),
      ('重要紧急', '${s.urgent}', 'D93025'),
      ('未闭环', '${s.open}', 'FF9500'),
      ('已闭环', '${s.done}', '34C759'),
    ];
    final col = (_contentW / items.length).round();
    _body.write(_table(
      [for (var i = 0; i < items.length; i++) col],
      [
        [
          for (final e in items)
            _Cell(_p(_r(e.$2, bold: true, size: 40, color: e.$3),
                    align: 'center', after: 0) +
                _p(_r(e.$1, size: 18, color: '919499'), align: 'center', after: 0),
                shade: 'F4F6F7', vAlign: 'center'),
        ],
      ],
    ));
    _body.write(_spacer(120));
  }

  // ---------------- 章节 ----------------

  void chapter(String no, ReportBlock block) {
    _body.write(_p(_r('$no、${cleanBlockTitle(block.title)}'),
        style: 'Heading1'));
    switch (block) {
      case PhotosBlock():
        _photos(block.groups);
      case ProgressBlock():
        _progress(block.rows);
      case LedgerBlock():
        _ledger(block.ledger);
      case NoteBlock():
        _note(block.note);
      case IssuesBlock():
        _issues(block.items);
      case DefectsBlock():
        _defects(block.defects);
    }
  }

  void _photos(List<WeeklyPhotoGroup> groups) {
    final col = (_contentW / _photoCols).floor();
    final cols = [
      for (var i = 0; i < _photoCols; i++)
        i == _photoCols - 1 ? _contentW - col * (_photoCols - 1) : col,
    ];

    for (final g in groups) {
      _body.write(_table([_contentW], [
        [
          _Cell(
            _p(_r(g.caption, bold: true, size: 22) +
                (g.date.isNotEmpty
                    ? _r('    ${g.date}', size: 18, color: '60656B')
                    : ''),
                after: 0),
            shade: 'F4F6F7',
          ),
        ],
      ]));

      final rows = <List<_Cell>>[];
      for (var i = 0; i < g.photos.length; i += _photoCols) {
        final row = <_Cell>[];
        for (var c = 0; c < _photoCols; c++) {
          final idx = i + c;
          row.add(idx < g.photos.length
              ? _Cell(_photoCell(g.photos[idx].file, g.caption), vAlign: 'center')
              : _Cell(_p('', after: 0)));
        }
        rows.add(row);
      }
      _body.write(_table(cols, rows));
      _body.write(_spacer(160));
    }
  }

  String _photoCell(String file, String alt) {
    final bytes = photoBytes[file];
    if (bytes == null) {
      return _p(_r('照片未加载', size: 18, color: 'B5B9BF'), align: 'center', after: 0);
    }
    final size = _photoSize(bytes);
    final rid = _registerMedia(file, bytes);
    return _imageParagraph(rid, size.$1, size.$2, alt);
  }

  /// 按原始宽高比算出展示尺寸（EMU）。
  (int, int) _photoSize(Uint8List bytes) {
    var w = 4;
    var h = 3;
    final decoded = img.decodeImage(bytes);
    if (decoded != null && decoded.width > 0 && decoded.height > 0) {
      w = decoded.width;
      h = decoded.height;
    }
    var tw = _photoW;
    var th = (_photoW * h / w).round();
    if (th > _photoMaxH) {
      th = _photoMaxH;
      tw = (_photoMaxH * w / h).round();
    }
    return (_emu(tw), _emu(th));
  }

  String _imageParagraph(String rid, int cx, int cy, String alt) {
    final id = _media.length;
    return '<w:p><w:pPr><w:jc w:val="center"/>'
        '<w:spacing w:before="60" w:after="60"/></w:pPr>'
        '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="$id" name="${_x(alt)}"/>'
        '<wp:cNvGraphicFramePr/>'
        '<a:graphic>'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic>'
        '<pic:nvPicPr><pic:cNvPr id="$id" name="${_x(alt)}"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr>'
        '<a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '</pic:spPr>'
        '</pic:pic>'
        '</a:graphicData></a:graphic>'
        '</wp:inline></w:drawing></w:r></w:p>';
  }

  void _progress(List<WeeklyProgressRow> rows) {
    _body.write(_table([1900, _contentW - 1900], [
      [
        _Cell(_p(_r('楼栋', bold: true, color: '60656B'), after: 0), shade: 'F4F6F7'),
        _Cell(_p(_r('现场安装施工进度情况', bold: true, color: '60656B'), after: 0),
            shade: 'F4F6F7'),
      ],
      for (final r in rows)
        [
          _Cell(_p(_r(r.building, bold: true), after: 0), width: 1900),
          _Cell([
            for (final seg in splitProgressDetail(r.detail))
              _p(_runs([
                    if (seg.tag.isNotEmpty)
                      _r('${seg.tag}：', bold: true, color: '0273CC'),
                    _r(seg.text),
                  ]),
                  after: 40),
          ].join()),
        ],
    ]));
    _body.write(_spacer(120));
  }

  void _ledger(WeeklyLedger l) {
    final cols = _evenCols(l.columns.length);
    _body.write(_table(cols, [
      [
        for (final c in l.columns)
          _Cell(_p(_r(c, bold: true, color: '60656B'), after: 0), shade: 'F4F6F7'),
      ],
      for (final row in l.filledRows)
        [
          for (var i = 0; i < l.columns.length; i++)
            _Cell(_p(_r(i < row.length ? row[i] : ''), after: 0)),
        ],
    ]));
    _body.write(_spacer(120));
  }

  void _note(WeeklyNote n) {
    _body.write(_table([_contentW], [
      [_Cell(_p(_r(n.text), after: 0), shade: 'F4F6F7')],
    ]));
    _body.write(_spacer(120));
  }

  void _issues(List<WeeklyIssue> items) {
    _body.write(_table([1100, 5000, _contentW - 6100], [
      [
        _Cell(_p(_r('序号', bold: true, color: '60656B'), align: 'center', after: 0),
            shade: 'F4F6F7'),
        _Cell(_p(_r('事由', bold: true, color: '60656B'), after: 0), shade: 'F4F6F7'),
        _Cell(_p(_r('备注', bold: true, color: '60656B'), after: 0), shade: 'F4F6F7'),
      ],
      for (final e in items)
        [
          _Cell(_p(_r(e.no, color: '919499'), align: 'center', after: 0)),
          _Cell(_p(_r(e.subject), after: 0)),
          _Cell(_p(_r(e.remark, color: '60656B'), after: 0)),
        ],
    ]));
    _body.write(_spacer(120));
  }

  void _defects(List<Defect> defects) {
    final list = sortDefects(defects);

    // 严重程度分布：4 列，每列「名称 + 数量」+ 一条比例条。
    final col = (_contentW / 4).floor();
    _body.write(_table([
      col, col, col, _contentW - col * 3,
    ], [
      [
        for (final s in kSeverityOrder)
          _Cell(
            _p(_r(s.label, size: 20, color: '60656B'), after: 0) +
                _p(_r('${list.where((d) => d.severity == s).length}',
                        bold: true, size: 32, color: _noHash(severityHex(s))),
                    after: 40) +
                _bar(list.where((d) => d.severity == s).length, list.length,
                    severityHex(s)),
            shade: 'FFFFFF',
          ),
      ],
    ]));
    _body.write(_spacer(160));

    // 分组明细：优先按楼栋（巡场销项表版式），无栋号信息时回退严重程度
    var idx = 0;
    for (final g in groupDefects(defects)) {
      final bg = g.colorHex ?? kBrandHex;
      final fg = g.colorHex == null
          ? '#FFFFFF'
          : (g.colorHex!.toUpperCase() == '#F5C518' ? '#5B4A00' : '#FFFFFF');
      _body.write(_table([_contentW], [
        [
          _Cell(
            _p(_r(g.title, bold: true, color: _noHash(fg)) +
                    _r('    ${g.subtitle ?? '${g.items.length} 项'}',
                        color: _noHash(fg)),
                after: 0),
            shade: _noHash(bg),
          ),
        ],
      ]));
      for (final d in g.items) {
        idx++;
        _body.write(_defectCard(idx, d));
      }
      _body.write(_spacer(120));
    }

    // 销项汇总表（对齐巡场报告单：重要等级 / 状态 / 是否闭合）
    _body.write(
        _table([700, 2600, 1300, 1100, 1100, 800, 2000, _contentW - 9600], [
      [
        for (final h in const [
          '序号',
          '部位 / 缺陷',
          '重要等级',
          '严重程度',
          '状态',
          '闭合',
          '责任人',
          '发现时间'
        ])
          _Cell(_p(_r(h, bold: true, color: '60656B'), after: 0), shade: 'F4F6F7'),
      ],
      for (final st in kStatusOrder)
        for (final d in list.where((e) => e.status == st))
          [
            _Cell(_p(_r('${list.indexOf(d) + 1}', color: '919499'), after: 0)),
            _Cell(_p(_r(d.part, bold: true), after: 0) +
                _p(_r('${d.anchor} · ${d.floor}', size: 18, color: '919499'), after: 0)),
            _Cell(_p(_r(d.effectiveImportance.label,
                bold: true,
                color: _noHash(importanceFg(d.effectiveImportance)),
                shade: _noHash(importanceBg(d.effectiveImportance))), after: 0)),
            _Cell(_p(_r(d.severity.label,
                bold: true,
                color: _noHash(severityFg(d.severity)),
                shade: _noHash(severityHex(d.severity))), after: 0)),
            _Cell(_p(_r(d.status.label,
                color: _noHash(statusFg(d.status)),
                shade: _noHash(statusBg(d.status))), after: 0)),
            _Cell(_p(_r(d.closed ? '是' : '否',
                bold: true,
                color: d.closed ? '1E9E4E' : 'E0342B'), after: 0)),
            _Cell(_p(_r(d.resp), after: 0)),
            _Cell(_p(_r(d.ts, size: 18), after: 0)),
          ],
    ]));
  }

  String _bar(int n, int total, String color) {
    final pct = total == 0 ? 0 : (1000 * n / total).round();
    final fill = pct.clamp(1, 999);
    return _table([fill, 1000 - fill], [
      [
        _Cell(_p('', after: 0), shade: _noHash(color)),
        _Cell(_p('', after: 0), shade: 'E9EAEB'),
      ],
    ], height: 60, borders: false);
  }

  String _defectCard(int idx, Defect d) {
    final fields = defectFields(d);
    const kCol = 1400;
    final rows = <List<_Cell>>[];
    for (var i = 0; i < fields.length; i += 2) {
      final row = <_Cell>[];
      for (var c = 0; c < 2; c++) {
        final j = i + c;
        if (j >= fields.length) {
          if (c == 0) {
            row.add(_Cell(_p('', after: 0), gridSpan: 2));
          }
          continue;
        }
        row.add(_Cell(_p(_r('${fields[j].$1}：', color: '919499', size: 20), after: 0),
            shade: 'FFFFFF', width: kCol));
        row.add(_Cell(_p(_r(fields[j].$2, size: 20), after: 0), shade: 'FFFFFF'));
      }
      rows.add(row);
    }

    // 一、巡场意见：现场照片行（相对路径 → photoBytes；缺失时渲染占位文字）
    final photoRow = d.photoPath != null && d.photoPath!.isNotEmpty
        ? [
            [
              _Cell(_p(_r('现场照片', color: '919499', size: 20), after: 0),
                  shade: 'F4F6F7', width: 1400),
              _Cell(_photoCell(d.photoPath!, '${d.part} 现场照片'), shade: 'F4F6F7'),
            ],
          ]
        : <List<_Cell>>[];

    // 二、整改回复（有回复内容或回复照片时渲染）
    final replyRow = ((d.reply ?? '').trim().isEmpty &&
            (d.replyPhotoPath ?? '').isEmpty)
        ? <List<_Cell>>[]
        : <List<_Cell>>[
            [
              _Cell(
                  _p(
                      _r('整改回复：', color: '919499', size: 20) +
                          _r(d.reply ?? '', size: 20) +
                          ((d.replyBy ?? '').trim().isNotEmpty ||
                                  (d.replyTs ?? '').trim().isNotEmpty
                              ? _r(
                                  '    ${[
                                    if ((d.replyBy ?? '').trim().isNotEmpty) d.replyBy!,
                                    if ((d.replyTs ?? '').trim().isNotEmpty) d.replyTs!,
                                  ].join(' · ')}',
                                  size: 18,
                                  color: '919499')
                              : ''),
                      after: 0),
                  shade: 'F4F6F7'),
            ],
            if ((d.replyPhotoPath ?? '').isNotEmpty)
              [
                _Cell(_p(_r('整改后照片', color: '919499', size: 20), after: 0),
                    shade: 'F4F6F7', width: 1400),
                _Cell(_photoCell(d.replyPhotoPath!, '${d.part} 整改后照片'),
                    shade: 'F4F6F7'),
              ],
          ];

    // 三、闭合确认
    final closeRow = <List<_Cell>>[
      [
        _Cell(
            _p(
                _r('是否闭合：', color: '919499', size: 20) +
                    _r(d.closed ? '是' : '否',
                        bold: true,
                        color: d.closed ? '1E9E4E' : 'E0342B',
                        size: 20) +
                    ((d.completion ?? '').trim().isNotEmpty
                        ? _r('    完成状态：${d.completion!}',
                            size: 20, color: '60656B')
                        : ''),
                after: 0),
            shade: 'F4F6F7'),
      ],
      if ((d.closeNote ?? '').trim().isNotEmpty)
        [
          _Cell(_p(_r('未闭合说明：', color: '919499', size: 20) +
                  _r(d.closeNote!, size: 20),
              after: 0),
              shade: 'FFF6E8'),
        ],
    ];

    return _table([_contentW], [
      [
        _Cell(
          _p(_r('$idx  ', bold: true, color: '0395FF') +
                  _r(d.part, bold: true) +
                  _r('  ${d.effectiveImportance.label}',
                      bold: true,
                      color: _noHash(importanceFg(d.effectiveImportance)),
                      shade: _noHash(importanceBg(d.effectiveImportance))) +
                  _r('  ${d.severity.label} · ${d.severity.action}',
                      bold: true,
                      color: _noHash(severityFg(d.severity)),
                      shade: _noHash(severityHex(d.severity))) +
                  _r('  ${d.status.label}',
                      color: _noHash(statusFg(d.status)),
                      shade: _noHash(statusBg(d.status))),
              after: 0),
          shade: 'F4F6F7',
        ),
      ],
      [
        _Cell(_table([kCol, _contentW - kCol - 200, kCol, _contentW - kCol - 200], rows,
            borders: false)),
      ],
      ...photoRow,
      [
        _Cell(_p(_r('巡场意见：', color: '919499', size: 20) + _r(d.note, size: 20),
                after: 0),
            shade: 'F4F6F7'),
      ],
      // AI 整改建议（给施工单位）
      if ((d.suggestion ?? '').trim().isNotEmpty)
        [
          _Cell(_p(_r('AI整改建议：', color: '0273CC', size: 20) +
                  _r(d.suggestion!, size: 20),
              after: 0),
              shade: 'E8F4FE'),
        ],
      ...replyRow,
      ...closeRow,
    ]);
  }

  void footer(String generatedAt) {
    _body.write(_spacer(240));
    _body.write(_p(
      _r('本报告由「蓝图落地」APP 自动生成 · 现场照片与进度数据同步自设计院周报 · '
          '生成时间 $generatedAt',
          size: 18, color: '919499'),
      align: 'center',
    ));
  }

  // ---------------- 图片登记 ----------------

  String _registerMedia(String file, Uint8List bytes) {
    final name = file.contains('/') ? file.split('/').last : file;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
    final safe = 'image${_media.length + 1}.$ext';
    _media.add(_Media(safe, bytes));
    return 'rIdImg${_media.length}';
  }
}

class _Media {
  _Media(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

// ==================== OOXML 片段构造 ====================

/// 表格单元格。
class _Cell {
  _Cell(
    this.xml, {
    this.width,
    this.shade,
    this.vAlign = 'top',
    this.gridSpan,
  });

  /// 单元格内容（一个或多个 `<w:p>`）。
  final String xml;

  /// 列宽（twips）。
  final int? width;

  /// 底色（不含 `#`）。
  final String? shade;

  final String vAlign;

  /// 横向合并列数。
  final int? gridSpan;
}

/// 自动均分列宽（余数补到最后一列，保证表格总宽 = 正文宽）。
List<int> _evenCols(int n) {
  final col = (_contentW / n).floor();
  return [for (var i = 0; i < n; i++) i == n - 1 ? _contentW - col * (n - 1) : col];
}

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// `#RRGGBB` → `RRGGBB`（OOXML 里不带 `#`）。
String _noHash(String hex) => hex.replaceFirst('#', '');

String _r(
  String text, {
  bool bold = false,
  String? color,
  int? size,
  String? shade,
}) {
  if (text.isEmpty) return '';
  return '<w:r><w:rPr>'
      '<w:rFonts w:ascii="微软雅黑" w:hAnsi="微软雅黑" w:eastAsia="微软雅黑"/>'
      '${bold ? '<w:b/>' : ''}'
      '${color != null ? '<w:color w:val="$color"/>' : ''}'
      '${size != null ? '<w:sz w:val="$size"/><w:szCs w:val="$size"/>' : ''}'
      '${shade != null ? '<w:shd w:val="clear" w:color="auto" w:fill="$shade"/>' : ''}'
      '</w:rPr><w:t xml:space="preserve">${_x(text)}</w:t></w:r>';
}

/// 多个 run 拼成一个段落正文。
String _runs(List<String> runs) => runs.join();

String _p(
  String runs, {
  String align = 'left',
  int before = 0,
  int after = 60,
  String? shade,
  String? style,
}) =>
    '<w:p><w:pPr>'
    '${style != null ? '<w:pStyle w:val="$style"/>' : ''}'
    '<w:spacing w:before="$before" w:after="$after" w:line="288" w:lineRule="auto"/>'
    '<w:jc w:val="$align"/>'
    '${shade != null ? '<w:shd w:val="clear" w:color="auto" w:fill="$shade"/>' : ''}'
    '</w:pPr>$runs</w:p>';

/// 空段落（用于撑开间距 / 阻止相邻表格被 Word 自动合并）。
String _spacer(int after) =>
    '<w:p><w:pPr><w:spacing w:after="$after" w:line="240" w:lineRule="auto"/>'
    '</w:pPr><w:r><w:rPr><w:sz w:val="4"/></w:rPr></w:r></w:p>';

/// 表格。[rows] 中每行的单元格数应与 [cols] 一致（或用 gridSpan 合并）。
String _table(
  List<int> cols,
  List<List<_Cell>> rows, {
  int? height,
  bool borders = true,
}) {
  final grid = cols.map((w) => '<w:gridCol w:w="$w"/>').join();
  final borderTags = borders
      ? '<w:tblBorders>${_border('top')}${_border('left')}${_border('bottom')}'
          '${_border('right')}${_border('insideH')}${_border('insideV')}</w:tblBorders>'
      : '<w:tblBorders>'
          '<w:top w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
          '<w:left w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
          '<w:bottom w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
          '<w:right w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
          '<w:insideH w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
          '<w:insideV w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
          '</w:tblBorders>';

  final body = rows.map((row) {
    final cells = row.map((c) {
      final w = c.width ?? 0;
      return '<w:tc><w:tcPr>'
          '${w > 0 ? '<w:tcW w:w="$w" w:type="dxa"/>' : ''}'
          '${c.gridSpan != null ? '<w:gridSpan w:val="${c.gridSpan}"/>' : ''}'
          '<w:vAlign w:val="${c.vAlign}"/>'
          '${c.shade != null ? '<w:shd w:val="clear" w:color="auto" w:fill="${c.shade}"/>' : ''}'
          '</w:tcPr>${c.xml.isEmpty ? '<w:p/>' : c.xml}</w:tc>';
    }).join();
    return '<w:tr>'
        '${height != null ? '<w:trPr><w:trHeight w:val="$height" w:hRule="exact"/></w:trPr>' : ''}'
        '$cells</w:tr>';
  }).join();

  return '<w:tbl>'
      '<w:tblPr>'
      '<w:tblW w:w="$_contentW" w:type="dxa"/>'
      '<w:jc w:val="center"/>'
      '$borderTags'
      '<w:tblCellMar>'
      '<w:top w:w="70" w:type="dxa"/><w:left w:w="90" w:type="dxa"/>'
      '<w:bottom w:w="70" w:type="dxa"/><w:right w:w="90" w:type="dxa"/>'
      '</w:tblCellMar>'
      '</w:tblPr>'
      '<w:tblGrid>$grid</w:tblGrid>'
      '$body'
      '</w:tbl>';
}

String _border(String tag) =>
    '<w:$tag w:val="single" w:sz="4" w:space="0" w:color="E9EAEB"/>';

// ==================== 包内固定部件 ====================

/// 包内固定部件：`[Content_Types].xml`。
/// 图片扩展名统一声明 jpg / jpeg / png（其余走 `Default xml` 兜底）。
String _contentTypes() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="jpg" ContentType="image/jpeg"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '</Types>';

String _rootRels() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/>'
    '</Relationships>';

String _docRels(List<_Media> media) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rIdStyles" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
    'Target="styles.xml"/>'
    // 图片关系：rId 与正文里 `r:embed` 一一对应，缺一条 Word 就打不开那张图
    '${[
      for (var i = 0; i < media.length; i++)
        '<Relationship Id="rIdImg${i + 1}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
            'Target="media/${media[i].name}"/>'
    ].join()}'
    '</Relationships>';

String _document(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document '
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    '<w:body>'
    '$body'
    '<w:sectPr>'
    '<w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" '
    'w:header="720" w:footer="720" w:gutter="0"/>'
    '</w:sectPr>'
    '</w:body></w:document>';

/// 包内固定部件：`word/styles.xml`（正文默认字体 / Heading1 样式）。
String _styles() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:docDefaults>'
    '<w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="微软雅黑" w:hAnsi="微软雅黑" w:eastAsia="微软雅黑"/>'
    '<w:sz w:val="21"/><w:szCs w:val="21"/>'
    '<w:lang w:val="zh-CN" w:eastAsia="zh-CN"/>'
    '</w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr>'
    '<w:spacing w:after="60" w:line="288" w:lineRule="auto"/>'
    '</w:pPr></w:pPrDefault>'
    '</w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
    '<w:name w:val="Normal"/><w:qFormat/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1">'
    '<w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:qFormat/>'
    '<w:next w:val="Normal"/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="320" w:after="160"/>'
    '<w:outlineLvl w:val="0"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="30"/><w:szCs w:val="30"/>'
    '<w:color w:val="0395FF"/></w:rPr></w:style>'
    '</w:styles>';
