# 拍照验收 · 功能流程规格（CAPTURE FLOW SPEC）

> **用途**：拍照验收是本项目的主链源头。本文固化它的**流程、数据契约、判定口径与已知偏离**，
> 供后续开发**溯源**（每个结论都带 `文件:行号`）与**矫正偏离**（§7 偏离清单 + §8 有意设计）。
> **维护规则**：只改与代码不符的行；每处引用行号必须能在源码复核。
> **代码基线**：commit `5361996` + 未提交工作区改动｜**核实日期**：2026-09-18
> ⚠️ **行号漂移**：2026-09-18 实施「立即修复」（D1/D13）后，`capture_page.dart` 第 869 行之后整体 **+9**、`capture_records_controller.dart` 第 283 行之后为 **+8~+10**；本文件行号未逐条同步，**引用时以方法名/字段名为准**。
> **关联文档**：`FEATURE_INVENTORY.md`（M3 拍照验收 / M4 问题清单 / M5 报告）

---

## 0. 一句话定义

**拍照验收 = 在图纸上定位部位 → 现场拍照（烧录防篡改水印）→ AI 识别缺陷 → 落一条「验收记录」→ 可转入「问题清单」→ 进入报告。**

它是现场取证的**唯一入口**，有两条下游出口：
- **出口 A（保存时自动）**：生成 1 条**聚合缺陷**（带照片）进入问题清单 → 报告靠它渲染现场照片；
- **出口 B（人工触发）**：在验收记录里**逐条/批量「转入问题清单」**，生成 N 条待整改缺陷。

---

## 1. 范围与角色

**在范围内**：图纸选点、取图与相机、水印、AI 识别、量尺校对（轻量）、问题描述、保存留痕、验收记录工作台、转入问题清单。

**不在范围内**（属别的模块，本文只写接口）：问题清单的处置/回复/销项（见 M4）、报告生成与四端导出（见 M5）、照片量尺的完整流程（见 M7）。

| 角色 | 在本流程中的动作 |
|---|---|
| 验收人（现场） | 选部位 → 拍照 → AI 识别 → 补描述 → 保存；事后在验收记录里转入问题清单 |
| 复核人（问题清单侧） | 接收转入的缺陷，指派责任、回复、销项（不在本文范围） |

---

## 2. 页面与路由地图

| 路由 | 页面 | 阶段 | 说明 |
|---|---|---|---|
| `/capture` | `CapturePage(stage: select)` | 选图纸与部位（可拍照） | 首页快捷操作「拍照验收」、底部导航中间按钮进入 |
| `/capture/select` | `CapturePage(stage: select)` | 同上 | 与 `/capture` 同页同阶段 |
| `/capture/photo` | `CapturePage(stage: operate)` | 拍照 / 识别 / 保存 | select 阶段拍完自动 push 到这里 |
| `/capture-records` | `CaptureRecordsPage` | 验收记录工作台 | 首页「验收记录」进入 |

依据：`lib/app.dart:152-201`

### ⚠️ 孤儿页（必须知道）

**`CaptureEntryPage`（`lib/features/capture/capture_entry_page.dart`）全项目仅定义、无任何路由或引用**（全库搜索 `CaptureEntryPage` 仅 1 处命中，即其自身定义 `:10`）。
它渲染的「按步骤完成验收」三步说明卡与「开始验收」按钮**实际不可达**；`/capture/select` 渲染的是 `CapturePage`。
→ 处置建议见 §7-D4。

---

## 3. 主流程

### 3.1 概念上的三步（入口页文案口径）

1. 选择图纸和部位 → 2. 现场拍照 → 3. 识别并保存（`capture_entry_page.dart:115-119`）

### 3.2 实际状态机

两个枚举：`CapturePageStage { select, operate }`（`capture_page.dart:65`，由路由参数固定，页内不变）
与 `_CaptureStep { selectFloor, selectPoint, capture }`（`capture_page.dart:68`）。

