# 开发日志 2026-09-03（周四）

> 目的：上下文恢复文档（省积分）。新会话先读本文 + `DEVELOPMENT_LOG_2026-09-02.md` + `CODEBUDDY_HANDOFF.md`。

## 一、今日完成：Excel 销项表导出（09-02 待办第 1 项，标注"对接价值最高"）

### 1. 新增 `lib/features/defects/report_xlsx.dart`
- 纯 Dart 手写 OOXML + `package:archive` 打包，与 `report_docx.dart` 同一套路，**零插件零原生依赖**（Web/桌面/移动通用）。
- 成为报告**第四个渲染端**（原 HTML/PDF/Word），复用 `report_content.dart` 的 `groupDefects()` / `buildReportStats()`，保证与三端同板块、同分组、同排序。
- **两个工作表**：
  1. `销项汇总` —— 标题/项目/周期/编制单位/编制人 + 8 项统计（照片·楼栋·施工内容·巡场问题·未闭环·已闭环·重要紧急·已回复）
  2. `巡场销项表` —— 按楼栋分组的明细（无楼栋数据自动回退按严重程度分组）

### 2. 表头对齐设计师巡场报告单（LDI/SZAD 模板）三大区
`巡场意见`（序号/楼栋/部位·缺陷/重要等级/严重程度/状态/责任单位·人/发现时间）
→ `整改回复`（内容/回复人/回复时间）
→ `闭合确认`（是否闭合/完成状态/未闭合说明）
共 14 列；分组头横跨整行显示「楼栋名 + 共N条·未闭环M」。

### 3. 接入导出入口
- `report_builder.dart` 的 `ReportExportFormat` 新增 `xlsx('Excel 销项表', …)`，**置于首位**（对接价值最高）。
- `defects_page.dart` 的 `_buildExportFile` switch 加 xlsx 分支（MIME `spreadsheetml.sheet`），并补 `import 'report_xlsx.dart';`。

## 二、实现要点（复用 / 避坑）

| 要点 | 说明 |
| --- | --- |
| 字符串单元格 | 统一用 `t="inlineStr"` + `<is><t>`，**省去 sharedStrings 索引管理**（几百行体积可忽略，换来实现大幅简化） |
| 样式槽位 | fonts 4 / fills 5 / borders 2 / cellXfs 8。**OOXML 规范：fill 槽位 1 = gray125 必须占位**，否则 Excel 报样式错误（故 fills 顺序不能动，Dart 侧未直接引用的槽位以注释说明） |
| 序号 | 用**独立计数器 `seq`**（跨分组累计），不可用行号换算——行号含表头与分组头会错位 |
| 空单元格 | 只写 `s="<style>"` 不写值，保持分组头边框连续 |
| 冻结首行 | `<pane ySplit="1" topLeftCell="A2" state="frozen"/>` |
| XML 安全 | `_esc()` 转义五字符 + `_xmlSafe()` 剔除 XML 1.0 非法控制符（`\x00-\x08` 等），避免备注里的隐藏字符让 Excel 报"文件损坏" |

## 三、环境坑（已确认，沿用 09-01/09-02 结论）

- **`flutter analyze` 在本机必崩**：analysis server 解析中文路径时 JSON `Unterminated string`（断点在 `E5%B7%A5%E5%85%B7/site-patrol/` 的 URL 编码处）。**本项目以 IDE 诊断（read_lints）为准**，不依赖 CLI analyze。
- git 代理 `127.0.0.1:7897` 无监听，推拉用一次性覆盖：`git -c http.proxy="" -c https.proxy="" push origin main`。
- 构建必须带 base-href：`flutter build web --release --base-href=/jianzhu/`。
- 本地预览：`python C:\Users\yuting.yang1\AppData\Local\Temp\serve_build_web.py` → `http://localhost:8765/jianzhu/`（根路径 404 正常，须带前缀）。
- WASM 不可用（`dart:html` 依赖），仅 JS 构建。

## 四、验证状态

- IDE 诊断：**0 lint**（4 个 warning 已清零：删未引用的槽位常量 + 去多余 `!`）
- 测试：`flutter test test/report_builder_test.dart test/report_export_test.dart` → **6/6 通过**
- 构建：`flutter build web --release --base-href=/jianzhu/` → **成功**
- 手工验证待办：导出一次 xlsx，用 Excel 打开确认三区列齐全、楼栋分组头正常、无"文件已损坏"提示

## 五、待办 / 下一步（承接 09-02）

1. ~~xlsx 销项表导出~~ ✅ 今日完成
2. **成果审核确签单**（送审/审核、批准-须修改-拒绝、各方签字栏）流程纳入
3. 后端 `/api/vision` prompt 升级：要求模型输出 `suggestion`（客户端已兼容）与真实 `severity`
4. 巡场清单页 UI：楼栋分组视图、整改回复录入入口（目前回复数据靠 mock/拍照，无编辑 UI）
5. 部署：`build/web` 上传宝塔 ECS 挂 `/jianzhu/`
6. 交接文档 `CODEBUDDY_HANDOFF.md` 的任务线①量尺修复 P1/P2 剩余项（P0 已完成：PhotoCalib 已 2D 化）
7. `F:\GitHub\site-patrol` 旧副本仍未删除（被进程占用），重启后可删

## 六、快速恢复命令

