# 开发日志 2026-08-20（坐标验证闭环 + 校准持久化 + 校准库方案 B）

> 本文档为上下文记录，供后续（换电脑/新会话）继续开发使用。
> 项目：工地巡检智能化管理（腾讯大铲湾 DY04 / 7 栋 B05 图纸验证）
> 续接自：`DEVELOPMENT_LOG_2026-08-18.md`
> 目的：固化"CAD 坐标验证→持久化→免重复校准"的完整结论，减少重复探索的积分消耗。

---

## 一、今日完成（三阶段）

### 阶段 1：坐标验证闭环（浏览器 vs Flutter vs CAD 真实值）

**结论：两端算法一致，实测偏差压线 < 2mm，精度达标（接受现状）。**

- 单位：mm。验证点取图纸同一位置，三方坐标如下：

| 来源 | X (mm) | Y (mm) |
|------|--------|--------|
| 浏览器端 (localhost:8002) | 107.9 | 109.8 |
| CAD 真实值 | 107.9692 | 107.8095 |
| Flutter 端 (localhost:8085) | 107.0 | 109.5 |

- 偏差：
  - 浏览器 vs CAD：ΔX=0.07, ΔY=1.99 → 综合 ≈ 1.99mm（压线合格）
  - Flutter vs CAD：ΔX=0.97, ΔY=1.69 → 综合 ≈ 1.95mm（压线合格）
  - 浏览器 vs Flutter：ΔX=0.9, ΔY=0.3（两端一致性好）
- **已知短板**：仅单点校准，Y 方向接近 2mm 上限。若要更稳，需两点/多点校准（未做）。
- 用户已确认"接受这个精度，先这样用"。

**关键事实（避免重复排查）**：
- 仿射公式：浏览器 `imagePxToWorld` 与 Flutter `CadCoordMapper.screenToWorld` 完全等价：
  `X = a*px + c；Y = d*py + f`（b=e=0）。详见 8-18 日志根因修复。
- 校准参数来源：浏览器「复制参数」导出 JSON（嵌套 `m` 字段），Flutter 端 `fromCalibrationMap` 已兼容该格式。
- B05 示例真实参数：`{"key":"dy04_7_B05","imgW":4500,"imgH":2551,"paperW":1489,"paperH":844,"m":{"a":0.3308888888888889,"b":0,"c":-359.5469524500907,"d":-0.3308888888888889,"e":0,"f":852.7574962071062}}`

### 阶段 2：浏览器校准 JSON 持久化（P0-2 遗留项）

- 把浏览器导出的原始校准 JSON 持久化到本地存储（Web=localStorage，移动端=secure_storage/Hive），换图/重启/刷新后自动恢复，免每次粘贴。
- 实现：`CadCalibrationStore` 新增 `saveRawJson` / `readRawJson` / `deleteRawJson`，存原始 JSON 文本（与系数存值区分，避免二次转换丢字段）。
- 弹窗 textarea 预填优先级：内存态 → 持久化原始 JSON → 空占位。
- 新增「清除校准」按钮（已校准时显示），回到内置演示坐标系并清持久化。

### 阶段 3：校准库（方案 B：多图纸批量自动套用）

- **目标**：已校准过的图纸 key+参数存成"本地清单"，App 启动期一次性灌入内存，后续打开任意已校准图纸自动套用，无需手动粘贴或逐张加载。适合多图纸批量场景。
- **实现**：
  - `CalibrationLibrary`：固定 key `cad_calib_library_v1` 存清单 `{drawingKey: {raw, map}}`。方法 `upsert`/`remove`/`listCalibrated`/`readRaw`/`buildAll`（纯函数，不依赖 riverpod 以避免循环引用）。
  - `saveCadCalibration` 自动登记进库（传原始 JSON 时）；内置演示坐标系则从中移除。
  - `deleteCadCalibration` 同步从库移除。
  - `applyCalibrationLibrary(ref)`：启动期调用，`buildAll()` 结果灌入 `cadCalibrationMapProvider`。
  - `main.dart` 的 `AuthBootstrap` 启动期调一次 `applyCalibrationLibrary`（用静态 `_libraryApplied` 防重复）。
