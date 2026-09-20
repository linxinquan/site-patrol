/// 数据模型门面（barrel）—— **唯一的数据契约入口**。
///
/// 原先是单文件（≈2,860 行 / 50 个声明），已按**域**拆到 `lib/data/models/`
/// 下 11 个文件；本文件只做 re-export，因此所有
/// `import 'package:gongdi_app/data/models.dart';` 的调用点**无需改动**，
/// 后端同学也仍然只读这一个文件作为契约索引。
///
/// ## 实体总览（域 → 实体 → 后端对应表）
///
/// | 域 | 文件 | 主要实体 | 后端表 |
/// |---|---|---|---|
/// | 认证授权 | `models/auth.dart` | `UserSession` `AuthTokens` `LoginResult` `AuthProfile` `PermissionScope` | `/auth/*` 接口；其中 **`PermissionScope` / `LoginResult` / `AuthProfile` 是派生视图与响应载体，不落表** |
/// | 账号与组织 | `models/account.dart` | `Org` `Discipline` `User` `Membership` | `orgs` / `disciplines` / `users` / `memberships` |
/// | 项目档案 | `models/project.dart` | `Project` `Party` `Milestone` `Floor` `SiteLocation` `ProgressEntry` | `projects` / `floors` / `site_locations` / `progress_entries` |
/// | 缺陷 | `models/defect.dart` | `Defect` + 4 个分级枚举 | `defects` / `defect_events` |
/// | 图纸与版本 | `models/drawing.dart` | `Drawing` `DrawingVersion` `Calibration` `Hotspot` | `drawings` / `drawing_versions` |
/// | 拍照验收 | `models/capture.dart` | `CaptureRecord` `CaptureDefectItem` `VlDefect` | `captures` |
/// | 量尺 | `models/measure.dart` | `MeasureSession` `MeasureItem` `PhotoCalib` | `measure_sessions` |
/// | 巡场 | `models/patrol.dart` | `PatrolPlan` `PatrolRecord` `PatrolPoint` `CheckIn` | `patrol_plans` / `patrol_records` |
/// | 量房 | `models/room.dart` | `RoomScanRecord` `RoomWall` `WallOpening` | `room_scans` |
/// | 报告归档 | `models/report.dart` | `ReportRecord` | `reports` |
/// | CAD（待剥离） | `models/cad_archive.dart` | `DwgInfo` `CadLayer` `UploadedDrawing` 等 | **不必建表** |
/// | 同步元数据 | `../sync_meta.dart` | `SyncMeta` | 各表公共列 |
///
/// ## 两条全局约定
///
/// 1. **落库形态由模型唯一决定**：写入方与读取方共用 `toJson()` / `fromJson()`，
///    不散落「裸 Map 约定」；`fromJson` 一律容错（缺字段回落默认值，不抛异常）。
/// 2. **客户端可写实体才带 `SyncMeta`**（`clientId` / `version` / 时间戳 / 软删）；
///    档案类由服务端维护，走**全量拉取覆盖**，不带增量同步元数据。
library;

export '../core/utils/time_text.dart' show msFromTsText;
export 'models/account.dart';
export 'models/auth.dart';
export 'models/cad_archive.dart';
export 'models/capture.dart';
export 'models/defect.dart';
export 'models/drawing.dart';
export 'models/measure.dart';
export 'models/patrol.dart';
export 'models/project.dart';
export 'models/report.dart';
export 'models/room.dart';
export 'sync_meta.dart';
