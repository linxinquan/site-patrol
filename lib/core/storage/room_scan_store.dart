import 'dart:convert';

import '../storage/local_storage.dart';
import '../../data/models.dart';

/// 量房记录持久化（照 `MeasureStore` 模式）。
///
/// 存储键范式：`room_scan_v1:<projectId>` → JSON List<RoomScanRecord>。
class RoomScanStore {
  const RoomScanStore._();

  static String _key(String projectId) => 'room_scan_v1:$projectId';

  static Future<List<RoomScanRecord>> list(String projectId) async {
    final raw = await LocalStorage.instance.readDoc(_key(projectId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(RoomScanRecord.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(
    String projectId,
    List<RoomScanRecord> records,
  ) async {
    await LocalStorage.instance
        .writeDoc(_key(projectId), jsonEncode(records.map((e) => e.toJson()).toList()));
  }
}
