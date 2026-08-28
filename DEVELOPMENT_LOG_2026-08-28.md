# 开发日志 2026-08-28（周五）

## 一、今日完成

### 1. AR 量尺 LiDAR 死锁修复（lib/features/measure/ar_measure_page.dart）
- **问题**：进入 AR 量尺页面一直停在"正在检测 LiDAR 支持…"占位，LiDAR 调用不上。上一版（93ecf4f）还好，回退到最新 main 后失效。
- **根因**：UiKitView 渲染条件与设备支持查询形成死锁：
  - `_supported` 默认为 `false`
  - `build()` 见 `_supported=false` → 走占位图，**UiKitView 不创建**
  - UiKitView 不创建 → `onPlatformViewCreated` 回调不触发 → `_onViewCreated` 不执行 → `_svc.isSupported()` 永远查不到 → `_supported` 永远 `false`
- **修复**：进入页面后**无条件先渲染** UiKitView，channel 注册后立刻设 `_supported=true` 放行；再异步查 `isSupported()`；非 LiDAR 设备回退占位。
  ```dart
  Future<void> _onViewCreated(int id) async {
    _supported = true;
    if (mounted) setState(() {});
    final supported = await _svc.isSupported();
    if (!mounted) return;
    if (!supported) {
      _supported = false;
      setState(() {});
      return;
    }
    await _svc.startSession();
  }
  ```
- **iOS 端（ArMeasureView.swift）无需改动**：原权限检查、深度采样、raycast 逻辑均齐全。

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

- `fix(ar): 修复 AR 量尺页面 UiKitView 死锁，LiDAR 通道无法建立`
  - `lib/features/measure/ar_measure_page.dart` `_onViewCreated` 重写