```bash
cd F:\建筑验收工具\site-patrol
git status && git log --oneline -3
flutter test test/report_builder_test.dart test/report_export_test.dart
flutter build web --release --base-href=/jianzhu/
git -c http.proxy="" -c https.proxy="" push origin main
```

## 七、下午补充：0902 需求差距实施（任务 1~6 全部落地）

> 主任务文件：`REQUIREMENTS_0902_IMPL.md`（含现状盘点与任务 1~7）。任务 7（网页链接）按约束不做（后端不在工程内）。

### 1. 各任务完成情况
| 任务 | 内容 | 状态 |
| --- | --- | --- |
| 1 | 本地整改建议库 14 → **35 条**（结构/砌筑/防水/装饰/机电/成品保护） | ✅ |
| 2 | 巡场**检查点打卡制**：`CheckIn` 模型 + `PatrolRecord.checkins/checkpointTotal` + `patrol_record_store` + 打卡栏（实时 `已到 n/m`）+ 漏检标红 + 达成率（完成 Snack / 历史面板） | ✅ |
| 3 | **DWG 自助上传 → OCF**：file_picker/web 自实现选文件 + `uploadDwgLocal` + `uploaded_drawing_store` + 图纸库「我的上传」+ 底图预览 | 🔶 见下方「本地转换链路」 |
| 4 | **设计师远程处置**：`Defect` 四字段 + `updateDefect` 持久化 + 详情页处置卡 + 「待设计师处置」筛选 + 卡片状态条 + **报告四端「设计师远程解决 N」** | ✅ |
| 5 | **施工方整改回复**：详情页回复卡（提交销项/仅保存待复核）+ 「待施工方回复」筛选 + 卡片回复条 | ✅ |
| 6 | 安卓 AR 调研：`ANDROID_AR_RESEARCH.md`（ARCore GMS 覆盖局限 / 华为 AR Engine 成本 / 建议路径 / 排期） | ✅ |

### 2. 浩辰配额用尽 → 切换「本地优先」转换链路（零配额）
```
DWG ──ODA File Converter(免费,本机已装)──► DXF ──ezdxf──► 图层/布局 JSON + PNG 底图 + SVG
```
- 新增 `server/cad_local.py`（ODA→DXF→ezdxf 元数据→渲染），`ocf_server.py` 加 `POST /api/upload-dwg-local`（产物与浩辰路径同构，前端协议不变）
- `CadService.uploadDwgLocal()`；浩辰 `uploadDwgAndConvert` 保留未删（买配额后一行切回）
- 上传图成为一等公民：`floorsProvider/drawingsProvider` 合并（`up_` 前缀、「我的上传」分组），**可进查看器 / 巡场 / 打点**
- 新建 `lib/shared/widgets/drawing_image.dart`：底图统一渲染（http→Network、否则 asset），viewer / patrol / editor / capture / measure 五处已切
- 实测（B01.dwg）：567 图层、布局 `['7栋组合图','Model']`、PNG 415KB、SVG 39MB

### 3. 已知坑（本次新增）
- **`file_picker 8.x` 在 Flutter Web HTML 渲染器下不可用**（点了没反应）→ 改用 `dart:html` 自实现，条件导入：`_dwg_picker_web.dart`(dart:html) / `_dwg_picker_io.dart`(file_picker)
- **Python `BaseHTTPRequestHandler` 的 `self.path` 未 URL 解码** → 中文文件名 404；`do_GET` 顶部加 `urllib.parse.unquote()`；`/api/ocf/` 分支需显式支持 `.svg`
- **Windows cmd/powershell 中文路径**：`Start-Process -WorkingDirectory` 与 `python -c` 均会乱码；长命令用临时 `.py` 脚本执行，输出重定向到文件再读
- 39MB SVG 在 flutter_svg（Web）渲染失败/黑屏 → 预览页**默认 PNG**，右上角按钮切到 SVG（按需）

### 4. 服务与预览
- CAD 服务：`cd F:\建筑验收工具\site-patrol && python server\ocf_server.py 8800`（`configured=True`，浩辰凭证在 `server/config.py`）
- 前端预览：`python C:\Users\yuting.yang1\AppData\Local\Temp\serve_build_web.py` → `http://localhost:8765/jianzhu/`
- 桌面端看完整标注（含文字）：浏览器直接打开 `http://localhost:8800/api/ocf/{key}.svg`

## 八、明日待办（承接本次）

1. **【P0】SVG 渲染优化**：39MB SVG 在 `flutter_svg`(Web) 渲染失败 → 方案：① ezdxf 实体级过滤（仅主结构/标注图层，剔除装饰/填充）② 文字层单独出 SVG 叠在 PNG 几何上 ③ 评估 Aspose.CAD 本地买断（高保真+含文字，彻底解决）
2. **上传图自动校准**：`bounds`(CAD mm 范围) 已落库，接 `cad_calibration` 生成 mapper → 打点带精确 worldX/Y + 图纸量尺开通
3. **图层开关面板**：读 `/api/ocf-meta/{key}`（567 图层数据已就绪）渲染图层列表
4. 真机走测：打卡 / 设计师处置 / 施工方回复 / 上传链路（本轮均为 lint + build 层验证）
5. 清理：`F:\GitHub\site-patrol` 旧副本（被进程占用，重启后可删）
