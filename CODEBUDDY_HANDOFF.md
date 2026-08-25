# 交给 CodeBuddy 的任务交代（分轮执行）

---

## 项目背景（先读）

- 工作目录：`F:\建筑验收工具\site-patrol` —— Flutter App「蓝图落地」（设计院工地数据工具），iOS/Android/Web 三端
- 后端：Express `backend/server.js`（:3000，视觉模型 qwen3.8-max）+ Python `server/measure_server.py`（:8820，量尺落库）
- 三大任务线：①量尺修复 ②巡场改造 ③AR量尺（暂缓）

---

## 任务线① 量尺修复

### 先读这些文件（按顺序）

1. `MEASURE_FIX_PLAN.md` —— 全部待改项清单（P0/P1/P2，含每项的行号与验证方法）
2. `PHOTOCALIB_2D_FIX.md` —— P0-1 的完整替换代码（4 个文件 6 处，直接照抄）
3. 现有实现（要改的对象）：
   - `lib/features/measure/measure_page.dart`
   - `lib/core/utils/measure_math.dart`
   - `lib/core/storage/measure_store.dart`
   - `lib/data/models.dart`
4. 风格参照（不要违背现有模式）：
   - `lib/features/capture/capture_page.dart`（取图、kIsWeb 分流、AppSnack 用法）
   - `lib/core/utils/cad_coord.dart`（坐标换算）
   - `lib/utils/path_metrics.dart`（CustomPainter 风格）
   - `AI_VISION_INTEGRATION.md`（后端/联调约定）

### 第一轮：只做 P0 两个修复

**P0-1：PhotoCalib 2D 修复**
- **严格按 `PHOTOCALIB_2D_FIX.md` 的 ①~⑥ 执行**（4 个文件 6 处替换，代码已写好，照搬）
- 硬性要求：旧会话 JSON（只有 pixA/pixB）必须兼容——`fromJson` 读到旧格式时 ay=by=0，不抛异常
- 改完自查：`flutter analyze` 无新增 error；逻辑上竖线标定（两点 dy 差大、dx≈0）的 mm/px 必须为合理值

**P0-2：标记错位修复**
- 问题：`measure_page.dart` 的 `_pickDot` 把原图像素坐标直接当 `Positioned(left/top)`，但图片按 `BoxFit.contain` 缩放显示，标记错位
- 方案：新增 `imageToDisplay(Offset imgPx, Size box, Size imgSize)`（BoxFit.contain 逆变换），三处标记（图纸蓝点、照片橙点/红点）渲染前换算成显示坐标再定位
- 自查：点击处与标记重合；浏览器窗口缩放后仍对齐

**第一轮约束**
- 只动 `models.dart`、`measure_store.dart`、`measure_page.dart` 与量尺相关部分，不碰其他功能
- 改完输出：改动文件清单 + 每处一行说明
- 不要跑 iOS/Android 构建（本机是 Windows）；可跑 `flutter build web --release` 验证编译

### 第二轮：P1 + P2

按 `MEASURE_FIX_PLAN.md` 的 §P1-1~P1-5、§P2-1~P2-3 执行：
- P1-1 图纸尺寸手填降级（图纸未校准时能手填加项）
- P1-2 默认容差改为 ±15mm / 2%（models.dart 约 579~580 行 + measure_page 约 54~55、103~104 行）
- P1-3 照片参考线 + 像素跨度显示（CustomPaint，照 path_metrics.dart 风格）
- P1-4 「清除标定」按钮（copyWith 已预留 clearPhotoCalib 参数）
- P1-5 `remote_repository.dart` 默认 host 端口核对（:3000 vs :8820）——**先不要自己改，把现状结论告诉我们再定**
- P2-1 `_test_measure.ps1` 路径改 `$PSScriptRoot`
- P2-2 `_onDrawTap` 的 `_imageSize==null` 回退分支改为提示并 return
- P2-3 提示文案按标定状态显示

---

## 任务线② 巡场改造（按总纲执行）

> 唯一执行入口：`PATROL_MASTER_PLAN.md`。先完整读完总纲，再按总纲 §1 的顺序读三份详细规格：
> `PATROL_OPTIMIZE.md`（7项改造细则）、`PATROL_ZOOM_WALL.md`（缩放+穿墙检测）、`PATROL_SEED_ROUTE.md`（编辑器增强+推荐路线），
> 以及现有代码（`patrol_page.dart`、`path_metrics.dart`、`mock_data.dart`、`models.dart`、`providers.dart`、`cad_meta_server.py`、`cad_meta_build.py`）。

**按总纲 §2 的 4 个阶段顺序执行**，每阶段完成验收清单后才进下一阶段，每阶段结束跑 `flutter analyze` + `flutter build web --release`，输出改动文件清单+验收自查结果。

关键点：
1. 阶段1 一次性建齐 `PatrolPlan/PatrolPoint/PatrolRecord/PatrolArgs` 模型，**PatrolPlan 直接带 `isRecommended` 字段**（默认false），避免阶段3回改模型
2. 阶段3 的 `cad_meta_build.py` 必须把 `dy04_7_B05` 加进 `OCF_KEYS` 并本机跑通，生成 `assets/walls/dy04_7_B05_walls.json`
3. 阶段5（A*自动寻路）**只读不实现**
4. 总纲 §4 的推荐路线坐标校准是**人工步骤**，代码侧只保证"校验穿墙"等工具可用
5. 与量尺修复的文件隔离：巡场改造不要碰 `measure_*`、`capture_page.dart`、AR 相关文件；两线都会改 `models.dart`（量尺在 PhotoCalib/MeasureItem 区域，巡场新增 Patrol* 类在文件别处）——**改动前先读最新 models.dart，在各自区域叠加，不要互相覆盖**

---

## 暂不执行：AR 量尺

- 文档已有：`AR_LIDAR_IMPL_DETAIL.md`（主实现）+ `AR_UX_SMOOTH.md`（交互补丁，冲突处以补丁为准）
- **现在不要动**：iOS 代码无法在本机（Windows）编译，需 Mac + iPhone 12 Pro 及以上真机；等设备到位后再安排实现，避免改一半烂尾

---

## 全局约束（所有任务线通用）

1. 所有改动保持旧数据兼容（读旧字段给默认值，不抛异常）
2. 每完成一项/一阶段：`flutter analyze` 无新增 error，Web 构建可过
3. 不要跑 iOS/Android 构建（Windows 环境）
4. 删除常量/文件前先 grep 确认无引用
5. 量尺修复完成后对照 `TEST_PLAN_MEASURE.md` 第 0~4 节自查（尤其 1.1 竖线标定、2.x 标记对齐、4.x 全流程）
