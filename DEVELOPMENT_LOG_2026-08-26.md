# 开发日志 2026-08-26（周三）

## 一、今日更新

### 1. 图纸校准：轴网交点自动套图（核心）
- 安装 **ODA File Converter**（`C:\Program Files\ODA\ODAFileConverter 27.1.0\`），固化 `server/dwg_to_dxf.py` 批量转换
- 用户提供天正 T3 DXF（G 盘），提取轴网交点 JSON：
  - B01：174 点（块内 `N-GRID建筑轴线` 层，递归展开块变换）
  - D01：63 点、D03：41 点、D04：37 点（`A-AXIS-GRID` 层，D03/D04 按 Y 拆分）
- 新增 `lib/core/cad/axis_auto_calibration.dart`：
  - `detectAxisLines` 识别底图轴线 → 交点
  - `matchAxisGridDeterministic`：利用轴网行列结构一维投票匹配（间距比值求 scale，差值投票求平移）
  - RANSAC 回退 + `fitAffineRobust` 最小二乘仿射拟合
- **修复重要 bug**：`fitAffineLeastSquares` 的 Y 维 d/e 系数顺序与 `CadCoordMapper.screenToWorld` 语义不符（含旋转的完整仿射会出错），已交换修正，手动多点校准与自动套图均受益
- 6 项算法测试全部通过（理想/噪声/无对应/最小二乘 sanity）

### 2. 默认校准 + 不提示"未校准"
- 修复 `seedDefaultCalibrations` 只写 localStorage 不入内存 map 的 bug：B05 种子写入后 AR量尺等页面读内存 map 仍为 null 导致"未校准"
- 扩展为所有内置图纸（B05/D01/D03/D04/B01）启动期写入 store + 内存 map
- 提取 `builtinCalibrationFor` 为公共函数（`providers.dart`），`drawing_viewer_page` 委托共用

### 3. 拍照调用相机 BUG 修复
- **问题**：拍照记录页"开始拍照"按钮，选点后点击无法调相机
- **根因**：`_confirmPointAndCapture` 检查 `_anchorLabel == '待选点'`，用户选点但未吸附到最近锚点（距离 >0.12）时 `_anchorLabel` 仍是"待选点"，点按钮被"请先选部位"拦截
- **修复**：选点后一步直接调用相机（`_doCapture`），不再卡中间步骤

### 4. AR量尺 Web 端相机可用
- **问题**：Web/非 iOS 平台 AR量尺只显示"仅 iPhone Pro"文字，无法调相机
- **修复**：退化为"拍照+参考物比例估算"简易量尺（`_buildWebFallback`），可调相机/相册 + 录入参考物实际尺寸

## 二、遗留问题（待办）

### 1. B01 校准精度不足（关键）
- B01 组合平面图轴网自动匹配在真实底图上**不可靠**：
  - 轴网线被打断（横线在底图上检测不到足够的强线）
  - 底图 = A0 图纸渲染（1189×841mm，1:250），但轴网 X/Y 比例与底图显示区域不匹配
  - 竖线匹配较可靠：`a=24.88, c=291881.8`；Y 方向（f≈1300500）精度有限
- **G 盘（T3 DXF 源）当前无法访问**（`G:\` 系统找不到路径，可能是网络盘/外接盘断开），需恢复后继续
- 已确认：**B01 块内有 2583 个 DIMENSION 尺寸标注**（含精确 defpoint CAD 坐标），G 盘恢复后可做更精确的尺寸标注自动校准

### 2. D01/D03/D04 校准为估算初值
- 轴网自动套图在合成数据上通过，但**未在真实底图上验证**（`detectAxisLines` 对真实 CAD 渲染底图检测线数不足）
- 当前种子为 1:150 + A2 图幅估算初值（量级正确，偏移/比例需精修）

### 3. 预览服务器 / 构建
- 构建产物已同步到 `web/`，预览 `http://127.0.0.1:8080/`
- 未提交的临时 bat 文件已清理

## 三、积分/额度消耗
- 安装 ODA File Converter、PyMuPDF、matplotlib（均为本地工具，无 API 额度）
- 所有图纸离线转换，运行时零额度
