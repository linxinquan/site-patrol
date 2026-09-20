/// 拍照验收域模型（D1 验收记录 + 图纸打点）。
///
/// [CaptureRecord] 是本地文档 `stored_vision_results` 元素结构的**唯一**定义：
/// 写入方 `toJson()`、读取方 `fromJson()` 共用，不再散落「裸 Map 约定」。
/// [CaptureDefectItem] 与 [VlDefect] 字段平铺一致，多一个 `status`
/// （是否已转入问题清单），保证历史数据可直接读回。
///
/// 后端对应表：`captures`（`ai_result` / `confirmed_result` 分别对应
/// [CaptureRecord.defects] 与其中的转入状态）。
library;

import '../../core/utils/time_text.dart';
import '../sync_meta.dart';
import 'defect.dart';

class TimelinePhoto {
  final String date;
  final String state; // before / mid / after
  final String caption;
  final bool verified;

  /// 图片路径：本地存储相对路径，或 assets 资源路径。
  final String? imagePath;

  /// 是否为 assets 资源图。false 时按本地存储文件读取。
  final bool isAsset;
  const TimelinePhoto({
    required this.date,
    required this.state,
    required this.caption,
    required this.verified,
    this.imagePath,
    this.isAsset = false,
  });
}

/// 拍照验收入口来源：区分普通验收进入，还是巡场里的快捷标记进入。
enum CaptureEntrySource {
  /// 默认入口：TabBar / 首页 / 图纸页等常规进入方式。
  standard,

  /// 巡场入口：从“标记问题”快捷带入当前图纸和当前位置。
  patrol,
}

/// 拍照验收路由参数：楼层 + 预锚定部位 + 相对坐标（0~1） + 可选图纸坐标。
class CaptureArgs {
  /// 所属项目 ID（无项目时按 currentProjectIdProvider 推断）。
  final String? projectId;

  /// 当前入口来源：用于区分巡场快捷标记和普通验收的 UI 与后续动作。
  final CaptureEntrySource source;
  final String floor;
  final String anchorLabel;
  final double x;
  final double y;

  /// 若从图纸打点跳转：关联的图纸 key；拍照记录时一并写入缺陷
  /// （真实坐标由 drawPointWorldX/drawPointWorldY 提供）。
  final String? drawingKey;
  final double? drawPointWorldX;
  final double? drawPointWorldY;
  const CaptureArgs({
    this.projectId,
    this.source = CaptureEntrySource.standard,
    this.floor = '',
    this.anchorLabel = '',
    this.x = 0.5,
    this.y = 0.5,
    this.drawingKey,
    this.drawPointWorldX,
    this.drawPointWorldY,
  });
}

/// VL 识别的缺陷结果。
class VlDefect {
  final String name;
  final DefectSeverity severity;
  final double conf;

  /// 缺陷描述（真实模型返回；mock 阶段为空）。
  final String? desc;

  /// AI 整改建议（给施工单位的处置建议；模型未返回时由本地建议库兜底）。
  final String? suggestion;
  const VlDefect({
    required this.name,
    required this.severity,
    required this.conf,
    this.desc,
    this.suggestion,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'severity': severity.name,
        'conf': conf,
        'desc': desc,
        'suggestion': suggestion,
      };

  factory VlDefect.fromJson(Map<String, dynamic> map) => VlDefect(
        name: map['name']?.toString() ?? '',
        severity: DefectSeverity.values.firstWhere(
          (s) => s.name == map['severity'],
          orElse: () => DefectSeverity.orange,
        ),
        conf: (map['conf'] as num?)?.toDouble() ?? 0.0,
        desc: map['desc']?.toString(),
        suggestion: map['suggestion']?.toString(),
      );
}

/// 拍照验收记录里的一条 AI 缺陷条目（`stored_vision_results` 文档元素的一部分）。
///
/// 与 [VlDefect] 的关系：字段相同（name/severity/conf/desc/suggestion），
/// 额外多一个流转状态 [status]（是否已转入问题清单）。
/// **存储形态与 [VlDefect.toJson] 平铺一致**（多一个 `status` 键），
/// 因此历史数据可直接读回，不需要迁移。
class CaptureDefectItem {
  /// 未转入问题清单。
  static const String statusPending = 'pending';

