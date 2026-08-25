import 'dart:convert';

import '../storage/local_storage.dart';
import '../../data/models.dart';
import '../../data/mock/mock_data.dart' show seedPatrolPlans;

/// 巡场路线持久化（localStorage / Hive，平台无感）。
///
/// 存储键范式：`patrol_plans_v1_<projectId>` → JSON List<PatrolPlan>。
/// 设计见 PATROL_OPTIMIZE.md 阶段一「② PatrolPlan 模型化」。
class PatrolPlanStore {
  const PatrolPlanStore._();

  static String _key(String projectId) => 'patrol_plans_v1_$projectId';

  /// 列出某项目的巡场路线。
  /// 首次读取（存储为空）时返回该项目种子，不强制写库；用户保存编辑后才写库。
  /// 旧数据/解析失败一律回退种子，不抛异常。
  static Future<List<PatrolPlan>> list(String projectId) async {
    final raw = await LocalStorage.instance.readDoc(_key(projectId));
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        final plans = list
            .whereType<Map<String, dynamic>>()
            .map(PatrolPlan.fromJson)
            .toList();
        if (plans.isNotEmpty) return plans;
      } catch (_) {
        // 解析失败按种子兜底
      }
    }
    return seedPatrolPlans.where((p) => p.projectId == projectId).toList();
  }

  /// 保存某项目全部路线（覆盖写）。
  static Future<void> save(String projectId, List<PatrolPlan> plans) async {
    final raw = jsonEncode(plans.map((p) => p.toJson()).toList());
    await LocalStorage.instance.writeDoc(_key(projectId), raw);
  }
}
