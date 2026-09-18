# 换账号交接执行手册 — 给当前 CodeBuddy（完整版）

> 背景：开发账号已切换。**你是新账号、无历史记忆**，而代码库已完成大量功能且未提交的改动混杂其中。
> 本文是**唯一执行依据**：按「第二节执行步骤」顺序做，做完按「第六节」输出报告。**禁止**按自己的猜测重写已存在的功能。

---

## 一、先读（恢复记忆，动手前必须）

按顺序读：
1. `SESSION_CONTEXT.md` —— 记忆压缩包
2. `ARCHIVE_2026-09-08.md` —— **归档基线**（切换账号前固化的正确状态，含✅/❌/⏸清单）
3. `TASK_DASHBOARD.md` —— 文档地图与执行记录

---

## 二、剩余任务线真实状态（已核实，勿重复开发）

| 任务线 | 真实状态 | 依据 | 你能做什么 |
|---|---|---|---|
| AR 第2轮（AR_CAPTURE_BUGFIX.md） | ✅ **Dart侧已实现并提交**（假估算页已删、`_measurements`多点+`_saveAll`、`pickPhotoRobust`、`imageToDisplay`、`_buildPickPin`；`ios/Runner/ArMeasureView.swift` 在仓库） | ARCHIVE ✅清单 + 代码核实 | **没有可写的Dart缺口**；iOS原生本机不能编 → 只做代码走查（见任务2） |
| 量尺 P1/P2（MEASURE_FIX_PLAN.md） | ✅ P1-1手填降级/P1-2容差15/P1-3参考线/P1-4清除标定、P2-1脚本路径/P2-2坐标统一/P2-3文案 均已实现 | ARCHIVE ✅清单 | 唯一缺口 **P1-5（云端host端口）＝冻结**，等部署确认，**不要自己改 host** |
| 文档对齐 | ⚠️ 未提交：`TASK_DASHBOARD.md`、`ARCHIVE_2026-09-08.md` 已 M 改 | git status | 任务6 提交固化 |
| 巡场 GPS | ✅ **代码已实现**（geolocator+权限声明+轨迹写 `PatrolRecord.track`） | ARCHIVE ✅清单 | 只差真机验证；说"GPS未做"是**误读归档** |
| 巡场墙线检测 | ✅ 已实现（`wall_lines.dart`/`geo.dart` 接入巡场页与编辑器） | ARCHIVE ✅清单 | 无缺口 |
| 第3轮回归（TEST_PLAN_MEASURE.md） | ❌ **真·剩余**，但需真机/真实照片 | — | **Web端部分本机可跑**（任务5） |

**结论：不存在"待开发的新功能线"。** 实际工作是：固化→验证→回归→文档对齐→输出报告。若你觉得需要"新功能"，先列出理由，不要直接写代码。

---

## 三、工作区当前状态（git 已核实）

- HEAD = `4b075bd`（归档提交，第1/2轮完成状态已提交）
- **19 个文件未提交 + 2 个新文件**（`lib/core/utils/anchor_objects.dart`、`mm_format.dart`）
- 未提交内容多为**新功能"量尺自动标定·零输入"**（measure_page `_autoCalib`/`detectAnchor`/`_tryAutoCalibOnce`、vision_service `detectAnchor`+`AnchorDetection`、`isReachable` 联网预检、mm 格式化、打卡扩展等）——**该功能不在任何规划文档里**，属于开发中的半成品

---

## 四、执行步骤（按顺序，每步完成才进下一步）

### 任务1：处理未提交 WIP（先问用户，再执行）
1. `git status` 展示给用户 → 问：**保留（提交）还是丢弃？**
2. 保留：`git add -A && git commit -m "wip: 量尺自动标定/格式化工具等（账号交接前固化）"`
3. 丢弃：`git checkout -- lib/data/models.dart lib/data/vision_service.dart ...`（逐文件列出，**不执行全盘 `checkout .`**，保留想要的如文档改动；2个新文件用 `git clean` 前先确认）
4. 输出：commit hash 或恢复清单

### 任务2：编译验证（上次失败，必须重试）
1. `flutter analyze` —— 上次 analysis server 崩溃（exit 255，环境问题非代码问题）；重试；若再崩，试 `flutter clean` 后再跑，或分文件 `dart analyze lib/features/measure/` 缩小范围
2. 若有 error：修复（**只修编译错误，不重构**）
3. `flutter build web --release` 通过
4. 输出：analyze 与构建结果

