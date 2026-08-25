# 量尺校对功能 — 改进实现清单（交付 CodeBuddy）

> 背景：MEASURE_FEATURE_PLAN.md 已实现（5文件），评审发现 2 个 P0 Bug + 若干 P1/P2 问题。
> 要求：**先读现有实现再改**；每项改动后保持 `flutter analyze` 无新增 error；不要改动与量尺无关的代码。

---

## 🔴 P0-1：照片标定只用 X 方向（1D），测量用 2D 距离 —— 不一致导致斜线/竖线标定算错

**问题**：`PhotoCalib` 只存 `pixA/pixB`（仅 x 坐标），`mmPerPx = refMm / (pixB - pixA).abs()`（纯水平差）；而测量用 2D 欧氏距离。参考物画斜线 → 比例尺偏大；参考物竖着画（门高/层高）→ 水平差≈0 → mm/px 爆炸，量出天文数字。

**涉及文件与修改**：

1. `lib/data/models.dart` — `PhotoCalib`（约 512~534 行）
   - 字段改为 `ax, ay, bx, by`（参考物两端点完整坐标）+ 保留 `imgW`
   - `mmPerPx => refMm / sqrt((bx-ax)^2 + (by-ay)^2)`（2D 距离）
   - `copyWith` 同步改
2. `lib/core/storage/measure_store.dart` — `_toJson`（约 43~50 行）与 `_fromJson`（约 70~77 行）
   - 序列化字段同步为 ax/ay/bx/by
   - **向后兼容**：`_fromJson` 读到旧格式（只有 pixA/pixB）时，ay=by=0，退化为旧行为（水平距离），不能报错
3. `lib/features/measure/measure_page.dart` — `_applyRefCalib`（约 198~220 行）
   - 存点时改为 `pixA: _refPicks[0].dx, pixA_y: _refPicks[0].dy, ...`（按新模型字段）
4. `lib/core/utils/measure_math.dart` — 无需大改（`photoMeasuredMm` 已用 2D `photoDistancePx`），确认签名与模型一致即可

**验证**：用一张照片，参考物竖着标定（如 1000mm 门高），量同方向线段，数值应合理（误差 <5%），不再出现巨大/异常值。

---

## 🔴 P0-2：选点标记显示错位（原图像素坐标直接用于 Positioned）

**问题**：`_pickDot(p, c)` 把**原图像素坐标**直接当 `Positioned(left/top)` 用，但图片按 `BoxFit.contain` 缩放显示，标记画在错误位置（原图坐标 > 容器尺寸时直接不可见）。

**涉及文件**：`lib/features/measure/measure_page.dart`

**修改**：
1. 新增坐标换算工具方法（页面内私有函数即可，或放 `measure_math.dart`）：
   ```dart
   /// 原图像素坐标 → 显示坐标（BoxFit.contain 反算，_onDrawTap 的逆变换）
   Offset imageToDisplay(Offset imgPx, Size box, Size imgSize) {
     final contain = _containSize(box, imgSize); // 已有此函数
     final offX = (box.width - contain.width) / 2;
     final offY = (box.height - contain.height) / 2;
     return Offset(
       offX + imgPx.dx / imgSize.width * contain.width,
       offY + imgPx.dy / imgSize.height * contain.height,
     );
   }
   ```
2. 三处标记渲染改为先换算再定位：
   - 图纸侧：`_drawingPicker` 中 `_drawPicks.map((p) => _pickDot(...))`（约 401 行）
   - 照片侧：`_refPicks`（橙色，约 503 行）与 `_photoPicks`（红色，约 504 行）
   - `_pickDot` 调用处需要能拿到 `box`（LayoutBuilder 的尺寸）与图片尺寸（`_imageSize` / `_photoSize`）

**验证**：点选任意位置，标记应精确落在点击处（原图放大/缩小时都正确）。

---

## 🟡 P1-1：图纸尺寸手填降级（图纸未校准时功能瘫痪）

**问题**：`_addItem`（约 156~195 行）要求 `_mapper != null` 才能加项；图纸未校准时整个量尺功能不可用。设计师需要"对照图纸正确尺寸"的最低保障是手填。

**修改**（`lib/features/measure/measure_page.dart`）：
1. 名称输入行旁（约 309~321 行）增加"图纸尺寸"输入框 `_drawingMmCtl`
2. 逻辑改为：
   - 图纸已校准：默认用两点量得值（可编辑覆盖），输入框预填量得值
   - 图纸未校准：允许手填图纸尺寸后添加（跳过 `_drawPicks` 校验，跳过 `drawingDistanceMm`）
3. 判定/清单/持久化不变

**验证**：删掉某图纸校准后，仍能手填图纸尺寸完成校对。

