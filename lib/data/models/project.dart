/// 项目档案域模型（B 类项目档案 + 现场辅助数据）。
///
/// 覆盖后台录入的项目侧数据：
/// - **B 类项目档案**：[Project]（B1 基本信息 + B2 地理位置）、[Party]（B3 五方参与方）、
///   [Milestone]（B4 里程碑）、[Floor]（B5 楼层）；
/// - **现场辅助**：[SiteLocation]（附近定位点 = 水印 GPS 的兜底来源）；
/// - **C4 回填**：[ProgressEntry]（施工进度回填，施工方免登录填报）。
///
/// 账号与组织（`Org` / `Discipline` / `User` / `Membership`）已拆到
/// `models/account.dart`——本文件**不再包含账号侧数据**。
///
/// 除 [ProgressEntry] 外均为**服务端维护、客户端只读**（走全量拉取覆盖，
/// 不带 [SyncMeta] 增量元数据）；[ProgressEntry] 是客户端可写实体，故带 `sync`。
///
/// 后端对应表：`projects` / `floors` / `site_locations` / `progress_entries`。
library;

import 'dart:math' as math;

import '../sync_meta.dart';

/// 项目参与方（甲方 / 设计院 / 监理 / 咨询 / PMO 等）。
///
/// **内嵌于 [Project.parties]**（随项目一起落库，无独立同步元数据）。
/// 它只是「展示用通讯录」；权限边界走 `Membership`（`models/account.dart`），
/// 两者不要混。
class Party {
  final String id; // ULID（便于后台按条维护）
  final String role; // 角色名，如 "甲方（业主方）"——自由文本，可扩展
  final String orgId; // → Org.id
  final String org; // 单位全称（展示冗余，渲染端不必 join）
  final String contact; // 对接人姓名（展示冗余）
  final String contactUserId; // → User.id（空串 = 未关联账号）
  final String title; // 对接人职务，如 "业主代表"
  const Party({
    this.id = '',
    required this.role,
    this.orgId = '',
    required this.org,
    required this.contact,
    this.contactUserId = '',
    required this.title,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'orgId': orgId,
        'org': org,
        'contact': contact,
        'contactUserId': contactUserId,
        'title': title,
      };

  factory Party.fromJson(Map<String, dynamic> m) => Party(
        id: m['id']?.toString() ?? '',
        role: m['role']?.toString() ?? '',
        orgId: m['orgId']?.toString() ?? '',
        org: m['org']?.toString() ?? '',
        contact: m['contact']?.toString() ?? '',
        contactUserId: m['contactUserId']?.toString() ?? '',
        title: m['title']?.toString() ?? '',
      );
}

/// 项目施工进度节点（关键里程碑，B4 后台录入）。
///
/// 它同时是**施工进度回填的框架**：施工方按节点提交 [ProgressEntry]（C4）。
/// `date` 语义固定为「计划日期」（不改名，避免波及首页时间轴与 mock）；
/// 实际完成看 [actualDate]。
class Milestone {
  final String id; // ULID（ProgressEntry 按它回填）
  final String name; // 节点名称，如 "主体结构封顶"
  final String date; // 计划日期，如 "2026-05-30"
  final String actualDate; // 实际完成日期；空串 = 未完成
  final bool done; // 是否已完成
  final bool current; // 是否为当前进行中的节点（高亮）
  const Milestone({
    this.id = '',
    required this.name,
    required this.date,
    this.actualDate = '',
    this.done = false,
    this.current = false,
  });

  /// 是否实质完成：显式标记 或 已填实际完成日期。
  bool get isDone => done || actualDate.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'date': date,
        'actualDate': actualDate,
        'done': done,
        'current': current,
      };

