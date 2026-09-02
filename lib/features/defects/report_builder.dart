import '../../data/models.dart';
import '../../data/weekly_report.dart';
import 'report_content.dart';

/// 报告导出格式（导出方式弹层选项）。
enum ReportExportFormat {
  pdf('PDF', '标准打印版式，适合汇报存档'),
  docx('Word', '可继续编辑、批注流转'),
  html('HTML', '浏览器打开，可另存为 PDF');

  const ReportExportFormat(this.label, this.subtitle);

  final String label;
  final String subtitle;
}

/// 现场工作汇报（周报）生成器。
///
/// 版式参照设计院现场管理周报（深总院《项目东区现场工作汇报》）：
///   封面（项目 / 标题 / 周期 / 编制单位 / 报告人）
///   → 现场施工进度（照片墙：图 + 日期 + 施工内容）
///   → 机电施工进度（楼栋 × 进度描述）
///   → 图档台账 / 变更台账 / 设计交底 / 技术协调
///   → 待沟通协调问题
///   → 巡场清单及闭环情况（APP 现场数据）
///
/// 输出**自包含 HTML**（内联 CSS、照片 base64 内嵌），可直接打印为 PDF。
/// 所有分组、统计、排版均由本模块完成，用户导出后无需再手工整理。

/// 严重程度顺序（红→绿，与「停工上报→常规观察」处置优先级一致）。
const List<DefectSeverity> _severityOrder = [
  DefectSeverity.red,
  DefectSeverity.orange,
  DefectSeverity.yellow,
  DefectSeverity.green,
];

/// 状态顺序（未闭环优先）。
const List<DefectStatus> _statusOrder = [
  DefectStatus.draft,
  DefectStatus.doing,
  DefectStatus.done,
  DefectStatus.reject,
];

const List<String> _cnNum = [
  '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
  '十一', '十二', '十三', '十四', '十五',
];

String _cn(int i) => i < _cnNum.length ? _cnNum[i] : '${i + 1}';

/// 去掉 PPT 标题里的序号前缀（「3、图档台账情况」→「图档台账情况」），
/// 避免与章节序号重复。
String _cleanTitle(String t) =>
    t.replaceFirst(RegExp(r'^\d{1,2}\s*[、.．]\s*'), '').trim();

