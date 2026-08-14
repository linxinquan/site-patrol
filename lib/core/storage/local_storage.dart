import 'dart:typed_data';

import 'app_storage_io.dart'
    if (dart.library.js_interop) 'app_storage_web.dart'
    if (dart.library.html) 'app_storage_web.dart'
    as impl;

/// 全局单例（编译期选定平台实现）。
final LocalStorage localStorageImpl = impl.localStorageImpl;

/// 本地存储抽象接口。业务层只依赖此接口，平台无感。
///
/// 编译期通过条件导入选定实现：
/// - 移动端（iOS/Android）：[AppStorageIo]（secure_storage + Hive + path_provider）
/// - Web（预览降级）：[AppStorageWeb]（localStorage + IndexedDB 或降级内存）
abstract class LocalStorage {
  /// 全局单例（编译期选定平台实现）。
  static LocalStorage get instance => localStorageImpl;

  // ---- KV（敏感/会话数据，加密存储）----

  /// 读取 KV 字符串，不存在返回 null。
  Future<String?> readKV(String key);

  /// 写入 KV 字符串。
  Future<void> writeKV(String key, String value);

  /// 删除 KV。
  Future<void> deleteKV(String key);

  // ---- 结构化文档（标记数据 / AI 结果，JSON 直存）----

  /// 读取 JSON 文档，不存在返回 null。
  Future<String?> readDoc(String key);

  /// 写入 JSON 文档。
  Future<void> writeDoc(String key, String value);

  /// 删除 JSON 文档。
  Future<void> deleteDoc(String key);

  // ---- 文件（图纸 / 照片，二进制大文件）----

  /// 读取二进制文件，不存在返回 null。
  Future<Uint8List?> readFile(String relativePath);

  /// 写入二进制文件。[relativePath] 相对存储根目录（如 `drawings/a.png`）。
  Future<void> writeFile(String relativePath, Uint8List bytes);

  /// 删除二进制文件。
  Future<void> deleteFile(String relativePath);

  /// 判断文件是否存在。
  Future<bool> fileExists(String relativePath);

  // ---- 启动期 ----

  /// 首次启动：把随包预置图纸从 assets 拷贝到本地 Documents/drawings。
  /// 已拷贝过则跳过，可安全重复调用。
  Future<void> seedDrawingsIfNeeded();
}
