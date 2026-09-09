# 量房功能（RoomPlan自动扫描 + 手动定点成图）— 全量实施文档（交付 CodeBuddy）

> 规格源：`MEASURE_ROOM_PLAN.md`（产品/路线/诚实边界）。本文=可执行实施。
> 双场景：①装修量房（净尺寸/门窗/完成面/户型记录）②工地房间核尺（LiDAR量房 vs 图纸对照超差判定）。
> 路线：A=RoomPlan 自动扫描（iOS16+/LiDAR，官方）＋B=手动定点/照片成图（跨平台，本机可验）。
> 平台现实：Windows 本机只能 `flutter analyze` + `flutter build web`；**iOS 原生(RoomPlan/AR扩展)只能写代码不可编译**，标 [原生-待真机]。
> 工作目录：`F:\建筑验收工具\site-patrol`。

---

## 0. 实施分层总览

| 层 | 内容 | 本机可验 |
|---|---|---|
| P0 | 数据模型 + 几何/工程习惯纯函数引擎 + 手动/照片成图页 + 记录列表/详情 + 报告字段（四端） | ✅ Web 可演示 |
| P1 | [原生-待真机] RoomPlan 封装 `RoomCaptureController` + AR 墙角定点模式扩展 + 自动扫描页接通 | ❌ 代码先写，真机联调 |
| P2 | 图纸对照核尺联动（复用校准 + MeasureItem 判定） | ✅ 可做 |
| P3 | 安卓 ARCore 实测评估（出文档，不写产品代码） | 调研 |

**执行建议：P0+P2 现在写（全 Dart/Web 可验）；P1 把 iOS 代码与 MethodChannel 契约写好、标"待联调"，不阻塞 P0。**

---

## P0-1：数据模型（`lib/data/models.dart` 追加，不覆盖）

```dart
// ==================== 量房记录 ====================
/// 墙段洞口（门/窗）：offsetFrom 为该段起点的偏移（mm）。
class WallOpening {
  final String type;        // 'door' | 'window'
  final double offsetFromMm;
  final double widthMm;
  final double? heightMm;   // 门高/窗台高（可空，人工补）
  // copyWith/toJson/fromJson（默认值兜底）
}

/// 量房墙段：局部坐标系 2D 点（mm），长度可由几何自算或 RoomPlan 给。
class RoomWall {
  final String id;
  final double ax, ay, bx, by;   // 局部坐标 mm（首点=原点）
  final double lengthMm;
  final double? thicknessMm;      // 墙厚（人工/图纸补）
  final List<WallOpening> openings;
  // copyWith/toJson/fromJson
}

/// 一次量房记录（source: roomplan | manual | photo）。
class RoomScanRecord {
  final String id;
  final String projectKey;
  final String name;            // 如 "B座 精装样板间 主卧"
  final String source;
  final int scannedAtMs;
  final List<RoomWall> walls;   // 墙段（首尾相接的闭合多边形）
  final double? closureDeltaMm; // 闭合差（自动算/扫描给）
  final double? netHeightMm;    // 净高（可空）
  final String? drawingKey;     // 关联图纸（核尺场景）
  final String? rawJson;        // RoomPlan 原始输出/或本记录扩展（大字段可存文件路径）
  final List<MeasureItem> checks; // 图纸对照判定项（复用现有 MeasureItem）
  final String? note;
  // copyWith/toJson/fromJson（全默认值兜底）；房间面积由几何实时算不入库
}

class RoomScanArgs {  // 路由参数
  final String? recordId; final String? projectKey; final String? drawingKey;
  const RoomScanArgs({this.recordId, this.projectKey, this.drawingKey});
}
```

存储：新增 `lib/core/storage/room_scan_store.dart`（照 `measure_store.dart`：key `room_scan_v1_<projectId>`，List<RoomScanRecord>）。

## P0-2：几何与工程习惯引擎（`lib/core/room/room_geometry.dart`，纯函数+可单测）

1. `polygonClosureDelta(List<Offset> ptsMm)` → 首尾缺口 mm；`routeHintsForClosure(delta)` → 建议复核哪些段
2. `orthoSnapPoints(List<Offset> pts, {double tolDeg = 5})` → 85~95°夹角吸附为 90°（返回修正后点集 + 被吸附角索引）
3. `roomAreaM2(List<Offset> pts)` → 鞋带公式面积
4. `dimensionLinesFor(walls, {bool net=true})` → 标注布局（每条墙段：中点垂直引出、线端箭头、文本参数），渲染层通用
5. `openingSplit(wall, openings)` → 在墙段上标注洞口打断位置（供绘制）
6. 单位/格式统一（mm / ㎡ / 双精度取舍）——建议直接复用现有 `mm_format.dart`/`fmtMm`

验收：写 6~10 个 dart test（`test/room_geometry_test.dart`）：直角吸附（88°→90°）、闭合差计算、正方形面积、标注引出方向。

## P0-3：成图编辑器（手动定点/照片成图，跨平台主路径）