| 触发 | 行号 | 迁移 |
|---|---|---|
| 进入 `select` 且带 `drawingKey`/`floor` | `:184-187` | → `selectPoint`（并吸附最近锚点） |
| 进入 `select` 无参数 | `:188-191` | → 选第一张图纸 → `selectPoint` |
| 进入 `operate` 且带参数 | `:194-196` | → `capture`（并吸附） |
| 进入 `operate` 无参数 | `:197-213` | → `selectPoint`（解析默认图纸世界坐标） |
| `operate` 首帧后 | `:215-219, 297-302` | **自动拉起相机**（`_didAutoOpenCamera` 去重） |
| 点图纸选点（`select` 阶段） | `:490-506` | 停留在 `selectPoint`，更新 `_x/_y/_drawPointWorld*` |
| 点图纸选点（`operate` 阶段） | `:503` | → `capture` |
| 点「重选部位」 | `:1975` | → `selectPoint` |
| `select` 阶段拍完（`_commitPhoto`） | `:727-742` | `push('/capture/photo')` → 进入 `operate` 页 |
| 保存成功后「继续验收」 | `:1008-1043` | 重置草稿 → `selectPoint` |

> **死枚举值**：`_CaptureStep.selectFloor` **从未被赋值**（全文件只出现在判断/渲染分支），`_buildFloorSelector`（`:1892`）不可达。→ §7-D6

### 3.3 端到端时序（文字泳道）

```
[选图纸/部位]  点图纸 → 夹取 0.02~0.98 → 吸附最近锚点(阈值0.12) → 换算世界坐标(mm)
      │
      ├─(select 阶段直接拍)─→ _doCapture → _commitPhoto → push('/capture/photo')
      │
[现场拍照]     自动拉相机 → pickPhotoRobust(移动端)/相册(Web) → _pendingShot
      │        → 压缩(compressImageAsync) → 烧录水印(applyPhotoWatermark, UI isolate 300~800ms)
      │        → 一次性 setState(_shotPhoto/_originalPhoto, 清空 _defects) → 提示
      │
[AI 识别]      手动点「AI 分析」→ 800ms 扫描动画 → mock(vlPreset) 或 VisionService.recognizeDefects
      │        → _defects / _scanError
      │
[量尺校对]     结果区第 2 段：容差 ±10mm/±5%（可改）→ 依赖图纸标定 mm/px → 逐项判定
      │
[问题描述]     手打 + 语音追加（VoiceInputButton）
      │
[保存]         校验 _shotPhoto 非空 → 写 entry(JSON) + 照片落盘 + 生成 1 条聚合 Defect → 刷新问题清单
      │
[验收记录]     /capture-records → 筛选/分组/详情 → 「转入问题清单」(单条/批量) → N 条 Defect
      │
[报告]         报告只读问题清单(Defect)，不读验收记录
```

---

## 4. 分步功能规格

### S1 选图纸与部位

| 项 | 规格 | 依据 |
|---|---|---|
| 图纸列表 | 7 栋项目用 `dy7Floors`，否则 `floors` | `:340-342` |
| 默认图纸 | 项目映射表决定 | `:344-352` |
| 默认态 | 验收默认直接落到第一张图纸，不停在「选择图纸」步骤 | `:188-189` 注释 |
| 选点 | 点击图纸 → 相对坐标夹取在 `0.02~0.98` | `:490-506` |
| 锚点吸附 | 距最近锚点 < `0.12` 或 `force` 时吸附，部位名自动带出 | `:509` |
| 世界坐标 | 由 `CadCoordMapper` 换算 mm；**未校准时返回 null 并静默降级**（页面仍可用） | `:463-486`；注释 `:469` |
| 锚点历史照片 | 点图钉可看该锚点历史照片；无则提示「「X」暂无历史照片」 | `:2043-2045` |
| 底图 | 本地 PNG；无 PNG 但有 `cadOcfKey` 时调 CAD 服务生成远程 PNG | `:430-455` |
| 远程 PNG 异常态 | 占位文案「正在生成 PNG 底图…」/「该图纸暂无 PNG 底图」 | `:1652` |

### S2 现场拍照

