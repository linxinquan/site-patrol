# 开发任务看板（CodeBuddy 轮次管理）

> 用途：给 CodeBuddy 的每个任务文档在哪、状态如何、下一轮执行哪个。
> 更新规则：每完成一轮，把对应行状态改为 ✅/部分，并在"执行记录"追加一行。

## 文档地图（都在 F:\建筑验收工具\site-patrol\）

| 文档 | 内容 | 状态 | 给 CodeBuddy 时怎么用 |
|---|---|---|---|
| `CODEBUDDY_HANDOFF.md` | 总交代（量尺修复/巡场/AR 三任务线+约束） | 部分执行 | 作为"全局约束"引用，不再整份贴 |
| `MEASURE_FIX_PLAN.md` | 量尺 P0/P1/P2 修复清单 | **大部分** | P0-1✅/P0-2✅/P1-1~4✅/P2-1~3✅ 已合入；**余 P1-5**（云端端口 3000 vs 8820，需部署方确认） |
| `PHOTOCALIB_2D_FIX.md` | P0-1 替换代码（6处） | ✅ 已合入（models 有 ax/ay/bx/by） | 无需再执行 |
| `AR_LIDAR_IMPL_DETAIL.md` + `AR_UX_SMOOTH.md` | AR 主实现+交互补丁 | ✅ 大体已实现 | 已实现，不再作为主任务 |
| `AR_CAPTURE_BUGFIX.md` | AR 多点+保存+黑屏 / 拍照记录选点 / 相机稳定性 / P0-2 | ✅ **已合入**（2026-09-08 代码核实） | 无需再执行；**iOS 原生部分本机不可编译，需真机验证** |
| `PATROL_MASTER_PLAN.md` + 三份规格 | 巡场总纲（模型/底图/编辑器/墙线/GPS/历史） | ✅ **主体已完成** | 墙线检测（`wall_lines.dart`+`geo.dart` 防穿墙）与 GPS 轨迹采集（`geolocator`）均已接入 |
| `REQUIREMENTS_0902_SOLUTIONS.md` | 0902 需求→方案映射 | 已盘点 | 背景参考 |
| `REQUIREMENTS_0902_IMPL.md` | 0902 差距任务 1~7 | ✅ **已全部合入**（1/2/3/4/5/6 + 任务5b 巡场小结） | **不再重复执行** |
| `TEST_PLAN_MEASURE.md` | 量尺测试清单 | **代码级已核** | 静态部分已回归（P0-1/P0-2/P1/P2 逐项核实）；**实测部分（竖线标定/标记对齐/精度/录像）需真机+真实照片，Windows 无法执行** |
| `REPLY_TO_LEADER_0902.md` / `PPT_OUTLINE_0902.md` | 给领导汇报 | 已交付 | 非 CodeBuddy 任务 |
| `SESSION_CONTEXT.md` | 会话记忆压缩包 | 常读 | 新会话/换账号先读 |
| `ARCHIVE_2026-09-08.md` | 归档基线快照 | 已提交 `4b075bd` | 账号切换前后核对基线用 |
| `CODEBUDDY_SWITCH_FIX.md` | 换账号交接执行手册（WIP处置/13项核查表/Web回归） | ⚠️ 依据执行 | 换新 CodeBuddy 账号时必读 |
| `MEASURE_ROOM_PLAN.md` | 量房（装修+核尺）产品与技术路线（A RoomPlan / B 手动） | 设计定稿 | 背景参考 |
| `ROOM_MEASURE_IMPL.md` | 量房实施分层总览（P0 可验 / P1 原生待真机） | ⏳ 待执行 | 分层与红线 |
| `ROOM_MEASURE_IMPL_DETAIL.md` | 量房超详细实施规格（模型/引擎/页面/报告/原生契约全代码） | ⏳ 待执行 | **当前主任务文件**（三段式见下） |

## 当前执行计划（推荐顺序）

### 第 1 轮 → REQUIREMENTS_0902_IMPL.md ✅ **已完成**（提交 `979a8b4`，2026-09-08 代码核实）
任务1 扩建议库（35 条 ≥30，强制类目全覆盖）→ 任务2 打卡制（`CheckIn` + `_CheckInBar` + 达成率）→ 任务3 DWG 上传（`cad_local.py` 浩辰本地零配额）→ 任务4 设计师远程处置（`designerAction` + 四端统计 `designerFixed`）→ 任务5 施工方回复 UI（`_ReplyCard`）；任务6 安卓 AR 调研文档（`ANDROID_AR_RESEARCH.md`）；任务7 等后端，不做。
**任务5b**（巡场汇总入报告）已补齐：`WeeklyReport.patrolSummary` 字段 + 导出弹窗手填 + HTML/PDF/DOCX/XLSX 四端渲染。

### 第 2 轮（第1轮验收后给）→ AR_CAPTURE_BUGFIX.md
AR 多点测量+批量保存 / AR 黑屏修复+删除假估算页 / 拍照记录选点反馈 / 相机稳定性(pickPhotoRobust) / 顺手补 P0-2 标记错位。

