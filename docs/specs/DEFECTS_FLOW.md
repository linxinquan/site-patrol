# 问题清单 · 功能流程规格（DEFECTS FLOW SPEC）

> **用途**：问题清单是缺陷闭环的**唯一工作台**（拍照验收的下游、报告导出的上游）。
> 本文固化它的流程、数据契约、状态机与已知偏离，供后续开发**溯源**与**矫正偏离**。
> **维护规则**：只改与代码不符的行；每处引用行号必须能在源码复核。
> **代码基线**：commit `5361996` + 未提交工作区改动｜**核实日期**：2026-09-18
> **关联文档**：`FEATURE_INVENTORY.md`（M4 问题清单 / M5 报告）、`docs/specs/CAPTURE_FLOW.md`（上游）
> **本文不含**：报告四端渲染细节（属 M5，另出规格）

---

## 0. 一句话定义

**问题清单 = 缺陷从「产生」到「闭合」的全生命周期工作台**：
状态分段浏览 → 打开详情 → 设计师处置 / 施工方回复 → 销项 → 导出报告。

它是**三条写入路径的汇聚点**：拍照验收保存（1 条聚合）、验收转入（N 条）、图纸打点（1 条）。

---

## 1. 范围与角色

**在范围内**：清单页（状态分段/操作卡/缺陷卡）、处置与回复二级页、记录详情页（设计师处置 / 整改回复 / 销项）、时间轴对比、导出入口与其归档副作用、缺陷状态机与数据契约。

**不在范围内**：报告四端渲染（M5）、拍照验收与验收记录（见 `CAPTURE_FLOW.md`）、巡场记录（M6）。

| 角色 | 在本流程中的动作 |
|---|---|
| 设计管理/设计院 | 看清单 → 打开详情 → 「设计师处置」三选一（远程已解决 / 远程已答复 / 需要到现场） |
| 施工方 | 看清单 → 打开详情 → 填「整改回复」→ 仅保存待复核 或 提交并销项 |
| 验收人 | 上游产出缺陷（本文只写入口，见 `CAPTURE_FLOW.md`） |
| 复核人 | 用状态分段盯「待整改 / 整改中」，用导出报告对外交付 |

> ⚠️ **角色是"扮演式"的**：右上角「切换身份」只切换展示用的当前用户（`currentUserIdProvider`），**不影响任何权限与数据可见性**。

---

## 2. 页面与路由地图

| 路由 | 页面 | 说明 |
|---|---|---|
| `/defects` | `DefectsPage` | 清单主页（底部导航「问题」tab） |
| `/defects/disposal/:kind` | `DisposalReplyPage(kind)` | `kind ∈ {designer, reply}`；待设计师处置 / 待施工方回复 |
| `/defects/record/:id` | `RecordDetailPage(defectId)` | 记录详情（处置 + 回复 + 销项） |
| `/timeline` | `TimelineComparePage(anchor)` | 同部位多时点照片对比；`extra` 传部位字符串 |

依据：`lib/app.dart:134-149, 218-228`

### ⚠️ 入口重复与死链

- 清单主页有 **3 个入口**：底部导航「问题」tab、首页「今日待办 → 查看全部」、验收记录「转入」后的 Snack 动作；首页快捷操作里的「问题清单」卡**已删除**（见 FEATURE_INVENTORY §4-10）。
- **`defectSpecialFilterProvider`（`providers.dart:331`）定义后从未被任何页面使用** → 死 provider；处置与回复页用的是自己的本地 `_kind` 状态（`defects_page.dart:998-1003`）。

---

## 3. 状态机

`DefectStatus { draft, doing, done, reject }` → 文案「待整改 / 整改中 / 已销项 / 已拒绝」（`models.dart:8-22`）

| 状态 | 文案 | 颜色（规范） | **有写入路径吗** |
|---|---|---|---|
| `draft` | 待整改 | 橙 `#FF9500` | ✅ 三条产生路径全部写 draft |
| `doing` | 整改中 | 蓝 `#0395FF` | ❌ **无任何代码写入**（仅 mock 种子有） |
| `done` | 已销项 | 绿 `#34C759` | ✅ 详情页两处写 done |
| `reject` | 已拒绝 | 红 `#FF3B30` | ❌ **无任何代码写入**（仅 mock 种子有） |

