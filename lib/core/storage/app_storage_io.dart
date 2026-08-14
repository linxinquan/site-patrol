import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_storage.dart';

/// 平台实现入口（供条件导入的 [LocalStorage] 抽象引用）。
final LocalStorage localStorageImpl = AppStorageIo.instance;

/// 移动端（iOS/Android）存储实现。
///
/// 分层隔离：
/// - KV 会话凭证 → flutter_secure_storage（Keychain/Keystore 系统级加密）
/// - 结构化文档（标记/AI 结果）→ Hive（本地 DB 文件）
/// - 大文件（图纸/照片）→ path_provider 的 Documents 目录
class AppStorageIo implements LocalStorage {
  AppStorageIo._();

  /// 平台单例，供 [LocalStorage.instance] 引用。
  static final AppStorageIo instance = AppStorageIo._();

  static const String _kvPrefix = 'gongdi_kv_';
  static const String _hiveBox = 'gongdi_docs';
  static const String _drawingsDir = 'drawings';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  Box<String>? _docBox;

  Future<Box<String>> _box() async {
    if (_docBox != null) return _docBox!;
    if (!Hive.isBoxOpen(_hiveBox)) {
      _docBox = await Hive.openBox<String>(_hiveBox);
    } else {
      _docBox = Hive.box<String>(_hiveBox);
    }
    return _docBox!;
  }

  Future<Directory> _documentsDir() async =>
      (await getApplicationDocumentsDirectory());

  /// 存储根目录下的完整路径。
  Future<String> _fullPath(String relativePath) async {
    final dir = await _documentsDir();
    return p.join(dir.path, relativePath);
  }

  // ---- KV ----

  @override
  Future<String?> readKV(String key) async =>
      await _secure.read(key: '$_kvPrefix$key');

  @override
  Future<void> writeKV(String key, String value) async =>
      await _secure.write(key: '$_kvPrefix$key', value: value);

  @override
  Future<void> deleteKV(String key) async =>
      await _secure.delete(key: '$_kvPrefix$key');

  // ---- 文档 ----

  @override
  Future<String?> readDoc(String key) async => (await _box()).get(key);

  @override
  Future<void> writeDoc(String key, String value) async =>
      await (await _box()).put(key, value);

  @override
  Future<void> deleteDoc(String key) async => await (await _box()).delete(key);

  // ---- 文件 ----

  @override
  Future<Uint8List?> readFile(String relativePath) async {
    final file = File(await _fullPath(relativePath));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeFile(String relativePath, Uint8List bytes) async {
    final file = File(await _fullPath(relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final file = File(await _fullPath(relativePath));
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> fileExists(String relativePath) async =>
      await File(await _fullPath(relativePath)).exists();

  // ---- 首次启动图纸拷贝 ----

  @override
  Future<void> seedDrawingsIfNeeded() async {
    // 标记已拷贝；已拷贝过则跳过。
    const marker = 'gongdi_seed_drawings_v1';
    if (await readKV(marker) == 'done') return;

    // 拷贝 assets/drawings 下所有图纸到本地目录。
    const manifest = <String>[
      'nkf_cor_1f.png',
      'nkf_east_1f.png',
      'nkf_east_4f.png',
      'nkf_inf_1f.png',
      'nkf_total_v.png',
      'nkf_total.png',
      'nkf_west_1f.png',
      'nkf_west_2f.png',
      'nkf_west_4f.png',
      'nkf_west_b1.png',
      'nkf_west_b2.png',
    ];

    for (final name in manifest) {
      final data = await rootBundle.load('assets/drawings/$name');
      await writeFile('$_drawingsDir/$name', data.buffer.asUint8List());
    }

    await writeKV(marker, 'done');
  }
}
