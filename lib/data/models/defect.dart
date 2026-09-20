/// 缺陷域模型。
///
/// 含四个正交的分级枚举（不要混用）：
/// - [DefectStatus]：处置流转状态（待整改 / 整改中 / 已销项 / 已拒绝）
/// - [DefectCategory]：专业分类（建筑 / 结构 / 装饰 / 给排水 / 暖通 / 电气 / 其他）
/// - [DefectSeverity]：严重程度 + 处置动作 + 规范分区色
/// - [DefectImportance]：重要等级（巡场报告单「重要等级」列）
///
/// 后端对应表：`defects`（当前态）+ `defect_events`（事件流 / 审计）。
library;

import 'package:flutter/material.dart';

import '../../core/utils/time_text.dart';
import '../sync_meta.dart';

enum DefectStatus { draft, doing, done, reject }

extension DefectStatusX on DefectStatus {
  String get label {
    switch (this) {
      case DefectStatus.draft:
        return '待整改';
      case DefectStatus.doing:
        return '整改中';
      case DefectStatus.done:
        return '已销项';
      case DefectStatus.reject:
        return '已拒绝';
    }
  }

  // 状态色**不放模型层**：唯一渲染方是问题清单的 `StatusPill._bg`（按设计稿取色）。
  // 原先此处另有一套 color/soft，无人使用且与 StatusPill 不一致，2026-09-18 删除。
}

/// 缺陷专业分类（7 类，**取值与 [Discipline] 的 code 对齐**）。
///
/// ⚠️ 这是**客户端投影**：真实专业清单由后端 `disciplines` 表维护
/// （可能扩到总图 / 景观 / 幕墙 / 智能化 / 室内…）。未知 code 由
/// [DefectCategory.fromCode] 回落 [other] —— 功能不崩，但**按专业过滤会失真**。
///
/// 因此约定：**扩展专业清单必须与客户端发版同步**。
/// （`Membership.disciplines` 用的是 String code，不受此限；受影响的只有缺陷自身的分类字段。）
enum DefectCategory {
  architecture,
  structure,
  decoration,
  water,
  hvac,
  electric,
  other;

  /// code（字符串）→ 枚举；未知 code 回落 [other]（不抛异常）。
  static DefectCategory fromCode(String? code) => values.firstWhere(
        (e) => e.name == code,
        orElse: () => other,
      );
}

extension DefectCategoryX on DefectCategory {
  String get label {
    switch (this) {
      case DefectCategory.architecture:
        return '建筑';
      case DefectCategory.structure:
        return '结构';
      case DefectCategory.decoration:
        return '装饰';
      case DefectCategory.water:
        return '给排水';
      case DefectCategory.hvac:
        return '暖通';
      case DefectCategory.electric:
        return '电气';
      case DefectCategory.other:
        return '其他';
    }
  }
}

/// 缺陷严重程度分级（红/橙/黄/绿 四通道，颜色体系不变）。
/// 文字用直白等级词（严重/较重/一般/轻微），避免"红区/橙区"等
/// 非标准说法让人看不懂；红=重要且紧急(停工+上报)、
/// 橙=重要不紧急(限期整改)、黄=紧急不重要(即改)、绿=不重要不紧急(观察)。
/// 重要等级（四象限），对齐 LDI 设计院巡场报告单「重要等级」列。
///
/// 与 [DefectSeverity]（处置优先级：停工→观察）互补：
/// severity 回答「多严重、怎么处置」，importance 回答「多急、要不要先办」。
enum DefectImportance {
  urgentImportant,
  importantNotUrgent,
  urgentNotImportant,
  normal,
}

extension DefectImportanceX on DefectImportance {
  String get label {
    switch (this) {
      case DefectImportance.urgentImportant:
        return '重要紧急';
      case DefectImportance.importantNotUrgent:
        return '重要不紧急';
      case DefectImportance.urgentNotImportant:
        return '紧急不重要';
      case DefectImportance.normal:
        return '普通';
    }
  }
}

enum DefectSeverity { red, orange, yellow, green }

extension DefectSeverityX on DefectSeverity {
  /// 显示名：直接描述严重程度，不依赖颜色。
  String get label {
    switch (this) {
      case DefectSeverity.red:
        return '严重';
      case DefectSeverity.orange:
        return '较重';
      case DefectSeverity.yellow:
        return '一般';
      case DefectSeverity.green:
        return '轻微';
    }
  }

