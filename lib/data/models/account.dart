/// 账号与组织域模型（A 类全局配置）。
///
/// 从 `models/project.dart` 拆出（原文件同时装「项目档案」与「账号组织」两块，
/// `Membership` 归哪边有歧义，故独立成域）。覆盖后台录入的账号侧数据：
/// - [Org]（组织 / 单位）、[Discipline]（专业字典）、[User]（账号档案）；
/// - [Membership]（项目成员 = 职责 × 专业 × 单位）—— 它同时是 App 端
///   「登录后能看到哪些项目」的唯一依据，以及权限边界的挂载点。
///
/// 均为**服务端维护、客户端只读**（走全量拉取覆盖，不带 [SyncMeta] 增量元数据），
/// 例外：[Membership] 是客户端可写实体，故带 `sync`。
///
/// 判定逻辑**不在本文件**：`PermissionScope`（`models/auth.dart`）是唯一入口，
/// 它把同一用户的多条 [Membership] 合并成「能做什么 + 能看哪类」。
///
/// 后端对应表：`orgs` / `disciplines` / `users` / `memberships`。
library;

import '../sync_meta.dart';

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

/// 专业字典（A 类全局配置，客户端只读）。
///
/// **为什么要有这张表而不是硬编码枚举**：设计院的专业划分带「专属语义」
/// （总图 / 景观 / 幕墙 / 智能化 / 室内…），院与院还不一样。写死进代码，
/// 每加一个专业就要发一次版。客户端只按 **code 字符串**使用，名称从本表取。
///
/// 约定：**专业 code 与 `DefectCategory` 复用同一套取值**，
/// 这样「暖通专业负责人看暖通类缺陷」不需要维护映射表。
///
/// ## 第一版范围（明确约定，避免过度设计）
///
/// **当前只做「结构专业」或「不分专业」两种**：
/// - 不分专业 → 成员 [Membership.disciplines] 留**空数组**（= 不限），这是默认情况；
/// - 只分结构 → 后台下发单条 `structure`，成员填 `[Discipline.structure]`。
///
/// 因此**第一版不需要任何按专业过滤的业务逻辑**：空数组天然放行全部。
/// 本类与 [Membership.disciplines] 只是**先把结构与取值定下来**，
/// 让后续加专业（暖通 / 给排水 / 幕墙…）不需要改表、不需要发版。
class Discipline {
  /// 建议的基础取值（与 `DefectCategory` 对齐，非穷举——真实清单由后台维护）。
  /// 第一版只会用到 [structure]，其余为后续扩展预留。
  static const String architecture = 'architecture'; // 建筑
  static const String structure = 'structure'; // 结构
  static const String water = 'water'; // 给排水
  static const String hvac = 'hvac'; // 暖通
  static const String electric = 'electric'; // 电气
  static const String decoration = 'decoration'; // 装饰
  static const String other = 'other'; // 其他

  final String code;
  final String name; // 展示名，如「暖通」
  final int sort;

