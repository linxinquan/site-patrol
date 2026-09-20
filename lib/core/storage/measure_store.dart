import 'dart:convert';

import '../storage/local_storage.dart';
import '../../data/models.dart';

/// 拍照量尺校对会话持久化（localStorage / Hive，平台无感）。
///
/// 存储键范式：`measure:<projectKey>:<drawingKey>` → JSON（目前按图纸唯一会话）。
/// 设计见 docs/archive/MEASURE_FEATURE_PLAN.md §3「数据持久化」。
///
/// 序列化**直接复用 [MeasureSession.toJson] / [MeasureSession.fromJson]**：
/// 原先此处另写了一份内联序列化，漏掉了 `sync`（同步元数据）——
/// 而落库实际走的是本类，导致同步元数据在存取过程中被丢弃。
/// 统一到模型后，「落库形态由模型唯一决定」这条约定才真正成立。
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
      return MeasureSession.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(MeasureSession s) async {
    await LocalStorage.instance
        .writeDoc(_key(s.projectKey, s.drawingKey), jsonEncode(s.toJson()));
  }
}