| 项 | 规格 | 依据 |
|---|---|---|
| 自动拉相机 | `operate` 页首帧后自动调用，`_didAutoOpenCamera` 防重复 | `:215-219, 297-302` |
| 取图分流 | Web → `ImagePicker.gallery`（1280/82）；Android/iOS → `pickPhotoRobust`（1920/88，权限引导 + 相册兜底） | `:532-552` |
| 权限被拒 | 弹「需要相机/相册权限」+「稍后」/「去设置」(`AppSettings.openAppSettings`) | `:555-571` |
| 取消拍摄 | 提示「已取消拍摄」，保持原状态 | `:648-651` |
| 压缩 | `compressImageAsync`（VM isolate；Web 回落主线程） | `:688` |
| 水印元信息 | `WatermarkMeta{ project, anchor, time, gps, altitude, reporter, serial, worldCoord }`；`project` 取**定位点名称** `_location.name`；`worldCoord` 仅在有图纸坐标时带 | `:690-705` |
| 水印烧录 | `applyPhotoWatermark`，**必须 UI isolate，阻塞主线程 300~800ms** | `:707-714`；注释 `:105-110` |
| 水印失败降级 | 用未烧录的压缩图，提示「已拍摄（水印烧录失败，已保留原图）」(danger) | `:711-715, 745-747` |
| 成功提示 | 「已拍摄并烧录防篡改水印」(success) | `:745` |
| 竞态保护 | 仅当 `_pendingShot == shot` 才应用结果，避免取消后「复活」 | `:718-720` |
| 重拍 | `_retake` 只重拍，图纸/部位不变；取消则保留当前照片 | `:978-983` |
| 拍照后副作用 | **清空 `_defects`**（AI 结果随新照片重置） | `:724` |
| 不再自动识别 | 注释明确：不再自动触发 AI，由用户手动点 | 注释 `:757` |

### S3 AI 识别（结果区第 1 段）

| 项 | 规格 | 依据 |
|---|---|---|
| 触发 | 手动点「AI 分析」按钮 | `:2844-2851` |
| 扫描动画 | 固定 800ms（避免一闪而过） | `:790` |
| mock 分流 | `_useMock = kIsWeb` → `vlPreset(anchor, replayReal:true)` | `:147-149, 796` |
| 真实调用 | 非 mock 且有照片 → `VisionService().recognizeDefects(_originalPhoto ?? _shotPhoto)`（用无水印图避免水印文字干扰） | `:797-828` |
| 超时 | 180s（`vision_service.dart:120`）；超时文案「识别超时（Ns）：模型响应过慢，可重试」 | `:820` |
| 其他失败 | 「识别失败：$e」 | `:825` |
| 建议兜底 | 模型未返回 `suggestion` 时走本地建议库 `suggestionFor` | `:813` |
| 未识别到缺陷 | 空态文案「尚未识别到缺陷…」；**保存时仍留痕**（不阻断） | `:2185-2189`；注释 `:894` |
| 严重程度 | **模型未返回 severity，统一默认 `orange`**（待后端补） | 注释 `:805-806` |
| 置信度 | 传真实 conf，低置信在卡片与清单提示人工复核 | 注释 `:807-808` |

### S4 量尺校对（结果区第 2 段，轻量）

| 项 | 规格 | 依据 |
|---|---|---|
| 容差默认 | ±`10`mm 且 ±`5`%（常量 `_defaultTolMm/_defaultTolPct`） | `:38-39, 158-159` |
| 标定来源 | `cadCalibrationMapProvider[drawingKey]` → `_scaleMmPerPx`；**无标定时静默降级**（隐藏标定比例 chip） | `:162, 2312` |
| 交互 | 可改容差、增删校对项、逐项显示图纸值/实测值/偏差/判定 | `:2384-2564` |
| 与 S6 的关系 | 校对项**不进** entry JSON，也不进问题清单（仅页面内参考） | `:857-869` |

> ⚠️ 判定门槛：本页用页面内 `_tolMm/_tolPct`，**未接项目级 `MeasureThresholdStore`**（拍照量尺页已接）。→ §7-D8

### S5 问题描述（结果区第 3 段）

- 手打：`_noteController`（`:123`）。
- 语音：`VoiceInputButton`，识别结果**追加**到文本框（`:3098-3113`）。
- 归一化：保存时 `trim()`（`:856`）。

### S6 保存（关键：一次拍照 = 一条验收记录 + 一条聚合缺陷）

**前置校验**（`_saveRecord`，`:989-991`）：`_scanning` 中直接 return；已保存（`_saved`）直接 return。

**第一次校验**（`_saveRecordToStorage`，`:846-852`）：`_shotPhoto == null` → 提示「请先拍照或选择照片」(danger)，返回 `false`（**不锁定按钮**，允许补拍后再存，注释 `:988`）。

**写入内容 —— 验收记录 entry（JSON，唯一事实源）**：

