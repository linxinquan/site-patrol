/// 认证与授权域模型（登录 / 令牌 / 会话 / 权限）。
///
/// 三层结构，不要混用：
/// - **账号档案** [User]（`models/account.dart`）：后台建号下发的用户资料，客户端只读；
/// - **项目成员** [Membership]（`models/account.dart`）：项目级角色 + 权限点，
///   是「登录后能看到哪些项目」与「能做什么」的唯一依据；
/// - **会话态** [UserSession]（本文件）：本机登录状态，JWT 形状，负责持久化与过期判断。
///
/// 接口契约（对应统一入口 `/api/v1`）：
/// - `POST /auth/login`   → [LoginResult]（令牌对 + 用户 + 项目成员）
/// - `POST /auth/refresh` → [AuthTokens]（轮换 refresh，旧的立即失效）
/// - `POST /auth/logout`  → 无返回（refresh 进服务端黑名单）
/// - `GET  /auth/me`      → [AuthProfile]（当前用户 + 项目列表 + 各项目权限）
///
/// 安全约定（与后端一致）：**角色与权限不放 JWT**，只放在响应体里按需刷新，
/// 避免权限变更后旧 token 仍生效。
library;

import '../../core/utils/time_text.dart';
import 'account.dart';

/// 本地会话模型（本机登录状态）。
///
/// 按正式期（后端 JWT）建模：测试期只是「校验来源」不同，
/// 会话结构、存储、过期判断与正式期完全一致。
///
/// 字段与序列化格式**保持既有形态**（`token` / `refreshToken` / `expiresAt`），
/// 以保证老版本写入的本地会话仍能读回。
class UserSession {
  final String userId; // 唯一标识（对应 User.id）
  final String username; // 登录名
  final String displayName; // 显示名（如「杨工」）
  final String? token; // access token（测试期可为空/固定串）
  final String? refreshToken; // 正式期用于续期
  final DateTime loginAt;
  final DateTime? expiresAt; // access token 过期时间（null = 长期有效）

  const UserSession({
    required this.userId,
    required this.username,
    required this.displayName,
    this.token,
    this.refreshToken,
    required this.loginAt,
    this.expiresAt,
  });

  /// 由登录响应构造（`POST /auth/login` 成功后调用）。
  ///
  /// [now] 仅便于测试注入。
  factory UserSession.fromLogin(LoginResult result, {DateTime? now}) {
    final t = result.tokens;
    return UserSession(
      userId: result.user.id,
      username: result.user.username,
      displayName: result.user.name,
      token: t.accessToken.isEmpty ? null : t.accessToken,
      refreshToken: t.refreshToken.isEmpty ? null : t.refreshToken,
      loginAt: now ?? DateTime.now(),
      expiresAt: t.accessExpiresAtMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(t.accessExpiresAtMs)
          : null,
    );
  }

  /// 是否已过期。expiresAt 为 null 表示长期有效。
  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  /// 是否已持有令牌（正式期登录后为 true；测试期占位会话可能为 false）。
  bool get hasToken => (token ?? '').isNotEmpty;

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'username': username,
        'displayName': displayName,
        'token': token,
        'refreshToken': refreshToken,
        'loginAt': loginAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
      };

  /// 从 JSON 恢复（容错：字段缺失时给空值）。
  factory UserSession.fromJson(Map<String, dynamic> map) => UserSession(
        userId: map['userId']?.toString() ?? '',
        username: map['username']?.toString() ?? '',
        displayName: map['displayName']?.toString() ?? '',
        token: map['token']?.toString(),
        refreshToken: map['refreshToken']?.toString(),
        loginAt: DateTime.tryParse(map['loginAt']?.toString() ?? '') ??
            DateTime.now(),
        expiresAt: map['expiresAt'] == null
            ? null
            : DateTime.tryParse(map['expiresAt'].toString()),
      );
}

/// 令牌对（`/auth/login` 与 `/auth/refresh` 的公共部分）。
///
/// 时间用 epoch 毫秒，与后端 `timestamptz` 可无损换算。
class AuthTokens {
  final String accessToken;
  final String refreshToken;

  /// access token 过期时间（epoch ms）；0 = 未提供（视为不过期）。
  final int accessExpiresAtMs;