### 第 3 轮（集成后）→ TEST_PLAN_MEASURE.md 全量回归 + 汇总冒烟测试
照片量尺+巡场+AR 三块联测，重点：旧会话兼容、Web/Android/iOS 三端、报告导出含新增字段。

### 每轮 CodeBuddy 输出
改动文件清单 + 每任务验收自查 + `flutter analyze`/Web 构建结果。

### 量房功能 · 三段式排期（当前主线，规格 `ROOM_MEASURE_IMPL_DETAIL.md`）
> 背景：需求=AR量尺升级为**量房成图**（沿墙定点/扫描→自动出标注尺寸的户型图→记录户型），双场景（装修量房+工地核尺对照），A=RoomPlan自动扫描(仅iOS16+LiDAR)＋B=手动/照片成图(跨平台)。

**段1（约0.5~1天）→ §1~§4：地基（先做，验收后再放段2）**
- §1 数据模型 `WallOpening/RoomWall/RoomScanRecord/RoomScanArgs`（models.dart 追加，代码已写好）
- §2 存储 `room_scan_store.dart`
- §3 几何引擎 `room_geometry.dart`（正交吸附/闭合差/面积/标注布局/洞口，完整代码已写好）
- §4 测试 `test/room_geometry_test.dart` 全绿（正方形12㎡/88°吸附/外法向/洞口中心）
- 验收：`flutter test` 全绿 + `flutter analyze` 无 error + 改动清单

**段2（约1.5~2天）→ §5~§8：页面与报告（段1验收后给）**
- §5 provider（`roomScansProvider`）→ §6 路由4条 + 入口「量房」
- §7 页面：记录列表 → 成图页（手动网格/照片标定两模式+正交+洞口+工程信息+保存）→ 详情（painter户型图+尺寸标注）→ 图纸核尺对照（复用校准+MeasureItem 判定）
- §8 报告四端接入（WeeklyReport.roomScans + RoomBlock → HTML/PDF/DOCX/XLSX）
- 验收：Web 端全流程可演示（点角→吸附→面积/闭合差→门洞→保存→列表→报告4格式含量房区）+ `flutter build web --release` 通过

**段3（约1天，[原生-待真机]）→ §9~§10：RoomPlan + 安卓调研**
- §9 `RoomCaptureController.swift` 骨架 + `room_capture` MethodChannel 契约 + `room_capture_service.dart` + `room_auto_scan_page.dart`；**本机只写代码不编译**，交付时列未验证清单
- §10 `ANDROID_AR_RESEARCH.md` 追加量房成图结论（调研文档，不写产品代码）
- 验收：代码与契约齐全、未验证项清单明确

**演示路径（无 Pro 设备也能跑）**：段2完成即可 Web 演示"手动成图→户型图带尺寸→报告"；RoomPlan 段3代码备好，等 iPhone Pro 真机联调。

## 执行记录
- 2026-09-08：归档快照 `ARCHIVE_2026-09-08.md`（切换登录账号前固化现状/在办/下一步）；工作区干净，main 与 origin 同步
- 2026-09 第0轮：量尺P0-1/巡场建模/报告导出/AR页面/AI建议 等已由 CodeBuddy 完成（代码核实）
- 2026-09-08 第1轮：0902 差距实施（任务1/2/3/4/5/6）已由 `979a8b4` 合入，代码核实通过；Web 构建通过。任务7（网页链接）待后端，不做
- 2026-09-08 文档校正：本看板与 `ARCHIVE_2026-09-08.md` 原标 0902 为「⏳待执行」，与实际不符，已更正为「✅已合入」，避免后续接手重复盘点
- 2026-09-10 量尺精度线（高精度改造）：
  - **照片侧透视校正**：新增 `core/utils/homography.dart`（归一化 DLT + Jacobi 最小特征向量，**不可用「固定 h₈=1」的 8 元解法**——h₈=0 是合法退化，4 点矩形标定会踩到）；`PhotoCalib` 追加单应字段（向后兼容）；`photoMeasuredMmAuto` 自动选择量测方式；量尺页支持「手动点选模数网格」与「AI 识别网格 → 图上绿色标注 → 人工确认」；实时显示「校正前（两点比例）→ 校正后（单应）」差值
  - **AI 被测目标**：`VisionService.detectTargets`（只给端点、**不让模型报尺寸**）→ 图上琥珀虚线候选尺寸线 → 工程命名（门 M0921 / 窗 C1518）+ 模数吸附（2075→提示 2100）→ 逐条人工采纳；采纳项 `source:'ai'` 且带估算误差带
  - **AR 系统偏差校正 + 距离门控**：新增 `core/storage/ar_scale_calibration.dart`（k = 真值/实测中位，偏差 >15% 判为测错）；AR 页文案把「重复性 ±mm」与「准确度」分开；原生上报 `depthMm`，超 5m 丢弃读数、超 0.3~3m 最佳区间提示（iOS 侧 [待真机]）
  - **报告四端同步**：新增 `core/utils/measure_labels.dart`（列名/行内容唯一来源），HTML/PDF/DOCX 出「尺寸校对」表、XLSX 出单行摘要，四端一律带**误差带 + 测量方式 + 判定**；量房保存时自动挂接该图纸的量尺清单为 `checks`；修复 `MeasureStore` 漏存 `errorMm` 的缺陷
  - 测试：`test/homography_test.dart`(9) + `test/vision_grid_test.dart`(3) + `test/measure_targets_test.dart`(13) + 四端同步断言（`room_export_compat_test` 新增 4 例）
