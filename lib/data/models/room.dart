/// 量房域模型（D4 量房记录）。
///
/// 墙段用**局部坐标系 2D 端点（mm）**表达，首尾相接构成闭合多边形；
/// 门窗洞口以「距墙段起点偏移」记录，便于按墙长重算编号。
/// 核尺结论 [RoomScanRecord.checks] 复用 [MeasureItem]，
/// **判定口径与量尺页同源**（门槛取 B7 项目级设置）。
///
/// 后端对应表：`room_scans`（`walls` / `checks` 以 JSONB 原样落库）。
library;

import 'dart:ui' show Offset;

import '../sync_meta.dart';
import 'measure.dart';

// ==================== 量房记录（docs/archive/MEASURE_ROOM_PLAN.md / ROOM_MEASURE_IMPL.md P0）====================

/// 墙段洞口（门/窗）：[offsetFromMm] 为距墙段起点偏移（mm）。
class WallOpening {
  final String type; // 'door' | 'window'
  final double offsetFromMm;
  final double widthMm;
  final double? heightMm; // 门高 / 窗台高（可空，人工补）
  const WallOpening({
    required this.type,
    required this.offsetFromMm,
    required this.widthMm,
    this.heightMm,
  });

  WallOpening copyWith({
    String? type,
    double? offsetFromMm,
    double? widthMm,
    double? heightMm,
  }) =>
      WallOpening(
        type: type ?? this.type,
        offsetFromMm: offsetFromMm ?? this.offsetFromMm,
        widthMm: widthMm ?? this.widthMm,
        heightMm: heightMm ?? this.heightMm,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'offsetFromMm': offsetFromMm,
        'widthMm': widthMm,
        'heightMm': heightMm,
      };

  factory WallOpening.fromJson(Map<String, dynamic> m) => WallOpening(
        type: m['type']?.toString() ?? 'door',
        offsetFromMm: (m['offsetFromMm'] as num? ?? 0).toDouble(),
        widthMm: (m['widthMm'] as num? ?? 0).toDouble(),
        heightMm: (m['heightMm'] as num?)?.toDouble(),
      );
}

/// 量房墙段：局部坐标系 2D 端点（mm）。
class RoomWall {
  final String id;
  final double ax, ay, bx, by; // 局部坐标 mm（首段起点=原点）
  /// 长度（mm）；RoomPlan 给值优先，手动成图可为 null → 用坐标自算。
  final double lengthMm; // 校正后长度（正交吸附后重算）
  final double? thicknessMm; // 墙厚（默认 200，人工可改）
  final List<WallOpening> openings;
  const RoomWall({
    required this.id,
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    required this.lengthMm,
    this.thicknessMm,
    this.openings = const [],
  });

  RoomWall copyWith({
    double? ax,
    double? ay,
    double? bx,
    double? by,
    double? lengthMm,
    double? thicknessMm,
    List<WallOpening>? openings,
  }) =>
      RoomWall(
        id: id,
        ax: ax ?? this.ax,
        ay: ay ?? this.ay,
        bx: bx ?? this.bx,
        by: by ?? this.by,
        lengthMm: lengthMm ?? this.lengthMm,
        thicknessMm: thicknessMm ?? this.thicknessMm,
        openings: openings ?? this.openings,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ax': ax,
        'ay': ay,
        'bx': bx,
        'by': by,
        'lengthMm': lengthMm,
        'thicknessMm': thicknessMm,
        'openings': openings.map((o) => o.toJson()).toList(),
      };

