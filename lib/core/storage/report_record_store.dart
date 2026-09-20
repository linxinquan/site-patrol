import 'dart:convert';

import '../storage/local_storage.dart';
import '../../data/models.dart';

/// 巡场报告归档持久化（localStorage / Hive，平台无感）。
///
/// 存储键范式：`report_records_v1_<projectId>` → JSON List<ReportRecord>。
/// 照 [patrol_record_store.dart] 的 PatrolRecordStore 模式。
class ReportRecordStore {
  const ReportRecordStore._();

  static String _key(String projectId) => 'report_records_v1_$projectId';

  /// 列出某项目已生成的报告；存储为空/解析失败 → 空列表（Provider 层再回退种子）。
  static Future<List<ReportRecord>> list(String projectId) async {
    final raw = await LocalStorage.instance.readDoc(_key(projectId));
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .whereType<Map<String, dynamic>>()
            .map(ReportRecord.fromJson)
            .toList();
      } catch (_) {
        // 解析失败按空兜底，不抛异常
      }
    }
    return const [];
  }

  /// 写入一条归档：同一「标题 + 周期」视为同一份报告（合并格式标签、刷新统计与
  /// 生成时间），避免同一次汇报导出 PDF / Excel 两次就在列表里出现两张卡。
  /// 新记录插到最前（列表按生成时间倒序展示）。
  static Future<void> upsert(String projectId, ReportRecord r) async {
    final all = [...await list(projectId)];
    final i =
        all.indexWhere((e) => e.title == r.title && e.period == r.period);
    if (i >= 0) {
      final old = all.removeAt(i);
      all.insert(
        0,
        r.copyWith(id: old.id, formats: _mergeFormats(old.formats, r.formats)),
      );
    } else {
      all.insert(0, r);
    }
    await LocalStorage.instance.writeDoc(
        _key(projectId), jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> delete(String projectId, String id) async {
    final all = await list(projectId);
    await LocalStorage.instance.writeDoc(
      _key(projectId),
      jsonEncode(all.where((e) => e.id != id).map((e) => e.toJson()).toList()),
    );
  }

  /// 保持原顺序合并去重（旧格式在前，新增格式追加）。
  static List<String> _mergeFormats(List<String> old, List<String> add) {
    final out = <String>[...old];
    for (final f in add) {
      if (!out.contains(f)) out.add(f);
    }
    return out;
  }
}
