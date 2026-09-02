import 'models.dart';

/// 周报 / 月报素材模型。
///
/// 版式参照深总院《项目东区现场工作汇报》（设计院现场管理周报通行格式）：
///   封面（项目 / 标题 / 周期 / 编制单位）
///   → 一、现场施工进度（照片墙：图 + 日期 + 施工内容）
///   → 二、机电施工进度（楼栋 × 进度描述）
///   → 三、图档台账 / 四、变更台账 / 五、设计交底 / 六、技术协调
///   → 七、待沟通协调问题
///
/// 素材由 `_tools/pptx_report_extract.py` 从设计院周报 PPTX 自动抽取，
/// 生成物落在 `mock/weekly_report_mock.dart`（该文件自动生成，勿手工编辑）。

/// 现场照片（带拍摄日期与施工内容说明）。
class WeeklyPhoto {
  /// assets 下的相对路径，如 `assets/site_photos/site_01.jpg`。
  final String file;

  /// 拍摄日期，`yyyy-MM-dd`；无日期时为空串。
  final String date;

  /// 施工内容 / 部位说明，如「绿毯 F4 区域防水施工」。
  final String caption;

  const WeeklyPhoto({
    required this.file,
    required this.date,
    required this.caption,
  });
}

/// 施工进度一行（楼栋 / 部位 → 进度描述）。
class WeeklyProgressRow {
  /// 楼栋或部位，如「7A栋」「地下室」。
  final String building;

  /// 进度描述（含各专业完成情况与百分比）。
  final String detail;

  const WeeklyProgressRow({required this.building, required this.detail});
}

/// 台账类表格（图档台账 / 变更台账 / 现场技术协调）。
class WeeklyLedger {
  final String title;
  final List<String> columns;
  final List<List<String>> rows;

  /// 来源 PPT 页码（1 起），用于跨板块排序（台账与文字说明穿插时保持原顺序）。
  final int page;

  const WeeklyLedger({
    required this.title,
    required this.columns,
    required this.rows,
    this.page = 99,
  });

  /// 整表为空或全填「无」时返回 true——报告里直接跳过该板块（不占版面）。
  /// 纯数字序号（1/2/3…）不算实质内容，防止空表被序号列「骗活」。
  bool get isEmpty {
    if (rows.isEmpty) return true;
    bool no(String c) {
      final t = c.trim();
      return t.isEmpty || t == '无' || RegExp(r'^\d{1,3}$').hasMatch(t);
    }

    return rows.expand((r) => r).every(no);
  }

  /// 过滤掉全空行后的有效数据行。
  List<List<String>> get filledRows =>
      rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}

/// 待沟通协调问题（序号 / 事由 / 备注）。
class WeeklyIssue {
  final String no;
  final String subject;
  final String remark;

  const WeeklyIssue({
    required this.no,
    required this.subject,
    required this.remark,
  });

  bool get isEmpty => subject.trim().isEmpty && remark.trim().isEmpty;
}

/// 一份完整的周报素材。
class WeeklyReport {
  /// 项目名称（封面），如「腾讯深圳总部项目」。
  final String project;

  /// 汇报标题，如「项目东区现场工作汇报」。
  final String title;

  /// 汇报周期，如「2023-10-07 ~ 2023-10-13」。
  final String period;

  /// 编制单位，如「深总院」。
  final String org;

  /// 期数（可为空）。
  final String issue;

  /// 现场照片（按施工内容分组展示）。
  final List<WeeklyPhoto> photos;

  /// 施工进度行。
  final List<WeeklyProgressRow> progress;

  /// 台账类表格。
  final List<WeeklyLedger> ledgers;

  /// 待沟通协调问题。
  final List<WeeklyIssue> issues;

  /// 纯文字说明（如「设计交底及会审情况：本周无」）。
  final List<WeeklyNote> notes;

  /// 关联的巡场清单（报告末尾的巡场清单，由 APP 侧按项目注入）。
  final List<Defect> defects;

  const WeeklyReport({
    required this.project,
    required this.title,
    required this.period,
    required this.org,
    this.issue = '',
    this.photos = const [],
    this.progress = const [],
    this.ledgers = const [],
    this.issues = const [],
    this.notes = const [],
    this.defects = const [],
  });

  /// 有内容的待协调问题。
  List<WeeklyIssue> get filledIssues =>
      issues.where((e) => !e.isEmpty).toList();

  /// 照片按施工内容聚合，保持原始顺序（同一部位多张图归为一组）。
  List<WeeklyPhotoGroup> get photoGroups {
    final groups = <WeeklyPhotoGroup>[];
    for (final p in photos) {
      final key = p.caption.isEmpty ? '现场照片' : p.caption;
      if (groups.isNotEmpty &&
          groups.last.caption == key &&
          groups.last.date == p.date) {
        groups.last.photos.add(p);
      } else {
        groups.add(WeeklyPhotoGroup(
          caption: key,
          date: p.date,
          photos: [p],
        ));
      }
    }
    return groups;
  }

  WeeklyReport copyWithDefects(List<Defect> d) => WeeklyReport(
        project: project,
        title: title,
        period: period,
        org: org,
        issue: issue,
        photos: photos,
        progress: progress,
        ledgers: ledgers,
        issues: issues,
        notes: notes,
        defects: d,
      );
}

/// 照片分组：同一施工内容（+ 同一日期）下的多张现场照片。
class WeeklyPhotoGroup {
  final String caption;
  final String date;
  final List<WeeklyPhoto> photos;

  WeeklyPhotoGroup({
    required this.caption,
    required this.date,
    required this.photos,
  });
}

/// 纯文字板块（如设计交底及会审情况）。
class WeeklyNote {
  final String title;
  final String text;

  /// 来源 PPT 页码（1 起），用于跨板块排序。
  final int page;

  const WeeklyNote({required this.title, required this.text, this.page = 99});
}
