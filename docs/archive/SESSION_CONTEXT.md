# 会话上下文（SESSION CONTEXT）— 快速恢复用
> 用途：项目"蓝图落地"的记忆压缩包。新会话/换模型/CodeBuddy 接手前**先读本文件**恢复上下文；细节查对应文档。更新时间：2026-09-09。

## 1. 团队与处境
- 深圳市建筑设计研究总院（SZAD）环境院 **AI中心** 3 人小组（中心共10人）；部门曾有解散压力→以"快速出货+让老板看到钱"为导向
- 已有产品：地库AI大师（AI自动画地库图）
- 技术栈：Flutter App（site-patrol）+ Python 服务（ocf/cad_meta/measure）+ 浩辰云图API（DWG→OCF）+ qwen 视觉模型（远端 120.24.240.129:3000）
- 工作目录：`F:\建筑验收工具\site-patrol`；远端 git：`github.com/linxinquan/site-patrol`（main）
- 本机 **Windows**：不能编 iOS；验证 = flutter test / flutter analyze / flutter build web；**已知：analysis server 因中文路径崩溃(exit 255)→ 回退 `dart analyze <目录>`**

## 2. 产品定位（对外口径）
- 产品名：**蓝图落地** = 设计院视角现场数据闭环工具（拍照识别→AI整改建议→巡场打卡→报告四格式→施工方整改回复→知识回流）
- 核心差异化：设计院出身懂"设计缺陷"；万翼做审图(查错)，我们做"画图+现场+报告"
- 当前热点方向：**量房成图**（AR/LiDAR→户型图带尺寸标注，装修+工地核尺双场景）

## 3. 代码库关键事实
- Flutter + riverpod + go_router；models.dart **约 1450+ 行**，多线共用 → **只追加不覆盖**；fromJson 新字段给默认值
- 关键模型：`Defect`(含 importance/reply/replyBy/replyTs/completion/closeNote/suggestion/designerAction 等)；`PhotoCalib`(ax/ay/bx/by ✅)；`MeasureItem`(含 source/errorMm)；`MeasureSession`(tolMm 15/2)；`PatrolPlan/PatrolRecord/CheckIn`；量房模型 `WallOpening/RoomWall/RoomScanRecord` **待加（段1）**
- 报告四格式：`weekly_report.dart` + `report_content.dart`(中间层) + HTML/PDF/DOCX/XLSX → **stats/字段改动四端同步**
- 视觉：`vision_service.dart`（qwen；`detectAnchor` 锚物识别已用于"自动锚零输入量尺"）；本地建议库 `defect_suggestions.dart`（35条）
- 相机：`core/utils/camera_pick.dart` 的 `pickPhotoRobust`（capture/measure/ar 三处接入）
- AR：Dart 侧完成（多点/批量保存/权限引导/无假估算）；`ios/Runner/ArMeasureView.swift` 原生代码在仓库 **[待真机]**
- 巡场：建模+编辑器+墙线检测(`wall_lines.dart`/`geo.dart`)+GPS(geolocator)+打卡(CheckIn) 均已实现
- ⚠️ 后端 Express 不在工程内（代码走远端）→ 网页链接/云同步冻结；P1-5 云端端口(:3000 vs :8820)冻结等部署确认
- 最近 WIP 已固化 commit `fa7d9e0`（2026-09-09 账号交接轮）

## 4. 文档地图（site-patrol\ 下；状态=最近核实）
| 文档 | 内容 | 状态 |
|---|---|---|
| SESSION_CONTEXT.md | 本文件 | 常读 |
| TASK_DASHBOARD.md | 文档地图+轮次计划+执行记录 | 每轮更新 |
| ARCHIVE_2026-09-08.md | 归档基线快照（切换账号前） | 基线 |
| CODEBUDDY_SWITCH_FIX.md | 换账号执行手册（WIP处置/13项核查表/Web回归） | 已执行完 |
| CODEBUDDY_HANDOFF.md | 三条任务线总交代 | 背景 |
| REQUIREMENTS_0902_IMPL.md / _SOLUTIONS.md | 0902 需求差距任务 | ✅ 全部合入 |
| MEASURE_FIX_PLAN.md / PHOTOCALIB_2D_FIX.md | 量尺修复 | ✅ 除 P1-5 冻结 |
| AR_LIDAR_IMPL_DETAIL.md / AR_UX_SMOOTH.md / AR_CAPTURE_BUGFIX.md | AR 实现+整修 | ✅ Dart 合入，iOS 待真机 |
| PATROL_MASTER_PLAN / PATROL_ZOOM_WALL / PATROL_SEED_ROUTE.md | 巡场 | ✅ 主体完成 |
| TEST_PLAN_MEASURE.md | 量尺回归 | 实测待真机 |
| REPLY_TO_LEADER_0902.md / PPT_OUTLINE_0902.md | 给领导汇报 | 已交付 |
| **MEASURE_ROOM_PLAN.md** | 量房产品+路线(A RoomPlan/B 手动) | 设计定稿 |
| **ROOM_MEASURE_IMPL.md** | 量房实施分层 | ⏳ 待执行 |
| **ROOM_MEASURE_IMPL_DETAIL.md** | 量房超详细规格（§1~§13 全代码/契约） | ⏳ **当前主任务** |
| **PASTE_MASTER.md** | CodeBuddy 开场总指令（纪律+必读） | 每轮粘贴① |
| **PASTE_ROOM_P1.md** | 量房段1交代（§1~§4 检查/验证/红线/输出） | ⏳ 待粘贴② |
| ANDROID_AR_RESEARCH.md | 安卓 AR 调研（含量房节待补） | 已有，量房节 P3 |