**结论：`doing` / `reject` 是"只能看、不能产生"的状态**。它们出现在状态分段（`defects_page.dart:1151, 1153`）、首页待办口径（`home_page.dart:976`：draft **或 doing** 都算待办）、报告未闭合统计（`report_content.dart:308`、`report_builder.dart:213`：draft **或 doing** 计为未闭合）与图例中，但 UI 没有任何入口能把缺陷推进到这两个状态。
→ 影响：报告「整改中」统计永远来自种子数据；用户无法表达"已开始整改"或"拒绝整改"。见 §7-D1。

**唯一的两处 status 写入**（都在记录详情页）：
1. 底部「提交并销项」→ `done` + `completion='已完成（整改销项）'`（`record_detail_page.dart:146-147`）
2. 设计师「远程已解决」→ `done` + `completion='已完成（设计师远程销项）'`（`record_detail_page.dart:595-596`）

---

## 4. 主流程

### 4.1 三条产生路径（写入 `Defect`）

| 路径 | 触发 | 产出 | 关键字段 | 证据 |
|---|---|---|---|---|
| A 拍照验收保存 | 验收页「保存记录」 | **1 条聚合缺陷** | `seed:'capture'`、带 `photoPath`、`tags:['拍照记录',…]` | `capture_page.dart:929-953` |
| B 验收转入 | 验收记录「转入问题清单」 | **N 条**（逐条） | `seed:'capture_convert'`、`id:'<captureId>#<idx>'`、**无 photoPath** | `capture_records_controller.dart:296-318` |
| C 图纸打点 | 图纸页长按/点选创建 | 1 条 | `status: draft` | `drawing_viewer_page.dart:858` |

> 路径 A 与 B 的关系问题（同一次拍照留 1+N 条）见 `CAPTURE_FLOW.md` §7-D2。

### 4.2 闭环时序

```
产生(draft)
   │
   ├─ 设计师 → /defects/record/:id →「远程已解决」+必填说明 ────→ done（"设计师远程销项"）
   ├─ 设计师 → 「远程已答复」(+选填说明) ────────────────────→ status 不变，只写 designer*
   ├─ 设计师 → 「需要到现场」(+选填说明) ────────────────────→ status 不变，只写 designer*
   │
   └─ 施工方 → /defects/record/:id →「填写回复」────────────────→ 只写 reply*
                   ├─「仅保存，待复核」────────────────────────→ status 不变
                   └─「提交并销项」───────────────────────────→ done（"整改销项"）
   │
导出报告（清单页右上角）→ 生成四格式 → 归档 ReportRecord
```

**注意：没有任何"撤销 / 重处置 / 删除缺陷"的入口。** 处置后 `_DesignerCard` 只读、按钮区隐藏（`record_detail_page.dart:615-729`）。

---

## 5. 分步功能规格

### S1 清单主页 `/defects`（`defects_page.dart`，1917 行）

**骨架**：AppBar（标题「问题清单」24/w600；右侧导出图标 + `UserSwitcher`，间距 16、右边距 12）→ `AsyncState(defectsProvider)` → `ListView.separated`（padding 12、间距 12）。

列表采用**索引契约**（`:87-111`）：
- `headerCount = 2`（状态分段 + 操作卡）
- 空：`[状态分段, 操作卡, 空态, OfflineBar]`
- 非空：`[状态分段, 操作卡, ...缺陷卡, OfflineBar]`
- 过滤在 build 内完成：`ds.where((d) => filter == null || d.status == filter)`（`:85-86`）

**状态分段**（`_StatusSegmented`，`:1145-1187`）：

| 段 | 过滤 |
|---|---|
| 全部（`null`） | 不筛 |
| 待整改（`draft`） | `d.status == draft` |
| 整改中（`doing`） | `d.status == doing`（**无数据源，见 §3**） |
| 已销项（`done`） | `d.status == done` |
| 已拒绝（`reject`） | `d.status == reject`（**无数据源，见 §3**） |

- 交互：点选切换；**再点已选项回到「全部」**（`:1160`）。
- **无搜索框、无时间筛选、无排序控件**；列表顺序 = `defectsProvider` 返回顺序（页面不做排序）。

**操作卡**（`_ActionCard`，`:1261-1454`）：
- 身份区：头像 + 姓名 + 角色标签（`role` 为空时**兜底写死「设计管理」**，`:1282`）；角色配色：含"业主"红 / 含"咨询|PMO"绿 / 其它蓝。
- 「切换身份」按钮 → `showUserSwitchSheet`（`:1421`）。
- 两个行动按钮（`:1323, 1329`，横向，窄屏 `<340` 转纵向）：
  - 「待设计师处置」→ `/defects/disposal/designer`
  - 「待施工方回复」→ `/defects/disposal/reply`