  /// refresh token 过期时间（epoch ms）；0 = 未提供。
  final int refreshExpiresAtMs;

  const AuthTokens({
    this.accessToken = '',
    this.refreshToken = '',
    this.accessExpiresAtMs = 0,
    this.refreshExpiresAtMs = 0,
  });

  /// access token 是否已过期（未提供过期时间时视为不过期）。
  bool get isAccessExpired =>
      accessExpiresAtMs > 0 &&
      DateTime.now().millisecondsSinceEpoch >= accessExpiresAtMs;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accessExpiresAtMs': accessExpiresAtMs,
        'refreshExpiresAtMs': refreshExpiresAtMs,
      };

  /// 容错解析：过期时间接受 epoch 毫秒数值或 ISO/`yyyy-MM-dd HH:mm:ss` 文本；
  /// 令牌字段同时兼容 `access` / `refresh`（后端简写）。
  factory AuthTokens.fromJson(Map<String, dynamic> m) => AuthTokens(
        accessToken: (m['accessToken'] ?? m['access'])?.toString() ?? '',
        refreshToken: (m['refreshToken'] ?? m['refresh'])?.toString() ?? '',
        accessExpiresAtMs: _ms(m['accessExpiresAtMs'] ?? m['expiresAt']),
        refreshExpiresAtMs: _ms(m['refreshExpiresAtMs'] ?? m['refreshExpiresAt']),
      );
}

/// 登录结果（`POST /auth/login`）。
///
/// 后端推荐返回 `memberships`（项目级角色 + 权限点，客户端可直接判断可见项目）；
/// 若只返回扁平的 `permissions`，[fromJson] 会兜底构造一条无项目的成员记录，
/// 保证两种返回形态都能落地。
class LoginResult {
  final AuthTokens tokens;
  final User user;
  final List<Membership> memberships;
  const LoginResult({
    required this.tokens,
    required this.user,
    this.memberships = const [],
  });

  /// 是否可见某个项目（登录后路由/项目切换的依据）。
  bool canSeeProject(String projectId) =>
      memberships.any((m) => m.projectId == projectId);

  Map<String, dynamic> toJson() => {
        'tokens': tokens.toJson(),
        'user': user.toJson(),
        'memberships': memberships.map((m) => m.toJson()).toList(),
      };