/// 生成自包含 HTML 周报。
///
/// [report] 周报素材（含照片、进度、台账、问题、缺陷）；
/// [reporter] 报告人；[generatedAt] 生成时间可读串；
/// [photoBase64] 照片 assets 路径 → base64 编码（缺失时显示占位块）。
String buildWeeklyReportHtml(
  WeeklyReport report, {
  required String reporter,
  required String generatedAt,
  Map<String, String> photoBase64 = const {},
}) {
  final buf = StringBuffer();
  final chapters = <({String title, String body})>[];

  // ===== 现场施工进度（照片墙）=====
  final groups = report.photoGroups;
  if (groups.isNotEmpty) {
    chapters.add(_photosSection('现场施工进度情况', groups, photoBase64));
  }

  // ===== 机电施工进度 =====
  if (report.progress.isNotEmpty) {
    chapters.add(_progressSection('现场（机电）施工进度情况', report.progress));
  }

  // ===== 台账类 + 纯文字说明（按原 PPT 页码排序，保持周报原始顺序）=====
  // 无实质内容的板块直接跳过：APP 没有台账/交底功能支撑，不渲染「本周无」占位。
  final misc = <({String title, String body, int page})>[
    for (final l in report.ledgers)
      if (!l.isEmpty)
        (title: l.title, body: _ledgerSection(l).body, page: l.page),
    for (final n in report.notes)
      if (n.text.trim().isNotEmpty && n.text.trim() != '本周无')
        (title: n.title, body: _noteSection(n).body, page: n.page),
  ]..sort((a, b) => a.page - b.page);
  for (final m in misc) {
    chapters.add((title: m.title, body: m.body));
  }

  // ===== 待沟通协调问题 =====
  if (report.filledIssues.isNotEmpty) {
    chapters.add(_issuesSection('待沟通协调问题', report.filledIssues));
  }

  // ===== 巡场清单及闭环（APP 现场数据）=====
  final defects = report.defects;
  if (defects.isNotEmpty) {
    chapters.add(_defectsSection(defects, photoBase64));
  }

  buf.writeln('<!DOCTYPE html>');
  buf.writeln('<html lang="zh-CN">');
  buf.writeln('<head>');
  buf.writeln('<meta charset="utf-8">');
  buf.writeln('<meta name="viewport" content="width=device-width, initial-scale=1">');
  buf.writeln('<title>${_esc(report.title)} - ${_esc(report.project)}</title>');
  buf.writeln('<style>');
  buf.writeln(_css());
  buf.writeln('</style>');
  buf.writeln('</head>');
  buf.writeln('<body>');

  // ===== 封面 =====
  buf.writeln('<header class="cover">');
  buf.writeln('<div class="cover-main">');
  buf.writeln('<h1>${_esc(report.title)}</h1>');
  buf.writeln('<div class="cover-sub">${_esc(report.project)}</div>');
  buf.writeln('</div>');
  buf.writeln('<div class="cover-meta">');
  if (report.period.isNotEmpty) {
    buf.writeln('<div><span>汇报周期</span><b>${_esc(report.period)}</b></div>');
  }
  if (report.org.isNotEmpty) {
    buf.writeln('<div><span>编制单位</span><b>${_esc(report.org)}</b></div>');
  }
  buf.writeln('<div><span>报告人</span><b>${_esc(reporter)}</b></div>');
  buf.writeln('<div><span>生成时间</span><b>${_esc(generatedAt)}</b></div>');
  buf.writeln('</div>');
  buf.writeln('</header>');

  // ===== 概览数字条 =====
  final openDefects = defects
      .where((d) =>
          d.status == DefectStatus.draft || d.status == DefectStatus.doing)
      .length;
  final doneCount =
      defects.where((d) => d.status == DefectStatus.done).length;
  // 巡场报告单「重要等级」维度：重要紧急条目数（最需优先处置）。
  final urgentCount = defects
      .where((d) => d.effectiveImportance == DefectImportance.urgentImportant)
      .length;
  buf.writeln('<section class="overview">');
  buf.writeln(_statCard('现场照片', '${report.photos.length}', '#0284E8', '#E8F4FE'));
  buf.writeln(_statCard('进度楼栋', '${report.progress.length}', '#0AA0C0', '#E2F5FA'));
  buf.writeln(_statCard('待协调问题', '${report.filledIssues.length}', '#C77700', '#FFF4E2'));
  buf.writeln(_statCard('巡场问题', '${defects.length}', '#E0342B', '#FFE9E7'));
  buf.writeln(_statCard('重要紧急', '$urgentCount', '#D93025', '#FCE8E6'));
  buf.writeln(_statCard('未闭环', '$openDefects', '#D98A00', '#FFF2DC'));
  buf.writeln(_statCard('已闭环', '$doneCount', '#1E9E4E', '#E4F6EB'));
  buf.writeln('</section>');

  // ===== 各章节 =====
  for (var i = 0; i < chapters.length; i++) {
    buf.writeln('<section class="chapter">');
    buf.writeln('<h2><i>${_cn(i)}</i>${_esc(_cleanTitle(chapters[i].title))}</h2>');
    buf.writeln(chapters[i].body);
    buf.writeln('</section>');
  }

  buf.writeln('<footer>本报告由「蓝图落地」APP 自动生成 · '
      '现场照片与进度数据同步自设计院周报 · 生成时间 ${_esc(generatedAt)}</footer>');
  buf.writeln('</body>');
  buf.writeln('</html>');
  return buf.toString();
}

// ==================== 各板块渲染 ====================
// 每个板块返回 (title, body)，由主函数统一编号渲染。

