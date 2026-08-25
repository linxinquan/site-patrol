import 'dart:convert';

import 'local_storage.dart';

/// 本地会话模型。
///
/// 按正式期（后端 JWT）建模：测试期只是「校验来源」不同，
/// 会话结构、存储、过期判断与正式期完全一致。
class UserSession {
  final String userId; // 唯一标识（测试期固定 id，正式期后端下发）
  final String username; // 登录名
  final String displayName; // 显示名（如「杨工」）
  final String? token; // 测试期可为空/固定串；正式期 access token
  final String? refreshToken; // 正式期用于续期
  final DateTime loginAt;
  final DateTime? expiresAt; // 过期时间（null = 长期有效）

  const UserSession({
    required this.userId,
    required this.username,
    required this.displayName,
    this.token,
    this.refreshToken,
    required this.loginAt,
    this.expiresAt,
  });

  /// 是否已过期。expiresAt 为 null 表示长期有效。
  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

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

/// 会话读写封装：只通过 [LocalStorage] 抽象与本地存储打交道。
class SessionStore {
  SessionStore({LocalStorage? storage}) : _storage = storage ?? LocalStorage.instance;

  final LocalStorage _storage;

  static const String _sessionKey = 'session';

  /// 读取本地会话；不存在或已过期返回 null。
  Future<UserSession?> read() async {
    final raw = await _storage.readKV(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final session =
          UserSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (session.isExpired) {
        await clear();
        return null;
      }
      return session;
    } catch (_) {
      // 解析失败视为无会话，并清理脏数据。
      await clear();
      return null;
    }
  }

  /// 写入会话。
  Future<void> save(UserSession session) async {
    await _storage.writeKV(_sessionKey, jsonEncode(session.toJson()));
  }

  /// 清除会话（登出）。
  Future<void> clear() async {
    await _storage.deleteKV(_sessionKey);
  }
}

/// 引导态与当前选择偏好（与账号解绑，重启后保留）。
///
/// 与 [SessionStore] 的区别：session 代表「是否已登录」，prefs 代表
/// 「登录后完成过引导、当前选了哪个用户 / 项目」。三者重启后都需恢复，
/// 否则已登录老用户会被路由守卫反复重定向到 /onboard。
class UserPrefs {
  UserPrefs({LocalStorage? storage})
      : _storage = storage ?? LocalStorage.instance;

  final LocalStorage _storage;

  static const String _onboardedKey = 'onboarded';
  static const String _userIdKey = 'currentUserId';
  static const String _projectIdKey = 'currentProjectId';

  /// 是否已完成引导（选过用户 + 项目）。
  Future<bool> readOnboarded() async {
    final raw = await _storage.readKV(_onboardedKey);
    return raw == 'true';
  }

  Future<void> saveOnboarded(bool v) async {
    await _storage.writeKV(_onboardedKey, v ? 'true' : 'false');
  }

  /// 当前登录用户 id；未选过返回 null。
  Future<String?> readUserId() async {
    final raw = await _storage.readKV(_userIdKey);
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  Future<void> saveUserId(String? v) async {
    if (v == null) {
      await _storage.deleteKV(_userIdKey);
    } else {
      await _storage.writeKV(_userIdKey, v);
    }
  }

  /// 当前项目 id；未选过返回 null。
  Future<String?> readProjectId() async {
    final raw = await _storage.readKV(_projectIdKey);
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  Future<void> saveProjectId(String? v) async {
    if (v == null) {
      await _storage.deleteKV(_projectIdKey);
    } else {
      await _storage.writeKV(_projectIdKey, v);
    }
  }

  /// 清空全部偏好（登出时调用，使下次登录重新走引导）。
  Future<void> clear() async {
    await _storage.deleteKV(_onboardedKey);
    await _storage.deleteKV(_userIdKey);
    await _storage.deleteKV(_projectIdKey);
  }
}
