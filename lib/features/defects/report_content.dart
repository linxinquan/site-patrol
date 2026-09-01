import '../../data/models.dart';
import '../../data/weekly_report.dart';

/// 报告正文的「与渲染格式无关」的中间层。
///
/// 现场工作汇报目前有三种渲染端：
///   - `report_builder.dart`  → 自包含 HTML（预览 / 打印 / 存档）
///   - `report_docx.dart`     → Word（.docx，可二次编辑后发给各方）
///   - `report_pdf.dart`      → PDF（定稿分发）
///
/// 三端共用这里的**板块顺序、空板块剔除规则、严重程度配色、排序规则**，
/// 避免出现「Word 里有的章节 PDF 里没有」这类偏差。
/// 任一渲染端新增板块时，改这里即可三端同步。

// ==================== 配色 ====================

/// 品牌色（与 App / HTML 报告一致）。
const String kBrandHex = '#0395FF';

/// 文本层级色。
const String kFgHex = '#202224';
const String kFg2Hex = '#60656B';
const String kMutedHex = '#919499';

/// 分隔线 / 浅底。
const String kLineHex = '#E9EAEB';
const String kBgHex = '#F4F6F7';

/// 严重程度主色（红→绿，对应「停工上报 → 常规观察」处置优先级）。
const Map<DefectSeverity, String> kSeverityHex = {
  DefectSeverity.red: '#FF3B30',
  DefectSeverity.orange: '#FF9500',
  DefectSeverity.yellow: '#F5C518',
  DefectSeverity.green: '#34C759',
};

/// 严重程度排序（严重在前）。
const List<DefectSeverity> kSeverityOrder = [
  DefectSeverity.red,
  DefectSeverity.orange,
  DefectSeverity.yellow,
  DefectSeverity.green,
];

/// 状态排序（未闭环在前）。
const List<DefectStatus> kStatusOrder = [
  DefectStatus.draft,
  DefectStatus.doing,
  DefectStatus.done,
  DefectStatus.reject,
];

String severityHex(DefectSeverity s) => kSeverityHex[s] ?? kBrandHex;

/// 严重程度上的文字色（黄底用深色字保证可读）。
String severityFg(DefectSeverity s) =>
    s == DefectSeverity.yellow ? '#5B4A00' : '#FFFFFF';

/// 状态标签底色（浅底 + 深色文字，与 HTML `.st-*` 一致）。
String statusBg(DefectStatus s) {
  switch (s) {
    case DefectStatus.draft:
      return '#FFEBEA';
    case DefectStatus.doing:
      return '#FFF3E0';
    case DefectStatus.done:
      return '#E6F8ED';
    case DefectStatus.reject:
      return '#E6F5FF';
  }
}

/// 状态标签文字色。
String statusFg(DefectStatus s) {
  switch (s) {
    case DefectStatus.draft:
      return '#FF3B30';
    case DefectStatus.doing:
      return '#B26A00';
    case DefectStatus.done:
      return '#1E9E4E';
    case DefectStatus.reject:
      return '#0273CC';
  }
}

/// `#RRGGBB` → `0xAARRGGBB`（package:pdf 的 PdfColor 用）。
int hexToArgb(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return int.parse(h, radix: 16);
}

// ==================== 板块 ====================

/// 报告正文板块（渲染端据此按顺序输出，无需各自重复过滤规则）。
sealed class ReportBlock {
  String get title;
}

/// 现场施工进度（照片墙，按「施工内容 + 日期」分组）。
final class PhotosBlock extends ReportBlock {
  PhotosBlock(this.groups);

  final List<WeeklyPhotoGroup> groups;

  @override
  String get title => '现场施工进度情况';
}

/// 现场（机电）施工进度（楼栋 × 进度）。
final class ProgressBlock extends ReportBlock {
  ProgressBlock(this.rows);

  final List<WeeklyProgressRow> rows;

  @override
  String get title => '现场（机电）施工进度情况';
}

/// 台账类表格（图档台账 / 变更台账 / 现场技术协调）。
final class LedgerBlock extends ReportBlock {
  LedgerBlock(this.ledger);

  final WeeklyLedger ledger;

  @override
  String get title => ledger.title;
}

/// 纯文字说明（如设计交底及会审情况）。
final class NoteBlock extends ReportBlock {
  NoteBlock(this.note);

  final WeeklyNote note;

  @override
  String get title => note.title;
}

/// 待沟通协调问题。
final class IssuesBlock extends ReportBlock {
  IssuesBlock(this.items);

  final List<WeeklyIssue> items;

  @override
  String get title => '待沟通协调问题';
}

/// 现场问题清单及闭环情况。
final class DefectsBlock extends ReportBlock {
  DefectsBlock(this.defects);

