# 蓝图落地 · 功能基线（FEATURE INVENTORY）

> 用途：**唯一的功能事实源**。接手/排期/评审前先读本文件；与其它 50+ 份开发日志冲突时，以本文件（代码核实结论）为准。
> 梳理方式：**逐文件读源码**，不采信过期文档与注释。核实日期 2026-09-18。
> 代码基线：commit `5361996`（重构验收流程…）+ 未提交工作区改动（含巡场报告归档、天气/语音记录下线）。
> 维护规则：功能增删/状态变化后**只改本文件对应行**，不要另开新文档。

---

## 0. 一句话定位

**设计院视角的现场数据闭环工具**（Flutter，iOS / Android / Web）：
现场取证 → 问题判定与闭环 → 巡检留痕 → 实测校核 → 报告交付 → 知识回流。

闭环主线：
```
拍照验收(AI识别)  →  问题清单(责任判定/整改回复/销项)  →  报告导出(HTML/PDF/DOCX/XLSX)
      ↑                                                        ↑
   巡场(路线/打卡/GPS)          照片量尺 · AR量尺 · 量房成图(实测校核)
```

**当前定性**：客户端闭环已跑通（可演示）；数据以**本地存储 + mock 种子**为主；线上后端**只有 1 个接口** `/api/vision`；CAD 链路已判废案待剥离；团队正在做**减法**（但未文档化）。

---

## 1. 状态图例

| 标记 | 含义 |
|---|---|
| ✅ | 已闭环：代码完整、可跑通、可演示 |
| 🟡 | 部分/受限：主体在，但依赖真机、外部服务，或已降级 |
| 🔴 | 未完成/占位：UI 在但逻辑为空、写死或 mock |
| ⛔ | 判废 / 冻结 / 待剥离 |

---

## 2. 功能全景（11 个模块）

### M1 账号、身份与引导

| # | 功能点 | 状态 | 入口/路由 | 关键证据 |
|---|---|---|---|---|
| 1.1 | 开屏登录页（点「开始使用」即登录，写死 demo 用户） | 🔴 | `/login` | `features/auth/login_page.dart:25-34` |
| 1.2 | 引导第 1 步：选择身份（4 个 mock 用户） | 🟡 | `/onboard` | `onboard_page.dart:42-47` |
| 1.3 | 引导第 2 步：选择项目 | ✅ | `/onboard/project` | `onboard_project_page.dart:43-50` |
| 1.4 | 路由守卫（未登录→login；未引导→onboard；已登录在 login→跳转） | ✅ | 全局 | `app.dart:43-61` |
| 1.5 | 会话持久化（已按 JWT 建模 token/refresh/expiresAt，但无真实鉴权） | 🟡 | — | `core/storage/session_store.dart:9-59` |
| 1.6 | 切换身份 / 切换项目 / 退出登录 | ✅ | 个人中心侧边栏 | `shared/widgets/profile_drawer.dart`、`user_switcher.dart` |
| 1.7 | 「添加更多账号 / 帮助 / 设置」 | 🔴 | 侧边栏 | `profile_drawer.dart:409-429`（仅提示"敬请期待"） |

> 结论：**整条账号线是演示态**。真实登录是后端重建方案中的客户端改造项之一。

---

### M2 项目与图纸

| # | 功能点 | 状态 | 入口/路由 | 关键证据 |
|---|---|---|---|---|
| 2.1 | 项目列表 / 切换（2 个种子项目：南科大附院 `nkf`、腾讯大铲湾 DY04·7栋） | ✅ | `/home` 顶部 | `mock/mock_data.dart:35-89`、`project_switcher.dart` |
| 2.2 | 楼层 + 图纸目录（各 11 张） | ✅ | `/projects` | `projects_page.dart` |
| 2.3 | 图纸查看：缩放 / 平移 / 复位 | ✅ | `/projects/drawing/:key` | `drawing_viewer_page.dart` |
| 2.4 | 热点跳转 + 长按锚定 | ✅ | 同上 | `drawing_viewer_page.dart:1174-1238` |
| 2.5 | 坐标校准（内置种子 / 轴网交点自动套图 / 图上多点最小二乘 / 粘贴 JSON / 清除） | ✅ | 校准弹窗 | `drawing_viewer_page.dart:190-283, 496-720` |
| 2.6 | 图上打点 → 直接创建缺陷 + 图钉标记 | ✅ | 图纸长按/点选 | `drawing_viewer_page.dart:785-965` |
| 2.7 | 上传 DWG（Web 自实现选择器；**移动端选择器已冻结返回 null**） | ⛔/🟡 | `/projects` | `_dwg_picker_io.dart:3-7`、`_dwg_picker_web.dart`、`cad_service.dart:190-207` |
| 2.8 | 导入图纸（PDF / JPG / PNG） | 🔴 | `/projects` | `projects_page.dart:189-191`（仅弹提示，未解析） |
| 2.9 | 矢量看图（浩辰 OCF，仅 Web 外链新窗口） | ⛔ | 工具条 | `drawing_viewer_page.dart:353-406`；随 CAD 剥离 |
| 2.10 | 蓝图原稿页（3 张预置 PNG，非真实 PDF 渲染） | 🟡 | `/blueprint` | `blueprint_viewer_page.dart` |
| 2.11 | 图层 / 布局面板（需真实 DWG 数据源） | 🔴 | 图纸工具条 | `cad_info_panel.dart:64-82` |