  factory LoginResult.fromJson(Map<String, dynamic> m) {
    final raw = m['memberships'];
    final list = (raw as List? ?? const [])
        .whereType<Map>()
        .map((e) => Membership.fromJson(e.cast<String, dynamic>()))
        .toList();
    final flat = (m['permissions'] as List?)?.whereType<String>().toList();
    return LoginResult(
      tokens: AuthTokens.fromJson(
          (m['tokens'] as Map?)?.cast<String, dynamic>() ?? m),
      user: User.fromJson(
          (m['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
      memberships: list.isNotEmpty || flat == null || flat.isEmpty
          ? list
          : [Membership(id: '', userId: '', projectId: '', permissions: flat)],
    );
  }
}

/// 当前身份（`GET /auth/me`）——登录后刷新用户资料与项目权限。
class AuthProfile {
  final User user;
  final List<Membership> memberships;
  const AuthProfile({required this.user, this.memberships = const []});

  /// 指定项目的权限视图；不是成员则为空权限。
  PermissionScope scopeOf(String projectId) => PermissionScope.forProject(
        memberships: memberships,
        projectId: projectId,
      );

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'memberships': memberships.map((m) => m.toJson()).toList(),
      };

  factory AuthProfile.fromJson(Map<String, dynamic> m) {
    final raw = m['memberships'];
    final list = (raw as List? ?? const [])
        .whereType<Map>()
        .map((e) => Membership.fromJson(e.cast<String, dynamic>()))
        .toList();
    final flat = (m['permissions'] as List?)?.whereType<String>().toList();
    return AuthProfile(
      user: User.fromJson(
          (m['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
      memberships: list.isNotEmpty || flat == null || flat.isEmpty
          ? list
          : [Membership(id: '', userId: '', projectId: '', permissions: flat)],
    );
  }
}

/// 某个（用户 × 项目）下的**权限点 + 专业范围**。
///
/// 两个正交轴，判定时是「与」关系：
/// - [permissions] —— 这个人**能做什么动作**；
/// - [disciplines] —— 这个人**能看/管哪一类数据**（**空 = 不限专业**）。
///
/// 业务代码只判断权限点与专业 code，不判断角色名 —— 角色是数据，权限点是代码：
/// ```dart
/// if (scope.can(Membership.permDefectClose)) { ... }        // 只判动作
/// if (scope.canOn(Membership.permDefectReply, d.category.name)) { ... } // 动作 + 专业
/// ```
class PermissionScope {
  final Set<String> permissions;

  /// 覆盖的专业 code（见 [Discipline]）；**空列表 = 不限专业**。
  final List<String> disciplines;

  /// 所属项目 id（空串 = 与项目无关的全局权限，如扁平 `permissions` 返回）。
  final String projectId;

  const PermissionScope(
    this.permissions, {
    this.disciplines = const [],
    this.projectId = '',
  });

  /// 空权限（未登录 / 非项目成员）。
  static const PermissionScope none = PermissionScope(<String>{});

  /// 从成员列表取「该用户在指定项目」的权限与专业并集。
  ///
  /// 专业合并规则：**任一命中的成员记录为「不限专业」，整体即为不限**（返回空列表）——
  /// 因为「项目负责人 + 结构负责人」两重身份叠加时，能看的范围应是并集（即全部）。
  factory PermissionScope.forProject({
    required List<Membership> memberships,
    required String projectId,
    String? userId,
  }) {
    final out = <String>{};
    final disciplines = <String>{};
    var unrestricted = false;
    for (final m in memberships) {
      if (m.status == Membership.statusDisabled) continue;
      if (userId != null && m.userId.isNotEmpty && m.userId != userId) continue;
      // 项目匹配，或记录本身不绑定项目（扁平 permissions 形态）。
      if (m.projectId.isNotEmpty && projectId.isNotEmpty && m.projectId != projectId) {
        continue;
      }
      out.addAll(m.permissions);
      if (m.disciplines.isEmpty) {
        unrestricted = true;
      } else {
        disciplines.addAll(m.disciplines);
      }
    }
    return PermissionScope(
      out,
      disciplines: unrestricted ? const [] : disciplines.toList(),
      projectId: projectId,
    );
  }

  bool get isEmpty => permissions.isEmpty;

  /// [disciplines] 是否为空（= 记录里没限定专业）。
  ///
  /// ⚠️ 注意与 [coversDiscipline] 的区别：本 getter **只看数据**，
  /// 不代表"可见全部"——未持有任何权限时（[none]）同样为空。
  bool get isAllDisciplines => disciplines.isEmpty;

  /// 是否拥有某个权限点（见 [Membership] 的 `perm*` 常量）。
  bool can(String permission) => permissions.contains(permission);

  /// 是否能覆盖某专业的数据范围。
  ///
  /// 判定规则（**先要有权限，再谈范围**）：
  /// - 未持有任何权限（未登录 / 非项目成员，如 [none]）→ 一律 `false`，
  ///   避免把"空范围"误当成"不限"；
  /// - 持有权限且 [disciplines] 为空 → `true`（不限专业：项目负责人 / 监理）；
  /// - 否则看是否命中列出的专业。
  bool coversDiscipline(String code) {
    if (permissions.isEmpty) return false;
    return disciplines.isEmpty || disciplines.contains(code);
  }

  /// 权限点 + 专业范围**同时**满足（数据范围与动作是「与」关系）。
  bool canOn(String permission, String disciplineCode) =>
      can(permission) && coversDiscipline(disciplineCode);

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'permissions': permissions.toList(),
        'disciplines': disciplines,
      };

  factory PermissionScope.fromJson(Map<String, dynamic> m) => PermissionScope(
        (m['permissions'] as List?)?.whereType<String>().toSet() ?? const {},
        disciplines:
            (m['disciplines'] as List?)?.whereType<String>().toList() ?? const [],
        projectId: m['projectId']?.toString() ?? '',
      );
}

/// 容错取 epoch 毫秒：数值直接用，文本按 `msFromTsText` 解析（失败 0）。
int _ms(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String && v.isNotEmpty) return msFromTsText(v);
  return 0;
}
