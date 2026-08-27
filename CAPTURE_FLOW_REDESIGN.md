# 拍照记录流程重构方案（拍照 → 照片 → AI 分析 → 语音描述 → 保存 → 记录列表/详情）

> 本文档仅做方案设计，不涉及代码改动。
> 目标：把"拍照记录"从「自动识别即自动暂存」改为「用户分步主动操作」的清晰闭环，新增语音描述、独立拍照记录列表页、记录详情弹层，并与图纸关联。
> **本期范围**：专注拍照记录相关（拍照、AI 分析按钮化、语音描述、保存、记录列表、记录详情）。**缺陷工单入库（"多一层处理"）本期不实现，仅预留数据结构。**

---

## 0. 结论速览（已拍板）

| 议题 | 结论 |
|------|------|
| AI 分析触发 | **按钮触发**（不再是自动）；异步机制已存在，仅迁移触发点 |
| loading | **需要**，页面内 overlay（保留现有 `_scanning`），不阻塞 Dialog |
| 照片位置 | **图纸下方独立卡片**，不再叠在图纸 Stack |
| 问题描述 | 新增 `note` 字段，手打 / 语音（语音**追加**到 note） |
| 保存时机 | **显式「保存记录」按钮**，不再自动暂存 |
| 入库？ | **不入库**；拍照记录与缺陷工单解耦 |
| 记录列表 | **内嵌拍照页（方案 A）**：操作区下方直接展示「本图纸拍照记录」列表，不跳转独立页 |
| 记录与图纸 | **按图纸隔离**：切图纸 = 切对应的拍照记录列表（按 `drawingKey` 维度，列表随 `/capture` 携带的图纸自动切换） |
| 详情页 | **底部弹层** `showModalBottomSheet`（非独立路由） |
| 拍照/相册按钮 | 保持**单个按钮**（现有平台分流：移动端相机/相册原生选择，Web/PC 文件选择） |
| "多一层处理" | 详情里选某条 AI 缺陷补信息后转工单——**本期不实现**，仅预留 `defect.status` 状态位 |

---

## 1. 现状基线（改造前）

`capture_page.dart` 当前痛点：

1. **AI 分析自动触发**：`_runScan` 拍照后自动调 `VisionService.recognizeDefects`。
2. **暂存自动**：`_runScan` 结束直接 `_persistResult`（写 `LocalStorage`），用户无选择权。
3. **照片叠图纸**：`_buildResultPanel` 把预览叠在图纸 `Stack`。
4. **无问题描述字段**：entry 仅 `ts/anchor/floor/count/defects/photo`。
5. **暂存无详情页**：底部列表只显示一行摘要。
6. **记录无独立页面**：暂存仅存在于 `/capture` 底部，无法跨图纸隔离、无列表页。

**已具备能力（可直接复用）**：
- AI 分析本就是异步网络调用（有 `_scanning` overlay、`TimeoutException`、Mock 回放 `vlPreset`）。
- 语音：`VoiceInputSheet` / `VoiceInputButton` + `SpeechRecognizer`（设备离线中文 ASR，无需后端）。
- 本地存储：`LocalStorage`（移动端 Hive / Web localStorage）、`writeFile/readFile/deleteFile`（照片落盘已可用）。
- 导航：GoRouter + ShellRoute，底部 4 Tab（项目/图纸/巡场/工单）+ 中间"验收"按钮（进 `/capture`）。

---

## 2. 产品功能方案（Product Perspective）

### 2.1 主流程（用户主控）

```
① 选点（图纸选部位/楼层，带 drawingKey/worldX/Y）
   ↓
② 拍照 / 相册（单按钮，平台分流） → 水印后 _shotPhoto
   ↓
③ 照片显示图纸下方预览（可重拍/重选）
   ↓
④ 点「AI 分析」→ overlay loading → 异步 VisionService → 结果显照片下方
   ↓
⑤ 填「问题描述」（手打 / 语音追加；可空）
   ↓
⑥ 点「保存记录」→ 才写入暂存（LocalStorage，带 drawingKey 维度）
   ↓
⑦ 页内下方「本图纸拍照记录」列表（按 drawingKey 自动筛选，随当前图纸切换）
   ↓
⑧ 点列表条目 → 底部弹层详情（照片+AI结果+描述+部位楼层时间）
```

### 2.2 与图纸关联（记录隔离维度）