> **红线**：`2.5 / 2.6`（CAD **坐标系**能力）虽属 CAD 相关，但**必须保留**，它支撑「图纸打点定位 / 量尺图纸侧取值 / 巡场防穿墙」三条主功能；`2.7/2.9`（CAD **渲染转换看图**）随新网页版 CAD 项目剥离。

---

### M3 拍照验收（核心主链）

| # | 功能点 | 状态 | 关键证据 |
|---|---|---|---|
| 3.1 | 三步流程：选图纸部位 → 现场拍照 → AI 识别并保存 | ✅ | `capture/capture_page.dart`（两阶段 `select`/`operate`） |
| 3.2 | 楼层选择 + 图上选点 + 附近定位选择（点位写入水印 GPS/海拔） | ✅ | `capture_page.dart:2860` |
| 3.3 | 真实相机（移动端相机 + 权限引导 + 相册兜底；Web 走相册选图） | ✅ | `capture_page.dart:532-552` + `core/utils/camera_pick.dart` |
| 3.4 | 防篡改水印烧录（信息栏 + 全图斜水印 + 图纸坐标 + 凭证号 + 哈希） | ✅ | `core/utils/photo_watermark.dart:58-165` |
| 3.5 | AI 缺陷识别（qwen3.8-max，`POST /api/vision`） | 🟡 | `vision_service.dart:107`；Web 走 `vlPreset` mock，真机走真实 |
| 3.6 | 结果区 4 段：缺陷识别 / 量尺校对 / 问题描述 / 拍照记录 | ✅ | `capture_page.dart:95, 1531` |
| 3.7 | 量尺校对（图纸侧 vs 照片侧，双容差 ±10mm/±5%） | ✅ | `capture_page.dart:2441` |
| 3.8 | 问题描述：手打 + 语音追加 | ✅ | `capture_page.dart:123`、`speech_recognizer.dart` |
| 3.9 | 保存记录（可继续验收 / 查看记录） | ✅ | `capture_page.dart:3128-3195` |
| 3.10 | 验收记录工作台：统计条 + 时间/楼层/仅 AI 筛选 + 分组网格 + 详情 + 批量转问题清单 + 删除 | ✅ | `capture_records/capture_records_page.dart`、`capture_records_controller.dart` |
| 3.11 | 本地存储 `stored_vision_results` | 🟡 | Web 端 File 走内存，**刷新即丢** |

> 已知降级：AI 未返回严重程度 → 统一默认 `orange`（`capture_page.dart:805-806`）；类头注释「真实相机已注释」**已过期**（实际已接真机相机）。

---

### M4 问题清单与闭环（核心主链）

| # | 功能点 | 状态 | 关键证据 |
|---|---|---|---|
| 4.1 | 状态分段：全部 / 待整改 / 整改中 / 已销项 / 已拒绝 | ✅ | `defects_page.dart:1148` |
| 4.2 | 缺陷卡（部位/类型/严重度/责任人/责任单位/备注/处置/回复） | ✅ | `defects_page.dart:1523` |
| 4.3 | 记录详情页 | 🟡 | `record_detail_page.dart:14-16`（静态 mock 版；水印照片为占位绘制） |
| 4.4 | 设计师远程处置：远程已解决 / 远程已答复 / 需到现场 | ✅ | `record_detail_page.dart:532-602`、`Defect.designerAction` |
| 4.5 | 施工方整改回复 + 提交销项 / 仅保存待复核 | ✅ | `record_detail_page.dart:1217-135` |
| 4.6 | 二级页：待设计师处置 `/defects/disposal/designer`、待施工方回复 `/defects/disposal/reply` | ✅ | `app.dart:143-150` |
| 4.7 | 时间轴对比（同部位多时点照片滑块前后对比） | 🟡 | `timeline_compare_page.dart`（数据 mock + 照片 CustomPainter 模拟） |
| 4.8 | 严重程度（红/橙/黄/绿）+ 重要性 + 完成状态 + 未闭合说明 | ✅ | `models.dart:8-130, 628-645` |
| 4.9 | AI 整改建议（模型优先，本地 35 条建议库兜底） | ✅ | `core/utils/defect_suggestions.dart` |