- **切换身份只影响**：本卡头像/姓名/角色、导出报告的 `reporter`、归档的 `reporter`；**不影响列表数据**。

**缺陷卡**（`_DefectCard`，`:1523-1862`，整卡点击 → `/defects/record/:id`）：
- 标题行：`part` + `StatusPill(status)`
- 字段区（6 行，名称列 56 宽）：

| 标签 | 取值 |
|---|---|
| 问题缺陷 | `d.type` |
| 严重程度 | `d.severity.label`（带色，见 §7-D2） |
| 缺陷位置 | `d.anchor` |
| 记录人 | `d.reporter` |
| 发现时间 | `d.ts` |
| 责任人 | `d.resp` |

- 展示块（4 个中实际存在 3 个）：
  1. **备注块**：**无条件渲染** `d.note`（`:1630-1642`）
  2. **设计师处置块**：`designerAction != null` 时显示（处置标签 + 说明 + 处置人 + 时间）
  3. **整改回复块**：`(reply ?? '').isNotEmpty` 时显示（回复人 + 正文 + 时间，绿底）
  4. **AI 建议块：不存在** —— `Defect.suggestion` 在卡片与详情页**均未渲染**（只在报告里用）
- **卡片无照片缩略图**（纯文本）。
- `StatusPill`：52×22 圆角 6，底色见 §7-D2。

**所有提示文案**：`暂无可导出的缺陷记录`(muted)、`暂无可导出的数据`(muted×2)、`当前平台暂不支持导出，请在 Web 端使用该功能`(muted)、`所选周期内暂无缺陷记录，请调整汇报周期`(muted)、`报告已导出：…（已收录到巡场报告）`(success)、`导出失败：$e`(danger)。
**空态**：`暂无问题`。

### S2 处置与回复页 `/defects/disposal/:kind`（`DisposalReplyPage`，`:989-1067`）

- 仅 2 个 kind：`designer`（默认）/ `reply`。
- 匹配口径（`:1006-1007`）：
  - `designer` → `d.pendingDesignerDisposal`，即 `designerAction == null && status != done`（`models.dart:641-642`）
  - `reply` → `(d.reply ?? '').isEmpty`
- 结构：AppBar（返回 + 居中标题「处置与回复」）→ 本地二段分段控件 → 列表（**复用同一个 `_DefectCard`**）→ 空态 `暂无待设计师处置的问题` / `暂无待施工方回复的问题`。
- **本页无任何写操作按钮**，唯一交互是点卡片进详情页。

### S3 记录详情页 `/defects/record/:id`（`record_detail_page.dart`，1262 行）

> 文件头注释自陈：`/// 记录详情页（静态版）。数据来源：当前巡场清单 mock（按 defectId 取）。待 P3 接真实后端后改为 record 资源。`（`:14-16`）

**数据**：`ref.watch(defectsProvider)` → 按 `id` 线性查找（`:55`）；查不到 → 居中灰字 **`未找到该记录`**（`:56-63`）。

分区（自上而下）：

| # | 卡片 | 内容 | 显隐 |
|---|---|---|---|
| ① | 水印照片卡 `_WatermarkPhoto`（`:384-484`） | **渐变占位块**（色相由 `d.seed` 派生）+ 中央斜向大字水印 + 底部 3 行（时间/GPS·海拔/楼层·部位）+ 右上校验胶囊 | 常显 |
| ② | 缺陷信息卡 `_InfoCard`（`:201-294`） | `part` + StatusPill + 红框 `type · anchor` + 严重程度 + 责任人 | 常显 |
| ③ | 时间轴入口 `_TimelineCard`（`:297-325`） | 「查看同部位时间轴对比」→ `/timeline`，`extra = d.anchor` | 常显 |
| ④ | 参数卡 `_ParamsCard`（`:329-349`） | 拍摄时间 / 海拔 / GPS坐标 / 楼层部位 | 常显 |
| ⑤ | 设计师处置卡 `_DesignerCard`（`:532-781`） | 未处置：3 个按钮；已处置：只读结果 | 依 `designerAction` 分叉 |
| ⑥ | 整改回复卡 `_ReplyCard`（`:972-1120`） | 空：「填写回复」按钮；非空：正文+回复人+时间 | 依 `reply` 是否为空 |
| ⑦ | 底部操作栏 `_RecordActionBar`（`:1217-1258`） | 「仅保存，待复核」+「提交并销项」 | 常显 |