({String title, String body}) _photosSection(String title,
        List<WeeklyPhotoGroup> groups, Map<String, String> photoBase64) =>
    (
      title: title,
      body:
          '<div class="photo-groups">${groups.map((g) => _photoGroup(g, photoBase64)).join('')}</div>',
    );

String _photoGroup(WeeklyPhotoGroup g, Map<String, String> photoBase64) {
  final imgs = g.photos.map((p) {
    final b64 = photoBase64[p.file];
    if (b64 == null || b64.isEmpty) {
      return '<div class="photo photo--missing">照片未加载</div>';
    }
    return '<figure class="photo"><img src="data:image/jpeg;base64,$b64" '
        'alt="${_esc(g.caption)}" loading="lazy"></figure>';
  }).join('');
  return '<div class="photo-group">'
      '<div class="photo-cap"><b>${_esc(g.caption)}</b>'
      '${g.date.isNotEmpty ? '<span class="photo-date">${_esc(g.date)}</span>' : ''}'
      '</div>'
      '<div class="photo-grid${g.photos.length == 1 ? ' photo-grid--1' : (g.photos.length == 2 ? ' photo-grid--2' : '')}">$imgs</div>'
      '</div>';
}

({String title, String body}) _progressSection(
        String title, List<WeeklyProgressRow> rows) =>
    (
      title: title,
      body:
          '<table class="report-table"><thead><tr><th class="col-b">楼栋</th>'
              '<th>现场安装施工进度情况</th></tr></thead><tbody>'
              '${rows.map((r) => '<tr><td class="col-b">${_esc(r.building)}</td>'
                  '<td>${_progressDetail(r.detail)}</td></tr>').join('')}'
              '</tbody></table>',
    );

/// 进度长文本 → 按分号分行；「防排烟：2层风管安装」拆成专业标签 + 内容两段式，
/// 避免整段挤成一坨。
String _progressDetail(String detail) {
  final parts = detail
      .split(RegExp(r'[；;]\s*'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);
  return parts.map((p) {
    final m = RegExp(r'^([^:：]{2,8})[:：]\s*(.+)$').firstMatch(p);
    if (m != null) {
      return '<div class="pg-row"><span class="pg-tag">${_esc(m.group(1)!)}</span>'
          '<span class="pg-txt">${_esc(m.group(2)!)}</span></div>';
    }
    return '<div class="pg-row"><span class="pg-txt">${_esc(p)}</span></div>';
  }).join('');
}

({String title, String body}) _ledgerSection(WeeklyLedger l) {
  if (l.isEmpty) {
    return (title: l.title, body: '<div class="empty">本周无</div>');
  }
  final th = l.columns.map((c) => '<th>${_esc(c)}</th>').join('');
  final body = l.filledRows
      .map((r) => '<tr>${r.map((c) => '<td>${_esc(c)}</td>').join('')}</tr>')
      .join('');
  return (
    title: l.title,
    body:
        '<table class="report-table"><thead><tr>$th</tr></thead>'
            '<tbody>$body</tbody></table>',
  );
}

({String title, String body}) _noteSection(WeeklyNote n) => (
      title: n.title,
      body:
          '<div class="note-box${n.text.trim().isEmpty || n.text.trim() == '本周无' ? ' empty' : ''}">'
              '${_esc(n.text)}</div>',
    );

({String title, String body}) _issuesSection(
        String title, List<WeeklyIssue> items) =>
    (
      title: title,
      body:
          '<table class="report-table"><thead><tr><th class="col-no">序号</th>'
              '<th>事由</th><th class="rem">备注</th></tr></thead><tbody>'
              '${items.map((e) => '<tr><td class="col-no">${_esc(e.no)}</td>'
                  '<td>${_esc(e.subject)}</td><td class="rem">${_esc(e.remark)}</td></tr>').join('')}'
              '</tbody></table>',
    );

