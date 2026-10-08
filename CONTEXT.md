# 上下文速览（给下一会话读，控制 token 成本）

> 用法：新会话先读本文件。只列"现在是什么状态 / 关键约定 / 怎么测 / 坑在哪"，细节去对应文件看。
> 最后更新：2026-09-23（AR 真机包 v0.1.0 已出，正在侧载）。仓库：gongdi_app（Flutter，工地验收）。

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
| **AR 标注对齐样张**（09-23） | `ios/Runner/ArMeasureView.swift` | 胶囊读数（竖边自动竖排，替换裸 SCNText）、虚线圆柱串（SceneKit 无原生虚线）、空心方块端点、**勾股直角边虚线**（水平投影+高度差）、面积对角虚线+边长胶囊+中央面积大字、体积**隐藏边虚线**（按"离相机最远的角"判定）+长/宽/高胶囊+中央体积大字 |
| **真机读数单位修复**（09-23） | `measure_math.partsFromWorldMeters` | 原 bug：原生世界坐标是**米**，喂给约定 mm 的 `pythagorasParts` 时漏乘 1000 → 界面显示 `1mm`（原生尺寸线却是 700mm）。换算集中到一个函数并加回归单测 |
| **「高度和」模式**（09-23） | `measure_math.dart`（`HeightSum`）、`ar_measure_page.dart` | 分段累加竖直高度：量一段、举高再量一段自动求和（≥2 段才落库一条独立记录）；切换读数模式/清除会重置累加器 |
| **iOS 云端构建+发布**（09-23） | `.github/workflows/ios-release.yml`、`codemagic.yaml` | 推 `v*` tag 自动建 Release 并附无签名 IPA（约 68MB，仓库 PUBLIC 免登录下载）；`gh workflow run` 手动触发只出 artifact |
| **电脑端样式效果图**（09-23） | `tools/ar_style_preview.dart` | `flutter test tools/ar_style_preview.dart` → `build/ar_style_preview/*.png`；复用同一套样式库离屏渲染 4 种形态，用于在电脑上核对观感（几何是示意，非真实 AR 坐标） |
| **真机验证通过项**（10-08） | v0.1.0 侧载实测 | 读数单位（不再 1mm）、面域+对角虚线+中央大字、边长胶囊（横/竖）、`已吸附：物体边界（±11mm）`、四个读数模式（含高度和）、「采纳本组」首屏可见 —— 全部符合预期 |
| **胶囊残留修复**（10-08） | `ArMeasureView.swift` | 面/体生成时**未撤掉上一条直线的读数胶囊**，与面域自己的边长胶囊混在一起 ⟹ 出现"多出胶囊、数值与面积记录对不上"。修法：`showArea`/`showVolume` 里加 `clearDimension()`，并给面/体节点命名 + `clearAreaVolume()` 按名兜底清理 |

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
- 单测：`flutter test`（现 **226 通过**；4 个 `widget_test.dart` auth 失败为**既有问题**，与量尺无关）。
- 效果图（电脑端核对样式）：`flutter test tools/ar_style_preview.dart` → `build/ar_style_preview/*.png`。

## 2. 环境与工具坑（已踩过，别再撞）
1. **iOS 已可云端构建**（本机仍是 Windows、无 Mac）：推 `v*` tag 或 `gh workflow run ios-release.yml --ref main` → GitHub Actions 在 `macos-15` 构建无签名 IPA → 自动发 Release（`https://github.com/linxinquan/site-patrol/releases`，仓库 PUBLIC 免登录下载）。
   - **必须 Xcode 16**：`app_settings 9.0.0` 的 SPM 清单声明 swift-tools 6.0，Xcode 15 的 Swift 5.10 在 *resolve package dependencies* 阶段就失败（报 `is using Swift tools version 6.0.0 but the installed version is 5.10.0`）。
   - **推送时网络坑**：本机 git 配了代理 `127.0.0.1:7897` 但时通时不通，需在「绕过代理（`-c http.proxy= -c https.proxy=`）」与「走代理」之间**交替重试**。
   - **PowerShell 坑**：`gh` 的 `--jq` 表达式**含空格会被拆成多个参数**（报 `accepts 1 arg(s)`）；用无空格表达式，或直接 `curl.exe` 验证 Release 资产。
