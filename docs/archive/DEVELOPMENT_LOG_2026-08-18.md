# 开发日志 2026-08-18（坐标换算根因定位 + 修复 + Android 构建验证）

> 本文档为上下文记录，供后续（换电脑/新会话）继续开发使用。
> 项目：工地巡检智能化管理（腾讯大铲湾 DY04 / 7 栋 B05 图纸验证）
> 续接自：`DEVELOPMENT_LOG_2026-08-17.md`

---

## 一、今日完成

### ✅ 首要：Flutter 端打点坐标不准 —— 根因定位并修复（已单元测试验证）

**排查结论（重要）**：

1. **★ 真正的 root cause：仿射系数 Y 位置语义不一致**（与 8-17 浏览器端字段错位 bug 同源）：
   - 浏览器端 `imagePxToWorld`：`X = a*px + c；Y = MAP.d * py + MAP.f`（**Y 系数在 d，乘 py**）。
   - Flutter 端原 `screenToWorld`：`X = a*px + b*py + c；Y = d*px + e*py + f`（**d 乘 px**）。
   - 用户从浏览器「复制参数」得到 `{a, b:0, c, d, e:0, f}`，Flutter 导入后把 `d` 错误用于 px
     → **Y 坐标系统性错误**（实测偏差 300+mm）。
   - **修复**：`screenToWorld` 仿射模式改为 `Y = d*py + e*px + f`（b=e=0 时 = `d*py + f`，
     与浏览器 `imagePxToWorld` 完全一致）；`worldToScreen` 逆变换（`py=(wy-f)/d`）本就一致。
   - 新增 `test/cad_coord_test.dart`（6 用例）验证：校准点精确、比例尺正确、正逆变换互逆、
     `fromCalibrationMap` 解析浏览器 JSON —— **全部通过**。

2. **次要：`InteractiveViewer` 坐标行为**：
   - `InteractiveViewer` 内部用 `Transform`（默认 `transformHitTests=true`）包裹 child，
     因此 child 内 `GestureDetector` 的 `localPosition` **已被自动反变换**为「未缩放局部坐标」。
   - 17 日疑点 (a) 的修正方向曾做反：`localToViewPixel` 再用矩阵二次反算 = 双重反变换（错误）。
   - **正确算法**：localPos 已是盒子坐标，减去图片居中偏移 → 归一化 → 整图像素 → `screenToWorld`，
     与浏览器 `screenToImagePx` 数学等价。

3. **内置 B05 校准系数是「演示值」，不能用于精度验证**：
   - `applyBuiltinB05` 用 `a=1/3.022, d=-1/3.022, c=-w/2*a, f=h/2*a`，
     隐含假设「图片中心 = CAD 原点 (0,0)」。
   - 真实 CAD 原点不在图中心 → 除中心点外**全图系统偏移**。
   - **必须**用浏览器端「复制参数」导出的真实校准（含单点偏移修正 c/f）才准。
   - 待办：内置 B05 应改为读取浏览器端上次保存的参数（见下方待办 4）。

**修改**：
- `lib/core/utils/cad_coord.dart`：`screenToWorld` 仿射分支 Y 系数位置修正（d 乘 py）。
- `lib/features/projects/drawing_viewer_page.dart`：
  - `_pickAnnotation` 移除 `localToViewPixel` 二次反变换，改为
    「盒子坐标 - 居中偏移 → 归一化 → 整图像素 → screenToWorld」；
  - 打点/锚定 `GestureDetector` 放回盒子层（覆盖整盒），注释说明 transformHitTests 行为。
- `test/cad_coord_test.dart`（新增）：坐标换算单元测试。

### ✅ 顺手修复：首页 `_QuickCard` 溢出 12px
- `lib/features/home/home_page.dart`：卡片加固定 `height: 84`，解决 `RenderFlex overflowed by 12px`。

### ✅ Android 构建验证（进行中）
- `flutter build apk --debug` 首次构建需下载 Android SDK Platform 34/35 组件。
- 日志：`C:\temp\_apk.log`（后台运行）。

---

## 二、下午续：图钉→拍照联动 + 坐标诊断增强

### ✅ 图钉 → 拍照记录（新功能）
- `CaptureArgs` 增加 `drawingKey / drawPointWorldX / drawPointWorldY`（`lib/data/models.dart`）。
- 图钉详情弹窗新增「拍照记录」按钮 → `context.push('/capture')` 带上图纸坐标。
- 打点 SnackBar 右侧新增「拍照」快捷按钮。
- `CapturePage` 生成缺陷工单时自动继承图纸坐标（`drawingKey/worldX/worldY`），
  实现「图纸打点 → 拍照 → 缺陷带坐标」闭环。

### ✅ 坐标诊断增强（应对"打点后仍不准"）
- 打点时 `debugPrint('[CAD PICK] ...')` 输出完整换算链路：
  `local → box → disp → origin → img(px,py) → world → a/d/c/f 系数`。
- 打点 SnackBar 显示校准参数摘要（a/d/c/f），让用户一眼看出用的是内置演示值还是真实参数。
- 图钉详情弹窗新增「整图像素」「校准参数」行，便于与浏览器端对照。

### ⚠️ 坐标精度仍未实测通过
- 用户截图反馈：打点坐标 (-681.5, -332.5) 仍不准（疑似用了内置B05演示值，或真实比例非 1/3.022）。
- 已加诊断输出，需用户打点后反馈 SnackBar/Console 的 a/d/c/f 参数才能最终定位。

---

## 三、待办（承接 8-17 日志）

1. [ ] **验证坐标修复**：粘贴浏览器端真实校准参数 → 打点对比 CAD `ID` 坐标（预期 <2mm，需实测）。
2. [ ] 「应用内置B05」改为读取浏览器端上次保存的参数（当前硬编码中心映射不可用于精度验证）。
3. [x] 图钉视觉优化（大头针样式 + 底部尖端对准 + 白描边数字）。
4. [ ] Android 构建完成后真机/平板验证（Android/iOS）。
5. [ ] 多图纸支持：7 栋其他楼层 PDF → PNG 底图批量生成。

---

## 三、关键技术备忘

- **Flutter 坐标换算正确姿势**（InteractiveViewer + 手势打点）：
  ```
  InteractiveViewer.transformHitTests = true（默认）
  → GestureDetector.localPosition 已是未缩放局部坐标（勿再乘变换矩阵）
  → 盒子坐标 - 居中偏移 = 图片显示坐标
  → /dispW、/dispH = 归一化比例
  → × imgW、× imgH = 整图像素坐标
  → CadCoordMapper.screenToWorld(px, py) = 真实图纸坐标
  ```
- **浏览器端校准参数格式**：`{a,b,c,d,e,f,imgW,imgH}`，`imagePxToWorld` 用 `X=a*px+c, Y=d*py+f`。
  单点校准：`scale=imgW/1489`，Y 系数存 `MAP.d`（8-17 已修字段错位 bug）。
- **内置 B05 ≠ 真实校准**：仅为离线演示，中心对齐；精度验证请用浏览器「复制参数」。
