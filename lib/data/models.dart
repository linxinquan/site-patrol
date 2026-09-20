import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'sync_meta.dart';

export 'sync_meta.dart';

/// 数据模型（mock 阶段用纯 Dart 类；接真实 API 时再补 freezed / json_serializable）。

/// 文本时间 → epoch 毫秒（0 = 解析失败 / 空）。
///
/// 兼容本项目历史格式（`yyyy-MM-dd HH:mm`、`yyyy-MM-dd HH:mm:ss`）与 ISO 8601。
/// 用于给同步层 / 后端把展示用文本时间换算成规范时间戳（不抛异常）。
int msFromTsText(String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return 0;
  final iso = t.contains('T') ? t : t.replaceFirst(' ', 'T');
  return DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0;
}

/// 容错取 double（非数值 → 0）。
///
/// 写成**顶层函数**是必要的：类内若存在名为 `num` 的字段（如 [Hotspot]），
/// 会在类作用域内遮蔽 `num` 类型，导致 `as num?` 无法编译。
double _asDouble(dynamic v) => v is num ? v.toDouble() : 0;

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

/// 缺陷专业分类（7 类）。
enum DefectCategory {
  architecture,
  structure,
  decoration,
  water,
  hvac,
  electric,
  other
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

/// 组织 / 单位（A1 后台录入，客户端只读）。
///
/// 第一版只需 4~6 条（本院 / 监理 / 施工 / 总包 / 甲方），**不做部门树**。
/// [type] 用字符串 code 而非 enum —— 缺陷分类、单位类型这类带「设计院专属语义」
/// 的枚举必须在数据里可扩展，否则将来做平民化产品要迁移。
class Org {
  /// 建议的单位类型取值（非穷举，数据里可扩展）。
  static const String typeOwner = 'owner'; // 甲方 / 业主
  static const String typeDesign = 'design'; // 设计院（LDI）
  static const String typeSupervision = 'supervision'; // 监理 / 全过程咨询
  static const String typeContractor = 'contractor'; // 施工 / 总包
  static const String typeConsulting = 'consulting'; // 第三方咨询 / PMO
  static const String typeOther = 'other';

  final String id; // ULID / 服务端下发
  final String name; // 全称，如「深圳市建筑设计研究总院」
  final String shortName; // 简称，如「深总院」（水印 / 清单用短名）
  final String type; // 见上方 type* 常量
  final int sort;
  const Org({
    required this.id,
    required this.name,
    this.shortName = '',
    this.type = typeOther,
    this.sort = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shortName': shortName,
        'type': type,
        'sort': sort,
      };

  factory Org.fromJson(Map<String, dynamic> m) => Org(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        shortName: m['shortName']?.toString() ?? '',
        type: m['type']?.toString() ?? typeOther,
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );
}

/// 项目成员关系（A2 用户账号 + B6 项目成员与角色）。
///
/// 承载两件事：① App 端「登录后能看到哪些项目」的唯一依据；
/// ② 权限边界的挂载点。权限判定**只认权限点，不认角色**——
/// 角色是数据（可后台新增而不发版），代码只硬编码 [permissions] 里的权限点。
class Membership {
  /// 系统预置角色 code（业务角色名单确定后由后台添加，客户端不写死判断）。
  static const String roleProjectManager = 'project_manager';
  static const String roleSiteEngineer = 'site_engineer';
  static const String roleDisciplineLead = 'discipline_lead';
  static const String roleViewer = 'viewer';

  /// 稳定权限点（业务动作）——代码只判断这些，不判断角色。
  static const String permDefectCreate = 'defect.create';
  static const String permDefectReply = 'defect.reply';
  static const String permDefectClose = 'defect.close';
  static const String permDefectAssign = 'defect.assign';
  static const String permPatrolRun = 'patrol.run';
  static const String permMeasureWrite = 'measure.write';
  static const String permReportExport = 'report.export';
  static const String permDrawingManage = 'drawing.manage';
  static const String permMemberManage = 'member.manage';

  /// 成员状态。
  static const String statusActive = 'active'; // 已加入
  static const String statusInvited = 'invited'; // 已邀请未接受
  static const String statusDisabled = 'disabled'; // 已停用

  final String id;
  final String userId; // → User.id
  final String projectId; // → Project.id
  final String roleCode; // 见上方 role* 常量
  final String roleName; // 展示冗余（角色名由后台维护）
  final List<String> permissions; // 见上方 perm* 常量
  final String status; // 见上方 status* 常量

  /// 同步元数据（可写实体）。
  final SyncMeta sync;
  const Membership({
    required this.id,
    required this.userId,
    required this.projectId,
    this.roleCode = roleViewer,
    this.roleName = '',
    this.permissions = const [],
    this.status = statusActive,
    this.sync = const SyncMeta(),
  });

  /// 是否拥有某个权限点。
  bool can(String permission) => permissions.contains(permission);

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'projectId': projectId,
        'roleCode': roleCode,
        'roleName': roleName,
        'permissions': permissions,
        'status': status,
        ...sync.toJson(),
      };