| 字段 | 类型 | 说明 | 行号 |
|---|---|---|---|
| `id` | String | `now.microsecondsSinceEpoch` | `:858` |
| `drawingKey` | String | 当前图纸 key（空串表示未关联） | `:859` |
| `worldX` / `worldY` | double? | 图纸世界坐标 mm（未选点/未校准为 null） | `:860-861` |
| `ts` | String | `YYYY-MM-DD HH:mm:ss` | `:854-855, 862` |
| `anchor` | String | 部位（锚点名 / 已选点(…) / 待选点） | `:863` |
| `floor` | String | 楼层 | `:864` |
| `count` | int | AI 缺陷条数 | `:865` |
| `defects` | List | `VlDefect.toJson()` **+ `status:'pending'`** | `:866-867` |
| `note` | String | 用户问题描述 | `:868` |
| `photo` | String? | 相对路径 `photos/xxx.jpg`；**落盘失败则不写该字段** | `:875-885` |

`defects[i]` = `{name, severity, conf, desc, suggestion, status}`，`status ∈ {pending, converted}`。

**照片落盘**：`photos/<ts 的 `:` 与空格替换为 `-`>.jpg`，写失败**不阻断**结构化结果（`:877-884`）。

**同时生成「聚合缺陷」（出口 A）** —— 一条拍照只生成 1 条 `Defect`：

| Defect 字段 | 取值 | 行号 |
|---|---|---|
| `id` | `cap_<microsecondsSinceEpoch>` | `:930` |
| `part` | `"部位·楼层·首个缺陷名"`，多项时加 `等N项` | `:931-933` |
| `type` | 首个缺陷名，无则 `现场拍照记录` | `:916, 934` |
| `category` | 固定 `other` | `:935` |
| `severity` | **取最高**（rank 越小越严重）；无识别结果 → `green` | `:910-915, 936` |
| `status` | `draft` | `:937` |
| `gps` / `alt` | 定位点 GPS / `海拔 X.Xm` | `:903-904, 941-942` |
| `resp` | 固定 `待指派` | `:943` |
| `reporter` | 当前用户 | `:944` |
| `tags` | `['拍照记录', ...各缺陷名]` | `:945` |
| `note` | 拼接：无缺陷说明 + 未落盘说明 + 各缺陷 desc + 用户描述（`\n` 连接） | `:917-922, 946` |
| `seed` | `capture` | `:947` |
| `photoPath` | **照片相对路径（报告照片靠这个字段）** | `:951` |
| `suggestion` | 各缺陷建议聚合，多条时 `缺陷名：建议` | `:923-928, 952` |

**保存后动作**：`invalidate(defectsProvider)`（`:955`）→ 入 `_storedResults` 头部（`:958`）→ `writeDoc('stored_vision_results')`（`:961-965`，`unawaited`）→ Snack。

**保存成功文案**（`:966-973`）：
- 巡场入口：`巡场标记已保存（未分析）` / `巡场标记已保存`
- 普通：`记录已保存（未分析）` / `记录已保存`

**保存后的按钮态**（`:3128-3195`）：`canSave = _shotPhoto != null && _pendingShot == null && !_scanning && !_saved`；已保存后变双按钮 —— 巡场入口「返回巡场继续 / 继续标记下一个问题」，普通「查看验收记录 / 继续验收」。

### S7 拍照记录（留痕，非结果区分段）

> **现状**：`_resultTab` 注释按 4 段设计（`:90-94`），但分段控件实际只有 **3 段**（`:1533-1536`）；「拍照记录」被移到 AppBar 相册图标 → 底部弹窗 `_showStoredSheet`（`:3215`）。→ §7-D5

- 列表：`_filteredStoredResults` 按当前 `_drawingKey` 过滤（`:3209`）。
- 支持：看缩略图、打开详情、删除（二次确认「删除暂存记录 / 将同时删除该记录及关联照片，确定？」`:3324-3328`）。
- 删除副作用：从 `_storedResults` 移除 + 重写文档 + 删照片文件。

---

## 5. 验收记录工作台（`/capture-records`）

数据源：`captureRecordsProvider`，底层为 `LocalStorage` 文档 `stored_vision_results`（`capture_records_controller.dart:61`，与 `capture_page.dart:145` 同 key）。

### 5.1 统计条口径（`capture_records_page.dart:274-299`）

| 指标 | 口径 |
|---|---|
| 累计记录 | 当前项目过滤后的 `all.length` |
| 今日新增 | `ts >= 今日 00:00` 的记录数 |
| 待整改 | **所有记录中 `defects[].status != 'converted'` 的缺陷总数**（与当前筛选无关） |