  /// 是否系统预置（预置项不可删，只能停用）。
  final bool isSystem;
  const Discipline({
    required this.code,
    required this.name,
    this.sort = 0,
    this.isSystem = false,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'sort': sort,
        'isSystem': isSystem,
      };

  factory Discipline.fromJson(Map<String, dynamic> m) => Discipline(
        code: m['code']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        sort: (m['sort'] as num?)?.toInt() ?? 0,
        isSystem: m['isSystem'] == true,
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
  final String username; // 登录名（后端 users.username，唯一）
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
    this.username = '',
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
        'username': username,
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
        username: m['username']?.toString() ?? '',
        orgId: m['orgId']?.toString() ?? '',
        org: m['org']?.toString() ?? '',
        role: m['role']?.toString() ?? '',
        avatar: m['avatar']?.toString() ?? '',
        phone: m['phone']?.toString() ?? '',
        email: m['email']?.toString() ?? '',
        status: m['status']?.toString() ?? statusActive,
      );
}

/// 项目成员关系（A2 用户账号 + B6 项目成员与角色）。
///
/// 承载两件事：① App 端「登录后能看到哪些项目」的唯一依据；
/// ② 权限边界的挂载点。权限判定**只认权限点，不认角色**——
/// 角色是数据（可后台新增而不发版），代码只硬编码 [permissions] 里的权限点。
///
/// ## 三个正交维度（不要揉成一个字段）
///
/// | 维度 | 字段 | 回答的问题 |
/// |---|---|---|
/// | 职责 | [roleCode] | 这个人**能做什么动作**（动作由 [permissions] 决定） |
/// | 专业 | [disciplines] | 这个人**负责/能看哪一类数据** |
/// | 单位 | [orgId] | 这个人**代表哪一方** |
///
/// 例：`中建四局 × 暖通 × 专业负责人` = 一条成员关系 → 能回复暖通类整改，且只看暖通类。
/// **不要把专业拼进 `roleCode`**（`discipline_lead_hvac` 之类会让角色按「职责 × 专业」
/// 组合爆炸，且违背「角色是数据不是代码」）。
///
/// ## [disciplines] 的语义
///
/// - **空列表 = 不限专业**（项目负责人、监理、管理类角色天然是全专业）；
///   **不要**造一个 `'all'` 伪值。
/// - **第一版基本都留空**：当前只做「结构专业」或「不分专业」（见 [Discipline]），
///   所以这一列现在几乎不参与判断，是为后续扩展预留的结构。
/// - 专业与权限点是**「与」关系**：`can('defect.reply')` **且** 缺陷专业被覆盖。
/// - 驻场、施工方、监理的成员**同样带专业**（他们也是按专业分包的）。
///
/// ## 本类只是数据，判定不在这里
///
/// **不要**在本类上做「能不能做某事」的判断——那是 `PermissionScope` 的职责
/// （`AuthProfile.scopeOf(projectId)`），它会把同一用户的多条成员记录合并。
/// 本类只提供**原始数据**：字段 + `toJson/fromJson`。
class Membership {
  /// 建议的角色 code 最小集：**职责**维度，不含专业。
  /// 真实角色名单由后台 `roles` 表定义（客户端不写死判断，只用 [permissions]）。
  static const String roleProjectManager = 'project_manager'; // 项目负责人（不限专业）
  static const String roleDisciplineLead = 'discipline_lead'; // 专业负责人（本专业内可销项/导出）
  static const String roleDesigner = 'designer'; // 专业设计师（只读 + 可提建议）
  static const String roleSiteEngineer = 'site_engineer'; // 驻场工程师（带专业）
  static const String roleContractor = 'contractor'; // 施工方（只看指派给自己的 + 可回复）
  static const String roleViewer = 'viewer'; // 只读

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

  /// 单位（维度三）→ [Org.id]；冗余自 [User.orgId]，便于按单位做数据范围过滤。
  final String orgId;
  final String roleCode; // 职责（维度一），见上方 role* 常量
  final String roleName; // 展示冗余（角色名由后台维护）
  final List<String> disciplines; // 专业（维度二），见 [Discipline]；**空 = 不限**
  final List<String> permissions; // 见上方 perm* 常量
  final String status; // 见上方 status* 常量

  /// 同步元数据（可写实体）。
  final SyncMeta sync;
  const Membership({
    required this.id,
    required this.userId,
    required this.projectId,
    this.orgId = '',
    this.roleCode = roleViewer,
    this.roleName = '',
    this.disciplines = const [],
    this.permissions = const [],
    this.status = statusActive,
    this.sync = const SyncMeta(),
  });

  /// 是否不限专业（纯粹的数据判断：这一条成员记录没有限定专业）。
  bool get isAllDisciplines => disciplines.isEmpty;

  // 判定方法**有意不放在这里**：本类只承载数据。
  // 「能否做某动作 / 能否看到某专业」统一走 `PermissionScope`
  // （`AuthProfile.scopeOf(projectId)`）——同一个判断只保留一个入口，
  // 避免「记录级」与「合并级」两套语义互相打架。

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'projectId': projectId,
        'orgId': orgId,
        'roleCode': roleCode,
        'roleName': roleName,
        'disciplines': disciplines,
        'permissions': permissions,
        'status': status,
        ...sync.toJson(),
      };

  factory Membership.fromJson(Map<String, dynamic> m) => Membership(
        id: m['id']?.toString() ?? '',
        userId: m['userId']?.toString() ?? '',
        projectId: m['projectId']?.toString() ?? '',
        orgId: m['orgId']?.toString() ?? '',
        roleCode: m['roleCode']?.toString() ?? roleViewer,
        roleName: m['roleName']?.toString() ?? '',
        disciplines:
            (m['disciplines'] as List?)?.whereType<String>().toList() ?? const [],
        permissions:
            (m['permissions'] as List?)?.whereType<String>().toList() ?? const [],
        status: m['status']?.toString() ?? statusActive,
        sync: SyncMeta.fromJson(m),
      );
}
