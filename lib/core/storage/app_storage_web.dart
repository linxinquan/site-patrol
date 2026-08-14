import 'dart:typed_data';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' show window;

import 'local_storage.dart';

/// 平台实现入口（供条件导入的 [LocalStorage] 抽象引用）。
final LocalStorage localStorageImpl = AppStorageWeb.instance;

/// Web（预览降级）存储实现。
///
/// 浏览器无系统级加密与文件系统，仅做演示级存储：
/// - KV / 文档 → localStorage（容量约 5MB，会话级）
/// - 大文件（图纸/照片）→ 内存 Map（仅当前页面会话有效，页面刷新即丢）
///
/// 真实 Web 生产可换 IndexedDB 存 Blob，本实现保持接口一致、可平滑替换。
class AppStorageWeb implements LocalStorage {
  AppStorageWeb._();

  /// 平台单例，供 [LocalStorage.instance] 引用。
  static final AppStorageWeb instance = AppStorageWeb._();

  static const String _prefix = 'gongdi_kv_';
  static const String _docsPrefix = 'gongdi_doc_';

  /// 大文件内存缓存（relativePath → bytes）。Web 仅当前会话可见。
  final Map<String, Uint8List> _files = {};

  // ---- KV ----

  @override
  Future<String?> readKV(String key) async => window.localStorage['$_prefix$key'];

  @override
  Future<void> writeKV(String key, String value) async =>
      window.localStorage['$_prefix$key'] = value;

  @override
  Future<void> deleteKV(String key) async =>
      window.localStorage.remove('$_prefix$key');

  // ---- 文档 ----

  @override
  Future<String?> readDoc(String key) async =>
      window.localStorage['$_docsPrefix$key'];

  @override
  Future<void> writeDoc(String key, String value) async =>
      window.localStorage['$_docsPrefix$key'] = value;

  @override
  Future<void> deleteDoc(String key) async =>
      window.localStorage.remove('$_docsPrefix$key');

  // ---- 文件 ----

  @override
  Future<Uint8List?> readFile(String relativePath) async => _files[relativePath];

  @override
  Future<void> writeFile(String relativePath, Uint8List bytes) async =>
      _files[relativePath] = bytes;

  @override
  Future<void> deleteFile(String relativePath) async => _files.remove(relativePath);

  @override
  Future<bool> fileExists(String relativePath) async =>
      _files.containsKey(relativePath);

  // ---- 首次启动图纸拷贝 ----

  @override
  Future<void> seedDrawingsIfNeeded() async {
    // Web 预览：图纸直接走 assets，无需拷贝本地。
    return;
  }
}