  /// 已转入问题清单（问题清单里已生成对应 [Defect]）。
  static const String statusConverted = 'converted';

  final String name;
  final DefectSeverity severity;
  final double conf;

  /// 缺陷描述（真实模型返回；mock 阶段为空）。
  final String? desc;

  /// AI 整改建议。
  final String? suggestion;

  /// 流转状态：[statusPending] / [statusConverted]。
  final String status;

  const CaptureDefectItem({
    required this.name,
    required this.severity,
    required this.conf,
    this.desc,
    this.suggestion,
    this.status = statusPending,
  });

  /// 由 AI 识别结果构造（默认未转入）。
  factory CaptureDefectItem.fromVlDefect(VlDefect v, {String status = statusPending}) =>
      CaptureDefectItem(
        name: v.name,
        severity: v.severity,
        conf: v.conf,
        desc: v.desc,
        suggestion: v.suggestion,
        status: status,
      );

  /// 还原为 AI 识别结果（用于「转入问题清单」时构造 [Defect]）。
  VlDefect toVlDefect() => VlDefect(
        name: name,
        severity: severity,
        conf: conf,
        desc: desc,
        suggestion: suggestion,
      );

  bool get isConverted => status == statusConverted;

  CaptureDefectItem copyWith({
    String? name,
    DefectSeverity? severity,
    double? conf,
    String? desc,
    String? suggestion,
    String? status,
  }) =>
      CaptureDefectItem(
        name: name ?? this.name,
        severity: severity ?? this.severity,
        conf: conf ?? this.conf,
        desc: desc ?? this.desc,
        suggestion: suggestion ?? this.suggestion,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'severity': severity.name,
        'conf': conf,
        'desc': desc,
        'suggestion': suggestion,
        'status': status,
      };

  /// 旧数据缺字段一律给默认值（`severity` 缺失回落 orange，与历史行为一致）。
  factory CaptureDefectItem.fromJson(Map<String, dynamic> m) => CaptureDefectItem(
        name: m['name']?.toString() ?? '',
        severity: DefectSeverity.values.firstWhere(
          (s) => s.name == m['severity'],
          orElse: () => DefectSeverity.orange,
        ),
        conf: (m['conf'] as num?)?.toDouble() ?? 0.0,
        desc: m['desc']?.toString(),
        suggestion: m['suggestion']?.toString(),
        status: m['status']?.toString() ?? statusPending,
      );
}

/// 一条拍照验收记录（`LocalStorage` 文档 `stored_vision_results` 的元素）。
///
/// 这是**唯一**的落库形态定义：写入方用 [toJson]，读取方用 [fromJson]，
/// 不再散落「裸 Map 约定」。对应后端 `captures` 表
/// （`project_id` / `drawing_id` / `floor` / `anchor` / `photo_file_id` /
/// `ai_result` / `confirmed_result` / `reporter_id`）。
///
/// 与后端语义对照：
/// - [defects] 是 AI 原始识别结果（后端 `ai_result`），
///   条目上的 [CaptureDefectItem.status] 是**人工确认/转入**的结果
///   （后端 `confirmed_result` 的一部分）；
/// - [photo] 是本地相对路径；上传对象存储后后端只保留 `photo_file_id`。
class CaptureRecord {
  /// 记录 id（历史数据为 `microsecondsSinceEpoch` 字符串）。
  final String id;

  /// 所属项目 id（旧数据为空串，转入问题清单时可用当前项目兜底）。
  final String projectId;

  /// 所属图纸 key（图纸打点来源）。
  final String drawingKey;

  /// 所属图纸版本（→ [DrawingVersion.id]）；空串 = 未版本化。
  final String drawingVersionId;

  /// 图纸坐标 X（mm）；[drawingKey] 非空且已校准时才有意义。
  final double? worldX;

  /// 图纸坐标 Y（mm）。
  final double? worldY;

  /// 记录时间（展示文本，`yyyy-MM-dd HH:mm:ss`）。
  final String ts;

  /// 部位（锚点标签）。
  final String anchor;

  /// 楼层。
  final String floor;

  /// AI 识别到的缺陷条目（含各自的转入状态）。
  final List<CaptureDefectItem> defects;

  /// 用户手写的问题描述。
  final String note;

  /// 水印照片的本地相对路径；无照片为 null。
  final String? photo;

