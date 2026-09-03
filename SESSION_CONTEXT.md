# 会话上下文（SESSION CONTEXT）— 快速恢复用

> 用途：本文件是"蓝图落地"项目的**记忆压缩包**。新会话/换模型/CodeBuddy 接手前，先读本文件即可恢复 80% 上下文；细节再查对应文档。更新时间：2026-09-02（记录整场会话）。

---

## 1. 团队与处境（为什么做这些）

- 团队：深圳市建筑设计研究总院（SZAD）环境院 **AI中心** 内 3 人小组（中心共10人）
- 危机：**部门面临解散**，老板给过1个月期限，"看不到希望就解散"——一切工作以"快速出货+让老板看到钱/希望"为导向
- 已有产品：地库AI大师（AI自动画地库图）
- 技术栈：Flutter App（site-patrol）+ Python 服务（ocf/cad_meta/measure）+ 浩辰云图API（DWG→OCF）+ qwen视觉模型（远端服务器）
- 工作目录：`F:\建筑验收工具\site-patrol`（Flutter 工程）；本机 **Windows**——**不能编译 iOS**，只能 flutter analyze + Web 构建

## 2. 产品定位（商业叙事，对外口径）

- 产品名：**蓝图落地** = 设计院视角的现场数据闭环工具（拍照识别→AI整改建议→巡场→报告→施工方整改→知识回流）
- 定位变化史：巡检APP（无前景）→ 设计-施工数据闭环 → 只做设计师（院长定调）→ 当前："设计师助手+现场数据闭环"
- 核心差异化：设计院出身懂"设计缺陷"；万翼做审图（查错），我们做"画图+现场+报告"
- 三条路：对内提效保命 → 对外卖服务造血 → 数据/产品翻身

## 3. 代码库关键事实（site-patrol）

- 平台：iOS/Android/Web，Flutter + riverpod + go_router
- **models.dart 已 1355+ 行**，多线共用——**修改一律"追加"，不覆盖**；新增字段 fromJson 给默认值（兼容红线）
- 关键模型位置：`Defect`~363（含 building/importance/reply/replyBy/replyTs/completion/closeNote/suggestion/photoPath）；`PhotoCalib`~536（已含 ax/ay/bx/by，P0-1✅）；`MeasureItem`/`MeasureSession`~624-700（含 source）；`PatrolPlan`~1213/`PatrolRecord`~1284/`PatrolPlanStore`
- 报告生成器完整：`weekly_report.dart` + `report_content.dart`（中间层）+ `report_builder.dart`(HTML)/`report_pdf.dart`/`report_docx.dart`/`report_xlsx.dart` —— **改 stats 必须四端同步**
- 视觉识别：`vision_service.dart`（qwen，host 默认 120.24.240.129:3000）；本地建议库 `core/utils/defect_suggestions.dart`（约11条关键词规则）
- 巡场：编辑器已建（patrol_editor_page）；打卡❌、墙线检测❌、GPS❌
- 量尺：measure_page 照片标定已实现（P0-1 ✅ / P0-2 标记错位 ❌）
- AR：ar_measure_page + iOS 原生 ArMeasureView.swift（LiDAR+sceneDepth）；**假估算页面还在（estMm=drw 永远合格，必须删）**；多点测量❌；相机权限处理❌
- 相机工具：capture_page 有权限引导；无通用兜底工具（pickPhotoRobust 待建）
- ⚠️ **后端 Express 目录不存在**（代码引用 /api/vision、/api/weather 走远端）——网页链接/云同步类任务冻结

## 4. 已创建文档地图（全在 site-patrol\ 下，含本文件）

| 文档 | 内容 | 状态 |
|---|---|---|
| SESSION_CONTEXT.md | 本文件 | 常读 |
| TASK_DASHBOARD.md | 文档地图+3轮计划+执行记录 | 每轮更新 |
| CODEBUDDY_HANDOFF.md | 总交代+全局约束 | 部分执行 |
| REQUIREMENTS_0902_SOLUTIONS.md | 0902六条需求→方案映射 | 盘点完成 |
| **REQUIREMENTS_0902_IMPL.md** | **0902差距任务1~7（当前主任务）** | ⏳待执行 |
| AR_CAPTURE_BUGFIX.md | AR多点/保存/黑屏+拍照选点+相机稳定性+P0-2 | ❌未执行 |
| PATROL_MASTER_PLAN.md | 巡场总纲（4阶段） | 部分（建模/编辑器已做） |
| PATROL_ZOOM_WALL.md | 巡场缩放+防穿墙（墙线检测） | ❌未执行 |
| PATROL_SEED_ROUTE.md | 巡场推荐路线规范+骨架 | ❌未执行 |
| MEASURE_FIX_PLAN.md | 量尺P0/P1/P2修复 | 部分（P0-1✅P0-2❌） |
| PHOTOCALIB_2D_FIX.md | P0-1替换代码 | ✅已合入 |
| AR_LIDAR_IMPL_DETAIL.md + AR_UX_SMOOTH.md | AR实现+交互 | ✅大体已实现 |
| TEST_PLAN_MEASURE.md | 量尺测试清单 | 待测 |
| REPLY_TO_LEADER_0902.md / PPT_OUTLINE_0902.md | 给领导汇报 | 已交付 |