---

### M5 报告与归档

| # | 功能点 | 状态 | 关键证据 |
|---|---|---|---|
| 5.1 | 导出弹窗：日期范围 + 小结手填 + 4 格式卡片 | ✅ | `defects_page.dart:218-534` |
| 5.2 | 四端渲染：HTML / PDF / DOCX / XLSX（共享 `ReportContent` 中间层） | ✅ | `report_builder.dart`、`report_pdf.dart`、`report_docx.dart`、`report_xlsx.dart` |
| 5.3 | 章节：照片墙 / 施工进度 / 台账 / 待协调问题 / 巡场清单闭环 / 量房记录 / 尺寸校对 / 巡场小结 | ✅ | `report_content.dart:214`（空板块自动剔除） |
| 5.4 | 概览统计（含尺寸校对合格/超差/需复核计数） | ✅ | `report_content.dart:259-298` |
| 5.5 | 报告归档（**只存元数据**，正文需重新导出） | ✅ | `report_record.dart`、`report_record_store.dart` |
| 5.6 | 巡场报告归档页（新建，未提交） | ✅ | `patrol/patrol_reports_page.dart`、`/patrol-reports` |
| 5.7 | 平台门控（Web 下载；移动端分享；桌面落盘） | ✅ | `report_export.dart`、`report_share.dart` |

> **最高维护成本点**：任何字段/统计改动必须**四端同步**（单测 `room_export_compat_test.dart` 已覆盖部分断言）。

---

### M6 巡场（工地巡检）

| # | 功能点 | 状态 | 关键证据 |
|---|---|---|---|
| 6.1 | 路线计划（2 条种子路线 + 持久化） | ✅ | `patrol_plan_store.dart`、`mock_data.dart:1212-1252` |
| 6.2 | 路线编辑器：加点 / 拖动 / 删点 / 双击设为检查点 / 撤销 / 清空 / 保存 | ✅ | `patrol_editor_page.dart` |
| 6.3 | 执行页：底图 + 样条路线动画 + 状态机（idle/running/paused/finished）+ 缩放复位 | ✅ | `patrol_page.dart` |
| 6.4 | 实时统计条（楼层/里程/点数/时长/模式） | ✅ | `patrol_page.dart:928-964` |
| 6.5 | 穿墙检测（真实几何运算 + 红色高亮 + 保存二次确认） | 🟡 | `geo.dart`、`wall_lines.dart`；**墙线资产仅 B05 一张（6 段）** |
| 6.6 | GPS 轨迹采集（geolocator） | 🟡 | `patrol_page.dart:317-369`；**只累计里程，从不上图** |
| 6.7 | 到达打卡（检查点绿/红/蓝语义 + 打卡率） | 🟡 | `patrol_page.dart:440-469`；按**动画进度**判定，非 GPS 到位 |
| 6.8 | 标记问题 → 跳转拍照验收（`source=patrol`） | ✅ | `patrol_page.dart:526-558` |
| 6.9 | 历史轨迹叠加 | 🔴 | 写入 `{lat,lng}`，读取 `{x,y}` → 轨迹退化为原点 |
| 6.10 | 巡检记录 `issueCount` | 🔴 | 恒为 0（标记问题后不回填） |
| 6.11 | 离线提示胶囊 | 🔴 | `patrol_page.dart:713` 写死文案 |

---

### M7 照片量尺（实测校核）

