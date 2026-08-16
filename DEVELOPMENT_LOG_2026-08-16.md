# 开发日志 2026-08-16（CAD 查看器截图模式 + 图层白名单方案）

> 本文档为上下文记录，供后续（换电脑/新会话）继续开发使用。
> 生成时间：2026-08-16（周六）
> 项目：工地巡检智能化管理（腾讯大铲湾 DY04 / 7 栋 B05 图纸验证）

---

## 一、今日已完成

### 1. 图层白名单/冻结图层方案（矢量 OCF 方向，已放弃为主方案）
- 安装 **ODA File Converter 27.1**（`C:\Program Files\ODA\ODAFileConverter 27.1.0\`，免费工具，DWG→DXF）
- 将 `F:\建筑验收工具\大铲湾DY04_资料\第一轮测试CAD\01_平面图\建施_AW-7-B05_V1.0_地下室夹层组合平面图_t3.dwg` 转成 DXF（280MB，因天正自定义对象 `TCH_PIPEWIRE` 转换时实体段截断，但 TABLES 段完整）
- 用 ezdxf.recover 读取截断 DXF，提取出**全部 1847 个图层的真实 isoff/isfrozen 状态**（297 冻结 + 13 关闭 = 310 隐藏层）
- 结果输出到 `server/cad_meta/dy04_7_B05_dxf_layers.json`
- 把 310 个真实图层名写入 `web/cad_viewer.html` 的 `FROZEN_LAYERS`，并加**归一化匹配**（全角/半角、去空格）
- **结论**：即使精确关闭 310 层，模型空间仍"炸"（大量 hatch/标注层未冻结），布局空间仍有紫色填充残留。**此方案被否，改用截图模式。**

### 2. PDF 整理（已完成）
- 从 `F:\设计院工作\SZAD\2020-腾讯大铲湾DY04\14-总院归档文件\09-施工图\01-建筑\7栋\PDF` 复制 **167 个 PDF** 到 `F:\建筑验收工具\大铲湾DY04_资料\第一轮测试CAD\`，按编号分类到 01~10 目录 + 目录与封面
- 按"DWG 编号匹配"删除无对应 DWG 的 PDF（06 楼梯详图删了 F17、F28 两张）

### 3. 截图嵌入 + 矢量定位混合方案（**当前主方案**）
- 新建 `web/cad_viewer_hybrid.html`（截图模式查看器）
- 底图：`web/dy04_7_B05_paper_hybrid.png`（4500×2551，B05 PDF 转 PNG，已确认效果=AutoCAD 布局空间，干净无炸线）
- 功能：
  - 单点 / 两点 / 预设三种坐标校准
  - 校准参数 localStorage 持久化（key 当前为 `cad_calib_v3_`）
  - 捕捉最近点（canvas Harris 角点检测）
  - 缩放：顶栏 +/−/↻ + Ctrl+滚轮
  - 定位结果 postMessage 回 Flutter（`{type:'cad-pick', worldX, worldY, text}`）
- UI：Ins 风扁平化（白底、圆角、segmented control），顶栏 60px、标题 16px、按钮 14px（已调至用户认可的大小）

---

## 二、未完成/待解决（明天继续）

### ⚠️ 核心问题：单点校准 Y 轴偏差大（X 基本准）
- **现象**：校准点填 `X=-295.2308, Y=95.0095`（AutoCAD ID 查得），应用后点同一特征点，返回 `X≈-258.7, Y≈851.7`，**Y 偏差 ~750mm**，X 误差 ~2mm
- **已确认的事实**：
  - PDF 物理页 = **1489.07 × 843.84 mm**（已实测）
  - 底图 PNG = 4500 × 2551 px，宽高比 1.764 = PDF 物理比例，**图片未被拉伸**
  - `scale = 4500/1489 = 3.022 px/mm`，算法 `a=1/scale, c=-imgW/2*a, e=-1/scale, f=imgH/2/scale` 数学上正确
  - X 准 Y 错 → 疑似 Y 方向某处乘了约 1.88 或 5 倍系数
- **待验证/候选原因**：
  1. `screenToImagePx` 用 `imgEl.getBoundingClientRect()` 换算，可能因 `#viewer` 的 flex + `align-self:center` 或浏览器 zoom 导致 **rect.height ≠ 真实显示高度**（Y 像素→图像像素放大）
  2. **建议优先做**：在定位点击时用 `debugPoint()`（已内置，输出像素坐标+算法坐标）打印 PY 像素值，和截图里实际红点位置对比，确认换算是否准确
  3. 若确认是 rect 问题 → `screenToImagePx` 改用 **CSS 尺寸比例**或**SVG overlay 的坐标**（SVG 与图片等大）
