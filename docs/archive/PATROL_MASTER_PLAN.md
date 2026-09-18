# 巡场功能总改造 — 执行总纲（CodeBuddy 唯一入口）

> 本文件是巡场改造的**唯一执行入口**：定义执行顺序、阶段验收与全局约束。
> 详细规格在三份文档里，各阶段标注了"规格依据"，实现时按文档细则执行。
> 工作目录：`F:\建筑验收工具\site-patrol`（Flutter，iOS/Android/Web；本机 Windows 只能 `flutter analyze` + Web 构建验证）。

## 0. 任务总览

把"巡场"从硬编码demo（南科大医院底图+写死路线+假数据）改造成完整功能：

1. 数据驱动：路线/检查点/楼层成为项目数据（PatrolPlan），底图按当前项目切换
2. 标记问题点携带真实项目/图纸/坐标信息
3. 用户自规划路线：编辑器加点/删点/拖动/检查点/撤销/清空/保存
4. 地图缩放平移（InteractiveViewer），解决"图纸太大看不清"
5. 真实里程：按图纸 CAD 校准坐标实算路线长度
6. 穿墙检测：DXF 墙图层提取 → 路线穿墙段红色警告 + "校验穿墙"一键检查
7. 默认"全局巡场推荐路线"：不穿墙、符合工程习惯（模板可复制编辑）
8. GPS 真实轨迹记录 + 历史记录列表

## 1. 先读（按顺序，动手前必须全部读完）

1. `PATROL_OPTIMIZE.md` —— 7项功能的模型/存储/页面改造细则
2. `PATROL_ZOOM_WALL.md` —— 缩放平移（P0）+ 穿墙检测（P1）+ 自动寻路方案（P2不实现）
3. `PATROL_SEED_ROUTE.md` —— 编辑器交互增强 + 推荐路线工程规范与骨架
4. 现有代码：
   - `lib/features/patrol/patrol_page.dart`、`lib/utils/path_metrics.dart`
   - `lib/data/mock/mock_data.dart`、`lib/data/models.dart`、`lib/core/di/providers.dart`
   - `lib/core/storage/measure_store.dart`（存储模式参照）、`lib/core/utils/cad_coord.dart`
   - `server/cad_meta_server.py`、`server/cad_meta_build.py`（穿墙数据管线）

## 2. 执行顺序（4 个阶段 + 1 个不做项，每阶段必须跑通验收再进下一阶段）

### 阶段1：数据驱动 + 底图切换 + 缩放（规格：PATROL_OPTIMIZE §②①③ + PATROL_ZOOM_WALL §P0）

一次性完成，避免反复改 patrol_page.dart：

1. `models.dart` **一次性**新增 `PatrolPoint / PatrolPlan / PatrolRecord / PatrolArgs` 四个模型——**PatrolPlan 直接包含 `isRecommended` 字段（默认 false）**（来自 SEED_ROUTE §5，防止阶段3回改模型）
2. 新增 `lib/core/storage/patrol_plan_store.dart`（照 measure_store 模式）+ providers 新增 `patrolPlansProvider / patrolRecordsProvider`
3. `mock_data.dart` 新增 `seedPatrolPlans`：南科大=迁移原34点路径（不破坏旧演示）；7栋=两条——`dy7_recommended`（推荐，isRecommended=true，用 PATROL_SEED_ROUTE §3 的15点占位坐标）+ 可留空占位计划（用户在编辑器创建）
4. `patrol_page.dart` 重构：读 plan（按当前项目+planId）→ 底图从 `drawingsProvider[plan.drawingKey]` 取 → 楼层chip读 `plan.floor` → 检查点用 `plan.checkpointIdxs` → 地图区包 `InteractiveViewer`（minScale 1 / maxScale 12 + 复位按钮，照 PATROL_ZOOM_WALL §P0）
5. `_markIssue` 传真实信息（PATROL_OPTIMIZE §③：projectId/drawingKey/floor/校准后 worldX/Y）
6. 清理：`path_metrics.dart` 的 `patrolPathPoints/patrolCheckpoints` 迁移进 mock 种子（保留注释出处）；`patrolPlanKey` 确认无引用后删除；`nkf_west_1f.png` 写死删除

**阶段1验收**：
- [ ] 切"腾讯大铲湾DY04·7栋"打开巡场 → 底图B05、楼层"B1"、推荐路线渲染（占位坐标）、带"推荐"徽标
- [ ] 切南科大 → 原西楼1F路线不变
- [ ] 捏合/滚轮放大≥5×可看清走廊，可平移，复位回全图
- [ ] 标记问题点 → 拍照页收到 projectId/drawingKey/floor，B05已校准带 worldX/Y
- [ ] `flutter analyze` + Web 构建通过

### 阶段2：路线编辑器 + 真实里程（规格：PATROL_OPTIMIZE §④⑤ + SEED_ROUTE §1 基础交互）

1. 新增 `lib/features/patrol/patrol_editor_page.dart`：单击加点、拖动移点、长按删点、双击切检查点、撤销/清空/保存；底图同款 `InteractiveViewer`（缩放平移）；坐标换算用 contain 反算（照 measure_page 经验，注意 InteractiveViewer 用 `TransformationController.toScene()` 取 child 坐标）
2. `patrol_page.dart` AppBar 加"编辑路线"入口 + go_router 路由 `/patrol-editor`
3. 新增 `realRouteKm()`（path_metrics.dart）：路线点经 `CadCoordMapper.screenToWorld` 求世界距离累加→km；巡场页里程 chip 用实算值，未校准走 `plan.totalKm` 兜底；点数 chip = 按进度×路线点数（删除常量48）