**① 水印照片卡（重要）**：
- **完全不读取 `d.photoPath` / `d.photos`**，永远是渐变占位（注释 `:398` `// 渐变背景（占位真实照片）`；`:382-383` 说明"真实场景应渲染真实照片 + 服务端水印"）。
- **校验胶囊不是校验**：`verified = d.status != DefectStatus.draft`（`:390`）→ 显示「已效验」/「待回网校验」；**未使用 `photoHash` / `watermarkSerial`，无任何哈希比对**。→ §7-D3（触及产品红线"不伪造验证结果"）

**⑤ 设计师处置三动作**（`_actionMeta`，`:543-574`）：

| action | 按钮 | 说明必填 | 写入 |
|---|---|---|---|
| `remoteFix` | 远程已解决（绿） | **必填** | `designerAction/designerNote/designerBy/designerTs` + **`status=done`** + `completion='已完成（设计师远程销项）'` |
| `remoteConfirm` | 远程已答复（红） | 选填 | 同上四项，**不改 status** |
| `onsite`（默认分支） | 需要到现场（橙） | 选填 | 同上四项，**不改 status** |

- 弹窗（`_DesignerActionSheet`）：必填未填 → `请先填写处置说明`（muted，`:914`）；确认按钮 `确认提交`。
- **无二次确认**；**处置后无法撤销或重新处置**。

**⑥ 整改回复**（`_editReply`，`:111-133`）：
- 表单**只有"回复内容"一个字段**（`maxLines:4`）：**没有回复照片上传入口**、**没有回复人输入**（自动取当前用户名）。
- 写入：`reply` / `replyBy` / `replyTs`；**不改 status、不写 completion**。
- 校验：空 → `请先填写整改回复内容`（muted）。
- 模型有 `replyPhotoPath`（`models.dart:480`），本页**从不写**。

**⑦ 底部操作栏**：

| 按钮 | 前置校验 | 写入 | 成功后 |
|---|---|---|---|
| 仅保存，待复核 | 回复非空（`:136-140`） | `reply/replyBy/replyTs`；**status 不变** | `updateDefect` → `invalidate(defectsProvider)` → Toast `已保存更新`(success)；**不 pop** |
| 提交并销项 | 同上 | 上述 + **`status=done`** + `completion='已完成（整改销项）'` | 同上；**不 pop** |

- 「待复核」**只是按钮文案，代码层没有任何对应状态位**（不写任何字段）。
- `_busy` 期间按钮与回复入口全禁用；**`updateDefect` 无 try/catch**，失败无提示、无回滚（`:68`）。
- **本页从不写 `closeNote`**（模型 `models.dart:483` 存在）。

**详情页不展示的模型字段**：`note`（备注）、`category`、`tags`、`suggestion`、`photos`、`closeNote`、`photoHash`、`watermarkSerial`、`importance`、`building`、`reporter`、CAD 坐标。
→ 其中 **`note` 在清单卡显示、在详情页不显示**，信息不一致（§7-D7）。

### S4 时间轴对比 `/timeline`（`timeline_compare_page.dart`，809+ 行）

- 入口：详情页 `_TimelineCard`，`extra = d.anchor`；页面默认 anchor 写死 `'西楼1F-左病房翼'`（`:26`）。
- 数据：`repositoryProvider.getTimeline(anchor)`（`:42`），dev 走 Mock。
- 交互：缩略图选择左/右两张（默认自动选首、末）→ 滑块对比（上层左图按 `_slider` 裁切，`_LeftPhotoClipper :727-740`）+ 「交换照片」→ 底部两块时点摘要（date + caption）。
- 时点标签：`before→前期` / `mid→中期` / `after→后期`（`:434-439`），由数据层按索引重标。
- **照片是真图**（`Image.asset` 或读本地文件 `Image.memory`，`:566-609`），**不是 CustomPainter 占位**（文件头注释 `:15` 已过时；`FEATURE_INVENTORY.md` 原有描述同步订正）。

### S5 导出报告（入口在清单页，详规属 M5）

**入口**：AppBar 右侧 `fileExportLine` → `_export`（`:119-162`）。
**数据源（关键）**：`defectsProvider` **全集**，**不受状态分段过滤影响**（对比 body 内 `:85-86` 的 `list`）；仅在弹层内按日期范围二次过滤（`_filterByPeriod`，`:199-211`，取 `ts` 前 10 位比较，**解析失败的记录一律纳入**）。

