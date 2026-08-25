import 'dart:convert';

import '../storage/local_storage.dart';
import '../../data/models.dart';

/// 拍照量尺校对会话持久化（localStorage / Hive，平台无感）。
///
/// 存储键范式：`measure:<projectKey>:<drawingKey>` → JSON（目前按图纸唯一会话）。
/// 设计见 MEASURE_FEATURE_PLAN.md §3「数据持久化」。
class MeasureStore {
  const MeasureStore._();

  static String _key(String projectKey, String drawingKey) =>
      'measure:$projectKey:$drawingKey';

  static Future<MeasureSession?> load(
    String projectKey,
    String drawingKey,
  ) async {
    final raw = await LocalStorage.instance
        .readDoc(_key(projectKey, drawingKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return _fromJson(m);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(MeasureSession s) async {
    await LocalStorage.instance
        .writeDoc(_key(s.projectKey, s.drawingKey), jsonEncode(_toJson(s)));
  }

  static Map<String, dynamic> _toJson(MeasureSession s) => {
        'id': s.id,
        'projectKey': s.projectKey,
        'drawingKey': s.drawingKey,
        'floor': s.floor,
        'tolMm': s.tolMm,
        'tolPct': s.tolPct,
        'photoCalib': s.photoCalib?.toJson(),
        'items': s.items
            .map((e) => {
                  'name': e.name,
                  'drawingMm': e.drawingMm,
                  'photoMm': e.photoMm,
                  'source': e.source,
                })
            .toList(),
        'updatedAt': s.updatedAt,
      };

  static MeasureSession _fromJson(Map<String, dynamic> m) {
    final calib = m['photoCalib'] as Map<String, dynamic>?;
    return MeasureSession(
      id: m['id'] as String,
      projectKey: m['projectKey'] as String,
      drawingKey: m['drawingKey'] as String,
      floor: m['floor'] as String? ?? '',
      tolMm: (m['tolMm'] as num? ?? 5).toDouble(),
      tolPct: (m['tolPct'] as num? ?? 2).toDouble(),
      photoCalib: calib == null ? null : PhotoCalib.fromJson(calib),
      items: (m['items'] as List? ?? [])
          .map((e) => (e as Map<String, dynamic>))
          .map((e) => MeasureItem(
            name: e['name'] as String? ?? '',
            drawingMm: (e['drawingMm'] as num? ?? 0).toDouble(),
            photoMm: (e['photoMm'] as num? ?? 0).toDouble(),
            source: e['source'] as String? ?? 'photo',
          ))
          .toList(),
      updatedAt: (m['updatedAt'] as num? ?? 0).toInt(),
    );
  }
}