> ⚠️ `_calcStats(all, filtered)` 的第二个参数 `filtered` **完全未被使用**（死参数）。

### 5.2 筛选与分组

- 时间：全部 / 今日 / 本周（本周 = 最近 7 天含今日，`controller:237, 246-248`）。
- 楼层：由当前数据去重生成选项（`page:301-310`）。
- 仅看 AI 缺陷：`defects` 非空即保留（`controller:256-259`）。
- 分组：今日 / 昨日 / 更早，空组剔除，组头可折叠（`widgets/grouped_grid.dart:53-83`）。
- 栅格：≥520 四列 / ≥400 三列 / 否则两列（`grouped_grid.dart:154-158`）。

### 5.3 卡片与详情

- 卡片：1:1 缩略图（Web 无图显示占位）+ 待转缺陷角标（或「无缺陷」绿勾）+ `部位` + `楼层 · MM-DD HH:mm`（`widgets/thumbnail_card.dart`）。
- 详情弹层 `StoredDetailSheet`（`capture_page.dart:3590`）：照片大图、「AI 识别结果」逐条（名称/描述/置信度 + 单条「转入问题清单」或「已转入」徽标）、问题描述、**批量转入问题清单（N）**、删除该记录。

### 5.4 「转入问题清单」（出口 B）

- 单条与批量**落点相同**：`onConvert(idxs)` → `capture_records_page._onConvert`（`page:236-270`）。
- 副作用序列（**无事务**）：
  1. 循环 `repo.addDefect(buildDefectFromCaptureDefect(...))`（`page:245-253`）
  2. `ref.invalidate(defectsProvider)`（`page:254`）
  3. 循环 `markDefectConverted(captureId, idx)`（`page:255-259`）—— **返回值被忽略**
  4. Snack「已生成 N 条问题记录」+「去问题清单」（`page:260-268`）
  5. 最终**无条件 `return true`**（`page:269`），无 try/catch
- 幂等保护：`markDefectConverted` 内部对已 `converted` 或未命中返回 `false`（`controller:140, 145`）。

**Defect 字段映射表**（`buildDefectFromCaptureDefect`，`controller:279-319`）：

| Defect 字段 | 来源 | 默认 |
|---|---|---|
| `id` | — | `"$captureId#$idx"`（`:297`） |
| `part` | `capture.anchor` | `验收点`（`:298`） |
| `type` | `vlDefect.name` | `未分类`（`:299`） |
| `category` | — | 固定 `other`（`:300`） |
| `severity` | `vlDefect.severity` 字符串解析 | 失败回落 `orange`（`:301, 322-328`） |
| `status` | — | 固定 `draft`（`:302`） |
| `anchor` / `floor` / `ts` | 透传 | `''` |
| `gps` / `alt` / `resp` | — | 固定 `''`（`:306-308`） |
| `reporter` | — | 固定 `验收记录`（`:309`） |
| `tags` | — | `['验收转工单', '验收#$captureId']`（`:310`，历史文案） |
| `note` | `capture.note` + `vlDefect.desc` | `"$note｜$desc"`（`:311`） |
| `seed` | — | `capture_convert`（`:312`） |
| `drawingKey/worldX/worldY` | 透传 | null |
| `photos` | `[capture.photo]` | `[]`（`:316`） |
| `photoPath` | **未赋值** | null ← **报告照片断链根因** |

### 5.5 删除

顺序保证：**先写回文档成功，才删照片文件**；写失败则中止且不删照片（`controller:99-112`）。写回时按 id 精确移除，保留其他项目/记录（`:95-97`）。

### 5.6 项目隔离

`_applyProjectFilter` 用 `drawingsProvider` 的 key 集合过滤；`drawingKey` 为空的记录保留（兼容历史）；drawings 未就绪时不过滤（`controller:205-218`）。切换项目通过 `ref.listen(is7DongProjectProvider)` 自动重载（`controller:54`）。

---

## 6. 与下游的接口

| 下游 | 是否读验收记录 | 说明 |
|---|---|---|
| 问题清单 `/defects` | **间接** | 只读 `Defect`；验收数据是经「保存」或「转入」进入的 |
| 报告导出 | **不读** | 数据源是 `defectsProvider`（`defects_page.dart:44, 119-124, 753-756`）；全库在 `features/defects` 内搜索 `capture/stored_vision/sourceCaptureId` **0 命中** |
| 报告照片 | 仅靠 `Defect.photoPath` | 四个导出端都只读 `photoPath`/`replyPhotoPath`（`report_builder.dart:536`、`report_pdf.dart:754`、`report_docx.dart:557`、`defects_page.dart:178`） |
| 报告归档 | 不读 | 归档只存元数据（见 M5） |