**阶段2验收**：
- [ ] 编辑器加5点→拖1点→长按删1点→双击设2检查点→保存→巡场页路线更新；重进App仍在
- [ ] B05（已校准）里程 chip 显示实算km；南科大走兜底
- [ ] `flutter analyze` + Web 构建通过

### 阶段3：穿墙检测 + 编辑器增强 + 推荐路线（规格：PATROL_ZOOM_WALL §P1 + PATROL_SEED_ROUTE §1~5）

1. **Python管线**：`cad_meta_server.py` 的 `parse_dwg_to_meta()` 追加 `wall_lines` 提取（LINE/LWPOLYLINE，图层名含 WALL/墙 且不含 COL，输出世界坐标mm）；`cad_meta_build.py` 的 `OCF_KEYS` **加入 `dy04_7_B05`**，生成后拷贝 `assets/walls/dy04_7_B05_walls.json`；`pubspec.yaml` 注册 `assets/walls/`
2. 新增 `lib/utils/geo.dart`（`segmentsIntersect` 叉积法 + `routeSegmentHitsWall` 纯函数）+ `lib/core/cad/wall_lines.dart`（rootBundle 加载 + `worldToScreen` 转相对0-100；未校准返回 null 并提示降级）
3. **编辑器增强**（SEED_ROUTE §1）：单击选中点+高亮+`删除`/`设为检查点`按钮；**"校验穿墙"按钮**（全路线跑检测→弹出"N段穿墙"+红色高亮 或 "无穿墙✓"）；**"复制路线"按钮**（另存"xx-副本"）；保存时穿墙段弹确认框
4. `PatrolOverlayPainter` 加 `crossingSegs` 参数：巡场页穿墙段红色渲染
5. 推荐路线种子就位（阶段1已建 isRecommended 字段；阶段3只改 mock 种子数据，不动模型）

**阶段3验收**：
- [ ] 本机跑通 `python server/cad_meta_build.py` → B05 元数据含 wall_lines → `assets/walls/dy04_7_B05_walls.json` 生成
- [ ] 编辑器打开占位推荐路线 → "校验穿墙"显示 N 段红色（证明检测生效）
- [ ] 选中点删除/设检查点/复制路线 可用
- [ ] 巡场页穿墙段红色
- [ ] `flutter analyze` + Web 构建通过

### 阶段4：GPS 真实轨迹 + 历史记录（规格：PATROL_OPTIMIZE §⑥⑦）

1. `pubspec.yaml` 加 `geolocator`；AndroidManifest + Info.plist 加定位权限
2. 新增 `lib/features/patrol/patrol_location_service.dart`（位置流、haversine 里程、track 记录、权限拒绝→手动模式降级）
3. `patrol_page.dart`：开始巡场启动GPS、里程chip用GPS实距、状态标识 GPS/手动、结束生成 PatrolRecord（时长/里程/点数/问题数）
4. 新增 `lib/core/storage/patrol_record_store.dart` + `lib/features/patrol/patrol_history_page.dart`（倒序列表+详情）；"历史轨迹"按钮跳真实列表（删假SnackBar）；go_router 加 `/patrol-history`

**阶段4验收**：
- [ ] 真机授权定位→轨迹/里程真实增长；拒绝→降级计时模式不崩溃
- [ ] 完成巡场→历史列表出现记录；重进App仍在；统计正确

### 阶段5【不实现】：A* 自动寻路（PATROL_ZOOM_WALL §P2 只读方案，等P1稳定后排期）

## 3. 全局约束（所有阶段通用）

1. **只改巡场相关文件** + 通用模型/存储/Python管线；**不碰量尺（measure_*）、拍照验收、AR 相关文件**
2. 所有存储读取旧数据给默认值兜底，不抛异常
3. 每阶段结束：`flutter analyze` 无新增 error + `flutter build web --release` 通过
4. 不跑 iOS/Android 构建（Windows 无法验证；geolocator 原生部分留待 Mac/真机）
5. 删除常量/文件前先 grep 确认无引用
6. 每阶段输出：改动文件清单 + 验收项自查结果

## 4. 人工步骤（代码完成后，团队做，约20分钟）

推荐路线占位坐标 → 真坐标校准（PATROL_SEED_ROUTE §4）：
编辑器放大到走廊级 → 按工程规范（闭环/只走公共走道/检查点八类）把占位点拖到真实走廊中线 → "校验穿墙"到 **0 红色段** → 里程合理 → 保存 → 把最终坐标**回写** `seedPatrolPlans` 的 `dy7_recommended`（替换占位值）。

## 5. 最终演示脚本（巡场）

> "巡场不再是写死的demo：打开就是当前项目的图纸和推荐路线——全局巡场按疏散通道闭环，楼梯、电梯、扶梯、机房、坡道、防火门自动设为检查点，路线有没有穿墙系统自动校验。路线可以自己画：加点、删点、拖动都行，里程按图纸真实坐标算出来。现场走一圈，GPS记录真实轨迹，历史随时回看。以后每个项目5分钟配一条自己的巡场路线。"
