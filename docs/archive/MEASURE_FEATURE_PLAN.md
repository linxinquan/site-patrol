# 量尺校对功能 — 实现路径（交付给 AI 实现）

> 目标：**今天内**在 site-patrol（Flutter + Express 后端）中实现"量尺校对"功能。
> 定位：**半自动标定测量**（不用AI识别），对照"照片实测尺寸 vs 图纸尺寸"，输出偏差与判定。
> 背景：设计师访谈痛点——"施工尺寸与图纸不符，肉眼难以发现的，希望拍照后可以识别尺寸，并方便对照图纸正确尺寸"。

---

## 1. 功能定义（五步流程）

1. **拍照/选图**：复用现有取图逻辑（Web=相册，移动端=相机）
2. **标定**：照片上点两个点 + 选参照物（快捷项：门宽900 / 瓷砖600 / A4纸297 / 标准砖240 / 自定义），得到 比例尺
3. **测量**：照片上点两个点 → 实时显示换算出的 mm（支持多条，各自命名、着色）
4. **图纸对照**：从图纸视图量出该部位的"图纸尺寸"（优先自动，见 §3），或手动输入
5. **对比判定 + 保存**：`|照片实测 - 图纸尺寸| ≤ 阈值`（默认 ±15mm，可配置）→ 绿"符合" / 红"超差Xmm"；保存为一条"量尺校对记录"

核心公式（照片侧）：
```
比例尺 scale_mm_per_px = 参照物真实尺寸(mm) ÷ 参照物两点像素距离(px)
被测尺寸(mm) = 被测两点像素距离(px) × scale_mm_per_px
```

---

## 2. 现状盘点（已有资产，直接复用，先读这些文件）

| 资产 | 文件 | 说明 |
|---|---|---|
| 屏幕像素↔CAD世界坐标(mm) 换算 | `lib/core/utils/cad_coord.dart` | `CadCoordMapper.screenToWorld / worldToScreen / localToViewPixel`（含 InteractiveViewer 变换）——**图纸量距的基础，已实现** |
| 图纸校准持久化 | `lib/core/cad/cad_calibration.dart` | `CadCalibrationStore` / `CalibrationLibrary`，仿射系数 {a,b,c,d,e,f} 按图纸 key 存储 |
| 取图+压缩 | `lib/features/capture/capture_page.dart` 的 `_pickImage`、`lib/core/utils/image_compress.dart` | `kIsWeb` 分流、maxWidth 1280 / quality 82 |
| 图纸查看器 | `lib/features/projects/drawing_viewer_page.dart`、`blueprint_viewer_page.dart` | 先读代码确认：是否已接入 CadCoordMapper、是否已有"量距"模式；若已接入，图纸侧直接加按钮 |
| 自定义绘制范例 | `lib/utils/path_metrics.dart` | `CustomPainter` 画点/线/圆/脉冲的现成写法，测量覆盖层照此风格 |
| 本地存储 | `lib/core/storage/local_storage.dart` | `readDoc/writeDoc` JSON 文档 |
| 仓库模式 | `lib/data/repository/repository.dart`、`remote_repository.dart`、`mock_repository.dart` | 记录保存照此模式（本地先行，服务端可选） |
| 后端 | `backend/server.js`（Express :3000，`/api/vision` 已通） | 可选：`POST /api/measurements` |
| 视觉模型（可选冲刺） | `lib/data/vision_service.dart` + `/api/vision`（qwen3.8-max） | 可选：prompt 改为"读出图纸标注的尺寸数字"，自动填图纸侧 |

---

## 3. 新增 / 修改文件清单

### 新增（核心 4 个，建议按顺序）

**① `lib/core/measure/measurement.dart` — 数据模型**
```dart
class MeasureRef {          // 标定参照物
  final String label;       // 门宽 / 瓷砖 / 自定义...
  final double mm;          // 真实尺寸 mm
  final Offset p1, p2;      // 照片上两点（原图像素坐标）
  double get pxDist;        // 两点像素距离
  double get scaleMmPerPx;  // mm / px
}

class MeasureLine {         // 一条被测线
  final String label;       // 如"墙净宽"
  final Offset p1, p2;      // 原图像素坐标
  final double photoMm;     // 换算结果
  double? drawingMm;        // 图纸尺寸（自动量出或手填）
  double? get deviation;    // photoMm - drawingMm
  bool? get pass;           // |deviation| <= threshold
}

class MeasureRecord {       // 一条保存记录
  final String id;
  final String projectKey;  // 如 dy04_17
  final String location;    // 部位描述
  final String? photoPath;  // 或 base64
  final MeasureRef ref;
  final List<MeasureLine> lines;
  final double threshold;   // 默认 15
  final DateTime createdAt;
  final String? note;
}
```