/// 巡场清单及闭环情况（版式对齐 LDI 设计院巡场报告单）：
/// 分组按楼栋（无栋号信息时回退按严重程度），每条问题按
/// 「巡场意见 → 整改回复 → 闭合确认」三段呈现，末尾附销项汇总表。
({String title, String body}) _defectsSection(
    List<Defect> defects, Map<String, String> photoBase64) {
  final list = [...defects]
    ..sort((a, b) {
      final sa = _severityOrder.indexOf(a.severity);
      final sb = _severityOrder.indexOf(b.severity);
      return sa != sb ? sa - sb : a.ts.compareTo(b.ts);
    });

  final buf = StringBuffer();

  // 重要等级分布 + 严重程度分布（巡场报告单按等级分派处置优先级）
  buf.writeln('<div class="bars">');
  for (final i in kImportanceOrder) {
    final n = list.where((d) => d.effectiveImportance == i).length;
    if (n == 0) continue;
    buf.writeln(_barItem(i.label, n, list.length, importanceFg(i)));
  }
  buf.writeln('</div>');
  buf.writeln('<div class="bars">');
  for (final s in _severityOrder) {
    final n = list.where((d) => d.severity == s).length;
    buf.writeln(_barItem(s.label, n, list.length, _severityHex(s)));
  }
  buf.writeln('</div>');

  // 分组明细：楼栋优先，回退严重程度
  var idx = 0;
  for (final g in groupDefects(defects)) {
    buf.writeln('<div class="group">');
    final bg = g.colorHex ?? kBrandHex;
    final fg = g.colorHex == null
        ? '#FFFFFF'
        : (g.colorHex!.toUpperCase() == '#F5C518' ? '#5B4A00' : '#FFFFFF');
    final right = g.subtitle ?? '${g.items.length} 项';
    buf.writeln('<div class="group-head" style="background:$bg;color:$fg">'
        '<span>${_esc(g.title)}</span>'
        '<span class="group-action">${_esc(right)}</span></div>');
    for (final d in g.items) {
      idx++;
      buf.writeln(_defectCard(idx, d, photoBase64));
    }
    buf.writeln('</div>');
  }

  // 销项汇总表（对齐巡场报告单列：序号 / 部位 / 重要等级 / 状态 / 责任人 / 时间）
  buf.writeln('<table class="report-table sum-table"><thead><tr><th class="col-no">序号</th>'
      '<th>部位 / 缺陷</th><th>重要等级</th><th>严重程度</th><th>状态</th>'
      '<th>是否闭合</th><th>责任人</th><th>发现时间</th></tr></thead><tbody>');
  var i2 = 0;
  for (final st in _statusOrder) {
    for (final d in list.where((e) => e.status == st)) {
      i2++;
      final imp = d.effectiveImportance;
      buf.writeln('<tr><td class="col-no">$i2</td>'
          '<td>${_esc(d.part)}<div class="sub-cell">${_esc(d.anchor)} · ${_esc(d.floor)}</div></td>'
          '<td><span class="pill" style="background:${importanceBg(imp)};'
          'color:${importanceFg(imp)}">${_esc(imp.label)}</span></td>'
          '<td><span class="pill" style="background:${_severityHex(d.severity)};'
          'color:${_severityFg(d.severity)}">${_esc(d.severity.label)}</span></td>'
          '<td>${_esc(d.status.label)}</td>'
          '<td>${d.closed ? '<span class="pill st-done">是</span>' : '<span class="pill st-draft">否</span>'}</td>'
          '<td>${_esc(d.resp)}</td>'
          '<td>${_esc(d.ts)}</td></tr>');
    }
  }
  buf.writeln('</tbody></table>');

  return (
    title: '巡场清单及闭环情况',
    body: buf.toString(),
  );
}

// ==================== 组件 ====================

String _statCard(String label, String value, String color, String bg) =>
    '<div class="stat" style="--c:$color;--bg:$bg">'
    '<div class="stat-v" style="color:$color">$value</div>'
    '<div class="stat-l">${_esc(label)}</div></div>';

