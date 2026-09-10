任务：量房段2 收口（widget 测试替代截图 + 2 条审计打磨项 + 文档入库）

前置（先读，以最新代码为准）：
- `WIDGET_TEST_ROOM_P2.md`（widget 测试目标与口径）
- `test/room_export_compat_test.dart`（**已有测试夹具范式**：`TestWidgetsFlutterBinding.ensureInitialized()`、纯数据构造、无 store 依赖 → 新测试照它的写法组织）
- `lib/features/room/room_draw_page.dart`（交互与 painter，注意最新已加 `viewScale` 与"点回起点闭合"）
- `lib/core/storage/local_storage.dart`（判断测试环境能否注入存储）

──────── A. 新增 `test/room_draw_flow_test.dart`（覆盖原人工截图清单） ────────
按 `WIDGET_TEST_ROOM_P2.md` 的 T1~T5 实现，**至少完成 T1/T4/T5**：
- T1 记录列表空态：pump `RoomRecordsPage`（ProviderScope override `currentProjectIdProvider='p1'`）→ 断言空态文案、无异常
- T4 洞口超出范围提示：直接对 `RoomDrawPage` 构造/或对洞口校验逻辑做等价断言（若手势驱动成本高，可抽验证函数并对其断言，**在测试注释里说明替代理由**）
- T5 记录卡渲染：构造一条 `RoomScanRecord`（含 1 个门洞）→ 断言卡片出现 名称/'㎡'/闭合差文案
- T2/T3（点角保存、闭合差确认）若手势+存储注入可行则做；**不可行就如实列出"仍待人工/待真机"**，不伪造、不 skip 假绿
- 断言须带期望/实际信息；文件头注释写明"替代人工截图验收（用户无电脑）"

──────── B. 修 2 条审计打磨项 ────────
1. **painter 重绘**：`room_draw_page.dart` 的 `_RoomGridPainter.shouldRepaint`（≈570 行）用 `old.pts != pts` 等**同一性比较**，而 `_pts/_openings` 是就地修改（`_openings.add(...)`）→ 加洞口后可能不重绘。
   修法（二选一，优先①）：① 变更时换新实例：`_openings = [..._openings, entry]`（同理 pts 变更处保持新列表）；② `shouldRepaint` 改内容比较（`listEquals` + 洞口逐项比）。
   验收：加洞口后立即显示，无需再点/缩放。
2. **尺寸标注引线偏移**：`room_plan_painter.dart` 的 `dimAnchorFor(pts, i, offsetPx: 26)` 传入的是**mm**，详情大图缩放下贴墙。
   修法：改为"先 map 到屏幕坐标再加屏幕像素偏移（如 26px）"，或把 mm 偏移放大到 ≥300mm 并加端线刻度。验收：详情页标注数字离开墙面、可读。

──────── C. 文档入库 ────────
工作区有未跟踪/改动文档，请一并 `git add` 并提交（信息示例：`docs: 量房段2 交接与测试方案（PASTE_*/WIDGET_TEST）+ 看板/上下文更新`）：
`PASTE_MASTER.md`、`PASTE_ROOM_P1.md`、`PASTE_ROOM_P2.md`、`PASTE_ROOM_P3.md`、`WIDGET_TEST_ROOM_P2.md`、`SESSION_CONTEXT.md`、`TASK_DASHBOARD.md`、`ROOM_MEASURE_IMPL_DETAIL.md`

──────── 验证与输出 ────────
1. `flutter test` 全量（含既有 room_geometry/room_export_compat）→ 全绿
2. `flutter analyze` 0 error（崩溃则 `dart analyze <改动目录>`）
3. `flutter build web --release` 通过
4. 输出：①新增测试与断言清单 ②两条打磨项修复前后对比（一句话+关键行）③无法自动化的项如实列出 ④commit hash

红线：不伪造/不 skip 假绿；不改段1已合入的几何语义；不动量尺与 AR 代码；新增测试不引第三方依赖。
