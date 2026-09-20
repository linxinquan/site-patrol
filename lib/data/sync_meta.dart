import '../core/utils/ids.dart';

/// 同步元数据：离线优先写入所需的**公共列**。
///
/// 对应后端设计中的公共列语义：`client_id` / `version` / `created_at` /
/// `updated_at` / `server_updated_at` / `deleted_at` / `created_by`。
///
/// 设计要点：
/// - **`clientId` 由客户端生成**：写入本地时即产生，push 时作为幂等键
///   （服务端建唯一索引），网络超时重发不会产生重复记录；
/// - `serverUpdatedAtMs` 由服务端回填，客户端只读（权威写入时间）；
/// - `deletedAtMs` 是软删标记（tombstone），`null` = 未删；
/// - 时间一律用 **epoch 毫秒（int）**，与后端 `timestamptz` 单向可换算，
///   避免字符串格式与时区歧义（历史模型里的 `ts` 仍是展示文本，见
///   `models.dart` 的 `msFromTsText`）。
///
/// **只给「客户端可写」的实体挂本类型**（缺陷 / 验收记录 / 量尺会话 / 量房 /
/// 巡场计划与记录 / 报告归档 / 施工进度）。
/// 项目、用户、组织、图纸、楼层等**档案类由服务端维护、客户端只读**，
/// 走「全量拉取覆盖」，不需要本类型（数据量极小，增量同步得不偿失）。
///
/// 序列化形态：**平铺到宿主实体的顶层 JSON**（不嵌套），例如
/// `{...业务字段, "clientId": "...", "version": 1, ...}`，后端列名一一对应，
/// 同步层无需再解一层。
class SyncMeta {
  /// 客户端生成的稳定标识（**ULID 文本，26 位**）。空串 = 该记录尚未纳入同步
  /// （如预置演示数据 / 历史数据）。
  final String clientId;

  /// 版本号：每次本地写入 +1（服务端据此识别更新）。
  final int version;

  /// 本地创建时间（epoch ms）。
  final int createdAtMs;

  /// 本地最后修改时间（epoch ms，客户端时钟，**不可信**，仅展示/参考）。
  final int updatedAtMs;

  /// 服务端写入时间（epoch ms，权威）。客户端本地写时为 null。
  final int? serverUpdatedAtMs;

  /// 软删时间（epoch ms）；null = 未删。
  final int? deletedAtMs;

  /// 创建者用户 id（展示用姓名不入此字段）。
  final String? createdBy;

  const SyncMeta({
    this.clientId = '',
    this.version = 1,
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
    this.serverUpdatedAtMs,
    this.deletedAtMs,
    this.createdBy,
  });

  /// 新建一条待同步记录的元数据：生成 `clientId` 并记录创建/修改时间。
  factory SyncMeta.create({String? createdBy, int? nowMs}) {
    final t = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return SyncMeta(
      clientId: newId(nowMs: t),
      version: 1,
      createdAtMs: t,
      updatedAtMs: t,
      createdBy: createdBy,
    );
  }

  /// 是否尚未纳入同步（预置/演示数据，或旧数据缺字段）。
  bool get isNew => clientId.isEmpty;

  /// 是否已被软删。
  bool get isDeleted => deletedAtMs != null;

  /// 本地改动一次：版本 +1 并刷新本地修改时间。
  SyncMeta touch({int? nowMs}) => copyWith(
        version: version + 1,
        updatedAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
      );

  SyncMeta copyWith({
    String? clientId,
    int? version,
    int? createdAtMs,
    int? updatedAtMs,
    int? serverUpdatedAtMs,
    int? deletedAtMs,
    String? createdBy,
  }) =>
      SyncMeta(
        clientId: clientId ?? this.clientId,
        version: version ?? this.version,
        createdAtMs: createdAtMs ?? this.createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        serverUpdatedAtMs: serverUpdatedAtMs ?? this.serverUpdatedAtMs,
        deletedAtMs: deletedAtMs ?? this.deletedAtMs,
        createdBy: createdBy ?? this.createdBy,
      );

  /// 平铺序列化：直接展开进宿主实体的顶层 JSON。
  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'version': version,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'serverUpdatedAtMs': serverUpdatedAtMs,
        'deletedAtMs': deletedAtMs,
        'createdBy': createdBy,
      };

  /// 从宿主实体的顶层 JSON 读取；缺字段给安全默认值（兼容旧数据）。
  factory SyncMeta.fromJson(Map<String, dynamic> m) => SyncMeta(
        clientId: m['clientId']?.toString() ?? '',
        version: (m['version'] as num?)?.toInt() ?? 1,
        createdAtMs: (m['createdAtMs'] as num?)?.toInt() ?? 0,
        updatedAtMs: (m['updatedAtMs'] as num?)?.toInt() ?? 0,
        serverUpdatedAtMs: (m['serverUpdatedAtMs'] as num?)?.toInt(),
        deletedAtMs: (m['deletedAtMs'] as num?)?.toInt(),
        createdBy: m['createdBy']?.toString(),
      );
}