新增 `lib/features/room/room_draw_page.dart`（照 measure_page 交互经验）：
- 输入两种底：①空白坐标系（装修量房：0.5m 网格纸感）②现场照片（拍照后标定→点墙角的 1px=mm 换算，复用 measure_page 的照片标定逻辑 `_applyRefCalib` 思路）
- 交互：单击加墙角点 → 自动连墙段 → 双击=非正交转折提示 → 拖动点改 → 长按删 → 在墙段上点=加门/窗洞口（弹宽度表单）→ 撤销/清空
- 实时：正交吸附开关（默认开）、显示每段长度mm、周长、面积㎡、闭合差
- 校验条：闭合差 ≤15mm 绿 / >15mm 红+"复核第X段"
- 工程信息卡：名称、净高、墙厚默认（如 200）、房间用途下拉（卧室/客厅/厨房/卫浴…装修场景）
- 保存 → RoomScanRecord(source:'manual') → 列表

## P0-4：记录列表/详情 + 报告接入

- `lib/features/room/room_records_page.dart`：按项目列表（缩略户型图 + 名称/时间/面积/闭合差状态）；详情=户型图 CustomPaint（墙/洞口/尺寸标注/面积文字）+ 工程信息 + 照片证据 + checks
- 报告：`WeeklyReport` 加 `List<RoomScanRecord>`/概要字段（默认空，兼容）；`report_content.dart` 加 `RoomBlock`，**HTML/PDF/DOCX/XLSX 四端同步**渲染量房记录（户型图以 SVG/PNG 字节内嵌，缺失显占位）
- 入口：图纸库/主页加"量房"入口（与"拍照量尺"平级）

## P0-5：图纸对照核尺（场景2，复用校对逻辑）

- 成图/详情页若有关联 `drawingKey`：调校准映射把户型多边形放到图纸坐标 → 与图纸标注关键尺寸逐条对比（或手动逐条对照测量）
- 生成 `checks: List<MeasureItem>`（source:'roomplan'/'manual'）→ 复用现有判定（tolMm/tolPct）与清单展示；进报告"尺寸校对"区
- v0 简化：每面墙一条对比（量得 vs 图纸输入），出偏差表即可

## P1：[原生-待真机] RoomPlan 封装 + AR 墙角模式

### 原生（`ios/Runner/`，只写代码不编译）
- `RoomCaptureController.swift`：
  - 封装 `RoomCaptureSession`/`RoomCaptureView`（RoomPlan，iOS16+）
  - 代理回调：捕获房间墙段/洞口/房间 JSON（`capturedRoom` → `export(to:json)` / `usdz`)
  - MethodChannel `room_capture`：`isRoomPlanSupported` / `start` / `stop` / `exportJson`（返回 JSON 字符串回 Flutter）
  - 权限沿用相机；A11+ 与 LiDAR 判断：`RoomCaptureSession.isSupported`
- 注册：`AppDelegate.swift` 加 view/通道注册（照 ArMeasureView 模式）
- 手动墙角模式：`ArMeasureView.swift` 加"连续角点"模式（每点返回世界坐标，Flutter 侧接墙角序列成墙段）——改动小，仅模式枚举+回调

### Dart 侧（可写可审）
- `lib/core/room/room_capture_service.dart`：MethodChannel 封装（照 ar_measure_service）
- `room_auto_scan_page.dart`：扫描 UI（提示绕房走一圈→骨架预览→跳 `room_draw_page` 修正补洞→工程信息→保存 source:'roomplan'）；`isRoomPlanSupported=false` → 提示并跳手动模式
- **联调验证项全部标注 [待真机]**，交付时列清单

## P2：安卓 ARCore 实测评估（出文档）

`ANDROID_AR_RESEARCH.md`（若旧文件已出结论，追加"量房场景"节）：1 台有 GMS 安卓实测 `ar_flutter_plugin_plus` 量房场景可达性与精度；无 GMS → 结论维持"安卓走照片/手动成图"，不写产品代码。

## 全局红线

1. `models.dart` 追加不覆盖；fromJson 全默认值；不触碰现有 measure/ar/capture 已修逻辑
2. 报告/统计四端同步；照片/户型图缺失显占位不阻断导出
3. [原生-待真机] 代码交付时明确标注"未编译未联调"；不伪造验证结果
4. 每阶段：`flutter analyze` 无 error + `flutter build web --release` 通过 + 改动清单
5. 几何引擎要有测试；不引入未批准第三方依赖（绘制用 CustomPaint，不用图表库）

## 给用户的演示路径（无 Mac/Pro 设备也能先跑）

P0 完成后：Web 端 → "量房" → 手动模式 → 空白底图点 4 角（或选现场照片标定后点角）→ 出房间/尺寸标注/面积/闭合差 → 保存 → 列表/进报告。**演示词：手动成图已能用；自动扫描（RoomPlan）代码已备好，等 iPhone Pro 一到就接通，扫一圈自动出图。**
