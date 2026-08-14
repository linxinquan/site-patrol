import 'dart:convert';

import 'web_storage_stub.dart'
    if (dart.library.html) 'web_storage_web.dart'
    if (dart.library.js_interop) 'web_storage_web.dart'
    as impl;

/// Web localStorage 暂存工具（key-value，值为 JSON 字符串）。
/// 仅 Web 生效；其他平台为空实现（避免 dart:html 污染移动端/测试编译）。
class WebStorage {
  static const String _prefix = 'gongdi_vision_';

  /// 读取 JSON 字符串，不存在返回 null。
  static String? get(String key) => impl.get('$_prefix$key');

  /// 写入 JSON 字符串。
  static void set(String key, String value) => impl.set('$_prefix$key', value);

  /// 删除。
  static void remove(String key) => impl.remove('$_prefix$key');

  /// 便捷：读列表。
  static List<dynamic> getList(String key) {
    final raw = get(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  /// 便捷：写列表。
  static void setList(String key, List<dynamic> list) =>
      set(key, jsonEncode(list));
}
