任务：量房功能 · 段3（RoomPlan 原生封装 + MethodChannel 契约 + 安卓调研文档）

范围：只做 `ROOM_MEASURE_IMPL_DETAIL.md` 的 §9~§10。前提：段1/段2 已完成并验收（模型/引擎/存储/页面/报告四端都在）。
⚠️ 本段 iOS 原生部分 **Windows 本机不可编译**——交付物是"代码+契约+未验证清单"，**禁止伪造任何验证结果**。

工作目录：F:\建筑验收工具\site-patrol

──────── 第一步 · 前置检查（读文件确认现状，以最新代码为准） ────────
1. `ios/Runner/ArMeasureView.swift` + `ArMeasureViewFactory.swift` + `AppDelegate.swift`：读现有 platform view 注册范式（viewType、channel 命名、messenger 传递）→ §9.5 照同款新增 RoomPlan 的 view/factory/channel。
2. `ios/Runner/Info.plist`：确认已有 NSCameraUsageDescription（RoomPlan 扫描需相机）。
3. `lib/core/ar/ar_measure_service.dart`（或同目录服务）：读 MethodChannel 封装写法 → §9.4 `room_capture_service.dart` 照同款。
4. `lib/app.dart`：段2已加 4 条量房路由 → 本段需把 `/room-scan`（自动扫描页）从占位接真（若段2留了占位）；若路由未含则补。
5. `ROOM_MEASURE_IMPL_DETAIL.md` §9 的骨架/契约、§10 说明为唯一规格源，照做。
6. RoomPlan 是 iOS16+ 系统框架（ARKit 家族），**无需新增 Pod**；确认 pubspec 不加任何新依赖。

──────── 第二步 · 实现顺序（代码按序产出，全部标注 [待真机]） ────────
A. `ios/Runner/RoomCaptureController.swift`（按 DETAIL §9.1 骨架补全）：
   - RoomCaptureSession 生命周期 start/stop、RoomBuilder、delegate 回调（didUpdate/didEndWith/didStartWith/didFailWithError）
   - `buildJson(from room:)` 按 §9.3 JSON 契约输出（walls/doors/windows/objects，米→毫米 ×1000，字段名与契约一致）
   - channel：`room_capture`；方法 isSupported/start/stop/exportJson；回调 onScanned(json)/onError(msg)
   - 权限：AVCaptureDevice 相机授权检查，拒绝走 onError（照 ArMeasureView 的处理）
B. `ios/Runner/RoomCapturePlatformView.swift` + `RoomCapturePlatformViewFactory.swift`：承载 RoomCaptureView 的 platform view（照 ArMeasureViewFactory 模式），viewType `room_capture_view`
C. `AppDelegate.swift`：注册 RoomCapture view factory + 通道（照 ArMeasure 注册追加，勿覆盖现有）
D. `lib/core/room/room_capture_service.dart`（Dart 封装，照 ar_measure_service 模式）：isSupported/start/stop/exportJson + onScanned/onError 处理
E. `lib/features/room/room_auto_scan_page.dart`（Dart，可写可 Web 审）：
   - `isRoomPlanSupported==false`（Web/安卓/非 Pro）→ 提示页 + 「用手动成图」按钮 → 跳 /room-draw（source:'manual'）
   - 支持 → 全屏 UiKitView(viewType room_capture_view) + 顶部引导文案（"从门口开始，绕房间缓慢走一圈…"）+ 底部「完成扫描」
   - 收 onScanned(json) → 解析 §9.3 JSON → 组装墙段序列（首尾相接）→ 转 RoomWall（doors/windows→openings）→ 跳 room_draw_page 确认修正（source:'roomplan'）
F. §10：`ANDROID_AR_RESEARCH.md` **追加**「量房成图」节：有 GMS 安卓实测 `ar_flutter_plugin_plus` 墙角打点可行性（若已实测过记录数据；未实测如实写"待实测"）；无 GMS → 结论"安卓主路径=手动/照片成图（P0 已实现）"；**只写文档，不写产品代码**

──────── 第三步 · 验证（本段能验的） ────────
1. `flutter analyze`（崩溃则 `dart analyze lib/core/room lib/features/room/room_auto_scan_page.dart`）→ 0 error（Dart 侧）
2. `flutter build web --release` 通过（auto_scan 页在 Web 走 isSupported=false 分支不报错）
3. iOS/Swift：**本机不编译**；交付时逐文件标注"未编译未联调"
4. 走查：RoomCaptureController 与 ArMeasureView 的通道/view 命名不冲突；AppDelegate 注册无重复

──────── 第四步 · 红线 ────────
- 不新增 Pod/第三方依赖；不改 ArMeasure 现有 iOS 文件（只新增文件 + AppDelegate 追加注册）
- [待真机] 项（isSupported/扫描/exportJson/onScanned/权限）全部列入"未验证清单"，**不伪造**
- models 不新增字段（JSON 解析直接映射段1的 WallOpening/RoomWall 等已有模型）
- §10 调研不写产品代码

──────── 第五步 · 输出 ────────
1. 新增文件清单（Dart/Swift 各列出，标 [待真机]）
2. Dart analyze / Web 构建结果
3. MethodChannel 契约表（方法/参数/返回/回调）确认与 §9.2 一致
4. "未验证清单"（真机必测项）
5. ANDROID_AR_RESEARCH.md 追加节的结论