---

## 🟡 P1-2：默认容差过严（5mm/2% → 建议 15mm/2%）+ 快捷档位

**问题**：照片标定法精度约 ±1~3%；3000mm 墙配 5mm 容差（0.17%）几乎必判超差。

**修改**：
1. `lib/data/models.dart` — `MeasureSession` 默认值 `tolMm: 5, tolPct: 2`（约 579~580 行）→ 改为 `tolMm: 15, tolPct: 2`
2. `lib/features/measure/measure_page.dart` — 初始控制器文本（约 54~55 行 `'5'`/`'2'`）→ `'15'`/`'2'`；`_loadSession` 默认（约 103~104 行）同步
3. 可选（有余力）：容差行加三档快捷选择 `ChoiceChip`：严格 5/1、标准 10/1.5、宽松 15/2

**验证**：新建会话默认显示 ±15mm / 2%。

---

## 🟡 P1-3：照片上显示参考线 + 像素跨度

**问题**：标定只有两个橙点，无法确认参考物两端位置与跨度。

**修改**（`lib/features/measure/measure_page.dart` `_photoPanel` 约 486~528 行）：
- 照片 Stack 加 `CustomPaint` 覆盖层（参考 `path_metrics.dart` 的绘制风格）：
  - 参考物两点间画橙色实线，中点标注 `跨度 px`（用 `imageToDisplay` 换算显示坐标）
  - 被测两点间画红色实线，中点标注换算 mm 值（已有文字显示，可保留）
- 线宽 2~3，端点沿用现有圆点标记

**验证**：标定后照片上可见橙色参考线；量测后可见红色线+数值。

---

## 🟡 P1-4：增加"重新标定"入口

**问题**：标定错了无法重置（`copyWith` 已有 `clearPhotoCalib` 参数但 UI 未用）。

**修改**（`lib/features/measure/measure_page.dart`）：
- 标定成功后的 Chip 旁（约 447~455 行）加 `TextButton('清除标定')`：
  ```dart
  setState(() {
    _session = _session!.copyWith(clearPhotoCalib: true);
    _refPicks.clear();
    _photoPicks.clear();
  });
  _persist();
  ```
- 清除后状态回到"未标定"，点照片进入参考物标定模式

**验证**：清除后 mm/px Chip 消失，重新标定数值更新。

---

## 🟡 P1-5：云端同步端口/地址核对

**问题**：`lib/data/repository/remote_repository.dart`（约 14~17 行）默认 host `http://120.24.240.129:3000`，但 `server/measure_server.py` 默认端口 **8820**（`MEASURE_PORT`），Express 视觉服务才是 3000。默认地址打到的不是量尺服务。

**修改**：
1. 确认部署拓扑：若 8820 已被反代/映射到 :3000，则只改注释说明；否则把默认值改为实际可达的 `http://<host>:8820`（或与部署方确认统一入口）
2. `MEASURE_HOST` 的 `--dart-define` 用法已在注释中，保持
3. 同步检查 `_start_server.py` / 部署脚本是否同时拉起 `measure_server.py`

**验证**：prod 环境保存后 GET 能取回会话（本地保存不受影响）。

---

## 🟢 P2-1：测试脚本路径硬编码

**修改**：`_test_measure.ps1`（第 1 行）`c:\sp\server\measure_server.py` → 相对路径：
```powershell
$server = Start-Process python -ArgumentList "$PSScriptRoot\server\measure_server.py",'8820' -WindowStyle Hidden -PassThru
```

## 🟢 P2-2：_onDrawTap 回退分支坐标体系统一

**修改**：`_onDrawTap`（约 408~423 行）`_imageSize == null` 时目前把显示坐标原样存入 `_drawPicks`，与正常分支（整图像素）混用。改为：`_imageSize == null` 时提示"图纸未加载"并 return，不存点。

## 🟢 P2-3：提示文案按状态显示

**修改**：`_photoPanel` 底部提示（约 530 行）改为状态相关：
- 未标定：`请在照片上点选参考物两端（橙），再点击「标定」`
- 已标定：`请在照片上点选被测两点（红）`

---

## ✅ 完成验收清单

- [ ] `flutter analyze` 无新增 error
- [ ] 竖线参考物标定数值合理（P0-1）
- [ ] 标记与点击位置重合（P0-2）
- [ ] 图纸未校准可手填完成校对（P1-1）
- [ ] 默认容差 ±15mm/2%（P1-2）
- [ ] 照片可见参考线与量测线（P1-3）
- [ ] 可清除标定并重新标定（P1-4）
- [ ] Web 端（flutter build web + serve_web.ps1）全流程可演示
- [ ] 录 90 秒演示视频（拍墙→标定→量距→对比→判定）