> `Defect.photos` 列表除赋值外**无任何消费方**。

---

## 7. 偏离清单（按严重度）

| # | 严重度 | 问题 | 证据 | 影响 | 建议 |
|---|---|---|---|---|---|
| D1 | ✅ **已修**<br>（2026-09-18） | **报告照片断链**：转入生成的 Defect 未写 `photoPath`，而报告只读 `photoPath` | `buildDefectFromCaptureDefect` 现补 `photoPath`；`report_builder.dart:516` 对 null 静默省略的行为保留（有路径才渲染照片区） | 原影响：转入的缺陷在报告里**连照片区块都不渲染**；`capture_page` 原注释称"显示占位"与实现不符，注释已同步修正 | 已完成 |
| D2 | 🔴 高 | **同一次拍照在问题清单留 1+N 条**：保存时生成 1 条聚合缺陷（`seed:'capture'`），转入又生成 N 条（`seed:'capture_convert'`） | `capture_page.dart:929-953` + `controller:296-318` | 同一照片/部位重复出现，报告与清单噪声 | 明确二者分工（留痕 vs 整改项），或转入时合并/去重 |
| D3 | 🔴 高 | **转入无事务、失败静默**：先写 N 条 Defect → 刷新 → 再逐个回写 `converted`；返回值忽略、无 try/catch、最终无条件 `return true` | `capture_records_page.dart:245-269` | 部分成功时验收记录仍显示未转入，可重复点击（Defect id 相同故清单不重复，但状态不一致） | 检查返回值 + 失败提示 + 重试；或改为「先建后标」的可回滚顺序 |
| D4 | 🟠 中 | **`CaptureEntryPage` 是孤儿页**：仅定义、无路由引用 | 全库仅 `capture_entry_page.dart:10` 命中 | 三步说明卡与「开始验收」不可达，维护成本白付 | 接管 `/capture` 或删除 |
| D5 | 🟠 中 | **结果区分段 3 段 vs 注释 4 段**：「拍照记录」实为 AppBar 弹窗 | `capture_page.dart:90-94` vs `:1533-1536, 3215` | 注释误导 | 改注释或把入口纳入分段 |
| D6 | 🟠 中 | **`_CaptureStep.selectFloor` 死枚举值**，从未赋值；`_buildFloorSelector` 不可达 | `:68, 1892` | 死代码 | 删除 |
| D7 | 🟠 中 | **`_scanTimer` 死字段**：只被 `cancel()`，从未赋值 | `:127, 322, 787, 981, 1023` | 死代码 | 删除 |
| D8 | 🟠 中 | **量尺校对判定门槛未接项目级配置**（本页用 `_tolMm/_tolPct`，拍照量尺页已接 `MeasureThresholdStore`） | `:158-159` vs `measure_threshold_store.dart` | 同一报告内两种判定口径 | 统一到项目级门槛 |
| D9 | 🟠 中 | **统计死参数**：`_calcStats` 的 `filtered` 完全未使用 | `capture_records_page.dart:274-277` | 「待整改」与当前筛选无关，易被误读 | 明确口径或启用 |
| D10 | 🟠 中 | **Web 端照片不落盘**（内存 Map，刷新即丢） | `capture_page.dart:870-874`、`app_storage_web.dart:26-27` | Web 演示会话刷新后记录与照片全丢 | 已在 FEATURE_INVENTORY 记为 Web 特性；如需持久需改存储 |
| D11 | 🟡 低 | **注释与实现不一致**：`models.dart:456-458` 称 `sourceCaptureId` 填 `"${captureId}#${idx}"`，实际填 `captureId` | `controller:317` | 误导 | 修注释 |
| D12 | 🟡 低 | **`sourceCaptureId` 只写不读**：无「问题清单 → 验收记录」反向同步 | `controller:317`；全库无读取 | 注释所称「双向」名不副实 | 要么补反向读，要么改注释 |
| D13 | 🟡 低<br>（部分已修） | 转入生成的 Defect 曾写死 `reporter='验收记录'`、`gps/alt/resp` 全空、`tags` 含历史文案「验收转工单」 | `buildDefectFromCaptureDefect` | **已修**：`reporter` 改用 entry 的真实拍摄人（旧数据回落 `验收记录`）、`gps/alt` 由 entry 透传。**未修**：`resp` 仍为空、`tags` 仍含历史文案 | 剩余项待处理 |
| D14 | 🟡 低 | AI 严重程度统一默认 `orange`（模型未返回） | `:805-806` | 报告严重度分布失真 | 后端补返回后映射 |
| D15 | 🟡 低 | Web 默认走 mock（`_useMock = kIsWeb`），结果为 `vlPreset` 预置数据 | `:147-149, 796` | Web 端识别结果非真实 | 演示特性，需在验收标准写明 |
| D16 | 🟡 低 | 水印「项目」字段取**定位点名称** `_location.name`，非项目名 | `:693` | 水印信息语义待确认 | 确认是否有意 |
| D17 | 🟡 低 | 类头注释称「真实相机已注释、走模拟拍照」，与实现（真机相机）不符 | 注释 `:46-48` vs `:532-552` | 误导（曾被当作未完成项） | 修注释 |
| D18 | 🟡 低 | 控制器内注释与缩进异常：顶层私有函数被写成「内部使用：Notifier 私有」 | `controller:264-265` | 可读性 | 整理 |