| # | 功能点 | 状态 | 关键证据 |
|---|---|---|---|
| 7.1 | 图纸侧两点量距（依赖 CAD 校准） | ✅ | `measure_page.dart:1287-1310` + `cad_coord.dart` |
| 7.2 | 照片侧标定：手动网格 + 单应透视校正（DLT，≥4 点） | ✅ | `core/utils/homography.dart`、`measure_page.dart:446-543` |
| 7.3 | AI 自动识别模数网格 → 图上绿标 → 人工确认 | ✅ | `measure_page.dart:548-665` |
| 7.4 | 锚物 / 参照物自动标定（零输入，两点比例法回退） | ✅ | `anchor_objects.dart`、`measure_math.photoMeasuredMmAuto` |
| 7.5 | AI 被测目标（门窗宽高双线自动配对 → 工程编号如 `M0921` + 模数吸附 + 逐条采纳） | ✅ | `measure_page.dart:740-883`、`engineering_naming.dart` |
| 7.6 | 误差带判定（`errorMm` + 1/3 门控 → 合格/超差/需复核） | ✅ | `models.MeasureItem.canJudge`、`measure_math.canJudgeByError` |
| 7.7 | 判定门槛项目级可配置（容差 mm/% + 误差带门槛） | ✅ | `measure_threshold_store.dart`（键 `measure_thresholds_v1:<project>`） |
| 7.8 | 校对清单 + 偏差趋势（系统性偏差判读） | ✅ | `measure_stats.dart` |
| 7.9 | 会话存储 `measure:<project>:<drawing>` | ✅ | `measure_store.dart:13` |

> 降级：AI 目标误差带为**估算值**（标定残差 or 0.5%×尺寸），非真实重复采样；所有 AI 能力**断网即失效**（降级为手动）。

---

### M8 AR 量尺

| # | 功能点 | 状态 | 关键证据 |
|---|---|---|---|
| 8.1 | iOS LiDAR 原生（ARKit + 场景深度，MethodChannel `ar_measure_channel`） | 🟡 | `ios/Runner/ArMeasureView.swift`；**待真机** |
| 8.2 | 采点 A/B + 连线 + 自动距离；长按清除；暂停/连续模式 | 🟡 | 同上 |
| 8.3 | 同边重复采样 → 中位数 ± 半极差误差带 → 逐组判定 | ✅ | `ar_measure_page.dart:245-330`（Dart 侧） |
| 8.4 | 距离门控（>5m 丢弃；0.3~3m 最佳区间提示） | ✅ | `ar_measure_page.dart:76-100` |
| 8.5 | 系统偏差校正系数 k（>15% 判测错） | ✅ | `core/storage/ar_scale_calibration.dart` |
| 8.6 | 批量保存（`source:'ar_lidar'`，带误差带） | ✅ | `ar_measure_page.dart:437-466` |
| 8.7 | 不支持态：区分「浏览器不支持」与「机型无 LiDAR」 | ✅ | `ar_measure_page.dart:473-544` |
| 8.8 | Web 预览（硬编码演示值 2980mm 等） | 🔴 | `ar_measure_page.dart:706-713` |
| 8.9 | Android AR | ⛔ | 无实现（调研结论：不投入） |

---

### M9 量房成图

| # | 功能点 | 状态 | 关键证据 |
|---|---|---|---|
| 9.1 | 手动打点成图：单击加点 / 点回起点闭合 / 长按删点 / 双击墙段加洞口 | ✅ | `room_draw_page.dart:108-284` |
| 9.2 | 正交吸附（内角 90±5°，保持墙长） | ✅ | `core/room/room_geometry.orthoSnap` |
| 9.3 | 概览：墙角数 / 周长 / 面积 / 闭合差（>15mm 高亮，>50mm 保存二次确认） | ✅ | `room_draw_page.dart:430-475` |
| 9.4 | 洞口（门/窗 + 距墙起点 + 宽；绘制挖空） | ✅ | `models.WallOpening`、`room_plan_painter.dart:115-147` |
| 9.5 | 记录列表（缩略户型图 + 面积 + 闭合差） | ✅ | `room_records_page.dart` |
| 9.6 | 详情（大图尺寸标注 + 改墙厚 / 删墙 + 净高 / 来源） | ✅ | `room_detail_page.dart` |
| 9.7 | 图纸核尺对照（选墙段 → 图纸点两端 → 生成 MeasureItem 入库） | 🟡 | `room_compare_page.dart`；判定**写死 15mm/2%，未接项目门槛** |
| 9.8 | 报告四端 `RoomBlock` | ✅ | `report_content.dart` |
| 9.9 | RoomPlan 自动扫描（iOS16+/LiDAR） | ⛔ | 模型预留 `source:'roomplan'`，**无原生实现，`/room-scan` 未注册** |
| 9.10 | 照片成图 / 拖动改点 | 🔴 | `room_draw_page.dart:20-21` 明确留待后续 |

---

