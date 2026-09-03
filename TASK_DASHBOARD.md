# 开发任务看板（CodeBuddy 轮次管理）

> 用途：给 CodeBuddy 的每个任务文档在哪、状态如何、下一轮执行哪个。
> 更新规则：每完成一轮，把对应行状态改为 ✅/部分，并在"执行记录"追加一行。

## 文档地图（都在 F:\建筑验收工具\site-patrol\）

| 文档 | 内容 | 状态 | 给 CodeBuddy 时怎么用 |
|---|---|---|---|
| `CODEBUDDY_HANDOFF.md` | 总交代（量尺修复/巡场/AR 三任务线+约束） | 部分执行 | 作为"全局约束"引用，不再整份贴 |
| `MEASURE_FIX_PLAN.md` | 量尺 P0/P1/P2 修复清单 | **部分** | P0-1✅已合入；P0-2 待做 |
| `PHOTOCALIB_2D_FIX.md` | P0-1 替换代码（6处） | ✅ 已合入（models 有 ax/ay/bx/by） | 无需再执行 |
| `AR_LIDAR_IMPL_DETAIL.md` + `AR_UX_SMOOTH.md` | AR 主实现+交互补丁 | ✅ 大体已实现 | 已实现，不再作为主任务 |
| `AR_CAPTURE_BUGFIX.md` | AR 多点+保存+黑屏 / 拍照记录选点 / 相机稳定性 / P0-2 | ❌ **未执行**（代码里假估算页仍在、无多点列表） | 下轮候选 |
| `PATROL_MASTER_PLAN.md` + 三份规格 | 巡场总纲（模型/底图/编辑器/墙线/GPS/历史） | **部分**（PatrolPlan/Record/编辑器/Store 已建） | 余项并入 0902 任务2 |
| `REQUIREMENTS_0902_SOLUTIONS.md` | 0902 需求→方案映射 | 已盘点 | 背景参考 |
| `REQUIREMENTS_0902_IMPL.md` | 0902 差距任务 1~7（推荐当前主任务） | ⏳ **待执行** | **本轮主文件** |
| `TEST_PLAN_MEASURE.md` | 量尺测试清单 | 待测 | 集成后回归 |
| `REPLY_TO_LEADER_0902.md` / `PPT_OUTLINE_0902.md` | 给领导汇报 | 已交付 | 非 CodeBuddy 任务 |

## 当前执行计划（推荐顺序）

### 第 1 轮（现在给）→ REQUIREMENTS_0902_IMPL.md
任务1 扩建议库(0.5h) → 任务2 打卡制(1d) → 任务3 DWG上传(1.5d) → 任务4 设计师远程处置(0.5d) → 任务5 施工方回复UI(0.5d)；任务6 安卓AR调研文档（并行产出）；任务7 网页链接等后端不做。

### 第 2 轮（第1轮验收后给）→ AR_CAPTURE_BUGFIX.md
AR 多点测量+批量保存 / AR 黑屏修复+删除假估算页 / 拍照记录选点反馈 / 相机稳定性(pickPhotoRobust) / 顺手补 P0-2 标记错位。

### 第 3 轮（集成后）→ TEST_PLAN_MEASURE.md 全量回归 + 汇总冒烟测试
照片量尺+巡场+AR 三块联测，重点：旧会话兼容、Web/Android/iOS 三端、报告导出含新增字段。

### 每轮 CodeBuddy 输出
改动文件清单 + 每任务验收自查 + `flutter analyze`/Web 构建结果。

## 执行记录
- 2026-09 第0轮：量尺P0-1/巡场建模/报告导出/AR页面/AI建议 等已由 CodeBuddy 完成（代码核实）
