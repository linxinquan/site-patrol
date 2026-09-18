任务：量房功能 · 段2（Provider → 路由/入口 → 页面 → 报告四端）

范围：只做 `ROOM_MEASURE_IMPL_DETAIL.md` 的 §5~§8。**禁止**实现 §9（RoomPlan 原生）与 §10（调研）。
前提：段1 已完成并验收（`WallOpening/RoomWall/RoomScanRecord/RoomScanArgs` 在 models.dart；`room_scan_store.dart`；`room_geometry.dart`；`test/room_geometry_test.dart` 全绿）。**不要重复添加段1任何内容。**

工作目录：F:\建筑验收工具\site-patrol（Windows，不能编 iOS；报告导出验证走 Web）

──────── 第一步 · 前置检查（读文件确认现状，迭代快，以最新代码为准） ────────
1. `lib/core/di/providers.dart`：读 `currentProjectIdProvider / projectProvider / defectsProvider` 的写法 → §5 的 `roomScansProvider` 照同款（family by projectId）。
2. `lib/app.dart`：读 MeasurePage / PatrolPage 的路由注册与 extra 传参模式 → §6 加 4 条路由（/room-records、/room-draw、/room-detail、/room-scan，extra=`RoomScanArgs`）。
3. 入口：读 `lib/features/home/home_page.dart` 的快捷操作区 与 `lib/features/measure/measure_page.dart` 顶部/底部是否有"量尺/AR"入口按钮 → 在同类位置加「量房」入口（图标+文案照现有风格）。
4. `lib/data/models.dart`：
   a. 确认段1 的量房模型已存在（有则跳过）；
   b. **`MeasureItem` 的 `toJson/fromJson` 现在有没有？**（段1 若已给 RoomScanRecord 补过则应有）——有则 §8/§7.5 直接复用；没有则按段1交代的口径补齐（不改现有存储 key）。
5. 报告现状（改动最多，务必逐个读）：
   - `lib/data/weekly_report.dart`：看现有字段（`patrolSummary` 等）与构建/读取处 → 追加 `final List<RoomScanRecord> roomScans;`（默认 `const []`），copyWith/默认构造/fromJson（若有）同步，缺读给默认。
   - `lib/features/defects/report_content.dart`：读 `ReportBlock` sealed 类与 `buildReportBlocks` 板块顺序 → 新增 `final class RoomBlock extends ReportBlock`（字段：`record` + 户型图 PNG 字节或空），插到 DefectsBlock 之后。
   - `report_builder.dart`(HTML) / `report_pdf.dart` / `report_docx.dart` / `report_xlsx.dart`：读各自对 block 的 switch/分发 → 各加 `RoomBlock` 分支（详见 §8 说明；四端同步）。
   - `lib/features/defects/defects_page.dart`：读 `_loadPhotoBytes` 与导出入口 → 量房户型图字节并入加载（缺失给占位）。
6. 绘制参考：`lib/features/measure/measure_page.dart`（照片标定换算）、`lib/utils/path_metrics.dart`/巡场 painter（CustomPaint 风格）、`lib/core/theme/design_tokens.dart`（色板）。

──────── 第二步 · 实现顺序（每小步可验证） ────────
A. §5：providers.dart 追加 `roomScansProvider`（family）+ `refreshRoomScans`；`flutter analyze` 过
B. §6：app.dart 4 条路由 + 入口「量房」按钮（home 或 measure 入口区）；`flutter build web` 过（能进空列表页）
C. §7.1 `room_records_page.dart`：列表（读 provider；空态"还没有量房记录，点 + 开始量房"；卡片=缩略户型图+名称/日期/面积/闭合差色标；点进详情；长按删除确认）
D. §7.2 `room_draw_page.dart`（核心，工作量大，分 4 子步）：
   D1 画布与网格：InteractiveViewer + 8000×8000mm 逻辑画布（SizedBox），网格线 500mm/1m 两档灰阶；坐标取点用 TransformationController
   D2 打点编辑：单击加点 / 拖动移点 / 长按删点 / 双击选中墙段→底部弹"添加洞口"(类型门/窗+距起端mm+宽mm)；正交吸附开关（默认开，改点后应用 room_geometry.orthoSnap，被吸附下标高亮）
   D3 底部状态条：周长 m · 面积 ㎡（areaM2）· 闭合差 mm（≤15 绿 / >15 红"需复核"）· 墙段数
   D4 工程信息卡 + 保存：名称/房间用途下拉/净高mm/墙厚mm；保存校验（角点≥3；闭合差>50mm 弹确认）→ 组 `RoomWall`（长度=wallLengthsMm 吸附后）→ `RoomScanStore.save` → pop 回列表（记录 source='manual'）
   E. §7.4 `room_plan_painter.dart`：户型 painter（填充/双线墙/洞口门弧窗线/尺寸标注层/面积文字），缩略与详情复用
   F. §7.3 `room_detail_page.dart`：详情（大户型图+标注开）+ 工程信息 + 墙段表（可删改存）+ 入口到 G
   G. §7.5 图纸核尺对照：详情页"对照图纸"→ 选/关联 drawingKey → 校准（loadCadCalibration；无则提示先校准）→ 逐墙"在图纸上点对应两点"（复用 measure_page 图纸量距交互）→ 生成 `MeasureItem(name:'墙N', drawingMm, photoMm=墙长, source:'manual')` → checks 存记录 → 判定列表
   H. §8 报告四端：WeeklyReport.roomScans + RoomBlock + HTML/PDF/DOCX/XLSX 四端 + defects_page 照片字节加载 → 导出验证

──────── 第三步 · 验证（段2完成标准） ────────
1. `flutter test test/room_geometry_test.dart` 仍全绿（未回退段1）
2. 静态：`flutter analyze`（崩溃则 `dart analyze lib/features/room lib/core/room lib/data/weekly_report.dart lib/features/defects/report_content.dart` 等改动目录）→ 0 error
3. `flutter build web --release` 通过
4. **Web 手动流程验收（必须自己点一遍截图留证）**：
   量房入口 → 手动模式 → 网格画布点 4 角 → 吸附 → 周长/面积/闭合差正确 → 加一扇门 → 保存 → 列表出现 → 详情户型图带尺寸标注 → 报告导出(HTML 至少；PDF/DOCX/XLSX 若 Web 限制则如实标注未验)含量房区
5. 旧数据兼容：无 room_scan key 时列表空、导出无房记录不崩

──────── 第四步 · 红线 ────────
- models.dart 只追加；不改段1已合入内容；fromJson 全默认值
- 报告四端同步（改一处必须四处）；无户型图字节时显占位不阻断导出
- 不实现 §9/§10；不新增第三方依赖；不调网络（图纸校准走本地校准库）
- Web 无法验证的导出格式：如实标注，不伪造

──────── 第五步 · 输出（段2结束时交付） ────────
1. 新增/修改文件清单（含行数）
2. flutter test 结果；analyze 结果；Web 构建结果
3. Web 手动流程验收截图或逐项说明（面积/闭合差/门洞/保存/报告）
4. 报告四端各自验证状态（HTML 验过？PDF/DOCX/XLSX 是否受限）
5. 遗留风险与[待真机]项
