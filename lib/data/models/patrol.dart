/// 巡场域模型（C5 路线模板 + D5 巡场记录 + D6 检查点打卡）。
///
/// 坐标体系：路线点用 **0~100 相对坐标**（与 `lib/utils/path_metrics.dart`
/// 的绘制/插值算法一致），经图纸校准换算真实里程。
/// 一次巡场 = 一个 [PatrolPlan]（模板）+ 一条 [PatrolRecord]（本次结果）。
///
/// 后端对应表：`patrol_plans`（`points` JSONB）+ `patrol_records`
/// （`track` / `checkins` JSONB）。
library;

import '../sync_meta.dart';

// ==================== 巡场 ====================

/// 巡场路线点（相对坐标 0~100，绑定图纸）。isCheckpoint=true 为检查点。
class PatrolPoint {
  final double dx; // 0~100（对应整图宽度的百分比）
  final double dy; // 0~100
  final bool isCheckpoint;
  const PatrolPoint({
    required this.dx,
    required this.dy,
    this.isCheckpoint = false,
  });

  PatrolPoint copyWith({double? dx, double? dy, bool? isCheckpoint}) =>
      PatrolPoint(
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        isCheckpoint: isCheckpoint ?? this.isCheckpoint,
      );

  Map<String, dynamic> toJson() =>
      {'dx': dx, 'dy': dy, 'isCheckpoint': isCheckpoint};

  /// 旧数据读取一律给默认值，缺字段不抛错。
  factory PatrolPoint.fromJson(Map<String, dynamic> m) => PatrolPoint(
        dx: (m['dx'] as num?)?.toDouble() ?? 0,
        dy: (m['dy'] as num?)?.toDouble() ?? 0,
        isCheckpoint: m['isCheckpoint'] == true,
      );
}

/// 巡场路线（一条路线绑定一张图纸、一个项目）。
class PatrolPlan {
  final String id;
  final String projectId;
  final String drawingKey;

  /// 所属图纸版本（→ [DrawingVersion.id]）；空串 = 未版本化。
  final String drawingVersionId;
  final String name; // 如 "B1 地下车库巡场路线"
  final String floor; // 如 "B1"
  final List<PatrolPoint> points;
  final double? totalKm; // 手动填写的兜底里程（图纸未校准时用）；校准后自动算
  final int updatedAt;

  /// 同步元数据（clientId / version / 时间戳 / 软删）。
  final SyncMeta sync;
  const PatrolPlan({
    required this.id,
    required this.projectId,
    required this.drawingKey,
    this.drawingVersionId = '',
    required this.name,
    required this.floor,
    required this.points,
    this.totalKm,
    this.updatedAt = 0,
    this.sync = const SyncMeta(),
  });

  /// 检查点下标（指向 [points]）。
  List<int> get checkpointIdxs => [
        for (var i = 0; i < points.length; i++)
          if (points[i].isCheckpoint) i
      ];

  PatrolPlan copyWith({
    String? drawingVersionId,
    String? name,
    String? floor,
    List<PatrolPoint>? points,
    double? totalKm,
    int? updatedAt,
    SyncMeta? sync,
  }) =>
      PatrolPlan(
        id: id,
        projectId: projectId,
        drawingKey: drawingKey,
        drawingVersionId: drawingVersionId ?? this.drawingVersionId,
        name: name ?? this.name,
        floor: floor ?? this.floor,
        points: points ?? this.points,
        totalKm: totalKm ?? this.totalKm,
        updatedAt: updatedAt ?? this.updatedAt,
        sync: sync ?? this.sync,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'drawingKey': drawingKey,
        'drawingVersionId': drawingVersionId,
        'name': name,
        'floor': floor,
        'points': points.map((p) => p.toJson()).toList(),
        'totalKm': totalKm,
        'updatedAt': updatedAt,
        ...sync.toJson(),
      };

