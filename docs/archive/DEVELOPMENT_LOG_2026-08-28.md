# 开发日志 2026-08-28（周五）

## 一、今日完成

### 1. AR 量尺 LiDAR 无法调用（两个根因，已彻底修复）
- **问题**：进入 AR 量尺页面一直停在"正在检测 LiDAR 支持…"占位，LiDAR 调用不上。上一版（70e436c）还好，93ecf4f 之后失效。
- **根因1（死锁）**：`UiKitView` 被 `if(_supported)` 包裹，而 `_supported` 初始 `false` → view 永不创建 → 原生 channel 永不注册 → `isSupported()` 永远查不到 → 永远卡占位图。上一版能工作是因为 `UiKitView` 无条件渲染。
- **根因2（channel 名错配）**：Dart 端写死 `ar_measure_0`，Swift 端用引擎分配的 platform view id 拼接 `ar_measure_<id>`，仅碰巧首个 view id=0 才匹配。
- **修复**：
  - `ar_measure_page.dart`：`UiKitView` 恢复无条件渲染；`_onViewCreated` 恢复主动查 `isSupported()`。
  - `ArMeasureView.swift` + `ar_measure_service.dart`：channel 统一固定名 `ar_measure_channel`，不再拼接 viewId。
- **验证**：✅ 真机（iPhone Pro）测试通过，AR 量尺可正常调用 LiDAR 测距。

### 2. 远程同步 + Web 重建
- `git fetch` + `git checkout main` + `git pull origin main`（更新到 237c0b9，快进 2 提交）。
- `flutter clean` 后 `flutter build web --release` 重建，`main.dart.js` 3.6MB，无构建报错。
- `flutter analyze` 无新增 error/warning。
- 无缓存预览服务器 `serve_web.py` 启动在 `:8765`（本机 `127.0.0.1`、局域网 `172.25.8.76`）。

## 二、对外汇报

### 本周（8/26-8/28）三个增量
1. **AR 量尺**：上周基础版 + 本周死锁修复，iPhone Pro 实测可恢复使用。
2. **语音录入**：拍照页"问题描述"支持设备离线语音（中文）。
3. **AI 审图调研**：帮图AI / 万翼AI / 广联达三家价格档位调研完成，结论——**不自己开发**，先小范围试点帮图AI（按张1元/图框，注册即用）。

### 当前卡点
- 图纸校准（B01/D0x）在真实底图上的自动匹配精度尚未收敛，预计还需 1–2 周。

### 下周计划（保守）
先把 AR 量尺 + 语音录入这条主链路跑稳，再回头推校准精修。不开新方向。

## 三、本次提交

- `98aa118` `fix(ar): 修复 AR 量尺页面 UiKitView 死锁，LiDAR 通道无法建立`（首次修复，未完全解决）
- `b64d14c` `fix(ar): 彻底修复 AR 量尺 LiDAR 无法调用（UiKitView 死锁 + channel 名错配）`
  - `ios/Runner/ArMeasureView.swift`：channel 固定名 `ar_measure_channel`
  - `lib/core/ar/ar_measure_service.dart`：channel 固定名
  - `lib/features/measure/ar_measure_page.dart`：UiKitView 无条件渲染 + 主动查支持
  - **真机验证通过** ✅