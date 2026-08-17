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
}