  /// 旧数据读取一律给默认值，缺字段不抛错。
  factory PatrolPlan.fromJson(Map<String, dynamic> m) => PatrolPlan(
        id: m['id'] as String? ?? '',
        projectId: m['projectId'] as String? ?? '',
        drawingKey: m['drawingKey'] as String? ?? '',
        drawingVersionId: m['drawingVersionId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        floor: m['floor'] as String? ?? '',
        points: (m['points'] as List? ?? [])
            .map((e) => PatrolPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalKm: (m['totalKm'] as num?)?.toDouble(),
        updatedAt: (m['updatedAt'] as num? ?? 0).toInt(),
        sync: SyncMeta.fromJson(m),
      );
}

/// 巡场检查点打卡（任务2：检查点打卡制）。[pointIdx] 对应 PatrolPlan.points 下标。
class CheckIn {
  final int pointIdx; // 对应 PatrolPlan.points 下标
  final int tsMs; // 打卡时间（ms）
  final String? note; // 备注（可空）
  const CheckIn({required this.pointIdx, required this.tsMs, this.note});

  CheckIn copyWith({int? pointIdx, int? tsMs, String? note}) => CheckIn(
        pointIdx: pointIdx ?? this.pointIdx,
        tsMs: tsMs ?? this.tsMs,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() =>
      {'pointIdx': pointIdx, 'tsMs': tsMs, 'note': note};

  /// 旧数据读取缺字段一律给默认值，不抛错。
  factory CheckIn.fromJson(Map<String, dynamic> m) => CheckIn(
        pointIdx: (m['pointIdx'] as num?)?.toInt() ?? 0,
        tsMs: (m['tsMs'] as num?)?.toInt() ?? 0,
        note: m['note'] as String?,
      );
}

/// 一次巡场记录（⑦历史用）。
class PatrolRecord {
  final String id;
  final String planId;
  final String projectId;
  final String drawingKey;

  /// 所属图纸版本（→ [DrawingVersion.id]）；空串 = 未版本化。
  final String drawingVersionId;
  final String name;
  final int startedAt; // ms
  final int finishedAt; // ms
  final double distKm; // 实际里程（GPS 或按进度估算）
  final int pointCount; // 采样点数
  final int issueCount; // 标记问题数
  final List<Map<String, double>> track; // GPS 轨迹 [{lat,lng,ts}]
  // 任务2：检查点打卡记录（按打卡先后顺序追加，一个点一次）。
  final List<CheckIn> checkins;
  // 任务2：路线检查点总数（达成率分母，= 对应 PatrolPlan.checkpointIdxs.length）。
  final int checkpointTotal;

  /// 同步元数据（clientId / version / 时间戳 / 软删）。
  final SyncMeta sync;
  const PatrolRecord({
    required this.id,
    required this.planId,
    required this.projectId,
    required this.drawingKey,
    this.drawingVersionId = '',
    required this.name,
    required this.startedAt,
    required this.finishedAt,
    required this.distKm,
    required this.pointCount,
    required this.issueCount,
    this.track = const [],
    this.checkins = const [],
    this.checkpointTotal = 0,
    this.sync = const SyncMeta(),
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'planId': planId,
        'projectId': projectId,
        'drawingKey': drawingKey,
        'drawingVersionId': drawingVersionId,
        'name': name,
        'startedAt': startedAt,
        'finishedAt': finishedAt,
        'distKm': distKm,
        'pointCount': pointCount,
        'issueCount': issueCount,
        'track': track,
        'checkins': checkins.map((c) => c.toJson()).toList(),
        'checkpointTotal': checkpointTotal,
        ...sync.toJson(),
      };

  /// 旧数据读取一律给默认值，缺字段不抛错。
  factory PatrolRecord.fromJson(Map<String, dynamic> m) => PatrolRecord(
        id: m['id'] as String? ?? '',
        planId: m['planId'] as String? ?? '',
        projectId: m['projectId'] as String? ?? '',
        drawingKey: m['drawingKey'] as String? ?? '',
        drawingVersionId: m['drawingVersionId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        startedAt: (m['startedAt'] as num? ?? 0).toInt(),
        finishedAt: (m['finishedAt'] as num? ?? 0).toInt(),
        distKm: (m['distKm'] as num? ?? 0).toDouble(),
        pointCount: (m['pointCount'] as num? ?? 0).toInt(),
        issueCount: (m['issueCount'] as num? ?? 0).toInt(),
        track: (m['track'] as List? ?? [])
            .whereType<Map>()
            .map((e) =>
                e.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())))
            .toList(),
        checkins: (m['checkins'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CheckIn.fromJson)
            .toList(),
        checkpointTotal: (m['checkpointTotal'] as num? ?? 0).toInt(),
        sync: SyncMeta.fromJson(m),
      );
}


/// 巡场页路由参数（照 MeasureArgs 模式）。
class PatrolArgs {
  final String? planId;
  const PatrolArgs({this.planId});
}
