import 'dart:convert';

import '../../data/models/auth.dart';
import 'local_storage.dart';

/// 会话模型 [UserSession] 已迁至模型层（`lib/data/models/auth.dart`），
/// 与登录/令牌/权限模型放在一起；为兼容既有 import，此处 re-export。
export '../../data/models/auth.dart' show UserSession;

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