- **用户收益**：每张图纸第一次粘贴校准后，刷新/换图/关App重开/换到其他已校准图纸，坐标都自动准。

---

## 二、文件改动清单

| 文件 | 改动 |
|------|------|
| `lib/core/utils/cad_coord.dart` | （前期）`fromCalibrationMap` 兼容浏览器嵌套 `m` 格式 |
| `lib/core/cad/cad_calibration.dart` | 新增 `saveRawJson`/`readRawJson`/`deleteRawJson`；新增 `CalibrationLibrary` 类（`upsert`/`remove`/`listCalibrated`/`readRaw`/`buildAll`） |
| `lib/core/di/providers.dart` | 新增 `calibrationLibraryProvider`；`saveCadCalibration`/`deleteCadCalibration` 同步维护校准库；新增 `applyCalibrationLibrary(WidgetRef)` |
| `lib/features/projects/drawing_viewer_page.dart` | 校准弹窗预填改走校准库；保存时登记进库；`_clearCalibration` 走 `deleteCadCalibration`；新增「清除校准」按钮 |
| `lib/main.dart` | `AuthBootstrap` 启动期一次性 `applyCalibrationLibrary` |
| `test/cad_coord_test.dart` | 共 18 个测试：原有 12 + 持久化 3 + 校准库 3 |

---

## 三、测试状态

- `flutter test test/cad_coord_test.dart` → **18/18 通过**（含持久化与校准库）。
- `flutter analyze`（改动文件）→ 仅 1 个 info 级 `sort_child_properties_last`（既有代码 659 行，非本次引入），无 error/warning。
- **既有 `test/widget_test.dart` 失败与本改动无关**（登录 UI 集成测试与当前实现脱节），未处理。

---

## 四、运行/调试环境（重要，避免重复踩坑）

- **中文路径乱码**：PowerShell 下 `cd`/命令被拆乱。统一用 junction 规避：
  `mklink /J c:\sp "f:\建筑验收工具\site-patrol"`，之后 `cmd /c "cd /d c:\sp && flutter ..."`
- **端口占用**：Flutter Web 用 8085；静态服务器用 8002。占用时换端口或 `Stop-Process` 对应 python/chrome。
- **预览地址**：
  - Flutter Web：`http://localhost:8085`（需 `flutter run -d chrome --web-port=8085` 或 run config）
  - 浏览器 CAD 查看器：`http://localhost:8002/cad_viewer_hybrid.html`（静态服务器 `_start_static.bat` / `serve_web.ps1`）
- **校准弹窗两个按钮别混**：「应用」= 灌入粘贴的 JSON；「应用内置B05」= 回退演示坐标系。用户曾误点后者导致显示内置值。
- `web/cad_viewer_hybrid.html` 已加 `window.onerror` 全局捕获，白屏时显红色错误便于无 F12 排查。

---

## 五、遗留 / 待办

1. **两点/多点校准**：当前单点校准 Y 方向接近 2mm 上限，可上多点标定把误差再压小。
2. **浏览器端持久化**：`cad_viewer_hybrid.html` 刷新会丢校准（未做 localStorage 自动保存/恢复）。仅 Flutter 端有库。
3. **方案 A（未做）**：浏览器端校准后自动推给 Flutter（共享 JSON 文件/同源读取），连粘贴都省。当前仅方案 B（Flutter 端库）已落地。
4. **校准库 UI**：当前无"校准库管理"页面（列出已校准图纸、批量导出/导入）。如需要可加。

---

## 六、关键决策记录（供接续）

- 用户确认精度 **< 2mm 接受现状**，不要继续优化单点算法。
- 用户选择 **方案 B（校准库）** 而非方案 A，因是多图纸批量场景。
- 校准库与单图纸 `saveCadCalibration` 是**同一入口**，不会重复存储；库清单是索引，系数是按 key 单独存（`cad_calib_v3_<key>`），两者并存。
- `cad_calibration.dart` 保持纯净、**不 import providers/riverpod**，循环依赖靠 `buildAll()` 返回 Map、由 providers 层写入解决。

---