  /// `done` 缺省时由 [actualDate] 推导（后台只填计划 + 实际日期即可）。
  factory Milestone.fromJson(Map<String, dynamic> m) {
    final actual = m['actualDate']?.toString() ?? '';
    return Milestone(
      id: m['id']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      date: m['date']?.toString() ?? '',
      actualDate: actual,
      done: m.containsKey('done')
          ? m['done'] == true
          : actual.isNotEmpty,
      current: m['current'] == true,
    );
  }
}

/// 项目（B1 基本信息 + B2 地理位置）。
///
/// 档案类：由后台录入、客户端只读、全量拉取覆盖。
class Project {
  final String id; // 项目唯一标识（多项目切换用）
  final String name;
  final String client;
  final String location; // 项目地址文本（展示 + 后台地理编码前的原始输入）
  final String status;
  final String siteArea;
  final String floorArea;
  final int beds;
  final String concept;

  /// 项目坐标（B2）。**照片水印 GPS 的兜底来源**：
  /// 优先设备定位 → 无信号时用项目坐标 → 再退化到手选附近定位点。
  final double? lat;
  final double? lng;

  /// 参与方列表（甲方 / 设计院 / 监理 / 咨询 / PMO）。
  final List<Party> parties;

  /// 施工进度里程碑（项目时间轴数据源）。
  final List<Milestone> milestones;
  const Project({
    required this.id,
    required this.name,
    required this.client,
    required this.location,
    required this.status,
    required this.siteArea,
    required this.floorArea,
    required this.beds,
    required this.concept,
    this.lat,
    this.lng,
    this.parties = const [],
    this.milestones = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'client': client,
        'location': location,
        'status': status,
        'siteArea': siteArea,
        'floorArea': floorArea,
        'beds': beds,
        'concept': concept,
        'lat': lat,
        'lng': lng,
        'parties': parties.map((p) => p.toJson()).toList(),
        'milestones': milestones.map((m) => m.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> m) => Project(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        client: m['client']?.toString() ?? '',
        location: m['location']?.toString() ?? '',
        status: m['status']?.toString() ?? '',
        siteArea: m['siteArea']?.toString() ?? '',
        floorArea: m['floorArea']?.toString() ?? '',
        beds: (m['beds'] as num?)?.toInt() ?? 0,
        concept: m['concept']?.toString() ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        parties: (m['parties'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Party.fromJson(e.cast<String, dynamic>()))
            .toList(),
        milestones: (m['milestones'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Milestone.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

/// 一条施工进度回填（C4，施工方免登录填报）。
///
/// **一律标注「施工方自报」**（[source] 固定 [sourceContractor]）：
/// 填报人身份不可证，报告里不得表述成设计院核实结论。
class ProgressEntry {
  /// 数据来源：施工方自报（唯一取值，保留字段以便将来接入监理复核）。
  static const String sourceContractor = 'contractor';

  /// 填报状态。
  static const String statusNotStarted = 'not_started';
  static const String statusInProgress = 'in_progress';
  static const String statusDone = 'done';
  static const String statusDelayed = 'delayed';

  final String id; // ULID
  final String projectId;
  final String milestoneId; // → Milestone.id（B4 是回填框架）
  final String status; // 见上方 status* 常量
  final String date; // 填报日期 / 实际日期，`yyyy-MM-dd`
  final String note;
  final List<String> photos; // 现场照片本地相对路径（上传后为对象存储 key）
  final String declaredBy; // 填报人姓名（免登录，仅姓名）

  /// 数据来源，见 [sourceContractor]。
  final String source;

  /// 同步元数据（可写实体）。
  final SyncMeta sync;
  const ProgressEntry({
    required this.id,
    required this.projectId,
    required this.milestoneId,
    this.status = statusInProgress,
    this.date = '',
    this.note = '',
    this.photos = const [],
    this.declaredBy = '',
    this.source = sourceContractor,
    this.sync = const SyncMeta(),
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'milestoneId': milestoneId,
        'status': status,
        'date': date,
        'note': note,
        'photos': photos,
        'declaredBy': declaredBy,
        'source': source,
        ...sync.toJson(),
      };

  factory ProgressEntry.fromJson(Map<String, dynamic> m) => ProgressEntry(
        id: m['id']?.toString() ?? '',
        projectId: m['projectId']?.toString() ?? '',
        milestoneId: m['milestoneId']?.toString() ?? '',
        status: m['status']?.toString() ?? statusInProgress,
        date: m['date']?.toString() ?? '',
        note: m['note']?.toString() ?? '',
        photos: (m['photos'] as List?)?.whereType<String>().toList() ?? const [],
        declaredBy: m['declaredBy']?.toString() ?? '',
        source: m['source']?.toString() ?? sourceContractor,
        sync: SyncMeta.fromJson(m),
      );
}

/// 附近定位点（工程水印相机风格）：项目 / 地标 + 地址 + GPS + 海拔。
/// 用户在拍照前可从附近定位点列表中选择一个作为水印定位信息。
class SiteLocation {
  final String id;

  /// 地点名称（如项目名 / 工地名）。
  final String name;

  /// 详细地址。
  final String address;

  /// 纬度（°N）。
  final double lat;

  /// 经度（°E）。
  final double lng;

  /// 海拔（m）。
  final double altitude;

  /// 关联项目 id（可空）。
  final String? projectId;
  const SiteLocation({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.altitude,
    this.projectId,
  });

  /// 水印显示用的 GPS 文本（与 CAD 模块纬度在前一致）。
  String get gpsText =>
      '${lat.toStringAsFixed(4)}°N ${lng.toStringAsFixed(4)}°E';

  /// 与另一个定位点的粗略距离（km，球面余弦）。用于"附近"排序/提示。
  double distanceKmTo(SiteLocation other) {
    const r = 6371.0;
    final dLat = (other.lat - lat) * 3.141592653589793 / 180;
    final dLng = (other.lng - lng) * 3.141592653589793 / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat * 3.141592653589793 / 180) *
            math.cos(other.lat * 3.141592653589793 / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'altitude': altitude,
        'projectId': projectId,
      };

  factory SiteLocation.fromJson(Map<String, dynamic> j) => SiteLocation(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        address: j['address'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        altitude: (j['altitude'] as num?)?.toDouble() ?? 0,
        projectId: j['projectId'] as String?,
      );
}

/// 楼层（B5 后台录入 / 由图名解析）。
///
/// 档案类：客户端只读。注意 [cached] / [progress] 是**客户端本地缓存态**
/// （图纸是否已下载），不属于后台数据 —— 因此 [toJson] 有意**不输出**它们
/// （缓存进度由 `floorCacheProvider` 单独管理）。
class Floor {
  final String key;
  final String projectId; // 所属项目（多项目隔离的必要条件）
  final String name;
  final int index;
  final bool cached; // 本地缓存态，不入库
  final int progress; // 本地缓存进度 0~100，不入库
  final String building; // 楼栋，如「7栋」
  final String floor; // 楼层号，如「B1」
  const Floor({
    required this.key,
    this.projectId = '',
    required this.name,
    required this.index,
    required this.cached,
    required this.progress,
    required this.building,
    required this.floor,
  });

  /// 仅输出后台字段（不含本地缓存态）。
  Map<String, dynamic> toJson() => {
        'key': key,
        'projectId': projectId,
        'name': name,
        'index': index,
        'building': building,
        'floor': floor,
      };

  /// `cached` / `progress` 不入库，读回按「未缓存」处理（由 pageCacheProvider 覆盖）。
  factory Floor.fromJson(Map<String, dynamic> m) => Floor(
        key: m['key']?.toString() ?? '',
        projectId: m['projectId']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        index: (m['index'] as num?)?.toInt() ?? 0,
        cached: false,
        progress: 0,
        building: m['building']?.toString() ?? '',
        floor: m['floor']?.toString() ?? '',
      );
}
