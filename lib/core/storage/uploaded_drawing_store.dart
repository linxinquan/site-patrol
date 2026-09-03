import 'dart:convert';

import '../storage/local_storage.dart';
import '../../data/models.dart';

/// 用户自助上传 DWG 的登记存储（任务3）。键：`uploaded_drawings_v1_<projectId>`。
/// 只登记元数据（key/名称/状态）；OCF 文件由 CAD 服务(ocf_server 8800)落盘并提供分发。
class UploadedDrawingStore {
  const UploadedDrawingStore._();

  static String _key(String projectId) => 'uploaded_drawings_v1_$projectId';

  static Future<List<UploadedDrawing>> list(String projectId) async {
    final raw = await LocalStorage.instance.readDoc(_key(projectId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(UploadedDrawing.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(
      String projectId, List<UploadedDrawing> items) async {
    final raw = jsonEncode(items.map((e) => e.toJson()).toList());
    await LocalStorage.instance.writeDoc(_key(projectId), raw);
  }
}