String _barItem(String label, int n, int total, String color) {
  final pct = total == 0 ? 0 : n / total;
  return '<div class="bar-item">'
      '<div class="bar-label"><span>${_esc(label)}</span><b>$n</b></div>'
      '<div class="bar-track"><div class="bar-fill" '
      'style="width:${(pct * 100).toStringAsFixed(0)}%;background:$color"></div></div>'
      '</div>';
}

/// 现场照片 / 整改回复照片（base64 内嵌，缺失时渲染占位不阻断导出。
/// 未挂照片的问题（如台账导入项）不渲染照片区）。
String _photoBlock(
  String? rel,
  Map<String, String> photoBase64,
  String alt,
  String emptyText,
) {
  if (rel == null || rel.isEmpty) return '';
  final b64 = photoBase64[rel];
  return '<div class="defect-photo">${b64 != null ? '<img src="data:image/jpeg;base64,$b64" alt="${_esc(alt)}">' : '<span class="ph-empty">$emptyText</span>'}</div>';
}

/// 缺陷卡（巡场报告单三段式）：巡场意见 → 整改回复 → 闭合确认。
String _defectCard(int idx, Defect d, Map<String, String> photoBase64) {
  final tags = d.tags.map((t) => '<span class="tag">${_esc(t)}</span>').join('');
  final coord = d.coordText;
  final imp = d.effectiveImportance;

  // —— 一、巡场意见 ——
  final suggestion = (d.suggestion ?? '').trim().isEmpty
      ? ''
      : '<div class="note-text ai">AI整改建议（施工单位）：${_esc(d.suggestion!)}</div>';
  final opinion = '<div class="dsec">'
      '<div class="dsec-h">巡场意见</div>'
      '<div class="dsec-b"><div class="note-text">${_esc(d.note)}</div>'
      '$suggestion'
      '${_photoBlock(d.photoPath, photoBase64, '${d.part}现场照片', '现场照片未加载')}'
      '</div></div>';

  // —— 二、整改回复 ——
  final reply = (d.reply == null || d.reply!.trim().isEmpty) &&
          (d.replyPhotoPath == null || d.replyPhotoPath!.isEmpty)
      ? ''
      : '<div class="dsec">'
          '<div class="dsec-h">整改回复</div>'
          '<div class="dsec-b">'
          '${(d.reply ?? '').trim().isNotEmpty ? '<div class="note-text">${_esc(d.reply!)}</div>' : ''}'
          '${_photoBlock(d.replyPhotoPath, photoBase64, '${d.part}整改后照片', '回复照片未加载')}'
          '${((d.replyBy ?? '').trim().isNotEmpty || (d.replyTs ?? '').trim().isNotEmpty) ? '<div class="reply-meta">${_esc([if ((d.replyBy ?? '').trim().isNotEmpty) d.replyBy!, if ((d.replyTs ?? '').trim().isNotEmpty) d.replyTs!].join(' · '))}</div>' : ''}'
          '</div></div>';

  // —— 三、闭合确认 ——
  final closeChips = [
    '<span class="close-chip">${d.closed ? '是否闭合：是' : '是否闭合：否'}</span>',
    if ((d.completion ?? '').trim().isNotEmpty)
      '<span class="close-chip">完成状态：${_esc(d.completion!)}</span>',
  ].join('');
  final close = '<div class="dsec">'
      '<div class="dsec-h">闭合确认</div>'
      '<div class="dsec-b"><div class="close-row">$closeChips</div>'
      '${(d.closeNote ?? '').trim().isNotEmpty ? '<div class="note-text warn">${_esc(d.closeNote!)}</div>' : ''}'
      '</div></div>';

  return '<div class="defect">'
      '<div class="defect-title"><span class="no">$idx</span>'
      '<span class="part">${_esc(d.part)}</span>'
      '<span class="pill" style="background:${importanceBg(imp)};'
      'color:${importanceFg(imp)}">${_esc(imp.label)}</span>'
      '<span class="pill" style="background:${_severityHex(d.severity)};'
      'color:${_severityFg(d.severity)}">${_esc(d.severity.label)} · ${_esc(d.severity.action)}</span>'
      '<span class="pill st-${d.status.name}">${_esc(d.status.label)}</span>'
      '</div>'
      '<div class="defect-body">'
      '<div class="field"><span class="k">缺陷类型</span><span class="v">${_esc(d.type)}</span></div>'
      '<div class="field"><span class="k">专业分类</span><span class="v">${_esc(d.category.label)}</span></div>'
      '<div class="field"><span class="k">缺陷位置</span><span class="v">${_esc(d.anchor)}</span></div>'
      '<div class="field"><span class="k">楼层部位</span><span class="v">${_esc(d.floor)}</span></div>'
      '<div class="field"><span class="k">责任人</span><span class="v">${_esc(d.resp)}</span></div>'
      '<div class="field"><span class="k">记录人</span><span class="v">${_esc(d.reporter)}</span></div>'
      '<div class="field"><span class="k">发现时间</span><span class="v">${_esc(d.ts)}</span></div>'
      '<div class="field"><span class="k">GPS / 海拔</span><span class="v">${_esc(d.gps)} · ${_esc(d.alt)}</span></div>'
      '${coord != null ? '<div class="field"><span class="k">图纸坐标</span><span class="v">${_esc(coord)}</span></div>' : ''}'
      '${tags.isNotEmpty ? '<div class="field"><span class="k">标签</span><span class="v">$tags</span></div>' : ''}'
      '</div>'
      '$opinion$reply$close'
      '</div>';
}