**② `lib/core/measure/measure_math.dart` — 纯函数（可单测）**
- `double pxDist(Offset a, Offset b)`
- `double toMm(double pxDist, double scaleMmPerPx)`
- `MeasureLine buildLine(p1, p2, scale)` 
- `bool judge(photoMm, drawingMm, threshold)`
- **坐标映射**（易错点）：图片按 `BoxFit.contain` 显示，`LayoutBuilder` 拿显示区域；`原始像素 = (显示坐标 - 图片左上角偏移) ÷ 显示宽高 × 原图宽高`。**所有计算用原图像素，显示层只负责画**。参照 `cad_coord.dart` 的 `localToViewPixel` 思路。

**③ `lib/features/measure/measure_page.dart` — 主页面**
- 状态机：`idle → picked → calibrated → measuring → comparing → saved`
- 顶部模式 Switch：`标定模式 / 测量模式`（照 capture_page `_useMock` 的 UI 模式）
- 图片区：`GestureDetector`(onTapUp 取点) + `CustomPaint` 覆盖层（参照物线=蓝色虚线、被测线=橙色实线、端点=圆点、线中标注 mm 文字、超差线标红）
- 图纸对照区：显示该部位图纸尺寸（自动量出或手填输入框）+ 阈值输入（默认15）
- 对比表：每条线 照片实测 / 图纸尺寸 / 差值 / 判定（绿勾/红叉）
- 保存按钮：组装 `MeasureRecord` → `MeasureRepository.save()`

**④ `lib/data/measure_repository.dart` — 存取**
- `save(record)` / `list(projectKey)` / `get(id)`：本地 `LocalStorage`（照 `CadCalibrationStore` 的 key 前缀模式，如 `measure_records_v1_`）
- 可选（有余力）：`remote_repository.dart` 加 `POST /api/measurements`，后端 `server.js` 加对应路由（照 `/api/vision` 的 Express + CORS + json limit 模式）

### 修改（3 处，小改）

- `lib/features/capture/capture_page.dart`：拍照后加"量尺校对"按钮 → 跳转 measure_page（带照片）
- `lib/features/projects/drawing_viewer_page.dart`：加"图纸量距"模式 → 复用 CadCoordMapper（若已接入），点两点显示 mm，支持"填入当前测量记录"
- `lib/app.dart` / 底部导航 / home_page：加量尺校对入口（或并入现有巡检流程）

---

## 4. 图纸侧量距（重点：基本是现成的）

1. 进入图纸查看器（校准库已按图纸 key 自动套用 `CadCoordMapper`）
2. 开启"量距"模式：点两点 → `localToViewPixel` 得到整图像素 → `screenToWorld` 得到两个世界坐标(mm)
3. `图纸尺寸 = (worldA - worldB).distance`（mm）——**CAD 世界坐标即毫米，不需要图纸比例**
4. 结果回填到 measure_page 当前测量线的 `drawingMm`

> ⚠️ 先读 `drawing_viewer_page.dart` / `blueprint_viewer_page.dart` 确认现有接入程度：若尚未接入 CadCoordMapper，先在查看器内完成"点两点→世界坐标→距离"的最小接入（半天量级）。

---

## 5. 可选冲刺（有余力再做，不阻塞主流程）

- **AI 读图纸尺寸**：复用 `/api/vision`（qwen3.8-max），prompt 如"读取这张建筑图纸中标注的所有尺寸数字，按'部位:数值mm'输出JSON"。把图纸截图发过去，结果预填 `drawingMm`，设计师确认。管线现成，主要是 prompt 调优（注意超时 180s、JSON 截取解析照 AI_VISION_INTEGRATION.md）

---

## 6. 验收标准（今天"做完"的定义）

- [ ] `flutter analyze` 无新增 error
- [ ] 手动流程跑通：拍照 → 标定（门宽900）→ 量一条线 → 显示mm → 输入/量出图纸尺寸 → 出判定（绿/红）→ 保存成功
- [ ] Web 端（`flutter build web --release` + `serve_web.ps1`）可演示
- [ ] 用一张真实照片验证数值合理（比如量已知900mm门洞，误差 < 5%）
- [ ] 录制 90 秒演示视频

---

## 7. 演示脚本（给设计师/院长）

> "拍一面墙 → 拿门洞宽度900mm标定 → 画线量墙长 → 图纸上点两点量出设计尺寸 → 系统算差值：图纸3000、实测2985、差15mm、阈值内绿勾。以前要带尺子，现在拍照就够——肉眼看不出的偏差，这个能看出来。"

## 8. 红线（演示时如实说）

1. 精度 ±1~3%，受拍照角度/透视影响；**垂直拍摄、标定线与被测线尽量同一平面**
2. 定位是"快速校对"，不是精密计量（全站仪/激光测距的活）
3. 图纸侧今天以"点两点量距 + 可选AI读数"为准，不承诺全自动