**弹层**（`_showExportSheet`，`:218-376`）：标题「导出现场工作汇报」→ 描述段 → 日期范围卡（`firstDate` 写死 `2024-01-01`）→ 过滤提示「已按周期过滤：全部 N 条中筛出 M 条」→ 导出小结（选填，手填，`:534-575`）→ 4 个格式卡（Excel/PDF/Word/网页链接）→「下载 HTML 报告」→ 平台降级文案。

**`_runExport`**（`:733-797`）：
1. 平台门控 → 2. 空数据拦截 → 3. `weeklyReportProvider.copyWithDefects(filtered, patrolSummary, roomScans, checks)` → 4. 收集照片字节（`report.photos[].file` 走 `rootBundle`；`report.defects[].photoPath` 走 LocalStorage）→ 5. 生成（xlsx/pdf/docx/html）→ 6. `exportReportFile` → 7. `_archiveReport` → 8. Snack「报告已导出：…（已收录到巡场报告）」/「报告已保存：…（已收录到巡场报告）」。

**归档**（`_archiveReport`，`:804-844`）：`ReportRecordStore.upsert(projectId, ReportRecord{ id:'rep_$now', …, formats:[格式], defectCount/openCount/doneCount/urgentCount, note: patrolSummary })` → `refreshReportRecords`。
- 存储键 `report_records_v1_<projectId>`；`upsert` 按 **`title + period`** 合并，同次汇报多格式只留一张卡并合并 `formats`。
- **只存元数据，正文不入库**；归档整体 `try/catch` 静默（注释：失败不阻断导出）。

---

## 6. 数据契约

### 6.1 `Defect` 字段（`models.dart:407-719`）

| 字段 | 类型 | 含义 | 谁写 |
|---|---|---|---|
| `id` | String | 唯一 id（`cap_<ts>` / `<captureId>#<idx>` / 种子 id） | 各产生路径 |
| `part` | String | 部位（卡片标题） | 产生路径 |
| `type` | String | 缺陷类型（卡片「问题缺陷」） | 产生路径 |
| `category` | DefectCategory | 专业分类 7 类 | **恒 `other`**（两条产生路径都写死） |
| `severity` | DefectSeverity | 严重程度 | 产生路径 |
| `status` | DefectStatus | 状态 | 见 §3 |
| `anchor` | String | 图纸锚点 | 产生路径 |
| `floor` | String | 楼层 | 产生路径 |
| `ts` | String | 发现时间 | 产生路径 |
| `gps` / `alt` | String | GPS / 海拔 | 仅路径 A 写（路径 B/C 空） |
| `resp` | String | 责任人 | 路径 A 写 `待指派` |
| `respUnit` | String? | 责任单位 | **无写入路径** |
| `reporter` | String | 记录人 | 路径 A=当前用户；路径 B 写死 `验收记录` |
| `tags` | List | 标签 | 路径 A `['拍照记录',…]`；路径 B `['验收转工单',…]` |
| `note` | String | 备注（清单卡显示） | 产生路径 |
| `seed` | String | 来源标记 | `capture` / `capture_convert` |
| `drawingKey` / `worldX` / `worldY` | — | 图纸回溯坐标 | 产生路径 |
| `photoPath` | String? | **报告现场照片唯一来源** | 仅路径 A 写（路径 B 未写 → CAPTURE D1） |
| `photos` | List | 照片列表 | 路径 B 写，**无消费方** |
| `photoHash` / `watermarkSerial` | String? | 防篡改凭证 | **无写入路径**（水印 burned 进图片，字段未落） |
| `importance` | DefectImportance? | 重要等级 | **无写入路径**（靠 `effectiveImportance` 推导） |
| `building` | String? | 楼栋分组 | **无写入路径** |
| `suggestion` | String? | AI 整改建议 | 路径 A 写；**清单/详情页都不显示，仅报告用** |
| `sourceCaptureId` | String? | 来源验收记录 id | 路径 B 写，**无读取方**（CAPTURE D12） |
| `reply` / `replyBy` / `replyTs` | — | 整改回复 | 详情页 `_editReply` / 底部栏 |
| `replyPhotoPath` | String? | 回复照片 | **无写入路径**（详情页无上传入口） |
| `closeNote` | String? | 未闭合说明 | **无写入路径** |
| `completion` | String? | 完成说明 | 两处销项写死文案 |
| `designerAction` / `designerNote` / `designerBy` / `designerTs` | — | 设计师处置四件套 | 详情页 `_DesignerCard` |

**几乎一半字段没有写入路径**——这是"模型先行、功能未跟上"的典型痕迹。

### 6.2 枚举与派生 getter（跨页/报告共用口径）

