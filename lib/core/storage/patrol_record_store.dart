import 'dart:convert';

import '../storage/local_storage.dart';
import '../../data/models.dart';

/// 巡场完成记录持久化（localStorage / Hive，平台无感）。
///
/// 存储键范式：`patrol_records_v1_<projectId>` → JSON List<PatrolRecord>。
/// 照 [patrol_plan_store.dart] 的 PatrolPlanStore 模式。
class PatrolRecordStore {
  const PatrolRecordStore._();

  static String _key(String projectId) => 'patrol_records_v1_$projectId';

  /// 列出某项目的巡场完成记录；存储为空/解析失败 → 空列表（Provider 层再回退 seed）。
  static Future<List<PatrolRecord>> list(String projectId) async {
    final raw = await LocalStorage.instance.readDoc(_key(projectId));
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        final records = list
            .whereType<Map<String, dynamic>>()
            .map(PatrolRecord.fromJson)
            .toList();
        if (records.isNotEmpty) return records;
      } catch (_) {
        // 解析失败按空兜底，不抛异常
      }
    }
    return const [];
  }

  /// 保存某项目全部记录（覆盖写）。
  static Future<void> save(
      String projectId, List<PatrolRecord> records) async {
    final raw = jsonEncode(records.map((r) => r.toJson()).toList());
    await LocalStorage.instance.writeDoc(_key(projectId), raw);
  }
}