### M10 数据层、后端与同步

| # | 功能点 | 状态 | 关键证据 |
|---|---|---|---|
| 10.1 | `Repository` 抽象接口（UI 只依赖接口） | ✅ | `repository/repository.dart:5-24` |
| 10.2 | `MockRepository`（实为**本地仓库**：Hive/localStorage 持久化 + 350ms 假延迟） | ✅ | `mock_repository.dart`（命名属历史遗留） |
| 10.3 | `RemoteRepository`（仅 `saveMeasurement`/`getMeasurement`，其余 12 方法 `throw UnimplementedError`） | 🔴 | `remote_repository.dart:52-90` |
| 10.4 | 数据源开关 | 🟡 | `providers.dart:26-28`；`Env.isProd ? Remote : Mock`（默认 dev→Mock） |
| 10.5 | 视觉服务 `POST /api/vision`（外挂 Express，`120.24.240.129:3000`，qwen3.8-max） | ✅ | `vision_service.dart:84-183` |
| 10.6 | CAD 服务（浩辰云图 `:8800` + 本地 ODA/ezdxf） | ⛔ | `cad_service.dart`；`server/ocf_server.py` 正在清理（本次已删 141 行） |
| 10.7 | 量尺落库服务 `measure_server.py`（`:8820`，从未上线） | 🔴 | `server/measure_server.py`；且 Flutter 默认 host 指向 `:3000`（**端口不一致**） |
| 10.8 | 后端重建方案（FastAPI + PostgreSQL + Redis + COS，离线优先 + SyncEngine/outbox） | ⛔ | `BACKEND_ARCHITECTURE.md`（2026-09-17 设计定稿，**待实施**） |

**客户端实际请求的外部地址（技术债：3 个硬编码 host）**

| 服务 | 配置项 | 默认值 |
|---|---|---|
| CAD / 底图 PNG / SVG | `CAD_HOST` | `http://localhost:8800` |
| 视觉识别 | `VISION_HOST` | `http://120.24.240.129:3000` |
| 量尺落库 | `MEASURE_HOST` | `http://120.24.240.129:3000` |

---

### M11 基础设施

| # | 能力 | 状态 | 关键证据 |
|---|---|---|---|
| 11.1 | 本地存储抽象（IO：secure_storage + Hive + 文件；Web：localStorage + **内存文件**） | 🟡 | `core/storage/local_storage.dart`、`app_storage_io/web.dart` |
| 11.2 | 语音输入（设备端离线 ASR，中文） | ✅ | `speech_recognizer.dart`、`voice_input.dart` |
| 11.3 | 水印 + SHA256/MD5（isolate） | ✅ | `photo_watermark.dart` |
| 11.4 | 图片压缩（isolate） | ✅ | `image_compress.dart` |
| 11.5 | 报告分享 / 下载（三分支） | ✅ | `report_share.dart`、`report_export.dart` |
| 11.6 | 离线提示条 | 🟡 | `offline_bar.dart`（静态文案） |
| 11.7 | 设计令牌 / 主题 / MiSans 字体 | ✅ | `core/theme/`、`DESIGN_TOKENS.md` |
| 11.8 | 相机取图工具 `pickPhotoRobust`（权限引导 + 相册兜底） | ✅ | `core/utils/camera_pick.dart` |
| 11.9 | 环境变量（`ENV` / 4 个 dart-define） | ✅ | `core/env/env.dart` |

---

## 3. 本地存储 Key 清单（数据事实源）

| Key | 内容 | 写入方 |
|---|---|---|
| `stored_vision_results` | 拍照验收记录（AI 结果 + 照片） | `capture_page.dart` / `capture_records_controller.dart` |
| `added_defects_v1` | 运行期新增缺陷 | `mock_repository.dart` |
| `measure:<project>:<drawing>` | 量尺会话 | `measure_store.dart` |
| `measure_thresholds_v1:<project>` | 判定门槛 | `measure_threshold_store.dart` |
| `room_scan_v1_<project>` | 量房记录 | `room_scan_store.dart` |
| `patrol_plans_v1_<project>` | 巡场路线 | `patrol_plan_store.dart` |
| `patrol_records_v1_<project>` | 巡场记录 | `patrol_record_store.dart` |
| `report_records_v1_<project>` | 报告归档元数据 | `report_record_store.dart` |
| `cad_calib_v3_<drawing>` / `cad_calib_library_v1` | 图纸校准 | `cad_calibration.dart` |
| `ar_scale_calib_v1` | AR 尺度校正 | `ar_scale_calibration.dart` |
| `uploaded_drawings_v1_<project>` | 上传图纸登记 | `uploaded_drawing_store.dart` |