| 名称 | 行号 | 口径 |
|---|---|---|
| `DefectStatus.label/color/soft` | `models.dart:11-48` | 待整改/整改中/已销项/已拒绝 |
| `DefectCategory.label` | `:63-80` | 建筑/结构/装饰/给排水/暖通/电气/其他 |
| `DefectImportance.label` | `:99-110` | 重要紧急/重要不紧急/紧急不重要/普通 |
| `DefectSeverity.label/action` | `:117-…` | 严重/较重/一般/轻微 → 停工上报/限期整改/即查即改/常规观察 |
| `effectiveImportance` | `:628-635` | 显式重要性优先，否则由 severity 推导（红→重要紧急、橙→重要不紧急、黄→紧急不重要、绿→普通）。**报告排序与统计的基准** |
| `closed` | `:638` | `status == done` |
| `pendingDesignerDisposal` | `:641-642` | `designerAction == null && status != done`（处置页 `designer` 筛选口径） |
| `designerActionLabel` | `:645-650` | remoteFix→远程已解决；remoteConfirm→远程已答复；onsite→需到场；其它空串 |
| `buildingOrEmpty` | `:709` | 空则报告端归「其他」 |
| `hasCadCoord` / `coordText` | `:712-718` | 三项坐标齐备才输出 `X=… Y=…`（1 位小数） |

> `copyWith`（`:653-706`）**只支持** `status/resp/building/reply*/closeNote/completion/suggestion/designer*` 的局部更新——即处置与回复链路；其余字段不可改。

### 6.3 存储与合并算法（`mock_repository.dart`）

- 落库键：`added_defects_v1`（`:22`）；内存 `_added: List<(Defect, bool is7)>`（`:19`）。
- 持久化结构：`[{is7: bool, defect: {...}}]`（`:45-56`）。
- **合并去重**（`getDefects`，`:82-97`）：
  ```
  byId = {每个种子: defect}
  再遍历 _added 中 is7 匹配当前项目的 → byId[id] = 该条   // 新增/更新覆盖种子
  顺序 = 种子顺序 + 新增追加（无显式排序）
  ```
- **项目隔离**：靠 `is7` 布尔标记（非 projectId）。`defectsProvider`（`providers.dart:302-308`）通过副作用 `repo.currentIs7 = is7` 把当前项目灌进 mock。
- `updateDefect`（`:124-134`）：**只在 `_added` 里按 id 查**（不查种子）→ 种子缺陷的**首次更新会被当作新增追加**；`is7` 取的是**更新时刻**的项目标记。
- `_restoreAdded` / `_persistAdded` 异常**静默吞掉**（`:40-42, 53-55`）。
- 假延迟 350ms（`:58-59`）。

### 6.4 上游接口

| 方法 | 签名 | 实现状态 |
|---|---|---|
| `getDefects({DefectStatus? status})` | `repository.dart:12` | Mock ✅ / Remote ❌ `UnimplementedError` |
| `addDefect(Defect)` | `:14` | Mock ✅ / Remote ❌ |
| `updateDefect(Defect)` | `:17` | Mock ✅ / Remote ❌ |
| `getTimeline(String anchor)` | `:18` | Mock ✅ / Remote ❌ |

`Repository` 抽象见 `repository.dart:5-24`；`repositoryProvider = Env.isProd ? RemoteRepository() : MockRepository()`（`providers.dart:26-28`）。

---

## 7. 偏离清单（按严重度）

