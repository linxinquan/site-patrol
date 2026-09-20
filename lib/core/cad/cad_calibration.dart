import 'dart:convert';

import '../storage/local_storage.dart';
import '../utils/cad_coord.dart';

/// 校准参数本地存储：每张图纸**每个版本**的坐标校准系数（仿射 {a,b,c,d,e,f}）离线持久化。
///
/// 数据来源：截图底图 + 单点/两点/轴网自动校准生成的仿射系数（与 web/cad_viewer_hybrid.html
/// 的 `cad_calib` / 分享链接 / 离线文件格式一致）。存储格式为 JSON。
///
/// ⚠️ **校准必须绑图纸版本**：图纸一改版，图面坐标系就变了，沿用旧校准会让历史坐标
/// **静默错位**（界面不报错，只是指到别的房间）。因此存储键为
/// `cad_calib_v4_<drawingKey>__<drawingVersionId>`。
///
/// 兼容：版本化之前的老数据存在 `cad_calib_v3_<drawingKey>`，读取时**视为当前版本**
/// 并自动迁移到 v4 键（只做一次，读走即迁），保证既有现场校准不丢。
///
/// 离线设计：工地无网时校准参数从本机读取，随 App 打包，不依赖服务器。
class CadCalibrationStore {
  CadCalibrationStore(this._storage);

  final LocalStorage _storage;

  /// v4 文档 key 前缀（按图纸 + 版本分档）。
  static const _prefix = 'cad_calib_v4_';

  /// v3 文档 key 前缀（版本化之前的按图纸存储，只读兼容 + 迁移）。
  static const _legacyPrefix = 'cad_calib_v3_';

  /// 未版本化图纸的档位后缀（显式标记，避免与将来真实的版本号冲突）。
  static const _unversioned = '__unversioned';

  String _key(String drawingKey, String versionId) =>
      '$_prefix$drawingKey${versionId.isEmpty ? _unversioned : '__$versionId'}';

  String _legacyKey(String drawingKey) => '$_legacyPrefix$drawingKey';

  /// 读取指定图纸 + 版本的校准映射；不存在返回 null。
  ///
  /// [versionId] 为空 = 该图纸尚未版本化（预置演示图 / 后台未发布）。
  /// 命中旧版（v3）键时自动迁移到当前键并返回，保证老校准不丢。
  Future<CadCoordMapper?> readCalibration(
    String drawingKey, {
    String versionId = '',
  }) async {
    try {
      final primary = await _readMapper(_key(drawingKey, versionId));
      if (primary != null) return primary;

      // 兼容迁移：版本化之前按「图纸」存的校准 → 归到当前版本档位。
      final legacyRaw = await _storage.readDoc(_legacyKey(drawingKey));
      if (legacyRaw == null || legacyRaw.isEmpty) return null;
      final mapper = _decodeMapper(legacyRaw);
      if (mapper == null) return null;
      await _storage.writeDoc(_key(drawingKey, versionId), legacyRaw);
      return mapper;
    } catch (_) {
      return null;
    }
  }

  /// 保存指定图纸 + 版本的校准映射。
  Future<void> saveCalibration(
    String drawingKey,
    CadCoordMapper mapper, {
    String versionId = '',
  }) async {
    await _storage.writeDoc(
      _key(drawingKey, versionId),
      jsonEncode(mapper.toCalibrationMap()),
    );
  }

  /// 删除指定图纸 + 版本的校准映射。
  ///
  /// [versionId] 为空时（未版本化图纸）一并清理旧版（v3）键。
  Future<void> deleteCalibration(
    String drawingKey, {
    String versionId = '',
  }) async {
    await _storage.deleteDoc(_key(drawingKey, versionId));
    if (versionId.isEmpty) {
      await _storage.deleteDoc(_legacyKey(drawingKey));
    }
  }

  Future<CadCoordMapper?> _readMapper(String key) async {
    final raw = await _storage.readDoc(key);
    if (raw == null || raw.isEmpty) return null;
    return _decodeMapper(raw);
  }

  CadCoordMapper? _decodeMapper(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic>) return null;
    return CadCoordMapper.fromCalibrationMap(j);
  }

  // ---- 原始浏览器校准 JSON（导出/导入用，便于弹窗预填与回溯） ----

  /// 原始 JSON 文档 key（与系数 key 区分，避免 toCalibrationMap 二次转换丢字段）。
  String _rawKey(String drawingKey, String versionId) =>
      '${_key(drawingKey, versionId)}__raw';

  String _legacyRawKey(String drawingKey) => '${_legacyPrefix}raw_$drawingKey';

  /// 保存浏览器导出的原始校准 JSON 文本（如含 m 字段的分享串）。
  /// 用于下次打开校准弹窗时直接预填，免重复粘贴。
  Future<void> saveRawJson(
    String drawingKey,
    String rawJson, {
    String versionId = '',
  }) async {
    await _storage.writeDoc(_rawKey(drawingKey, versionId), rawJson);
  }

  /// 读取持久化的原始校准 JSON 文本；未保存返回 null（旧版键一并兼容）。
  Future<String?> readRawJson(
    String drawingKey, {
    String versionId = '',
  }) async {
    final raw = await _storage.readDoc(_rawKey(drawingKey, versionId));
    if (raw != null && raw.trim().isNotEmpty) return raw;
    final legacy = await _storage.readDoc(_legacyRawKey(drawingKey));
    if (legacy == null || legacy.trim().isEmpty) return null;
    // 迁移到当前版本档位，后续不再读旧键。
    await _storage.writeDoc(_rawKey(drawingKey, versionId), legacy);
    return legacy;
  }

  /// 删除持久化的原始校准 JSON 文本（通常与 deleteCalibration 成对调用）。
  Future<void> deleteRawJson(
    String drawingKey, {
    String versionId = '',
  }) async {
    await _storage.deleteDoc(_rawKey(drawingKey, versionId));
    if (versionId.isEmpty) {
      await _storage.deleteDoc(_legacyRawKey(drawingKey));
    }
  }
}