  final List<Defect> defects;

  @override
  String get title => '现场问题清单及闭环情况';
}

/// 按周报版式排出正文板块顺序，并剔除无实质内容的板块。
///
/// 剔除规则（与 HTML 端一致，P0）：
/// - 照片 / 进度 / 问题 / 缺陷：空集合不出章节；
/// - 台账：`WeeklyLedger.isEmpty`（全空 / 全「无」/ 纯数字序号）时剔除；
/// - 文字说明：空串或「本周无」时剔除。
/// 台账与文字说明按原始 PPT 页码穿插排序，保持设计院周报原有次序。
List<ReportBlock> buildReportBlocks(WeeklyReport report) {
  final blocks = <ReportBlock>[];

  final groups = report.photoGroups;
  if (groups.isNotEmpty) blocks.add(PhotosBlock(groups));

  if (report.progress.isNotEmpty) blocks.add(ProgressBlock(report.progress));

  final misc = <({int page, ReportBlock block})>[
    for (final l in report.ledgers)
      if (!l.isEmpty) (page: l.page, block: LedgerBlock(l)),
    for (final n in report.notes)
      if (n.text.trim().isNotEmpty && n.text.trim() != '本周无')
        (page: n.page, block: NoteBlock(n)),
  ]..sort((a, b) => a.page - b.page);
  blocks.addAll(misc.map((e) => e.block));

  if (report.filledIssues.isNotEmpty) {
    blocks.add(IssuesBlock(report.filledIssues));
  }
  if (report.defects.isNotEmpty) blocks.add(DefectsBlock(report.defects));

  return blocks;
}

// ==================== 概览统计 ====================

/// 封面下方的概览数字条。
class ReportStats {
  const ReportStats({
    required this.photos,
    required this.buildings,
    required this.issues,
    required this.defects,
    required this.open,
    required this.done,
  });

  final int photos;
  final int buildings;
  final int issues;
  final int defects;
  final int open;
  final int done;
}

ReportStats buildReportStats(WeeklyReport report) {
  final defects = report.defects;
  return ReportStats(
    photos: report.photos.length,
    buildings: report.progress.length,
    issues: report.filledIssues.length,
    defects: defects.length,
    open: defects
        .where((d) =>
            d.status == DefectStatus.draft || d.status == DefectStatus.doing)
        .length,
    done: defects.where((d) => d.status == DefectStatus.done).length,
  );
}

/// 缺陷排序：先按严重程度（严重在前），同级按发现时间。
List<Defect> sortDefects(List<Defect> defects) => [...defects]..sort((a, b) {
      final sa = kSeverityOrder.indexOf(a.severity);
      final sb = kSeverityOrder.indexOf(b.severity);
      return sa != sb ? sa - sb : a.ts.compareTo(b.ts);
    });

// ==================== 文本工具 ====================

const List<String> _cnNum = [
  '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
  '十一', '十二', '十三', '十四', '十五',
];

/// 章节序号（0 → 一）。
String cnNumber(int i) => i < _cnNum.length ? _cnNum[i] : '${i + 1}';

/// 去掉 PPT 标题自带的序号前缀（「3、图档台账情况」→「图档台账情况」），
/// 避免与渲染端自动生成的章节序号重复。
String cleanBlockTitle(String t) =>
    t.replaceFirst(RegExp(r'^\d{1,2}\s*[、.．]\s*'), '').trim();

/// 进度长文本 → 若干「专业标签 + 内容」行。
///
/// 「防排烟：2层风管安装；给排水：主管安装」→
/// `[('防排烟','2层风管安装'), ('给排水','主管安装')]`；
/// 无冒号前缀时标签为空串，整句作为内容。
List<({String tag, String text})> splitProgressDetail(String detail) =>
    detail
        .split(RegExp(r'[；;]\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((p) {
      final m = RegExp(r'^([^:：]{2,8})[:：]\s*(.+)$').firstMatch(p);
      return m != null
          ? (tag: m.group(1)!, text: m.group(2)!)
          : (tag: '', text: p);
    }).toList();

/// 缺陷卡片展示的字段（键 → 值），空值自动跳过。
List<(String, String)> defectFields(Defect d) => [
      ('缺陷类型', d.type),
      ('专业分类', d.category.label),
      ('缺陷位置', d.anchor),
      ('楼层部位', d.floor),
      ('责任人', d.resp),
      ('记录人', d.reporter),
      ('发现时间', d.ts),
      ('GPS / 海拔', '${d.gps} · ${d.alt}'),
      if (d.coordText != null) ('图纸坐标', d.coordText!),
      if (d.tags.isNotEmpty) ('标签', d.tags.join(' / ')),
    ].where((e) => e.$2.trim().isNotEmpty).toList();