## 5. 功能现状（2026-09-09 核实）
- ✅ 已有：AI整改建议(35条库+进报告)、报告四格式导出(LDI三段式)、缺陷证据链+设计师远程处置、施工方回复、打卡制、DWG本地转换(cad_local.py)、手机看CAD、巡场建模/编辑器/墙线防穿墙/GPS、AR多点测量(Dart)、自动锚零输入量尺、量尺P0/P1/P2(除P1-5)、误差带判定(MeasureItem.errorMm/canJudge)
- ❌ 待做：**量房三段式（段1模型/引擎/测试→段2页面/报告→段3 RoomPlan原生）**；量尺/AR/GPS 真机实测与录像（需设备）
- ⏸ 冻结：网页链接/云同步（后端）、P1-5（端口）、安卓 AR（调研维持"安卓走照片/手动量房"）

## 6. 当前执行计划（量房 = 当前主线，三段式）
- **段1**（§1~§4：模型+存储+几何引擎+测试）→ 先做，验收（flutter test 全绿）后放段2
- **段2**（§5~§8：页面+painter+核尺对照+报告四端）→ Web 可演示
- **段3**（§9~§10：RoomPlan 原生代码+契约+安卓调研）→ [待真机]
- 收尾另排：真机回归（TEST_PLAN_MEASURE）+ iOS AR/量房联调

## 7. 关键技术事实
- OCF=浩辰私有网页格式；识别/解析回 DWG，OCF 只展示
- 照片量尺：参照物标定 mm/px=refMm/2D像素距，±1~3%；"快速校对"非精密计量
- AR LiDAR：iPhone 12 Pro+；**≥2m 手机读数达不到 GB 验收精度→UI 已标注"需复核"**；同边重复采样+误差带判定
- RoomPlan：ARKit 官方量房（iOS16+/LiDAR），自动出墙/门/窗/房间+尺寸；黑盒成图→需标注层补工程信息
- CadCoordMapper：屏幕像素↔CAD 世界坐标 mm；B05 有演示校准
- 浩辰 API：华为云网关；dwgToOcf 异步任务；配额商用待确认

## 8. 待领导拍板
1. 安卓 AR 值不值得投（倾向不投）
2. 网页协作链接后端归属/预算（后端不在工程）
3. 浩辰转换授权/配额

## 9. 红线口径
- AI/远程处置标"AI辅助，人工复核"；不编造规范条文号
- 判定精度诚实（手机测量达不到验收精度就说"需复核"）；**不伪造验证结果（[待真机]=不假装通过）**
- models 追加不覆盖、fromJson 默认值；报告四端同步；不引新依赖；删前 grep；不碰范围外

## 10. CodeBuddy 每轮必带
先读 `PASTE_MASTER.md`（纪律）→ 任务 `PASTE_xxx.md`（细节）→ 规格文档；先读文档与最新代码；标✅不重写；每步 analyze/test/构建+改动清单输出；Windows 不能编 iOS

## 11. 任务交付规范（2026-09-09 起执行）
1. **任务分解产出 4 件套**，全部落盘 site-patrol\：
   ① 详细规格文档 `XXX_IMPL_DETAIL.md`（纯逻辑给完整代码，UI 给精确规格，原生给契约/骨架）
   ② 交代文本 `PASTE_XXX.md`（范围/前置检查/按序步骤/验证命令/红线/输出格式，自包含）
   ③ 看板登记：`TASK_DASHBOARD.md`（文档地图行 + 排期/分段 + 执行记录）
   ④ 记忆更新：`SESSION_CONTEXT.md`（现状/计划/文档表）
2. **给 CodeBuddy 两段粘贴**：①`PASTE_MASTER.md` 开场总指令 ②任务 `PASTE_XXX.md` 细节；大任务按"段"放行，每段验收后才放下一段
3. 每个任务文档开头附：文件地址（site-patrol\ 相对路径）+ 需要哪些前置文件
4. 回复用户时给出新增/更新的**文件路径清单**

## 12. 执行记录（最近）
- 2026-09-08：归档 `ARCHIVE_2026-09-08.md`；第1/2/4轮已完成提交（0902 任务、AR整修、量尺P1/P2、GPS、自动锚零输入量尺、误差带判定）
- 2026-09-09 账号交接轮：WIP 固化 `fa7d9e0`；dart analyze 0 error/7 warning；13 项回归核查表全"在"；Web 构建过；量尺 Web 实测待人工
- 2026-09-09 量房立项：`MEASURE_ROOM_PLAN.md` → `ROOM_MEASURE_IMPL.md` → `ROOM_MEASURE_IMPL_DETAIL.md`（超详细30KB）→ 看板登记三段式 → `PASTE_MASTER.md` + `PASTE_ROOM_P1.md`（段1交代）→ **段1 待执行**