  /// GPS 文本（水印同款，如 `22.5936°N 113.9798°E`）。
  final String gps;

  /// 海拔文本（如 `海拔 18.2m`）。
  final String alt;

  /// 记录人（展示用姓名）。
  final String reporter;

  /// 同步元数据。
  final SyncMeta sync;

  const CaptureRecord({
    required this.id,
    this.projectId = '',
    this.drawingKey = '',
    this.drawingVersionId = '',
    this.worldX,
    this.worldY,
    required this.ts,
    this.anchor = '',
    this.floor = '',
    this.defects = const [],
    this.note = '',
    this.photo,
    this.gps = '',
    this.alt = '',
    this.reporter = '',
    this.sync = const SyncMeta(),
  });

  /// AI 缺陷条数（历史 JSON 里的 `count` 字段由此派生，不再单独存储）。
  int get count => defects.length;

  /// 是否识别到 AI 缺陷（未识别到也留痕，用于「仅 AI」筛选）。
  bool get hasDefects => defects.isNotEmpty;

  /// 未转入问题清单的条目数。
  int get pendingCount => defects.where((d) => !d.isConverted).length;

  /// 记录时间的规范时间戳（epoch ms）。给同步层 / 后端用。
  int get tsMs => msFromTsText(ts);

  CaptureRecord copyWith({
    String? projectId,
    String? drawingKey,
    String? drawingVersionId,
    double? worldX,
    double? worldY,
    String? ts,
    String? anchor,
    String? floor,
    List<CaptureDefectItem>? defects,
    String? note,
    String? photo,
    String? gps,
    String? alt,
    String? reporter,
    SyncMeta? sync,
  }) =>
      CaptureRecord(
        id: id,
        projectId: projectId ?? this.projectId,
        drawingKey: drawingKey ?? this.drawingKey,
        drawingVersionId: drawingVersionId ?? this.drawingVersionId,
        worldX: worldX ?? this.worldX,
        worldY: worldY ?? this.worldY,
        ts: ts ?? this.ts,
        anchor: anchor ?? this.anchor,
        floor: floor ?? this.floor,
        defects: defects ?? this.defects,
        note: note ?? this.note,
        photo: photo ?? this.photo,
        gps: gps ?? this.gps,
        alt: alt ?? this.alt,
        reporter: reporter ?? this.reporter,
        sync: sync ?? this.sync,
      );

  /// 覆盖指定条目的流转状态（转入问题清单成功后调用）。
  CaptureRecord withDefectStatus(int idx, String status) {
    if (idx < 0 || idx >= defects.length) return this;
    return copyWith(
      defects: [
        for (var i = 0; i < defects.length; i++)
          i == idx ? defects[i].copyWith(status: status) : defects[i],
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'drawingKey': drawingKey,
        'drawingVersionId': drawingVersionId,
        'worldX': worldX,
        'worldY': worldY,
        'ts': ts,
        'anchor': anchor,
        'floor': floor,
        'count': count,
        'defects': defects.map((d) => d.toJson()).toList(),
        'note': note,
        'photo': photo,
        'gps': gps,
        'alt': alt,
        'reporter': reporter,
        ...sync.toJson(),
      };

  /// 旧数据读取一律给默认值，缺字段不抛错。
  factory CaptureRecord.fromJson(Map<String, dynamic> m) => CaptureRecord(
        id: m['id']?.toString() ?? '',
        projectId: m['projectId']?.toString() ?? '',
        drawingKey: m['drawingKey']?.toString() ?? '',
        drawingVersionId: m['drawingVersionId']?.toString() ?? '',
        worldX: (m['worldX'] as num?)?.toDouble(),
        worldY: (m['worldY'] as num?)?.toDouble(),
        ts: m['ts']?.toString() ?? '',
        anchor: m['anchor']?.toString() ?? '',
        floor: m['floor']?.toString() ?? '',
        defects: (m['defects'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => CaptureDefectItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
        note: m['note']?.toString() ?? '',
        photo: _emptyToNull(m['photo']),
        gps: m['gps']?.toString() ?? '',
        alt: m['alt']?.toString() ?? '',
        reporter: m['reporter']?.toString() ?? '',
        sync: SyncMeta.fromJson(m),
      );

  static String? _emptyToNull(dynamic v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }
}