  /// 处置动作（与分级框架对应）。
  String get action {
    switch (this) {
      case DefectSeverity.red:
        return '停工上报';
      case DefectSeverity.orange:
        return '限期整改';
      case DefectSeverity.yellow:
        return '即查即改';
      case DefectSeverity.green:
        return '常规观察';
    }
  }

  /// 严重程度文本色（规范分区色）：严重 #FF4444 / 较重 #FF9500 /
  /// 一般 #FF9500（与较重同橙，依设计稿 Frame 2147228012）/ 轻微 #34C759。
  /// **唯一事实源**：问题清单与记录详情页均取此处（2026-09-18 统一，原先两处各有一套色值）。
  Color get color {
    switch (this) {
      case DefectSeverity.red:
        return const Color(0xFFFF4444); // 严重
      case DefectSeverity.orange:
        return const Color(0xFFFF9500); // 较重
      case DefectSeverity.yellow:
        return const Color(0xFFFF9500); // 一般（与较重同橙）
      case DefectSeverity.green:
        return const Color(0xFF34C759); // 轻微
    }
  }
}

class Defect {
  final String id;

  /// 所属项目 id（对应后端 `defects.project_id`）。
  ///
  /// 缺陷按项目隔离，缺失会导致跨项目串数据；旧数据（无该字段）解析为空串。
  final String projectId;

  final String part;
  final String type;

  /// 专业分类（建筑/结构/装饰/给排水/暖通/电气/其他）。
  final DefectCategory category;

  /// 紧急/重要程度（红/橙/黄/绿）。
  final DefectSeverity severity;
  final DefectStatus status;
  final String anchor;
  final String floor;
  final String ts;
  final String gps;
  final String alt;

  /// 纬度（°N，数值）。`null` = 未采集（历史数据只有 [gps] 文本）。
  final double? lat;

  /// 经度（°E，数值）。`null` = 未采集。
  final double? lng;

  /// 责任人（责任单位 + 人），如 "深圳市建工集团 王工"。
  final String resp;

  /// 责任单位（拆分字段，便于单独展示）。
  final String respUnit;

  /// 责任用户 id（关联后端 `users`；[resp] 是展示用的冗余文本）。
  final String? respUserId;

  /// 记录人（谁发现/记录的）。
  final String reporter;

  /// 记录人用户 id（关联后端 `users`；[reporter] 是展示用的冗余文本）。
  final String? reporterId;

  /// 附加标签（自由标签，如 "二次结构"、"防火重点"、"总包责任"）。
  final List<String> tags;
  final String note;
  final String seed;

  /// 所属图纸 key（CAD 打点来源，可为空）。
  final String? drawingKey;

  /// 所属图纸版本（→ [DrawingVersion.id]）。
  ///
  /// **坐标绑版本**：空串表示该记录产生于版本化之前（历史/演示数据），
  /// 无法保证 [worldX]/[worldY] 指向正确的图面位置。
  final String drawingVersionId;

  /// 图纸坐标 X（mm，CAD 打点换算，用于图纸上回溯定位）。
  final double? worldX;

  /// 图纸坐标 Y（mm，CAD 打点换算，用于图纸上回溯定位）。
  final double? worldY;

  /// 关联照片相对路径列表（预留：多图场景；当前报告只读 [photoPath]，暂无消费方）。
  final List<String> photos;

  /// 来源拍照验收记录 id（从验收记录转入问题时填入该验收记录的 `entry.id`）；
  /// 为空表示非验收来源（图纸打点 / 手动录入等）。
  /// 与 [sourceCaptureIdx] 成对使用，可反查「该验收记录里第 i 条 AI 缺陷」的当前状态（DV-19 回流）。
  final String? sourceCaptureId;

  /// 来源验收记录中 AI 缺陷条目的下标（与 [sourceCaptureId] 成对）。
  /// 后端重建时对应 `defects.source_capture_id` + `defects.source_capture_index` 两列，
  /// 便于按 `source_capture_id` 建索引后 join 出回流状态。
  final int? sourceCaptureIdx;

  /// 现场照片相对路径（如 `photos/xxx.jpg`，由拍照记录流程写入本地存储）。
  /// 报告导出时按此路径读取照片字节内嵌到 PDF / Word / HTML。
  ///
  /// 本地路径；上传对象存储后后端只保留 `photo_file_id`。
  final String? photoPath;

