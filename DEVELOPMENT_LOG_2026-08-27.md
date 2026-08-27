# 开发日志 2026-08-27（周四）

## 一、今日更新

### 1. detectAxisLines 算法重构 + 关键 bug 修复
**核心问题**（真实 B01/D01/D03/D04 底图欠检测根因）：
- `lib/core/cad/axis_calibration.dart:detectAxisLines` 旧版用「暗像素占比 > coverageMin」判据。
- **隐藏 bug 1：min-pooling 写反了**。代码 `if (gray > darkest) darkest = gray;` 实际是 max-pooling（取最亮 = 背景），意图与变量名相反。Python 脚本里写的是正确的 `block.min()`，移植到 Dart 时被反。
- **隐藏 bug 2：`Int8List` 范围 -128..127，`fillRange(255)` 越界被静默截断**（实际写 0）。未 min-pooling 时整张 pooled 全 0，所有行/列都被判为"暗"（虽然这反而让旧 max-pooling 版本在白底图上能凑出一些信号）。
- **设计问题**：「暗像素占比」对 min-pooling 膨胀的噪声（墙线/梁线/文字/尺寸碎片聚合成长段）鲁棒性差。

**修复与改进**（Dart 端）：
- min-pooling 改为真正的 `if (gray < darkest) darkest = gray;`（取块内最暗 = 黑线）
- `Int8List` → `Uint8List`（范围 0..255，可存 255）
- 显式 `g.fillRange(0, g.length, 255)` 初始化为白
- 判据改为「最长连续暗段」+ 容缺（≤`maxGap` 像素亮色小缺口视为连续）
- 一维聚类（`clusterTol` 像素内合并）→ 质心为轴线位置
- 新参数：`minRatio`（替代 `coverageMin`）、`maxGap`（4）、`clusterTol`（8）
- 默认参数保守（minRatio=0.5），保留对宽线/细线都稳定
- 调用方（`_autoCalibrateByAxisGrid` 与 `_detectAxisLinesAsync`）同步更新参数名

**验证**（真实底图）：
- B01（4500x3186 组合平面图）：旧 v1 = 4 竖 + 4 横；新 v2 = 17 竖 + 8 横（Python 模拟）
- D01（2400x1133 剖面图）：v2 = 17 竖 + 5 横，能命中底部 7 个轴号位置
- D03/D04：v2 输出 13-20 横 + 16-23 竖

### 2. 测试覆盖增强
- 新增 2 个合成数据测试（`test/axis_auto_calibration_test.dart`）：
  - 「3 横 + 4 竖长线带 1-2px 缺口 + 30 段噪声」：验证 v2 能稳定识别长线、对噪声稳健、容缺有效
  - 「纯噪声：应返回空线集」：验证 v2 不误检
- 全部 8 个测试通过（含原有 6 个 matchAxisIntersections / fitAffineLeastSquares 回归用例）

### 3. Web 重建 + 预览
- `flutter build web --no-tree-shake-icons` 成功
- 静态服务器 `http://127.0.0.1:8080/` 运行中
- 浏览器预览已打开，可验证 D01/D03/D04/B01 真实底图的轴线检测效果

## 二、未完成 / 遗留事项

### 1. B01 Y 方向精度（卡 G 盘）
- **原因**：本地 `B01.dxf` 是 ODA 直转的，**天正 TAuthor 自定义对象全部以 `ACAD_PROXY_OBJECT` 形式存在**（用 ezdxf 检查：模型空间只剩 7 HATCH + 8 LWPOLYLINE + 1 INSERT，没有 DIMENSION）。原 G 盘 T3 导出 DXF（2583 个 DIMENSION defpoint）目前不可访问。
- **离线进展**：改进 detectAxisLines 后，真实 B01 底图 v2 算法检出 17 竖 + 8 横（v1 是 4+4），但 B01 轴网 JSON 是两块区域（地下一层 + 另一区），底图与轴网比例不严格匹配，matchAxisGridDeterministic 难以成功。
- **下一步**：等 G 盘恢复后用 T3 DXF + DIMENSION 精校，可彻底解决 B01 精度问题。

### 2. D01/D03/D04 初值未在真实底图验证
- 已知问题：D03/D04 轴网 JSON 的 CAD x/y 范围与底图像素比例不均匀（s_x=33.9 vs s_y=9.4-11.6 mm/px，差 3x），说明轴网 JSON 是从更大的建筑俯视/剖面提取，与底图渲染范围不对应。
- matchAxisGridDeterministic 用 1D 投票求 scale，理论上能容忍非均匀，但需要更多数据点（v2 算法已提升召回，但本图数据本身不匹配）。
- **当前方案**：保留估算初值（a=37.125）+ demo 兜底，保证 app 打开不报错。

### 3. G 盘（T3 DXF 源）当前仍不可访问
- 启动期 G: 路径检查：`G_DRIVE_MISSING`
- 需用户恢复外接盘/网络盘后继续推进

## 三、技术要点

### Dart 类型陷阱
- `Int8List` 范围 -128..127，写入 255 越界被静默截断。涉及灰度 0..255 的场景用 `Uint8List`。
- `import 'dart:ui' as ui;` 后 `Offset` 必须写 `ui.Offset`，否则 "Method not found: 'Offset'"。

### 端行尾差异
- 项目 Dart 文件用 CRLF（`\r\n`），用 `replace_in_file` 传 LF old_str 会匹配失败。
- 已用 Python 脚本做 CRLF 安全的精确字符串替换。

## 四、积分/额度消耗
- 全部本地工具改进（无 API 额度）
