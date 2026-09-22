# 上下文速览（给下一会话读，控制 token 成本）

> 用法：新会话先读本文件。只列"现在是什么状态 / 关键约定 / 怎么测 / 坑在哪"，细节去对应文件看。
> 最后更新：2026-09-22（量尺段收尾）。仓库：gongdi_app（Flutter，工地验收）。

## 1. 量尺模块（本轮主线）

### 已交付（a66d304 / 13f2b5e 及后续）
| 能力 | 文件 | 备注 |
|---|---|---|
| 照片量尺透视校正 | `lib/core/utils/homography.dart`、`measure_math.dart` | DLT 单应（归一化+Jacobi 特征向量），网格多点标定；旧两点比例保留回退 |
| AI 自动识别网格/目标 | `lib/data/vision_service.dart`、`measure_page.dart` | 识别→图上绿色/琥珀标注→**人工确认**才生效；尺寸一律由标定换算，不认模型报的数 |
| 面积/体积模式 | `lib/core/utils/measure_modes.dart`、`ar_measure_page.dart`、`features/measure/widgets/area_volume_sheet.dart` | 直线/面积/体积 三模式；面积体积**连续量 长宽[高] 自动出面/成体**（FaceBuilder） |
| 量尺叠加样式 | `lib/core/utils/measure_style.dart` | 明黄线 + 空心方块端点 + 胶囊标注（Web 预览**不再画面域/立方体/模拟吸附**，见"产品决策"） |
| AR 吸附（原生） | `ios/Runner/ArMeasureView.swift` | raycast 平面 → **平面边界/角点** → 特征点 → 深度兜底；snap 类型上报 Dart（真机提示条显示） |
| AR 原生面/体绘制（P2） | `ArMeasureView.swift` + `ar_measure_page.dart` + `measure_math.faceCorners` | 面积/体积生成后按**已采纳边的世界端点**画半透明黄面/立方体 + 边缘线 + 文字，[待真机] |
| AR 拍照留图 | `snapPicture`（原生合成）+ `deliverImage` | 相机画面 + AR 标注 → PNG → **一键直存相册** |
| 真机自检卡 | `ar_measure_page._buildSelfCheckCard` | 设置页：LiDAR支持/会话/尺度校正k/最近深度/最近吸附/已采纳数（给 Mac 打包后逐项核对） |
| 距离门控 + 尺度校正 | `ar_measure_page.dart`、`core/storage/ar_scale_calibration.dart` | 0.3~3m 最佳、>5m 丢弃；已知长度求 k 修正系统偏差 |
| 一键直存相册 | `lib/core/utils/save_to_gallery*.dart`（gal 2.3.3） | 移动端直存，失败/桌面/Web 回退分享面板/下载 |
| 导出测量图/户型图 | `lib/core/utils/dim_draw.dart`、`diagram_export.dart` | 图上标注尺寸 + 图签 |
| AR 交互回归脚本 | `tools/ar_preview_smoke.ps1` | 一条命令：登录→打点→采纳→面积/体积→截图（build\ar_smoke） |
| 精度基线 SOP（P1） | `docs/AR_ACCURACY_BASELINE.md` | 器材/样本矩阵/记录表/判定阈值算法（同事真机实测后填表） |

### 产品决策（容易回退错，必读）
- **Web 预览不画"样张式"面域/立方体/模拟吸附**：那些是需要 AR 空间坐标或真实场景的标注，预览里只能是合成示意——画出来会**误导用户**以为 App 已识别房间形状/边界。预览只画用户真实点出的几何 + 数值（在清单），并带"演示界面·非实测"角标。真机上由原生按真实命中绘制。
- **误差带 ≠ 精度**：`MeasureItem.errorMm` 是**重复性**；准确度靠尺度校正，口径分开。
- **单位**：`MeasureItem.unit ∈ {mm, m2, m3}`；面积/体积 `drawingMm=0`、**不参与合格判定**；文案统一 `measure_labels.dart`。
- **判定门槛**：默认 `tolMm=15 / tolPct=2%`；误差带 > 容差/3 → 「需卷尺复核」。
- **4mm 级项（垂直度/平整度/阴阳角）手机做不到**，报告只给"疑似偏差，请复核"，不给合格/超差。

### 关键约定（改动前必读）
（误差带/单位/判定门槛/4mm 上限已并入上方"产品决策"，此处只留补充）
- **样式**：图上标注长度用 `m/3 位小数`；清单/报告按工程习惯 mm 取整、面积 2 位小数。

### 测试入口
- Web 预览（无原生依赖）：`flutter build web --release` → `python -m http.server 8080 -d build\web` → `http://localhost:8080/#/measure/ar`。
- 回归脚本：`powershell -ExecutionPolicy Bypass -File tools\ar_preview_smoke.ps1`（截图到 `build\ar_smoke`；`-SkipLogin` 复用会话）。
- 单测：`flutter test`（现 218 通过；4 个 `widget_test.dart` auth 失败为**既有问题**，与量尺无关）。

## 2. 环境与工具坑（已踩过，别再撞）
1. **iOS 不能在本机（Windows）编译**：所有 LiDAR/ARKit/相册（gal）原生功能**只能写代码、待真机/Mac 验证**；iOS 打包需 Mac 上 `pod install`。用户真机 = iPhone 14 Pro Max（有 LiDAR ✓）。
2. **agent-browser**（交互回归）：已全局装（复用本机 Chrome；官方 Chromium 下载在国内超时，不必装）。要点见脚本头注释：
   - Flutter Web 控件定位：**必须先开语义树**（`document.querySelector('flt-semantics-placeholder').click()`），且语义树随重渲染重建 → 定位**必须重试**；
   - 画布打点：在 **`flutter-view`** 上直接派发 PointerEvent；**不要派发到 `flt-glass-pane`**（会处理两次）；
   - 不用 `agent-browser mouse`（坐标不可靠）、不用 `state save/load`（往仓库根写文件 + 与导航打架）。
3. **npm 脚本策略**：装 agent-browser 需 `npm install -g --allow-scripts=agent-browser agent-browser`。
4. **PowerShell 脚本中文**：PS 5.1 读无 BOM 文件按 ANSI → 中文用 `[char]` 码点拼装（见 smoke 脚本 `U` 函数）。

## 3. 待办 / 边界（[待真机] = 只能 Mac/真机验证）
- **真机验证清单（同事 Mac 打包后逐项过）**：吸附（墙根线/墙角）、原生黄线/方块/胶囊、面/体半透明绘制、距离门控、尺度校正 k、拍照留图直存相册、设置页"真机自检"逐项核对。
- **P1 精度基线**：按 `docs/AR_ACCURACY_BASELINE.md` 跑 20 组实测填表 → 定「可判定/仅参考」两档。
- **面积/体积"直接框选面/体"**（手框面，非量边组合）：需原生平面检测，未做。
- `capture_records_test.dart`（riverpod API 漂移）+ `widget_test.dart`（auth）为既有失败，未处理。
- `pubspec.lock` 会带 8 行环境性版本回退（本机环境所致，无法避免，已随提交）。

## 4. 其他模块状态（一句话）
- 报告四端（HTML/PDF/DOCX/XLSX）量尺清单渲染统一走 `measure_labels.dart`；量房成图（room_draw_page）已支持手动打点+闭合差+导出户型图；GPS/语音等原生能力均待真机。
