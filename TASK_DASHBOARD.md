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

## 执行记录
- 2026-09-08：归档快照 `ARCHIVE_2026-09-08.md`（切换登录账号前固化现状/在办/下一步）；工作区干净，main 与 origin 同步
- 2026-09 第0轮：量尺P0-1/巡场建模/报告导出/AR页面/AI建议 等已由 CodeBuddy 完成（代码核实）
- 2026-09-08 第1轮：0902 差距实施（任务1/2/3/4/5/6）已由 `979a8b4` 合入，代码核实通过；Web 构建通过。任务7（网页链接）待后端，不做
- 2026-09-08 文档校正：本看板与 `ARCHIVE_2026-09-08.md` 原标 0902 为「⏳待执行」，与实际不符，已更正为「✅已合入」，避免后续接手重复盘点
- 2026-09-08 第4轮：量尺 P1-1~P4 / P2-1~3 落地（P1-5 涉云端端口待部署确认）；巡场 GPS 轨迹采集（geolocator）；尺寸 UI 显示取整（mm 整数、% 留 1 位）；**实现「自动锚零输入量尺」**（`anchor_objects` 尺寸库 + `vision_service.detectAnchor` + 自动标定/手动兜底，全机型、免手填参考物）——详见 `ANDROID_AR_RESEARCH.md` §6；Web 构建通过
- 2026-09-09 账号交接轮（依 `CODEBUDDY_SWITCH_FIX.md` §4）：WIP 全量固化 `fa7d9e0`（22 文件 +975/−56）；`flutter analyze` 仍因中文路径崩溃（exit 255，环境问题）→ 改用 `dart analyze lib` 得 **0 error / 7 warning / 133 info**；13 项回归核查表**全部「在」**；AR iOS 原生只读走查通过；Web 构建通过；量尺 Web 端 6 项实测**待人工执行**（需真实照片与打点）
