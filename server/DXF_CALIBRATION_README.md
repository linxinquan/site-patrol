# DXF → 自动校准种子生成

## 目的
为 B01/D01/D03（以及任意新图纸）生成 **<2mm 精度的内置校准种子**，让 App 打开图纸即自动校准，完全脱离浏览器端手动校准。

## 前置
已有 `server/dwg_cache/` 下：
- `D01.dwg`（已下载，14MB）
- `D03_D04.dwg`（已下载，2.7MB）

**B01 的 DWG 源在 COS 上不存在（404），需你另行提供**（或从本地资料盘拷贝）。

## 你需要做的（在有 CAD 的机器上）

### 1. 安装转换工具（任选其一）
- **ODA File Converter**（免费，推荐）：
  https://www.opendesign.com/guestfiles/oda_file_converter
- 或 GStarCAD / AutoCAD：打开 DWG 后 `另存为` → 选择 `*.dxf`（ASCII 2013/2018 版）。

### 2. 转换命令（ODA File Converter 命令行）
```bat
"<安装路径>\OdaFileConverter.exe" <输入dwg目录> <输出dxf目录> ACAD2018 DXF 0 1
```
例：
```bat
"C:\Program Files\ODA\ODAFileConverter\OdaFileConverter.exe" ^
  "F:\建筑验收工具\site-patrol\server\dwg_cache" ^
  "F:\建筑验收工具\site-patrol\server\dwg_cache" ^
  ACAD2018 DXF 0 1
```

### 3. 放置转换好的 DXF 到 `server/dwg_cache/`，命名为：
| 图纸 | 期望文件 |
|---|---|
| B01 | `B01.dxf`（需你补源 DWG） |
| D01 | `D01.dxf` |
| D03 | `D03.dxf`（从 D03_D04.dwg 中取 D03） |

## 生成校准（我自动完成）
DWF 到位后运行：
```bat
cd /d F:\建筑验收工具\site-patrol\server
python derive_calib_from_dxf.py dwg_cache\D01.dxf 2400 1133
python derive_calib_from_dxf.py dwg_cache\D03.dxf 2400 1698
python derive_calib_from_dxf.py dwg_cache\B01.dxf 4500 3186
```
脚本会输出：
- 布局页面尺寸 / 图纸空间 extents（mm）
- 视口内「模型坐标 → 图纸空间」映射
- 建议校准系数（`a`/`d`/`c`/`f`）

## 精度说明
- `a`/`d`（mm/px 比例）：由布局 extents ÷ 底图像素直接得到，**可靠**。
- `c`/`f`（平移偏移）：需**至少一个真实坐标点**校正。脚本会输出中心对齐估算值；
  正式内置种子前，我会用"图上多点校准"或你提供的任一点坐标做最终验证。
