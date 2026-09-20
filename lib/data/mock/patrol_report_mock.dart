import '../models.dart';

/// 已生成巡场报告的演示种子（本地归档为空时由 [reportRecordsProvider] 兜底）。
///
/// 只覆盖默认项目（腾讯大铲湾 DY04 · 7栋）：与 `seedPatrolRecords` 的巡场时间线
/// （8/15、8/22、8/25）对齐，便于和巡场历史互相印证。真实导出过的报告写入
/// LocalStorage 后，种子自动让位（有存储数据即不读种子）。
const List<ReportRecord> seedReportRecords = [
  ReportRecord(
    id: 'rep_demo_2026-08-18',
    projectId: 'tencent-dy04-7',
    projectName: '腾讯大铲湾 DY04 · 7栋',
    title: '现场工作汇报',
    period: '2025-08-11 ~ 2025-08-17',
    reporter: '王工 · 深圳市建工集团 · 现场负责人',
    createdAt: 1755446400000, // 2025-08-18 00:00
    formats: ['PDF', 'Word'],
    defectCount: 12,
    openCount: 4,
    doneCount: 8,
    urgentCount: 2,
    note: '沿 B05 分区平面完成 7 栋 4 层巡场，重点核查墙身防水与机电预留预埋。',
  ),
  ReportRecord(
    id: 'rep_demo_2026-08-25',
    projectId: 'tencent-dy04-7',
    projectName: '腾讯大铲湾 DY04 · 7栋',
    title: '现场工作汇报',
    period: '2025-08-18 ~ 2025-08-24',
    reporter: '王工 · 深圳市建工集团 · 现场负责人',
    createdAt: 1756051200000, // 2025-08-25 00:00
    formats: ['网页链接', 'Excel'],
    defectCount: 7,
    openCount: 3,
    doneCount: 4,
    urgentCount: 1,
    note: '本周巡场 2 次（8/22 南侧偏移复查），新增缺陷 3 条，闭环 5 条。',
  ),
];