  factory Membership.fromJson(Map<String, dynamic> m) => Membership(
        id: m['id']?.toString() ?? '',
        userId: m['userId']?.toString() ?? '',
        projectId: m['projectId']?.toString() ?? '',
        roleCode: m['roleCode']?.toString() ?? roleViewer,
        roleName: m['roleName']?.toString() ?? '',
        permissions:
            (m['permissions'] as List?)?.whereType<String>().toList() ?? const [],
        status: m['status']?.toString() ?? statusActive,
        sync: SyncMeta.fromJson(m),
      );
}

/// 项目参与方（甲方 / 设计院 / 监理 / 咨询 / PMO 等）。
///
/// **内嵌于 [Project.parties]**（随项目一起落库，无独立同步元数据）。
/// 它只是「展示用通讯录」；权限边界走 [Membership]，两者不要混。
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

/// 系统用户（参与方代表）。
///
/// 档案类：由后台建号下发，客户端只读（头像切换/身份展示）。
/// [role] 是**展示用**的岗位描述；真正的权限看 [Membership.permissions]。
class User {
  /// 账号状态。
  static const String statusActive = 'active';
  static const String statusInvited = 'invited';
  static const String statusDisabled = 'disabled';

  final String id;
  final String name; // 姓名，如 "欧阳嘉"
  final String orgId; // → Org.id
  final String org; // 单位（展示冗余），如 "Arcadis（凯迪思）"
  final String role; // 岗位描述（展示用），如 "全过程咨询 / PMO"
  final String avatar; // 头像路径（assets 或对象存储 key）
  final String phone;
  final String email;
  final String status; // 见上方 status* 常量
  const User({
    required this.id,
    required this.name,
    this.orgId = '',
    required this.org,
    required this.role,
    required this.avatar,
    this.phone = '',
    this.email = '',
    this.status = statusActive,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'orgId': orgId,
        'org': org,
        'role': role,
        'avatar': avatar,
        'phone': phone,
        'email': email,
        'status': status,
      };

  factory User.fromJson(Map<String, dynamic> m) => User(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        orgId: m['orgId']?.toString() ?? '',
        org: m['org']?.toString() ?? '',
        role: m['role']?.toString() ?? '',
        avatar: m['avatar']?.toString() ?? '',
        phone: m['phone']?.toString() ?? '',
        email: m['email']?.toString() ?? '',
        status: m['status']?.toString() ?? statusActive,
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

/// 图纸热点（底图上的可点区域）。
///
/// **内嵌于 [DrawingVersion.hotspots]**：热点是坐标，必须随版本走。
class Hotspot {
  final int num;
  final String label;
  final String target;
  final double x; // 0~1 相对坐标
  final double y; // 0~1 相对坐标
  const Hotspot({
    required this.num,
    required this.label,
    required this.target,
    required this.x,
    required this.y,
  });

  Map<String, dynamic> toJson() =>
      {'num': num, 'label': label, 'target': target, 'x': x, 'y': y};

  factory Hotspot.fromJson(Map<String, dynamic> m) {
    // 注意：本类有名为 `num` 的字段，会在类作用域内遮蔽 `num` 类型，
    // 因此这里不能写 `as num?`，改用顶层容错取值函数。
    return Hotspot(
      num: _asDouble(m['num']).toInt(),
      label: m['label']?.toString() ?? '',
      target: m['target']?.toString() ?? '',
      x: _asDouble(m['x']),
      y: _asDouble(m['y']),
    );
  }
}

/// 图纸（C1，版本身份）。
///
/// **版本化的核心约定**：本类只承载「图纸身份」与**当前发布版本的冗余快照**；
/// 权威数据在 [DrawingVersion]（底图尺寸、热点、校准都随版本走）。
/// 冗余字段（[src] / [w] / [h] / [hotspots]）由服务端按 `publishedVersionId`
/// join 回填，客户端渲染代码可直接用，不必改。
class Drawing {
  final String key; // 本地业务 key（后台建表时作为 external key）
  final String projectId; // 所属项目（多项目隔离的必要条件）
  final String title;
  final String crumb; // 面包屑，如「7栋 详图」
  final String variant; // 图纸类型，如 detail / plan
  final String discipline; // 专业，如 建筑 / 结构 / 机电（自由文本，可扩展）
  final String src; // 冗余快照：当前发布版本底图（assets 路径或对象存储 key）
  final double w; // 冗余快照：底图像素宽
  final double h; // 冗余快照：底图像素高
  final List<Hotspot> hotspots; // 冗余快照：当前发布版本热点

  /// 当前发布版本（→ [DrawingVersion.id]）。
  /// 空串 = 尚未版本化（预置演示图 / 后台未发布）。
  final String publishedVersionId;
  final int sort; // 列表排序

  /// 若为 CAD/OCF 图纸，标记对应 OCF 缓存 key（如 `dy04_7_B01`）。
  /// ⚠️ CAD 链路已判废案，待整体剥离。
  final String? cadOcfKey;
  const Drawing({
    required this.key,
    this.projectId = '',
    required this.title,
    required this.crumb,
    required this.variant,
    this.discipline = '',
    required this.src,
    required this.w,
    required this.h,
    required this.hotspots,
    this.publishedVersionId = '',
    this.sort = 0,
    this.cadOcfKey,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'projectId': projectId,
        'title': title,
        'crumb': crumb,
        'variant': variant,
        'discipline': discipline,
        // 冗余快照也一并输出：后端可直接落库，客户端也能脱离版本表渲染。
        'src': src,
        'w': w,
        'h': h,
        'hotspots': hotspots.map((e) => e.toJson()).toList(),
        'publishedVersionId': publishedVersionId,
        'sort': sort,
        'cadOcfKey': cadOcfKey,
      };

  factory Drawing.fromJson(Map<String, dynamic> m) => Drawing(
        key: m['key']?.toString() ?? '',
        projectId: m['projectId']?.toString() ?? '',
        title: m['title']?.toString() ?? '',
        crumb: m['crumb']?.toString() ?? '',
        variant: m['variant']?.toString() ?? '',
        discipline: m['discipline']?.toString() ?? '',
        src: m['src']?.toString() ?? '',
        w: (m['w'] as num?)?.toDouble() ?? 0,
        h: (m['h'] as num?)?.toDouble() ?? 0,
        hotspots: (m['hotspots'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Hotspot.fromJson(e.cast<String, dynamic>()))
            .toList(),
        publishedVersionId: m['publishedVersionId']?.toString() ?? '',
        sort: (m['sort'] as num?)?.toInt() ?? 0,
        cadOcfKey: m['cadOcfKey']?.toString(),
      );
}

/// 图纸版本（C1）——**本次改造的关键**。
///
/// 规则（与需求文档一致）：
/// - 改版走「发布」动作：旧版本 [state] 置 `archived` 并锁只读；
/// - **不做自动坐标迁移**（算法不可靠且不可解释），改版后提示驻场重锚；
/// - 底图、尺寸、热点、校准**全部绑版本**（[Calibration.drawingVersionId]）。
class DrawingVersion {
  /// 版本状态。
  static const String stateDraft = 'draft'; // 已上传未发布
  static const String statePublished = 'published'; // 已发布（当前生效）
  static const String stateArchived = 'archived'; // 已归档（旧版，只读）

  final String id; // ULID
  final String drawingKey; // → Drawing.key
  final String version; // 版本号，**必填**，如 'V1.0'
  final String versionDate; // 版本日期，`yyyy-MM-dd`
  final String state; // 见上方 state* 常量
  final String baseImagePath; // 底图（本地相对路径 / 对象存储 key）
  final double width; // 底图像素宽（权威）
  final double height; // 底图像素高（权威）
  final String? bounds; // CAD 坐标范围 'xmin,ymin,xmax,ymax'（mm）
  final List<Hotspot> hotspots; // 热点随版本走（坐标）
  final int publishedAtMs; // 发布时间（epoch ms）
  final String? publishedBy; // 发布人 → User.id
  const DrawingVersion({
    required this.id,
    required this.drawingKey,
    required this.version,
    this.versionDate = '',
    this.state = stateDraft,
    this.baseImagePath = '',
    this.width = 0,
    this.height = 0,
    this.bounds,
    this.hotspots = const [],
    this.publishedAtMs = 0,
    this.publishedBy,
  });

  bool get isPublished => state == statePublished;

  Map<String, dynamic> toJson() => {
        'id': id,
        'drawingKey': drawingKey,
        'version': version,
        'versionDate': versionDate,
        'state': state,
        'baseImagePath': baseImagePath,
        'width': width,
        'height': height,
        'bounds': bounds,
        'hotspots': hotspots.map((e) => e.toJson()).toList(),
        'publishedAtMs': publishedAtMs,
        'publishedBy': publishedBy,
      };

  factory DrawingVersion.fromJson(Map<String, dynamic> m) => DrawingVersion(
        id: m['id']?.toString() ?? '',
        drawingKey: m['drawingKey']?.toString() ?? '',
        version: m['version']?.toString() ?? '',
        versionDate: m['versionDate']?.toString() ?? '',
        state: m['state']?.toString() ?? stateDraft,
        baseImagePath: m['baseImagePath']?.toString() ?? '',
        width: (m['width'] as num?)?.toDouble() ?? 0,
        height: (m['height'] as num?)?.toDouble() ?? 0,
        bounds: m['bounds']?.toString(),
        hotspots: (m['hotspots'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Hotspot.fromJson(e.cast<String, dynamic>()))
            .toList(),
        publishedAtMs: (m['publishedAtMs'] as num?)?.toInt() ?? 0,
        publishedBy: m['publishedBy']?.toString(),
      );
}

/// 图纸坐标校准（C2）——**必须绑版本**。
///
/// [map] 是仿射系数（`viewWidth` / `viewHeight` / `a`..`f`），
/// 由 `CadCoordMapper.fromCalibrationMap` 解析；[raw] 保留浏览器导出的原始 JSON，
/// 便于下次打开校准弹窗预填。
///
/// ⚠️ 与 [PhotoCalib] 区分：本类是**图纸级**（像素 ↔ 毫米世界坐标），
/// [PhotoCalib] 是**照片级**（照片内参考物标定）。
class Calibration {
  final String drawingKey; // → Drawing.key
  final String drawingVersionId; // ⚠️ 坐标绑版本
  final String? raw; // 浏览器原始校准 JSON（可空）
  final Map<String, dynamic> map; // 仿射系数
  final int updatedAtMs;
  const Calibration({
    required this.drawingKey,
    this.drawingVersionId = '',
    this.raw,
    this.map = const {},
    this.updatedAtMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'drawingKey': drawingKey,
        'drawingVersionId': drawingVersionId,
        'raw': raw,
        'map': map,
        'updatedAtMs': updatedAtMs,
      };

  factory Calibration.fromJson(Map<String, dynamic> m) => Calibration(
        drawingKey: m['drawingKey']?.toString() ?? '',
        drawingVersionId: m['drawingVersionId']?.toString() ?? '',
        raw: m['raw']?.toString(),
        map: (m['map'] as Map?)?.cast<String, dynamic>() ?? const {},
        updatedAtMs: (m['updatedAtMs'] as num?)?.toInt() ?? 0,
      );
}

class AnchorPhoto {
  final String file;
  final String date;
  final String caption;
  const AnchorPhoto({
    required this.file,
    required this.date,
    required this.caption,
  });
}

class PhotoAnchor {
  final String id;
  final double x;
  final double y;
  final String label;
  final String? labelPos;
  final List<AnchorPhoto> photos;
  const PhotoAnchor({
    required this.id,
    required this.x,
    required this.y,
    required this.label,
    this.labelPos,
    required this.photos,
  });
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
        category: DefectCategory.values.firstWhere(
            (e) => e.name == m['category'],
            orElse: () => DefectCategory.other),
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

/// 拍照量尺校对：一张照片内对某一构件，实测尺寸 vs 图纸标注尺寸的比对。
class ScaleCheck {
  final String name; // 量尺项，如「梁宽」「墙厚」
  final double measuredMm; // 现场量尺实测值（mm）
  final double drawingMm; // 图纸标注值（mm）
  const ScaleCheck({
    required this.name,
    required this.measuredMm,
    required this.drawingMm,
  });

  /// 偏差 = 实测 - 图纸（mm）
  double get deviation => measuredMm - drawingMm;

  /// 偏差率 = 偏差 / 图纸（%）
  double get deviationPct => drawingMm == 0 ? 0 : deviation / drawingMm * 100;

  /// 是否合格：偏差绝对值 <= 容差
  bool pass(double tolMm, double tolPct) =>
      deviation.abs() <= tolMm && deviationPct.abs() <= tolPct;

  ScaleCheck copyWith({String? name, double? measuredMm, double? drawingMm}) =>
      ScaleCheck(
        name: name ?? this.name,
        measuredMm: measuredMm ?? this.measuredMm,
        drawingMm: drawingMm ?? this.drawingMm,
      );
}

// ==================== 半自动标定测量（拍照量尺校对 V2）====================
// 设计见 docs/archive/MEASURE_FEATURE_PLAN.md：图纸侧量距（CAD 校准）+ 照片侧量距（参考物标定）
// + 逐项校对（图纸 mm vs 实测 mm，双容差判定）。

/// 照片侧量距的一次标定：以已知尺寸参考物（卷尺/标准块）标定照片上的像素比例。
/// 存储参考物两端点完整像素坐标（2D），mm/px 用 2D 欧氏距离计算。
class PhotoCalib {
  final double refMm; // 参考物真实尺寸（mm）
  final double ax; // 起点像素 x（整图坐标系，0..imgW）
  final double ay; // 起点像素 y（整图坐标系，0..imgH）
  final double bx; // 终点像素 x
  final double by; // 终点像素 y
  final double imgW; // 照片整图像素宽
  final double imgH; // 照片整图像素高

  /// 平面单应（图像像素 → 被测平面 mm，行主序 9 元素）。
  ///
  /// 由「模数网格 ≥4 点」标定得到：相当于把斜拍画面矫正为正视图后再量距，
  /// 消除两点比例法在斜拍下的透视失真（倾角越大/越远，失真越大）。
  /// null = 未做单应标定，量距回退两点比例法（旧行为，向后兼容旧会话）。
  final List<double>? homography;

  /// 单应标定残差（mm，控制点最大偏差）。
  /// 仅 ≥5 个控制点时才有意义——4 点是精确解，残差恒为 0，不代表精度高。
  final double? homographyResidualMm;

  /// 单应标定的已知网格跨度（mm），仅用于显示（如「600×600 网格 9 点」）。
  final double? calibWidthMm;
  final double? calibHeightMm;

  /// 单应标定所用控制点数（0 = 未做单应标定）。
  final int calibPoints;

  const PhotoCalib({
    required this.refMm,
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    required this.imgW,
    this.imgH = 0,
    this.homography,
    this.homographyResidualMm,
    this.calibWidthMm,
    this.calibHeightMm,
    this.calibPoints = 0,
  });

  /// 是否已做单应（透视校正）标定。
  bool get hasHomography => homography != null && homography!.length == 9;

  /// 参考物像素跨度（2D 欧氏距离，px）。
  double get spanPx => math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));

  /// 照片像素比例（mm/px）：参考物尺寸 / 像素跨度（2D）。
  double get mmPerPx => spanPx <= 1e-6 ? 0 : refMm / spanPx;

  PhotoCalib copyWith({
    double? refMm,
    double? ax,
    double? ay,
    double? bx,
    double? by,
    double? imgW,
    double? imgH,
    List<double>? homography,
    double? homographyResidualMm,
    double? calibWidthMm,
    double? calibHeightMm,
    int? calibPoints,
  }) =>
      PhotoCalib(
        refMm: refMm ?? this.refMm,
        ax: ax ?? this.ax,
        ay: ay ?? this.ay,
        bx: bx ?? this.bx,
        by: by ?? this.by,
        imgW: imgW ?? this.imgW,
        imgH: imgH ?? this.imgH,
        homography: homography ?? this.homography,
        homographyResidualMm: homographyResidualMm ?? this.homographyResidualMm,
        calibWidthMm: calibWidthMm ?? this.calibWidthMm,
        calibHeightMm: calibHeightMm ?? this.calibHeightMm,
        calibPoints: calibPoints ?? this.calibPoints,
      );

  /// 新格式序列化。
  Map<String, dynamic> toJson() => {
        'refMm': refMm,
        'ax': ax,
        'ay': ay,
        'bx': bx,
        'by': by,
        'imgW': imgW,
        'imgH': imgH,
        if (homography != null) 'homography': homography,
        if (homographyResidualMm != null) 'hResidualMm': homographyResidualMm,
        if (calibWidthMm != null) 'calibW': calibWidthMm,
        if (calibHeightMm != null) 'calibH': calibHeightMm,
        if (calibPoints > 0) 'calibPts': calibPoints,
      };

  /// 兼容旧格式（仅 {refMm, pixA, pixB, imgW}）：旧数据 ay=by=0，
  /// 退化为水平距离计算，与旧版行为一致，不抛异常。
  factory PhotoCalib.fromJson(Map<String, dynamic> m) {
    final pixA = (m['pixA'] as num?)?.toDouble();
    final pixB = (m['pixB'] as num?)?.toDouble();
    return PhotoCalib(
      refMm: (m['refMm'] as num?)?.toDouble() ?? 0,
      ax: (m['ax'] as num?)?.toDouble() ?? pixA ?? 0,
      ay: (m['ay'] as num?)?.toDouble() ?? 0,
      bx: (m['bx'] as num?)?.toDouble() ?? pixB ?? 0,
      by: (m['by'] as num?)?.toDouble() ?? 0,
      imgW: (m['imgW'] as num?)?.toDouble() ?? 0,
      imgH: (m['imgH'] as num?)?.toDouble() ?? 0,
      homography: _parseHomography(m['homography']),
      homographyResidualMm: (m['hResidualMm'] as num?)?.toDouble(),
      calibWidthMm: (m['calibW'] as num?)?.toDouble(),
      calibHeightMm: (m['calibH'] as num?)?.toDouble(),
      calibPoints: (m['calibPts'] as num?)?.toInt() ?? 0,
    );
  }

  /// 容错解析单应矩阵：非 9 元素 / 含非数值 → 视为未标定（null），不抛异常。
  static List<double>? _parseHomography(dynamic raw) {
    if (raw is! List || raw.length != 9) return null;
    final out = <double>[];
    for (final v in raw) {
      if (v is! num) return null;
      out.add(v.toDouble());
    }
    return out;
  }
}

/// 校对清单中的一项：图纸侧量得值 vs 照片侧量得值。
class MeasureItem {
  final String name; // 量尺项，如「梁宽」「墙厚」
  final double drawingMm; // 图纸侧量得（CAD 校准后，mm）
  final double photoMm; // 照片侧量得（参考物标定后，mm）
  /// 测量来源：'photo' 默认（照片标尺法）| 'ar_lidar'（AR量尺）| 'manual'。
  /// 旧会话数据无该字段时按 'photo' 处理，保证向后兼容。
  final String source;

  /// 测量误差带半宽（±mm）。LiDAR/AR 等有误差来源时填写；
  /// 旧数据 / 手动录入为 null = 误差未知（不参与判定门控，pass() 逻辑不变）。
  final double? errorMm;
  const MeasureItem({
    required this.name,
    required this.drawingMm,
    required this.photoMm,
    this.source = 'photo',
    this.errorMm,
  });

  /// 偏差 = 照片实测 - 图纸（mm）
  double get deviation => photoMm - drawingMm;

  /// 偏差率 = 偏差 / 图纸（%）
  double get deviationPct => drawingMm == 0 ? 0 : deviation / drawingMm * 100;

  /// 是否合格：偏差绝对值 <= 容差
  bool pass(double tolMm, double tolPct) =>
      deviation.abs() <= tolMm && deviationPct.abs() <= tolPct;

  /// 判定可用性（测量不确定度规约）：测量误差带应 ≤ 容差的 1/3，
  /// 否则实测值与容差边界不可分，报"合格/超差"不可信，应提示复核。
  /// 误差未知（null）或误差过大 → 不可判定。
  bool canJudge(double tolMm) =>
      errorMm != null && errorMm! > 0 && errorMm! <= tolMm / 3;

  MeasureItem copyWith(
          {String? name,
          double? drawingMm,
          double? photoMm,
          String? source,
          double? errorMm}) =>
      MeasureItem(
        name: name ?? this.name,
        drawingMm: drawingMm ?? this.drawingMm,
        photoMm: photoMm ?? this.photoMm,
        source: source ?? this.source,
        errorMm: errorMm ?? this.errorMm,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'drawingMm': drawingMm,
        'photoMm': photoMm,
        'source': source,
        if (errorMm != null) 'errorMm': errorMm,
      };

  /// 字段名与 `MeasureSession` 既有内联序列化保持一致（name/drawingMm/photoMm/source），
  /// 新增 `errorMm` 缺省为 null，旧数据不抛异常。
  factory MeasureItem.fromJson(Map<String, dynamic> m) => MeasureItem(
        name: m['name']?.toString() ?? '',
        drawingMm: (m['drawingMm'] as num? ?? 0).toDouble(),
        photoMm: (m['photoMm'] as num? ?? 0).toDouble(),
        source: m['source']?.toString() ?? 'photo',
        errorMm: (m['errorMm'] as num?)?.toDouble(),
      );
}

/// 一次测量会话（可持久化）。
class MeasureSession {
  final String id;
  final String projectKey;
  final String drawingKey;

  /// 所属图纸版本（→ [DrawingVersion.id]）；空串 = 未版本化。
  final String drawingVersionId;
  final String floor;
  final double tolMm; // 容差 mm
  final double tolPct; // 容差 %
  final PhotoCalib? photoCalib; // 照片侧标定（可空）
  final List<MeasureItem> items;
  final int updatedAt; // 毫秒时间戳

  /// 同步元数据（clientId / version / 时间戳 / 软删）。
  final SyncMeta sync;
  const MeasureSession({
    required this.id,
    required this.projectKey,
    required this.drawingKey,
    this.drawingVersionId = '',
    required this.floor,
    this.tolMm = 15,
    this.tolPct = 2,
    this.photoCalib,
    this.items = const [],
    this.updatedAt = 0,
    this.sync = const SyncMeta(),
  });

  MeasureSession copyWith({
    String? projectKey,
    String? drawingKey,
    String? drawingVersionId,
    String? floor,
    double? tolMm,
    double? tolPct,
    PhotoCalib? photoCalib,
    bool clearPhotoCalib = false,
    List<MeasureItem>? items,
    int? updatedAt,
    SyncMeta? sync,
  }) =>
      MeasureSession(
        id: id,
        projectKey: projectKey ?? this.projectKey,
        drawingKey: drawingKey ?? this.drawingKey,
        drawingVersionId: drawingVersionId ?? this.drawingVersionId,
        floor: floor ?? this.floor,
        tolMm: tolMm ?? this.tolMm,
        tolPct: tolPct ?? this.tolPct,
        photoCalib: clearPhotoCalib ? null : (photoCalib ?? this.photoCalib),
        items: items ?? this.items,
        updatedAt: updatedAt ?? this.updatedAt,
        sync: sync ?? this.sync,
      );

  int get passCount => items.where((e) => e.pass(tolMm, tolPct)).length;
  bool get allPass => items.isNotEmpty && passCount == items.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectKey': projectKey,
        'drawingKey': drawingKey,
        'drawingVersionId': drawingVersionId,
        'floor': floor,
        'tolMm': tolMm,
        'tolPct': tolPct,
        'photoCalib': photoCalib?.toJson(),
        'items': items
            .map((e) => {
                  'name': e.name,
                  'drawingMm': e.drawingMm,
                  'photoMm': e.photoMm,
                  'source': e.source,
                  if (e.errorMm != null) 'errorMm': e.errorMm,
                })
            .toList(),
        'updatedAt': updatedAt,
        ...sync.toJson(),
      };

  factory MeasureSession.fromJson(Map<String, dynamic> m) {
    final calib = m['photoCalib'] as Map<String, dynamic>?;
    return MeasureSession(
      id: m['id'] as String? ?? '',
      projectKey: m['projectKey'] as String? ?? '',
      drawingKey: m['drawingKey'] as String? ?? '',
      drawingVersionId: m['drawingVersionId'] as String? ?? '',
      floor: m['floor'] as String? ?? '',
      tolMm: (m['tolMm'] as num? ?? 15).toDouble(),
      tolPct: (m['tolPct'] as num? ?? 2).toDouble(),
      photoCalib: calib == null ? null : PhotoCalib.fromJson(calib),
      items: (m['items'] as List? ?? [])
          .map((e) => (e as Map<String, dynamic>))
          .map((e) => MeasureItem(
                name: e['name'] as String? ?? '',
                drawingMm: (e['drawingMm'] as num? ?? 0).toDouble(),
                photoMm: (e['photoMm'] as num? ?? 0).toDouble(),
                source: e['source'] as String? ?? 'photo', // 旧数据兼容
                errorMm: (e['errorMm'] as num?)?.toDouble(), // 旧数据 null
              ))
          .toList(),
      updatedAt: (m['updatedAt'] as num? ?? 0).toInt(),
      sync: SyncMeta.fromJson(m),
    );
  }
}

/// 拍照量尺校对页路由参数。
class MeasureArgs {
  final String projectKey;
  final String drawingKey;
  final String floor;
  const MeasureArgs({
    required this.projectKey,
    required this.drawingKey,
    this.floor = '',
  });
}

// ==================== 浩辰云图 CAD 模型 ====================

/// 图层状态信息（来自 getDwgInfo 返回的 layers）。
class CadLayer {
  final String name;
  final bool isOff;
  final bool isFrozen;
  final bool isLock;
  const CadLayer({
    required this.name,
    required this.isOff,
    required this.isFrozen,
    required this.isLock,
  });

  factory CadLayer.fromJson(dynamic v) {
    if (v is String) {
      return CadLayer(name: v, isOff: false, isFrozen: false, isLock: false);
    }
    final j = (v as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return CadLayer(
      name: j['name']?.toString() ?? '',
      isOff: j['isoff'] == true || j['isOff'] == true,
      isFrozen: j['isfrozen'] == true || j['isFrozen'] == true,
      isLock: j['islock'] == true || j['isLock'] == true,
    );
  }
}

/// 布局信息（模型空间 / 布局 1/2...）。
/// 浩辰返回两种形态：字符串，或 Map（{globalName, handle, nickName} / {name}）。
class CadLayout {
  final String name;

  /// 布局句柄（用于前端切换布局定位）。
  final String? handle;
  const CadLayout({required this.name, this.handle});

  factory CadLayout.fromJson(dynamic v) {
    if (v is String) return CadLayout(name: v);
    if (v is Map<String, dynamic>) {
      return CadLayout(
        name: (v['nickName']?.toString() ??
                v['globalName']?.toString() ??
                v['name']?.toString() ??
                '')
            .trim(),
        handle: v['handle']?.toString(),
      );
    }
    return const CadLayout(name: '');
  }
}

/// DWG 图纸解析结果（getDwgInfo + getTaskStatus 合并）。
class DwgInfo {
  final String requestId;
  final String taskType;
  final int status; // 0 未开始 / 1 执行中 / 2 已完成
  final int resultCode; // 0 成功
  final String? resultMsg;
  final String? deflayout;
  final List<CadLayer> layers;
  final List<CadLayout> layouts;
  final List<String> blocks;
  final List<String> xrefs;
  final String? error;

  const DwgInfo({
    required this.requestId,
    required this.taskType,
    required this.status,
    required this.resultCode,
    this.resultMsg,
    this.deflayout,
    this.layers = const [],
    this.layouts = const [],
    this.blocks = const [],
    this.xrefs = const [],
    this.error,
  });

  bool get isDone => status == 2;
  bool get isOk => isDone && resultCode == 0;

  factory DwgInfo.fromJson(Map<String, dynamic> j) {
    final biz = j['bizData'] as Map<String, dynamic>?;
    return DwgInfo(
      requestId: biz?['requestId']?.toString() ?? '',
      taskType: biz?['taskType']?.toString() ?? '',
      status: (biz?['status'] as num?)?.toInt() ?? 0,
      resultCode: (biz?['resultCode'] as num?)?.toInt() ?? -1,
      resultMsg: biz?['resultMsg']?.toString(),
      deflayout: biz?['deflayout']?.toString(),
      layers: ((biz?['layers'] as List?) ?? []).map(CadLayer.fromJson).toList(),
      layouts:
          ((biz?['layouts'] as List?) ?? []).map(CadLayout.fromJson).toList(),
      blocks:
          ((biz?['blocks'] as List?) ?? []).map((e) => e.toString()).toList(),
      xrefs: ((biz?['xrefs'] as List?) ?? []).map((e) => e.toString()).toList(),
      error: j['msg']?.toString(),
    );
  }
}

/// 图纸坐标标注（巡场精度标注）。
/// 用真实 CAD 图纸坐标（mm）记录缺陷位置，配合 CadCoordMapper 实现屏幕坐标自动换算。
class CadAnnotation {
  final String id;

  /// 所属图纸 key。
  final String drawingKey;

  /// 缺陷/标注名称。
  final String label;

  /// 图纸坐标（mm）。
  final double worldX;
  final double worldY;

  /// 屏幕相对坐标（0~1，便于无坐标系时的兜底定位）。
  final double relX;
  final double relY;
  final DateTime createdAt;
  const CadAnnotation({
    required this.id,
    required this.drawingKey,
    required this.label,
    required this.worldX,
    required this.worldY,
    required this.relX,
    required this.relY,
    required this.createdAt,
  });

  String get coordText =>
      'X=${worldX.toStringAsFixed(2)}  Y=${worldY.toStringAsFixed(2)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'drawingKey': drawingKey,
        'label': label,
        'worldX': worldX,
        'worldY': worldY,
        'relX': relX,
        'relY': relY,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CadAnnotation.fromJson(Map<String, dynamic> j) => CadAnnotation(
        id: j['id']?.toString() ?? '',
        drawingKey: j['drawingKey']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        worldX: (j['worldX'] as num?)?.toDouble() ?? 0,
        worldY: (j['worldY'] as num?)?.toDouble() ?? 0,
        relX: (j['relX'] as num?)?.toDouble() ?? 0,
        relY: (j['relY'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// 异步任务查询结果。
class CadTaskStatus {
  final String requestId;
  final String taskType;
  final int status;
  final int resultCode;
  final String? resultMsg;
  final Map<String, dynamic>? bizData;

  const CadTaskStatus({
    required this.requestId,
    required this.taskType,
    required this.status,
    required this.resultCode,
    this.resultMsg,
    this.bizData,
  });

  bool get isDone => status == 2;
  bool get isOk => isDone && resultCode == 0;

  factory CadTaskStatus.fromJson(Map<String, dynamic> j) {
    final biz = j['bizData'] as Map<String, dynamic>?;
    return CadTaskStatus(
      requestId: biz?['requestId']?.toString() ?? '',
      taskType: biz?['taskType']?.toString() ?? '',
      status: (biz?['status'] as num?)?.toInt() ?? 0,
      resultCode: (biz?['resultCode'] as num?)?.toInt() ?? -1,
      resultMsg: biz?['resultMsg']?.toString(),
      bizData: biz,
    );
  }
}

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

/// 用户上传 DWG 转换登记（任务3：DWG 自助上传 → OCF 手机查看）。
class UploadedDrawing {
  final String key; // drawingKey / OCF 缓存 key
  final String name; // 展示名（原始文件名去 .dwg）
  final String fileName; // 原始文件名（含扩展）
  final int sizeBytes;
  final int tsMs;

  /// 底图 PNG 像素宽/高（后端渲染时返回；0 = 旧数据未记录）。
  final int width;
  final int height;

  /// CAD 坐标范围 "xmin,ymin,xmax,ymax"（mm，供后续自动校准）。
  final String? bounds;

  /// 'converting'（转换中）/ 'done'（已转换）/ 'failed'（失败）。
  final String status;
  final String? error; // failed 时给可读错误
  const UploadedDrawing({
    required this.key,
    required this.name,
    required this.fileName,
    this.sizeBytes = 0,
    this.tsMs = 0,
    this.width = 0,
    this.height = 0,
    this.bounds,
    this.status = 'converting',
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'tsMs': tsMs,
        'width': width,
        'height': height,
        'bounds': bounds,
        'status': status,
        'error': error,
      };

  /// 旧数据读取缺字段一律给默认值。
  factory UploadedDrawing.fromJson(Map<String, dynamic> m) => UploadedDrawing(
        key: m['key']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        fileName: m['fileName']?.toString() ?? '',
        sizeBytes: (m['sizeBytes'] as num? ?? 0).toInt(),
        tsMs: (m['tsMs'] as num? ?? 0).toInt(),
        width: (m['width'] as num? ?? 0).toInt(),
        height: (m['height'] as num? ?? 0).toInt(),
        bounds: m['bounds']?.toString(),
        status: m['status']?.toString() ?? 'done',
        error: m['error']?.toString(),
      );
}

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

/// 巡场页路由参数（照 MeasureArgs 模式）。
class PatrolArgs {
  final String? planId;
  const PatrolArgs({this.planId});
}

/// 巡场路径工具：从 HTML demo 的 app.js（patrolPath / patrolCheckpoints / roundPolyline）移植。
///
/// 注意：以下常量已迁移为 [PatrolPlan] 模型（见 [lib/data/models.dart]），
/// 本文件仅保留纯算法（进度插值 / 累计长度 / 检查点命中），不再持有业务路径数据。
///
/// 坐标体系：0-100 相对坐标（巡场页按容器尺寸缩放）。