| # | 严重度 | 问题 | 证据 | 影响 | 建议 |
|---|---|---|---|---|---|
| D1 | 🔴 高 | **`doing` / `reject` 两个状态无任何写入路径**，只能来自 mock 种子 | 全库写入点仅 `capture_page.dart:937`、`capture_records_controller.dart:302`、`drawing_viewer_page.dart:858` 全为 `draft`；`record_detail_page.dart:146-147, 595-596` 写 `done`；`DefectStatus.doing/reject` 仅出现在 `mock_data.dart:584,608,1044,1112,1135` | 用户无法表达"已开始整改"或"拒绝整改"；报告「整改中」统计永远是种子数据 | 明确产品语义：是否需要"开始整改/拒绝"动作 |
| D2 | 🔴 高 | **`Color(0xFF4444)` 缺两位十六进制**（应为 `0xFFFF4444`），该值 alpha=0x00 → **完全透明** | `defects_page.dart:1544`（严重程度文字色）与 `:1885`（「待整改」胶囊底色） | 「严重」严重程度值**看不见**；「待整改」胶囊变透明底 + 白字 → 视觉上消失 | 改 `0xFFFF4444` |
| D3 | 🔴 高 | **"已效验"胶囊是状态推导，不是校验**：`verified = status != draft`，未用 `photoHash`/`watermarkSerial`、无哈希比对 | `record_detail_page.dart:390, 436-447` | 显示「已效验」但系统实际未校验任何东西 —— **触及红线"不伪造验证结果"** | 接真实哈希比对，或改文案为"已提交/未提交" |
| D4 | 🟠 中 | **水印照片卡永远是渐变占位**，不读 `d.photoPath`/`d.photos` | `record_detail_page.dart:384-484`（注释 `:382-383, 398`） | 详情页看不到现场照片（清单卡也无缩略图）；照片**只在报告里可见**（转入条的报告照片已于 2026-09-18 修复，见 `CAPTURE_DEFECT_MAPPING.md` §4） | 接真实照片 |
| D5 | 🟠 中 | **详情页不显示备注 `note`**，但清单卡无条件显示 | 详情页未渲染 `note` vs `defects_page.dart:1630-1642` | 同一记录两处信息不一致（验收描述只在清单页可见） | 详情页补备注块 |
| D6 | 🟠 中 | **回复照片入口缺失**：模型有 `replyPhotoPath`，详情页只有单字段文本框 | `record_detail_page.dart:1123-1214` vs `models.dart:480` | 报告「整改后照片」永远空 → `report_builder.dart:541-547` 显示占位 | 补照片上传 |
| D7 | 🟠 中 | **`updateDefect` 只查 `_added` 不查种子**；`is7` 取更新时刻的标记 | `mock_repository.dart:124-134` | 种子缺陷首次更新被当新增追加；跨项目场景可能归属错项目 | 改为在全量集合中查找；用 projectId 而非布尔 |
| D8 | 🟠 中 | **`updateDefect` 无错误处理**：无 try/catch、无失败提示、无回滚 | `record_detail_page.dart:68` | 写入失败时用户以为已保存 | 加 try/catch + 失败 Toast |
| D9 | 🟠 中 | **导出报告不受状态分段影响**（用全集而非当前筛选） | `defects_page.dart:121-124` vs `:85-86` | 用户选了「已销项」再导出，仍导出全部；易误判 | 明确是否应跟随筛选 |
| D10 | 🟠 中 | **处置与回复页无写操作**，只是"筛选后的清单"，所有操作都要再进详情页 | `defects_page.dart:989-1067` | 与「待设计师处置/待施工方回复」的按钮语义不符，多一次跳转 | 或在页内直接处置 |
| D11 | 🟡 低 | **`closeNote` 有模型无写入**：无"未闭合说明"入口 | `models.dart:483` | 「已销项」缺说明；报告无未闭合原因 | 需要则补入口 |
| D12 | 🟡 低 | **`sourceCaptureId` 只写不读**；`photos` 无消费方；`photoHash`/`watermarkSerial`/`importance`/`building`/`respUnit`/`replyPhotoPath` 均无写入路径 | 见 §6.1 | 模型与实现脱节，字段名存实亡 | 逐字段决定补实现或删 |
| D13 | 🟡 低 | **`category` 恒为 `other`**：两条产生路径都写死 | `capture_page.dart:935`、`capture_records_controller.dart:300` | 专业分类筛选/统计无法成立（报告也不按 category 分组） | 接 AI 分类或人工选择 |
| D14 | 🟡 低 | **`defectSpecialFilterProvider` 定义后无人使用** | `providers.dart:331` | 死代码 | 删除或接线 |
| D15 | 🟡 低 | **「待复核」无状态位**：只是按钮文案 | `record_detail_page.dart:1239` | "待复核"语义无处查询/统计 | 需状态位则补 |
| D16 | 🟡 低 | 「切换身份」是扮演式开关，**不影响任何权限与数据可见性** | `user_switch_sheet.dart:27`；`defectsProvider` 与用户无关 | 与后端权限设计（`BACKEND_ARCHITECTURE` §6）冲突，需要时降级为管理员功能 | 已在后端方案中列为改造项 |
| D17 | 🟡 低 | 详情页严重程度**恒用橙色**，未按 severity 变色 | `record_detail_page.dart:262-266`（`severity.color` 未用） | 与清单页不一致 | 统一 |
| D18 | 🟡 低 | 角色为空时**兜底写死「设计管理」** | `defects_page.dart:1282` | 展示不实 | 兜底为「未设置」 |
| D19 | 🟡 低 | `_StatusSegmented` 注释称选中色品牌蓝 `#0395FF`，实现为 `#202224` | `defects_page.dart:1143-1144` vs `:1216` | 注释误导 | 修注释 |
| D20 | 🟡 低 | 时间轴默认 anchor 写死 `'西楼1F-左病房翼'`；mock 兜底也写死同一 anchor | `timeline_compare_page.dart:26`、`mock_repository.dart:205` | 无数据时展示无关部位 | 改为空态 |
| D21 | 🟡 低 | 时间轴页头注释称"照片：CustomPainter 模拟"，实际是真图 | `timeline_compare_page.dart:15` vs `:566-609` | 误导（`FEATURE_INVENTORY` 已同步订正） | 修注释 |
| D22 | 🟡 低 | 导出弹窗日期下界写死 `2024-01-01`；项目名兜底写死 `建筑验收项目` | `defects_page.dart:269, 135` | — | 按项目起始日期 |
| D23 | 🟡 低 | `_filterByPeriod` 对**时间戳无法解析的记录一律纳入** | `defects_page.dart:207` | 脏数据进入报告 | 显式排除或提示 |