/// 校准库：所有已校准图纸的本地清单。
///
/// 解决“多图纸批量场景”下每次进入都要校准的问题——只要某图纸校准过一次，
/// 其 key 与参数就被登记进清单；App 启动时 [applyLibraryToProviders] / 
/// `applyCalibrationLibrary` 会把清单里所有图纸的坐标映射一次性灌入内存，
/// 后续打开任意图纸自动套用，无需手动粘贴。
///
/// 存储：固定 key `cad_calib_library_v1` 的 JSON 文档，结构：
/// ```json
/// {
///   "<drawingKey>": {
///     "raw": "<浏览器原始 JSON 文本，用于弹窗预填>",
///     "map": { "viewWidth":..., "viewHeight":..., "a":..., ... },
///     "drawingVersionId": "<校准时的图纸版本；空串 = 未版本化>"
///   }
/// }
/// ```
class CalibrationLibrary {
  CalibrationLibrary(this._storage);

  final LocalStorage _storage;

  static const _kLibraryKey = 'cad_calib_library_v1';

  /// 读取整个清单；未初始化返回空 Map。
  Future<Map<String, dynamic>> _readAll() async {
    final raw = await _storage.readDoc(_kLibraryKey);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      return j is Map<String, dynamic> ? j : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, dynamic> all) async {
    await _storage.writeDoc(_kLibraryKey, jsonEncode(all));
  }

  /// 登记/更新一个图纸的校准（系数 + 原始 JSON + 校准时的图纸版本）。
  Future<void> upsert(
    String drawingKey,
    CadCoordMapper mapper,
    String? rawJson, {
    String drawingVersionId = '',
  }) async {
    final all = await _readAll();
    all[drawingKey] = {
      'raw': rawJson,
      'map': mapper.toCalibrationMap(),
      'drawingVersionId': drawingVersionId,
    };
    await _writeAll(all);
  }

  /// 从清单移除一个图纸。
  Future<void> remove(String drawingKey) async {
    final all = await _readAll();
    all.remove(drawingKey);
    await _writeAll(all);
  }

  /// 返回所有已校准图纸的 key 列表。
  Future<List<String>> listCalibrated() async {
    final all = await _readAll();
    return all.keys.toList();
  }

  /// 读取某图纸登记的原始 JSON（用于弹窗预填）；未登记返回 null。
  Future<String?> readRaw(String drawingKey) async {
    final all = await _readAll();
    final entry = all[drawingKey];
    if (entry is Map && entry['raw'] is String) {
      final r = entry['raw'] as String;
      return r.trim().isEmpty ? null : r;
    }
    return null;
  }

  /// 根据清单构建所有已校准图纸的映射表（key → CadCoordMapper）。
  /// 调用方负责把结果灌入内存 provider（保持本类不依赖 riverpod，避免循环引用）。
  ///
  /// [currentVersions] 为「图纸 → 当前发布版本」的解析表：
  /// 校准时的版本与当前版本不一致时**跳过该条**（图纸已改版，校准失效，
  /// 应由驻场重新校准，而不是让旧坐标静默错位）。
  /// 传 null 表示不做版本校验（旧行为）。
  Future<Map<String, CadCoordMapper>> buildAll({
    Map<String, String>? currentVersions,
  }) async {
    final all = await _readAll();
    final result = <String, CadCoordMapper>{};
    for (final e in all.entries) {
      final entry = e.value;
      if (entry is! Map || entry['map'] is! Map) continue;

      if (currentVersions != null) {
        final expected = currentVersions[e.key];
        final stored = entry['drawingVersionId']?.toString() ?? '';
        // expected 为 null = 该图纸不在当前图纸表中（如已删除）→ 不拦截。
        if (expected != null && expected.isNotEmpty && expected != stored) {
          continue;
        }
      }

      try {
        result[e.key] = CadCoordMapper.fromCalibrationMap(
          (entry['map'] as Map).cast<String, dynamic>(),
        );
      } catch (_) {
        // 单条损坏不影响其余。
      }
    }
    return result;
  }
}