- 每条记录存 `drawingKey`（来自选点 `widget.args.drawingKey`）。
- 拍照页（`/capture`）本身从图纸页带 `drawingKey` 进入，页内记录列表**只显示该图纸**的记录；在图纸页切到另一张图再进拍照页，列表随之切换（无需独立页跳转）。
- 存储上所有图纸记录放同一 `LocalStorage` 文档（如 `capture_records`），列表按 `drawingKey` 过滤；或每图纸一个 key（`capture_records_<drawingKey>`）。**推荐前者**（单文档、过滤简单，记录量不大）。

### 2.3 字段与数据结构（暂存 entry 扩展）

```jsonc
{
  "id": "<unique>",                 // 记录唯一 id（用于详情/删除定位）
  "drawingKey": "b3-struct",        // ★新增：所属图纸，列表筛选维度
  "ts": "2026-08-27 14:03:09",      // 保存时间
  "anchor": "B 区 3 层 柱 02",       // 部位（选点）
  "floor": "B3",                     // 楼层
  "worldX": 123.4, "worldY": 56.7,   // 图纸坐标（可选，详情展示）
  "count": 2,                        // AI 识别缺陷数
  "defects": [                       // AI 结果（VlDefect.toJson + 预留 status）
    {
      "name": "钢筋间距不足", "severity": "orange", "conf": 0.83, "desc": "…",
      "status": "pending"            // ★预留：pending=未转工单 / converted=已转（本期恒 pending）
    }
  ],
  "photo": "photos/<ts>.jpg",        // 移动端落盘相对路径；Web 无
  "note": "现场柱筋间距明显偏小…"      // ★新增：问题描述（手打/语音追加），可空
}
```

- `note` 可空；空时不强校验，允许只存照片+AI结果。
- 删除时同步 `LocalStorage.deleteFile(photo)`（已实现逻辑保留）。
- **转工单预留**：`defects[].status` 本期恒 `pending`，详情页不展示"转工单"按钮（后续实现时再加，从 pending → converted 并写缺陷库）。

### 2.4 边界与降级

- AI 失败（超时/鉴权/网络）：保留 `_scanError` 文案，提示可重试；**不落暂存**（无结果可存，用户仍可仅保存照片+描述——需允许"未分析也保存"）。
- Mock 模式：仍 `vlPreset(replayReal:true)`，但**不再自动暂存**，需点「保存记录」才落盘。
- Web 无照片落盘：`photo` 为空，详情/列表缩略图显示占位。
- 未分析直接保存：允许，列表/详情显示"未分析"标记。

---

## 3. UI 布局设计（UI Perspective）

### 3.1 拍照页（`/capture`）整体结构（自上而下）

```
┌─────────────────────────────────────────┐
│ AppBar: 拍照记录                 [Mock 开关]│
├─────────────────────────────────────────┤
│ ① 锚点信息条：部位 · 楼层 · 图纸名        │  (_buildAnchorBar，保留)
│ ② 图纸区（纯画布，不含照片）              │  (_buildDrawingStage，移除照片叠加)
│ ③ 照片预览区（图纸下方独立卡片）          │  ★新增 _buildPhotoPanel
│    [水印照片 Image.memory]  重拍/重选      │
│ ④ AI 分析按钮区                          │  ★新增 _buildAnalyzeBar
│    [📷 拍照/选择]   [🤖 AI 分析](未拍照置灰) │
│ ⑤ AI 结果区（照片下方，仅分析后显示）     │  (_buildDefectSection)
│ ⑥ 问题描述输入区                         │  ★新增 _buildNoteField
│    [文本框……] [🎤 语音]                  │
│ ⑦ 保存记录按钮（主操作）                 │  ★改造：显式保存（未拍照禁用）
├─────────────────────────────────────────┤
│ ⑧ 本图纸拍照记录列表（页内直接展示）      │  ★升级现有 _buildStoredResults
│    [缩略图] 部位·楼层  时间  识别N处/未分析│  （按 drawingKey 过滤，点开详情弹层）
│    ··· 空态：本图纸暂无拍照记录 ···        │
└─────────────────────────────────────────┘
```
（记录列表**直接内嵌本页**⑧区，不跳转独立页；随进入 `/capture` 携带的 `drawingKey` 自动筛选。）

### 3.2 拍照页内记录列表区（方案 A，非独立页）