---

## 8. 有意设计（**不要当 bug 盲改**）

1. **状态分段点选可反选**（再点回到「全部」）——省一个"全部"段的点击路径（`defects_page.dart:1160`）。
2. **导出用全集而非当前筛选**——报告是"对外交付"，不应受浏览筛选影响（`:121-124`）。
3. **归档按 `title + period` 合并**——同一次汇报导出多种格式只留一张卡并合并 `formats`（`report_record_store.dart:32-45`）。
4. **归档失败不阻断导出**——报告正文已交付，元数据留痕可事后补（`defects_page.dart:799-802, 841-843`）。
5. **照片缺失只影响配图**——报告端显示"照片未加载"占位，不阻断导出（`:173, 184`）。
6. **`upsert` 只存元数据**——报告正文字节不入本地归档（`report_record.dart:3-5`）。
7. **处置后卡片只读**——避免误改已提交的处置结论（`record_detail_page.dart:615-729`）。
8. **详情页按 id 线性查找**——数据量小，简单优先（`:55`）。

---

## 9. 溯源索引

| 文件 | 职责 |
|---|---|
| `lib/features/defects/defects_page.dart` | 清单主页 + 处置与回复页 + 导出弹窗/生成/归档（1917 行） |
| `lib/features/defects/record_detail_page.dart` | 记录详情：水印占位卡 / 设计师处置 / 整改回复 / 销项（1262 行） |
| `lib/features/defects/timeline_compare_page.dart` | 同部位多时点照片滑块对比 |
| `lib/features/defects/report_content.dart` | 报告中间层：章节顺序、空板块剔除、`ReportStats` |
| `lib/features/defects/report_builder.dart` / `report_pdf` / `report_docx` / `report_xlsx` | 四端渲染（M5 详规另写） |
| `lib/core/utils/defect_suggestions.dart` | 本地建议库 **35 条**（**不映射 `DefectCategory`**）；`suggestionFor` 按 `_rules` 声明顺序做**子串包含**匹配，首个命中即返回，未命中给通用兜底（`:233-241`） |
| `lib/core/di/providers.dart` | `defectsProvider`(`:302-308`)、`refreshDefects`(`:311-313`)、`defectFilterProvider`(`:316`)、`defectSpecialFilterProvider`(`:331`，死) |
| `lib/data/repository/mock_repository.dart` | 合并去重(`:82-97`)、新增(`:117-122`)、更新(`:124-134`)、时间轴构造(`:137-206`)、`added_defects_v1` |
| `lib/data/repository/remote_repository.dart` | prod 路径 **4 个方法全 `UnimplementedError`**（`:76-90`） |
| `lib/data/models.dart` | `Defect`(`:407-719`)、四个枚举与扩展(`:8-135`)、派生 getter(`:628-718`) |
| `lib/data/mock/mock_data.dart` | 种子 `defects`(`:530`)、`dy7Defects`(`:1015`)、`timeline`(仅 1 个 key，`:676-703`) |
| `lib/core/storage/report_record_store.dart` | 报告归档 `report_records_v1_<projectId>` |

---

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-18 | 首版：从代码逐文件核实建立（基线 `5361996` + 未提交改动）；输出 23 条偏离、8 条有意设计；订正 FEATURE_INVENTORY 中"时间轴照片为 CustomPainter 占位"的过时描述 |