> ⚠️ 这些 Key **互不连通**，是否同步到后端、如何同步，目前**无任何设计**。

---

## 4. 关键发现（功能漂移与风险）

1. **两条平行的"记录→清单"通路**：验收记录（`stored_vision_results`）与问题清单（`Defect`）是两套数据，靠「转入问题清单」手工转换；报告归档又是第三套元数据。三套之间无统一 ID 链。
2. **数据来源三重分裂**：默认走本地 Mock、真机走真实视觉模型、CAD 走另一个外部服务；三个 host 各自硬编码，且量尺 host 端口与服务实现**不一致**。
3. **后端处于"已判废 → 待重建"中间态**：`server/` 正在被清理，但客户端 `cad_service.dart`、`uploaded_drawing_store.dart`、`remote_repository.dart` 仍在工程内。
4. **"想到就加"的实锤**：首页快捷操作曾达 **9 个入口**（图纸管理 / 问题清单 / 语音记录 / 图层索引 / PDF 原稿 / 量房…），现被砍到 **5 个**；天气模块（模型 + provider + banner）整块删除；语音记录独立页删除。**收敛正在进行，但没有文档记录"为什么砍"**，易被下一轮重复加回。
5. **精度口径不统一**：拍照量尺 / AR 已接入项目级门槛，**量房核尺写死 15mm/2%**，同一份报告里两种判定口径并存。
6. **巡场三处"半接线"**：GPS 只算里程不上图、`issueCount` 恒 0、历史轨迹读写字段不一致（轨迹退化到原点）。
7. **文档与代码互相打脸**：`BACKEND_ARCHITECTURE.md` 称 `remote_repository.dart`「已删除」——实际仍在；称天气已拆成 `server/weather_server.py`——**该文件不存在**；`capture_page.dart` 类注释称相机已注释——**实际已接真机相机**。
8. **平台能力矩阵先天不齐**（同一功能各端可用性不同，需在验收标准里写清）：
   - AR 量尺：仅 iOS 真机
   - 矢量看图 / DWG 上传：仅 Web
   - Web 文件存储：刷新即丢
   - 报告导出：Web 下载 / 移动分享 / 桌面落盘
9. **非产品产物混入功能文档体系**：`VIDEO_PLAN_0908.md`（建筑漫游 AI 视频制作手册）、`PPT_OUTLINE_0902.md`、`REPLY_TO_LEADER_0902.md`、`email_drafts/` 属**对外汇报素材**，不是 App 功能，建议与功能文档分域存放。

---

## 5. 功能边界建议（**待你拍板，非既成事实**）

### 建议保留（主线，投入优先级最高）
- 拍照验收 → 问题清单闭环 → 报告四端
- 巡场（路线 / 打卡 / 报告归档）
- 照片量尺校对（含 CAD 坐标系能力）

### 建议降级为"演示可用、不做真机投入"
- 量房成图（手动打点保留；RoomPlan 待 iPhone Pro 真机到位再评估）
- AR 量尺（代码已在，等真机联调，**不再新增投入**）

### 建议剥离 / 移出本仓库
- CAD 渲染 / 转换 / 看图（浩辰 OCF、GStarSDK、ODA/ezdxf、DWG 上传预览）→ 新网页版 CAD 项目
- **保留** CAD 坐标系能力（屏幕像素↔图纸 mm、校准、轴网、墙线）

### 建议明确暂停（避免被重新加回）
- 天气 / 语音记录页 / PDF 原稿 / 图层索引 / 导入 PDF 图纸

### 待建（后端线，独立排期）
- 真实登录与权限（权限点而非角色）
- 后端服务 + 离线优先同步（SyncEngine / outbox）

---

## 6. 下一步（待确认后执行）

1. **确认本文件的模块划分与状态标记**（是否与团队认知一致）。
2. 确认第 5 节的功能取舍边界 → 产出版本级「做什么 / 不做什么」清单。
3. 补充 **角色与权限矩阵**（甲方 / 设计院 / 监理 / 施工方 × 业务动作），当前仅 `Party` 展示档案，无真实账号体系。
4. 产出**功能优先级与迭代计划**（结合后端重建里程碑）。
5. 清理文档：把 50+ 份开发日志归档到 `docs/archive/`，只留 `FEATURE_INVENTORY.md` 作为功能事实源。