  /// 现场照片内容哈希（SHA-256，十六进制）。取证链 + 对象存储去重的依据。
  final String? photoHash;

  /// 水印凭证号（烧录进照片流水，用于「照片不可篡改取证」回溯）。
  final String? watermarkSerial;

  /// 重要等级（巡场报告单「重要等级」列）。为空时按 [severity] 推导。
  final DefectImportance? importance;

  /// 楼栋 / 栋号（巡场销项表按此分组，如「9栋」「7栋、8栋」）。
  final String? building;

  /// 整改回复内容（施工单位回复 / 整改说明，对应巡场报告单「回复内容」）。
  final String? reply;

  /// 回复人（整改回复的责任方 / 回复单位）。
  final String? replyBy;

  /// 回复人用户 id（关联后端 `users`；[replyBy] 是展示用的冗余文本）。
  final String? replyById;

  /// 回复时间（格式同 [ts]）。
  final String? replyTs;

  /// 整改回复照片相对路径（整改后现场照片，对应「回复·截图」列）。
  final String? replyPhotoPath;

  /// 未闭合说明（对应巡场报告单「如未，填写意见」）。
  final String? closeNote;

  /// AI 整改建议（给施工单位的处置建议，AI 识别生成 / 人工修订）。
  final String? suggestion;

  /// 完成状态（对应巡场报告单「完成状态」，如 已完成 / 进行中 / 未开始）。
  final String? completion;

  /// 设计师处置动作：null=未处置 / remoteFix=远程已解决(销项) / remoteConfirm=远程已答复 / onsite=需到场。
  final String? designerAction;

  /// 设计师处置说明。
  final String? designerNote;

  /// 处置设计师（默认当前用户）。
  final String? designerBy;

  /// 处置设计师用户 id（关联后端 `users`；[designerBy] 是展示用的冗余文本）。
  final String? designerById;

  /// 设计师处置时间（格式同 [ts]）。
  final String? designerTs;

  /// 同步元数据（clientId / version / 时间戳 / 软删）。
  final SyncMeta sync;

  const Defect({
    required this.id,
    required this.projectId,
    required this.part,
    required this.type,
    required this.category,
    required this.severity,
    required this.status,
    required this.anchor,
    required this.floor,
    required this.ts,
    required this.gps,
    required this.alt,
    this.lat,
    this.lng,
    required this.resp,
    this.respUnit = '',
    this.respUserId,
    this.reporter = '现场记录',
    this.reporterId,
    this.tags = const [],
    required this.note,
    required this.seed,
    this.drawingKey,
    this.drawingVersionId = '',
    this.worldX,
    this.worldY,
    this.photos = const [],
    this.sourceCaptureId,
    this.sourceCaptureIdx,
    this.photoPath,
    this.photoHash,
    this.watermarkSerial,
    this.importance,
    this.building,
    this.reply,
    this.replyBy,
    this.replyById,
    this.replyTs,
    this.replyPhotoPath,
    this.closeNote,
    this.completion,
    this.suggestion,
    this.designerAction,
    this.designerNote,
    this.designerBy,
    this.designerById,
    this.designerTs,
    this.sync = const SyncMeta(),
  });