## 5. 当前功能现状（0902 盘点结论）

- ✅ 已有可演示：AI整改建议（识别后出措施+本地库兜底+进报告）、报告四格式导出（对齐LDI巡场报告单三段式）、缺陷证据链、手机看CAD管线（10张真实图纸已转OCF）、缺陷整改回复数据字段、巡场建模+编辑器
- ❌ 待开发：检查点打卡制、DWG自助上传、设计师远程处置、施工方回复UI、AR修复整份（多点/保存/黑屏/删假估算）、量尺P0-2、巡场墙线检测/GPS
- ⏸ 冻结：网页协作链接（等后端）；安卓AR调研=出文档

## 6. 当前执行计划（3轮）

1. **第1轮（现在）**：`REQUIREMENTS_0902_IMPL.md` 任务1~5（扩建议库→打卡→DWG上传→远程处置→回复UI）+任务6调研文档+任务7跳过
2. **第2轮**：`AR_CAPTURE_BUGFIX.md` 整份
3. **第3轮**：`TEST_PLAN_MEASURE.md` 三块功能全量回归

## 7. 关键技术事实（速查）

- **OCF**：浩辰私有网页发布格式。DWG 浏览器看不了→服务端转 OCF（轻量/懒加载/防泄露/跨端）；矢量可交互（测量/图层/点选）是"照片↔图纸关联"的根基；**识别/解析回 DWG 做，OCF 只做展示**
- **照片量尺**：参照物标定 mm/px=refMm/2D像素距；照片±1~3%误差；定位"快速校对"非精密计量
- **AR LiDAR**：iPhone 12 Pro+；sceneDepth+raycast，±1~2cm@5m；iOS原生MethodChannel；Android无GMS跑不了ARCore→安卓主路径=照片量尺
- **校准**：CadCoordMapper 屏幕像素↔CAD世界坐标mm；B05 有演示校准（含系统偏移），真实精度需现场校准
- **浩辰API**：华为云网关 gstarcadsdk.apistore.huaweicloud.com（backend_api.txt 有全文档）；dwgToOcf/getTaskStatus 等异步任务；**按次消耗配额，商用授权待确认**

## 8. 待领导拍板（汇报卡点）

1. 安卓AR值不值得投（倾向：不投，安卓用照片量尺）
2. 网页协作链接后端归属与预算（后端不在工程内）
3. 浩辰转换API商用授权/配额（DWG上传依赖）

## 9. 红线与口径（对外/汇报）

- AI建议/远程处置标注"AI辅助，人工复核"；不编造规范条文号
- 演示不承诺网页端/后端能力（后端未落地）
- 报告/统计改动四渲染端同步；新旧数据兼容；不碰范围外文件

## 10. 给 CodeBuddy 的注意要点（每轮必带）

1. 先读 TASK_DASHBOARD + 对应任务文档 + **最新代码**再改（迭代快）
2. 标✅已存在的不重写，只叠加；models.dart 追加不覆盖
3. 每任务：flutter analyze 无错 + Web 构建过 + 输出改动清单
4. 后端/网页任务不做；改 Python 服务先确认启动方式
5. Windows 不能编 iOS

## 11. 执行记录（本会话完成的事）

- 商业咨询轮：定位从巡检APP→设计院数据闭环→设计师助手（含出处链接）
- 文档产出：上表全部文档（本会话创建）
- CodeBuddy 已实现（代码核实）：量尺P0-1、报告生成器全套、AI建议字段+本地库、缺陷回复字段、巡场建模+编辑器、AR页面+原生、打卡❌
- 给领导的汇报已出（REPLY_TO_LEADER_0902.md）