2. **agent-browser**（交互回归）：已全局装（复用本机 Chrome；官方 Chromium 下载在国内超时，不必装）。要点见脚本头注释：
   - Flutter Web 控件定位：**必须先开语义树**（`document.querySelector('flt-semantics-placeholder').click()`），且语义树随重渲染重建 → 定位**必须重试**；
   - 画布打点：在 **`flutter-view`** 上直接派发 PointerEvent；**不要派发到 `flt-glass-pane`**（会处理两次）；
   - 不用 `agent-browser mouse`（坐标不可靠）、不用 `state save/load`（往仓库根写文件 + 与导航打架）。
3. **npm 脚本策略**：装 agent-browser 需 `npm install -g --allow-scripts=agent-browser agent-browser`。
4. **PowerShell 脚本中文**：PS 5.1 读无 BOM 文件按 ANSI → 中文用 `[char]` 码点拼装（见 smoke 脚本 `U` 函数）。
5. **Windows 侧载环境（09-23 已装好）**：iTunes 12.13.11.1（`winget install Apple.iTunes`）**不带** Apple 驱动 —— 必须再装 `winget install Apple.AppleMobileDeviceSupport`（19.4.0.10），才会出现 `Apple Mobile Device Service` 服务与 Apple USB 驱动；否则 iPhone 在设备管理器里只是 WPD 便携设备、Sideloadly 报"找不到设备"。Sideloadly 在 `D:\Sideloadly\`，**装了新驱动后必须重启 Sideloadly** 才会重新枚举设备（重启后应能看到 `Apple Mobile Device USB Device` 状态 OK）。

## 3. 待办 / 边界（[待真机] = 只能 Mac/真机验证）

### ⏭ 2026-09-24 从这里继续（侧载最后一步没做完）
侧载环境**已全部就绪**：Sideloadly 已识别设备（`Yang (26 6.2) …@USB`）、Apple ID `happyyangyuting@sina.com` 已填、IPA 已下到 `C:\Users\yuting.yang1\Downloads\Runner.ipa`（68.3MB, v0.1.0）。
**卡点**：Sideloadly 的 IPA 框仍是 `(none)`，还差加载 IPA 这一步。明天按此顺序：
1. Sideloadly 左上角 IPA 框加载 `Downloads\Runner.ipa`（或直接拖进去）；
2. Advanced Options **全部保持默认不勾**；
3. 点 **Start** → 粘贴 **App 专用密码**（该账号开了双重认证，普通密码会报错；专用密码同理需在 appleid.apple.com 生成）；
4. iPhone：设置 → 通用 → VPN与设备管理 → **信任**证书；iOS 16+ 还要开「隐私与安全性 → **开发者模式**」并重启；
5. **真机逐项验证本轮改动**：
   - 读数**不再是 1mm**（米→mm 单位 bug）；
   - 底部「采纳本组」**直接可见**、不用滚（原先被采样明细列表顶出首屏）；
   - 点两点：黄线 + 两端空心方块 + 中点胶囊；**勾股直角边虚线**；
   - 面积：面域 + 对角虚线 + 边长胶囊 + 中央 `x.xxxm²`；体积：立方体 + **隐藏边虚线** + 三边胶囊 + 中央 `x.xxxm³`；
   - 「高度和」：连续量两段自动累加求和；
   - 若观感偏差（胶囊大小/字号/虚线密度/大字比例），按真机截图微调 `ArMeasureView.swift` 后**重新推 tag 出包**（约 6 分钟）。
6. 免费 Apple ID 签名的 App **7 天过期**，到期用同一 App 专用密码重签（IPA 不必重建）。

- **真机验证清单（同事 Mac 打包后逐项过）**：吸附（墙根线/墙角）、原生黄线/方块/胶囊、面/体半透明绘制、距离门控、尺度校正 k、拍照留图直存相册、设置页"真机自检"逐项核对。
- **P1 精度基线**：按 `docs/AR_ACCURACY_BASELINE.md` 跑 20 组实测填表 → 定「可判定/仅参考」两档。
- **面积/体积"直接框选面/体"**（手框面，非量边组合）：需原生平面检测，未做。
- `capture_records_test.dart`（riverpod API 漂移）+ `widget_test.dart`（auth）为既有失败，未处理。
- `pubspec.lock` 会带 8 行环境性版本回退（本机环境所致，无法避免，已随提交）。

## 4. 其他模块状态（一句话）
- 报告四端（HTML/PDF/DOCX/XLSX）量尺清单渲染统一走 `measure_labels.dart`；量房成图（room_draw_page）已支持手动打点+闭合差+导出户型图；GPS/语音等原生能力均待真机。