  /// 序列化（拍照/图纸打点新增记录的本地持久化用）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'part': part,
        'type': type,
        'category': category.name,
        'severity': severity.name,
        'status': status.name,
        'anchor': anchor,
        'floor': floor,
        'ts': ts,
        'gps': gps,
        'alt': alt,
        'lat': lat,
        'lng': lng,
        'resp': resp,
        'respUnit': respUnit,
        'respUserId': respUserId,
        'reporter': reporter,
        'reporterId': reporterId,
        'tags': tags,
        'note': note,
        'seed': seed,
        'drawingKey': drawingKey,
        'drawingVersionId': drawingVersionId,
        'worldX': worldX,
        'worldY': worldY,
        'photoPath': photoPath,
        'photoHash': photoHash,
        'watermarkSerial': watermarkSerial,
        'photos': photos,
        'sourceCaptureId': sourceCaptureId,
        'sourceCaptureIdx': sourceCaptureIdx,
        'importance': importance?.name,
        'building': building,
        'reply': reply,
        'replyBy': replyBy,
        'replyById': replyById,
        'replyTs': replyTs,
        'replyPhotoPath': replyPhotoPath,
        'closeNote': closeNote,
        'completion': completion,
        'suggestion': suggestion,
        // 设计师处置四件套：fromJson 一直在读，但原先 toJson 漏写 →
        // 本地持久化（added_defects_v1）再读回时处置结果会丢失（2026-09-18 修复）。
        'designerAction': designerAction,
        'designerNote': designerNote,
        'designerBy': designerBy,
        'designerById': designerById,
        'designerTs': designerTs,
        // 同步元数据平铺到顶层（clientUuid / version / 各时间戳 / 软删）。
        ...sync.toJson(),
      };

  /// 反序列化：缺字段给安全默认值（兼容旧数据），不抛错。
  factory Defect.fromJson(Map<String, dynamic> m) => Defect(
        id: m['id']?.toString() ?? '',
        projectId: m['projectId']?.toString() ?? '',
        part: m['part']?.toString() ?? '',
        type: m['type']?.toString() ?? '',
        category: DefectCategory.fromCode(m['category']?.toString()),
        severity: DefectSeverity.values.firstWhere(
            (e) => e.name == m['severity'],
            orElse: () => DefectSeverity.green),
        status: DefectStatus.values.firstWhere((e) => e.name == m['status'],
            orElse: () => DefectStatus.draft),
        anchor: m['anchor']?.toString() ?? '',
        floor: m['floor']?.toString() ?? '',
        ts: m['ts']?.toString() ?? '',
        gps: m['gps']?.toString() ?? '',
        alt: m['alt']?.toString() ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        resp: m['resp']?.toString() ?? '待指派',
        respUnit: m['respUnit']?.toString() ?? '',
        respUserId: m['respUserId']?.toString(),
        reporter: m['reporter']?.toString() ?? '现场记录',
        reporterId: m['reporterId']?.toString(),
        tags: (m['tags'] as List?)?.whereType<String>().toList() ?? const [],
        note: m['note']?.toString() ?? '',
        seed: m['seed']?.toString() ?? 'capture',
        drawingKey: m['drawingKey']?.toString(),
        drawingVersionId: m['drawingVersionId']?.toString() ?? '',
        worldX: (m['worldX'] as num?)?.toDouble(),
        worldY: (m['worldY'] as num?)?.toDouble(),
        photoPath: m['photoPath']?.toString(),
        photoHash: m['photoHash']?.toString(),
        watermarkSerial: m['watermarkSerial']?.toString(),
        photos: (m['photos'] as List?)?.whereType<String>().toList() ?? const [],
        sourceCaptureId: m['sourceCaptureId']?.toString(),
        sourceCaptureIdx: (m['sourceCaptureIdx'] as num?)?.toInt(),
        importance: DefectImportance.values
            .where((e) => e.name == m['importance'])
            .cast<DefectImportance?>()
            .firstOrNull,
        building: m['building']?.toString(),
        reply: m['reply']?.toString(),
        replyBy: m['replyBy']?.toString(),
        replyById: m['replyById']?.toString(),
        replyTs: m['replyTs']?.toString(),
        replyPhotoPath: m['replyPhotoPath']?.toString(),
        closeNote: m['closeNote']?.toString(),
        completion: m['completion']?.toString(),
        suggestion: m['suggestion']?.toString(),
        designerAction: m['designerAction']?.toString(),
        designerNote: m['designerNote']?.toString(),
        designerBy: m['designerBy']?.toString(),
        designerById: m['designerById']?.toString(),
        designerTs: m['designerTs']?.toString(),
        sync: SyncMeta.fromJson(m),
      );

  /// 未显式指定重要等级时按严重程度推导（红→重要紧急 … 绿→普通）。
  DefectImportance get effectiveImportance =>
      importance ??
      switch (severity) {
        DefectSeverity.red => DefectImportance.urgentImportant,
        DefectSeverity.orange => DefectImportance.importantNotUrgent,
        DefectSeverity.yellow => DefectImportance.urgentNotImportant,
        DefectSeverity.green => DefectImportance.normal,
      };

  /// 是否闭合（已销项视为闭合，对应巡场报告单「是否闭合」列）。
  bool get closed => status == DefectStatus.done;

  /// 是否"待设计师处置"：尚未有设计师处置动作且未闭合（供列表筛选）。
  bool get pendingDesignerDisposal =>
      designerAction == null && status != DefectStatus.done;

  /// 设计师处置动作的可读中文标签（null 返回空串）。
  String get designerActionLabel => switch (designerAction) {
        'remoteFix' => '远程已解决',
        'remoteConfirm' => '远程已答复',
        'onsite' => '需到场',
        _ => '',
      };

  /// 发现时间的规范时间戳（epoch ms）。给同步层 / 后端用；[ts] 文本解析失败返回 0。
  int get tsMs => msFromTsText(ts);

  /// 回复时间的规范时间戳（epoch ms）；未回复返回 null。
  int? get replyTsMs => replyTs == null ? null : msFromTsText(replyTs);

  /// 设计师处置时间的规范时间戳（epoch ms）；未处置返回 null。
  int? get designerTsMs => designerTs == null ? null : msFromTsText(designerTs);

  /// 复制并覆盖字段（处置 / 回复 / 人工修订等局部更新用；仅传需改的字段，null 保持原值）。
  ///
  /// 2026-09-18 扩展：补齐人工可编辑字段（`part`/`category`/`severity`/`note`/`respUnit`/
  /// `importance`/`photoPath`/`photos`/`sourceCaptureIdx`），供「详情页人工改分类 / 严重程度 / 描述」使用。
  ///
  /// 注意：`copyWith` **不会**自动递增 [sync] 版本；同步层在写库时显式传
  /// `sync: d.sync.touch()`。
  Defect copyWith({
    DefectStatus? status,
    String? part,
    DefectCategory? category,
    DefectSeverity? severity,
    String? note,
    String? resp,
    String? respUnit,
    String? respUserId,
    String? reporterId,
    double? lat,
    double? lng,
    String? building,
    DefectImportance? importance,
    String? photoPath,
    String? photoHash,
    String? watermarkSerial,
    List<String>? photos,
    int? sourceCaptureIdx,
    String? reply,
    String? replyBy,
    String? replyById,
    String? replyTs,
    String? replyPhotoPath,
    String? closeNote,
    String? completion,
    String? suggestion,
    String? designerAction,
    String? designerNote,
    String? designerBy,
    String? designerById,
    String? designerTs,
    SyncMeta? sync,
  }) =>
      Defect(
        id: id,
        projectId: projectId,
        part: part ?? this.part,
        type: type,
        category: category ?? this.category,
        severity: severity ?? this.severity,
        status: status ?? this.status,
        anchor: anchor,
        floor: floor,
        ts: ts,
        gps: gps,
        alt: alt,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        resp: resp ?? this.resp,
        respUnit: respUnit ?? this.respUnit,
        respUserId: respUserId ?? this.respUserId,
        reporter: reporter,
        reporterId: reporterId ?? this.reporterId,
        tags: tags,
        note: note ?? this.note,
        seed: seed,
        drawingKey: drawingKey,
        drawingVersionId: drawingVersionId,
        worldX: worldX,
        worldY: worldY,
        photoPath: photoPath ?? this.photoPath,
        photoHash: photoHash ?? this.photoHash,
        watermarkSerial: watermarkSerial ?? this.watermarkSerial,
        photos: photos ?? this.photos,
        sourceCaptureId: sourceCaptureId,
        sourceCaptureIdx: sourceCaptureIdx ?? this.sourceCaptureIdx,
        importance: importance ?? this.importance,
        building: building ?? this.building,
        reply: reply ?? this.reply,
        replyBy: replyBy ?? this.replyBy,
        replyById: replyById ?? this.replyById,
        replyTs: replyTs ?? this.replyTs,
        replyPhotoPath: replyPhotoPath ?? this.replyPhotoPath,
        closeNote: closeNote ?? this.closeNote,
        completion: completion ?? this.completion,
        suggestion: suggestion ?? this.suggestion,
        designerAction: designerAction ?? this.designerAction,
        designerNote: designerNote ?? this.designerNote,
        designerBy: designerBy ?? this.designerBy,
        designerById: designerById ?? this.designerById,
        designerTs: designerTs ?? this.designerTs,
        sync: sync ?? this.sync,
      );

  /// 楼栋分组名（未标注楼栋时回退到空串，由渲染端归到「其他」）。
  String get buildingOrEmpty => (building ?? '').trim();

  /// 是否有 CAD 图纸坐标（可回溯定位）。
  bool get hasCadCoord =>
      drawingKey != null && worldX != null && worldY != null;

  /// CAD 坐标文本（"X=… Y=…"），无坐标时返回 null。
  String? get coordText => hasCadCoord
      ? 'X=${worldX!.toStringAsFixed(1)}  Y=${worldY!.toStringAsFixed(1)}'
      : null;
}

