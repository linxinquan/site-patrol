import 'dart:convert';

import '../storage/local_storage.dart';
import '../utils/cad_coord.dart';

/// 校准参数本地存储：每张图纸的坐标校准系数（仿射 {a,b,c,d,e,f}）离线持久化。
///
/// 数据来源：截图底图 + 单点/两点校准生成的仿射系数（与 web/cad_viewer_hybrid.html
/// 的 `cad_calib` / 分享链接 / 离线文件格式一致）。存储格式为 JSON。
///
/// 离线设计：工地无网时校准参数从本机读取，随 App 打包，不依赖服务器。
class CadCalibrationStore {
  CadCalibrationStore(this._storage);

  final LocalStorage _storage;

  /// 校准参数在 LocalStorage 中的文档 key 前缀。
  static const _prefix = 'cad_calib_v3_';

  String _key(String drawingKey) => '$_prefix$drawingKey';

  /// 读取指定图纸的校准映射；不存在返回 null。
  Future<CadCoordMapper?> readCalibration(String drawingKey) async {
    try {
      final raw = await _storage.readDoc(_key(drawingKey));
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      return CadCoordMapper.fromCalibrationMap(j);
    } catch (_) {
      return null;
    }
  }

  /// 保存指定图纸的校准映射。
  Future<void> saveCalibration(String drawingKey, CadCoordMapper mapper) async {
    final j = mapper.toCalibrationMap();
    await _storage.writeDoc(_key(drawingKey), jsonEncode(j));
  }

  /// 删除指定图纸的校准映射。
  Future<void> deleteCalibration(String drawingKey) async {
    await _storage.deleteDoc(_key(drawingKey));
  }

  // ---- 原始浏览器校准 JSON（导出/导入用，便于弹窗预填与回溯） ----

  /// 原始 JSON 文档 key（与系数 key 区分，避免 toCalibrationMap 二次转换丢字段）。
  String _rawKey(String drawingKey) => '${_prefix}raw_$drawingKey';

  /// 保存浏览器导出的原始校准 JSON 文本（如含 m 字段的分享串）。
  /// 用于下次打开校准弹窗时直接预填，免重复粘贴。
  Future<void> saveRawJson(String drawingKey, String rawJson) async {
    await _storage.writeDoc(_rawKey(drawingKey), rawJson);
  }

  /// 读取持久化的原始校准 JSON 文本；未保存返回 null。
  Future<String?> readRawJson(String drawingKey) async {
    final raw = await _storage.readDoc(_rawKey(drawingKey));
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  /// 删除持久化的原始校准 JSON 文本（通常与 deleteCalibration 成对调用）。
  Future<void> deleteRawJson(String drawingKey) async {
    await _storage.deleteDoc(_rawKey(drawingKey));
  }
}

/// 校准库：所有已校准图纸的本地清单。
///
/// 解决“多图纸批量场景”下每次进入都要校准的问题——只要某图纸校准过一次，
/// 其 key 与参数就被登记进清单；App 启动时 [applyLibraryToProviders] 会把清单里
/// 所有图纸的坐标映射一次性灌入内存，后续打开任意图纸自动套用，无需手动粘贴。
///
/// 存储：固定 key `cad_calib_library_v1` 的 JSON 文档，结构：
/// ```json
/// {
///   "<drawingKey>": {
///     "raw": "<浏览器原始 JSON 文本，用于弹窗预填>",
///     "map": { "viewWidth":..., "viewHeight":..., "a":..., ... }
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

  /// 登记/更新一个图纸的校准（系数 + 原始 JSON）。
  Future<void> upsert(
      String drawingKey, CadCoordMapper mapper, String? rawJson) async {
    final all = await _readAll();
    all[drawingKey] = {
      'raw': rawJson,
      'map': mapper.toCalibrationMap(),
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
  Future<Map<String, CadCoordMapper>> buildAll() async {
    final all = await _readAll();
    final result = <String, CadCoordMapper>{};
    for (final e in all.entries) {
      final entry = e.value;
      if (entry is! Map || entry['map'] is! Map) continue;
      try {
        result[e.key] = CadCoordMapper.fromCalibrationMap(
          entry['map'] as Map<String, dynamic>,
        );
      } catch (_) {
        // 单条损坏不影响其余。
      }
    }
    return result;
  }
}