## 七、2026-08-20 后续补充（下午：UI 修正 + Web 预览内置校准）

> 承接上半日「坐标验证→持久化→校准库」后，继续处理用户反馈的 3 项问题。

### 1. 拍照验收页（现改名「拍照记录」）图纸串图修复
- **现象**：从图纸页进入拍照页，`CaptureArgs` 已带 `drawingKey`，但 `capture_page` 没用，而是按楼层名 `floorToDrawingKey(_floor)` 查全局 `nkf_*` 表，7栋B1 找不到 → fallback 到南方医院 `nkf_west_1f`，显示成另一个项目的图纸。
- **修复**（`lib/features/capture/capture_page.dart`）：
  - 新增成员变量 `Drawing? _drawing`；`_drawingKey` getter 优先用 `widget.args.drawingKey`。
  - `build` 中直接查 `dy7Drawings`（常量表，`Map<String,Drawing>`）而非依赖异步 `drawingsProvider`，避免 provider 加载完成前 fallback 串图。
  - 文案：AppBar「拍照验收」→「拍照记录」，底部按钮「保存验收记录」→「保存记录」。
- **配套**（`lib/features/projects/drawing_viewer_page.dart`）：`_anchor()`（锚点按钮）进入拍照页时也补上 `drawingKey: widget.d.key`。

### 2. 图钉/坐标标签遮挡图纸
- **现象**：`_buildAnnotationMarks` 图钉半径 16px、右侧带固定坐标标签，缩放时不变化，遮挡图纸内容。
- **修复**（`drawing_viewer_page.dart`）：图钉缩到半径 10px，**默认不显示坐标标签**；点击图钉弹窗显示完整 X/Y 坐标。减少遮挡。

### 3. Web 预览「没有校准」→ 内置真实校准种子
- **根因**：之前校准库只给移动端（secure_storage/Hive）用，Web 的 localStorage 从没被写入过真实参数，启动 `applyCalibrationLibrary` 读到空清单 → 回退演示坐标系（中心=原点近似），即用户看到的"没校准"。
- **修复**（`lib/main.dart` 启动期）：
  - 用真实 B05 参数（4500×2551 底图，`a=0.3308888888888889, d=-0.3308888888888889, c=-359.3091448275862, f=852.4496763746746`）构造 `CadCoordMapper`，`lib.upsert('dy04_7_B05', ...)` 写入校准库清单（`cad_calib_library_v1`）。
  - **仅在清单尚未登记该图纸时写入**（`readRaw` 判空），不覆盖用户手动校准。
  - 启动后 `applyCalibrationLibrary` 将其灌入内存，B05 打开即带真实坐标。
- **验证**：`flutter build web --release` 产出 `build/web`；用 Python 静态服务 `c:\sp\build\web` 于 **http://localhost:12345/**（8080 被系统 HTTP.sys 占用，serve_web.ps1 因中文路径编码错误需改用 junction 路径 `c:\sp\build\web`）。

### 变更文件清单（下午）
| 文件 | 改动 |
| --- | --- |
| `lib/features/capture/capture_page.dart` | 拍照记录改名；按 drawingKey 查 dy7Drawings 修复串图；图钉缩小/去标签在另一个文件 |
| `lib/features/projects/drawing_viewer_page.dart` | `_anchor()` 补 drawingKey；`_buildAnnotationMarks` 图钉缩小+去默认标签 |
| `lib/main.dart` | 启动期注入内置真实 B05 校准种子（仅空清单时写入） |

### 明日待办（用户提醒）
1. **拍照量尺校对功能**：拍照后量尺尺寸（照片中实测）与图纸坐标/真实尺寸做比对校验。⭐ 重点
2. 回归验证 capture_page 多图纸串图修复效果。
3. 验证 Web 预览其他有底图图纸是否需要预置真实校准。

### 环境提示（更新）
- **Web 预览地址**：`http://localhost:12345/`（Python 静态服务 `c:\sp\build\web`）。
- 8080 被系统 HTTP.sys（PID 4）占用，勿用。
- `serve_web.ps1` 的 root 已改 `c:\sp\build\web`（junction）以避中文编码问题。
</content>
