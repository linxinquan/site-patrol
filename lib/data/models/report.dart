/// 报告归档域模型。
///
/// 从 `lib/data/report_record.dart` 迁入 `models/`（原先是唯一不在 barrel 里的
/// 入库实体，违反「`models.dart` 是唯一契约入口」的约定，v2.2 补齐）。
///
/// 后端对应表：`reports`。客户端可写实体，故带 [SyncMeta]。
///
/// 注意：**正文不入库** —— 报告正文（HTML / PDF / Word / Excel）一律客户端按需重导，
/// 归档只存元数据（标题 / 周期 / 格式 / 统计 / 小结），见 `BACKEND_ARCHITECTURE.md` §11。
library;

import '../sync_meta.dart';

/// 一份**已生成**的巡场报告归档记录（「巡场报告」页的列表项）。
///
/// 只保存元数据（标题 / 周期 / 格式 / 统计 / 巡场小结），**不保存报告正文**：
/// PDF/Word 动辄数 MB 且现场照片以 base64 内嵌，写进 LocalStorage 会撑爆配额。
/// 归档的职责是「查得到、看得清」，需要原件时回问题清单页重新导出。
class ReportRecord {
  /// 归档 id（`rep_<生成时间 ms>`）。
  final String id;

  final String projectId;
  final String projectName;

  /// 报告标题，如「现场工作汇报」。
  final String title;

  /// 汇报周期，如 `2025-08-11 ~ 2025-08-17`。
  final String period;

  /// 编制人（姓名 · 单位 · 角色）。
  final String reporter;

  /// 生成时间（ms）。
  final int createdAt;

  /// 已导出的格式标签（PDF / Word / Excel / 网页链接）。
  /// 同一份报告（标题 + 周期相同）导出多种格式时合并到一条，不重复建卡。
  final List<String> formats;

  /// 报告内问题总数 / 未闭环 / 已闭环 / 重要紧急（与报告封面统计同源）。
  final int defectCount;
  final int openCount;
  final int doneCount;
  final int urgentCount;

  /// 导出时填写的巡场小结（可空）。
  final String note;

  /// 同步元数据（`clientId` / version / 时间戳 / 软删）。
  final SyncMeta sync;

  const ReportRecord({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.title,
    required this.period,
    required this.reporter,
    required this.createdAt,
    this.formats = const [],
    this.defectCount = 0,
    this.openCount = 0,
    this.doneCount = 0,
    this.urgentCount = 0,
    this.note = '',
    this.sync = const SyncMeta(),
  });

  DateTime get createdAtTime => DateTime.fromMillisecondsSinceEpoch(createdAt);

  ReportRecord copyWith({
    String? id,
    List<String>? formats,
    int? createdAt,
    SyncMeta? sync,
  }) =>
      ReportRecord(
        id: id ?? this.id,
        projectId: projectId,
        projectName: projectName,
        title: title,
        period: period,
        reporter: reporter,
        createdAt: createdAt ?? this.createdAt,
        formats: formats ?? this.formats,
        defectCount: defectCount,
        openCount: openCount,
        doneCount: doneCount,
        urgentCount: urgentCount,
        note: note,
        sync: sync ?? this.sync,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'title': title,
        'period': period,
        'reporter': reporter,
        'createdAt': createdAt,
        'formats': formats,
        'defectCount': defectCount,
        'openCount': openCount,
        'doneCount': doneCount,
        'urgentCount': urgentCount,
        'note': note,
        ...sync.toJson(),
      };

  /// 旧数据读取缺字段一律给默认值，不抛错。
  factory ReportRecord.fromJson(Map<String, dynamic> m) => ReportRecord(
        id: m['id'] as String? ?? '',
        projectId: m['projectId'] as String? ?? '',
        projectName: m['projectName'] as String? ?? '',
        title: m['title'] as String? ?? '',
        period: m['period'] as String? ?? '',
        reporter: m['reporter'] as String? ?? '',
        createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
        formats: (m['formats'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        defectCount: (m['defectCount'] as num?)?.toInt() ?? 0,
        openCount: (m['openCount'] as num?)?.toInt() ?? 0,
        doneCount: (m['doneCount'] as num?)?.toInt() ?? 0,
        urgentCount: (m['urgentCount'] as num?)?.toInt() ?? 0,
        note: m['note'] as String? ?? '',
        sync: SyncMeta.fromJson(m),
      );
}