  factory RoomWall.fromJson(Map<String, dynamic> m) => RoomWall(
        id: m['id']?.toString() ?? '',
        ax: (m['ax'] as num? ?? 0).toDouble(),
        ay: (m['ay'] as num? ?? 0).toDouble(),
        bx: (m['bx'] as num? ?? 0).toDouble(),
        by: (m['by'] as num? ?? 0).toDouble(),
        lengthMm: (m['lengthMm'] as num? ?? 0).toDouble(),
        thicknessMm: (m['thicknessMm'] as num?)?.toDouble(),
        openings: (m['openings'] as List? ?? [])
            .map((e) => WallOpening.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 量房记录。
class RoomScanRecord {
  final String id;
  final String projectKey;
  final String name; // 房间名，如「主卧」
  final String roomUse; // 用途：卧室/客厅/厨房/卫浴/其他（装修场景）
  final String source; // 'roomplan' | 'manual' | 'photo'
  final int scannedAtMs;
  final List<RoomWall> walls; // 首尾相接（按顺序构成闭合多边形）
  final double? closureDeltaMm;
  final double? netHeightMm; // 净高 mm
  final String? drawingKey; // 核尺场景关联图纸

  /// 核尺所用图纸的版本（→ [DrawingVersion.id]）；空串 = 未版本化。
  final String drawingVersionId;
  final List<MeasureItem> checks; // 与图纸对照判定（复用 MeasureItem）
  final String? note;

  /// 同步元数据（clientId / version / 时间戳 / 软删）。
  final SyncMeta sync;
  const RoomScanRecord({
    required this.id,
    required this.projectKey,
    required this.name,
    this.roomUse = '其他',
    this.source = 'manual',
    required this.scannedAtMs,
    this.walls = const [],
    this.closureDeltaMm,
    this.netHeightMm,
    this.drawingKey,
    this.drawingVersionId = '',
    this.checks = const [],
    this.note,
    this.sync = const SyncMeta(),
  });

  /// 几何派生的只读值（不入库）
  List<Offset> get cornerPoints => [
        for (final w in walls) Offset(w.ax, w.ay),
        if (walls.isNotEmpty) Offset(walls.last.bx, walls.last.by),
      ];

  RoomScanRecord copyWith({
    String? name,
    String? roomUse,
    String? source,
    List<RoomWall>? walls,
    double? closureDeltaMm,
    double? netHeightMm,
    String? drawingKey,
    String? drawingVersionId,
    List<MeasureItem>? checks,
    String? note,
    SyncMeta? sync,
  }) =>
      RoomScanRecord(
        id: id,
        projectKey: projectKey,
        name: name ?? this.name,
        roomUse: roomUse ?? this.roomUse,
        source: source ?? this.source,
        scannedAtMs: scannedAtMs,
        walls: walls ?? this.walls,
        closureDeltaMm: closureDeltaMm ?? this.closureDeltaMm,
        netHeightMm: netHeightMm ?? this.netHeightMm,
        drawingKey: drawingKey ?? this.drawingKey,
        drawingVersionId: drawingVersionId ?? this.drawingVersionId,
        checks: checks ?? this.checks,
        note: note ?? this.note,
        sync: sync ?? this.sync,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectKey': projectKey,
        'name': name,
        'roomUse': roomUse,
        'source': source,
        'scannedAtMs': scannedAtMs,
        'walls': walls.map((w) => w.toJson()).toList(),
        'closureDeltaMm': closureDeltaMm,
        'netHeightMm': netHeightMm,
        'drawingKey': drawingKey,
        'drawingVersionId': drawingVersionId,
        'checks': checks.map((c) => c.toJson()).toList(),
        'note': note,
        ...sync.toJson(),
      };

  factory RoomScanRecord.fromJson(Map<String, dynamic> m) => RoomScanRecord(
        id: m['id']?.toString() ?? '',
        projectKey: m['projectKey']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        roomUse: m['roomUse']?.toString() ?? '其他',
        source: m['source']?.toString() ?? 'manual',
        scannedAtMs: (m['scannedAtMs'] as num? ?? 0).toInt(),
        walls: (m['walls'] as List? ?? [])
            .map((e) => RoomWall.fromJson(e as Map<String, dynamic>))
            .toList(),
        closureDeltaMm: (m['closureDeltaMm'] as num?)?.toDouble(),
        netHeightMm: (m['netHeightMm'] as num?)?.toDouble(),
        drawingKey: m['drawingKey']?.toString(),
        drawingVersionId: m['drawingVersionId']?.toString() ?? '',
        checks: (m['checks'] as List? ?? [])
            .map((e) => MeasureItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: m['note']?.toString(),
        sync: SyncMeta.fromJson(m),
      );
}

/// 量房页路由参数。
class RoomScanArgs {
  final String? recordId;
  final String? projectKey;
  final String? drawingKey;
  final String? drawingTitle;
  const RoomScanArgs({
    this.recordId,
    this.projectKey,
    this.drawingKey,
    this.drawingTitle,
  });
}
