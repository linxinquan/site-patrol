# 量房段2 · Widget 测试替代截图（交付 CodeBuddy，用户无电脑时的验收替代）

> 背景：段2 动态验收原计划"人工点 Web 截图 4 张"；用户下班无电脑 → 改由 **widget 测试程序化覆盖手动流程**（比截图更能回归）。本文件给出目标与实现口径；**若 LocalStorage 无法在测试注入，如实降级并说明**，不硬编假结果。
> 先读：`lib/features/room/room_draw_page.dart`、`room_records_page.dart`、`lib/core/storage/local_storage.dart`（确认测试环境下的存储实现/Hive 初始化方式）、`test/` 现有测试写法与 pubspec 的 flutter_test。

## 目标行为（对应用户原人工清单）
1. 成图页可"点 4 角"并给出 周长/面积/闭合差；点回起点闭合后闭合差=记录缺口
2. 双击墙段可加"门/窗"洞口（含超范围校验提示）
3. 保存（≥3 点、闭合差>50 弹确认）→ RoomScanRecord 落库（source='manual'）
4. 列表页显示该记录（名称/面积/闭合差色标），长按可删

## 测试文件与用例建议（新增 `test/room_draw_flow_test.dart`）
实现时以"可跑、不崩、断言关键数值"为准；页面内部状态为私有 → 通过**手势事件**驱动（tester.tapAt / longPress / doubleTap），坐标注意 InteractiveViewer 变换（进入页 _resetView 后 scale≈0.12+translate(80,80)；画布 8000×8000，屏幕坐标→画布坐标=先平移反算再缩放）。

- T1 空列表态：pump `RoomRecordsPage`（ProviderScope overrides: currentProjectIdProvider='p1'）→ expect 空态文案存在、无异常
- T2 保存一条：pump `RoomDrawPage(args: RoomScanArgs(projectKey:'p1'))` → 依屏幕坐标 tap 4 个成矩形点（先算好屏幕落点）→ 底部状态条出现 面积≈期望值（容许闭合差逻辑差异）→ 点"保存" → 期望 Navigator pop / 或 RoomScanStore.list('p1') 出现 1 条 name='房间'（若 LocalStorage 可用）
- T3 闭合差确认流：4 点后不点回起点直接保存 → 若缺口>50 期望弹"闭合差偏大"对话框
- T4 洞口校验：双击墙段 → 填 offset+宽 超出墙长 → 期望 danger 提示不崩溃
- T5 记录卡渲染：预置一条 record（直接构造 RoomScanRecord）→ pump RecordsPage → expect 卡内出现 name 与 '㎡'、闭合差文案

## 关键实现提示
1. LocalStorage：先读实现；若是 Hive/平台通道，测试需 `TestWidgetsFlutterBinding.ensureInitialized()` 并按现有 mock 通道处理；做不到注入 → 把 T2/T5 降级为"构造 store 的内存假实现注入"或在交付说明标注"无法自动化、仍待人工"，**不许绕过断言假装通过**
2. 坐标换算助手：抽一个纯函数（屏幕→画布 mm），在测试里复用与页面相同的 0.12/translate 常量
3. 每条用例失败时输出实际值便于定位（expect 信息带期望/实际）
4. 跑完：`flutter test test/room_draw_flow_test.dart` 全绿为通过；`flutter analyze` 0 error

## 交付输出
1. 新增测试文件与用例清单（各自断言了什么）
2. flutter test 结果
3. 若部分用例无法注入/不可测：列出并给出替代（人工项清单），**不伪造**