---

## 8. 有意设计（**不要当 bug 盲改**）

以下行为是**注释明确写下的设计决策**，改之前必须先确认产品意图：

1. **一次拍照聚合为一条 Defect** —— VL 常对同一张照片返回多条观察，但「现场一次观察即一次整改」，拆多条会在报告/列表重复（`capture_page.dart:889-892`）。
2. **没有识别结果也入问题清单** —— 保证拍照留痕可追溯，「避免拍了看不到」（`:894`）。
3. **照片落盘失败也入列表** —— 照片缺失只影响报告配图，记录必须同步（`:895-896`）。
4. **水印必须在 UI isolate** —— 已知阻塞 300~800ms，为将来 isolate 化保留了 UI 分支（`:105-110, 3134-3135`）。
5. **不再自动触发 AI** —— 由用户手动点「AI 分析」（`:757`）。
6. **保存按钮首次误触不锁定** —— 未拍照时可补拍后再存（`:988`）。
7. **`tags` 保留「验收转工单」文案** —— 历史数据标识，改名会造成新旧数据对不上（`controller:273-274`）。
8. **删除先写文档后删照片** —— 保证数据完整性优先（`controller:99-105`）。

---

## 9. 溯源索引

| 文件 | 职责 |
|---|---|
| `lib/features/capture/capture_page.dart` | 主页面：选图纸/选点/拍照/水印/AI/量尺校对/描述/保存/拍照记录弹窗 |
| `lib/features/capture/capture_entry_page.dart` | 验收入口说明页（**孤儿**，见 D4） |
| `lib/features/capture_records/capture_records_page.dart` | 验收记录工作台：统计/筛选/分组/详情/转入 |
| `lib/features/capture_records/capture_records_controller.dart` | 数据源、删除、`converted` 回写、`buildDefectFromCaptureDefect` |
| `lib/features/capture_records/widgets/*.dart` | `stats_strip` / `filter_tabs` / `filter_sheet` / `grouped_grid` / `thumbnail_card` |
| `lib/data/models.dart` | `Defect`（`:407-718`）、`VlDefect`/`VisionResult`（`vision_service.dart:8-79`）、`CaptureArgs`、`SiteLocation` |
| `lib/data/vision_service.dart` | `recognizeDefects`（`:107`）、host 配置（`:84-87`） |
| `lib/core/utils/photo_watermark.dart` | 水印烧录与哈希 |
| `lib/core/utils/image_compress.dart` | 压缩（isolate） |
| `lib/core/utils/camera_pick.dart` | `pickPhotoRobust`（权限引导 + 相册兜底） |
| `lib/core/storage/local_storage.dart` | KV / Doc / File 抽象（IO 与 Web 分流） |
| `lib/data/repository/mock_repository.dart` | `addDefect` 落 `added_defects_v1`（`:118-122`） |
| `lib/features/defects/report_builder.dart` 等四端 | 报告渲染，只读 `Defect.photoPath` |

---

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-18 | 首版：从代码逐文件核实建立（基线 `5361996` + 未提交改动）；输出 18 条偏离、8 条有意设计 |
