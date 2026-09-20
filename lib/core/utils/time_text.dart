/// 文本时间 ↔ 规范时间戳（epoch ms）的换算工具。
///
/// 为什么需要它：本项目历史数据里的时间字段是**展示文本**
/// （`yyyy-MM-dd HH:mm` / `yyyy-MM-dd HH:mm:ss`），而后端需要
/// `timestamptz`。这些文本**无损可换算**，不需要迁移存量数据，
/// 只在同步/落库时用本函数转一次即可。
///
/// 纯日期语义（如 `Milestone.date`、`DrawingVersion.versionDate`）不带时刻，
/// 继续保持 `yyyy-MM-dd` 文本，不走本函数。
library;

/// 文本时间 → epoch 毫秒（0 = 解析失败 / 空）。
///
/// 兼容本项目历史格式（`yyyy-MM-dd HH:mm`、`yyyy-MM-dd HH:mm:ss`）与 ISO 8601。
/// 解析失败返回 0 且**不抛异常**，供同步层安全换算。
int msFromTsText(String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return 0;
  final iso = t.contains('T') ? t : t.replaceFirst(' ', 'T');
  return DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0;
}
