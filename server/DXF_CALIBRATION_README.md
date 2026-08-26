# DXF → 自动校准种子生成

## 轴网交点自动套图校准（建筑工程标准做法）

已实现 `lib/core/cad/axis_auto_calibration.dart`（算法 + 测试全部通过）：

**原理**：底图（PDF 渲染）上的轴线交点与 CAD 中的轴网交点是**同一几何网格**，
分处像素坐标系与毫米坐标系。算法自动做：
1. 底图侧：`detectAxisLines` 识别横/竖轴线 → `axisIntersections` 求交点（像素）
2. CAD 侧：从 DXF 轴网层提取交点（毫米）→ 打包 JSON 随 App 加载
3. `matchAxisGridDeterministic`：利用轴网**行列结构**一维投票匹配（X/Y 方向独立
   求 scale 与平移），组合行列对应 → 交点对
4. `fitAffineRobust` 最小二乘仿射拟合 → 全自动 <1mm 校准

同时修复了一个重要 bug：`fitAffineLeastSquares` 的 Y 维 d/e 系数顺序与
`CadCoordMapper.screenToWorld` 语义不符（无旋转时无影响，含旋转的完整仿射
拟合会出错）——现已交换修正，手动多点校准与自动套图均受益。

**数据需求**：CAD 侧轴网交点须从**含完整轴网的 DXF** 提取。天正 DWG 经 ODA
直转会丢失天正自定义轴网对象（实测 D01 只剩竖线、B01 几何全在块内）。
→ **需在装有天正的机器上用「文件布图 → 整图导出 → T3（2013）」** 导出
`B01_T3.dxf`（组合平面轴网最完整），我再用 `extract_axis_intersections.py`
提取交点 JSON 打包进 App，即可全自动套图校准。

`extract_axis_intersections.py` 用法：
```bat
cd /d F:\建筑验收工具\site-patrol\server
python extract_axis_intersections.py server\dwg_cache\B01_T3.dxf server\axis_data\dy04_7_B01.json
```

## 最新状态（2026-08-26）

- ✅ **ODA File Converter 已在本机安装**：`C:\Program Files\ODA\ODAFileConverter 27.1.0\OdaFileConverter.exe`
- ✅ **D01 / D03 / B01 已成功转为 DXF**：`server/dwg_cache/D01.dxf`、`D03_D04.dxf`、`B01.dxf`
- ✅ **三张图内置估算种子已写入** `drawing_viewer_page.dart` 的 `_builtinCalibrationFor`：
  - B05：真实视口校准（<2mm，已验证）
  - D01 / D03：剖面图 1:150 估算初值，App 打开即近似自动校准
  - B01：地下一层顶板组合平面图，天正组合平面（模型空间跨度异常 ~1.5e8mm），按 1:100+A1 估算初值
- ⏳ **三张图的最终 c/f 偏移需精修**：天正模型空间大坐标 + 底图为局部渲染，无法自动锁定偏移。
  **请在 App 内用「图上多点校准」录入 2~3 个已知坐标点，即可收敛到 <2mm 并持久化**（内置种子作为初始值）。

## 自动转换（已固化脚本）

```bat
cd /d F:\建筑验收工具\site-patrol\server
python dwg_to_dxf.py          # 转换 dwg_cache 下所有 .dwg
python dwg_to_dxf.py B01.dwg  # 仅转换指定文件（B01 真实源到位后执行）
```

转换成功会生成同名 `.dxf`；失败会生成 `<name>.dxf.err` 占位，可据此判断源文件是否有效。

## D01 / D03 已探测到的关键信息
- 标注比例：**1:150**（剖面图）
- D01 轴网层范围（模型空间）：X[-101940, -85331]，Y[875680, 896200]
- D03 轴网层（AXIS）范围：   X[-41904, 39546]，  Y[685215, 890352]
- 注意：天正图模型空间含多栋/参照，整体 extents 跨度极大，**不能**直接用整体范围推算 a/d，
  故采用「1:150 + 标准图幅」估算初值，最终由 App 多点校准精修。

## 老流程（参考）
原 `derive_calib_from_dxf.py` 基于"布局视口"推算，适用于有 Paperspace 视口的图纸（如 B05）。
对天正模型空间图不适用，已改用上述估算 + App 交互校准方案。
