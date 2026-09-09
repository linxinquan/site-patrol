import 'dart:convert';

import 'local_storage.dart';
import '../../data/models.dart';

/// 量房记录持久化：key = `room_scan_v1_<projectId>` → JSON List。
class RoomScanStore {
  const RoomScanStore._();

  static String _key(String projectId) => 'room_scan_v1_$projectId';

  static Future<List<RoomScanRecord>> list(String projectId) async {
    final raw = await LocalStorage.instance.readDoc(_key(projectId));
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return arr
          .map((e) => RoomScanRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 保存（按 id upsert，新记录插头部）。旧数据无此 key → 空列表，不报错。
  static Future<void> save(String projectId, RoomScanRecord r) async {
    final all = [...await list(projectId)];
    final i = all.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      all[i] = r;
    } else {
      all.insert(0, r);
    }
    await LocalStorage.instance
        .writeDoc(_key(projectId), jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> delete(String projectId, String id) async {
    final all = await list(projectId);
    await LocalStorage.instance.writeDoc(_key(projectId),
        jsonEncode(all.where((e) => e.id != id).map((e) => e.toJson()).toList()));
  }
}