- **下一个调试方向（省积分，不扣浩辰次数）**：
  ```
  F12 → Console:
  debugPoint(px, py)  // 手动输入像素验证算法
  ```
  或临时在 `svg.addEventListener('click')` 里 console.log 原始 `e.clientX/clientY`、`svg.getBoundingClientRect()`、`imgEl.getBoundingClientRect()` 三者对比

### 待办列表（按优先级）
1. [ ] **修复单点校准 Y 偏差**（先用 debugPoint 定位 rect 问题，再修 screenToImagePx）
2. [ ] 校验修复后重新做一次完整校准，确认 X、Y 均 < 1mm 误差
3. [ ] 将校准参数从 localStorage 升级为"可导出/导入"（方便多设备/工地无 CAD 环境），或接入 Flutter 端保存
4. [ ] Flutter 端接入 `cad_viewer_hybrid.html`（确认 postMessage 的 cad-pick 事件被正确接收并写入巡查记录）
5. [ ] 多图纸支持：7 栋其他楼层 PDF → PNG 底图批量生成，按 key 切换
6. [ ] （可选）截图模式下标注功能（测量距离、画点、标签），需与 Flutter 数据模型对接

---

## 三、关键文件清单

| 文件 | 说明 |
|------|------|
| `web/cad_viewer_hybrid.html` | **主交付物**，截图模式查看器（所有校准/定位/缩放逻辑在此） |
| `web/dy04_7_B05_paper_hybrid.png` | B05 底图（PDF 转 PNG，4500×2551） |
| `web/cad_viewer.html` | 旧的矢量 OCF 渲染页（GStarSDK 方向，已不再主推） |
| `server/dwg_cache/*.dxf` | ODA 转出的 DXF（280MB，已加 .gitignore） |
| `server/cad_meta/dy04_7_B05_dxf_layers.json` | DXF 图层解析结果（310 冻结层，已写入 cad_viewer.html 用） |
| `server/cad_meta/dy04_7_B05_vpdetail.json` | 布局视口解析（4 个视口，VP freeze 全 0——天正图数据缺失） |
| `F:\建筑验收工具\...\01_平面图\` | B05 PDF/DWG 源文件（AutoCAD 可打开） |
| `F:\设计院工作\...\7栋\PDF\` | 7 栋全部 PDF 源（167 张） |

---

## 四、重要约束与经验（避免重复踩坑）

- **浩辰 API 配额仅剩 11 次**：任何扣次接口调用必须先征得用户同意
- **浩辰 `getDwgInfo` 不返回 `vpfreeze`**（视口冻结），无法据此还原布局空间显示
- **ODA 转天正图 DXF 实体段被截断**（`AcDbDictionary can't be cast to AcDbBlockTableRecord`），但 TABLES 段可用 ezdxf.recover 读取
- **ezdxf 不能直接读 DWG**（只能读 DXF）
- **图纸空间 OCF 不含视口裁剪**（浩辰转 OCF 时布局视口数据丢失）→ 这是放弃矢量方案的根本原因
- **用户拒绝 PNG 替代矢量**用于最终展示，但**接受"截图底图 + 坐标映射"混合方案**（截图只做视觉，坐标来自映射计算，仍属"可定位"）
- **PDF → PNG 渲染**：用 `pypdfium2`（已 pip 安装），`page.render(scale=dpi/72)` 可指定分辨率；`get_size()` 返回 pt 单位，物理 mm = pt/72*25.4

## 五、UI 偏好（用户已确认）
- Ins 极简 / ISO 扁平化：白底 `#F5F6F8`、卡片白 `#FFFFFF`、描边 `#E5E7EB`、主文字 `#111827`、次级 `#6B7280`、强调 `#111827`/`#2563EB`/成功绿 `#16A34A`
- 顶栏：60px 高、标题 16-17px、按钮 14px、圆角 10-12px
- 查看/定位/校准用 segmented control（iOS 风格）
- 缩放按钮 + 百分比在顶栏左侧
- 底图初始**自动适配窗口**（整图可见），Ctrl+滚轮缩放，放大后可滚动平移

---

## 六、Git 提交记录
- 本次提交包含：混合方案 HTML、B05 底图、DXF 解析结果（meta json）、PDF 整理辅助、`DEVELOPMENT_LOG_2026-08-16.md`
- DXF 大文件已 .gitignore（不推送）