- 位置：拍照页操作区（①~⑦）下方，即第 ⑧ 区，**与原底部暂存列表同位置**，但升级为：
  - 按 `drawingKey` 过滤，只显示当前图纸记录；切图纸进 `/capture` 即自动切换。
  - 顶部小标题"本图纸拍照记录（N）"。
- 列表项（复用并增强现有 `_buildStoredResultTile`）：缩略图 + 部位·楼层 + 时间 + "识别 N 处 / 未分析" + "含描述"标记。
- 点条目 → 底部弹层详情（见 3.3）。
- 空态：灰字"本图纸暂无拍照记录"。

### 3.3 记录详情（底部弹层，方案 ③）

`showModalBottomSheet` 展开式 `StoredDetailSheet(entry)`：
- 顶部拖拽条 + 部位·楼层·时间 + 关闭。
- 照片大图（`photo` → `LocalStorage.readFile` → `Image.memory`；Web 占位）。
- AI 识别结果：缺陷卡片列表（复用 `_buildDefectCard` 只读版）；未分析显示占位。
- 问题描述：`note` 文本（空→"无描述"灰字）。
- 底部：`删除`（复用确认弹窗 + `_deleteStoredResult`）。
- **本期不含"转工单"按钮**（预留，`defects[].status` 后续驱动）。

### 3.4 loading 与按钮态

- AI 分析：保留 `_scanning` 页面内 overlay（轻量、不遮照片）；期间禁用 AI 分析与保存按钮防竞态。
- 拍照按钮：单按钮，内部按平台分流（移动端原生相机/相册选择；Web/PC 文件选择），与现状一致。
- 语音：文本框右侧 `VoiceInputButton` → `VoiceInputSheet`，`onResult` **追加**到 `note` 的 `TextEditingController`（可继续手打编辑）。

---

## 4. 导航落地（GoRouter 改动）

- **不新增任何路由**。拍照记录列表直接内嵌 `/capture` 页（第 ⑧ 区），随进入拍照页携带的 `drawingKey` 自动按图纸筛选。
- `app.dart` **无需改动**（保留现有 `/capture` 路由与 ShellRoute 底部导航）。
- 底部 Tab **不变**（不新增第 5 Tab，符合方案 A：列表就在拍照页内）。

---

## 5. 与现有代码映射（改造清单，供后续编码）

| 现有元素 | 处理方式 |
|----------|----------|
| `_buildResultPanel`（照片叠图纸 Stack） | 拆分：照片移到新 `_buildPhotoPanel`（图纸下方）；图纸区保持纯画布 |
| `_runScan`（自动分析 + 自动 `_persistResult`） | 拆为：① 纯分析（异步、仅出结果，去掉自动暂存）；② 暂存逻辑移到「保存记录」按钮 |
| `_scanning` / `_buildScanningOverlay` | 保留，AI 分析 loading |
| 底部"暂存列表"（`_buildStoredResults`） | **升级为页内记录列表区**：按 `drawingKey` 过滤、加小标题、空态文案；条目点击 → 详情弹层（不再跳转独立页） |
| `_persistResult` / `_deleteStoredResult` | 保留，仅调用时机变化（按钮触发）；entry 新增 `id/drawingKey/worldX/Y/note`；删除仍清 `photo`；恢复/过滤按 `drawingKey` |
| `VoiceInputSheet` / `VoiceInputButton` | 复用，挂 `_buildNoteField` 语音按钮，结果追加 |
| `LocalStorage` | 复用；记录文档建议统一为 `capture_records`（多图纸存一文档，列表按 `drawingKey` 过滤），替代原 `_storageKey` |
| 新：`StoredDetailSheet` | 底部弹层详情（照片+AI+描述+删除），由列表条目点击触发 |
| `app.dart` | **无需改动**（列表内嵌拍照页，不新增路由） |
| 转工单 | **不实现**；仅 `defects[].status` 字段预留（恒 `pending`） |

---

## 6. 待确认（已闭合，记录备查）

- ~~「保存记录」是否入库~~ → **不入库**，拍照记录独立。
- ~~拍照/相册按钮~~ → 单按钮，现状即为平台分流。
- ~~详情页形式~~ → 底部弹层。
- ~~语音结果~~ → 追加到 note。
- ~~记录列表入口~~ → 方案 A（内嵌拍照页，不跳转独立页），并与图纸关联（按 drawingKey 筛选）。
- ~~多一层处理（转工单）~~ → 本期不实现，仅预留 status 字段。
