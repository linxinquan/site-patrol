# DXF → 自动校准种子生成

## 最新状态（2026-08-26）

- ✅ **ODA File Converter 已在本机安装**：`C:\Program Files\ODA\ODAFileConverter 27.1.0\OdaFileConverter.exe`
- ✅ **D01 / D03 已成功转为 DXF**：`server/dwg_cache/D01.dxf`、`D03_D04.dxf`
- ✅ **D01 / D03 内置估算种子已写入** `drawing_viewer_page.dart` 的 `_builtinCalibrationFor`，
  按 1:150 剖面比例推算（量级正确），App 打开即近似自动校准。
- ⏳ **B01 源文件损坏**：当前 `server/dwg_cache/B01.dwg` 实际是 429 字节的 XML 错误页（非真实图纸），
  转换失败（`B01.dxf.err`）。**需你重新提供真实 B01.dwg**，然后我会自动转 DXF 并补种子。
- ⏳ **D01 / D03 的 c/f 偏移需精修**：因天正模型空间大坐标 + 底图为局部渲染，无法自动锁定偏移。
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
