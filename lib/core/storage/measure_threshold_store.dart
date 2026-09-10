import 'dart:convert';

import 'local_storage.dart';

/// 量尺判定门槛（**项目级**设置）。
///
/// 为什么要有它：容差与"可判定"的门槛是**项目/合同约定**，不是写死在代码里的
/// 常数——公装和家装的允许偏差不同、精细木作与抹灰更不是一个量级。
/// 把 15mm/2%、以及"误差带多大才允许下结论"做成可配置，避免把
/// 某一个项目的口径硬编码给所有项目。
///
/// 判定规则（与 `MeasureItem.canJudge` 同源）：
/// - 误差带 ≤ [effectiveJudgeMax] → 允许给「合格 / 超差」；
/// - 否则一律「需卷尺复核（误差过大）」。
class MeasureThresholds {
  /// 判定容差（mm）。
  final double tolMm;

  /// 判定容差（%）。
  final double tolPct;

  /// 误差带门槛（±mm）：误差带 ≤ 该值才允许判定；null = 用容差/3（测量不确定度规约）。
  final double? judgeMaxErrorMm;

  const MeasureThresholds({
    this.tolMm = 15,
    this.tolPct = 2,
    this.judgeMaxErrorMm,
  });

  /// 实际生效的误差带门槛。
  double get effectiveJudgeMax => judgeMaxErrorMm ?? tolMm / 3;

  /// 门槛是否被显式配置过（界面用于提示"当前为默认值"）。
  bool get isDefault =>
      tolMm == 15 && tolPct == 2 && judgeMaxErrorMm == null;

  /// 人类可读的一句话（界面与报告共用）。
  String get summary =>
      '容差 ±${_trim(tolMm)}mm / ${_trim(tolPct)}%，'
      '误差带 ≤${_trim(effectiveJudgeMax)}mm 才判定';

  static String _trim(num v) {
    final d = v.toDouble();
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  MeasureThresholds copyWith({
    double? tolMm,
    double? tolPct,
    double? judgeMaxErrorMm,
    bool clearJudgeMax = false,
  }) =>
      MeasureThresholds(
        tolMm: tolMm ?? this.tolMm,
        tolPct: tolPct ?? this.tolPct,
        judgeMaxErrorMm:
            clearJudgeMax ? null : (judgeMaxErrorMm ?? this.judgeMaxErrorMm),
      );

  Map<String, dynamic> toJson() => {
        'tolMm': tolMm,
        'tolPct': tolPct,
        if (judgeMaxErrorMm != null) 'judgeMaxErrorMm': judgeMaxErrorMm,
      };

  factory MeasureThresholds.fromJson(Map<String, dynamic> m) =>
      MeasureThresholds(
        tolMm: (m['tolMm'] as num? ?? 15).toDouble(),
        tolPct: (m['tolPct'] as num? ?? 2).toDouble(),
        judgeMaxErrorMm: (m['judgeMaxErrorMm'] as num?)?.toDouble(),
      );
}

/// 项目级判定门槛的持久化（键：`measure_thresholds_v1:<projectKey>`）。
class MeasureThresholdStore {
  const MeasureThresholdStore._();

  static String _key(String projectKey) =>
      'measure_thresholds_v1:$projectKey';

  /// 读取项目门槛；未配置或解析失败 → 返回默认值（不抛异常）。
  static Future<MeasureThresholds> load(String projectKey) async {
    if (projectKey.isEmpty) return const MeasureThresholds();
    final raw = await LocalStorage.instance.readDoc(_key(projectKey));
    if (raw == null || raw.isEmpty) return const MeasureThresholds();
    try {
      return MeasureThresholds.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const MeasureThresholds();
    }
  }

  static Future<void> save(
      String projectKey, MeasureThresholds t) async {
    if (projectKey.isEmpty) return;
    await LocalStorage.instance
        .writeDoc(_key(projectKey), jsonEncode(t.toJson()));
  }

  static Future<void> clear(String projectKey) async {
    if (projectKey.isEmpty) return;
    await LocalStorage.instance.deleteDoc(_key(projectKey));
  }
}