- 2026-09-08 第4轮：量尺 P1-1~P4 / P2-1~3 落地（P1-5 涉云端端口待部署确认）；巡场 GPS 轨迹采集（geolocator）；尺寸 UI 显示取整（mm 整数、% 留 1 位）；**实现「自动锚零输入量尺」**（`anchor_objects` 尺寸库 + `vision_service.detectAnchor` + 自动标定/手动兜底，全机型、免手填参考物）——详见 `ANDROID_AR_RESEARCH.md` §6；Web 构建通过
- 2026-09-09 账号交接轮（依 `CODEBUDDY_SWITCH_FIX.md` §4）：WIP 全量固化 `fa7d9e0`（22 文件 +975/−56）；`flutter analyze` 仍因中文路径崩溃（exit 255，环境问题）→ 改用 `dart analyze lib` 得 **0 error / 7 warning / 133 info**；13 项回归核查表**全部「在」**；AR iOS 原生只读走查通过；Web 构建通过；量尺 Web 端 6 项实测**待人工执行**（需真实照片与打点）
- 2026-09-09 需求收敛（iPhone 纯手机 + 判定级复核记录）：AR 量尺升级为**同边重复采样 + 误差带判定**——`MeasureItem` 新增 `errorMm`（判定门控 1/3 规约 `canJudge`）；`measure_math` 增 `medianOf`/`spreadHalfRange`/`canJudgeByError`；AR 页改「多测几次 → 采纳本组(中位±误差) → 逐组判定/需复核」；测量误差带随项进报告与共享清单；约束：≥2m 距离手机读数无法达到 GB 验收精度，UI 已诚实标注"需复核"
- 2026-09 量房立项：规格 `MEASURE_ROOM_PLAN.md`（A RoomPlan＋B 手动成图；装修+核尺双场景）→ 分层 `ROOM_MEASURE_IMPL.md` → 超详细 `ROOM_MEASURE_IMPL_DETAIL.md`（模型/引擎/页面/报告/原生全代码）；**三段式排期见上**
- 2026-09 量房段1 ✅：模型(WallOpening/RoomWall/RoomScanRecord)+`room_scan_store`+`room_geometry`(正交吸附/闭合差/面积/标注)+`room_geometry_test` 全绿（包名按 pubspec=gongdi_app）；CodeBuddy 勘误 3 处已回写源文档 §3/§4（import models、闭合差语义 3000/0、包名）→ **段2（§5~§8 页面+报告四端）当前执行中**
- 2026-09 量房段2 ✅ 代码合入（静态+单测过）：5 页面（含 room_compare_page 核尺）、4 路由+首页入口、roomScansProvider、WeeklyReport.roomScans、RoomBlock 报告四端（均有 `build\量房记录_示例.*` 真实文件证据）；**动态验收待用户按清单人工点 Web 流程补 4 张截图**（空态/打点状态条/列表卡片/详情标注）
- 2026-09 段3 交代 `PASTE_ROOM_P3.md` 已提前备好（§9 RoomPlan 原生+MethodChannel 契约+§10 安卓调研，全部[待真机]）——段2 动态验收通过即可开跑
- 2026-09-09 晚 段2 静态补充审计（目标轮2，等用户截图期间）：`room_records_page`/`room_plan_painter`/`room_draw_page` 复核通过（防除零、洞口挖空、几何语义正确）；**打磨项1条**=尺寸标注引线偏移按 mm 计（26mm），详情大图缩放下几乎贴墙——建议 v1.5 改为屏幕像素偏移或 ≥300mm+端线
- 2026-09-09 晚 用户说明：下班回家、无电脑——**段2"人工截图验收"改期**：选项①明天用户回电脑按清单补 4 张截图；选项②由 CodeBuddy 在用户机器上补 widget 测试程序化覆盖手动流程（点角→面积/闭合差→保存→列表）替代截图；期间由目标轮次自主推进非 UI 工作（构建/静态/文档）
- 2026-09-09 晚 段2 复核补充：成图页全文件审计通过（闭合手势/正交吸附/洞口校验/保存流均健壮）；**打磨项2**：①painter `shouldRepaint` 用列表同一性比较而列表就地修改 → 加洞口后可能不重绘（建议 shouldRepaint 比内容或 mutation 时换新列表）②尺寸标注引线偏移 26mm 缩放下贴墙（建议 ≥300mm 或屏幕像素）。Widget 测试方案已写 `WIDGET_TEST_ROOM_P2.md`（用户无电脑时的验收替代，明天 CodeBuddy 执行）
