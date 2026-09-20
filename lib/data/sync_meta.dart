import 'dart:math' as math;

/// 同步元数据：离线优先 + 增量同步所需的**公共列**。
///
/// 对应后端设计（`BACKEND_ARCHITECTURE.md` §7.2 公共列约定）：
/// `client_uuid` / `version` / `created_at` / `updated_at` /
/// `server_updated_at` / `deleted_at` / `created_by`。
///
/// 设计要点：
/// - **`clientUuid` 由客户端生成**：写入本地时即产生，push 时作为幂等键
///   （服务端对 `client_uuid` 建唯一索引），网络超时重发不会产生重复记录；
/// - `serverUpdatedAtMs` 由服务端回填，客户端只读（权威写入时间）；
/// - `deletedAtMs` 是软删标记（tombstone），`null` = 未删；
/// - 时间一律用 **epoch 毫秒（int）**，与后端 `timestamptz` 单向可换算，
///   避免字符串格式与时区歧义（历史模型里的 `ts` 仍是展示文本，见
///   `models.dart` 的 `msFromTsText`）。
///
/// 序列化形态：**平铺到宿主实体的顶层 JSON**（不嵌套），例如
/// `{...业务字段, "clientUuid": "...", "version": 1, ...}`，
/// 与后端列名一一对应，同步层无需再解一层。
class SyncMeta {
  /// 客户端生成的稳定标识（UUID v4）。空串 = 该记录尚未纳入同步（如预置演示数据）。
  final String clientUuid;

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
    this.clientUuid = '',
    this.version = 1,
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
    this.serverUpdatedAtMs,
    this.deletedAtMs,
    this.createdBy,
  });

  /// 新建一条待同步记录的元数据：生成 `clientUuid` 并记录创建/修改时间。
  factory SyncMeta.create({String? createdBy, int? nowMs}) {
    final t = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return SyncMeta(
      clientUuid: newUuidV4(),
      version: 1,
      createdAtMs: t,
      updatedAtMs: t,
      createdBy: createdBy,
    );
  }

  /// 是否尚未纳入同步（预置/演示数据，或旧数据缺字段）。
  bool get isNew => clientUuid.isEmpty;

  /// 是否已被软删。
  bool get isDeleted => deletedAtMs != null;

  /// 本地改动一次：版本 +1 并刷新本地修改时间。
  SyncMeta touch({int? nowMs}) => copyWith(
        version: version + 1,
        updatedAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
      );

  SyncMeta copyWith({
    String? clientUuid,
    int? version,
    int? createdAtMs,
    int? updatedAtMs,
    int? serverUpdatedAtMs,
    int? deletedAtMs,
    String? createdBy,
  }) =>
      SyncMeta(
        clientUuid: clientUuid ?? this.clientUuid,
        version: version ?? this.version,
        createdAtMs: createdAtMs ?? this.createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        serverUpdatedAtMs: serverUpdatedAtMs ?? this.serverUpdatedAtMs,
        deletedAtMs: deletedAtMs ?? this.deletedAtMs,
        createdBy: createdBy ?? this.createdBy,
      );

  /// 平铺序列化：直接展开进宿主实体的顶层 JSON。
  Map<String, dynamic> toJson() => {
        'clientUuid': clientUuid,
        'version': version,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'serverUpdatedAtMs': serverUpdatedAtMs,
        'deletedAtMs': deletedAtMs,
        'createdBy': createdBy,
      };

  /// 从宿主实体的顶层 JSON 读取；缺字段给安全默认值（兼容旧数据）。
  factory SyncMeta.fromJson(Map<String, dynamic> m) => SyncMeta(
        clientUuid: m['clientUuid']?.toString() ?? '',
        version: (m['version'] as num?)?.toInt() ?? 1,
        createdAtMs: (m['createdAtMs'] as num?)?.toInt() ?? 0,
        updatedAtMs: (m['updatedAtMs'] as num?)?.toInt() ?? 0,
        serverUpdatedAtMs: (m['serverUpdatedAtMs'] as num?)?.toInt(),
        deletedAtMs: (m['deletedAtMs'] as num?)?.toInt(),
        createdBy: m['createdBy']?.toString(),
      );

  /// 生成 UUID v4（RFC 4122）。
  ///
  /// 用 `Random.secure()` 手写，避免为单个工具函数引入 `uuid` 依赖。
  static String newUuidV4() {
    final rnd = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256), growable: false);
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