### 任务3：回归核查表（13项，逐项输出 在/不在/可疑+行号）
对照 ARCHIVE「已完成✅」逐项验证：
1. `PhotoCalib` 2D（ax/ay/bx/by，mmPerPx 用2D距离）
2. `measure_page.imageToDisplay` 存在且图纸蓝点/照片橙点/红点渲染前换算
3. 量尺手填降级（`_drawingMmCtl`，未校准时能加项）
4. `MeasureSession.tolMm` 默认15/2（含旧数据兜底15）
5. 清除标定（`_clearRefCalib`）
6. `core/utils/camera_pick.dart` + capture/measure/ar 三处用 `pickPhotoRobust`
7. ar_measure_page **无** `estMm=drw` 假结果逻辑
8. AR `_measurements` 列表 + `_saveAll` 批量保存
9. capture_page 选点图钉 + label「已选点(x%, y%)」，无「待选点」阻塞
10. `VlDefect/Defect.suggestion` + `defect_suggestions.dart` + 报告含建议
11. `CheckIn` + `PatrolRecord.checkins` + 巡场页打卡
12. 报告四端同步（`report_content.dart` 中间层改动 → HTML/PDF/DOCX/XLSX 都渲染；本次若涉及新字段要四端验证）
13. `flutter analyze` 无 error

**任何「不在/可疑」→ 疑似回归**：`git log --oneline -- <file>` + `git show <commit>:<file>` 找回对比，修复后记录。

### 任务4：AR iOS 原生代码走查（只读不改）
`ios/Runner/ArMeasureView.swift` + `AppDelegate.swift` 注册、`Info.plist` 相机权限——**只做走查**，确认与 ARCHIVE 描述一致（权限检查/多点/占位），输出走查结论。**不编译不改代码**（Windows 不能编 iOS）。

### 任务5：量尺 Web 端回归（第3轮中本机可跑的部分）
按 `TEST_PLAN_MEASURE.md` 在 Web 上执行**不依赖真机相机**的项（用「素材照片/相册选图」替代现场拍照）：
- 测试前准备：选择一张已校准图纸（如 dy04_7_B05）；准备 2 张已知尺寸照片（如 A4 纸/门宽照片）
- 必测项：
  1. 竖线标定数值合理（P0-1 回归）
  2. 标记与点击位置重合（P0-2 回归，不同窗口宽度）
  3. 全流程：图纸点两点→拍/选照片→标定→照片点两点→加入校对→判定→保存→重进恢复
  4. **旧会话兼容**：用旧格式 JSON（仅 pixA/pixB）验证 load 不崩
  5. 量 A4 纸宽 210mm：实测 210±10mm
  6. 合格/超差两种判定
- 输出：逐项通过/失败 + 截图说明

### 任务6：文档对齐并提交
1. 更新 `TASK_DASHBOARD.md`：「执行记录」追加本轮（WIP固化、analyze结果、核查表结论、回归结果）
2. 更新 `ARCHIVE_2026-09-08.md`：仅追加「账号交接后的新进展」小节（不要改动原正文快照）
3. `git add` 全部 + `git commit -m "fix: 账号交接核查与回归（WIP固化/核查表/Web回归）"`（若用户授权推送，推送远端 main）

---

## 五、禁止事项（红线，不可违背）

1. **不重写已存在功能**——ARCHIVE ✅清单里的内容只核验不重做
2. 不改 `remote_repository.dart` 的 host（P1-5 冻结）；不改 iOS 原生（不编译不验证）；不做网页/云同步（后端不在工程）；不做安卓 AR
3. `models.dart` 追加不覆盖；`fromJson` 新字段给默认值
4. 报告/统计改动四端同步
5. 删常量/文件前先 grep；不改范围外文件
6. 每步输出改动清单；不悄悄静默失败

## 六、输出报告（本手册结束时交付）

1. 任务1：WIP 处理结果（commit hash 或恢复清单）
2. 任务2：flutter analyze / web build 结果（成功或错误列表）
3. 任务3：13 项核查表逐项「在/不在/可疑+行号」+ 修复记录
4. 任务4：AR iOS 走查结论
5. 任务5：Web 回归逐项通过/失败
6. 任务6：文档更新与提交信息
7. 剩余风险（真机项：iOS AR/照片精度/GPS 需设备验证）