// ==================== 工具 ====================

String _severityHex(DefectSeverity s) {
  switch (s) {
    case DefectSeverity.red:
      return '#FF3B30';
    case DefectSeverity.orange:
      return '#FF9500';
    case DefectSeverity.yellow:
      return '#F5C518';
    case DefectSeverity.green:
      return '#34C759';
  }
}

/// 严重程度文字色（黄色底用深色字保证可读）。
String _severityFg(DefectSeverity s) =>
    s == DefectSeverity.yellow ? '#5B4A00' : '#FFFFFF';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// ==================== 样式 ====================

String _css() => r'''
:root { color-scheme: light; }
* { box-sizing: border-box; }
body {
  margin: 0; padding: 0 0 32px; background: #F5F6F8;
  font-family: -apple-system, "PingFang SC", "Microsoft YaHei", "Segoe UI", sans-serif;
  color: #202224; line-height: 1.55; font-size: 14px;
}
.wrap { max-width: 900px; margin: 0 auto; }
body > * { max-width: 900px; margin-left: auto; margin-right: auto; }

/* ---- 封面 ---- */
.cover {
  background: linear-gradient(135deg, #0A9BFF 0%, #0580E8 100%);
  color: #fff; border-radius: 0 0 20px 20px; padding: 28px 28px 24px;
  margin-bottom: 16px;
}
.cover h1 { font-size: 24px; margin: 0; letter-spacing: 1px; font-weight: 700; }
.cover-sub { font-size: 13px; opacity: .9; margin-top: 4px; }
.cover-meta {
  display: grid; grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px; margin-top: 18px; justify-content: stretch;
}
.cover-meta div {
  display: flex; flex-direction: column;
  background: rgba(255,255,255,.16); border: none;
  border-radius: 12px; padding: 9px 13px; min-width: 0;
}
.cover-meta span { font-size: 11px; opacity: .82; }
.cover-meta b { font-size: 14px; font-weight: 600; margin-top: 1px; word-break: break-all; }

/* ---- 概览（INS 风 pastel 色卡，无框无影）---- */
.overview {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(108px, 1fr)); gap: 12px;
  margin-bottom: 16px; box-sizing: border-box;
}
.stat {
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  min-width: 0; background: var(--bg, #F1F3F5); border-radius: 16px;
  padding: 17px 8px; text-align: center;
}
.stat-v { font-size: 26px; font-weight: 800; line-height: 1; letter-spacing: -0.5px; }
.stat-l {
  font-size: 12px; color: #60656B; margin-top: 7px; font-weight: 500;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%;
}
@media (max-width: 480px) {
  .overview { gap: 9px; }
  .stat { border-radius: 13px; padding: 13px 6px; }
  .stat-v { font-size: 22px; }
  .stat-l { font-size: 11px; }
}

/* ---- 章节 ---- */
.chapter { background: #fff; border-radius: 18px; padding: 18px 20px; margin-bottom: 14px; }
.chapter h2 {
  font-size: 17px; margin: 0 0 14px; padding-left: 11px; font-weight: 700;
  border-left: 4px solid #0395FF; display: flex; align-items: baseline; gap: 7px;
}
.chapter h2 i { font-style: normal; color: #0395FF; font-size: 15px; }
.chapter h2::after { content: ''; flex: 1; height: 1px; background: #EEF0F2; align-self: center; }

/* ---- 照片墙 ---- */
.photo-groups { display: flex; flex-direction: column; gap: 10px; }
.photo-group { border-radius: 14px; overflow: hidden; background: #F6F7F9; }
.photo-cap {
  display: flex; justify-content: space-between; align-items: center; gap: 10px;
  background: #F6F7F9; padding: 9px 14px;
  border-left: 3px solid #0395FF;
}
.photo-cap b { font-size: 14px; font-weight: 600; }
.photo-date { font-size: 12px; color: #60656B; white-space: nowrap; font-variant-numeric: tabular-nums; }
.photo-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; padding: 10px; }
.photo-grid--1 { grid-template-columns: 1fr; }
.photo-grid--2 { grid-template-columns: repeat(2, 1fr); }
.photo { margin: 0; border-radius: 10px; overflow: hidden; background: #ECEEF1; }
.photo img { display: block; width: 100%; height: 172px; object-fit: cover; }
/* 单张照片占满整行：图纸完整展示不裁剪，不留大片空白 */
.photo-grid--1 .photo img { height: auto; max-height: 400px; object-fit: contain; }
.photo-grid--1 .photo--missing { height: 172px; }
.photo--missing {
  height: 172px; display: flex; align-items: center; justify-content: center;
  color: #B5B9BF; font-size: 12px;
}

/* ---- 进度专业行（「防排烟：xxx」两段式）---- */
.pg-row { display: flex; gap: 8px; padding: 2px 0; }
.pg-tag { flex-shrink: 0; min-width: 70px; color: #0273CC; font-weight: 600; }
.pg-txt { color: #202224; min-width: 0; }

/* ---- 表格 ---- */
.report-table { width: 100%; border-collapse: collapse; font-size: 13px; }
.report-table th, .report-table td {
  text-align: left; padding: 9px 10px; border-bottom: 1px solid #EEF0F2; vertical-align: top;
}
.report-table th { color: #60656B; font-weight: 600; background: #F6F7F9; white-space: nowrap; }
.report-table td { color: #202224; word-break: break-word; }
.report-table .col-b { width: 78px; font-weight: 600; white-space: nowrap; }
.report-table .col-no { width: 48px; color: #919499; }
.report-table .rem { width: 30%; color: #60656B; }
.sum-table { margin-top: 18px; }
.sub-cell { color: #919499; font-size: 12px; margin-top: 2px; }

/* ---- 说明 / 空态 ---- */
.note-box { background: #F6F7F9; border-radius: 12px; padding: 12px 14px; font-size: 13px; color: #202224; }
.empty { color: #919499; font-size: 13px; padding: 4px 0; }

/* ---- 严重程度分布 ---- */
.bars { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 16px; }
.bar-label { display: flex; justify-content: space-between; font-size: 12px; color: #60656B; margin-bottom: 4px; }
.bar-label b { color: #202224; }
.bar-track { height: 7px; background: #EEF0F2; border-radius: 999px; overflow: hidden; }
.bar-fill { height: 100%; border-radius: 999px; }

/* ---- 缺陷 ---- */
.group { margin-bottom: 14px; }
.group-head {
  display: flex; justify-content: space-between; align-items: center;
  padding: 9px 14px; border-radius: 10px; font-weight: 700; font-size: 14px;
}
.group-action { font-weight: 500; font-size: 12px; opacity: .92; }
.defect { background: #F8F9FB; border-radius: 12px; padding: 14px 16px; margin-top: 10px; }
.defect-title { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-bottom: 9px; }
.defect-title .no {
  display: inline-flex; width: 21px; height: 21px; align-items: center; justify-content: center;
  background: #0395FF; color: #fff; border-radius: 7px; font-size: 12px; flex-shrink: 0;
}
.defect-title .part { font-size: 14px; font-weight: 600; flex: 1; min-width: 110px; }
.pill { display: inline-block; padding: 2px 8px; border-radius: 6px; font-size: 12px; font-weight: 600; white-space: nowrap; }
.st-draft { background: #FFEBEA; color: #FF3B30; }
.st-doing { background: #FFF3E0; color: #B26A00; }
.st-done { background: #E6F8ED; color: #1E9E4E; }
.st-reject { background: #E6F5FF; color: #0273CC; }
.defect-body { display: grid; grid-template-columns: 1fr 1fr; gap: 5px 20px; }
.field { display: flex; font-size: 13px; min-width: 0; }
.field.full { grid-column: 1 / -1; }
.field .k { width: 80px; color: #919499; flex-shrink: 0; }
.field .v { color: #202224; word-break: break-all; }
.field .v.note { background: #EEF0F3; padding: 6px 10px; border-radius: 8px; flex: 1; }
.tag { display: inline-block; background: #EEF0F3; color: #60656B; border-radius: 6px; padding: 1px 6px; font-size: 12px; margin-right: 4px; }
.defect-photo { margin-top: 8px; }
.defect-photo img { display: block; max-width: 280px; max-height: 200px; border-radius: 10px; border: none; object-fit: cover; }
.defect-photo .ph-empty { display: inline-block; background: #EEF0F3; color: #919499; border-radius: 8px; padding: 10px 14px; font-size: 12px; }

/* ---- 巡场报告单三段式：巡场意见 / 整改回复 / 闭合确认 ---- */
.dsec { margin-top: 11px; }
.dsec-h {
  display: flex; align-items: center; gap: 6px;
  font-size: 12px; font-weight: 700; color: #0273CC; margin-bottom: 5px;
}
.dsec-h::before { content: ''; width: 3px; height: 11px; background: #0395FF; border-radius: 2px; }
.dsec-b { font-size: 13px; color: #202224; }
.note-text { background: #F2F4F6; border-radius: 8px; padding: 8px 11px; white-space: pre-wrap; }
.note-text.ai { background: #E8F4FE; color: #02519E; margin-top: 6px; }
.note-text.warn { background: #FFF6E8; color: #7A4E00; }
.reply-meta { margin-top: 5px; font-size: 12px; color: #919499; }
.close-row { display: flex; gap: 8px; flex-wrap: wrap; }
.close-chip { background: #F2F4F6; color: #60656B; border-radius: 6px; padding: 3px 9px; font-size: 12px; }

footer {
  text-align: center; color: #B8BCC2; font-size: 12px;
  margin-top: 22px; margin-bottom: 4px; padding: 0 20px;
}

@media (max-width: 700px) {
  .photo-grid { grid-template-columns: repeat(2, 1fr); }
  .bars { grid-template-columns: repeat(2, 1fr); }
  .defect-body { grid-template-columns: 1fr; }
}

@media print {
  body { background: #fff; padding: 0; }
  .cover { border-radius: 0; }
  .chapter, .overview { border: none; box-shadow: none; }
  .chapter { page-break-inside: auto; }
  .photo-group, .defect, .group-head { page-break-inside: avoid; }
  .report-table { page-break-inside: auto; }
  .report-table tr { page-break-inside: avoid; }
  footer { page-break-inside: avoid; }
  @page { margin: 14mm 12mm; }
}
''';
